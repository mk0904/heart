import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/attendance_service.dart';
import '../services/firebase_auth_service.dart';
import '../models/attendance_record.dart';
import 'register_screen.dart';
import 'mark_attendance_screen.dart';

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
  List<AttendanceRecord> _historyRecords = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load enrollment status first (critical for UI)
    _checkEnrollmentStatus();
    // Load history separately (non-blocking, can show loading state)
    _loadHistoryRecords();
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
      // Check Firebase user document for face registration
      final user = await _authService.getCurrentUser();
      if (user != null) {
        // Run parallel operations for faster loading
        final results = await Future.wait([
          // Check local registration (fast - Hive query)
          Future.value(_attendanceService.getAllPersons().any((p) => p.employeeId == user.uid)),
          // Check current check-in status
          _attendanceService.isCurrentlyCheckedIn(),
        ]);
        
        final hasLocalRegistration = results[0] as bool;
        final isCheckedIn = results[1] as bool;
        
        // Update UI immediately with initial state
        if (mounted) {
          setState(() {
            _isEnrolled = hasLocalRegistration;
            _isCheckedIn = isCheckedIn;
            _isLoading = false;
          });
        }
        
        // Check for auto-checkout in background (non-blocking)
        _attendanceService.checkAutoCheckout().then((_) async {
          final updatedCheckedIn = await _attendanceService.isCurrentlyCheckedIn();
          if (mounted && updatedCheckedIn != _isCheckedIn) {
            setState(() {
              _isCheckedIn = updatedCheckedIn;
            });
          }
        });
      } else {
        setState(() {
          _isEnrolled = false;
          _isCheckedIn = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEnrolled = false;
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
          : allRecords.where((r) => r.type == filterValue).toList();
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
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                          padding: const EdgeInsets.all(AppTheme.spacingLG),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              // Status Card
                              _buildStatusCard(),
                              const SizedBox(height: AppTheme.spacingMD),
                              
                              // Action Buttons Card
                              _buildActionsCard(),
                              const SizedBox(height: AppTheme.spacingXL),
                              
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
    );
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


  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _isEnrolled 
                  ? AppTheme.successLight 
                  : AppTheme.warningLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            ),
            child: Icon(
              _isEnrolled ? Icons.check_circle : Icons.info,
              color: _isEnrolled ? AppTheme.success : AppTheme.warning,
              size: 24,
            ),
          ),
          const SizedBox(width: AppTheme.spacingMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEnrolled ? 'Face Registered' : 'Face Not Registered',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isEnrolled
                      ? 'You can now mark attendance'
                      : 'Register your face to enable attendance',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Column(
        children: [
          if (!_isEnrolled)
            _buildRegisterButton()
          else
            Column(
              children: [
                _buildMarkAttendanceButton(),
                const SizedBox(height: AppTheme.spacingMD),
                _buildReRegisterButton(),
              ],
            ),
        ],
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
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingMD),
        
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
        Expanded(
          child: _buildFilterPill('all', 'All'),
        ),
        const SizedBox(width: AppTheme.spacingSM),
        Expanded(
          child: _buildFilterPill('check-in', 'Check In'),
        ),
        const SizedBox(width: AppTheme.spacingSM),
        Expanded(
          child: _buildFilterPill('check-out', 'Check Out'),
        ),
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
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryRecordCard(AttendanceRecord record) {
    final isCheckIn = record.type == 'check_in';
    
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Row(
        children: [
          // Status Badge
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCheckIn ? AppTheme.successLight : AppTheme.warningLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            ),
            child: Center(
              child: Text(
                isCheckIn ? 'IN' : 'OUT',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isCheckIn ? AppTheme.success : AppTheme.warning,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingMD),
          // Date and Time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(record.timestamp),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(record.timestamp),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${weekdays[dateTime.weekday - 1]}, ${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RegisterScreen()),
          );
          if (result == true) {
            _checkEnrollmentStatus();
          }
        },
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
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildMarkAttendanceButton() {
    final buttonText = _isCheckedIn ? 'Check Out' : 'Check In';
    final buttonIcon = _isCheckedIn ? Icons.logout : Icons.login;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          // Check if within college hours
          final isWithinHours = await _attendanceService.isWithinCollegeHours();
          if (!isWithinHours) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Attendance can only be marked during college hours'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }

          // Check geofence
          final geofenceResult = await _attendanceService.validateGeofence();
          if (!geofenceResult['valid']) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(geofenceResult['message'] ?? 'Location validation failed'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MarkAttendanceScreen(
                isCheckIn: !_isCheckedIn,
              ),
            ),
          );
          // Reload status and history after marking attendance
          await _checkEnrollmentStatus();
          await _loadHistoryRecords();
        },
        icon: Icon(buttonIcon, color: AppTheme.white, size: 20),
        label: Text(
          buttonText,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isCheckedIn ? Colors.orange : AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildReRegisterButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RegisterScreen()),
          );
          if (result == true) {
            _checkEnrollmentStatus();
          }
        },
        icon: const Icon(Icons.refresh, size: 18, color: AppTheme.textSecondary),
        label: const Text(
          'Re-register Face',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
          side: const BorderSide(color: AppTheme.borderLight, width: 1),
        ),
      ),
    );
  }
}
