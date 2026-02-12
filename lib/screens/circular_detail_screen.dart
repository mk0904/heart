import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';

class CircularDetailScreen extends StatefulWidget {
  final Map<String, dynamic> circular;

  const CircularDetailScreen({super.key, required this.circular});

  @override
  State<CircularDetailScreen> createState() => _CircularDetailScreenState();
}

class _CircularDetailScreenState extends State<CircularDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final TextEditingController _commentController = TextEditingController();
  
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _attachments = [];
  String _authorName = 'Admin';
  String? _downloadingFileId;
  String? _userId;
  StreamSubscription? _circularSubscription;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _normalizeAttachments(widget.circular);
    _fetchAuthorName();
    _subscribeToCircular();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _circularSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _authService.getCurrentUser();
      setState(() {
        _userId = user?.uid;
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _fetchAuthorName() async {
    final createdBy = widget.circular['createdBy'];
    if (createdBy == null) return;
    
    try {
      final user = await _firestoreService.getUser(createdBy);
        if (user != null) {
          setState(() {
            _authorName = user.name;
          });
        }
    } catch (e) {
      // Handle error
    }
  }

  void _normalizeAttachments(Map<String, dynamic> data) {
    try {
      List<Map<String, dynamic>> atts = [];
      
      if (data['attachments'] != null && data['attachments'] is List) {
        final attachments = data['attachments'] as List;
        for (int i = 0; i < attachments.length; i++) {
          final att = attachments[i];
          if (att is Map) {
            // Extract URL - handle various formats
            String url = '';
            if (att['url'] != null) {
              url = att['url'].toString();
            } else if (att['uri'] != null) {
              url = att['uri'].toString();
            } else if (att['link'] != null) {
              url = att['link'].toString();
            }
            
            atts.add({
              'id': att['public_id'] ?? att['publicId'] ?? att['id'] ?? i.toString(),
              'name': att['name'] ?? 'Attachment ${i + 1}.pdf',
              'url': url,
              'public_id': att['public_id'] ?? att['publicId'],
              'size': att['size'] != null ? '${((att['size'] as int) / 1024).round()} KB' : 'Unknown',
              'type': att['type'] ?? (url.endsWith('.pdf') ? 'application/pdf' : 'document'),
            });
          } else if (att is String) {
            // Handle case where attachment is just a URL string
            atts.add({
              'id': i.toString(),
              'name': 'Attachment ${i + 1}.pdf',
              'url': att,
              'size': 'Unknown',
              'type': att.endsWith('.pdf') ? 'application/pdf' : 'document',
            });
          }
        }
      } else if (data['files'] != null && data['files'] is List) {
        final files = data['files'] as List;
        for (int i = 0; i < files.length; i++) {
          final file = files[i];
          if (file is Map) {
            // Extract URL - handle various formats
            String url = '';
            if (file['url'] != null) {
              url = file['url'].toString();
            } else if (file['uri'] != null) {
              url = file['uri'].toString();
            } else if (file['link'] != null) {
              url = file['link'].toString();
            }
            
            atts.add({
              'id': file['id'] ?? i.toString(),
              'name': file['name'] ?? 'Attachment ${i + 1}.pdf',
              'url': url,
              'public_id': file['public_id'] ?? file['publicId'],
              'size': file['size'] != null ? '${((file['size'] as int) / 1024).round()} KB' : 'Unknown',
              'type': file['type'] ?? (url.endsWith('.pdf') ? 'application/pdf' : 'document'),
            });
          } else if (file is String) {
            // Handle case where file is just a URL string
            atts.add({
              'id': i.toString(),
              'name': 'Attachment ${i + 1}.pdf',
              'url': file,
              'size': 'Unknown',
              'type': file.endsWith('.pdf') ? 'application/pdf' : 'document',
            });
          }
        }
      }
      
      setState(() {
        _attachments = atts;
      });
    } catch (e) {
      setState(() {
        _attachments = [];
      });
    }
  }

  void _subscribeToCircular() {
    if (widget.circular['id'] == null) return;
    
    _circularSubscription = FirebaseFirestore.instance
        .collection('circulars')
        .doc(widget.circular['id'])
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
      
      setState(() {
        _comments = sorted.map((c) => c).toList();
      });
      
      // Update attachments
      _normalizeAttachments(data);
    });
  }

  Future<void> _handleAddComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || widget.circular['id'] == null || _userId == null) return;
    
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;
      
      final entry = <String, dynamic>{
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': text,
        'userId': _userId!,
        'userName': user.name,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      
      await FirebaseFirestore.instance
          .collection('circulars')
          .doc(widget.circular['id'])
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

  Future<void> _handleDownload(Map<String, dynamic> attachment) async {
    final attachmentId = attachment['id'];
    final attachmentName = attachment['name'] ?? 'Attachment';
    final url = attachment['url']?.toString().trim() ?? '';
    
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid URL found for this attachment')),
        );
      }
      return;
    }
    
    // Validate URL format
    Uri? uri;
    try {
      uri = Uri.parse(url);
      if (!uri.hasScheme) {
        // If no scheme, try adding https://
        uri = Uri.parse('https://$url');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid URL format')),
        );
      }
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Attachment'),
        content: Text('Open $attachmentName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                _downloadingFileId = attachmentId;
              });

              final messenger = ScaffoldMessenger.of(context);
              
              try {
                // Try to launch the URL
                // Use externalApplication mode to open in browser/app
                final launched = await launchUrl(
                  uri!,
                  mode: LaunchMode.externalApplication,
                );
                
                if (!launched) {
                  // If launch failed, try with platformDefault mode
                  await launchUrl(
                    uri,
                    mode: LaunchMode.platformDefault,
                  );
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Could not open the file: ${e.toString()}'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              } finally {
                if (mounted) {
                  setState(() {
                    _downloadingFileId = null;
                  });
                }
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  String _getDateString(dynamic date) {
    if (date == null) return '';
    try {
      DateTime dateTime;
      if (date is Timestamp) {
        dateTime = date.toDate();
      } else if (date is Map && date['seconds'] != null) {
        dateTime = DateTime.fromMillisecondsSinceEpoch((date['seconds'] as int) * 1000);
      } else if (date is int) {
        dateTime = DateTime.fromMillisecondsSinceEpoch(date);
      } else if (date is String) {
        dateTime = DateTime.parse(date);
      } else {
        return '';
      }
      return dateTime.toLocal().toString();
    } catch (e) {
      return '';
    }
  }

  String _formatCommentTime(int timestamp) {
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return date.toLocal().toString();
    } catch (e) {
      return '';
    }
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingLG),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Circular Content
                    _buildCircularCard(),
                    
                    // Attachments Section
                    if (_attachments.isNotEmpty) _buildAttachmentsSection(),
                    
                    // Comments Section
                    _buildCommentsSection(),
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
                'Circular Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48), // Spacer for centering
        ],
      ),
    );
  }

  Widget _buildCircularCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      margin: const EdgeInsets.only(bottom: AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.circular['title'] ?? 'Circular',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            widget.circular['message'] ?? widget.circular['description'] ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppTheme.spacingMD),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getDateString(widget.circular['sentDate'] ?? widget.circular['createdAt']),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                'By $_authorName',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachments (${_attachments.length})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingMD),
        Wrap(
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          spacing: AppTheme.spacingBase,
          runSpacing: AppTheme.spacingBase,
          children: _attachments.map((attachment) {
            final isDownloading = _downloadingFileId == attachment['id'];
            return GestureDetector(
              onTap: isDownloading ? null : () => _handleDownload(attachment),
              child: Opacity(
                opacity: isDownloading ? 0.5 : 1.0,
                child: Container(
                  width: (MediaQuery.of(context).size.width - AppTheme.spacingLG * 2 - AppTheme.spacingBase) / 2,
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                    border: Border.all(color: AppTheme.borderLight, width: 0.5),
                    boxShadow: AppTheme.shadowSM,
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacingSM),
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(AppTheme.radiusBase),
                            topRight: Radius.circular(AppTheme.radiusBase),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.description,
                                size: 18,
                                color: AppTheme.white,
                              ),
                            ),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: AppTheme.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Content
                      Padding(
                        padding: const EdgeInsets.all(AppTheme.spacingSM),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attachment['name'] ?? 'Attachment',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.text,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              attachment['size'] ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppTheme.spacing2XL),
      ],
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
            fontWeight: FontWeight.bold,
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
          ),
          child: Stack(
            children: [
              TextField(
                controller: _commentController,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      borderSide: const BorderSide(color: AppTheme.borderLight, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1),
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingMD,
                      AppTheme.spacingMD,
                      50,
                      AppTheme.spacingMD,
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
                          ? AppTheme.textDisabled.withValues(alpha: 0.5)
                          : AppTheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.borderLight, width: 0.5),
                    boxShadow: AppTheme.shadowSM,
                    ),
                    child: const Icon(
                      Icons.send,
                      size: 20,
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
                            bottom: BorderSide(color: AppTheme.borderLight, width: 1),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
                          height: 1.4,
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
