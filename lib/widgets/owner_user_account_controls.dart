import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/prop_chat_service.dart';
import '../theme/app_colors.dart';

Future<void> showOwnerUserRoleManager(
  BuildContext context, {
  required ValueChanged<String> showMessage,
}) async {
  final emailController = TextEditingController();
  final founderNumberController = TextEditingController();
  var selectedRole = 'admin';
  var sendPasswordSetupEmail = true;
  var saving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.gold),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        title: const Text(
          'O  MANAGE USER ROLE',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create or update any non-owner account. Core, Pro, Pro Founder, and Admin grant complimentary access without requiring payment.',
                style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('owner-role-email'),
                controller: emailController,
                enabled: !saving,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('User email'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('owner-role-select'),
                initialValue: selectedRole,
                isExpanded: true,
                dropdownColor: const Color(0xFF0F1620),
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('Role'),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('A - ADMIN')),
                  DropdownMenuItem(
                    value: 'core',
                    child: Text('C - CORE ACCESS'),
                  ),
                  DropdownMenuItem(value: 'pro', child: Text('P - PRO ACCESS')),
                  DropdownMenuItem(
                    value: 'pro_founder',
                    child: Text('PF - PRO FOUNDER'),
                  ),
                  DropdownMenuItem(value: 'user', child: Text('U - USER')),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setDialogState(() => selectedRole = value);
                        }
                      },
              ),
              if (selectedRole == 'pro_founder') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: founderNumberController,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration('Founder number (1-999)'),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: sendPasswordSetupEmail,
                onChanged: saving
                    ? null
                    : (value) =>
                          setDialogState(() => sendPasswordSetupEmail = value),
                activeTrackColor: AppColors.gold,
                title: const Text(
                  'SEND PASSWORD SETUP EMAIL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text(
                  'New users receive an invitation. Existing users receive a secure password-change link.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            key: const ValueKey('owner-assign-role'),
            onPressed: saving
                ? null
                : () async {
                    setDialogState(() => saving = true);
                    try {
                      final result = await ApiService()
                          .inviteOrUpdateUserAccess(
                            email: emailController.text,
                            role: selectedRole,
                            founderNumber: int.tryParse(
                              founderNumberController.text.trim(),
                            ),
                            sendPasswordSetupEmail: sendPasswordSetupEmail,
                          );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      showMessage(
                        '${result['email']} is now ${result['role'].toString().toUpperCase()}. ${result['emailSent'] == true ? 'A secure password setup email was sent.' : 'No password email was requested.'}',
                      );
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() => saving = false);
                      showMessage('Unable to assign role: $error');
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.bgBase,
            ),
            child: Text(saving ? 'SAVING...' : 'ASSIGN ROLE'),
          ),
        ],
      ),
    ),
  );
  emailController.dispose();
  founderNumberController.dispose();
}

class OwnerUserAccountControls extends StatelessWidget {
  const OwnerUserAccountControls({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 680;
      final description = const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'USER ACCOUNT CONTROLS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Create accounts; assign Admin, Core, Pro, Pro Founder, or standard User access; bypass payment for complimentary roles; and send secure password setup emails.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      );
      final action = Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('owner-view-all-members'),
            onPressed: () => _showOwnerMemberDirectory(context),
            icon: const Icon(Icons.groups_2_outlined),
            label: const Text('VIEW ALL MEMBERS'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold),
          ),
          FilledButton.icon(
            key: const ValueKey('owner-manage-user-roles'),
            onPressed: () => showOwnerUserRoleManager(
              context,
              showMessage: (message) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message))),
            ),
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('MANAGE ACCESS'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.bgBase,
            ),
          ),
        ],
      );
      return Container(
        key: const ValueKey('owner-user-account-controls'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1823),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withValues(alpha: .65)),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [description, const SizedBox(height: 12), action],
              )
            : Row(
                children: [
                  Expanded(child: description),
                  const SizedBox(width: 18),
                  action,
                ],
              ),
      );
    },
  );
}

Future<void> _showOwnerMemberDirectory(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sidebar,
    constraints: const BoxConstraints(maxWidth: 920),
    builder: (_) => const _OwnerMemberDirectory(),
  );
}

class _OwnerMemberDirectory extends StatefulWidget {
  const _OwnerMemberDirectory();

  @override
  State<_OwnerMemberDirectory> createState() => _OwnerMemberDirectoryState();
}

class _OwnerMemberDirectoryState extends State<_OwnerMemberDirectory> {
  late final Future<Map<String, dynamic>> _members = ApiService()
      .fetchOperationsDetail('members');
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _email(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email application is available.')),
      );
    }
  }

  Future<void> _chat(Map member) async {
    final userId = member['userId']?.toString() ?? '';
    final name = member['name']?.toString().trim();
    if (userId.isEmpty) return;
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: Text(
          'MESSAGE ${name?.isNotEmpty == true ? name : member['email']}',
          style: const TextStyle(color: AppColors.gold, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('Private message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('SEND'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.trim().isEmpty) return;
    try {
      final service = PropChatService();
      final conversationId = await service.startDirectConversation(userId);
      await service.sendDirectMessage(conversationId, message);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Private message sent.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to send message: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: .9,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'MEMBER DIRECTORY',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
            TextField(
              controller: _search,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(
                'Search name, email, user ID, or membership',
              ).copyWith(prefixIcon: const Icon(Icons.search)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _members,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = (snapshot.data?['rows'] as List? ?? const [])
                      .whereType<Map>()
                      .where((member) {
                        if (_query.isEmpty) return true;
                        return ['name', 'email', 'userId', 'member'].any(
                          (key) => member[key]
                              .toString()
                              .toLowerCase()
                              .contains(_query),
                        );
                      })
                      .toList(growable: false);
                  if (rows.isEmpty) {
                    return const Center(
                      child: Text(
                        'No members found.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final member = rows[index];
                      final email = member['email']?.toString() ?? '';
                      final name = member['name']?.toString().trim();
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C1823),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.chromeShadow),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.gold.withValues(
                                alpha: .15,
                              ),
                              foregroundColor: AppColors.gold,
                              child: Text(
                                (name?.isNotEmpty == true
                                        ? name!
                                        : email.isNotEmpty
                                        ? email
                                        : 'M')
                                    .substring(0, 1)
                                    .toUpperCase(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name?.isNotEmpty == true ? name! : 'Member',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      color: AppColors.silver,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${member['member'] ?? 'user'}  |  ${member['userId'] ?? ''}',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Email member',
                              onPressed: email.isEmpty
                                  ? null
                                  : () => _email(email),
                              icon: const Icon(
                                Icons.email_outlined,
                                color: AppColors.gold,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Chat with member',
                              onPressed: () => _chat(member),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                color: AppColors.gold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

InputDecoration _fieldDecoration(String label) => InputDecoration(
  isDense: true,
  labelText: label,
  labelStyle: const TextStyle(color: Color(0xFF8A98AA), fontSize: 11),
  filled: true,
  fillColor: const Color(0xFF0F1620),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.chromeShadow),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.gold),
  ),
);
