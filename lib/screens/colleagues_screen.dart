import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';


class ColleaguesScreen extends StatefulWidget {
  const ColleaguesScreen({super.key});

  @override
  State<ColleaguesScreen> createState() => _ColleaguesScreenState();
}

class _ColleaguesScreenState extends State<ColleaguesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _showSearchIcon = false;
  bool _loading = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  String? _userCollegeId;
  String? _currentUserRole;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _loadUsers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
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

  void _onSearchChanged() {
    setState(() {
      _filterUsers();
    });
  }

  void _filterUsers() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredUsers = _users;
    } else {
      _filteredUsers = _users.where((user) {
        final name = (user['name'] ?? '').toString().toLowerCase();
        final email = (user['email'] ?? '').toString().toLowerCase();
        final role = (user['role'] ?? '').toString().toLowerCase();
        return name.contains(query) || email.contains(query) || role.contains(query);
      }).toList();
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
    });
    
    try {
      // Get current user to filter by college
      final user = await _authService.getCurrentUser();
      _userCollegeId = user?.collegeId;
      _currentUserRole = user?.role;
      _currentUserId = user?.uid;
      
      // Fetch users from Firebase
      final users = await _firestoreService.getUsers(collegeId: _userCollegeId);
      
      // Convert UserProfile to Map for display, include current user
      setState(() {
        _users = users
            .map((u) => <String, dynamic>{
              'id': u.uid,
              'name': u.name,
              'email': u.email,
              'role': u.role,
              'active': u.active ?? true,
              'photoUrl': u.photoUrl,
              'phoneNumber': u.phoneNumber,
              'employmentType': u.employmentType,
              'payBand': u.payBand,
              'dateOfAppointment': u.dateOfAppointment?.toIso8601String(),
              'dateOfConfirmation': u.dateOfConfirmation?.toIso8601String(),
              'dateOfRetirement': u.dateOfRetirement?.toIso8601String(),
              'dateOfBirth': u.dateOfBirth?.toIso8601String(),
              'govtQuarter': u.govtQuarter,
              'profileCompleted': u.profileCompleted,
            })
            .toList();
        
        // Sort by role hierarchy: Principal > Vice-Principal > Others, then alphabetically
        _users.sort((a, b) {
          final aActive = a['active'] ?? true;
          final bActive = b['active'] ?? true;
          final aRole = (a['role'] ?? '').toString().toLowerCase();
          final bRole = (b['role'] ?? '').toString().toLowerCase();
          final aName = (a['name'] ?? '').toString();
          final bName = (b['name'] ?? '').toString();
          
          // Helper function to get role priority (lower = higher priority)
          int getRolePriority(String role) {
            if (role == 'principal') return 1;
            if (role == 'vice-principal') return 2;
            return 3; // All other roles
          }
          
          // First sort by active status
          if (aActive != bActive) {
            return aActive ? -1 : 1;
          }
          
          // Then by role hierarchy
          final aPriority = getRolePriority(aRole);
          final bPriority = getRolePriority(bRole);
          if (aPriority != bPriority) {
            return aPriority.compareTo(bPriority);
          }
          
          // Finally by name alphabetically
          return aName.compareTo(bName);
        });
        
        _filteredUsers = List.from(_users);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading colleagues: $e')),
        );
      }
    }
  }

  void _handleUserPress(Map<String, dynamic> user) {
    if (_currentUserRole?.toLowerCase() == 'principal') {
      _showUserStatusModal(user);
    }
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final userId = user['id'];
    final currentStatus = user['active'] ?? true;
    final newStatus = !currentStatus;
    
    // Optimistically update UI
    setState(() {
      final index = _users.indexWhere((u) => u['id'] == userId);
      if (index != -1) {
        _users[index]['active'] = newStatus;
      }
      final filteredIndex = _filteredUsers.indexWhere((u) => u['id'] == userId);
      if (filteredIndex != -1) {
        _filteredUsers[filteredIndex]['active'] = newStatus;
      }
    });

    // Close the modal
    Navigator.pop(context);
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'active': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${newStatus ? 'activated' : 'deactivated'} successfully'),
          ),
        );
      }
    } catch (e) {
      // Revert on error
      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index]['active'] = currentStatus;
        }
        final filteredIndex = _filteredUsers.indexWhere((u) => u['id'] == userId);
        if (filteredIndex != -1) {
          _filteredUsers[filteredIndex]['active'] = currentStatus;
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update user status: $e')),
        );
      }
    }
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
              // Header
              _buildHeader(),
            
            // Content
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Search
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingLG),
                      child: _buildSearchBar(),
                    ),
                  ),
                  
                  // Users List
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                    sliver: _loading
                        ? SliverToBoxAdapter(
                            child: _buildSkeleton(),
                          )
                        : _filteredUsers.isEmpty
                            ? SliverToBoxAdapter(
                                child: _buildEmptyState(),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final user = _filteredUsers[index];
                                    return _buildUserCard(user);
                                  },
                                  childCount: _filteredUsers.length,
                                ),
                              ),
                  ),
                  
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 90),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  void _showUserStatusModal(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          final isActive = user['active'] ?? true;
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
                        'User Status',
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile Section
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: AppTheme.shadowBase,
                                  border: Border.all(color: AppTheme.white, width: 4),
                                  image: user['photoUrl'] != null && (user['photoUrl'] as String).isNotEmpty
                                      ? DecorationImage(
                                          image: NetworkImage(user['photoUrl'] as String),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: user['photoUrl'] != null && (user['photoUrl'] as String).isNotEmpty
                                    ? null
                                    : Center(
                                        child: Text(
                                          (user['name'] ?? 'U')[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 40,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.white,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: AppTheme.spacingMD),
                              Text(
                                user['name'] ?? 'User',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.text,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacingXS),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.spacingMD,
                                  vertical: AppTheme.spacingXS,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryLight,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                                ),
                                child: Text(
                                  user['role'] ?? 'Not specified',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: AppTheme.spacingXL),
                        
                        // Basic Info
                        _buildInfoSection('Basic Information', [
                          _buildInfoRow('Name', user['name'] ?? 'Not provided', Icons.person_outline),
                          _buildInfoRow('Email', user['email'] ?? 'Not provided', Icons.email_outlined),
                          _buildInfoRow('Phone', user['phoneNumber'] ?? 'Not provided', Icons.phone_outlined),
                        ]),
                        
                        const SizedBox(height: AppTheme.spacingLG),

                        // Employment Details
                        _buildInfoSection('Employment Details', [
                          _buildInfoRow('Employment Type', user['employmentType'] ?? 'Not specified', Icons.work_outline),
                          _buildInfoRow('Pay Band', user['payBand'] ?? 'Not specified', Icons.attach_money),
                          if (user['dateOfAppointment'] != null)
                            _buildInfoRow('Date of Appointment', _formatDate(user['dateOfAppointment']), Icons.calendar_today_outlined),
                          if (user['dateOfConfirmation'] != null)
                            _buildInfoRow('Date of Confirmation', _formatDate(user['dateOfConfirmation']), Icons.verified_user_outlined),
                          if (user['dateOfRetirement'] != null)
                            _buildInfoRow('Date of Retirement', _formatDate(user['dateOfRetirement']), Icons.event_busy_outlined),
                          _buildInfoRow('Government Quarter', user['govtQuarter'] == true ? 'Yes' : 'No', Icons.home_outlined),
                        ]),
                        
                        const SizedBox(height: AppTheme.spacingLG),

                        // Status Information
                        _buildInfoSection('Status Information', [
                          Container(
                            padding: const EdgeInsets.all(AppTheme.spacingMD),
                            decoration: BoxDecoration(
                              color: isActive ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                              border: Border.all(
                                color: isActive ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isActive ? Icons.check_circle_outline : Icons.block_outlined,
                                      color: isActive ? AppTheme.success : AppTheme.error,
                                      size: 20,
                                    ),
                                    const SizedBox(width: AppTheme.spacingSM),
                                    Text(
                                      'Current Status',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isActive ? AppTheme.success : AppTheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacingSM,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive ? AppTheme.success : AppTheme.error,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingSM),
                          _buildInfoRow('Profile Completed', user['profileCompleted'] == true ? 'Yes' : 'No', Icons.assignment_turned_in_outlined),
                        ]),
                      ],
                    ),
                  ),
                ),
                
                // Actions
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
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            side: const BorderSide(color: AppTheme.borderLight),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingMD),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: user['id'] == _currentUserId ? null : () {
                             _toggleUserStatus(user);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isActive ? AppTheme.error : AppTheme.success,
                            disabledBackgroundColor: AppTheme.textSecondary.withValues(alpha: 0.3),
                            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                            ),
                          ),
                          child: Text(
                            user['id'] == _currentUserId 
                              ? 'You' 
                              : (isActive ? 'Deactivate' : 'Activate'),
                            style: TextStyle(
                              color: user['id'] == _currentUserId ? AppTheme.textSecondary : AppTheme.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return isoString;
    }
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text( // Only showing the first line to verify replacement
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingMD),
        ...children,
        const SizedBox(height: AppTheme.spacingLG),
        const Divider(height: 1, color: AppTheme.borderLight),
        const SizedBox(height: AppTheme.spacingLG),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, [IconData? icon]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: Icon(icon, size: 20, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: AppTheme.spacingMD),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.text,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Colleagues',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          if (_showSearchIcon)
            AnimatedOpacity(
              opacity: _showSearchIcon ? 1.0 : 0.0,
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
                    Icons.search,
                    size: 20,
                    color: AppTheme.text,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search colleagues',
          hintStyle: const TextStyle(color: AppTheme.textSecondary),
          prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppTheme.white),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMD,
            vertical: AppTheme.spacingMD,
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isActive = user['active'] ?? true;
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      padding: const EdgeInsets.all(AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
        boxShadow: AppTheme.shadowSM,
      ),
      child: GestureDetector(
        onTap: () => _handleUserPress(user),
        child: Row(
          children: [
            // Avatar
            Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  image: user['photoUrl'] != null && (user['photoUrl'] as String).isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(user['photoUrl'] as String),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: user['photoUrl'] != null && (user['photoUrl'] as String).isNotEmpty
                    ? null
                    : Center(
                        child: Text(
                          (user['name'] ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.white,
                          ),
                        ),
                      ),
              ),
              if (isActive)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(width: AppTheme.spacingMD),
          
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'] ?? 'User',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user['email'] ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user['role'] != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingSM,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                    child: Text(
                      user['role'],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Toggle Switch (for principal) or Arrow (for others)
          if (_currentUserRole == 'principal')
            Switch(
              value: isActive,
              onChanged: (value) {
                _handleUserPress(user);
              },
              activeTrackColor: AppTheme.primary,
            )
          else
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing5XL),
      child: Column(
        children: [
          const Icon(
            Icons.people,
            size: 64,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: AppTheme.spacingLG),
          Text(
            _searchController.text.trim().isNotEmpty
                ? 'No matching colleagues'
                : 'No colleagues found',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          const Text(
            'Colleagues will appear here',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(5, (index) => Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
        padding: const EdgeInsets.all(AppTheme.spacingMD),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          border: Border.all(color: AppTheme.borderLight, width: 0.5),
          boxShadow: AppTheme.shadowSM,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.borderLight,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppTheme.spacingMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: '60%'.length * 10,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: '80%'.length * 10,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      )),
    );
  }
}
