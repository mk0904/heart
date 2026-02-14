import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/notification_service.dart';
import 'notification_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with TickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final NotificationService _notificationService = NotificationService();
  late TabController _tabController;
  String? _userId;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _filteredNotifications = [];
  bool _loading = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadNotifications();
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      _filterNotifications();
    });
  }

  void _filterNotifications() {
    final isPendingTab = _tabController.index == 0;
    
    _filteredNotifications = _notifications.where((notif) {
      final isRead = _isRead(notif);
      if (isPendingTab) {
        return !isRead; // Show only unread in Pending tab
      } else {
        return isRead; // Show only read in Mark as Read tab
      }
    }).toList();
    
    // Sort by createdAt descending
    _filteredNotifications.sort((a, b) {
      final dateA = a['createdAt'];
      final dateB = b['createdAt'];
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      try {
        DateTime aDateTime;
        DateTime bDateTime;
        
        if (dateA is Timestamp) {
          aDateTime = dateA.toDate();
        } else if (dateA is String) {
          aDateTime = DateTime.parse(dateA);
        } else {
          return 0;
        }
        
        if (dateB is Timestamp) {
          bDateTime = dateB.toDate();
        } else if (dateB is String) {
          bDateTime = DateTime.parse(dateB);
        } else {
          return 0;
        }
        
        return bDateTime.millisecondsSinceEpoch.compareTo(aDateTime.millisecondsSinceEpoch);
      } catch (e) {
        return 0;
      }
    });
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
    });

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      _userId = user.uid;
      final allNotifications = await _firestoreService.getAllNotifications(_userId!);
      
      // Filter to show only notifications (exclude invitations and circulars)
      final filteredNotifications = allNotifications.where((notif) {
        final type = notif['type']?.toString().toLowerCase();
        // Only show push notifications or notifications without a type (general notifications)
        // Exclude invitations and circulars
        return type == null || type == 'push' || (type != 'invitation' && type != 'circular');
      }).toList();
      
      setState(() {
        _notifications = filteredNotifications;
        _filterNotifications(); // Filter based on selected tab
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notifications: $e')),
        );
      }
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      final allNotifications = await _firestoreService.getAllNotifications(user.uid);
      
      // Filter to count only notifications (exclude invitations and circulars)
      final filteredNotifications = allNotifications.where((notif) {
        final type = notif['type']?.toString().toLowerCase();
        return type == null || type == 'push' || (type != 'invitation' && type != 'circular');
      }).toList();
      
      // Count unread notifications
      int count = 0;
      for (var notif in filteredNotifications) {
        final read = notif['read'];
        final readBy = notif['readBy'] as List?;
        
        bool isRead = false;
        if (read == true) {
          isRead = true;
        } else if (readBy != null && readBy.contains(user.uid)) {
          isRead = true;
        }
        
        if (!isRead) {
          count++;
        }
      }
      
      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    if (_userId == null) return;

    try {
      // Update Firebase first
      await _firestoreService.markNotificationAsRead(notification['id'], _userId!);
      
      // Refresh notifications from Firebase to get updated state
      await _loadNotifications();
      await _loadUnreadCount();
      _filterNotifications(); // Re-filter after marking as read
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark as read: $e')),
        );
      }
    }
  }

  bool _isRead(Map<String, dynamic> notification) {
    final read = notification['read'];
    final readBy = notification['readBy'] as List?;
    
    if (read == true) {
      return true;
    }
    
    if (readBy != null && _userId != null && readBy.contains(_userId)) {
      return true;
    }
    
    return false;
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is Map && timestamp['seconds'] != null) {
        date = DateTime.fromMillisecondsSinceEpoch((timestamp['seconds'] as int) * 1000);
      } else if (timestamp is String) {
        // Handle ISO string format like "2026-02-01T14:14:33.105Z"
        date = DateTime.parse(timestamp);
      } else {
        return 'Unknown date';
      }
      
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return 'Just now';
          }
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Unknown date';
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
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(),
              
              // Tabs
              _buildTabs(),
              
              // Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredNotifications.isEmpty
                        ? _buildEmptyState(_tabController.index == 0)
                        : RefreshIndicator(
                            onRefresh: () async {
                              await _loadNotifications();
                              await _loadUnreadCount();
                            },
                            child: ListView.builder(
                              padding: const EdgeInsets.all(AppTheme.spacingLG),
                              itemCount: _filteredNotifications.length,
                              itemBuilder: (context, index) {
                                final notification = _filteredNotifications[index];
                                final isRead = _isRead(notification);
                                final isLast = index == _filteredNotifications.length - 1;
                                final isPendingTab = _tabController.index == 0;
                                
                                return _buildNotificationCard(notification, isRead, isLast, isPendingTab);
                              },
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
      decoration: const BoxDecoration(
        color: Colors.white,
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
                'Notifications',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          if (_unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_unreadCount == 0) const SizedBox(width: 48), // Spacer for centering
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textSecondary,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'Pending'),
          Tab(text: 'Mark as Read'),
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

  Widget _buildNotificationCard(
    Map<String, dynamic> notification,
    bool isRead,
    bool isLast,
    bool isPendingTab,
  ) {
    return GestureDetector(
      onTap: () async {
        // Navigate to detail screen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NotificationDetailScreen(notification: notification),
          ),
        );
        
        // Refresh if notification was marked as read
        if (result == true) {
          await _loadNotifications();
          await _loadUnreadCount();
          _filterNotifications(); // Re-filter after marking as read
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : AppTheme.spacingMD),
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          border: Border.all(
            color: isRead ? AppTheme.borderLight : AppTheme.primary.withOpacity(0.3),
            width: isRead ? 0.5 : 1.5,
          ),
          boxShadow: AppTheme.shadowSM,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Expanded(
                  child: Text(
                    notification['title'] ?? 'Notification',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                      color: AppTheme.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: AppTheme.spacingXS),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingXS),
            // Subtitle row with time in bottom right
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    notification['message'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSM),
                Text(
                  _formatDate(notification['createdAt']),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                // Tick mark button - only show in Pending tab
                if (isPendingTab && !isRead) ...[
                  const SizedBox(width: AppTheme.spacingSM),
                  GestureDetector(
                    onTap: () => _markAsRead(notification),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        color: AppTheme.primary,
                        size: 18,
                      ),
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

  Widget _buildEmptyState(bool isPendingTab) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing5XL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPendingTab ? Icons.check_circle : Icons.notifications_none,
              size: 64,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: AppTheme.spacingLG),
            Text(
              isPendingTab ? 'All caught up!' : 'No read notifications',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSM),
            Text(
              isPendingTab 
                  ? 'No pending notifications'
                  : 'You haven\'t marked any notifications as read yet',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
