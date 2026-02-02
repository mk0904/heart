import 'package:flutter/material.dart';
import '../services/attendance_service.dart';
import '../models/attendance_record.dart';
import '../theme/app_theme.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  List<AttendanceRecord> _records = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'check-in', 'check-out' (mapped to check_in/check_out)

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
      final allRecords = await _attendanceService.getAttendanceHistory();
      // Map filter values to match model (check-in -> check_in, check-out -> check_out)
      final filterValue = _filter == 'check-in' 
          ? 'check_in' 
          : _filter == 'check-out' 
              ? 'check_out' 
              : _filter;
      final filtered = _filter == 'all'
          ? allRecords
          : allRecords.where((r) => r.type == filterValue).toList();
      if (mounted) {
        setState(() {
          _records = filtered;
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                  : _records.isEmpty
                      ? _buildEmptyState()
                      : _buildRecordsList(),
            ),
          ],
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
            child: _buildFilterButton('check-in', 'Check In'),
          ),
          const SizedBox(width: AppTheme.spacingSM),
          Expanded(
            child: _buildFilterButton('check-out', 'Check Out'),
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
        itemCount: _records.length,
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        itemBuilder: (context, index) {
          final record = _records[index];
          return _buildRecordCard(record);
        },
      ),
    );
  }

  Widget _buildRecordCard(AttendanceRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      padding: const EdgeInsets.all(AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        boxShadow: AppTheme.shadowBase,
      ),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundDark,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
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
                      record.personName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${record.employeeId}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMD,
                  vertical: AppTheme.spacingXS,
                ),
                decoration: BoxDecoration(
                  color: record.type == 'check_in'
                      ? AppTheme.successLight
                      : AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  record.type == 'check_in' ? 'IN' : 'OUT',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMD),
          // Details
          Container(
            padding: const EdgeInsets.only(top: AppTheme.spacingMD),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.borderLight, width: 1),
              ),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  Icons.access_time,
                  '${_formatDate(record.timestamp)} at ${_formatTime(record.timestamp)}',
                ),
                const SizedBox(height: AppTheme.spacingXS),
                _buildDetailRow(
                  Icons.check_circle,
                  'Confidence: ${(record.confidence * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: AppTheme.spacingSM),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
