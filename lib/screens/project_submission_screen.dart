import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firebase_storage_service.dart';
import 'dart:io';

class ProjectSubmissionScreen extends StatefulWidget {
  final Map<String, dynamic> project;
  final String? submissionId;
  final Map<String, dynamic>? existingData;

  const ProjectSubmissionScreen({
    super.key,
    required this.project,
    this.submissionId,
    this.existingData,
  });

  @override
  State<ProjectSubmissionScreen> createState() => _ProjectSubmissionScreenState();
}

class _ProjectSubmissionScreenState extends State<ProjectSubmissionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirebaseStorageService _storageService = FirebaseStorageService();
  final TextEditingController _notesController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  
  double _percentage = 0;
  int _previousPercentage = 0;
  final List<File> _images = [];
  bool _loading = false;
  bool _submitting = false;
  
  // New fields
  List<Map<String, dynamic>> _colleges = [];
  String? _selectedCollegeId;
  String? _selectedCollegeName;
  String _submissionStatus = 'Pending';
  String? _userRole;
  List<String> _existingImageUrls = [];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadColleges();
    if (widget.existingData != null) {
      _loadExistingData();
    } else {
      _loadPreviousSubmission();
    }
  }

  Future<void> _loadUserProfile() async {
    final user = await _authService.getCurrentUser();
    if (mounted) {
      setState(() {
        _userRole = user?.role;
      });
    }
  }

  Future<void> _loadColleges() async {
    try {
      final colleges = await _firestoreService.getColleges();
      if (mounted) {
        setState(() {
          _colleges = colleges;
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  void _loadExistingData() {
    final data = widget.existingData!;
    setState(() {
      _percentage = (data['percentage'] ?? 0).toDouble();
      _notesController.text = data['notes'] ?? '';
      _submissionStatus = data['status'] ?? 'Pending';
      _selectedCollegeId = data['collegeId'];
      _selectedCollegeName = data['collegeName'];
      
      final images = data['images'] as List? ?? [];
      _existingImageUrls = images.map((img) {
        if (img is String) return img;
        if (img is Map) return img['url'] as String? ?? '';
        return '';
      }).where((url) => url.isNotEmpty).cast<String>().toList();
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPreviousSubmission() async {
    setState(() => _loading = true);
    try {
      final submissions = await _firestoreService.getSubmissions(widget.project['id']);
      if (submissions.isNotEmpty) {
        // Sort by createdAt and get latest
        submissions.sort((a, b) {
          final dateA = _parseDate(a['createdAt']);
          final dateB = _parseDate(b['createdAt']);
          return dateB.compareTo(dateA);
        });
        final lastSubmission = submissions.first;
        _previousPercentage = lastSubmission['percentage'] ?? 0;
        _percentage = _previousPercentage.toDouble();
      }
    } catch (e) {
      // Ignore errors
    } finally {
      setState(() => _loading = false);
    }
  }

  DateTime _parseDate(dynamic date) {
    if (date == null) return DateTime(1970);
    if (date is DateTime) return date;
    if (date is String) {
      try {
        return DateTime.parse(date);
      } catch (e) {
        return DateTime(1970);
      }
    }
    try {
      return (date as dynamic).toDate();
    } catch (e) {
      return DateTime(1970);
    }
  }

  Future<void> _pickImage() async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 images allowed')),
      );
      return;
    }

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _images.add(File(pickedFile.path));
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  Future<void> _handleSubmit() async {
    if (_percentage < _previousPercentage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Percentage must be at least $_previousPercentage%')),
      );
      return;
    }

    if (_notesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter progress notes')),
      );
      return;
    }

    if (_selectedCollegeId == null && _userRole?.toLowerCase().replaceAll('-', ' ') == 'ministerial staff') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a college')),
      );
      return;
    }

    // Safety check: Principals cannot create new submissions
    if (widget.submissionId == null && _userRole?.toLowerCase().replaceAll('-', ' ') != 'ministerial staff') {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only Ministerial Staff can create new submissions')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final user = await _authService.getCurrentUser();
      
      // Upload images to Firebase Storage and get download URLs
      final newImageData = await _storageService.uploadProjectSubmissionImages(
        files: _images,
        projectId: widget.project['id'] ?? '',
      );

      // Combine existing and new images
      final allImages = [..._existingImageUrls, ...newImageData];

      final submissionData = {
        'projectId': widget.project['id'],
        'projectName': widget.project['name'],
        'percentage': _percentage.round(),
        'notes': _notesController.text.trim(),
        'images': allImages,
        'status': _submissionStatus,
        if (_selectedCollegeId != null) 'collegeId': _selectedCollegeId,
        if (_selectedCollegeName != null) 'collegeName': _selectedCollegeName,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      if (widget.submissionId != null) {
        // Update existing
        submissionData['updatedBy'] = user?.uid;
        await _firestoreService.updateSubmission(widget.submissionId!, submissionData);
      } else {
        // Create new
        submissionData['userId'] = user?.uid ?? 'unknown';
        submissionData['userName'] = user?.name ?? 'Unknown User';
        submissionData['createdAt'] = DateTime.now().toIso8601String();
        await _firestoreService.addSubmission(submissionData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submission successful!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(
        fontSize: 15,
        color: AppTheme.text,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 15,
        ),
        prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.backgroundDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          borderSide: const BorderSide(color: AppTheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          borderSide: const BorderSide(color: AppTheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLG,
          vertical: AppTheme.spacingMD,
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
        color: Colors.white,
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
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Project Submission',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text,
                  ),
                ),
                if (_previousPercentage > 0)
                  Text(
                    'Previous: $_previousPercentage%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildPercentageSection() {
    if (_previousPercentage >= 100) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Completion Percentage',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMD),
            decoration: BoxDecoration(
              color: AppTheme.successLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              border: Border.all(color: AppTheme.success, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                const SizedBox(width: AppTheme.spacingSM),
                const Expanded(
                  child: Text(
                    'Project already completed at 100%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Completion Percentage',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        TextFormField(
          keyboardType: TextInputType.number,
          initialValue: _percentage > 0 ? _percentage.round().toString() : '',
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            TextInputFormatter.withFunction((oldValue, newValue) {
              if (newValue.text.isEmpty) return newValue;
              final value = int.tryParse(newValue.text);
              if (value == null) return oldValue;
              if (value < 0 || value > 100) return oldValue;
              return newValue;
            }),
          ],
          style: const TextStyle(
            fontSize: 15,
            color: AppTheme.text,
          ),
          decoration: InputDecoration(
            labelText: 'Enter percentage ($_previousPercentage-100)',
            labelStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
            ),
            suffixText: '%',
            suffixStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
            ),
            prefixIcon: const Icon(Icons.percent, size: 20, color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.backgroundDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.error, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.error, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingLG,
              vertical: AppTheme.spacingMD,
            ),
          ),
          onChanged: (value) {
            if (value.isNotEmpty) {
              final percentage = int.tryParse(value);
              if (percentage != null && percentage >= _previousPercentage && percentage <= 100) {
                setState(() => _percentage = percentage.toDouble());
              }
            } else {
              setState(() => _percentage = 0);
            }
          },
        ),
        if (_previousPercentage > 0) ...[
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            'Minimum allowed: $_previousPercentage%',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCollegeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select College',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCollegeId,
              hint: const Text('Select a college'),
              isExpanded: true,
              items: _colleges.map((college) {
                return DropdownMenuItem<String>(
                  value: college['id'],
                  child: Text(college['name'] ?? 'Unknown'),
                );
              }).toList(),
              onChanged: _userRole?.toLowerCase().replaceAll('-', ' ') == 'ministerial staff' 
                ? (value) {
                    setState(() {
                      _selectedCollegeId = value;
                      _selectedCollegeName = _colleges.firstWhere((c) => c['id'] == value)['name'];
                    });
                  }
                : null, // Disable for non-Ministerial Staff (or maybe allow Principal to edit?)
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _submissionStatus,
              isExpanded: true,
              items: ['Pending', 'Approved', 'Rejected'].map((status) {
                return DropdownMenuItem<String>(
                  value: status,
                  child: Text(status),
                );
              }).toList(),
              onChanged: _userRole?.toLowerCase() == 'principal'
                  ? (value) {
                      if (value != null) {
                        setState(() => _submissionStatus = value);
                      }
                    }
                  : null, 
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Progress Images (min 1)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingSM,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _images.isNotEmpty
                    ? AppTheme.successLight
                    : AppTheme.warningLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_images.length} selected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _images.isNotEmpty
                      ? AppTheme.success
                      : AppTheme.warning,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingMD),
        Wrap(
          spacing: AppTheme.spacingXS,
          runSpacing: AppTheme.spacingXS,
          children: [
            ..._images.asMap().entries.map((entry) {
              final index = entry.key;
              final image = entry.value;
              return Stack(
                children: [
                  Container(
                    width: (MediaQuery.of(context).size.width - AppTheme.spacing2XL * 2 - AppTheme.spacingXS * 2) / 3,
                    height: (MediaQuery.of(context).size.width - AppTheme.spacing2XL * 2 - AppTheme.spacingXS * 2) / 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                      border: Border.all(color: AppTheme.borderLight, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                      child: Image.file(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppTheme.borderLight,
                            child: const Icon(Icons.broken_image, size: 32, color: AppTheme.textSecondary),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: AppTheme.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: AppTheme.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
            if (_images.length < 5)
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: (MediaQuery.of(context).size.width - AppTheme.spacing2XL * 2 - AppTheme.spacingXS * 2) / 3,
                  height: (MediaQuery.of(context).size.width - AppTheme.spacing2XL * 2 - AppTheme.spacingXS * 2) / 3,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppTheme.borderLight,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                    color: AppTheme.backgroundDark,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 32,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(height: AppTheme.spacingXS),
                      Text(
                        'Add',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
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
        backgroundColor: Colors.white,
        body: _loading 
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppTheme.spacingLG),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Project Info Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppTheme.spacingMD),
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
                                  widget.project['name'] ?? 'Untitled Project',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.project['description'] ?? 'No description provided',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: AppTheme.spacingXL),
                          
                          // Form
                          _buildPercentageSection(),
                          
                          const SizedBox(height: AppTheme.spacingXL),
                          
                          if (_userRole?.toLowerCase().replaceAll('-', ' ') == 'ministerial staff') ...[
                            _buildCollegeSection(),
                            const SizedBox(height: AppTheme.spacingXL),
                          ],
                          
                          if (_userRole?.toLowerCase() == 'principal' && widget.submissionId != null) ...[
                            _buildStatusSection(),
                            const SizedBox(height: AppTheme.spacingXL),
                          ],
                          
                          _buildInputField(
                            controller: _notesController,
                            label: 'Progress Notes',
                            icon: Icons.notes,
                            maxLines: 4,
                          ),
                          
                          const SizedBox(height: AppTheme.spacingXL),
                          
                          _buildImagesSection(),
                          
                          const SizedBox(height: AppTheme.spacing2XL),
                          
                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: (_submitting ||
                                      _previousPercentage >= 100 ||
                                      _percentage < _previousPercentage ||
                                      _notesController.text.trim().isEmpty ||
                                      _images.isEmpty)
                                  ? null
                                  : _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                ),
                                elevation: 0,
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Submit Progress Update',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing2XL),
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
}
