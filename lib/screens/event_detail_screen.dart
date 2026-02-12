import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/image_full_screen_view.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();


  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> _getDisplayImages() {
    final images = widget.event['images'] as List?;
    if (images == null) return [];
    
    return images.map((img) {
      if (img is String) return img;
      if (img is Map) return img['uri'] ?? img['url'] ?? '';
      return '';
    }).where((url) => url.isNotEmpty).cast<String>().toList();
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'TBA';
    try {
      final date = DateTime.parse(dateString);
      final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _formatTime(String? timeString) {
    return timeString ?? 'TBA';
  }

  @override
  Widget build(BuildContext context) {
    final displayImages = _getDisplayImages();
    
    if (widget.event.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: AppBar(
          title: const Text('Event Details'),
          backgroundColor: AppTheme.white,
          foregroundColor: AppTheme.text,
        ),
        body: const Center(
          child: Text('Event not found'),
        ),
      );
    }

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
                child: Column(
                  children: [
                    // Image Gallery Slider
                    if (displayImages.isNotEmpty)
                      _buildImageGallery(displayImages)
                    else
                      _buildEmptyImagePlaceholder(),
                    
                    // Event Details
                    _buildDetailsSection(),
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
                'Event Details',
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

  Widget _buildImageGallery(List<String> images) {
    return Container(
      height: 250,
      margin: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.borderLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: images.length,
              onPageChanged: (index) {
                setState(() {
                  _currentImageIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ImageFullScreenView(
                          images: images,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  child: Image.network(
                    images[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: AppTheme.borderLight,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: AppTheme.borderLight,
                        child: const Center(
                          child: Icon(Icons.broken_image, size: 32, color: AppTheme.textSecondary),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            // Image Counter
            if (images.length > 1)
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  ),
                  child: Text(
                    '${_currentImageIndex + 1} / ${images.length}',
                    style: const TextStyle(
                      color: AppTheme.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            // Navigation Dots
            if (images.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (index) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentImageIndex == index
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

  Widget _buildEmptyImagePlaceholder() {
    return Container(
      height: 250,
      margin: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.borderLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
      ),
      child: const Center(
        child: Icon(Icons.event, size: 48, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
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
          // Event Title
          Text(
            widget.event['title'] ?? 'Untitled Event',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          
          // Event Description
          if (widget.event['description'] != null) ...[
            const SizedBox(height: AppTheme.spacingSM),
            Text(
              widget.event['description'],
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          
          const SizedBox(height: AppTheme.spacingLG),
          
          // Info Cards Container
          Column(
            children: [
              // Date & Time Card
              _buildInfoCard(
                icon: Icons.calendar_today,
                title: 'Date & Time',
                children: [
                  _buildInfoRow(
                    icon: Icons.access_time,
                    label: 'Starts',
                    value: '${_formatDate(widget.event['startDate'])} • ${_formatTime(widget.event['startTime'])}',
                  ),
                  const Divider(height: 1, color: AppTheme.borderLight),
                  _buildInfoRow(
                    icon: Icons.access_time,
                    label: 'Ends',
                    value: '${_formatDate(widget.event['endDate'])} • ${_formatTime(widget.event['endTime'])}',
                  ),
                ],
              ),
              
              const SizedBox(height: AppTheme.spacingMD),
              
              // Location Card
              _buildInfoCard(
                icon: Icons.location_on,
                title: 'Location',
                children: [
                  _buildInfoRow(
                    label: 'Venue',
                    value: widget.event['venue'] ?? 'TBA',
                  ),
                  if (widget.event['district'] != null) ...[
                    const Divider(height: 1, color: AppTheme.borderLight),
                    _buildInfoRow(
                      label: 'District',
                      value: widget.event['district'],
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: AppTheme.spacingMD),
              
              // Organizer Card
              _buildInfoCard(
                icon: Icons.person,
                title: 'Organizer',
                children: [
                  _buildInfoRow(
                    label: 'Name',
                    value: widget.event['organizedBy'] ?? 'Organizer',
                  ),
                ],
              ),
              
              // Participants Card
              if (widget.event['maleParticipants'] != null || widget.event['femaleParticipants'] != null) ...[
                const SizedBox(height: AppTheme.spacingMD),
                _buildInfoCard(
                  icon: Icons.people,
                  title: 'Participants',
                  children: [
                    _buildInfoRow(
                      label: 'Male',
                      value: '${widget.event['maleParticipants'] ?? 0}',
                    ),
                    const Divider(height: 1, color: AppTheme.borderLight),
                    _buildInfoRow(
                      label: 'Female',
                      value: '${widget.event['femaleParticipants'] ?? 0}',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.spacingSM,
        horizontal: 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.primary),
              const SizedBox(width: AppTheme.spacingSM),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXS),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    IconData? icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: AppTheme.spacingXS),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
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
