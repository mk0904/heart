import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/firebase_auth_service.dart';
import '../services/notification_service.dart';
import '../utils/user_friendly_errors.dart';

class NotificationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> notification;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
  });

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _commentController = TextEditingController();
  String? _userId;
  bool _isRead = false;
  List<Map<String, dynamic>> _comments = [];
  StreamSubscription? _circularSubscription;
  String? _circularId;

  @override
  void initState() {
    super.initState();
    _checkReadStatus();
    _checkIfCircular();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _circularSubscription?.cancel();
    super.dispose();
  }

  void _checkIfCircular() async {
    final type = widget.notification['type']?.toString().toLowerCase();
    if (type == 'circular') {
      // Get circular ID from notification - could be in circularId field or the notification ID itself
      _circularId = widget.notification['circularId'] ?? 
                    widget.notification['circular_id'] ??
                    widget.notification['id'];
      
      // If not found, try to find circular by matching title/message
      if (_circularId == null || _circularId == widget.notification['id']) {
        try {
          final title = widget.notification['title'] ?? '';
          final snapshot = await FirebaseFirestore.instance
              .collection('circulars')
              .where('title', isEqualTo: title)
              .limit(1)
              .get();
          
          if (snapshot.docs.isNotEmpty) {
            _circularId = snapshot.docs.first.id;
          }
        } catch (e) {
          // If search fails, use notification ID as fallback
          _circularId = widget.notification['id'];
        }
      }
      
      if (_circularId != null) {
        _subscribeToCircular();
      }
    }
  }

  void _subscribeToCircular() {
    if (_circularId == null) return;
    
    _circularSubscription = FirebaseFirestore.instance
        .collection('circulars')
        .doc(_circularId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      
      final data = snapshot.data();
      if (data == null) return;
      
      // Update comments
      final commentsArr = data['comments'] as List? ?? [];
      final sorted = List<Map<String, dynamic>>.from(commentsArr)
        ..sort((a, b) {
          final aTime = a['createdAt'] ?? 0;
          final bTime = b['createdAt'] ?? 0;
          return bTime.compareTo(aTime);
        });
      
      if (mounted) {
        setState(() {
          _comments = sorted.map((c) => c).toList();
        });
      }
    });
  }

  Future<void> _handleAddComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _circularId == null || _userId == null) return;
    
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;
      
      final entry = <String, dynamic>{
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': text,
        'userId': _userId!,
        'userName': user.name.isNotEmpty ? user.name : user.email,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      
      await FirebaseFirestore.instance
          .collection('circulars')
          .doc(_circularId)
          .update({
        'comments': FieldValue.arrayUnion([entry]),
      });
      
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to post comment')),
        );
      }
    }
  }

  String _formatCommentTime(int timestamp) {
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inSeconds < 60) {
        return '${difference.inSeconds} sec ago';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hr ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _checkReadStatus() async {
    final user = await _authService.getCurrentUser();
    if (user != null) {
      setState(() {
        _userId = user.uid;
        _isRead = _isNotificationRead(widget.notification);
      });
    }
  }

  bool _isNotificationRead(Map<String, dynamic> notification) {
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

  Future<void> _markAsRead() async {
    if (_userId == null || _isRead) return;

    try {
      await _notificationService.markAsRead(widget.notification['id']);
      setState(() {
        _isRead = true;
      });
      
      // Return true to indicate notification was marked as read
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyErrors.message(e))),
        );
      }
    }
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
      
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      
      return '${months[date.month - 1]} ${date.day}, ${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown date';
    }
  }

  Future<void> _handleFileUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open file')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final title = notification['title'] ?? 'Notification';
    final message = notification['message'] ?? '';
    final attachments = notification['attachments'] as List? ?? [];
    final fileUrls = notification['fileUrls'] as List? ?? [];

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
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main Content Card
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(AppTheme.spacingLG),
                        padding: const EdgeInsets.all(AppTheme.spacing2XL),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                          border: Border.all(color: AppTheme.borderLight, width: 0.5),
                          boxShadow: AppTheme.shadowSM,
                        ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.text,
                              height: 1.3,
                            ),
                          ),
                          
                          const SizedBox(height: AppTheme.spacingMD),
                          
                          // Date
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: AppTheme.spacingXS),
                              Text(
                                _formatDate(notification['createdAt']),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: AppTheme.spacingXL),
                          
                          // Message
                          if (message.isNotEmpty)
                            Text(
                              message,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppTheme.text,
                                height: 1.6,
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Attachments
                    if (attachments.isNotEmpty || fileUrls.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Attachments',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.text,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacingMD),
                            ...attachments.map((attachment) {
                              final url = attachment is String ? attachment : attachment['url'] ?? '';
                              final name = attachment is Map ? attachment['name'] ?? 'Attachment' : 'Attachment';
                              return _buildAttachmentItem(name, url);
                            }),
                            ...fileUrls.map((url) {
                              return _buildAttachmentItem('File', url);
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingLG),
                    ],
                    
                    // Mark as read button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                      child: _isRead
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, size: 18, color: AppTheme.primary),
                                  SizedBox(width: AppTheme.spacingSM),
                                  Text(
                                    'Marked as Read',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _markAsRead,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: AppTheme.white,
                                  padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check, size: 18),
                                    SizedBox(width: AppTheme.spacingSM),
                                    Text(
                                      'Mark as Read',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    
                    // Comments Section for Circulars
                    if (widget.notification['type']?.toString().toLowerCase() == 'circular') ...[
                      const SizedBox(height: AppTheme.spacing2XL),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
                        child: _buildCommentsSection(),
                      ),
                    ],
                    
                    const SizedBox(height: AppTheme.spacing2XL),
                  ],
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
        horizontal: AppTheme.spacingMD,
        vertical: AppTheme.spacingBase,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.text, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Notification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48), // Balance the back button
        ],
      ),
    );
  }

  Widget _buildAttachmentItem(String name, String url) {
    if (url.isEmpty) return const SizedBox.shrink();
    
    return GestureDetector(
      onTap: () => _handleFileUrl(url),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          border: Border.all(color: AppTheme.borderLight, width: 0.5),
          boxShadow: AppTheme.shadowSM,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              ),
              child: const Icon(
                Icons.description,
                color: AppTheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppTheme.spacingMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to open',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Comments',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingMD),
        
        // Add Comment Card
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingLG),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            border: Border.all(color: AppTheme.borderLight, width: 0.5),
            boxShadow: AppTheme.shadowSM,
          ),
          child: Stack(
            children: [
              TextField(
                controller: _commentController,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: const TextStyle(color: AppTheme.textLight),
                  filled: true,
                  fillColor: AppTheme.backgroundDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.only(
                    left: AppTheme.spacingMD,
                    right: 50,
                    top: AppTheme.spacingBase,
                    bottom: AppTheme.spacingBase,
                  ),
                ),
              ),
              Positioned(
                bottom: AppTheme.spacingSM,
                right: AppTheme.spacingSM,
                child: GestureDetector(
                  onTap: _commentController.text.trim().isEmpty ? null : _handleAddComment,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _commentController.text.trim().isEmpty
                          ? AppTheme.textDisabled.withOpacity(0.5)
                          : AppTheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: AppTheme.shadowSM,
                    ),
                    child: const Icon(
                      Icons.send,
                      size: 18,
                      color: AppTheme.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Comments List
        if (_comments.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMD),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingLG),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              border: Border.all(color: AppTheme.borderLight, width: 0.5),
              boxShadow: AppTheme.shadowSM,
            ),
            child: Column(
              children: _comments.map((comment) {
                return Container(
                  margin: EdgeInsets.only(
                    bottom: comment == _comments.last ? 0 : AppTheme.spacingMD,
                  ),
                  padding: EdgeInsets.only(
                    bottom: comment == _comments.last ? 0 : AppTheme.spacingMD,
                  ),
                  decoration: BoxDecoration(
                    border: comment == _comments.last
                        ? null
                        : const Border(
                            bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            comment['userName'] ?? 'User',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                          Text(
                            _formatCommentTime(comment['createdAt'] ?? 0),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingXS),
                      Text(
                        comment['text'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.text,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
