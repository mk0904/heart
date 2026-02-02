import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import 'circular_detail_screen.dart';

class CircularsScreen extends StatefulWidget {
  const CircularsScreen({super.key});

  @override
  State<CircularsScreen> createState() => _CircularsScreenState();
}

class _CircularsScreenState extends State<CircularsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  late AnimationController _skeletonAnimationController;
  late Animation<double> _skeletonOpacity;
  bool _showSearchIcon = false;
  bool _loading = false;
  List<Map<String, dynamic>> _circulars = [];
  List<Map<String, dynamic>> _filteredCirculars = [];
  String? _userId;

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
    _loadCirculars();
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
      _filterCirculars();
    });
  }

  void _filterCirculars() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredCirculars = _circulars;
    } else {
      _filteredCirculars = _circulars.where((circular) {
        final title = (circular['title'] ?? '').toString().toLowerCase();
        final message = (circular['message'] ?? circular['description'] ?? '').toString().toLowerCase();
        return title.contains(query) || message.contains(query);
      }).toList();
    }
  }

  Future<void> _loadCirculars() async {
    setState(() {
      _loading = true;
    });
    
    try {
      // Get current user ID
      final user = await _authService.getCurrentUser();
      _userId = user?.uid;
      
      // Fetch circulars from Firebase
      final circulars = await _firestoreService.getCirculars(userId: _userId);
      
      setState(() {
        _circulars = circulars;
        _filteredCirculars = circulars;
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
          SnackBar(content: Text('Error loading circulars: $e')),
        );
      }
    }
  }

  Map<String, dynamic> _computeDateInfo(Map<String, dynamic> circular) {
    int ts = 0;
    if (circular['sentDate'] != null) {
      if (circular['sentDate'] is Map && circular['sentDate']['seconds'] != null) {
        ts = circular['sentDate']['seconds'] * 1000;
      } else if (circular['sentDate'] is int) {
        ts = circular['sentDate'];
      }
    } else if (circular['createdAt'] != null) {
      if (circular['createdAt'] is Map && circular['createdAt']['seconds'] != null) {
        ts = circular['createdAt']['seconds'] * 1000;
      } else if (circular['createdAt'] is int) {
        ts = circular['createdAt'];
      }
    }
    
    final date = ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now();
    final diffMs = DateTime.now().difference(date).inMilliseconds;
    final diffDays = (diffMs / (1000 * 60 * 60 * 24)).floor();
    
    String label = 'Today';
    if (diffDays == 1) {
      label = '1 day ago';
    } else if (diffDays > 1 && diffDays < 30) {
      label = '$diffDays days ago';
    } else if (diffDays >= 30 && diffDays < 365) {
      final months = (diffDays / 30).floor();
      label = '$months month${months > 1 ? 's' : ''} ago';
    } else if (diffDays >= 365) {
      final years = (diffDays / 365).floor();
      label = '$years year${years > 1 ? 's' : ''} ago';
    }
    
    String tier = 'old';
    if (diffDays <= 2) {
      tier = 'fresh';
    } else if (diffDays <= 7) {
      tier = 'recent';
    } else if (diffDays <= 30) {
      tier = 'stale';
    }
    
    return {'label': label, 'tier': tier};
  }

  Color _getTagColor(String tier) {
    switch (tier) {
      case 'fresh':
        return const Color(0xFF2E7D32);
      case 'recent':
        return const Color(0xFFD97706);
      case 'stale':
        return const Color(0xFF546E7A);
      case 'old':
        return const Color(0xFF37474F);
      default:
        return AppTheme.borderLight;
    }
  }

  void _handleCircularPress(Map<String, dynamic> circular) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CircularDetailScreen(circular: circular),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    await _loadCirculars();
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
                  
                  // Circulars List
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                    sliver: _loading
                        ? SliverToBoxAdapter(
                            child: _buildSkeleton(),
                          )
                        : _filteredCirculars.isEmpty
                            ? SliverToBoxAdapter(
                                child: _buildEmptyState(),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final circular = _filteredCirculars[index];
                                    final isLast = index == _filteredCirculars.length - 1;
                                    return _buildCircularCard(circular, isLast);
                                  },
                                  childCount: _filteredCirculars.length,
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
            'Circulars',
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
          hintText: 'Search circulars',
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

  Widget _buildCircularCard(Map<String, dynamic> circular, bool isLast) {
    final dateInfo = _computeDateInfo(circular);
    final attachmentCount = circular['attachments'] != null
        ? (circular['attachments'] is List ? circular['attachments'].length : 0)
        : (circular['files'] != null && circular['files'] is List
            ? circular['files'].length
            : 0);
    
    return GestureDetector(
      onTap: () => _handleCircularPress(circular),
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : AppTheme.spacingMD),
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
            circular['title'] ?? 'Circular',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            circular['message'] ?? circular['description'] ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSM,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getTagColor(dateInfo['tier']),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  dateInfo['label'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.white,
                  ),
                ),
              ),
              if (attachmentCount > 0) ...[
                const SizedBox(width: AppTheme.spacingXS),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.description, size: 12, color: AppTheme.white),
                      const SizedBox(width: 4),
                      Text(
                        '$attachmentCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
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
            Icons.description,
            size: 64,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: AppTheme.spacingLG),
          Text(
            _searchController.text.trim().isNotEmpty
                ? 'No matching circulars'
                : 'No circulars yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          const Text(
            'Circulars will appear here once published',
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
              margin: EdgeInsets.only(bottom: index == 2 ? 0 : AppTheme.spacingMD),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: '60%'.length * 10,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppTheme.borderLight,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                        ),
                      ),
                      Container(
                        width: 70,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.borderLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  Container(
                    width: '85%'.length * 10,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppTheme.borderLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingXS),
                        Container(
                          width: 24,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppTheme.borderLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
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
