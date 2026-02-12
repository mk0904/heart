import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import '../navigation/main_tab_navigator.dart';
import '../models/user_profile.dart';
import '../services/firebase_storage_service.dart';

class EditProfileScreen extends StatefulWidget {
  final bool isCompleteProfile;
  
  const EditProfileScreen({
    super.key,
    this.isCompleteProfile = false,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}



class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirebaseStorageService _storageService = FirebaseStorageService();
  final ImagePicker _imagePicker = ImagePicker();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _payBandController = TextEditingController();
  
  String? _employmentType;
  bool? _govtQuarter;
  DateTime? _dateOfBirth;
  DateTime? _dateOfAppointment;
  DateTime? _dateOfConfirmation;
  DateTime? _dateOfRetirement;
  bool _loading = false;
  bool _saving = false;
  String? _userId;
  String? _photoUrl;
  File? _selectedImage;
  bool _uploadingPhoto = false;
  bool _isProfileIncomplete = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }
  
  // Check if profile is incomplete
  bool _checkIfProfileIncomplete(UserProfile user) {
    // Check if profileCompleted is false
    if (user.profileCompleted == false) return true;
    
    // Check if required fields are missing
    final phoneNumber = user.phoneNumber ?? user.phone ?? '';
    final payBand = user.payBand ?? '';
    
    return phoneNumber.trim().isEmpty || payBand.trim().isEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _payBandController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }
      
      _userId = user.uid;
      _nameController.text = user.name ?? '';
      _phoneController.text = user.phoneNumber ?? '';
      _payBandController.text = user.payBand ?? '';
      _employmentType = user.employmentType;
      _govtQuarter = user.govtQuarter;
      _dateOfBirth = user.dateOfBirth;
      _dateOfAppointment = user.dateOfAppointment;
      _dateOfConfirmation = user.dateOfConfirmation;
      _dateOfRetirement = user.dateOfRetirement;
      _photoUrl = user.photoUrl;
      
      // Check if profile is incomplete
      _isProfileIncomplete = _checkIfProfileIncomplete(user);
      
      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  Future<void> _selectDate(String type) async {
    DateTime? initialDate;
    switch (type) {
      case 'dob':
        initialDate = _dateOfBirth ?? DateTime.now().subtract(const Duration(days: 365 * 30));
        break;
      case 'appointment':
        initialDate = _dateOfAppointment ?? DateTime.now();
        break;
      case 'confirmation':
        initialDate = _dateOfConfirmation ?? DateTime.now();
        break;
      case 'retirement':
        initialDate = _dateOfRetirement ?? DateTime.now().add(const Duration(days: 365 * 10));
        break;
    }
    
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    
    if (picked != null) {
      setState(() {
        switch (type) {
          case 'dob':
            _dateOfBirth = picked;
            break;
          case 'appointment':
            _dateOfAppointment = picked;
            break;
          case 'confirmation':
            _dateOfConfirmation = picked;
            break;
          case 'retirement':
            _dateOfRetirement = picked;
            break;
        }
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _showImageSourceDialog() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLG)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_selectedImage != null || _photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: AppTheme.error),
                title: const Text('Remove Photo', style: TextStyle(color: AppTheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                    _photoUrl = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    // In complete profile mode, validate required fields
    if (widget.isCompleteProfile || _isProfileIncomplete) {
      if (_phoneController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your phone number')),
        );
        return;
      }
      if (_payBandController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your Pay Band / Grade Pay')),
        );
        return;
      }
    }

    setState(() {
      _saving = true;
      _uploadingPhoto = _selectedImage != null;
    });

    try {
      String? updatedPhotoUrl = _photoUrl;

      // If new image selected, upload it
      if (_selectedImage != null) {
        updatedPhotoUrl = await _storageService.uploadProfileImage(
          _selectedImage!,
          _userId!,
        );
      } else if (_photoUrl == null && _selectedImage == null) {
        // Photo was removed
        updatedPhotoUrl = null;
      }

      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        if (_payBandController.text.isNotEmpty) 'payBand': _payBandController.text.trim(),
        if (_employmentType != null) 'employmentType': _employmentType,
        if (_govtQuarter != null) 'govtQuarter': _govtQuarter,
        if (_dateOfBirth != null) 'dateOfBirth': _dateOfBirth!.toIso8601String(),
        if (_dateOfAppointment != null) 'dateOfAppointment': _dateOfAppointment!.toIso8601String(),
        if (_dateOfConfirmation != null) 'dateOfConfirmation': _dateOfConfirmation!.toIso8601String(),
        if (_dateOfRetirement != null) 'dateOfRetirement': _dateOfRetirement!.toIso8601String(),
        'photoUrl': updatedPhotoUrl, // Always update, can be null
        'profileCompleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await _firestoreService.updateUser(_userId!, updateData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // If in complete profile mode, navigate to main app
        if (widget.isCompleteProfile || _isProfileIncomplete) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainTabNavigator()),
          );
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadingPhoto = false;
        });
      }
    }
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
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(AppTheme.spacing2XL),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: AppTheme.spacingMD),
                              const Text(
                                'Update your profile information',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacing2XL),
                              
                              // Profile Picture Section
                              Center(
                                child: _buildProfilePictureSection(),
                              ),
                              
                              const SizedBox(height: AppTheme.spacing2XL),
                              
                              // Name
                              _buildInputField(
                                controller: _nameController,
                                label: 'Full Name',
                                icon: Icons.person_outline,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Name is required';
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Phone Number
                              _buildInputField(
                                controller: _phoneController,
                                label: 'Phone Number',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                validator: (value) {
                                  // Required in complete profile mode or if profile is incomplete
                                  if ((widget.isCompleteProfile || _isProfileIncomplete) && (value == null || value.trim().isEmpty)) {
                                    return 'Phone number is required';
                                  }
                                  if (value != null && value.trim().isNotEmpty && value.length < 10) {
                                    return 'Please enter a valid phone number';
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Employment Type
                              _buildDropdown(
                                value: _employmentType,
                                label: 'Employment Type',
                                icon: Icons.work_outline,
                                items: [
                                  const DropdownMenuItem(
                                    value: 'Contractual',
                                    child: Text('Contractual'),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'Permanent',
                                    child: Text('Permanent'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _employmentType = value;
                                  });
                                },
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Pay Band
                              _buildInputField(
                                controller: _payBandController,
                                label: 'Pay Band / Grade Pay',
                                icon: Icons.account_balance_wallet_outlined,
                                hintText: 'e.g., PB-1, PB-2',
                                validator: (value) {
                                  // Required in complete profile mode
                                  if ((widget.isCompleteProfile || _isProfileIncomplete) && (value == null || value.trim().isEmpty)) {
                                    return 'Please enter your Pay Band / Grade Pay';
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Date of Birth
                              _buildDateField(
                                label: 'Date of Birth',
                                value: _formatDate(_dateOfBirth),
                                icon: Icons.calendar_today_outlined,
                                onTap: () => _selectDate('dob'),
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Date of Appointment
                              _buildDateField(
                                label: 'Date of Appointment',
                                value: _formatDate(_dateOfAppointment),
                                icon: Icons.event_outlined,
                                onTap: () => _selectDate('appointment'),
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Date of Confirmation
                              _buildDateField(
                                label: 'Date of Confirmation',
                                value: _formatDate(_dateOfConfirmation),
                                icon: Icons.verified_outlined,
                                onTap: () => _selectDate('confirmation'),
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Date of Retirement
                              _buildDateField(
                                label: 'Date of Retirement',
                                value: _formatDate(_dateOfRetirement),
                                icon: Icons.event_busy_outlined,
                                onTap: () => _selectDate('retirement'),
                              ),
                              
                              const SizedBox(height: AppTheme.spacingLG),
                              
                              // Government Quarter
                              _buildToggleField(
                                label: 'Government Quarter',
                                value: _govtQuarter,
                                onChanged: (value) {
                                  setState(() {
                                    _govtQuarter = value;
                                  });
                                },
                              ),
                              
                              const SizedBox(height: AppTheme.spacing2XL),
                              
                              // Save Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: (_saving || _uploadingPhoto) ? null : _saveProfile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: (_saving || _uploadingPhoto)
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.white),
                                          ),
                                        )
                                      : const Text(
                                          'Save Profile',
                                          style: TextStyle(
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
          if (!widget.isCompleteProfile && !_isProfileIncomplete)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppTheme.text, size: 22),
              onPressed: () => Navigator.pop(context),
            )
          else
            const SizedBox(width: 48),
          Expanded(
          child: Center(
            child: Text(
              (widget.isCompleteProfile || _isProfileIncomplete) ? 'Complete Profile' : 'Edit Profile',
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

  Widget _buildProfilePictureSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: _showImageSourceDialog,
          child: Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.borderLight,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  color: AppTheme.backgroundDark,
                ),
                child: ClipOval(
                  child: _selectedImage != null
                      ? Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildPlaceholderAvatar();
                          },
                        )
                      : _photoUrl != null && _photoUrl!.isNotEmpty && !_photoUrl!.startsWith('/')
                          ? Image.network(
                              _photoUrl!,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return _buildPlaceholderAvatar();
                              },
                            )
                          : _buildPlaceholderAvatar(),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 16,
                    color: AppTheme.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        Text(
          'Change profile photo',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderAvatar() {
    final name = _nameController.text.trim();
    final initial = name.isNotEmpty
        ? name[0].toUpperCase()
        : 'U';
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
      ),
      child: Center(
        child: Icon(
          Icons.person,
          size: 50,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? hintText,
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
        hintText: hintText,
        labelStyle: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 15,
        ),
        hintStyle: const TextStyle(
          color: AppTheme.textLight,
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

  Widget _buildDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLG,
          vertical: AppTheme.spacingMD,
        ),
      ),
      items: items,
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 15,
        color: AppTheme.text,
      ),
      dropdownColor: AppTheme.white,
      icon: const Icon(
        Icons.keyboard_arrow_down,
        color: AppTheme.textSecondary,
        size: 20,
      ),
      borderRadius: BorderRadius.circular(AppTheme.radiusBase),
    );
  }

  Widget _buildDateField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final hasValue = value != 'Select date';
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
            Icon(icon, size: 20, color: AppTheme.textSecondary),
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
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: hasValue ? AppTheme.text : AppTheme.textLight,
                    ),
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

  Widget _buildToggleField({
    required String label,
    required bool? value,
    required Function(bool?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: value,
              onChanged: (val) => onChanged(val),
              activeColor: AppTheme.primary,
            ),
            const SizedBox(width: AppTheme.spacingXS),
            const Text(
              'Yes',
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(width: AppTheme.spacingLG),
            Radio<bool>(
              value: false,
              groupValue: value,
              onChanged: (val) => onChanged(val),
              activeColor: AppTheme.primary,
            ),
            const SizedBox(width: AppTheme.spacingXS),
            const Text(
              'No',
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.text,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
