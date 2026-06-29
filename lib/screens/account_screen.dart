import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/firebase_auth_service.dart';
import 'web_view_screen.dart';
import 'support_screen.dart';
import 'contact_us_screen.dart';
import 'delete_account_screen.dart';
import 'edit_profile_screen.dart';
import 'welcome_screen.dart';
import '../utils/user_friendly_errors.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  String _userName = 'User Name';
  String _userEmail = 'mk@gmail.com';
  String _userRole = 'Employee';
  String _userInitial = 'U';
  String? _photoUrl;
  bool _loading = false;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoadingProfile = true;
    });
    
    try {
      final user = await _authService.getCurrentUser();
      if (user != null && mounted) {
        setState(() {
          _userName = user.name;
          _userEmail = user.email;
          _userRole = _formatRole(user.role);
          _userInitial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U';
          _photoUrl = user.photoUrl;
          _isLoadingProfile = false;
        });
      } else {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
      });
    }
  }

  String _formatRole(String role) {
    return role
        .split('-')
        .map((word) => word.isEmpty 
            ? '' 
            : word[0].toUpperCase() + word.substring(1))
        .join(' ');
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
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadUserProfile,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _buildHeader(),
                  
                  // Profile Card
                  _buildProfileCard(),
                  
                  // Quick Actions
                  _buildQuickActions(context),
                  
                  // Sign Out Button
                  _buildSignOutButton(context),
                  
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLG,
        AppTheme.spacingXL,
        AppTheme.spacingLG,
        AppTheme.spacingBase,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS),
          const Text(
            'Manage your profile and settings',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    if (_isLoadingProfile) {
      return Container(
        margin: const EdgeInsets.only(
          top: AppTheme.spacingBase,
          left: AppTheme.spacingLG,
          right: AppTheme.spacingLG,
        ),
        padding: const EdgeInsets.all(AppTheme.spacingBase),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(color: AppTheme.borderLight, width: 0.5),
          boxShadow: AppTheme.shadowSM,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.backgroundDark,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppTheme.spacingBase),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 16,
                    width: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundDark,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 14,
                    width: 180,
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundDark,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(
        top: AppTheme.spacingBase,
        left: AppTheme.spacingLG,
        right: AppTheme.spacingLG,
      ),
      padding: const EdgeInsets.all(AppTheme.spacingBase),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              image: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(_photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _photoUrl != null && _photoUrl!.isNotEmpty
                ? null
                : Center(
                    child: Text(
                      _userInitial,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.white,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppTheme.spacingBase),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (_userRole.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spacingXS),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingSM,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                    ),
                    child: Text(
                      _userRole,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(
        id: 'edit-profile',
        label: 'Edit Profile',
        icon: Icons.edit,
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EditProfileScreen(),
            ),
          );
          if (result == true) {
            _loadUserProfile();
          }
        },
      ),
      _QuickAction(
        id: 'support',
        label: 'Support / Helpdesk',
        icon: Icons.settings,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SupportScreen()),
          );
        },
      ),
      _QuickAction(
        id: 'privacy',
        label: 'Privacy Policy',
        icon: Icons.shield,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const WebViewScreen(
                title: 'Privacy Policy',
                url: 'https://heart.nititechnologies.in/privacy-policy',
              ),
            ),
          );
        },
      ),
      _QuickAction(
        id: 'terms',
        label: 'Terms of Service',
        icon: Icons.description,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const WebViewScreen(
                title: 'Terms of Service',
                url: 'https://heart.nititechnologies.in/terms-and-conditions',
              ),
            ),
          );
        },
      ),
      _QuickAction(
        id: 'contact',
        label: 'Contact Us',
        icon: Icons.phone,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ContactUsScreen()),
          );
        },
      ),
      _QuickAction(
        id: 'delete',
        label: 'Delete Account',
        icon: Icons.delete,
        destructive: true,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DeleteAccountScreen()),
          );
        },
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLG,
        AppTheme.spacingLG,
        AppTheme.spacingLG,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
              border: Border.all(color: AppTheme.borderLight, width: 0.5),
          boxShadow: AppTheme.shadowSM,
            ),
            child: Column(
              children: actions.map((action) {
                final isLast = action.id == actions.last.id;
                return _buildQuickActionItem(context, action, isLast);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem(
    BuildContext context,
    _QuickAction action,
    bool isLast,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        child: Container(
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(
                    bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
                  ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingBase,
            vertical: 14,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: action.destructive
                      ? const Color(0x14FF0000)
                      : const Color(0x1AA0D9D9),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  action.icon,
                  size: 18,
                  color: action.destructive
                      ? const Color(0xFFFF0000)
                      : AppTheme.primary,
                ),
              ),
              const SizedBox(width: AppTheme.spacingSM),
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: action.destructive
                        ? const Color(0xFFFF0000)
                        : AppTheme.text,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: action.destructive
                    ? const Color(0xFFFF0000)
                    : AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLG,
        AppTheme.spacingXL,
        AppTheme.spacingLG,
        AppTheme.spacingLG,
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _loading ? null : () => _handleSignOut(context),
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.white),
                  ),
                )
              : const Icon(Icons.logout, color: AppTheme.white, size: 20),
          label: Text(
            _loading ? 'Signing out...' : 'Sign Out',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            disabledBackgroundColor: AppTheme.primary.withOpacity(0.6),
            padding: const EdgeInsets.symmetric(
              vertical: AppTheme.spacingMD,
              horizontal: AppTheme.spacingBase,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  void _handleSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        ),
        title: const Text(
          'Sign Out',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.text,
          ),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                _loading = true;
              });
              
              try {
                await _authService.signOut();
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(UserFriendlyErrors.message(e)),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _loading = false;
                  });
                }
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.error,
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  _QuickAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });
}
