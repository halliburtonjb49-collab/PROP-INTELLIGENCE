import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_manager.dart';
import '../services/prop_chat_service.dart';
import '../theme/app_colors.dart';

class PropChatPage extends StatefulWidget {
  const PropChatPage({super.key, this.service});

  final PropChatService? service;

  @override
  State<PropChatPage> createState() => _PropChatPageState();
}

class _PropChatPageState extends State<PropChatPage> {
  late final PropChatService _service = widget.service ?? PropChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Set<String> _blockedUserIds = const {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBlocks());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBlocks() async {
    try {
      final blocked = await _service.loadBlockedUserIds();
      if (mounted) setState(() => _blockedUserIds = blocked);
    } catch (_) {}
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _send() async {
    if (_sending || _messageController.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(_messageController.text);
      _messageController.clear();
    } catch (error) {
      _message('Unable to send: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report(PropChatMessage message) async {
    try {
      await _service.reportMessage(message.id, 'Reported from PROP CHAT');
      _message('Message reported for review.');
    } catch (error) {
      _message('Unable to report: $error');
    }
  }

  Future<void> _block(PropChatMessage message) async {
    try {
      await _service.blockUser(message.userId);
      setState(() => _blockedUserIds = {..._blockedUserIds, message.userId});
      _message('@${message.username} has been hidden.');
    } catch (error) {
      _message('Unable to block: $error');
    }
  }

  Future<void> _delete(PropChatMessage message) async {
    try {
      await _service.deleteMessage(message.id);
    } catch (error) {
      _message('Unable to delete: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthManager.instance.sessionState.value;
    final canModerate = auth.isOwner || auth.isAdmin;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF0B1823),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: const Row(
            children: [
              Icon(Icons.forum_rounded, color: AppColors.gold),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROP CHAT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    Text(
                      'Community room · Be respectful · Never share personal information',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<PropChatMessage>>(
            stream: _service.watchMessages(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ChatNotice(
                  icon: Icons.cloud_off_rounded,
                  text:
                      'PROP CHAT is not available yet. The database setup may still need to be applied.',
                );
              }
              final messages = (snapshot.data ?? const <PropChatMessage>[])
                  .where((message) => !_blockedUserIds.contains(message.userId))
                  .toList(growable: false);
              if (messages.isEmpty) {
                return const _ChatNotice(
                  icon: Icons.waving_hand_rounded,
                  text: 'No messages yet. Start the conversation.',
                );
              }
              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(14),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isOwn = message.userId == _service.currentUserId;
                  return _MessageBubble(
                    message: message,
                    isOwn: isOwn,
                    onReport: isOwn ? null : () => _report(message),
                    onBlock: isOwn ? null : () => _block(message),
                    onDelete: isOwn || canModerate
                        ? () => _delete(message)
                        : null,
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF07131D),
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('prop-chat-message-field'),
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message the community…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('prop-chat-send-button'),
                  tooltip: 'Send message',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.onReport,
    required this.onBlock,
    required this.onDelete,
  });

  final PropChatMessage message;
  final bool isOwn;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          color: isOwn ? const Color(0xFF182617) : const Color(0xFF0D1C28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isOwn ? AppColors.gold : AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 6, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${message.username}',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message.body,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        TimeOfDay.fromDateTime(
                          message.createdAt,
                        ).format(context),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Message actions',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                  onSelected: (action) {
                    if (action == 'report') onReport?.call();
                    if (action == 'block') onBlock?.call();
                    if (action == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (onReport != null)
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report message'),
                      ),
                    if (onBlock != null)
                      const PopupMenuItem(
                        value: 'block',
                        child: Text('Block user'),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete message'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatNotice extends StatelessWidget {
  const _ChatNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.gold, size: 38),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
