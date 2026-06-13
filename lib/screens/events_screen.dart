import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import '../utils/event_edit_policy.dart';
import 'event_detail_screen.dart';
import 'event_form_screen.dart';
import '../utils/user_friendly_errors.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  late AnimationController _skeletonAnimationController;
  late Animation<double> _skeletonOpacity;
  bool _showSearchIcon = false;
  bool _loading = false;
  bool _showFilters = false;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _filteredEvents = [];
  String? _userId;
  String? _selectedCollege;
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>> _colleges = [];

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
    _loadEvents();
    _loadColleges();
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
      _filterEvents();
    });
  }

  void _filterEvents() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredEvents = _events;
    } else {
      _filteredEvents = _events.where((event) {
        final title = (event['title'] ?? '').toString().toLowerCase();
        final description = (event['description'] ?? '').toString().toLowerCase();
        final venue = (event['venue'] ?? '').toString().toLowerCase();
        return title.contains(query) || description.contains(query) || venue.contains(query);
      }).toList();
    }
  }

  Future<void> _loadColleges() async {
    try {
      final colleges = await _firestoreService.getColleges();
      setState(() {
        _colleges = colleges;
      });
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loading = true;
    });
    
    try {
      // Get current user (for reference, but don't filter by default)
      final user = await _authService.getCurrentUser();
      _userId = user?.uid;
      
      // Fetch events from Firebase - only filter by college if explicitly selected
      // Show all events by default (no college filter)
      final events = await _firestoreService.getEvents(
        collegeId: _selectedCollege, // Only filter if user explicitly selected a college
      );
      
      // Apply date filters if set
      List<Map<String, dynamic>> filtered = events;
      if (_startDate != null || _endDate != null) {
        filtered = events.where((event) {
          if (event['startDate'] == null) return false;
          try {
            final eventDate = DateTime.parse(event['startDate']);
            if (_startDate != null && eventDate.isBefore(_startDate!)) return false;
            if (_endDate != null && eventDate.isAfter(_endDate!)) return false;
            return true;
          } catch (e) {
            return false;
          }
        }).toList();
      }
      
      setState(() {
        _events = filtered;
        _filteredEvents = filtered;
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

  void _clearFilters() {
    setState(() {
      _selectedCollege = null;
      _startDate = null;
      _endDate = null;
    });
    _loadEvents();
  }

  void _applyFilters() {
    setState(() {
      _showFilters = false;
    });
    _loadEvents();
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${_getMonthName(date.month)} ${date.day}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Future<void> _handleEventPress(Map<String, dynamic> event) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailScreen(event: event),
      ),
    );
    if (result == true) _loadEvents();
  }

  Future<void> _handleEditEvent(Map<String, dynamic> event) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EventFormScreen(event: event),
      ),
    );
    if (result == true) _loadEvents();
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
          child: Stack(
            children: [
              Column(
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
                        
                        // Events List
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                          sliver: _loading
                              ? SliverToBoxAdapter(
                                  child: _buildSkeleton(),
                                )
                              : _filteredEvents.isEmpty
                                  ? SliverToBoxAdapter(
                                      child: _buildEmptyState(),
                                    )
                                  : SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                          if (index == 0) {
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Padding(
                                                  padding: EdgeInsets.only(bottom: AppTheme.spacingMD),
                                                  child: Text(
                                                    'Past Events',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.text,
                                                    ),
                                                  ),
                                                ),
                                                _buildEventCard(_filteredEvents[index]),
                                              ],
                                            );
                                          }
                                          return _buildEventCard(_filteredEvents[index]);
                                        },
                                        childCount: _filteredEvents.length,
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
              
              // Floating Add Button - Bottom Right
              Positioned(
                bottom: AppTheme.spacingLG,
                right: AppTheme.spacingLG,
                child: FloatingActionButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EventFormScreen(),
                      ),
                    );
                    if (result == true) {
                      _loadEvents();
                    }
                  },
                  backgroundColor: AppTheme.primary,
                  child: const Icon(Icons.add, color: AppTheme.white),
                ),
              ),
              
              // Floating Filter Button - Bottom Left
              Positioned(
                bottom: AppTheme.spacingLG,
                left: AppTheme.spacingLG,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _showFilters = true;
                    });
                  },
                  backgroundColor: AppTheme.textSecondary,
                  child: const Icon(Icons.filter_list, color: AppTheme.white),
                ),
              ),
              
              // Filter Modal
              if (_showFilters) _buildFilterModal(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterModal() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showFilters = false;
        });
      },
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {}, // Prevent closing when tapping inside
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusXL),
                    topRight: Radius.circular(AppTheme.radiusXL),
                  ),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacing2XL),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AppTheme.borderLight, width: 1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filter Events',
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
                                _showFilters = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    // Filter Content
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(AppTheme.spacing2XL),
                        children: [
                          // College Filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'College',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.text,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacingSM),
                              Builder(
                                builder: (context) {
                                  final collegeDropdownItems = <DropdownMenuItem<String>>[
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('All Colleges'),
                                    ),
                                    ..._colleges.map((college) {
                                      return DropdownMenuItem<String>(
                                        value: college['id'] as String?,
                                        child: Text(
                                          college['name'] ?? 'Unknown',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      );
                                    }),
                                  ];
                                  return DropdownButtonFormField<String>(
                                    initialValue: _selectedCollege,
                                    isExpanded: true,
                                    isDense: true,
                                    selectedItemBuilder: (context) {
                                      return collegeDropdownItems.map((item) {
                                        final c = item.child;
                                        final label = c is Text
                                            ? (c.data ?? '')
                                            : (item.value?.toString() ?? '');
                                        return Align(
                                          alignment: AlignmentDirectional.centerStart,
                                          child: Text(
                                            label,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: AppTheme.text,
                                            ),
                                          ),
                                        );
                                      }).toList();
                                    },
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: AppTheme.backgroundDark,
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: AppTheme.spacingMD,
                                        vertical: AppTheme.spacingMD,
                                      ),
                                    ),
                                    items: collegeDropdownItems,
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedCollege = value;
                                      });
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: AppTheme.spacingLG),
                          
                          // Start Date Filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Start Date',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.text,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacingSM),
                              InkWell(
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate ?? DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: _endDate ?? DateTime(2100),
                                  );
                                  if (date != null) {
                                    setState(() {
                                      _startDate = date;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacingMD,
                                    vertical: AppTheme.spacingMD,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.backgroundDark,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _startDate != null
                                            ? _formatDate(_startDate!.toIso8601String())
                                            : 'Select Start Date',
                                        style: TextStyle(
                                          color: _startDate != null
                                              ? AppTheme.text
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                      const Icon(Icons.calendar_today,
                                          size: 18, color: AppTheme.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: AppTheme.spacingLG),
                          
                          // End Date Filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'End Date',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.text,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacingSM),
                              InkWell(
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _endDate ?? (_startDate ?? DateTime.now()),
                                    firstDate: _startDate ?? DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (date != null) {
                                    setState(() {
                                      _endDate = date;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacingMD,
                                    vertical: AppTheme.spacingMD,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.backgroundDark,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _endDate != null
                                            ? _formatDate(_endDate!.toIso8601String())
                                            : 'Select End Date',
                                        style: TextStyle(
                                          color: _endDate != null
                                              ? AppTheme.text
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                      const Icon(Icons.calendar_today,
                                          size: 18, color: AppTheme.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: AppTheme.spacing2XL),
                          
                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _clearFilters,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                                    side: const BorderSide(color: AppTheme.borderLight),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                    ),
                                  ),
                                  child: const Text(
                                    'Clear All',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppTheme.spacingMD),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _applyFilters,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                                    backgroundColor: AppTheme.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                    ),
                                  ),
                                  child: const Text(
                                    'Apply Filters',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                'Events',
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
                    if (!mounted) return;
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
          hintText: 'Search events',
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

  Widget _buildEventCard(Map<String, dynamic> event) {
    final images = event['images'] as List?;
    final List<String> imageUrls = images?.map<String>((img) {
      if (img is String) return img;
      if (img is Map) return (img['uri'] ?? img['url'] ?? '').toString();
      return '';
    }).where((url) => url.isNotEmpty).toList() ?? [];
    final canEdit = canEditEvent(event, _userId);
    final editableUntil = eventEditableUntil(event);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Slider
          _buildImageSlider(imageUrls, () => _handleEventPress(event)),
          
          // Event Details
          GestureDetector(
            onTap: () => _handleEventPress(event),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          event['title'] ?? 'Untitled Event',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatDate(event['startDate']),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (canEdit) ...[
                        const SizedBox(width: AppTheme.spacingXS),
                        IconButton(
                          tooltip: 'Edit event',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                          onPressed: () => _handleEditEvent(event),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    'Organized by ${event['organizedBy'] ?? 'Organizer'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (canEdit && editableUntil != null) ...[
                    const SizedBox(height: AppTheme.spacingSM),
                    _buildEditWindowChip(editableUntil),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditWindowChip(DateTime editableUntil) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.22),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_outlined, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            'Editable until ${_formatEditExpiry(editableUntil)}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatEditExpiry(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final now = DateTime.now();
    final sameDay =
        now.year == local.year && now.month == local.month && now.day == local.day;
    if (sameDay) return '$hour:$minute $period';
    return '${local.day}/${local.month}, $hour:$minute $period';
  }

  Widget _buildImageSlider(List<String> imageUrls, VoidCallback onTap) {
    if (imageUrls.isEmpty) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: AppTheme.borderLight,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppTheme.radiusBase),
              topRight: Radius.circular(AppTheme.radiusBase),
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.event,
              size: 32,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      );
    }

    return _EventImageSlider(
      imageUrls: imageUrls,
      onTap: onTap,
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing5XL),
      child: Column(
        children: [
          const Icon(
            Icons.event,
            size: 64,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: AppTheme.spacingLG),
          Text(
            _searchController.text.trim().isNotEmpty
                ? 'No matching events'
                : 'No events yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          const Text(
            'Events will appear here once created',
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
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(AppTheme.radiusBase),
                        topRight: Radius.circular(AppTheme.radiusBase),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingMD),
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
                          width: '50%'.length * 10,
                          height: 12,
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
          ),
        );
      },
    );
  }
}

class _EventImageSlider extends StatefulWidget {
  final List<String> imageUrls;
  final VoidCallback onTap;

  const _EventImageSlider({
    required this.imageUrls,
    required this.onTap,
  });

  @override
  State<_EventImageSlider> createState() => _EventImageSliderState();
}

class _EventImageSliderState extends State<_EventImageSlider> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        height: 160,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return Image.network(
                  widget.imageUrls[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppTheme.borderLight,
                      child: const Center(
                        child: Icon(Icons.broken_image, color: AppTheme.textSecondary),
                      ),
                    );
                  },
                );
              },
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.imageUrls.length,
                    (index) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentIndex == index
                            ? AppTheme.white
                            : AppTheme.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
