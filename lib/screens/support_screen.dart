import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _authService = FirebaseAuthService();
  final _firestoreService = FirestoreService();
  String _ticketType = 'Support';
  bool _loading = false;
  bool _isMessageFocused = false;
  List<Map<String, dynamic>> _previousTickets = [];
  bool _loadingTickets = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _messageFocusNode.addListener(() {
      setState(() {
        _isMessageFocused = _messageFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    if (user != null) {
      _nameController.text = user.name;
      _emailController.text = user.email;
      _userId = user.uid;
      _loadPreviousTickets();
    } else {
      setState(() => _loadingTickets = false);
    }
  }

  Future<void> _loadPreviousTickets() async {
    if (_userId == null) return;
    
    setState(() => _loadingTickets = true);
    try {
      final tickets = await _firestoreService.getUserTickets(_userId!);
      setState(() {
        _previousTickets = tickets;
        _loadingTickets = false;
      });
    } catch (e) {
      setState(() => _loadingTickets = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _loading = true);

    try {
      final user = await _authService.getCurrentUser();
      
      final ticketData = {
        'type': _ticketType.toLowerCase(), // 'support' or 'feedback'
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'message': _messageController.text.trim(),
        'userId': user?.uid ?? 'unknown',
        'userName': user?.name ?? _nameController.text.trim(),
        'status': 'open', // open, in-progress, resolved, closed
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await _firestoreService.addTicket(ticketData);

      setState(() => _loading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.white),
                SizedBox(width: AppTheme.spacingSM),
                Text('Ticket submitted successfully!'),
              ],
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            ),
          ),
        );
        _messageController.clear();
        _loadPreviousTickets(); // Refresh ticket list
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: AppTheme.white),
                const SizedBox(width: AppTheme.spacingSM),
                Expanded(child: Text('Error submitting ticket: $e')),
              ],
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.text, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Support / Helpdesk',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingLG),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subtitle
                  const Text(
                    'We\'re here to help! Submit your query or feedback',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing2XL),

                  // Ticket Type Toggle
                  _buildTicketTypeSelector(),

                  const SizedBox(height: AppTheme.spacingLG),

                  // Name Input
                  _buildInputField(
                    controller: _nameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your full name';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: AppTheme.spacingLG),

                  // Email Input
                  _buildInputField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: AppTheme.spacingLG),

                  // Message Input
                  _buildMessageField(),

                  const SizedBox(height: AppTheme.spacingXL),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        disabledBackgroundColor: AppTheme.primary.withOpacity(0.6),
                        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send_outlined, size: 20, color: AppTheme.white),
                                const SizedBox(width: AppTheme.spacingSM),
                                const Text(
                                  'Submit Ticket',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: AppTheme.spacingXL),

                  // Help Section
                  _buildHelpSection(),

                  const SizedBox(height: AppTheme.spacing2XL),

                  // Previous Tickets Section
                  _buildPreviousTicketsSection(),

                  const SizedBox(height: AppTheme.spacingXL),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTicketTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildPill('Feedback', Icons.feedback_outlined),
        ),
        const SizedBox(width: AppTheme.spacingSM),
        Expanded(
          child: _buildPill('Support', Icons.support_agent_outlined),
        ),
      ],
    );
  }

  Widget _buildPill(String label, IconData icon) {
    final isActive = _ticketType == label;
    return GestureDetector(
      onTap: () => setState(() => _ticketType = label),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppTheme.spacingSM,
          horizontal: AppTheme.spacingMD,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : AppTheme.backgroundDark,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? AppTheme.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: AppTheme.spacingSM),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? AppTheme.white : AppTheme.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(
            fontSize: 16,
            color: AppTheme.text,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: 'Enter your $label',
            hintStyle: const TextStyle(
              color: AppTheme.textLight,
              fontSize: 16,
            ),
            prefixIcon: Icon(
              icon,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            filled: true,
            fillColor: AppTheme.backgroundDark,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMD,
              vertical: AppTheme.spacingMD,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: Colors.transparent, width: 0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: Colors.transparent, width: 0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
              borderSide: const BorderSide(color: AppTheme.error, width: 2),
            ),
            errorStyle: const TextStyle(
              fontSize: 12,
              color: AppTheme.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Message',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSM),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            border: Border.all(
              color: _isMessageFocused ? AppTheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: AppTheme.spacingMD,
                  top: AppTheme.spacingMD,
                ),
                child: Icon(
                  Icons.message_outlined,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _messageController,
                  focusNode: _messageFocusNode,
                  maxLines: 6,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your message';
                    }
                    if (value.trim().length < 10) {
                      return 'Please provide more details (at least 10 characters)';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.text,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Describe your issue or feedback in detail...',
                    hintStyle: const TextStyle(
                      color: AppTheme.textLight,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(AppTheme.spacingMD),
                    errorBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorStyle: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHelpSection() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(
          color: AppTheme.primaryLight.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: AppTheme.primary,
              ),
              const SizedBox(width: AppTheme.spacingSM),
              Text(
                'Need immediate help?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMD),
          Text(
            'For urgent matters, please contact us directly through the Contact Us section in your account settings.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviousTicketsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Your Previous Tickets',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.text,
              ),
            ),
            if (_previousTickets.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSM,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_previousTickets.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingMD),
        if (_loadingTickets)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppTheme.spacingXL),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_previousTickets.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingXL),
            decoration: BoxDecoration(
              color: AppTheme.backgroundDark,
              borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                  const Text(
                    'No tickets yet',
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
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _previousTickets.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppTheme.spacingSM),
            itemBuilder: (context, index) {
              final ticket = _previousTickets[index];
              return _buildTicketCard(ticket);
            },
          ),
      ],
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final type = ticket['type'] ?? 'support';
    final status = ticket['status'] ?? 'open';
    final message = ticket['message'] ?? '';
    final createdAt = ticket['createdAt'] ?? '';
    
    Color statusColor;
    String statusText;
    switch (status.toLowerCase()) {
      case 'open':
        statusColor = AppTheme.warning;
        statusText = 'Open';
        break;
      case 'in-progress':
        statusColor = AppTheme.primary;
        statusText = 'In Progress';
        break;
      case 'resolved':
        statusColor = AppTheme.success;
        statusText = 'Resolved';
        break;
      case 'closed':
        statusColor = AppTheme.textSecondary;
        statusText = 'Closed';
        break;
      default:
        statusColor = AppTheme.textSecondary;
        statusText = status;
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
        border: Border.all(color: AppTheme.borderLight, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSM,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: type == 'feedback' 
                      ? AppTheme.secondary.withValues(alpha: 0.1)
                      : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      type == 'feedback' ? Icons.feedback_outlined : Icons.support_agent_outlined,
                      size: 12,
                      color: type == 'feedback' ? AppTheme.secondary : AppTheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      type.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: type == 'feedback' ? AppTheme.secondary : AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingSM),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSM,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              const Spacer(),
              // Date
              Text(
                _formatTicketDate(createdAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            message.length > 150 ? '${message.substring(0, 150)}...' : message,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.text,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTicketDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }
}
