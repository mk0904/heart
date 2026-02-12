import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';

class SubmitDataScreen extends StatefulWidget {
  const SubmitDataScreen({super.key});

  @override
  State<SubmitDataScreen> createState() => _SubmitDataScreenState();
}

class _SubmitDataScreenState extends State<SubmitDataScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  
  String _selectedStream = '';
  String _selectedSemester = '';
  String _selectedCourse = '';
  bool _submitting = false;
  bool _loadingSubmissions = false;
  bool _refreshing = false;

  
  Map<String, dynamic>? _collegeLocation;

  String? _userId;
  String? _currentUserRole;
  String? _currentUserName;
  
  final Map<String, Map<String, String>> _studentData = {
    'st': {'male': '', 'female': ''},
    'sc': {'male': '', 'female': ''},
    'obc': {'male': '', 'female': ''},
    'general': {'male': '', 'female': ''},
    'pwd_only': {'male': '', 'female': ''},
    'st_pwd': {'male': '', 'female': ''},
    'sc_pwd': {'male': '', 'female': ''},
    'obc_pwd': {'male': '', 'female': ''},
    'general_pwd': {'male': '', 'female': ''},
  };
  
  List<Map<String, dynamic>> _recentSubmissions = [];

  final List<Map<String, String>> _streams = [
    {'value': 'B.A', 'label': 'B.A'},
    {'value': 'B.Sc', 'label': 'B.Sc'},
    {'value': 'B.Tech', 'label': 'B.Tech'},
    {'value': 'B.Com', 'label': 'B.Com'},
    {'value': 'B.Ed', 'label': 'B.Ed'},
    {'value': 'M.A', 'label': 'M.A'},
    {'value': 'M.Sc', 'label': 'M.Sc'},
    {'value': 'M.Tech', 'label': 'M.Tech'},
    {'value': 'M.Com', 'label': 'M.Com'},
  ];
  
  final List<String> _semesters = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th', '8th'];
  
  final List<Map<String, String>> _courses = [
    {'value': 'Economics', 'label': 'Economics'},
    {'value': 'Education', 'label': 'Education'},
    {'value': 'English', 'label': 'English'},
    {'value': 'History', 'label': 'History'},
    {'value': 'Philosophy', 'label': 'Philosophy'},
    {'value': 'Political Science', 'label': 'Political Science'},
    {'value': 'Sociology', 'label': 'Sociology'},
    {'value': 'Psychology', 'label': 'Psychology'},
    {'value': 'Mathematics', 'label': 'Mathematics'},
    {'value': 'Physics', 'label': 'Physics'},
    {'value': 'Chemistry', 'label': 'Chemistry'},
    {'value': 'Biology', 'label': 'Biology'},
    {'value': 'Computer Science', 'label': 'Computer Science'},
    {'value': 'Commerce', 'label': 'Commerce'},
  ];

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
      setState(() {
        _userId = user.uid;
        _currentUserRole = user.role;
        _currentUserName = user.name;
      });
      _fetchCollegeLocation();
      _fetchRecentSubmissions();
    } catch (e) {
      // Handle error
    }
  }

  bool get _isPrincipal => _currentUserRole?.toLowerCase() == 'principal';

  Future<void> _fetchCollegeLocation() async {
    try {
      final user = await _authService.getCurrentUser();
      final collegeId = user?.collegeId;
      if (collegeId == null) return;
      
      final college = await _firestoreService.getCollege(collegeId);
      if (college != null) {
        setState(() {
          _collegeLocation = college;
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _fetchRecentSubmissions() async {
    setState(() {
      _loadingSubmissions = true;
    });
    
    try {
      final user = await _authService.getCurrentUser();
      final collegeId = user?.collegeId;
      
      final submissions = await _firestoreService.getEnrollmentSubmissions(
        collegeId: collegeId,
        submittedBy: collegeId == null ? _userId : null,
      );
      
      setState(() {
        _recentSubmissions = submissions.take(10).toList();
        _loadingSubmissions = false;
      });
    } catch (e) {
      setState(() {
        _loadingSubmissions = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _refreshing = true;
    });
    await _fetchRecentSubmissions();
    setState(() {
      _refreshing = false;
    });
  }

  Map<String, int> _calculateTotals() {
    int totalMale = 0;
    int totalFemale = 0;
    
    _studentData.forEach((category, data) {
      totalMale += int.tryParse(data['male'] ?? '0') ?? 0;
      totalFemale += int.tryParse(data['female'] ?? '0') ?? 0;
    });
    
    return {
      'totalMale': totalMale,
      'totalFemale': totalFemale,
      'totalStudents': totalMale + totalFemale,
    };
  }

  Map<String, int> _calculateCategoryTotals() {
    return {
      'st': (int.tryParse(_studentData['st']!['male'] ?? '0') ?? 0) +
            (int.tryParse(_studentData['st']!['female'] ?? '0') ?? 0) +
            (int.tryParse(_studentData['st_pwd']!['male'] ?? '0') ?? 0) +
            (int.tryParse(_studentData['st_pwd']!['female'] ?? '0') ?? 0),
      'sc': (int.tryParse(_studentData['sc']!['male'] ?? '0') ?? 0) +
            (int.tryParse(_studentData['sc']!['female'] ?? '0') ?? 0) +
            (int.tryParse(_studentData['sc_pwd']!['male'] ?? '0') ?? 0) +
            (int.tryParse(_studentData['sc_pwd']!['female'] ?? '0') ?? 0),
      'obc': (int.tryParse(_studentData['obc']!['male'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['obc']!['female'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['obc_pwd']!['male'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['obc_pwd']!['female'] ?? '0') ?? 0),
      'general': (int.tryParse(_studentData['general']!['male'] ?? '0') ?? 0) +
                 (int.tryParse(_studentData['general']!['female'] ?? '0') ?? 0) +
                 (int.tryParse(_studentData['general_pwd']!['male'] ?? '0') ?? 0) +
                 (int.tryParse(_studentData['general_pwd']!['female'] ?? '0') ?? 0),
      'pwd': (int.tryParse(_studentData['pwd_only']!['male'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['pwd_only']!['female'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['st_pwd']!['male'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['st_pwd']!['female'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['sc_pwd']!['male'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['sc_pwd']!['female'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['obc_pwd']!['male'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['obc_pwd']!['female'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['general_pwd']!['male'] ?? '0') ?? 0) +
             (int.tryParse(_studentData['general_pwd']!['female'] ?? '0') ?? 0),
    };
  }

  void _updateStudentData(String category, String gender, String value) {
    setState(() {
      _studentData[category]![gender] = value;
    });
  }

  Future<void> _handleSubmit() async {
    if (_selectedStream.isEmpty || _selectedSemester.isEmpty || _selectedCourse.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Stream, Semester, and Course.')),
        );
      }
      return;
    }

    final totals = _calculateTotals();
    if (totals['totalStudents'] == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter at least some student data.')),
        );
      }
      return;
    }

    try {
      setState(() {
        _submitting = true;
      });
      
      final user = await _authService.getCurrentUser();
      if (user == null) {
        setState(() {
          _submitting = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated. Please log in again.')),
          );
        }
        return;
      }

      final collegeId = user.collegeId;
      
      // Clean student data (convert empty strings to '0')
      final cleanedStudentData = <String, Map<String, String>>{};
      _studentData.forEach((key, value) {
        cleanedStudentData[key] = {
          'male': value['male']!.isEmpty ? '0' : value['male']!,
          'female': value['female']!.isEmpty ? '0' : value['female']!,
        };
      });

      final categoryTotals = _calculateCategoryTotals();
      
      final submissionData = <String, dynamic>{
        'stream': _selectedStream,
        'semester': _selectedSemester,
        'course': _selectedCourse,
        'studentData': cleanedStudentData,
        'categoryTotals': categoryTotals,
        'totals': totals,
        'submittedBy': user.uid,
        'submittedByName': user.name,
        'submittedAt': FieldValue.serverTimestamp(),
        'collegeId': collegeId,
        'collegeName': user.college ?? 'Unknown College',
        'role': user.role,
        'status': 'pending', // pending, approved, rejected
        'reviewedBy': null,
        'reviewedByName': null,
        'reviewedAt': null,
      };

      if (_collegeLocation != null) {
        submissionData['college'] = {
          'id': _collegeLocation!['id'] ?? collegeId,
          'name': _collegeLocation!['name'] ?? user.college ?? 'Unknown College',
          'email': _collegeLocation!['email'],
          'phone': _collegeLocation!['phone'],
          'address': _collegeLocation!['address'],
          'location': _collegeLocation!['location'],
          'latitude': _collegeLocation!['latitude'],
          'longitude': _collegeLocation!['longitude'],
        };
      } else if (collegeId != null) {
        submissionData['college'] = {
          'id': collegeId,
          'name': user.college ?? 'Unknown College',
        };
      }

      await _firestoreService.addEnrollmentSubmission(submissionData);
      
      // Reset form
      setState(() {
        _selectedStream = '';
        _selectedSemester = '';
        _selectedCourse = '';
        _studentData.forEach((key, value) {
          value['male'] = '';
          value['female'] = '';
        });
      });
      
      // Refresh submissions after a delay
      Future.delayed(const Duration(milliseconds: 500), () {
        _fetchRecentSubmissions();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrollment data submitted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit data: $e')),
        );
      }
    } finally {
      setState(() {
        _submitting = false;
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
        dateObj = DateTime.fromMillisecondsSinceEpoch((date['seconds'] as int) * 1000);
      } else {
        dateObj = DateTime.parse(date.toString());
      }
      return '${_getMonthName(dateObj.month)} ${dateObj.day}, ${dateObj.year} ${dateObj.hour.toString().padLeft(2, '0')}:${dateObj.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown Date';
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  void _openSubmissionModal(Map<String, dynamic> submission) {
    showModalBottomSheet(
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
          SnackBar(content: Text('Failed to approve: $e')),
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
          SnackBar(content: Text('Failed to reject: $e')),
        );
      }
    }
  }

  void _editSubmission(Map<String, dynamic> submission) {
    // Pre-fill form with submission data
    setState(() {
      _selectedStream = submission['stream'] ?? '';
      _selectedSemester = submission['semester'] ?? '';
      _selectedCourse = submission['course'] ?? '';
      
      // Load student data
      final studentData = submission['studentData'] as Map<String, dynamic>?;
      if (studentData != null) {
        studentData.forEach((category, data) {
          if (data is Map) {
            _studentData[category] = {
              'male': data['male']?.toString() ?? '0',
              'female': data['female']?.toString() ?? '0',
            };
          }
        });
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Form pre-filled with submission data. You can now edit and resubmit.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
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
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingLG),
                  child: Column(
                    children: [
                      // Form Card
                      _buildFormCard(),
                      
                      // Student Data Input (shown when form is filled)
                      if (_selectedStream.isNotEmpty && _selectedSemester.isNotEmpty && _selectedCourse.isNotEmpty)
                        _buildStudentDataCard(),
                      
                      // Recent Submissions
                      _buildRecentSubmissionsCard(),
                    ],
                  ),
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
                'Submit Data',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48), // Spacer for centering
        ],
      ),
    );
  }

  Widget _buildFormCard() {
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
          // Stream Selection
          _buildDropdownField(
            'Stream *',
            _selectedStream,
            _streams,
            (value) => setState(() => _selectedStream = value),
            'Select Stream',
            Icons.description,
          ),
          
          const SizedBox(height: AppTheme.spacingLG),
          
          // Semester Selection
          _buildSemesterSelector(),
          
          const SizedBox(height: AppTheme.spacingLG),
          
          // Course Selection
          _buildDropdownField(
            'Course *',
            _selectedCourse,
            _courses,
            (value) => setState(() => _selectedCourse = value),
            'Select Course',
            Icons.description,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<Map<String, String>> options,
    Function(String) onChanged,
    String placeholder,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingXS),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
          child: DropdownButton<String>(
            value: value.isEmpty ? null : value,
            isExpanded: true,
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down, color: AppTheme.text),
            hint: Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: AppTheme.spacingSM),
                Text(
                  placeholder,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
            items: options.map((option) {
              return DropdownMenuItem<String>(
                value: option['value'],
                child: Text(option['label'] ?? ''),
              );
            }).toList(),
            onChanged: (newValue) {
              if (newValue != null) {
                onChanged(newValue);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSemesterSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Semester *',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingXS),
        Wrap(
          spacing: AppTheme.spacingXS,
          runSpacing: AppTheme.spacingXS,
          children: _semesters.map((semester) {
            final isSelected = _selectedSemester == semester;
            return GestureDetector(
              onTap: () => setState(() => _selectedSemester = semester),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: AppTheme.spacingSM,
                  horizontal: AppTheme.spacingMD,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : AppTheme.backgroundDark,
                  borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.borderLight,
                  ),
                ),
                child: Text(
                  semester,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? AppTheme.white : AppTheme.text,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStudentDataCard() {
    final totals = _calculateTotals();
    final categoryTotals = _calculateCategoryTotals();
    
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
          const Text(
            'Student Enrollment Data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            '$_selectedStream $_selectedSemester - $_selectedCourse',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingLG),
          
          // Category Rows
          _buildCategoryRow('ST', 'st'),
          _buildCategoryRow('SC', 'sc'),
          _buildCategoryRow('OBC', 'obc'),
          _buildCategoryRow('General', 'general'),
          
          // PWD Categories
          const SizedBox(height: AppTheme.spacingLG),
          const Text(
            'PWD Categories',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingMD),
          _buildCategoryRow('PWD Only', 'pwd_only'),
          _buildCategoryRow('ST + PWD', 'st_pwd'),
          _buildCategoryRow('SC + PWD', 'sc_pwd'),
          _buildCategoryRow('OBC + PWD', 'obc_pwd'),
          _buildCategoryRow('General + PWD', 'general_pwd'),
          
          // Totals Display
          const SizedBox(height: AppTheme.spacingLG),
          _buildTotalsContainer(totals, categoryTotals),
          
          // Submit Button
          const SizedBox(height: AppTheme.spacingLG),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_upload, color: AppTheme.white, size: 20),
                        const SizedBox(width: AppTheme.spacingSM),
                        const Text(
                          'Submit Data',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.white,
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

  Widget _buildCategoryRow(String label, String category) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.text,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingLG),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'M',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingXS),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: TextEditingController(
                            text: _studentData[category]!['male'],
                          )..selection = TextSelection.fromPosition(
                            TextPosition(offset: _studentData[category]!['male']!.length),
                          ),
                          onChanged: (value) => _updateStudentData(category, 'male', value),
                          keyboardType: TextInputType.number,
                          maxLength: 3,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                              borderSide: const BorderSide(color: AppTheme.borderLight),
                            ),
                            filled: true,
                            fillColor: AppTheme.backgroundDark,
                            contentPadding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.spacingLG),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'F',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingXS),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: TextEditingController(
                            text: _studentData[category]!['female'],
                          )..selection = TextSelection.fromPosition(
                            TextPosition(offset: _studentData[category]!['female']!.length),
                          ),
                          onChanged: (value) => _updateStudentData(category, 'female', value),
                          keyboardType: TextInputType.number,
                          maxLength: 3,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                              borderSide: const BorderSide(color: AppTheme.borderLight),
                            ),
                            filled: true,
                            fillColor: AppTheme.backgroundDark,
                            contentPadding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsContainer(Map<String, int> totals, Map<String, int> categoryTotals) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        children: [
          const Text(
            'Student Count Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingMD),
          
          // Category Totals
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Category Totals:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          _buildBreakdownRow('ST', categoryTotals['st'] ?? 0),
          _buildBreakdownRow('SC', categoryTotals['sc'] ?? 0),
          _buildBreakdownRow('OBC', categoryTotals['obc'] ?? 0),
          _buildBreakdownRow('General', categoryTotals['general'] ?? 0),
          _buildBreakdownRow('PWD', categoryTotals['pwd'] ?? 0),
          
          // Final Totals
          const SizedBox(height: AppTheme.spacingMD),
          const Divider(height: 2, color: AppTheme.primary, thickness: 2),
          const SizedBox(height: AppTheme.spacingMD),
          _buildTotalRow('Total Male', totals['totalMale'] ?? 0),
          _buildTotalRow('Total Female', totals['totalFemale'] ?? 0),
          const SizedBox(height: AppTheme.spacingSM),
          const Divider(height: 1, color: AppTheme.borderLight),
          const SizedBox(height: AppTheme.spacingSM),
          _buildGrandTotalRow('Total Students', totals['totalStudents'] ?? 0),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
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
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrandTotalRow(String label, int value) {
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
                    color: _refreshing ? AppTheme.textSecondary : AppTheme.primary,
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
                    const Icon(Icons.description, size: 48, color: AppTheme.textSecondary),
                    const SizedBox(height: AppTheme.spacingMD),
                    const Text(
                      'No submissions found. Submit your first data to see it here.',
                      style: TextStyle(
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
            ..._recentSubmissions.map((submission) => _buildSubmissionItem(submission)),
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
            // Left side: Title and Date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${submission['stream']} ${submission['semester']} - ${submission['course']}',
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
            // Right side: Status and Details
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(submission['status'] ?? 'pending').withValues(alpha: 0.1),
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
                // Student count details
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
              // Handle bar
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

              // Header
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
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppTheme.spacingLG),
                  child: Column(
                    children: [
                      // Basic Info
                      _buildModalCard(
                        'Basic Information',
                        [
                          _buildModalInfoRow('Stream:', submission['stream']),
                          _buildModalInfoRow('Semester:', submission['semester']),
                          _buildModalInfoRow('Course:', submission['course']),
                          _buildModalInfoRow('Submitted By:', submission['submittedByName'] ?? 'Unknown'),
                          _buildModalInfoRow('Submitted At:', _formatDate(submission['submittedAt'])),
                        ],
                      ),
                      
                      const SizedBox(height: AppTheme.spacingMD),
                      
                      // Student Data
                      _buildModalStudentDataCard(submission),
                      const SizedBox(height: AppTheme.spacingXL),
                    ],
                  ),
                ),
              ),

              // Action Buttons (for principals only)
              if (_isPrincipal)
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
                          onPressed: () {
                            Navigator.pop(context);
                            _editSubmission(submission);
                          },
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            side: const BorderSide(color: AppTheme.primary),
                            foregroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
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
                            disabledBackgroundColor: AppTheme.textSecondary.withValues(alpha: 0.3),
                            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
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
                            disabledBackgroundColor: AppTheme.textSecondary.withValues(alpha: 0.3),
                            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
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
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalStudentDataCard(Map<String, dynamic> submission) {
    final categoryTotals = submission['categoryTotals'] as Map<String, dynamic>? ?? {};
    final studentData = submission['studentData'] as Map<String, dynamic>? ?? {};
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
          
          // Category Totals
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
          
          // Detailed Breakdown
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
                  Text(
                    entry.key.replaceAll('_', ' + ').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.text,
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
          
          // Final Totals
          const Divider(height: 2, color: AppTheme.primary, thickness: 2),
          const SizedBox(height: AppTheme.spacingMD),
          _buildModalTotalRow('Total Male', totals['totalMale'] ?? 0),
          _buildModalTotalRow('Total Female', totals['totalFemale'] ?? 0),
          const SizedBox(height: AppTheme.spacingSM),
          const Divider(height: 1, color: AppTheme.borderLight),
          const SizedBox(height: AppTheme.spacingSM),
          _buildModalGrandTotalRow('Total Students', totals['totalStudents'] ?? 0),
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
