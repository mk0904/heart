import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/attendance_screen.dart';
import '../screens/projects_screen.dart';
import '../screens/circulars_screen.dart';
import '../screens/account_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../theme/app_theme.dart';

class MainTabNavigator extends StatefulWidget {
  final bool isActive;
  
  const MainTabNavigator({super.key, this.isActive = true});

  @override
  State<MainTabNavigator> createState() => _MainTabNavigatorState();
}

class _MainTabNavigatorState extends State<MainTabNavigator> {
  int _currentIndex = 0;

  List<Widget> get _screens => [
    HomeScreen(isActive: widget.isActive),
    const AttendanceScreen(),
    const ProjectsScreen(),
    const CircularsScreen(),
    const AccountScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // If inactive, default to Home tab (which will show the message)
    if (!widget.isActive) {
      _currentIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: _screens[_currentIndex],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: AppTheme.white,
              boxShadow: AppTheme.shadowBase,
            ),
            child: SafeArea(
              child: Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTabItem(0, Icons.home, 'Home'),
                    _buildTabItem(1, Icons.calendar_today, 'Attendance'),
                    _buildTabItem(2, Icons.list, 'Projects'),
                    _buildTabItem(3, Icons.description, 'Circulars'),
                    _buildTabItem(4, Icons.person, 'Account'),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Overlay blocker for inactive users (except when on Home or Account tab)
        if (!widget.isActive && _currentIndex != 0 && _currentIndex != 4)
          _buildInactiveOverlay(),
      ],
    );
  }

  Widget _buildInactiveOverlay() {
    return Container(
      color: Colors.white.withOpacity(0.95),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing2XL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 80,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: AppTheme.spacingXL),
              Text(
                'Account Inactive',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: AppTheme.spacingMD),
              Text(
                'Please get approval from admin to access this feature.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingXL),
              ElevatedButton(
                onPressed: () async {
                  // Navigate to Edit Profile - allowed even when inactive
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EditProfileScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingXL,
                    vertical: AppTheme.spacingMD,
                  ),
                ),
                child: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMD),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentIndex = 4; // Navigate to Account tab
                  });
                },
                child: Text(
                  'Go to Account',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final isHomeTab = index == 0;
    final isAccountTab = index == 4;
    final isEnabled = widget.isActive || isHomeTab || isAccountTab;
    
    return Expanded(
      child: GestureDetector(
        onTap: isEnabled
            ? () => setState(() => _currentIndex = index)
            : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: isSelected ? 26 : 24,
                  color: isSelected ? AppTheme.white : AppTheme.textSecondary,
                ),
              ),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
