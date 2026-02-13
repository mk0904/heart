import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';
import 'project_submission_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final Map<String, dynamic> project;

  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final PageController _imageViewerController = PageController();
  
  bool _loading = false;
  List<Map<String, dynamic>> _submissions = [];
  bool _viewerVisible = false;
  List<String> _viewerImages = [];
  int _viewerIndex = 0;
  String? _userRole;
  String? _userCollegeId;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _loadUserProfile();
    await _loadSubmissions();
  }

  @override
  void dispose() {
    _imageViewerController.dispose();
    super.dispose();
  }

  Future<void> _loadSubmissions() async {
    setState(() => _loading = true);
    try {
      // getSubmissions already sorts by createdAt descending
      final submissions = await _firestoreService.getSubmissions(widget.project['id']);
      
      // filter locally if user has a collegeId
      List<Map<String, dynamic>> filtered = submissions;
      if (_userCollegeId != null && _userRole?.toLowerCase() != 'super admin') {
        filtered = submissions.where((s) => s['collegeId'] == _userCollegeId).toList();
      }

      setState(() {
        _submissions = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading submissions: $e')),
        );
      }
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = await _authService.getCurrentUser();
      if (mounted) {
        setState(() {
          _userRole = user?.role;
          _userCollegeId = user?.collegeId;
        });
      }
    } catch (e) {
      // Ignore error for now
    }
  }

  Color _getStatusColor(String? status) {
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

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      DateTime dateTime;
      if (date is Timestamp) {
        dateTime = date.toDate();
      } else if (date is Map && date['seconds'] != null) {
        dateTime = DateTime.fromMillisecondsSinceEpoch((date['seconds'] as int) * 1000);
      } else if (date is String) {
        dateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        dateTime = date;
      } else {
        return 'N/A';
      }
      return '${_getMonthName(dateTime.month)} ${dateTime.day}, ${dateTime.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  void _handleImagePress(List<dynamic> images, int index) {
    final normalized = images.map((img) {
      if (img is String) return img;
      if (img is Map) return img['url'] ?? img['uri'] ?? '';
      return '';
    }).where((url) => url.isNotEmpty).cast<String>().toList();
    
    setState(() {
      _viewerImages = normalized;
      _viewerIndex = index;
      _viewerVisible = true;
    });
    
    if (_viewerImages.isNotEmpty) {
      _imageViewerController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: Stack(
          children: [
            Column(
              children: [
                // Header
                _buildHeader(),
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppTheme.spacingLG),
                    child: Column(
                      children: [
                        // Project Info Card
                        _buildProjectCard(),
                        
                        // New Submission Button
                        if (widget.project['status']?.toLowerCase() != 'completed' && 
                            _userRole?.toLowerCase().replaceAll('-', ' ') == 'ministerial staff')
                          _buildNewSubmissionButton(),
                        
                        // Submissions Section
                        _buildSubmissionsSection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // Fullscreen Image Viewer
            if (_viewerVisible) _buildImageViewer(),
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
                'Project Details',
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

  Widget _buildProjectCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
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
          Text(
            widget.project['name'] ?? 'Untitled Project',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            widget.project['description'] ?? '',
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
                '${widget.project['submissionsCount'] ?? 0} submissions',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (widget.project['status'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                    vertical: 4,
                  ),
                  constraints: const BoxConstraints(minWidth: 70),
                  decoration: BoxDecoration(
                    color: _getStatusColor(widget.project['status']),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.project['status'].toUpperCase(),
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
        ],
      ),
    );
  }

  Widget _buildNewSubmissionButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppTheme.spacingLG),
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProjectSubmissionScreen(project: widget.project),
            ),
          ).then((_) => _loadSubmissions());
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          ),
        ),
        child: const Text(
          'New Submission',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSubmissionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Past Submissions (${_submissions.length})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: AppTheme.spacingMD),
        
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppTheme.spacingXL),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_submissions.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingXL),
              child: Column(
                children: [
                  const Icon(Icons.description, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: AppTheme.spacingMD),
                  const Text(
                    'No submissions yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  const Text(
                    'Submit your first progress update',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ..._submissions.map((submission) => _buildSubmissionCard(submission)),
      ],
    );
  }

  Widget _buildSubmissionCard(Map<String, dynamic> submission) {
    final images = submission['images'] as List? ?? [];
    final imageUrls = images.map((img) {
      if (img is String) return img;
      if (img is Map) return img['url'] ?? img['uri'] ?? '';
      return '';
    }).where((url) => url.isNotEmpty).cast<String>().toList();
    
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
          border: Border.all(color: AppTheme.borderLight, width: 0.5),
          boxShadow: AppTheme.shadowSM,
      ),
      child: InkWell(
        onTap: (_userRole?.toLowerCase() == 'principal')
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProjectSubmissionScreen(
                      project: widget.project,
                      submissionId: submission['id'],
                      existingData: submission,
                    ),
                  ),
                ).then((_) => _loadSubmissions());
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _formatDate(submission['createdAt']),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSM,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                ),
                child: Text(
                  '${(submission['percentage'] ?? 0).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.white,
                  ),
                ),
              ),
            ],
          ),
          
          // Author
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            'By ${submission['userName'] ?? 'Unknown User'}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.primary,
            ),
          ),
          
          // Notes
          if (submission['notes'] != null && submission['notes'].toString().isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingMD),
            Text(
              submission['notes'],
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.text,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          
          // Image Gallery
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingMD),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _handleImagePress(images, index),
                    child: Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(right: AppTheme.spacingSM),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                        border: Border.all(color: AppTheme.borderLight, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                        child: Image.network(
                          imageUrls[index],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppTheme.borderLight,
                              child: const Icon(Icons.broken_image, size: 24),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    ));
  }

  Widget _buildImageViewer() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _viewerVisible = false;
        });
      },
      child: Container(
        color: Colors.black.withOpacity(0.95),
        child: Stack(
          children: [
            // Close Button
            Positioned(
              top: 50,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _viewerVisible = false;
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
            
            // Image Viewer
            PageView.builder(
              controller: _imageViewerController,
              itemCount: _viewerImages.length,
              onPageChanged: (index) {
                setState(() {
                  _viewerIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return Center(
                  child: Image.network(
                    _viewerImages[index],
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.broken_image, size: 64, color: Colors.white),
                      );
                    },
                  ),
                );
              },
            ),
            
            // Dots Indicator
            if (_viewerImages.length > 1)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _viewerImages.length,
                    (index) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _viewerIndex == index
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
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
