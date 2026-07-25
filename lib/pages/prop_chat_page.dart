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
  List<PropChatRoom> _rooms = const [
    PropChatRoom(id: 'general', name: 'General'),
  ];
  Set<String> _blockedUserIds = const {};
  String _roomId = 'general';
  PropChatMessage? _replyingTo;
  DateTime? _lastRead;
  Timer? _typingTimer;
  Timer? _presenceTimer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
    _messageController.addListener(_typingChanged);
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_service.updatePresence(_roomId, isTyping: false)),
    );
  }

  Future<void> _initialize() async {
    try {
      final values = await Future.wait([
        _service.loadRooms(),
        _service.loadBlockedUserIds(),
        _service.localLastRead(_roomId),
      ]);
      if (!mounted) return;
      setState(() {
        _rooms = values[0] as List<PropChatRoom>;
        _blockedUserIds = values[1] as Set<String>;
        _lastRead = values[2] as DateTime?;
      });
      await _service.updatePresence(_roomId, isTyping: false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _presenceTimer?.cancel();
    unawaited(_service.updatePresence(_roomId, isTyping: false));
    _messageController
      ..removeListener(_typingChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _typingChanged() {
    _typingTimer?.cancel();
    unawaited(
      _service.updatePresence(
        _roomId,
        isTyping: _messageController.text.trim().isNotEmpty,
      ),
    );
    _typingTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_service.updatePresence(_roomId, isTyping: false)),
    );
  }

  void _notice(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('CONFIRM'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _selectRoom(String roomId) async {
    if (roomId == _roomId) return;
    await _service.updatePresence(_roomId, isTyping: false);
    final lastRead = await _service.localLastRead(roomId);
    if (!mounted) return;
    setState(() {
      _roomId = roomId;
      _lastRead = lastRead;
      _replyingTo = null;
    });
    await _service.updatePresence(roomId, isTyping: false);
  }

  Future<void> _send() async {
    if (_sending || _messageController.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(
        _messageController.text,
        roomId: _roomId,
        replyToId: _replyingTo?.id,
      );
      _messageController.clear();
      setState(() => _replyingTo = null);
    } catch (error) {
      _notice('Unable to send: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _edit(PropChatMessage message) async {
    final controller = TextEditingController(text: message.body);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('EDIT MESSAGE'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || updated.isEmpty || updated == message.body) return;
    try {
      await _service.editMessage(message.id, updated);
    } catch (error) {
      _notice('Unable to edit: $error');
    }
  }

  Future<void> _delete(PropChatMessage message) async {
    if (!await _confirm('Delete message?', 'This action cannot be undone.')) {
      return;
    }
    try {
      await _service.deleteMessage(message.id);
    } catch (error) {
      _notice('Unable to delete: $error');
    }
  }

  Future<void> _report(PropChatMessage message) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('REPORT MESSAGE'),
        children: [
          for (final value in const [
            'Spam or scam',
            'Harassment',
            'Hate or abusive content',
            'Dangerous misinformation',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text(value),
            ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _service.reportMessage(message.id, reason);
      _notice('Message reported for review.');
    } catch (error) {
      _notice('Unable to report: $error');
    }
  }

  Future<void> _block(PropChatMessage message) async {
    if (!await _confirm(
      'Block @${message.username}?',
      'Their messages will be hidden from your chat.',
    )) {
      return;
    }
    try {
      await _service.blockUser(message.userId);
      setState(() => _blockedUserIds = {..._blockedUserIds, message.userId});
      _notice('@${message.username} has been hidden.');
    } catch (error) {
      _notice('Unable to block: $error');
    }
  }

  Future<void> _editUsername() async {
    final controller = TextEditingController(
      text: AuthManager.instance.sessionState.value.username ?? '',
    );
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PUBLIC USERNAME'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 24,
              decoration: const InputDecoration(hintText: 'prop_fan'),
            ),
            const Text(
              '3–24 letters, numbers, or underscores. Must start with a letter.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (username == null || username.isEmpty) return;
    try {
      final saved = await _service.updateUsername(username);
      AuthManager.instance.setPublicUsername(saved);
      _notice('Your public username is now @$saved.');
    } catch (error) {
      _notice('Unable to save username: $error');
    }
  }

  Future<void> _preferences() async {
    var preferences = await _service.loadPreferences();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('CHAT SETTINGS'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Chat notifications'),
                value: preferences.notificationsEnabled,
                onChanged: (value) => setDialogState(
                  () => preferences = PropChatPreferences(
                    notificationsEnabled: value,
                    soundsEnabled: preferences.soundsEnabled,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('Message sounds'),
                value: preferences.soundsEnabled,
                onChanged: (value) => setDialogState(
                  () => preferences = PropChatPreferences(
                    notificationsEnabled: preferences.notificationsEnabled,
                    soundsEnabled: value,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await _service.savePreferences(preferences);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
  }

  void _guidelines() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PROP CHAT COMMUNITY GUIDELINES'),
        content: const SingleChildScrollView(
          child: Text(
            'Be respectful and discuss sports in good faith.\n\n'
            'Do not share personal information, payment details, private account information, links, spam, threats, harassment, hate speech, or claims of guaranteed winnings.\n\n'
            'Messages may be retained for safety and moderation. Reported-message evidence is preserved even if the original message is removed. Repeated violations may lead to warnings, mutes, suspension, or a permanent ban.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I UNDERSTAND'),
          ),
        ],
      ),
    );
  }

  Future<void> _moderation() async {
    try {
      final results = await Future.wait([
        _service.loadOpenReports(),
        _service.loadHealth(),
        _service.loadOperationalAlerts(),
      ]);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ModerationDialog(
          reports: results[0] as List<PropChatReport>,
          health: results[1] as Map<String, dynamic>,
          alerts: results[2] as List<PropChatOperationalAlert>,
          service: _service,
          onNotice: _notice,
        ),
      );
    } catch (error) {
      _notice('Unable to load moderation: $error');
    }
  }

  void _afterMessages(List<PropChatMessage> messages) {
    final unread = _lastRead == null
        ? 0
        : messages
              .where((message) => message.createdAt.isAfter(_lastRead!))
              .length;
    PropChatService.unreadCount.value = unread;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      unawaited(_service.markRoomRead(_roomId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthManager.instance.sessionState.value;
    final canModerate = auth.isOwner || auth.isAdmin;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.panel, AppColors.background],
        ),
      ),
      child: Column(
        children: [
          _ChatHeader(
            roomId: _roomId,
            presence: _service.watchPresence(_roomId),
            canModerate: canModerate,
            onUsername: _editUsername,
            onSettings: _preferences,
            onGuidelines: _guidelines,
            onModeration: _moderation,
          ),
          StreamBuilder<List<PropChatModerationNotice>>(
            stream: _service.watchModerationNotices(),
            builder: (context, snapshot) {
              final notices = snapshot.data ?? const [];
              if (notices.isEmpty) return const SizedBox.shrink();
              final notice = notices.first;
              return MaterialBanner(
                backgroundColor: AppColors.panelLight,
                leading: const Icon(Icons.gavel_rounded, color: AppColors.gold),
                content: Text(
                  '${notice.restriction.toUpperCase()}: ${notice.reason}'
                  '${notice.expiresAt == null ? '' : '\nExpires ${notice.expiresAt!.toLocal()}'}',
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        _service.acknowledgeModerationNotice(notice.id),
                    child: const Text('ACKNOWLEDGE'),
                  ),
                ],
              );
            },
          ),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: _rooms.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return ChoiceChip(
                  label: Text(room.name.toUpperCase()),
                  selected: room.id == _roomId,
                  onSelected: (_) => _selectRoom(room.id),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: StreamBuilder<List<PropChatMessage>>(
              stream: _service.watchMessages(roomId: _roomId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _ChatNotice(
                    icon: Icons.cloud_off_rounded,
                    text: 'Live chat temporarily disconnected. Retrying…',
                  );
                }
                final messages = (snapshot.data ?? const <PropChatMessage>[])
                    .where(
                      (message) => !_blockedUserIds.contains(message.userId),
                    )
                    .toList(growable: false);
                if (messages.isEmpty) {
                  return const _ChatNotice(
                    icon: Icons.waving_hand_rounded,
                    text: 'No messages yet. Start the conversation.',
                  );
                }
                _afterMessages(messages);
                final firstUnread = _lastRead == null
                    ? -1
                    : messages.indexWhere(
                        (message) => message.createdAt.isAfter(_lastRead!),
                      );
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final previous = index == 0 ? null : messages[index - 1];
                    final showDate =
                        previous == null ||
                        DateUtils.dateOnly(previous.createdAt) !=
                            DateUtils.dateOnly(message.createdAt);
                    final isOwn = message.userId == _service.currentUserId;
                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: message.createdAt),
                        if (index == firstUnread)
                          const _SectionDivider(label: 'NEW MESSAGES'),
                        _MessageBubble(
                          message: message,
                          reply: message.replyToId == null
                              ? null
                              : messages
                                    .where(
                                      (candidate) =>
                                          candidate.id == message.replyToId,
                                    )
                                    .firstOrNull,
                          isOwn: isOwn,
                          onReply: () => setState(() => _replyingTo = message),
                          onReact: (emoji) =>
                              _service.toggleReaction(message.id, emoji),
                          onEdit: isOwn ? () => _edit(message) : null,
                          onReport: isOwn ? null : () => _report(message),
                          onBlock: isOwn ? null : () => _block(message),
                          onDelete: isOwn || canModerate
                              ? () => _delete(message)
                              : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_replyingTo != null)
            _ReplyComposerBanner(
              message: _replyingTo!,
              onCancel: () => setState(() => _replyingTo = null),
            ),
          _Composer(
            controller: _messageController,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.roomId,
    required this.presence,
    required this.canModerate,
    required this.onUsername,
    required this.onSettings,
    required this.onGuidelines,
    required this.onModeration,
  });
  final String roomId;
  final Stream<List<Map<String, dynamic>>> presence;
  final bool canModerate;
  final VoidCallback onUsername;
  final VoidCallback onSettings;
  final VoidCallback onGuidelines;
  final VoidCallback onModeration;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.borderGold)),
      ),
      child: Row(
        children: [
          const Icon(Icons.forum_rounded, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: presence,
              builder: (context, snapshot) {
                final users = snapshot.data ?? const [];
                final typing = users
                    .where((row) => row['is_typing'] == true)
                    .length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PROP CHAT',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    Text(
                      typing > 0
                          ? '$typing ${typing == 1 ? 'person is' : 'people are'} typing…'
                          : '${users.length} online · #$roomId',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'PROP CHAT options',
            icon: const Icon(Icons.tune_rounded, color: AppColors.silver),
            onSelected: (value) {
              if (value == 'username') onUsername();
              if (value == 'settings') onSettings();
              if (value == 'guidelines') onGuidelines();
              if (value == 'moderation') onModeration();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'username',
                child: Text('Edit public username'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Notification settings'),
              ),
              const PopupMenuItem(
                value: 'guidelines',
                child: Text('Community guidelines'),
              ),
              if (canModerate)
                const PopupMenuItem(
                  value: 'moderation',
                  child: Text('Moderation dashboard'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.reply,
    required this.isOwn,
    required this.onReply,
    required this.onReact,
    required this.onEdit,
    required this.onReport,
    required this.onBlock,
    required this.onDelete,
  });
  final PropChatMessage message;
  final PropChatMessage? reply;
  final bool isOwn;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;
  final VoidCallback? onEdit;
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
          color: isOwn ? AppColors.panelLight : AppColors.panel,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isOwn ? AppColors.gold : AppColors.gunmetalLight,
              width: isOwn ? 1.4 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '@${message.username}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isOwn
                                    ? AppColors.gold
                                    : AppColors.silver,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (message.isVerified) ...[
                            const SizedBox(width: 5),
                            const Tooltip(
                              message: 'Verified PROP INTELLIGENCE staff',
                              child: Icon(
                                Icons.verified_rounded,
                                size: 15,
                                color: AppColors.blue,
                              ),
                            ),
                          ],
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
                        if (action == 'reply') onReply();
                        if (action == 'edit') onEdit?.call();
                        if (action == 'report') onReport?.call();
                        if (action == 'block') onBlock?.call();
                        if (action == 'delete') onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'reply',
                          child: Text('Reply'),
                        ),
                        if (onEdit != null)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit message'),
                          ),
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
                if (reply != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.sidebar,
                      border: Border(
                        left: BorderSide(color: AppColors.gold, width: 3),
                      ),
                    ),
                    child: Text(
                      '@${reply!.username}: ${reply!.body}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                Text(
                  message.body,
                  style: const TextStyle(color: AppColors.white, height: 1.35),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final emoji in const ['👍', '🔥', '👀'])
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '$emoji ${message.reactions[emoji] ?? ''}'.trim(),
                        ),
                        onPressed: () => onReact(emoji),
                      ),
                    Text(
                      '${_formatTimestamp(message.createdAt)}${message.editedAt == null ? '' : ' · edited'}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                      ),
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: AppColors.sidebar,
          border: Border(top: BorderSide(color: AppColors.borderGold)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('prop-chat-message-field'),
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Message the community…',
                  counterText: '',
                  fillColor: AppColors.panel,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('prop-chat-send-button'),
              tooltip: 'Send message',
              onPressed: sending ? null : onSend,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                disabledBackgroundColor: AppColors.gunmetal,
              ),
              icon: sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyComposerBanner extends StatelessWidget {
  const _ReplyComposerBanner({required this.message, required this.onCancel});
  final PropChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: AppColors.panelLight,
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, color: AppColors.gold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Replying to @${message.username}',
              style: const TextStyle(color: AppColors.silver, fontSize: 11),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ModerationDialog extends StatefulWidget {
  const _ModerationDialog({
    required this.reports,
    required this.health,
    required this.alerts,
    required this.service,
    required this.onNotice,
  });
  final List<PropChatReport> reports;
  final Map<String, dynamic> health;
  final List<PropChatOperationalAlert> alerts;
  final PropChatService service;
  final ValueChanged<String> onNotice;

  @override
  State<_ModerationDialog> createState() => _ModerationDialogState();
}

class _ModerationDialogState extends State<_ModerationDialog> {
  late final List<PropChatReport> reports = [...widget.reports];
  late final List<PropChatOperationalAlert> alerts = [...widget.alerts];

  Future<void> _act(PropChatReport report, String action) async {
    if (action == 'dismiss') {
      await widget.service.resolveReport(report.id, 'dismissed');
    } else {
      final expiry = switch (action) {
        'muted' => DateTime.now().add(const Duration(hours: 24)),
        'suspended' => DateTime.now().add(const Duration(days: 7)),
        _ => null,
      };
      await widget.service.restrictUser(
        report.userId,
        action,
        reason: report.reason,
        expiresAt: expiry,
      );
      await widget.service.resolveReport(report.id, 'resolved');
    }
    setState(() => reports.remove(report));
    widget.onNotice('Moderation action saved.');
  }

  Future<void> _addBlockedTerm() async {
    final controller = TextEditingController();
    final term = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ADD BLOCKED TERM'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Phrase to block'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (term == null || term.length < 2) return;
    await widget.service.addBlockedTerm(term);
    widget.onNotice('Safety filter updated.');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('MODERATION · ${reports.length} OPEN'),
      content: SizedBox(
        width: 680,
        child: ListView(
          shrinkWrap: true,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('${widget.health['online_users'] ?? 0} ONLINE'),
                ),
                Chip(
                  label: Text(
                    '${widget.health['messages_24h'] ?? 0} MESSAGES / 24H',
                  ),
                ),
                Chip(
                  label: Text(
                    '${widget.health['open_reports'] ?? reports.length} REPORTS',
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.filter_alt_rounded, size: 17),
                  label: const Text('ADD BLOCKED TERM'),
                  onPressed: _addBlockedTerm,
                ),
              ],
            ),
            if (alerts.isNotEmpty) ...[
              const Divider(),
              const Text(
                'OPERATIONAL ALERTS',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              for (final alert in alerts)
                ListTile(
                  leading: Icon(
                    alert.severity == 'critical'
                        ? Icons.error_rounded
                        : Icons.warning_rounded,
                    color: alert.severity == 'critical'
                        ? AppColors.red
                        : AppColors.gold,
                  ),
                  title: Text(alert.type.replaceAll('_', ' ').toUpperCase()),
                  subtitle: Text('${alert.details}'),
                  trailing: TextButton(
                    onPressed: () async {
                      await widget.service.resolveOperationalAlert(alert.id);
                      setState(() => alerts.remove(alert));
                    },
                    child: const Text('RESOLVE'),
                  ),
                ),
            ],
            const Divider(),
            if (reports.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('No open reports.')),
              )
            else
              for (final report in reports)
                ListTile(
                  title: Text('@${report.username}: ${report.body}'),
                  subtitle: Text('Reason: ${report.reason}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _act(report, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'warned',
                        child: Text('Issue warning'),
                      ),
                      PopupMenuItem(
                        value: 'muted',
                        child: Text('Mute 24 hours'),
                      ),
                      PopupMenuItem(
                        value: 'suspended',
                        child: Text('Suspend 7 days'),
                      ),
                      PopupMenuItem(
                        value: 'banned',
                        child: Text('Permanent ban'),
                      ),
                      PopupMenuItem(
                        value: 'dismiss',
                        child: Text('Dismiss report'),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final value = DateUtils.isSameDay(date, now)
        ? 'TODAY'
        : DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))
        ? 'YESTERDAY'
        : '${date.month}/${date.day}/${date.year}';
    return _SectionDivider(label: value);
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
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

String _formatTimestamp(DateTime value) {
  final now = DateTime.now();
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return DateUtils.isSameDay(value, now)
      ? '$hour:$minute $period'
      : '${value.month}/${value.day} · $hour:$minute $period';
}
