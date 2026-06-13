import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_permission_service.dart';
import '../services/attendance_service.dart';
import '../services/cloud_face_service.dart';
import '../services/firebase_auth_service.dart';
import '../theme/app_theme.dart';
import 'cloud_mark_attendance_screen.dart';
import 'cloud_register_face_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService();

  final FirebaseAuthService _authService = FirebaseAuthService();
  final ScrollController _scrollController = ScrollController();
  bool _isEnrolled = false;
  bool _isCheckedIn = false;
  bool _isLoading = true;
  bool _showSearchIcon = false;
  String _historyFilter = 'all'; // 'all', 'check-in', 'check-out'
  List<Map<String, dynamic>> _historyRecords = [];
  bool _isLoadingHistory = false;

  /// From Firestore `users/{uid}.faceImageUrl` after registration upload.
  String? _faceImageUrl;

  static const double _avatarSize = 88;

  // Eligibility State
  bool _isCheckingEligibility = true;
  bool _canCheckInAction = false;
  bool _canCheckOutAction = false;
  String? _eligibilityMessage;

  /// College schedule from Firebase (`startTime`/`endTime` as int hour or `"HH:mm"` 24h string).
  int? _collegeStartHour;
  int? _collegeStartMinute;
  int? _collegeEndHour;
  int? _collegeEndMinute;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load enrollment status first (critical for UI)
    _checkEnrollmentStatus();
    // Load history separately (non-blocking, can show loading state)
    _loadHistoryRecords();
    _loadCollegeSchedule();
    // Check eligibility logic (Time & Location)
    _checkEligibility();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 60;
    if (shouldShow != _showSearchIcon) {
      setState(() {
        _showSearchIcon = shouldShow;
      });
    }
  }

  Future<void> _checkEnrollmentStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        // Run parallel operations for faster loading
        final results = await Future.wait([
          // Check Firestore directly for face registration
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          // Check current check-in status
          _attendanceService.isCurrentlyCheckedIn(),
        ]);

        final userDoc = results[0] as DocumentSnapshot;
        final isCheckedIn = results[1] as bool;

        bool hasRegistration = false;
        String? faceUrl;
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>?;
          hasRegistration = data?['faceRegistered'] ?? false;
          faceUrl = data?['faceImageUrl'] as String?;
        }

        if (mounted) {
          setState(() {
            _isEnrolled = hasRegistration;
            _faceImageUrl = hasRegistration ? faceUrl : null;
            _isCheckedIn = isCheckedIn;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isEnrolled = false;
          _faceImageUrl = null;
          _isCheckedIn = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEnrolled = false;
          _faceImageUrl = null;
          _isCheckedIn = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadHistoryRecords() async {
    if (_isLoadingHistory) return; // Prevent multiple simultaneous loads

    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final allRecords = await _attendanceService.getAttendanceHistory();
      final filterValue = _historyFilter == 'check-in'
          ? 'check_in'
          : _historyFilter == 'check-out'
          ? 'check_out'
          : _historyFilter;

      final filtered = _historyFilter == 'all'
          ? allRecords
          : allRecords.where((r) => r['type'] == filterValue).toList();

      if (mounted) {
        setState(() {
          _historyRecords = filtered;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _handleRefresh() async {
    await Future.wait([
      _checkEnrollmentStatus(),
      _loadHistoryRecords(),
      _loadCollegeSchedule(),
      _checkEligibility(),
    ]);
  }

  Future<void> _loadCollegeSchedule() async {
    try {
      final details = await _attendanceService.getCollegeDetails();
      if (!mounted) return;
      setState(() {
        if (details != null) {
          _collegeStartHour = details['startHour'] as int?;
          _collegeStartMinute = details['startMinute'] as int? ?? 0;
          _collegeEndHour = details['endHour'] as int?;
          _collegeEndMinute = details['endMinute'] as int? ?? 0;
        } else {
          _collegeStartHour = null;
          _collegeStartMinute = null;
          _collegeEndHour = null;
          _collegeEndMinute = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _collegeStartHour = null;
          _collegeStartMinute = null;
          _collegeEndHour = null;
          _collegeEndMinute = null;
        });
      }
    }
  }

  /// Formats 24h clock as 12h with minutes, e.g. `9:00 AM`, `2:30 PM`.
  String _formatCollegeTime(int hour24, int minute) {
    final h = hour24.clamp(0, 23);
    final m = minute.clamp(0, 59);
    final period = h >= 12 ? 'PM' : 'AM';
    final displayH = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    return '$displayH:$mm $period';
  }

  Future<void> _checkEligibility() async {
    if (!mounted) return;

    setState(() {
      _isCheckingEligibility = true;
      _eligibilityMessage = null;
    });

    try {
      final isCheckInTimeValid = await _attendanceService.isCheckInAllowed();
      final isCheckOutTimeValid = await _attendanceService.isCheckOutAllowed();

      final geofenceResult = await _attendanceService.validateGeofence();
      final isLocationValid = geofenceResult['valid'] == true;
      final canCheckIn = isLocationValid && isCheckInTimeValid && !_isCheckedIn;
      final canCheckOut = isLocationValid && isCheckOutTimeValid;

      if (mounted) {
        setState(() {
          _canCheckInAction = canCheckIn;
          _canCheckOutAction = canCheckOut;
          _eligibilityMessage = _eligibilityMessageForActions(
            isLocationValid: isLocationValid,
            locationMessage: geofenceResult['message']?.toString(),
            isCheckInTimeValid: isCheckInTimeValid,
            isCheckOutTimeValid: isCheckOutTimeValid,
          );
          _isCheckingEligibility = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _canCheckInAction = false;
          _canCheckOutAction = false;
          _eligibilityMessage = "Unable to verify location";
          _isCheckingEligibility = false;
        });
      }
    }
  }

  String? _eligibilityMessageForActions({
    required bool isLocationValid,
    required bool isCheckInTimeValid,
    required bool isCheckOutTimeValid,
    String? locationMessage,
  }) {
    if (!isLocationValid) {
      return locationMessage ?? 'You are not in the bounded area for marking attendance.';
    }
    if (isCheckInTimeValid || isCheckOutTimeValid) return null;
    return 'Check-in is allowed before college start time. Check-out is allowed after college hours.';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: SafeArea(
        child: Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          body: Column(
            children: [
              // Header
              _buildHeader(),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _handleRefresh,
                        child: CustomScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // Cards Section
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                AppTheme.spacingMD,
                                AppTheme.spacingSM,
                                AppTheme.spacingMD,
                                AppTheme.spacingLG,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                                  _buildScheduleInfoCard(),
                                  if (_collegeStartHour != null &&
                                      _collegeEndHour != null)
                                    const SizedBox(height: AppTheme.spacingSM),
                                  _buildActionsCard(),
                                  const SizedBox(height: AppTheme.spacingLG),

                                  // History Section
                                  _buildHistorySection(),
                                ]),
                              ),
                            ),

                            const SliverToBoxAdapter(
                              child: SizedBox(height: 90),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRegisterFace() async {
    final hasLocationPermission =
        await _ensureLocationPermissionForFaceRegistration();
    if (!hasLocationPermission) return;
    if (!mounted) return;

    if (!CloudFaceService.isConfigured) {
      _showCloudBackendMissingMessage();
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const CloudRegisterFaceScreen(),
      ),
    );
    if (result == true) {
      await _checkEnrollmentStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Face registered successfully!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _showCloudBackendMissingMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Face verification backend is not configured.'),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<bool> _ensureLocationPermissionForFaceRegistration() async {
    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted) return true;

    final requestStatus =
        await AppPermissionService.instance.requestLocationWhenInUse();
    if (requestStatus.isGranted) return true;
    if (!mounted) return false;

    if (requestStatus.isPermanentlyDenied) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location permission needed'),
          content: const Text(
            'Please allow location permission in Settings to register your face for attendance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Location permission is required. Please allow it.',
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    return false;
  }

  bool _historyFilterAccepts(String type) {
    if (_historyFilter == 'all') return true;
    if (_historyFilter == 'check-in') return type == 'check_in';
    if (_historyFilter == 'check-out') return type == 'check_out';
    return type == _historyFilter;
  }

  void _applyCloudAttendanceResult(
    Map<String, dynamic>? result, {
    required bool isCheckIn,
  }) {
    if (result == null || result['matched'] != true) return;

    final rawEvent = result['event'];
    final event = rawEvent is Map
        ? Map<String, dynamic>.from(rawEvent)
        : <String, dynamic>{
            'type': isCheckIn ? 'check_in' : 'check_out',
            'time': DateTime.now().toIso8601String(),
            'confidence': result['confidence'] ?? 1.0,
          };
    final type = (event['type'] ?? (isCheckIn ? 'check_in' : 'check_out'))
        .toString();

    setState(() {
      _isCheckedIn = isCheckIn;
      if (_historyFilterAccepts(type)) {
        final exists = _historyRecords.any(
          (record) =>
              record['type'] == event['type'] &&
              record['time'] == event['time'],
        );
        if (!exists) {
          _historyRecords = [event, ..._historyRecords];
        }
      }
    });
  }

  Future<void> _handleCheckIn() async {
    if (!CloudFaceService.isConfigured) {
      _showCloudBackendMissingMessage();
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const CloudMarkAttendanceScreen(isCheckIn: true),
      ),
    );
    if (result != null && result['matched'] == true) {
      if (mounted) {
        _applyCloudAttendanceResult(result, isCheckIn: true);
      }
      Future.delayed(const Duration(milliseconds: 600), _loadHistoryRecords);
      _checkEligibility();
      Future.delayed(const Duration(seconds: 2), () async {
        final confirmed = await _attendanceService.isCurrentlyCheckedIn();
        if (mounted && confirmed != _isCheckedIn) {
          setState(() => _isCheckedIn = confirmed);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Checked in successfully!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleCheckOut() async {
    if (!CloudFaceService.isConfigured) {
      _showCloudBackendMissingMessage();
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const CloudMarkAttendanceScreen(isCheckIn: false),
      ),
    );
    if (result != null && result['matched'] == true) {
      if (mounted) {
        _applyCloudAttendanceResult(result, isCheckIn: false);
      }
      Future.delayed(const Duration(milliseconds: 600), _loadHistoryRecords);
      _checkEligibility();
      Future.delayed(const Duration(seconds: 2), () async {
        final confirmed = await _attendanceService.isCurrentlyCheckedIn();
        if (mounted && confirmed != _isCheckedIn) {
          setState(() => _isCheckedIn = confirmed);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Checked out successfully!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingLG,
        vertical: AppTheme.spacingBase,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Attendance',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          AnimatedOpacity(
            opacity: _showSearchIcon ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: _showSearchIcon ? 1.0 : 0.8,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_upward,
                    size: 20,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleInfoCard() {
    if (_collegeStartHour == null || _collegeEndHour == null) {
      return const SizedBox.shrink();
    }
    final startH = _collegeStartHour!;
    final startM = _collegeStartMinute ?? 0;
    final endH = _collegeEndHour!;
    final endM = _collegeEndMinute ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMD,
        vertical: AppTheme.spacingSM,
      ),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.schedule,
              size: 16,
              color: AppTheme.primary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: AppTheme.spacingSM),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppTheme.textSecondary,
                ),
                children: [
                  const TextSpan(text: 'Check-in ends '),
                  TextSpan(
                    text: _formatCollegeTime(startH, startM),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text,
                    ),
                  ),
                  TextSpan(
                    text: ' · ',
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                  const TextSpan(text: 'Check-out from '),
                  TextSpan(
                    text: _formatCollegeTime(endH, endM),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isEnrolled)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMD),
                child: _buildRegisterButton(),
              )
            else
              _buildEnrolledAttendanceCard(),
          ],
        ),
      ),
    );
  }

  /// Polished layout: identity (left) + status + primary CTA; secondary action separated below.
  Widget _buildEnrolledAttendanceCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingBase,
            AppTheme.spacingLG,
            AppTheme.spacingBase,
            AppTheme.spacingMD,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRegisteredFaceAvatar(),
              const SizedBox(width: AppTheme.spacingBase),
              Expanded(child: _buildMarkAttendanceButton()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingBase),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.borderLight.withValues(alpha: 0.9),
          ),
        ),
        Material(
          color: AppTheme.backgroundLight.withValues(alpha: 0.65),
          child: InkWell(
            onTap: _handleRegisterFace,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacingMD,
                horizontal: AppTheme.spacingBase,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_front_outlined,
                    size: 20,
                    color: AppTheme.primary.withValues(alpha: 0.88),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Update registered face',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: AppTheme.textSecondary.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisteredFaceAvatar() {
    final hasPhoto = _faceImageUrl != null && _faceImageUrl!.isNotEmpty;

    final inner = hasPhoto
        ? Image.network(
            _faceImageUrl!,
            width: _avatarSize,
            height: _avatarSize,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: _avatarSize,
                height: _avatarSize,
                color: AppTheme.backgroundDark,
                alignment: Alignment.center,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppTheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                _faceAvatarPlaceholder(),
          )
        : _faceAvatarPlaceholder();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _avatarSize + 4,
          height: _avatarSize + 4,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withValues(alpha: 0.35),
                AppTheme.primary.withValues(alpha: 0.08),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: inner,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: 15,
              color: AppTheme.success.withValues(alpha: 0.95),
            ),
            const SizedBox(width: 4),
            Text(
              'Registered',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _faceAvatarPlaceholder() {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      color: AppTheme.backgroundDark,
      alignment: Alignment.center,
      child: Icon(
        Icons.face_rounded,
        size: 44,
        color: AppTheme.textSecondary.withValues(alpha: 0.45),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        const Text(
          'Attendance History',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),

        // Filter Pills
        _buildFilterPills(),
        const SizedBox(height: AppTheme.spacingMD),

        // History Records
        _isLoadingHistory
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.spacingXL),
                  child: CircularProgressIndicator(),
                ),
              )
            : _historyRecords.isEmpty
            ? _buildEmptyHistoryState()
            : Column(
                children: _historyRecords.map((record) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.spacingMD),
                    child: _buildHistoryRecordCard(record),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildFilterPills() {
    return Row(
      children: [
        Expanded(child: _buildFilterPill('all', 'All')),
        const SizedBox(width: AppTheme.spacingSM),
        Expanded(child: _buildFilterPill('check-in', 'Check In')),
        const SizedBox(width: AppTheme.spacingSM),
        Expanded(child: _buildFilterPill('check-out', 'Check Out')),
      ],
    );
  }

  Widget _buildFilterPill(String filter, String label) {
    final isActive = _historyFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _historyFilter = filter;
        });
        _loadHistoryRecords();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppTheme.spacingSM,
          horizontal: AppTheme.spacingMD,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : AppTheme.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(
            color: isActive ? AppTheme.primary : AppTheme.borderLight,
            width: 0.5,
          ),
          boxShadow: isActive ? null : AppTheme.shadowSM,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? AppTheme.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing2XL),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.access_time,
            size: 48,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: AppTheme.spacingMD),
          const Text(
            'No attendance records',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            _historyFilter == 'all'
                ? 'Attendance records will appear here once marked'
                : 'No ${_historyFilter.replaceAll('-', ' ')} records found',
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Only non-empty http(s) URLs; everything else shows the placeholder thumb/modal.
  String? _safeAttendanceImageUrl(dynamic raw) {
    if (raw == null) return null;
    final s = raw is String ? raw.trim() : raw.toString().trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return s;
  }

  Widget _buildHistoryRecordCard(Map<String, dynamic> record) {
    final isCheckIn = record['type'] == 'check_in';
    final timestamp = DateTime.parse(record['time'] as String);
    final photoUrl = _safeAttendanceImageUrl(record['photoUrl']);
    final accent = isCheckIn ? AppTheme.success : AppTheme.warning;
    final typeLabel = isCheckIn ? 'Check-in' : 'Check-out';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        child: Material(
          color: AppTheme.white,
          child: InkWell(
            onTap: () => _showAttendanceDetailModal(context, record),
            splashColor: AppTheme.primary.withValues(alpha: 0.06),
            highlightColor: AppTheme.primary.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMD,
                vertical: 10,
              ),
              child: Row(
                children: [
                  _historyThumbnail(photoUrl, isCheckIn, size: 50),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(timestamp),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.text,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _formatTime(timestamp),
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary.withValues(
                                  alpha: 0.92,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.28),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.15,
                                  color: accent.withValues(alpha: 0.95),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: AppTheme.textSecondary.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact square thumb for list rows (no IN/OUT overlay). [photoUrl] must be pre-validated.
  Widget _historyThumbnail(
    String? photoUrl,
    bool isCheckIn, {
    required double size,
  }) {
    final accent = isCheckIn ? AppTheme.success : AppTheme.warning;
    if (photoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            photoUrl,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return ColoredBox(
                color: AppTheme.backgroundDark,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: accent.withValues(alpha: 0.08),
              child: Icon(
                Icons.hide_image_outlined,
                size: size * 0.42,
                color: AppTheme.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Icon(
        isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
        size: size * 0.44,
        color: accent.withValues(alpha: 0.75),
      ),
    );
  }

  void _showAttendanceDetailModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final isCheckIn = record['type'] == 'check_in';
    final timestamp = DateTime.parse(record['time'] as String);
    final photoUrl = _safeAttendanceImageUrl(record['photoUrl']);

    final accent = isCheckIn ? AppTheme.success : AppTheme.warning;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewPadding.bottom;
        final safeBottom = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: AppTheme.spacingSM,
            right: AppTheme.spacingSM,
            bottom: bottomInset > 0 ? 0 : AppTheme.spacingSM,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusLG),
              ),
              boxShadow: AppTheme.shadowLG,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingLG,
                      AppTheme.spacingSM,
                      AppTheme.spacingLG,
                      AppTheme.spacingMD,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Attendance details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.text,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingMD),
                        if (photoUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusBase,
                            ),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return ColoredBox(
                                    color: AppTheme.backgroundDark,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: accent.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) =>
                                    ColoredBox(
                                      color: AppTheme.backgroundDark,
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                          AppTheme.spacingLG,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.hide_image_outlined,
                                              size: 44,
                                              color: AppTheme.textSecondary
                                                  .withValues(alpha: 0.5),
                                            ),
                                            const SizedBox(
                                              height: AppTheme.spacingSM,
                                            ),
                                            Text(
                                              "Couldn't load photo",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textSecondary
                                                    .withValues(alpha: 0.9),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Check your connection or Storage access.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textSecondary
                                                    .withValues(alpha: 0.65),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingLG),
                        ] else ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppTheme.spacingXL,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundDark,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusBase,
                              ),
                              border: Border.all(color: AppTheme.borderLight),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.photo_camera_outlined,
                                  size: 40,
                                  color: AppTheme.textSecondary.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacingSM),
                                Text(
                                  'No verification photo for this record',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingLG),
                        ],
                        _detailTile(
                          icon: Icons.schedule_rounded,
                          label: 'Time',
                          value: _formatTime(timestamp),
                          valueColor: accent,
                        ),
                        const SizedBox(height: AppTheme.spacingLG),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: AppTheme.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusBase,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8 + safeBottom),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailTile({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: AppTheme.textSecondary.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppTheme.text,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[dateTime.weekday - 1]}, ${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _handleRegisterFace,
        icon: const Icon(Icons.camera_alt, color: AppTheme.white, size: 20),
        label: const Text(
          'Register Face',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildMarkAttendanceButton() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _attendanceActionButton(
                label: 'Check In',
                icon: Icons.login,
                enabled: _canCheckInAction,
                backgroundColor: AppTheme.primary,
                onPressed: _handleCheckIn,
              ),
            ),
            const SizedBox(width: AppTheme.spacingSM),
            Expanded(
              child: _attendanceActionButton(
                label: 'Check Out',
                icon: Icons.logout,
                enabled: _canCheckOutAction,
                backgroundColor: Colors.orange,
                onPressed: _handleCheckOut,
              ),
            ),
          ],
        ),
        if (!_canCheckInAction &&
            !_canCheckOutAction &&
            !_isCheckingEligibility &&
            _eligibilityMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.error_outline,
                    size: 15,
                    color: AppTheme.error,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _eligibilityMessage!,
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _attendanceActionButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required Color backgroundColor,
    required Future<void> Function() onPressed,
  }) {
    final effectiveColor = _isCheckingEligibility
        ? AppTheme.textSecondary.withValues(alpha: 0.3)
        : enabled
        ? backgroundColor
        : AppTheme.textSecondary;

    return ElevatedButton.icon(
      onPressed: !_isCheckingEligibility && enabled ? onPressed : null,
      icon: _isCheckingEligibility
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, color: AppTheme.white, size: 19),
      label: Text(
        _isCheckingEligibility ? 'Checking...' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: effectiveColor,
        disabledBackgroundColor: effectiveColor.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }
}
