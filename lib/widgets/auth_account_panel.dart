import 'package:flutter/material.dart';

import '../models/member_identity.dart';
import '../screens/paywall_screen.dart';
import '../services/auth_manager.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/billing_service.dart';
import '../services/prop_watchlist_service.dart';
import 'member_identity_badge.dart';
import 'official_identity_badge.dart';

import '../theme/app_colors.dart' as brand_colors;

@visibleForTesting
bool shouldShowPlanSelector({
  required SubscriptionTier tier,
  required String role,
}) =>
    tier != SubscriptionTier.edge ||
    const {'owner', 'admin', 'tester'}.contains(role.trim().toLowerCase());

@visibleForTesting
bool shouldShowSubscriptionManagement({
  required SubscriptionTier tier,
  required String role,
}) =>
    tier != SubscriptionTier.free &&
    !const {'owner', 'admin', 'tester'}.contains(role.trim().toLowerCase());

class AuthAccountPanel extends StatefulWidget {
  const AuthAccountPanel({super.key});

  @override
  State<AuthAccountPanel> createState() => _AuthAccountPanelState();
}

class _AuthAccountPanelState extends State<AuthAccountPanel> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final SportsAppAuthService _authService = SportsAppAuthService();
  final PropWatchlistService _watchlistService = PropWatchlistService();

  bool _registerMode = false;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showMessage('Email and password are required.');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      if (_registerMode) {
        final registrationResult = await _authService.createNewUserAccount(
          email,
          password,
        );
        if (registrationResult.success) {
          await _watchlistService.syncLocalAndCloudWatchlist();
        }
        _showMessage(registrationResult.message);
      } else {
        final loginResult = await _authService.loginUserAccount(
          email,
          password,
        );
        if (loginResult.success) {
          await _watchlistService.syncLocalAndCloudWatchlist();
        }
        _showMessage(loginResult.message);
      }
    } catch (error) {
      _showMessage('Auth failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showPlans() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BrandedPaywallModalSheet(),
    );
  }

  Future<void> _manageSubscription() async {
    await RevenueCatBillingService().openSubscriptionManagement(context);
  }

  Future<void> _deleteAccount() async {
    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: brand_colors.AppColors.sidebar,
        title: const Text('DELETE ACCOUNT'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your account and associated research data. '
              'Deleting the account does not automatically cancel an active '
              'membership; manage that membership first if one is active.',
            ),
            const SizedBox(height: 14),
            const Text('Type DELETE to confirm.'),
            const SizedBox(height: 8),
            TextField(
              controller: confirmationController,
              autofocus: true,
              decoration: _fieldDecoration('Confirmation'),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(
              dialogContext,
              confirmationController.text.trim() == 'DELETE',
            ),
            child: const Text('DELETE PERMANENTLY'),
          ),
        ],
      ),
    );
    confirmationController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await ApiService().deleteCurrentAccount();
      await AuthManager.instance.signOut();
      _showMessage('Your account and associated data were deleted.');
    } catch (error) {
      _showMessage('Account deletion failed: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _setOwnerPreview(String selection) {
    final tier = switch (selection) {
      'no_plan' => SubscriptionTier.free,
      'core' => SubscriptionTier.core,
      'edge' => SubscriptionTier.edge,
      _ => null,
    };
    AuthManager.instance.setOwnerAccessPreview(tier);
    _showMessage(
      tier == null
          ? 'Owner access preview disabled.'
          : tier == SubscriptionTier.free
          ? 'Previewing the signed-in experience with no active plan.'
          : 'Previewing the app as a ${tier.displayName.toUpperCase()} subscriber.',
    );
  }

  Future<void> _showRoleManager() async {
    final emailController = TextEditingController();
    final founderNumberController = TextEditingController();
    var selectedRole = 'admin';
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: brand_colors.AppColors.sidebar,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: brand_colors.AppColors.gold),
          ),
          title: const Text(
            'O  MANAGE USER ROLE',
            style: TextStyle(
              color: brand_colors.AppColors.gold,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The user must create an account first. Core, Pro, and Pro Founder grant complimentary access without changing billing.',
                  style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  enabled: !saving,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration('User email'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  dropdownColor: const Color(0xFF0F1620),
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration('Role'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('A - ADMIN')),
                    DropdownMenuItem(
                      value: 'core',
                      child: Text('C - CORE ACCESS'),
                    ),
                    DropdownMenuItem(
                      value: 'pro',
                      child: Text('P - PRO ACCESS'),
                    ),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        final result = await AuthManager.instance
                            .assignUserRole(
                              email: emailController.text,
                              role: selectedRole,
                              founderNumber: int.tryParse(
                                founderNumberController.text.trim(),
                              ),
                            );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _showMessage(
                          '${result['email']} is now ${result['role'].toString().toUpperCase()}.',
                        );
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => saving = false);
                        _showMessage('Unable to assign role: $error');
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: brand_colors.AppColors.gold,
                foregroundColor: brand_colors.AppColors.bgBase,
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

  Future<void> _submitChangeRequest() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: brand_colors.AppColors.sidebar,
        title: const Text(
          'A  REQUEST OWNER APPROVAL',
          style: TextStyle(
            color: Color(0xFF6DB8FF),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Describe the proposed application change. The owner must approve it before implementation or release.',
                style: TextStyle(color: Color(0xFFB7C2CE), height: 1.45),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                maxLength: 120,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('Request title'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                minLines: 4,
                maxLines: 8,
                maxLength: 4000,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration(
                  'What should change, why, and what users are affected?',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await AuthManager.instance.submitChangeRequest(
                  title: titleController.text,
                  description: descriptionController.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (error) {
                _showMessage('Unable to submit request: $error');
              }
            },
            child: const Text('SEND TO OWNER'),
          ),
        ],
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    if (submitted == true) {
      _showMessage('Change request sent to the owner for approval.');
    }
  }

  Future<void> _showChangeRequests() async {
    try {
      final requests = await AuthManager.instance.listChangeRequests();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: brand_colors.AppColors.sidebar,
          title: Row(
            children: [
              const Icon(
                Icons.approval_rounded,
                color: brand_colors.AppColors.gold,
              ),
              const SizedBox(width: 9),
              Text(
                AuthManager.instance.sessionState.value.isOwner
                    ? 'OWNER CHANGE APPROVALS'
                    : 'MY CHANGE REQUESTS',
                style: const TextStyle(
                  color: brand_colors.AppColors.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 460,
            child: requests.isEmpty
                ? const Center(
                    child: Text(
                      'No change requests yet.',
                      style: TextStyle(color: Color(0xFFB7C2CE)),
                    ),
                  )
                : ListView.separated(
                    itemCount: requests.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      return _ChangeRequestCard(
                        request: request,
                        canReview:
                            AuthManager.instance.sessionState.value.isOwner &&
                            request.isPending,
                        onApprove: () => _reviewChangeRequest(
                          dialogContext,
                          request,
                          approved: true,
                        ),
                        onDeny: () => _reviewChangeRequest(
                          dialogContext,
                          request,
                          approved: false,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showMessage('Unable to load change requests: $error');
    }
  }

  Future<void> _reviewChangeRequest(
    BuildContext requestsDialogContext,
    AppChangeRequest request, {
    required bool approved,
  }) async {
    final responseController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: brand_colors.AppColors.sidebar,
        title: Text(
          approved ? 'APPROVE CHANGE REQUEST' : 'DENY CHANGE REQUEST',
          style: TextStyle(
            color: approved
                ? brand_colors.AppColors.success
                : const Color(0xFFFF6B72),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: responseController,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Owner response (optional)'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approved ? 'APPROVE' : 'DENY'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await AuthManager.instance.reviewChangeRequest(
          requestId: request.id,
          approved: approved,
          response: responseController.text,
        );
        if (requestsDialogContext.mounted) {
          Navigator.pop(requestsDialogContext);
        }
        _showMessage(approved ? 'Request approved.' : 'Request denied.');
        if (mounted) await _showChangeRequests();
      } catch (error) {
        _showMessage('Unable to review request: $error');
      }
    }
    responseController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthSessionState>(
      valueListenable: AuthManager.instance.sessionState,
      builder: (context, state, child) {
        final isUnavailable = state.message.contains('not configured');
        final canSubmit = !_submitting && !isUnavailable;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: brand_colors.AppColors.sidebar,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: state.isOwner
                  ? brand_colors.AppColors.gold
                  : brand_colors.AppColors.chromeShadow,
              width: state.isOwner ? 1.4 : 1,
            ),
          ),
          child: state.authenticated
              ? _SignedInView(
                  username:
                      state.username ??
                      resolvePublicUsername(userId: state.userId ?? ''),
                  role: state.role,
                  assignedMemberRole: state.assignedMemberRole,
                  founderNumber: state.founderNumber,
                  subscriptionTier: state.effectiveSubscriptionTier,
                  accessPreviewTier: state.accessPreviewTier,
                  onOwnerPreviewChanged: state.isOwner
                      ? _setOwnerPreview
                      : null,
                  onViewPlans: _showPlans,
                  onManageSubscription:
                      shouldShowSubscriptionManagement(
                        tier: state.subscriptionTier,
                        role: state.role,
                      )
                      ? _manageSubscription
                      : null,
                  onManageRoles: state.isOwner ? _showRoleManager : null,
                  onChangeRequests: state.isOwner || state.isAdmin
                      ? _showChangeRequests
                      : null,
                  onSubmitChangeRequest: state.isAdmin
                      ? _submitChangeRequest
                      : null,
                  onDeleteAccount: _submitting ? null : _deleteAccount,
                  onSignOut: () async {
                    try {
                      await AuthManager.instance.signOut();
                      _showMessage('Signed out.');
                    } catch (error) {
                      _showMessage('Sign-out failed: $error');
                    }
                  },
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _registerMode ? 'Create Account' : 'Sign In',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      enabled: canSubmit,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _fieldDecoration('Email'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      enabled: canSubmit,
                      obscureText: true,
                      decoration: _fieldDecoration('Password'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: canSubmit ? _submit : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brand_colors.AppColors.gold,
                              foregroundColor: brand_colors.AppColors.bgBase,
                              minimumSize: const Size(0, 34),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _registerMode ? 'REGISTER' : 'LOGIN',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: canSubmit
                              ? () {
                                  setState(() {
                                    _registerMode = !_registerMode;
                                  });
                                }
                              : null,
                          child: Text(
                            _registerMode ? 'Have account?' : 'Create account',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.message,
                      style: const TextStyle(
                        color: Color(0xFF8A98AA),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF8A98AA), fontSize: 11),
      filled: true,
      fillColor: const Color(0xFF0F1620),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: brand_colors.AppColors.chromeShadow,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: brand_colors.AppColors.chromeShadow,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: brand_colors.AppColors.gold),
      ),
    );
  }
}

class _SignedInView extends StatelessWidget {
  final String username;
  final String role;
  final String? assignedMemberRole;
  final int? founderNumber;
  final SubscriptionTier subscriptionTier;
  final SubscriptionTier? accessPreviewTier;
  final ValueChanged<String>? onOwnerPreviewChanged;
  final VoidCallback onViewPlans;
  final Future<void> Function()? onManageSubscription;
  final VoidCallback? onManageRoles;
  final VoidCallback? onChangeRequests;
  final VoidCallback? onSubmitChangeRequest;
  final Future<void> Function()? onDeleteAccount;
  final Future<void> Function() onSignOut;

  const _SignedInView({
    required this.username,
    required this.role,
    required this.assignedMemberRole,
    required this.founderNumber,
    required this.subscriptionTier,
    required this.accessPreviewTier,
    required this.onOwnerPreviewChanged,
    required this.onViewPlans,
    required this.onManageSubscription,
    required this.onManageRoles,
    required this.onChangeRequests,
    required this.onSubmitChangeRequest,
    required this.onDeleteAccount,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedRole = role.trim().toLowerCase();
    final identityRole = MemberIdentityRole.fromValues(
      accountRole: normalizedRole,
      assignedRole: assignedMemberRole,
      subscriptionTier: subscriptionTier,
    );
    final roleColor = identityRole == MemberIdentityRole.admin
        ? const Color(0xFF6DB8FF)
        : brand_colors.AppColors.gold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MemberIdentityBadge(
              username: username,
              role: identityRole,
              founderNumber: founderNumber,
              showUsername: false,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@$username',
                    key: const ValueKey('account-display-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: normalizedRole == 'owner'
                          ? roleColor
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (normalizedRole == 'owner')
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: OfficialOwnerBadge(compact: true),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          normalizedRole == 'admin'
                              ? Icons.admin_panel_settings_outlined
                              : normalizedRole == 'tester'
                              ? Icons.science_outlined
                              : Icons.person_outline_rounded,
                          color: roleColor,
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            identityRole.label,
                            key: const ValueKey('account-role-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: roleColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .55,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          runSpacing: 4,
          children: [
            if (onOwnerPreviewChanged != null)
              PopupMenuButton<String>(
                key: const ValueKey('owner-access-preview-menu'),
                tooltip: 'Preview subscription access',
                onSelected: onOwnerPreviewChanged,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'no_plan',
                    child: Text('PREVIEW WITH NO PLAN'),
                  ),
                  PopupMenuItem(value: 'core', child: Text('PREVIEW AS CORE')),
                  PopupMenuItem(value: 'edge', child: Text('PREVIEW AS PRO')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'off', child: Text('EXIT PREVIEW')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accessPreviewTier == null
                        ? Colors.transparent
                        : brand_colors.AppColors.gold.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accessPreviewTier == null
                          ? brand_colors.AppColors.chromeShadow
                          : brand_colors.AppColors.gold,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.science_outlined, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        accessPreviewTier == null
                            ? 'ACCESS PREVIEW'
                            : accessPreviewTier == SubscriptionTier.free
                            ? 'PREVIEW: NO PLAN'
                            : 'PREVIEW: ${accessPreviewTier!.displayName.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (shouldShowPlanSelector(
              tier: subscriptionTier,
              role: normalizedRole,
            ))
              TextButton.icon(
                key: const ValueKey('view-plans-button'),
                onPressed: onViewPlans,
                icon: const Icon(Icons.workspace_premium_outlined, size: 15),
                label: Text(
                  subscriptionTier == SubscriptionTier.free
                      ? 'CHOOSE PLAN'
                      : 'VIEW PLANS',
                ),
              ),
            if (onManageSubscription != null)
              TextButton.icon(
                key: const ValueKey('manage-subscription-button'),
                onPressed: onManageSubscription,
                icon: const Icon(Icons.credit_card_outlined, size: 15),
                label: const Text('MANAGE SUBSCRIPTION'),
              ),
            if (onManageRoles != null)
              TextButton.icon(
                onPressed: onManageRoles,
                icon: const Icon(Icons.manage_accounts_outlined, size: 15),
                label: const Text('MANAGE ROLES'),
              ),
            if (onSubmitChangeRequest != null)
              TextButton.icon(
                onPressed: onSubmitChangeRequest,
                icon: const Icon(Icons.edit_note_rounded, size: 15),
                label: const Text('REQUEST CHANGE'),
              ),
            if (onChangeRequests != null)
              TextButton.icon(
                onPressed: onChangeRequests,
                icon: Icon(Icons.approval_outlined, size: 15, color: roleColor),
                label: Text(
                  normalizedRole == 'owner' ? 'APPROVALS' : 'REQUESTS',
                ),
              ),
            TextButton.icon(
              key: const ValueKey('delete-account-button'),
              onPressed: onDeleteAccount,
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
              icon: const Icon(Icons.delete_forever_outlined, size: 15),
              label: const Text('DELETE ACCOUNT'),
            ),
            TextButton.icon(
              onPressed: onSignOut,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD4AF37),
              ),
              icon: const Icon(Icons.logout_rounded, size: 15),
              label: const Text('SIGN OUT'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChangeRequestCard extends StatelessWidget {
  const _ChangeRequestCard({
    required this.request,
    required this.canReview,
    required this.onApprove,
    required this.onDeny,
  });

  final AppChangeRequest request;
  final bool canReview;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (request.status) {
      'approved' => brand_colors.AppColors.success,
      'denied' => const Color(0xFFFF6B72),
      _ => brand_colors.AppColors.gold,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  request.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'ADMIN: ${request.requesterEmail}',
            style: const TextStyle(
              color: Color(0xFF6DB8FF),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            request.description,
            style: const TextStyle(
              color: Color(0xFFB7C2CE),
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (request.ownerResponse?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              'OWNER RESPONSE: ${request.ownerResponse}',
              style: const TextStyle(
                color: brand_colors.AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (canReview) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onDeny,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('DENY'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B72),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('APPROVE'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
