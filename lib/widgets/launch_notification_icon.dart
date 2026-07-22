import 'package:flutter/material.dart';
import '../services/launch_notification_service.dart';
import '../theme/app_colors.dart' as app_colors;

/// A notification bell icon that allows users to subscribe for launch notifications
class LaunchNotificationIcon extends StatefulWidget {
  const LaunchNotificationIcon({super.key});

  @override
  State<LaunchNotificationIcon> createState() => _LaunchNotificationIconState();
}

class _LaunchNotificationIconState extends State<LaunchNotificationIcon> {
  final LaunchNotificationService _notificationService =
      LaunchNotificationService();
  bool _hasSubscribed = false;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    final subscribed = await _notificationService.hasSubscribed();
    if (mounted) {
      setState(() {
        _hasSubscribed = subscribed;
      });
    }
  }

  void _showNotificationDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _LaunchNotificationDialog(
        onSubscribed: () {
          setState(() {
            _hasSubscribed = true;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _hasSubscribed
          ? 'You\'re subscribed for launch notifications'
          : 'Get notified when we go live',
      child: IconButton(
        onPressed: _showNotificationDialog,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              _hasSubscribed
                  ? Icons.notifications_active
                  : Icons.notifications_outlined,
              size: 20,
              color: _hasSubscribed
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.textSecondary,
            ),
            if (!_hasSubscribed)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF36B9FF),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8836B9FF),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        style: IconButton.styleFrom(
          backgroundColor: _hasSubscribed
              ? app_colors.AppColors.gold.withValues(alpha: 0.1)
              : Colors.transparent,
          padding: const EdgeInsets.all(8),
        ),
      ),
    );
  }
}

class _LaunchNotificationDialog extends StatefulWidget {
  final VoidCallback onSubscribed;

  const _LaunchNotificationDialog({required this.onSubscribed});

  @override
  State<_LaunchNotificationDialog> createState() =>
      _LaunchNotificationDialogState();
}

class _LaunchNotificationDialogState extends State<_LaunchNotificationDialog> {
  final TextEditingController _emailController = TextEditingController();
  final LaunchNotificationService _notificationService =
      LaunchNotificationService();
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();

    // Simple email validation
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email address';
      });
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await _notificationService.subscribeForLaunch(email);

      if (!mounted) return;

      if (success) {
        setState(() {
          _submitted = true;
          _isSubmitting = false;
        });

        widget.onSubscribed();

        // Auto-close after showing success
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _errorMessage = 'Unable to subscribe. Please try again.';
          _isSubmitting = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return AlertDialog(
        backgroundColor: app_colors.AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: app_colors.AppColors.borderGold),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: app_colors.AppColors.gold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 38,
                  color: app_colors.AppColors.gold,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'YOU\'RE ALL SET!',
                style: TextStyle(
                  color: app_colors.AppColors.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'We\'ll send you an email as soon as we go live.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app_colors.AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: app_colors.AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: app_colors.AppColors.borderGold),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: app_colors.AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: app_colors.AppColors.gold,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAUNCH NOTIFICATION',
                  style: TextStyle(
                    color: app_colors.AppColors.gold,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Get notified when we go live',
                  style: TextStyle(
                    color: app_colors.AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Be the first to know when our platform launches. Enter your email below and we\'ll send you a notification as soon as we\'re live.',
              style: TextStyle(
                color: app_colors.AppColors.textSecondary,
                fontSize: 13,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: const TextStyle(
                color: app_colors.AppColors.white,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                labelText: 'Email Address',
                labelStyle: const TextStyle(
                  color: app_colors.AppColors.textSecondary,
                  fontSize: 12,
                ),
                hintText: 'your.email@example.com',
                hintStyle: TextStyle(
                  color: app_colors.AppColors.textMuted.withValues(alpha: 0.5),
                ),
                prefixIcon: const Icon(
                  Icons.email_outlined,
                  color: app_colors.AppColors.textMuted,
                  size: 20,
                ),
                filled: true,
                fillColor: const Color(0xFF08131D),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: app_colors.AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: app_colors.AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: app_colors.AppColors.gold,
                    width: 1.5,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFFFF6B72),
                    width: 1.5,
                  ),
                ),
                errorText: _errorMessage,
                errorStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onSubmitted: (_) => _submitEmail(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: app_colors.AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your email is secure and will only be used for launch notifications.',
                    style: TextStyle(
                      color: app_colors.AppColors.textMuted.withValues(alpha: 0.8),
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submitEmail,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF06111B)),
                  ),
                )
              : const Icon(Icons.notifications_active, size: 18),
          label: Text(_isSubmitting ? 'SUBSCRIBING...' : 'NOTIFY ME'),
          style: FilledButton.styleFrom(
            backgroundColor: app_colors.AppColors.gold,
            foregroundColor: const Color(0xFF06111B),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ],
    );
  }
}
