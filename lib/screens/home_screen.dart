import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../navigation/main_tab_navigator.dart';
import 'edit_profile_screen.dart';
import 'events_screen.dart';
import 'invitations_screen.dart';
import 'colleagues_screen.dart';
import 'review_submissions_screen.dart';
import 'submit_data_screen.dart';
import 'notifications_screen.dart';
import 'notification_detail_screen.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import 'dart:async';
import '../utils/user_friendly_errors.dart';

class HomeScreen extends StatefulWidget {
  final bool isActive;
  
  const HomeScreen({super.key, this.isActive = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();
  String _userName = 'User';
  String? _userRole;
  int _unreadCount = 0;
  StreamSubscription? _notificationSubscription;
  String? _userId;
  List<Map<String, dynamic>> _notifications = [];
  bool _loadingNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadNotifications();
    _loadUnreadCount();
    _startListening();
    _requestNotificationPermission();
  }

  Future<void> _requestNotificationPermission() async {
    // Small delay to ensure UI is ready
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      await _notificationService.requestPermission();
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loadingNotifications = true;
    });

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        setState(() {
          _loadingNotifications = false;
        });
        return;
      }

      _userId = user.uid;
      final allNotifications = await _firestoreService.getAllNotifications(_userId!);
      
      // Filter to show only notifications (exclude invitations)
      final filteredNotifications = allNotifications.where((notif) {
        final type = notif['type']?.toString().toLowerCase();
        return type != 'invitation';
      }).toList();
      
      // Filter to only show unread notifications
      // Ensure _userId is set before filtering
      final unreadNotifications = filteredNotifications.where((notification) {
        if (_userId == null) return false; // Don't show any if userId not set
        return !_isRead(notification);
      }).toList();
      
      // Sort by createdAt descending and take first 3
      unreadNotifications.sort((a, b) {
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
      
      setState(() {
        _notifications = unreadNotifications.take(3).toList();
        _loadingNotifications = false;
      });
    } catch (e) {
      setState(() {
        _loadingNotifications = false;
      });
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
    if (timestamp == null) return 'Unknown';
    
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
        return 'Unknown';
      }
      
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inSeconds < 60) {
        return '${difference.inSeconds} sec ago';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hr ago';
      } else if (difference.inDays < 30) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return '$months mo ago';
      } else {
        final years = (difference.inDays / 365).floor();
        return '$years yr ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    if (_userId == null) return;

    try {
      // Mark as read in Firebase
      await _firestoreService.markNotificationAsRead(notification['id'], _userId!);
      
      // Remove from local list immediately for instant UI update
      setState(() {
        _notifications = _notifications.where((n) => n['id'] != notification['id']).toList();
      });
      
      // Then refresh from Firebase to ensure consistency
      await Future.delayed(const Duration(milliseconds: 300)); // Small delay for Firebase propagation
      await _loadNotifications();
      await _loadUnreadCount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyErrors.message(e))),
        );
        // Reload on error to ensure consistency
        await _loadNotifications();
      }
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        _userId = user.uid;
        final allNotifications = await _firestoreService.getAllNotifications(user.uid);
        
        // Filter to count only notifications (exclude invitations)
        final filteredNotifications = allNotifications.where((notif) {
          final type = notif['type']?.toString().toLowerCase();
          return type != 'invitation';
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
      }
    } catch (e) {
      // Ignore error
    }
  }

  void _startListening() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      _userId = user.uid;
      final stream = _firestoreService.streamAllNotifications(_userId!);
      _notificationSubscription = stream.listen(
        (notifications) {
          // Filter to count only notifications (exclude invitations)
          final filteredNotifications = notifications.where((notif) {
            final type = notif['type']?.toString().toLowerCase();
            return type != 'invitation';
          }).toList();
          
          // Sort by createdAt descending and take first 3
          filteredNotifications.sort((a, b) {
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
          
          // Filter to only show unread notifications
          final unreadNotifications = filteredNotifications.where((notification) {
            if (_userId == null) return false;
            final read = notification['read'];
            final readBy = notification['readBy'] as List?;
            
            bool isRead = false;
            if (read == true) {
              isRead = true;
            } else if (readBy != null && readBy.contains(_userId)) {
              isRead = true;
            }
            
            return !isRead;
          }).toList();
          
          // Count unread notifications
          int unread = unreadNotifications.length;
          
          // Update date sorting for unread notifications
          unreadNotifications.sort((a, b) {
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
          
          if (mounted) {
            setState(() {
              _unreadCount = unread;
              _notifications = unreadNotifications.take(3).toList();
            });
          }
        },
        onError: (error) {
          // Ignore error
        },
      );
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user != null && mounted) {
        setState(() {
          _userName = user.name;
          _userRole = user.role;
        });
      }
    } catch (e) {
      // Ignore error
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: widget.isActive
            ? RefreshIndicator(
                onRefresh: _handleRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(), // Enable pull-to-refresh even when content doesn't scroll
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      _buildHeader(context),
                      
                      // Complete Profile Card (if needed)
                      // _buildCompleteProfileCard(context),
                      
                      // Features Grid
                      _buildFeaturesGrid(context),
                      
                      // Pending Notifications Section
                      _buildNotificationsSection(context),
                      
                      const SizedBox(height: AppTheme.spacing5XL),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _handleRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                    child: _buildInactiveMessage(context),
                  ),
                ),
              ),
      ),
    );
  }
  
  Future<void> _handleRefresh() async {
    // Check active status
    await _checkActiveStatus();
    
    // Refresh all data
    await Future.wait([
      _loadUserProfile(),
      _loadNotifications(),
      _loadUnreadCount(),
    ]);
  }

  Widget _buildInactiveMessage(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing2XL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 80,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: AppTheme.spacingXL),
            Text(
              'Account Pending Activation',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMD),
            Text(
              'You have to wait till the account gets activated by the admin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXL),
            ElevatedButton.icon(
              onPressed: _checkActiveStatus,
              icon: const Icon(Icons.refresh, color: AppTheme.white),
              label: const Text(
                'Refresh Status',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingXL,
                  vertical: AppTheme.spacingMD,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMD),
            ElevatedButton(
              onPressed: () async {
                // Navigate to Edit Profile - allowed even when inactive
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfileScreen(),
                  ),
                );
                if (result == true && mounted) {
                  await _loadUserProfile();
                  await _checkActiveStatus();
                }
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
          ],
        ),
      ),
    );
  }
  
  Future<void> _checkActiveStatus() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        final active = user.active ?? true;
        
        // If user is now active, replace the MainTabNavigator with active status
        if (active && !widget.isActive) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const MainTabNavigator(isActive: true),
              ),
            );
          }
        } else if (!active && widget.isActive) {
          // If user was shown active UI but is actually inactive
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const MainTabNavigator(isActive: false),
              ),
            );
          }
        } else if (!active) {
          // Still inactive, show a message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your account is still pending activation. Please wait for admin approval.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
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
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLG,
        AppTheme.spacingXL,
        AppTheme.spacingLG,
        AppTheme.spacingLG,
      ),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo and App Name Row
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/images/home.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.favorite,
                              color: AppTheme.white,
                              size: 24,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSM),
                    const Text(
                      'HEART Nagaland',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMD),
                // Welcome Section
                Text(
                  'Welcome,',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  _userName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          // Notification Button
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsScreen()),
              );
              // Refresh unread count when returning from notifications screen
              if (result == true || mounted) {
                await _loadUnreadCount();
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.notifications,
                    color: AppTheme.white,
                    size: 24,
                  ),
                ),
                if (_unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: AppTheme.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesGrid(BuildContext context) {
    final features = [
      _FeatureItem(
        title: 'Events',
        icon: Icons.event,
        color: const Color(0xFF1F3A5F),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EventsScreen()),
          );
        },
      ),
      _FeatureItem(
        title: 'Invitations',
        icon: Icons.mail,
        color: const Color(0xFF1B5C5A),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const InvitationsScreen()),
          );
        },
      ),
      _FeatureItem(
        title: 'Colleagues',
        icon: Icons.people,
        color: const Color(0xFF3F2E56),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ColleaguesScreen()),
          );
        },
      ),
    ];

    features.add(
      _FeatureItem(
        title: 'Edit\nProfile',
        icon: Icons.edit,
        color: const Color(0xFF5A2A27),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditProfileScreen()),
          );
          if (result == true && mounted) {
            await _loadUserProfile();
            await _checkActiveStatus();
          }
        },
      ),
    );

    // Enrollment data: submit form for all roles; principals also get a dedicated review tile.
    features.add(
      _FeatureItem(
        title: 'Submit\nData',
        icon: Icons.cloud_upload,
        color: AppTheme.primary,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SubmitDataScreen(),
            ),
          );
        },
      ),
    );
    if (_userRole != null) {
      final role = _userRole!.toLowerCase().replaceAll('-', ' ');
      if (role == 'principal') {
        features.add(
          _FeatureItem(
            title: 'Review\nSubmissions',
            icon: Icons.fact_check,
            color: AppTheme.secondary,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ReviewSubmissionsScreen(),
                ),
              );
            },
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      child: Wrap(
        spacing: AppTheme.spacingXS,
        runSpacing: AppTheme.spacingXS,
        children: features.map((feature) => _buildFeatureCard(feature)).toList(),
      ),
    );
  }

  Widget _buildFeatureCard(_FeatureItem feature) {
    return Builder(
      builder: (context) => SizedBox(
        width: (MediaQuery.of(context).size.width - 
                (AppTheme.spacingLG * 2) - AppTheme.spacingXS) / 2,
        child: GestureDetector(
          onTap: feature.onTap,
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: feature.color,
              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            ),
            padding: const EdgeInsets.all(AppTheme.spacingMD),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    feature.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.white,
                    ),
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    feature.icon,
                    color: AppTheme.white,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                  );
                  if (result == true || mounted) {
                    await _loadNotifications();
                    await _loadUnreadCount();
                  }
                },
                child: const Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMD),
          if (_loadingNotifications)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacing2XL),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                border: Border.all(color: AppTheme.borderLight, width: 0.5),
                boxShadow: AppTheme.shadowSM,
              ),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_notifications.isEmpty)
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
                if (result == true || mounted) {
                  await _loadNotifications();
                  await _loadUnreadCount();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacing2XL),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  border: Border.all(color: AppTheme.borderLight, width: 0.5),
                  boxShadow: AppTheme.shadowSM,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 24,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: AppTheme.spacingMD),
                    const Text(
                      'All caught up!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingSM),
                    const Text(
                      'No pending notifications',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                ..._notifications.map((notification) {
                  final isRead = _isRead(notification);
                  return _buildNotificationItem(notification, isRead);
                }),
                if (_notifications.length >= 3)
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                      );
                      if (result == true || mounted) {
                        await _loadNotifications();
                        await _loadUnreadCount();
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppTheme.spacingMD),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                        border: Border.all(color: AppTheme.borderLight, width: 0.5),
                        boxShadow: AppTheme.shadowSM,
                      ),
                      child: Center(
                        child: Text(
                          'View all notifications',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification, bool isRead) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NotificationDetailScreen(notification: notification),
          ),
        );
        if (result == true || mounted) {
          await _loadNotifications();
          await _loadUnreadCount();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        decoration: BoxDecoration(
          color: AppTheme.white,
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
                if (!isRead) ...[
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
}

class _FeatureItem {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _FeatureItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
