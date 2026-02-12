import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  late TabController _tabController;
  late AnimationController _skeletonAnimationController;
  late Animation<double> _skeletonOpacity;
  bool _showSearchIcon = false;
  bool _loading = false;
  List<Map<String, dynamic>> _invitations = [];
  List<Map<String, dynamic>> _filteredInvitations = [];
  String? _userId;
  Map<String, dynamic>? _selectedInvitation;
  bool _showInfoModal = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _skeletonAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _skeletonOpacity = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _skeletonAnimationController, curve: Curves.easeInOut),
    );
    _skeletonAnimationController.repeat(reverse: true);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _loadInvitations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _skeletonAnimationController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      _filterInvitations();
    });
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
      _filterInvitations();
    });
  }

  void _filterInvitations() {
    final query = _searchController.text.trim().toLowerCase();
    final isPendingTab = _tabController.index == 0;
    
    List<Map<String, dynamic>> baseList = _invitations.where((inv) {
      if (isPendingTab) {
        return (inv['status'] ?? 'pending') == 'pending';
      } else {
        return (inv['status'] ?? 'pending') != 'pending';
      }
    }).toList();
    
    if (query.isEmpty) {
      _filteredInvitations = baseList;
    } else {
      _filteredInvitations = baseList.where((inv) {
        final title = (inv['title'] ?? '').toString().toLowerCase();
        final subtitle = (inv['subtitle'] ?? inv['message'] ?? '').toString().toLowerCase();
        final venue = (inv['venue'] ?? '').toString().toLowerCase();
        return title.contains(query) || subtitle.contains(query) || venue.contains(query);
      }).toList();
    }
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _loading = true;
    });
    
    try {
      final user = await _authService.getCurrentUser();
      _userId = user?.uid;
      
      if (_userId == null) {
        setState(() {
          _loading = false;
        });
        return;
      }
      
      final notifications = await _firestoreService.getNotifications(_userId!);
      
      // Filter for invitations only and transform data
      final invitations = notifications.where((notif) {
        return notif['type'] == 'invitation';
      }).map((notif) {
        return {
          'id': notif['id'],
          'title': notif['title'] ?? 'Untitled Invitation',
          'subtitle': notif['message'] ?? '',
          'venue': notif['venue'] ?? 'TBA',
          'date': notif['date'] ?? 'TBA',
          'time': notif['time'] ?? 'TBA',
          'locationLink': notif['locationLink'] ?? '',
          'status': notif['status'] ?? 'pending',
          'createdAt': notif['createdAt'],
          'responses': notif['responses'] ?? {},
        };
      }).toList();
      
      // Sort by createdAt descending
      invitations.sort((a, b) {
        final dateA = a['createdAt'];
        final dateB = b['createdAt'];
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        try {
          final aTime = dateA is Timestamp ? dateA.toDate().millisecondsSinceEpoch : 0;
          final bTime = dateB is Timestamp ? dateB.toDate().millisecondsSinceEpoch : 0;
          return bTime.compareTo(aTime);
        } catch (e) {
          return 0;
        }
      });
      
      setState(() {
        _invitations = invitations;
        _filterInvitations();
        _loading = false;
      });
      _skeletonAnimationController.stop();
    } catch (e) {
      setState(() {
        _loading = false;
      });
      _skeletonAnimationController.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading invitations: $e')),
        );
      }
    }
  }

  Future<void> _handleAcceptInvitation(Map<String, dynamic> invitation) async {
    if (_userId == null) return;
    
    try {
      await _firestoreService.updateInvitationResponse(
        invitation['id'],
        _userId!,
        'accepted',
      );
      
      setState(() {
        final index = _invitations.indexWhere((inv) => inv['id'] == invitation['id']);
        if (index != -1) {
          _invitations[index]['status'] = 'accepted';
          final responses = Map<String, dynamic>.from(_invitations[index]['responses'] ?? {});
          responses[_userId!] = {
            'status': 'accepted',
            'respondedAt': DateTime.now().toIso8601String(),
            'respondedBy': _userId!,
          };
          _invitations[index]['responses'] = responses;
          _filterInvitations();
        }
        if (_selectedInvitation?['id'] == invitation['id']) {
          _selectedInvitation = _invitations[index];
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accepted invitation to "${invitation['title']}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept invitation: $e')),
        );
      }
    }
  }

  Future<void> _handleDeclineInvitation(Map<String, dynamic> invitation) async {
    if (_userId == null) return;
    
    try {
      await _firestoreService.updateInvitationResponse(
        invitation['id'],
        _userId!,
        'declined',
      );
      
      setState(() {
        final index = _invitations.indexWhere((inv) => inv['id'] == invitation['id']);
        if (index != -1) {
          _invitations[index]['status'] = 'declined';
          final responses = Map<String, dynamic>.from(_invitations[index]['responses'] ?? {});
          responses[_userId!] = {
            'status': 'declined',
            'respondedAt': DateTime.now().toIso8601String(),
            'respondedBy': _userId!,
          };
          _invitations[index]['responses'] = responses;
          _filterInvitations();
        }
        if (_selectedInvitation?['id'] == invitation['id']) {
          _selectedInvitation = _invitations[index];
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Declined invitation to "${invitation['title']}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decline invitation: $e')),
        );
      }
    }
  }

  Future<void> _handleLocationPress(String? locationLink) async {
    if (locationLink == null || locationLink.isEmpty) return;
    
    try {
      final uri = Uri.parse(locationLink);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open location link')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open location link')),
        );
      }
    }
  }

  void _handleInvitationPress(Map<String, dynamic> invitation) {
    setState(() {
      _selectedInvitation = invitation;
      _showInfoModal = true;
    });
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'accepted':
        return AppTheme.primary;
      case 'declined':
        return AppTheme.error;
      case 'pending':
        return AppTheme.warning;
      default:
        return AppTheme.textSecondary;
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
      child: SafeArea(
        child: Scaffold(
          backgroundColor: AppTheme.white,
          body: Stack(
          children: [
            Column(
              children: [
                // Header
                _buildHeader(),
                
                // Tabs
                _buildTabs(),
                
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
                      
                      // Invitations List
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                        sliver: _loading
                            ? SliverToBoxAdapter(
                                child: _buildSkeleton(),
                              )
                            : _filteredInvitations.isEmpty
                                ? SliverToBoxAdapter(
                                    child: _buildEmptyState(),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final invitation = _filteredInvitations[index];
                                        final isLast = index == _filteredInvitations.length - 1;
                                        return _buildInvitationCard(invitation, isLast);
                                      },
                                      childCount: _filteredInvitations.length,
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
            
            // Info Modal
            if (_showInfoModal && _selectedInvitation != null) _buildInfoModal(),
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
                'Invitations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
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
                  Future.delayed(const Duration(milliseconds: 350), () {
                    FocusScope.of(context).requestFocus(FocusNode());
                  });
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
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
      child: Row(
        children: [
          Expanded(
            child: _buildTab('Pending', 0),
          ),
          const SizedBox(width: AppTheme.spacingSM),
          Expanded(
            child: _buildTab('Older', 1),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppTheme.spacingSM,
          horizontal: AppTheme.spacingLG,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : AppTheme.backgroundDark,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? AppTheme.white : AppTheme.text,
          ),
        ),
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
          hintText: 'Search invitations',
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

  Widget _buildInvitationCard(Map<String, dynamic> invitation, bool isLast) {
    final status = invitation['status'] ?? 'pending';
    
    return GestureDetector(
      onTap: () => _handleInvitationPress(invitation),
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : AppTheme.spacingMD),
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
            // Title and Subtitle
            Text(
              invitation['title'] ?? 'Invitation',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.text,
                height: 1.2,
              ),
            ),
            if (invitation['subtitle'] != null && invitation['subtitle'].toString().isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingXS),
              Text(
                invitation['subtitle'],
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            
            const SizedBox(height: AppTheme.spacingMD),
            
            // Event Details
            _buildDetailRow(Icons.location_on, invitation['venue'] ?? 'TBA'),
            const SizedBox(height: AppTheme.spacingXS),
            _buildDetailRow(
              Icons.calendar_today,
              '${invitation['date'] ?? 'TBA'} at ${invitation['time'] ?? 'TBA'}',
            ),
            
            if (invitation['locationLink'] != null && invitation['locationLink'].toString().isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingXS),
              GestureDetector(
                onTap: () => _handleLocationPress(invitation['locationLink']),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spacingSM,
                    horizontal: AppTheme.spacingMD,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                    border: Border.all(
                      color: AppTheme.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, size: 16, color: AppTheme.primary),
                      const SizedBox(width: AppTheme.spacingXS),
                      const Text(
                        'Open in Maps',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: AppTheme.spacingLG),
            
            // Action Buttons or Status Badge
            if (status == 'pending')
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      'Accept',
                      AppTheme.primary,
                      AppTheme.white,
                      Icons.check,
                      () => _handleAcceptInvitation(invitation),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingBase),
                  Expanded(
                    child: _buildActionButton(
                      'Decline',
                      AppTheme.white,
                      AppTheme.error,
                      Icons.close,
                      () => _handleDeclineInvitation(invitation),
                      isOutlined: true,
                    ),
                  ),
                ],
              )
            else
              _buildStatusBadge(status),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: AppTheme.spacingSM),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    Color backgroundColor,
    Color textColor,
    IconData icon,
    VoidCallback onPressed, {
    bool isOutlined = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
        decoration: BoxDecoration(
          color: isOutlined ? backgroundColor : backgroundColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          border: isOutlined ? Border.all(color: textColor, width: 1) : Border.all(color: AppTheme.borderLight, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: AppTheme.spacingXS),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.spacingSM,
        horizontal: AppTheme.spacingMD,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppTheme.spacingXS),
          Text(
            status.substring(0, 1).toUpperCase() + status.substring(1),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing5XL),
      child: Column(
        children: [
          const Icon(
            Icons.mail_outline,
            size: 64,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: AppTheme.spacingLG),
          Text(
            _searchController.text.trim().isNotEmpty
                ? 'No matching invitations'
                : 'No invitations',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          const Text(
            'You\'ll see invitations here when they arrive',
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
    return AnimatedBuilder(
      animation: _skeletonOpacity,
      builder: (context, child) {
        return Opacity(
          opacity: _skeletonOpacity.value,
          child: Column(
            children: List.generate(3, (index) => Container(
              margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
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
                  Container(
                    width: '70%'.length * 10,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                  Container(
                    width: '90%'.length * 10,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMD),
                  Container(
                    width: '60%'.length * 10,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.borderLight,
                          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingBase),
                      Container(
                        width: 80,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.borderLight,
                          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )),
          ),
        );
      },
    );
  }

  Widget _buildInfoModal() {
    final invitation = _selectedInvitation!;
    final status = invitation['status'] ?? 'pending';
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _showInfoModal = false;
        });
      },
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when tapping inside
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
                maxWidth: 500,
              ),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingLG),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            invitation['title'] ?? 'Invitation',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.text,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.text, size: 22),
                          onPressed: () {
                            setState(() {
                              _showInfoModal = false;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppTheme.spacingLG),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Subtitle
                          if (invitation['subtitle'] != null && invitation['subtitle'].toString().isNotEmpty) ...[
                            Text(
                              invitation['subtitle'],
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacingLG),
                          ],
                          
                          // Event Information Card
                          Container(
                            padding: const EdgeInsets.all(AppTheme.spacingLG),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundDark,
                              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                            ),
                            child: Column(
                              children: [
                                _buildModalInfoRow(
                                  Icons.location_on_outlined,
                                  'Venue',
                                  invitation['venue'] ?? 'TBA',
                                ),
                                const SizedBox(height: AppTheme.spacingMD),
                                _buildModalInfoRow(
                                  Icons.calendar_today_outlined,
                                  'Date',
                                  invitation['date'] ?? 'TBA',
                                ),
                                const SizedBox(height: AppTheme.spacingMD),
                                _buildModalInfoRow(
                                  Icons.access_time_outlined,
                                  'Time',
                                  invitation['time'] ?? 'TBA',
                                ),
                              ],
                            ),
                          ),
                          
                          // Location Link
                          if (invitation['locationLink'] != null && invitation['locationLink'].toString().isNotEmpty) ...[
                            const SizedBox(height: AppTheme.spacingLG),
                            GestureDetector(
                              onTap: () {
                                _handleLocationPress(invitation['locationLink']);
                                setState(() {
                                  _showInfoModal = false;
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppTheme.spacingMD,
                                  horizontal: AppTheme.spacingLG,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                  border: Border.all(
                                    color: AppTheme.primary.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.primary),
                                    const SizedBox(width: AppTheme.spacingXS),
                                    const Text(
                                      'Open Location in Maps',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: AppTheme.spacingLG),
                          
                          // Status Badge
                          Center(
                            child: _buildStatusBadge(status),
                          ),
                          
                          // Action Buttons for Pending
                          if (status == 'pending') ...[
                            const SizedBox(height: AppTheme.spacingLG),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  _handleAcceptInvitation(invitation);
                                  setState(() {
                                    _showInfoModal = false;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check, size: 20, color: AppTheme.white),
                                    SizedBox(width: AppTheme.spacingSM),
                                    Text(
                                      'Accept Invitation',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacingMD),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  _handleDeclineInvitation(invitation);
                                  setState(() {
                                    _showInfoModal = false;
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                                  side: const BorderSide(color: AppTheme.error, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.close, size: 20, color: AppTheme.error),
                                    SizedBox(width: AppTheme.spacingSM),
                                    Text(
                                      'Decline Invitation',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: AppTheme.spacingMD),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
