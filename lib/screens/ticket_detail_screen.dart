import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/user_friendly_errors.dart';

/// Chat thread for a helpdesk ticket: `tickets/{id}/messages` + original [ticket] body.
class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final _firestoreService = FirestoreService();
  final _authService = FirebaseAuthService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  String get _ticketId => widget.ticket['id'] as String? ?? '';

  /// Inlined here so hot reload does not hit "Lookup failed" on new [FirestoreService] methods.
  Stream<List<Map<String, dynamic>>> _ticketMessagesStream() {
    if (_ticketId.isEmpty) {
      return const Stream<List<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance
        .collection('tickets')
        .doc(_ticketId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  Map<String, dynamic> _effectiveTicket(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = Map<String, dynamic>.from(widget.ticket);
    if (doc.data() != null) {
      m.addAll(doc.data()!);
    }
    m['id'] = _ticketId;
    return m;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty || _sending) return;

    final user = await _authService.getCurrentUser();
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in again')),
        );
      }
      return;
    }

    setState(() => _sending = true);
    try {
      await _firestoreService.addUserTicketMessage(
        ticketId: _ticketId,
        senderId: user.uid,
        senderName: user.name.trim().isEmpty ? (user.email) : user.name,
        text: text,
      );
      _textController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyErrors.message(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    final d = t;
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .doc(_ticketId)
          .snapshots(),
      builder: (context, ticketSnap) {
        final doc = ticketSnap.hasData ? ticketSnap.data : null;
        final effective = doc == null || !doc.exists
            ? (Map<String, dynamic>.from(widget.ticket)..['id'] = _ticketId)
            : _effectiveTicket(doc);

        final type = effective['type'] ?? 'support';
        final status = (effective['status'] ?? 'open').toString().toLowerCase().trim();
        final canReply = status != 'closed' && status != 'resolved';
        final initialBody = (effective['message'] ?? '').toString().trim();

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.white,
            statusBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: AppTheme.backgroundLight,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.text),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ticket',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text,
                    ),
                  ),
                  Text(
                    '${type.toString().toUpperCase()} · ${status.toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            body: Column(
              children: [
                if (status == 'closed')
                  Material(
                    color: AppTheme.warningLight.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMD,
                        vertical: AppTheme.spacingSM,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, size: 18, color: AppTheme.warning),
                          const SizedBox(width: AppTheme.spacingSM),
                          Expanded(
                            child: Text(
                              'This ticket is closed. You can read the thread but new replies are disabled.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.text.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _ticketMessagesStream(),
                    builder: (context, snapshot) {
                      final streamErr = snapshot.hasError ? snapshot.error! : null;
                      final messages = snapshot.hasData ? snapshot.data! : <Map<String, dynamic>>[];

                      return ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppTheme.spacingMD),
                        children: [
                          if (streamErr != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppTheme.spacingMD),
                              child: Material(
                                color: AppTheme.warningLight.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppTheme.spacingMD),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
                                      const SizedBox(width: AppTheme.spacingSM),
                                      Expanded(
                                        child: Text(
                                          'Could not load live replies (${UserFriendlyErrors.message(streamErr)}). '
                                          'Your original message and any cached content still appear below.',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: AppTheme.text,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (initialBody.isNotEmpty) ...[
                            _bubble(
                              isUser: true,
                              name: (effective['userName'] ?? effective['name'] ?? 'You').toString(),
                              text: initialBody,
                              time: _parseTime(effective['createdAt']),
                              subtitle: 'Original request',
                            ),
                            const SizedBox(height: AppTheme.spacingSM),
                          ],
                          for (final m in messages) ...[
                            _bubbleFromMessage(m),
                            const SizedBox(height: AppTheme.spacingSM),
                          ],
                          if (initialBody.isEmpty &&
                              messages.isEmpty &&
                              streamErr == null &&
                              snapshot.connectionState == ConnectionState.waiting)
                            const Padding(
                              padding: EdgeInsets.only(top: 48),
                              child: Center(
                                child: Text(
                                  'Loading conversation…',
                                  style: TextStyle(color: AppTheme.textSecondary),
                                ),
                              ),
                            ),
                          if (initialBody.isEmpty &&
                              messages.isEmpty &&
                              streamErr == null &&
                              snapshot.connectionState != ConnectionState.waiting)
                            Padding(
                              padding: const EdgeInsets.only(top: 48),
                              child: Center(
                                child: Text(
                                  canReply
                                      ? 'No messages yet. Say hello below.'
                                      : 'No messages in this thread.',
                                  style: const TextStyle(color: AppTheme.textSecondary),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (canReply)
                  SafeArea(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingMD,
                        AppTheme.spacingSM,
                        AppTheme.spacingMD,
                        AppTheme.spacingMD,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 4000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Type a message…',
                                filled: true,
                                fillColor: AppTheme.backgroundDark,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.spacingMD,
                                  vertical: AppTheme.spacingSM,
                                ),
                                counterText: '',
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingSM),
                          IconButton.filled(
                            onPressed: _sending ? null : _send,
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: AppTheme.white,
                            ),
                            icon: _sending
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!canReply && status == 'resolved')
                  SafeArea(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingMD,
                        AppTheme.spacingMD,
                        AppTheme.spacingMD,
                        AppTheme.spacingLG,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.08),
                        border: Border(
                          top: BorderSide(color: AppTheme.success.withValues(alpha: 0.25)),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle, size: 12, color: AppTheme.success),
                          const SizedBox(width: AppTheme.spacingSM),
                          Expanded(
                            child: Text(
                              'This ticket is resolved. You can’t add more messages — scroll up to read the full conversation.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.text.withValues(alpha: 0.88),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bubbleFromMessage(Map<String, dynamic> m) {
    final role = (m['senderRole'] ?? 'user').toString().toLowerCase();
    final isUser = role == 'user';
    final name = (m['senderName'] ?? '').toString();
    final text = (m['text'] ?? '').toString();
    return _bubble(
      isUser: isUser,
      name: name.isEmpty ? (isUser ? 'You' : 'Support') : name,
      text: text,
      time: _parseTime(m['createdAt']),
    );
  }

  Widget _bubble({
    required bool isUser,
    required String name,
    required String text,
    required DateTime? time,
    String? subtitle,
  }) {
    final bg = isUser ? AppTheme.primary : AppTheme.backgroundDark;
    final fg = isUser ? AppTheme.white : AppTheme.text;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMD,
            vertical: AppTheme.spacingSM,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.radiusBase),
            border: isUser
                ? null
                : Border.all(color: AppTheme.borderLight, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isUser
                          ? AppTheme.white.withValues(alpha: 0.85)
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isUser ? AppTheme.white.withValues(alpha: 0.9) : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: fg,
                ),
              ),
              if (time != null) ...[
                const SizedBox(height: 6),
                Text(
                  _formatTime(time),
                  style: TextStyle(
                    fontSize: 11,
                    color: isUser
                        ? AppTheme.white.withValues(alpha: 0.75)
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
