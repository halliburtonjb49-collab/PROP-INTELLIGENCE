import 'package:flutter/material.dart';

import '../services/auth_manager.dart';
import '../services/auth_service.dart';
import '../services/prop_watchlist_service.dart';

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

  Future<void> _showRoleManager() async {
    final emailController = TextEditingController();
    var selectedRole = 'admin';
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0B151E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFFFC400)),
          ),
          title: const Text(
            'O  MANAGE USER ROLE',
            style: TextStyle(
              color: Color(0xFFFFC400),
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
                  'The user must create an account before a role can be assigned.',
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
                      value: 'tester',
                      child: Text('T - TESTER'),
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
                backgroundColor: const Color(0xFFFFC400),
                foregroundColor: const Color(0xFF050A0F),
              ),
              child: Text(saving ? 'SAVING...' : 'ASSIGN ROLE'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
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
            color: const Color(0xFF0B151E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: state.isOwner
                  ? const Color(0xFFFFC400)
                  : const Color(0xFF273445),
              width: state.isOwner ? 1.4 : 1,
            ),
          ),
          child: state.authenticated
              ? _SignedInView(
                  email: state.email ?? 'Unknown',
                  role: state.role,
                  onManageRoles: state.isOwner ? _showRoleManager : null,
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
                              backgroundColor: const Color(0xFFFFC72C),
                              foregroundColor: const Color(0xFF050A0F),
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
        borderSide: const BorderSide(color: Color(0xFF273445)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF273445)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFFFC72C)),
      ),
    );
  }
}

class _SignedInView extends StatelessWidget {
  final String email;
  final String role;
  final VoidCallback? onManageRoles;
  final Future<void> Function() onSignOut;

  const _SignedInView({
    required this.email,
    required this.role,
    required this.onManageRoles,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedRole = role.trim().toLowerCase();
    final roleLetter = switch (normalizedRole) {
      'owner' => 'O',
      'admin' => 'A',
      'tester' => 'T',
      _ => 'U',
    };
    final roleLabel = switch (normalizedRole) {
      'owner' => 'OWNER',
      'admin' => 'ADMIN',
      'tester' => 'TESTER',
      _ => 'USER',
    };
    final roleColor = switch (normalizedRole) {
      'owner' => const Color(0xFFFFC400),
      'admin' => const Color(0xFF6DB8FF),
      'tester' => const Color(0xFFE0E0E0),
      _ => const Color(0xFF56D38A),
    };

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: roleColor.withValues(alpha: 0.12),
            border: Border.all(color: roleColor, width: 1.5),
          ),
          child: Text(
            roleLetter,
            style: TextStyle(
              color: roleColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                roleLabel,
                style: TextStyle(
                  color: roleColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: normalizedRole == 'owner' ? roleColor : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (onManageRoles != null)
          TextButton(
            onPressed: onManageRoles,
            child: const Text('ROLES', style: TextStyle(fontSize: 10)),
          ),
        TextButton(
          onPressed: onSignOut,
          child: const Text('SIGN OUT', style: TextStyle(fontSize: 10)),
        ),
      ],
    );
  }
}
