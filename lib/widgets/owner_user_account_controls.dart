import 'package:flutter/material.dart';

import '../services/api_service.dart';
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
                    : (value) => setDialogState(
                        () => sendPasswordSetupEmail = value,
                      ),
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
                      final result = await ApiService().inviteOrUpdateUserAccess(
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
      final action = FilledButton.icon(
        key: const ValueKey('owner-manage-user-roles'),
        onPressed: () => showOwnerUserRoleManager(
          context,
          showMessage: (message) => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message))),
        ),
        icon: const Icon(Icons.manage_accounts_outlined),
        label: const Text('MANAGE USER ACCOUNTS'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.bgBase,
        ),
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
