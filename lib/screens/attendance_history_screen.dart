import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/attendance_service.dart';
import '../models/daily_attendance.dart';
import '../theme/app_theme.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  List<DailyAttendance> _dailyRecords = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'present', 'absent'

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final allRecords = await _attendanceService.getDailyAttendanceHistory();
      
      // Filter logic
      List<DailyAttendance> filtered = allRecords;
      if (_filter == 'present') {
        filtered = allRecords.where((d) => d.isPresent).toList();
      } else if (_filter == 'absent') {
        filtered = allRecords.where((d) => !d.isPresent).toList();
      }

      if (mounted) {
        setState(() {
          _dailyRecords = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      child: SafeArea(
        child: Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          body: Column(
            children: [
              // Header
              _buildHeader(),
              
              // Filters
              _buildFilters(),
              
              // Records List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _dailyRecords.isEmpty
                        ? _buildEmptyState()
                        : _buildRecordsList(),
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
        horizontal: AppTheme.spacing2XL,
        vertical: AppTheme.spacingXL,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 1),
        ),
      ),
      child: const Text(
        'Attendance History',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: AppTheme.text,
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      child: Row(
        children: [
          Expanded(
            child: _buildFilterButton('all', 'All'),
          ),
          const SizedBox(width: AppTheme.spacingSM),
          Expanded(
            child: _buildFilterButton('present', 'Present'),
          ),
          const SizedBox(width: AppTheme.spacingSM),
          Expanded(
            child: _buildFilterButton('absent', 'Absent'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String filter, String label) {
    final isActive = _filter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = filter;
        });
        _loadRecords();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppTheme.spacingSM,
          horizontal: AppTheme.spacingMD,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : AppTheme.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(
            color: isActive ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? AppTheme.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.access_time,
            size: 64,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: AppTheme.spacingLG),
          const Text(
            'No attendance records',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            _filter == 'all'
                ? 'Attendance records will appear here once marked'
                : 'No ${_filter.replaceAll('_', ' ')} records found',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    return RefreshIndicator(
      onRefresh: () async {
        _loadRecords();
      },
      child: ListView.builder(
        itemCount: _dailyRecords.length,
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        itemBuilder: (context, index) {
          return _buildDailyCard(_dailyRecords[index]);
        },
      ),
    );
  }



  Widget _buildDailyCard(DailyAttendance day) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusBase)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(AppTheme.spacingMD, 0, AppTheme.spacingMD, AppTheme.spacingMD),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: day.isPresent ? AppTheme.successLight : AppTheme.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  day.isPresent ? Icons.check : Icons.close,
                  color: day.isPresent ? AppTheme.success : AppTheme.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppTheme.spacingMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(DateTime.parse(day.date)),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      day.isPresent 
                        ? (day.autoCheckedOut 
                            ? 'Auto Checked-Out' 
                            : (day.checkoutTime != null ? 'Present' : 'Active'))
                        : 'Absent',
                      style: TextStyle(
                        color: day.isPresent ? AppTheme.success : AppTheme.error,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          subtitle: day.isPresent ? Padding(
            padding: const EdgeInsets.only(top: 8, left: 50),
            child: Row(
              children: [
                if (day.checkInTime != null)
                  _buildMiniTimePill('In: ${_formatTime(day.checkInTime!)}', AppTheme.primaryLight, AppTheme.primary),
                const SizedBox(width: 8),
                if (day.checkoutTime != null)
                  _buildMiniTimePill('Out: ${_formatTime(day.checkoutTime!)}', AppTheme.secondary.withValues(alpha: 0.1), AppTheme.secondary),
              ],
            ),
          ) : null,
          children: [
            const Divider(),
            if (day.events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('No details available.', style: TextStyle(color: AppTheme.textSecondary)),
              )
            else
              ...day.events.map((event) => _buildEventRow(event)),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniTimePill(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEventRow(Map<String, dynamic> event) {
    final type = event['type'] ?? 'unknown';
    final timeStr = event['time'] as String?;
    final time = timeStr != null ? DateTime.parse(timeStr) : DateTime.now();
    final isCheckIn = type == 'check_in';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
           Column(
             children: [
               Container(
                 width: 2,
                 height: 10,
                 color: AppTheme.borderLight,
               ),
               Container(
                 width: 10,
                 height: 10,
                 decoration: BoxDecoration(
                   color: isCheckIn ? AppTheme.success : AppTheme.warning,
                   shape: BoxShape.circle,
                 ),
               ),
               Container(
                 width: 2,
                 height: 10,
                 color: AppTheme.borderLight,
               ),
             ],
           ),
           const SizedBox(width: AppTheme.spacingMD),
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   isCheckIn ? 'Checked In' : 'Checked Out',
                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                 ),
                 Text(
                   _formatTime(time),
                   style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                 ),
               ],
             ),
           ),
        ],
      ),
    );
  }
  String _formatDate(DateTime dateTime) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${weekdays[dateTime.weekday - 1]}, ${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
