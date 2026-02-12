import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firebase_storage_service.dart';

class EventFormScreen extends StatefulWidget {
  final Map<String, dynamic>? event;

  const EventFormScreen({super.key, this.event});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirebaseStorageService _firebaseStorageService = FirebaseStorageService();
  final ImagePicker _imagePicker = ImagePicker();
  
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _venueController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _maleParticipantsController = TextEditingController();
  final TextEditingController _femaleParticipantsController = TextEditingController();
  
  final List<XFile> _images = [];
  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now();
  TimeOfDay _endTime = TimeOfDay.now();
  bool _loading = false;
  String? _userId;
  String? _userCollegeId;

  @override
  void initState() {
    super.initState();
    _loadUser();
    if (widget.event != null) {
      _loadEventData();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _districtController.dispose();
    _maleParticipantsController.dispose();
    _femaleParticipantsController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    setState(() {
      _userId = user?.uid;
      _userCollegeId = user?.collegeId;
    });
  }

  void _loadEventData() {
    final event = widget.event!;
    _titleController.text = event['title'] ?? '';
    _descriptionController.text = event['description'] ?? '';
    _venueController.text = event['venue'] ?? '';
    _districtController.text = event['district'] ?? '';
    _maleParticipantsController.text = (event['maleParticipants'] ?? 0).toString();
    _femaleParticipantsController.text = (event['femaleParticipants'] ?? 0).toString();
    
    if (event['startDate'] != null) {
      try {
        _startDate = DateTime.parse(event['startDate']);
      } catch (e) {
        // Ignore
      }
    }
    if (event['endDate'] != null) {
      try {
        _endDate = DateTime.parse(event['endDate']);
      } catch (e) {
        // Ignore
      }
    }
    if (event['startTime'] != null) {
      try {
        final timeParts = event['startTime'].toString().split(':');
        if (timeParts.length >= 2) {
          int hour = int.tryParse(timeParts[0]) ?? 0;
          int minute = int.tryParse(timeParts[1].split(' ')[0]) ?? 0;
          if (event['startTime'].toString().toLowerCase().contains('pm') && hour != 12) {
            hour += 12;
          } else if (event['startTime'].toString().toLowerCase().contains('am') && hour == 12) {
            hour = 0;
          }
          _startTime = TimeOfDay(hour: hour, minute: minute);
        }
      } catch (e) {
        // Ignore
      }
    }
    if (event['endTime'] != null) {
      try {
        final timeParts = event['endTime'].toString().split(':');
        if (timeParts.length >= 2) {
          int hour = int.tryParse(timeParts[0]) ?? 0;
          int minute = int.tryParse(timeParts[1].split(' ')[0]) ?? 0;
          if (event['endTime'].toString().toLowerCase().contains('pm') && hour != 12) {
            hour += 12;
          } else if (event['endTime'].toString().toLowerCase().contains('am') && hour == 12) {
            hour = 0;
          }
          _endTime = TimeOfDay(hour: hour, minute: minute);
        }
      } catch (e) {
        // Ignore
      }
    }
  }

  Future<void> _pickImages() async {
    final remainingSlots = 20 - _images.length;
    if (remainingSlots <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can add up to 20 images')),
        );
      }
      return;
    }

    try {
      final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
        imageQuality: 70, // Reduced from 80 to prevent memory issues
        maxWidth: 1080, // Resize large images to prevent crash
        maxHeight: 1080,
        requestFullMetadata: false, // Speed up picking on iOS
      );
      
      if (pickedFiles.isNotEmpty) {
        setState(() {
          if (_images.length + pickedFiles.length > 20) {
            _images.addAll(pickedFiles.take(20 - _images.length));
          } else {
            _images.addAll(pickedFiles);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking images: $e')),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  Future<void> _selectDateTime(bool isStart) async {
    DateTime initialDateTime;
    if (isStart) {
      initialDateTime = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _startTime.hour,
        _startTime.minute,
      );
    } else {
      initialDateTime = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        _endTime.hour,
        _endTime.minute,
      );
    }

    // First pick the date
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      // Then pick the time
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: isStart ? _startTime : _endTime,
      );

      if (pickedTime != null) {
        setState(() {
          if (isStart) {
            _startDate = pickedDate;
            _startTime = pickedTime;
          } else {
            _endDate = pickedDate;
            _endTime = pickedTime;
            // Ensure end date/time is not before start
            final endDateTime = DateTime(
              _endDate.year,
              _endDate.month,
              _endDate.day,
              _endTime.hour,
              _endTime.minute,
            );
            final startDateTime = DateTime(
              _startDate.year,
              _startDate.month,
              _startDate.day,
              _startTime.hour,
              _startTime.minute,
            );
            if (endDateTime.isBefore(startDateTime)) {
              _endDate = _startDate;
              _endTime = _startTime;
            }
          }
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${_getMonthName(date.month)} ${date.day}, ${date.year}';
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  bool _validateForm() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter event title')),
      );
      return false;
    }
    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter event description')),
      );
      return false;
    }
    if (_venueController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter venue')),
      );
      return false;
    }
    if (_districtController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter district')),
      );
      return false;
    }
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date')),
      );
      return false;
    }
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least 1 image')),
      );
      return false;
    }
    return true;
  }

  Future<void> _submitForm() async {
    if (!_validateForm()) return;

    setState(() => _loading = true);
    
    // final user = await _authService.currentUser; // Assuming auth service is available
    // if (user == null) {
      // Handle unauthenticated state if necessary
      // return;
    // }

    try {
      // Upload images to Firebase Storage
      final imageFiles = _images.map((xFile) => File(xFile.path)).toList();
      final imageUrls = await _firebaseStorageService.uploadEventImages(imageFiles);

      final eventData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'startDate': _startDate.toIso8601String().split('T')[0],
        'startTime': _formatTime(_startTime),
        'endDate': _endDate.toIso8601String().split('T')[0],
        'endTime': _formatTime(_endTime),
        'venue': _venueController.text.trim(),
        'district': _districtController.text.trim(),
        'maleParticipants': int.tryParse(_maleParticipantsController.text) ?? 0,
        'femaleParticipants': int.tryParse(_femaleParticipantsController.text) ?? 0,
        'organizedBy': await _getUserName(),
        'collegeId': _userCollegeId,
        'createdBy': _userId,
        'images': imageUrls,
        'status': widget.event?['status'] ?? 'upcoming',
      };

      if (widget.event?['id'] != null) {
        await _firestoreService.saveEvent(eventData, eventId: widget.event!['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event updated successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        await _firestoreService.saveEvent(eventData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event created successfully!')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save event: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String> _getUserName() async {
    final user = await _authService.getCurrentUser();
    return user?.name ?? user?.email ?? 'Organizer';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacing2XL),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppTheme.spacingXS),
                        const Text(
                          'Fill in the details below',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingLG),

                        // Images Section
                        _buildImagesSection(),
                        
                        const SizedBox(height: AppTheme.spacingLG),

                        // Event Title
                        _buildInputField(
                          controller: _titleController,
                          label: 'Event Title',
                          icon: Icons.title_outlined,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter event title';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: AppTheme.spacingLG),

                        // Event Description
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 4,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppTheme.text,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Event Description',
                            labelStyle: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 15,
                            ),
                            prefixIcon: const Icon(Icons.description_outlined, size: 20, color: AppTheme.textSecondary),
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
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter event description';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: AppTheme.spacingLG),

                        // Start Date & Time
                        _buildDateTimeField(
                          label: 'Start Date & Time',
                          date: _startDate,
                          time: _startTime,
                          onTap: () => _selectDateTime(true),
                        ),

                        const SizedBox(height: AppTheme.spacingLG),

                        // End Date & Time
                        _buildDateTimeField(
                          label: 'End Date & Time',
                          date: _endDate,
                          time: _endTime,
                          onTap: () => _selectDateTime(false),
                        ),

                        const SizedBox(height: AppTheme.spacingLG),

                        // Venue
                        _buildInputField(
                          controller: _venueController,
                          label: 'Venue',
                          icon: Icons.location_on_outlined,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter venue';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: AppTheme.spacingLG),

                        // District
                        _buildInputField(
                          controller: _districtController,
                          label: 'District',
                          icon: Icons.map_outlined,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter district';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: AppTheme.spacingLG),

                        // Participants
                        Row(
                          children: [
                            Expanded(
                              child: _buildInputField(
                                controller: _maleParticipantsController,
                                label: 'Male Participants',
                                icon: Icons.person_outline,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacingMD),
                            Expanded(
                              child: _buildInputField(
                                controller: _femaleParticipantsController,
                                label: 'Female Participants',
                                icon: Icons.person_outline,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppTheme.spacing2XL),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submitForm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.white),
                                    ),
                                  )
                                : Text(
                                    widget.event != null ? 'Update Event' : 'Create Event',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.white,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: AppTheme.spacingXL),
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
            child: Center(
              child: Text(
                widget.event != null ? 'Edit Event' : 'Create Event',
                style: const TextStyle(
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
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
        suffixIcon: suffixIcon,
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
      validator: validator,
    );
  }

  Widget _buildDateTimeField({
    required String label,
    required DateTime date,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLG,
          vertical: AppTheme.spacingMD,
        ),
        decoration: BoxDecoration(
          color: AppTheme.backgroundDark,
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: AppTheme.spacingMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(date),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.text,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingMD),
                      Icon(
                        Icons.access_time_outlined,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(time),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
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
              'Images (min 1)',
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
                        File(image.path),
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
            if (_images.length < 20)
              GestureDetector(
                onTap: _pickImages,
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
}
