import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/user_friendly_errors.dart';
import 'submit_data_screen.dart';

/// Principal-only list + detail/review for enrollment submissions.
/// Does not load course catalog or the submit form — use [SubmitDataScreen] for that.
class ReviewSubmissionsScreen extends StatefulWidget {
  const ReviewSubmissionsScreen({super.key});

  @override
  State<ReviewSubmissionsScreen> createState() =>
      _ReviewSubmissionsScreenState();
}

class _ReviewSubmissionsScreenState extends State<ReviewSubmissionsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();

  bool _loadingSubmissions = false;
  bool _refreshing = false;
  String? _userId;
  String? _currentUserName;
  List<Map<String, dynamic>> _recentSubmissions = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final role = user.role.toLowerCase().replaceAll('-', ' ');
      if (role != 'principal') {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Only principals can review submissions.'),
            ),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _userId = user.uid;
          _currentUserName = user.name;
        });
      }
      await _fetchRecentSubmissions();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _fetchRecentSubmissions() async {
    setState(() {
      _loadingSubmissions = true;
    });

    try {
      final user = await _authService.getCurrentUser();
      final collegeId = user?.collegeId ?? user?.college;

      final submissions = await _firestoreService.getEnrollmentSubmissions(
        collegeId: collegeId,
        submittedBy: collegeId == null ? _userId : null,
      );

      if (mounted) {
        setState(() {
          _recentSubmissions = submissions.take(10).toList();
          _loadingSubmissions = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingSubmissions = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _refreshing = true;
    });
    await _fetchRecentSubmissions();
    if (mounted) {
      setState(() {
        _refreshing = false;
      });
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Unknown Date';
    try {
      DateTime dateObj;
      if (date is Timestamp) {
        dateObj = date.toDate();
      } else if (date is Map && date['seconds'] != null) {
        dateObj = DateTime.fromMillisecondsSinceEpoch(
          (date['seconds'] as int) * 1000,
        );
      } else {
        dateObj = DateTime.parse(date.toString());
      }
      return '${_getMonthName(dateObj.month)} ${dateObj.day}, ${dateObj.year} '
          '${dateObj.hour.toString().padLeft(2, '0')}:'
          '${dateObj.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Unknown Date';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }

  void _openSubmissionModal(Map<String, dynamic> submission) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSubmissionBottomSheet(submission),
    );
  }

  Future<void> _approveSubmission(Map<String, dynamic> submission) async {
    try {
      final submissionId = submission['id'];
      if (submissionId == null) return;

      await _firestoreService.updateEnrollmentSubmission(submissionId, {
        'status': 'approved',
        'reviewedBy': _userId,
        'reviewedByName': _currentUserName,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submission approved successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        _fetchRecentSubmissions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyErrors.message(e))),
        );
      }
    }
  }

  Future<void> _rejectSubmission(Map<String, dynamic> submission) async {
    try {
      final submissionId = submission['id'];
      if (submissionId == null) return;

      await _firestoreService.updateEnrollmentSubmission(submissionId, {
        'status': 'rejected',
        'reviewedBy': _userId,
        'reviewedByName': _currentUserName,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submission rejected'),
            backgroundColor: AppTheme.error,
          ),
        );
        _fetchRecentSubmissions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyErrors.message(e))),
        );
      }
    }
  }

  void _openEditInSubmitScreen(Map<String, dynamic> submission) {
    Navigator.pop(context);
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => SubmitDataScreen(
          initialSubmissionMap: Map<String, dynamic>.from(submission),
        ),
      ),
    );
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
      child: Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppTheme.spacingLG),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppTheme.spacingLG),
                          margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusBase),
                            border: Border.all(
                              color: AppTheme.borderLight,
                              width: 0.5,
                            ),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 48,
                                color: AppTheme.primary,
                              ),
                              SizedBox(height: AppTheme.spacingMD),
                              Text(
                                'Tap a submission to view details, edit, approve, or reject.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.text,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildRecentSubmissionsCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        color: AppTheme.white,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.text, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Review Submissions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildRecentSubmissionsCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Submissions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
              TextButton(
                onPressed: _refreshing ? null : _onRefresh,
                child: Text(
                  'Refresh',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _refreshing
                        ? AppTheme.textSecondary
                        : AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMD),
          if (_loadingSubmissions)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.spacingXL),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_recentSubmissions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingXL),
                child: Column(
                  children: [
                    const Icon(
                      Icons.description,
                      size: 48,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: AppTheme.spacingMD),
                    Text(
                      'No submissions found.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._recentSubmissions.map(_buildSubmissionItem),
        ],
      ),
    );
  }

  Widget _buildSubmissionItem(Map<String, dynamic> submission) {
    return GestureDetector(
      onTap: () => _openSubmissionModal(submission),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMD),
        margin: const EdgeInsets.only(bottom: AppTheme.spacingSM),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          border: Border.all(color: AppTheme.borderLight, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${submission['academicYear'] != null && submission['academicYear'].toString().isNotEmpty ? submission['academicYear'] + ' • ' : ''}${submission['stream']} ${submission['semester']} - ${submission['course']}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(submission['submittedAt']),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingMD),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(submission['status'] ?? 'pending')
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    border: Border.all(
                      color: _getStatusColor(submission['status'] ?? 'pending'),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _getStatusText(submission['status'] ?? 'pending'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(submission['status'] ?? 'pending'),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${submission['totals']?['totalStudents'] ?? 0} students',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.text,
                  ),
                ),
                Text(
                  '${submission['totals']?['totalMale'] ?? 0}M • ${submission['totals']?['totalFemale'] ?? 0}F',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppTheme.spacingSM),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmissionBottomSheet(Map<String, dynamic> submission) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: AppTheme.spacingMD),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingLG),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Submission Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.text),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppTheme.spacingLG),
                  child: Column(
                    children: [
                      _buildModalCard(
                        'Basic Information',
                        [
                          _buildModalInfoRow(
                            'Academic Year:',
                            '${submission['academicYear'] ?? 'N/A'}',
                          ),
                          _buildModalInfoRow(
                            'Stream:',
                            '${submission['stream'] ?? ''}',
                          ),
                          _buildModalInfoRow(
                            'Semester:',
                            '${submission['semester'] ?? ''}',
                          ),
                          _buildModalInfoRow(
                            'Course:',
                            '${submission['course'] ?? ''}',
                          ),
                          _buildModalInfoRow(
                            'Submitted By:',
                            '${submission['submittedByName'] ?? 'Unknown'}',
                          ),
                          _buildModalInfoRow(
                            'Submitted At:',
                            _formatDate(submission['submittedAt']),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingMD),
                      _buildModalStudentDataCard(submission),
                      const SizedBox(height: AppTheme.spacingXL),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingLG),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  border: Border(
                    top: BorderSide(color: AppTheme.borderLight, width: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openEditInSubmitScreen(submission),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.spacingMD,
                          ),
                          side: const BorderSide(color: AppTheme.primary),
                          foregroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusBase),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSM),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: submission['status'] != 'approved'
                            ? () => _approveSubmission(submission)
                            : null,
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          disabledBackgroundColor:
                              AppTheme.textSecondary.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.spacingMD,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusBase),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSM),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: submission['status'] != 'rejected'
                            ? () => _rejectSubmission(submission)
                            : null,
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('Reject'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          disabledBackgroundColor:
                              AppTheme.textSecondary.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.spacingMD,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusBase),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingMD),
          ...children,
        ],
      ),
    );
  }

  Widget _buildModalInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalStudentDataCard(Map<String, dynamic> submission) {
    final categoryTotals =
        submission['categoryTotals'] as Map<String, dynamic>? ?? {};
    final studentData =
        submission['studentData'] as Map<String, dynamic>? ?? {};
    final totals = submission['totals'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student Enrollment Data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingLG),
          const Text(
            'Category Totals',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          ...categoryTotals.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${entry.key.toUpperCase()}:',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    '${entry.value}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppTheme.spacingLG),
          const Text(
            'Detailed Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          ...studentData.entries.map((entry) {
            final data = entry.value as Map<String, dynamic>? ?? {};
            final male = int.tryParse(data['male']?.toString() ?? '0') ?? 0;
            final female = int.tryParse(data['female']?.toString() ?? '0') ?? 0;
            final total = male + female;

            if (total == 0) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      entry.key.replaceAll('_', ' + ').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.text,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'M: $male',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingSM),
                      Text(
                        'F: $female',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingSM),
                      Text(
                        'Total: $total',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppTheme.spacingLG),
          const Divider(height: 2, color: AppTheme.primary, thickness: 2),
          const SizedBox(height: AppTheme.spacingMD),
          _buildModalTotalRow('Total Male', totals['totalMale'] ?? 0),
          _buildModalTotalRow('Total Female', totals['totalFemale'] ?? 0),
          const SizedBox(height: AppTheme.spacingSM),
          const Divider(height: 1, color: AppTheme.borderLight),
          const SizedBox(height: AppTheme.spacingSM),
          _buildModalGrandTotalRow(
            'Total Students',
            totals['totalStudents'] ?? 0,
          ),
        ],
      ),
    );
  }

  Widget _buildModalTotalRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalGrandTotalRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingSM),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppTheme.success;
      case 'rejected':
        return AppTheme.error;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'pending':
      default:
        return 'Pending';
    }
  }
}
