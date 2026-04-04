import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import 'project_detail_screen.dart';
import 'project_submission_screen.dart';
import '../utils/user_friendly_errors.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  late AnimationController _skeletonAnimationController;
  late Animation<double> _skeletonOpacity;
  bool _showSearchIcon = false;
  bool _loading = false;
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _filteredProjects = [];
  String? _userCollegeId;

  @override
  void initState() {
    super.initState();
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
    _loadProjects();
  }

  @override
  void dispose() {
    _skeletonAnimationController.dispose();
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
      _filterProjects();
    });
  }

  void _filterProjects() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredProjects = _projects;
    } else {
      _filteredProjects = _projects.where((project) {
        final name = (project['name'] ?? '').toString().toLowerCase();
        final description = (project['description'] ?? '').toString().toLowerCase();
        return name.contains(query) || description.contains(query);
      }).toList();
    }
  }

  Future<void> _loadProjects() async {
    setState(() {
      _loading = true;
    });
    
    try {
      // Get current user to filter by college
      final user = await _authService.getCurrentUser();
      _userCollegeId = user?.collegeId;
      
      // Fetch projects from Firebase
      final projects = await _firestoreService.getProjects(
        collegeId: _userCollegeId,
      );
      
      setState(() {
        _projects = projects;
        _filteredProjects = projects;
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
          SnackBar(content: Text(UserFriendlyErrors.message(e))),
        );
      }
    }
  }

  Color _getStatusBackground(String? status) {
    switch (status) {
      case 'Ongoing':
        return const Color(0xFFD97706);
      case 'Completed':
        return AppTheme.primary;
      case 'On Hold':
        return const Color(0xFF37474F);
      default:
        return const Color(0xFF263238);
    }
  }

  void _handleProjectPress(Map<String, dynamic> project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailScreen(project: project),
      ),
    );
  }

  void _handleSubmitPress(Map<String, dynamic> project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectSubmissionScreen(project: project),
      ),
    ).then((_) => _loadProjects());
  }

  Future<void> _handleRefresh() async {
    await _loadProjects();
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
                onRefresh: _handleRefresh,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                  // Search
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingLG),
                      child: _buildSearchBar(),
                    ),
                  ),
                  
                  // Projects List
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                    sliver: _loading
                        ? SliverToBoxAdapter(
                            child: _buildSkeleton(),
                          )
                        : _filteredProjects.isEmpty
                            ? SliverToBoxAdapter(
                                child: _buildEmptyState(),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final project = _filteredProjects[index];
                                    return _buildProjectCard(project);
                                  },
                                  childCount: _filteredProjects.length,
                                ),
                              ),
                  ),
                  
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 90),
                  ),
                ],
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
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Projects',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
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
          hintText: 'Search projects',
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

  Widget _buildProjectCard(Map<String, dynamic> project) {
    final status = project['status'] as String?;
    final isCompleted = status?.toLowerCase() == 'completed';
    
    return GestureDetector(
      onTap: () => _handleProjectPress(project),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
        padding: const EdgeInsets.all(AppTheme.spacingMD),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          border: Border.all(color: AppTheme.borderLight, width: 0.5),
          boxShadow: AppTheme.shadowSM,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project['name'] ?? 'Untitled Project',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppTheme.spacingXS),
                          Text(
                            project['description'] ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMD),
                    if (status != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingSM,
                          vertical: 4,
                        ),
                        constraints: const BoxConstraints(minWidth: 70),
                        decoration: BoxDecoration(
                          color: _getStatusBackground(status),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMD),
                Row(
                  children: [
                    const Icon(Icons.description, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: AppTheme.spacingXS),
                    Text(
                      '${project['submissionsCount'] ?? 0} submissions',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (!isCompleted)
              Positioned(
                bottom: AppTheme.spacingMD,
                right: AppTheme.spacingMD,
                child: GestureDetector(
                  onTap: () => _handleSubmitPress(project),
                  child: Container(
                    width: 32,
                    height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    child: const Icon(
                      Icons.add,
                      size: 16,
                      color: AppTheme.white,
                    ),
                  ),
                ),
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
            Icons.list,
            size: 64,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: AppTheme.spacingLG),
          Text(
            _searchController.text.trim().isNotEmpty
                ? 'No matching projects'
                : 'No projects found',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          const Text(
            'Projects will appear here once assigned',
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
              padding: const EdgeInsets.all(AppTheme.spacingMD),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                border: Border.all(color: AppTheme.borderLight, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxWidth: 200),
                              height: 18,
                              decoration: BoxDecoration(
                                color: AppTheme.borderLight,
                                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacingXS),
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxWidth: 250),
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppTheme.borderLight,
                                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingMD),
                      Container(
                        width: 70,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppTheme.borderLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingMD),
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMD),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.borderLight,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ),
        );
      },
    );
  }
}
