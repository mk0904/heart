import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import '../models/user_profile.dart';

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
  Map<String, dynamic>? _selectedUser;
  bool _showToggleModal = false;

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
      
      // Convert UserProfile to Map for display, exclude current user
      setState(() {
        _users = users
            .where((u) => u.uid != _currentUserId)
            .map((u) => <String, dynamic>{
              'id': u.uid,
              'name': u.name,
              'email': u.email,
              'role': u.role,
              'active': u.active ?? true,
              'status': u.status ?? 'Active',
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
        
        // Sort: active users first, then by name
        _users.sort((a, b) {
          final aActive = a['active'] ?? a['status'] == 'Active';
          final bActive = b['active'] ?? b['status'] == 'Active';
          if (aActive == bActive) {
            return (a['name'] ?? '').compareTo(b['name'] ?? '');
          }
          return aActive ? -1 : 1;
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
    if (_currentUserRole == 'principal') {
      setState(() {
        _selectedUser = user;
        _showToggleModal = true;
      });
    }
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final userId = user['id'];
    final currentStatus = user['active'] ?? user['status'] == 'Active';
    final newStatus = !currentStatus;
    
    // Optimistically update UI
    setState(() {
      final index = _users.indexWhere((u) => u['id'] == userId);
      if (index != -1) {
        _users[index]['active'] = newStatus;
        _users[index]['status'] = newStatus ? 'Active' : 'Inactive';
      }
      final filteredIndex = _filteredUsers.indexWhere((u) => u['id'] == userId);
      if (filteredIndex != -1) {
        _filteredUsers[filteredIndex]['active'] = newStatus;
        _filteredUsers[filteredIndex]['status'] = newStatus ? 'Active' : 'Inactive';
      }
      _showToggleModal = false;
    });
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'active': newStatus,
        'status': newStatus ? 'Active' : 'Inactive',
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
          _users[index]['status'] = currentStatus ? 'Active' : 'Inactive';
        }
        final filteredIndex = _filteredUsers.indexWhere((u) => u['id'] == userId);
        if (filteredIndex != -1) {
          _filteredUsers[filteredIndex]['active'] = currentStatus;
          _filteredUsers[filteredIndex]['status'] = currentStatus ? 'Active' : 'Inactive';
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
    return SafeArea(
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppTheme.backgroundLight,
            body: Column(
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
          
          // Toggle Modal for Principals
          if (_showToggleModal && _selectedUser != null) _buildToggleModal(),
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
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Colleagues',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
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
            ),
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
    final isActive = user['active'] ?? user['status'] == 'Active';
    
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
                ),
                child: Center(
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
              activeColor: AppTheme.primary,
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

  Widget _buildToggleModal() {
    final user = _selectedUser!;
    final isActive = user['active'] ?? user['status'] == 'Active';
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _showToggleModal = false;
        });
      },
      child: Container(
        color: Colors.black54,
        child: DraggableScrollableSheet(
          initialChildSize: 0.8,
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
                  // Header
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingLG),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.borderLight, width: 1),
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
                          onPressed: () {
                            setState(() {
                              _showToggleModal = false;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  // User Info
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
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      (user['name'] ?? 'U')[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacingMD),
                                Text(
                                  user['name'] ?? 'User',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.text,
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacingXS),
                                Text(
                                  user['role'] ?? 'Not specified',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: AppTheme.spacingXL),
                          
                          // Basic Info
                          _buildInfoSection('Basic Information', [
                            _buildInfoRow('Name', user['name'] ?? 'Not provided'),
                            _buildInfoRow('Email', user['email'] ?? 'Not provided'),
                            _buildInfoRow('Phone', user['phoneNumber'] ?? 'Not provided'),
                            _buildInfoRow('Role', user['role'] ?? 'Not specified'),
                          ]),
                          
                          // Employment Details
                          _buildInfoSection('Employment Details', [
                            _buildInfoRow('Employment Type', user['employmentType'] ?? 'Not specified'),
                            _buildInfoRow('Pay Band', user['payBand'] ?? 'Not specified'),
                            if (user['dateOfAppointment'] != null)
                              _buildInfoRow('Date of Appointment', user['dateOfAppointment']),
                            if (user['dateOfConfirmation'] != null)
                              _buildInfoRow('Date of Confirmation', user['dateOfConfirmation']),
                            if (user['dateOfRetirement'] != null)
                              _buildInfoRow('Date of Retirement', user['dateOfRetirement']),
                            _buildInfoRow('Government Quarter', user['govtQuarter'] == true ? 'Yes' : 'No'),
                          ]),
                          
                          // Status Information
                          _buildInfoSection('Status Information', [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Current Status:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isActive ? AppTheme.primary : AppTheme.borderLight,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: AppTheme.spacingXS),
                                    Text(
                                      isActive ? 'Active' : 'Inactive',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            _buildInfoRow('Profile Completed', user['profileCompleted'] == true ? 'Yes' : 'No'),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  
                  // Actions
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingLG),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppTheme.borderLight, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _showToggleModal = false;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                              side: const BorderSide(color: AppTheme.borderLight),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingMD),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _toggleUserStatus(user),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                            ),
                            child: Text(
                              isActive ? 'Deactivate' : 'Activate',
                              style: const TextStyle(color: AppTheme.white),
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
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        ...children,
        const SizedBox(height: AppTheme.spacingLG),
        const Divider(height: 1, color: AppTheme.borderLight),
        const SizedBox(height: AppTheme.spacingLG),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.text,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
