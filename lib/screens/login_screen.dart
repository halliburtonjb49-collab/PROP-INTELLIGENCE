import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/developer_mode_service.dart';
import '../theme/prop_intelligence_colors.dart';

const _gold = PropIntelligenceColors.premiumGold;
const _pageBackground = Color(0xFF020609);
const _panelBackground = Color(0xE6070B0E);
const _fieldBackground = Color(0xFF111518);
const _mutedText = Color(0xFF9A9A9A);
const _publicSignupEnabled = bool.fromEnvironment(
  'ALLOW_PUBLIC_SIGNUP',
  defaultValue: false,
);

class CorporateLoginScreen extends StatefulWidget {
  const CorporateLoginScreen({super.key});

  @override
  State<CorporateLoginScreen> createState() => _CorporateLoginScreenState();
}

class _CorporateLoginScreenState extends State<CorporateLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = SportsAppAuthService();
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _obscurePassword = true;
  int _resendCooldownSeconds = 0;
  Timer? _resendCooldownTimer;

  @override
  void dispose() {
    _resendCooldownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 60]) {
    _resendCooldownTimer?.cancel();
    setState(() => _resendCooldownSeconds = seconds);
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _resendCooldownSeconds = 0);
      } else {
        setState(() => _resendCooldownSeconds -= 1);
      }
    });
  }

  Future<void> _handleAuthentication() async {
    if (_isLoading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showFeedbackMessage('Enter your email address and password.');
      return;
    }

    setState(() => _isLoading = true);
    final result = _isRegistering
        ? await _authService.createNewUserAccount(email, password)
        : await _authService.loginUserAccount(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showFeedbackMessage(result.message);
  }

  void _startRegistration() {
    if (!_publicSignupEnabled) {
      _showFeedbackMessage(
        'PROP INTELLIGENCE is currently in private beta. New accounts are not open yet.',
      );
      return;
    }
    setState(() => _isRegistering = true);
  }

  Future<void> _handlePasswordReset() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final result = await _authService.sendPasswordResetEmail(
      _emailController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showFeedbackMessage(result.message);
  }

  Future<void> _handleSocialSignIn(OAuthProvider provider) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final result = await _authService.signInWithProvider(provider);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!result.success) _showFeedbackMessage(result.message);
  }

  Future<void> _handleResendVerification() async {
    if (_isLoading || _resendCooldownSeconds > 0) return;
    setState(() => _isLoading = true);
    final result = await _authService.resendVerificationEmail(
      _emailController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result.success || result.suggestedRetrySeconds > 0) {
      _startResendCooldown(
        result.suggestedRetrySeconds > 0 ? result.suggestedRetrySeconds : 60,
      );
    }
    _showFeedbackMessage(result.message);
  }

  void _showFeedbackMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: _gold,
      ),
    );
  }

  Future<void> _openSiteSection(String section) async {
    final uri = Uri.parse('https://www.propsintell.com/#$section');
    if (!await launchUrl(uri, webOnlyWindowName: '_self')) {
      _showFeedbackMessage('Could not open that section.');
    }
  }

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panelBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _gold.withValues(alpha: 0.72)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        title: const Row(
          children: [
            Icon(Icons.query_stats_rounded, color: _gold, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'PROP INTELLIGENCE',
                style: TextStyle(
                  color: _gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FIND THE EDGE',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'PROP INTELLIGENCE transforms live player, matchup and market data into clear prop research. Compare lines, monitor movement, review model confidence and build smarter slips across multiple sports.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'WHAT YOU CAN DO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 10),
                _AboutBullet('Access real-time player and line data'),
                _AboutBullet('Identify positive-value opportunities'),
                _AboutBullet('Compare projections and market movement'),
                _AboutBullet('Build, save and track prop slips'),
                _AboutBullet('Research NBA, NFL, MLB, WNBA, NHL and more'),
                SizedBox(height: 18),
                _AboutNotice(
                  title: 'PRIVATE BETA',
                  text:
                      'Access is currently limited while features, data sources and analytics are being tested.',
                ),
                SizedBox(height: 10),
                _AboutNotice(
                  title: 'RESPONSIBLE USE',
                  text:
                      'For informational and entertainment purposes only. Predictions are not guaranteed. Users must meet applicable age requirements and wager responsibly.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('BACK TO LOGIN'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openSiteSection('about');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
            ),
            child: const Text(
              'LEARN MORE',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeveloperBypassPrompt() async {
    if (!DeveloperModeService.canShowEntry) return;
    final pinController = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PropIntelligenceColors.darkCardBg,
        title: const Text(
          'Developer Access',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: pinController,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Developer PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(pinController.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    pinController.dispose();
    if (!mounted || pin == null) return;
    _showFeedbackMessage(
      DeveloperModeService.unlock(pin)
          ? 'Developer mode unlocked for this session.'
          : 'Invalid developer PIN.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: Stack(
        children: [
          const Positioned.fill(child: _AnalyticsBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                final tightDesktop = !compact && constraints.maxWidth < 1120;
                return Column(
                  children: [
                    _TopNavigation(
                      compact: compact,
                      tight: tightDesktop,
                      onBrandTap: _showAboutDialog,
                      onNavigate: _openSiteSection,
                      onSignUp: _startRegistration,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, bodyConstraints) {
                          final horizontalPadding = compact
                              ? 20.0
                              : (tightDesktop ? 24.0 : 42.0);
                          final verticalPadding = compact
                              ? 26.0
                              : (tightDesktop ? 22.0 : 28.0);
                          return SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: verticalPadding,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    bodyConstraints.maxHeight -
                                    (verticalPadding * 2),
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1420,
                                  ),
                                  child: compact
                                      ? Column(
                                          children: [
                                            _HeroBrand(
                                              compact: true,
                                              dense: false,
                                              onLongPress:
                                                  _openDeveloperBypassPrompt,
                                            ),
                                            const SizedBox(height: 28),
                                            _buildLoginCard(dense: false),
                                          ],
                                        )
                                      : Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: _HeroBrand(
                                                compact: false,
                                                dense: tightDesktop,
                                                onLongPress:
                                                    _openDeveloperBypassPrompt,
                                              ),
                                            ),
                                            SizedBox(
                                              width: tightDesktop ? 26 : 60,
                                            ),
                                            SizedBox(
                                              width: tightDesktop ? 360 : 460,
                                              child: _buildLoginCard(
                                                dense: tightDesktop,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const _Footer(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard({required bool dense}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 460),
      padding: EdgeInsets.fromLTRB(
        dense ? 20 : 28,
        dense ? 20 : 27,
        dense ? 20 : 28,
        dense ? 16 : 23,
      ),
      decoration: BoxDecoration(
        color: _panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _gold.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.72),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
          BoxShadow(color: _gold.withValues(alpha: 0.05), blurRadius: 28),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isRegistering ? 'CREATE YOUR ACCOUNT' : 'WELCOME BACK',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _gold,
                fontSize: dense ? 22 : 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isRegistering
                  ? 'Join PROP INTELLIGENCE and find your edge'
                  : 'Log in to access your dashboard',
              style: TextStyle(color: _mutedText, fontSize: dense ? 15 : 16),
            ),
            const SizedBox(height: 12),
            Container(
              width: 74,
              height: 2,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.transparent, _gold, Colors.transparent],
                ),
                boxShadow: [
                  BoxShadow(color: _gold.withValues(alpha: 0.8), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _FieldLabel(
              label: 'Email Address',
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: dense ? 14 : 16,
                ),
                decoration: _fieldDecoration(
                  hint: 'Enter your email',
                  prefixIcon: Icons.mail_outline_rounded,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _FieldLabel(
              label: 'Password',
              child: TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                onSubmitted: (_) => _handleAuthentication(),
                textInputAction: TextInputAction.done,
                autofillHints: _isRegistering
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: dense ? 14 : 16,
                ),
                decoration: _fieldDecoration(
                  hint: _isRegistering
                      ? 'Create a secure password'
                      : 'Enter your password',
                  prefixIcon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            if (!_isRegistering)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _handlePasswordReset,
                  style: TextButton.styleFrom(
                    foregroundColor: _gold,
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                  ),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: dense ? 48 : 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleAuthentication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  disabledBackgroundColor: _gold.withValues(alpha: 0.5),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  elevation: 8,
                  shadowColor: _gold.withValues(alpha: 0.35),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        _isRegistering ? 'CREATE ACCOUNT' : 'LOGIN',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            const _OrDivider(),
            const SizedBox(height: 13),
            _SocialButton(
              label: 'Continue with Google',
              leading: const Text(
                'G',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
              onPressed: _isLoading
                  ? null
                  : () => _handleSocialSignIn(OAuthProvider.google),
            ),
            const SizedBox(height: 8),
            _SocialButton(
              label: 'Continue with Apple',
              leading: const Icon(Icons.apple, color: Colors.white, size: 23),
              onPressed: _isLoading
                  ? null
                  : () => _handleSocialSignIn(OAuthProvider.apple),
            ),
            const SizedBox(height: 13),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _isRegistering
                      ? 'Already have an account?'
                      : "Don't have an account?",
                  style: const TextStyle(color: _mutedText, fontSize: 13),
                ),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_isRegistering) {
                            setState(() => _isRegistering = false);
                          } else {
                            _startRegistration();
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: _gold,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    _isRegistering ? 'LOG IN' : 'SIGN UP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (_isRegistering)
              TextButton(
                onPressed: _resendCooldownSeconds > 0 || _isLoading
                    ? null
                    : _handleResendVerification,
                child: Text(
                  _resendCooldownSeconds > 0
                      ? 'Resend verification in $_resendCooldownSeconds s'
                      : 'Resend verification email',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
      prefixIcon: Icon(prefixIcon, color: Colors.white54, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _fieldBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF34383B)),
        borderRadius: BorderRadius.circular(6),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _gold),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _TopNavigation extends StatelessWidget {
  final bool compact;
  final bool tight;
  final VoidCallback onBrandTap;
  final Future<void> Function(String section) onNavigate;
  final VoidCallback onSignUp;

  const _TopNavigation({
    required this.compact,
    required this.tight,
    required this.onBrandTap,
    required this.onNavigate,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 58 : 66,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : (tight ? 18 : 42),
      ),
      decoration: const BoxDecoration(
        color: Color(0xD9000305),
        border: Border(bottom: BorderSide(color: Color(0xFF29220F))),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'About PROP INTELLIGENCE',
            child: OutlinedButton.icon(
              onPressed: onBrandTap,
              icon: Icon(
                Icons.query_stats_rounded,
                color: _gold,
                size: compact ? 16 : 18,
              ),
              label: Text(
                'PROP INTELLIGENCE',
                style: TextStyle(
                  color: _gold,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: Color(0xFF9C7410)),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : (tight ? 10 : 16),
                  vertical: compact ? 9 : (tight ? 10 : 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (!compact) ...[
            for (final item in const [
              ('FEATURES', 'features'),
              ('HOW IT WORKS', 'how-it-works'),
              ('PRICING', 'pricing'),
              ('ABOUT', 'about'),
              ('CONTACT', 'contact'),
            ])
              TextButton(
                onPressed: () => onNavigate(item.$2),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: EdgeInsets.symmetric(horizontal: tight ? 4 : 8),
                ),
                child: Text(
                  item.$1,
                  style: TextStyle(fontSize: tight ? 9 : 11),
                ),
              ),
            SizedBox(width: tight ? 6 : 14),
          ],
          OutlinedButton(
            onPressed: onSignUp,
            style: OutlinedButton.styleFrom(
              foregroundColor: _gold,
              side: const BorderSide(color: Color(0xFF9C7410)),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : (tight ? 14 : 22),
                vertical: compact ? 9 : (tight ? 11 : 15),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'SIGN UP',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBrand extends StatelessWidget {
  final bool compact;
  final bool dense;
  final VoidCallback onLongPress;

  const _HeroBrand({
    required this.compact,
    required this.dense,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPress: onLongPress,
          child: Image.asset(
            'assets/branding/prop_intelligence_logo.png',
            width: compact ? 290 : (dense ? 355 : 450),
            height: compact ? 290 : (dense ? 355 : 450),
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: compact ? 24 : (dense ? 10 : 30),
          runSpacing: 22,
          children: [
            _Feature(
              width: dense ? 108 : 120,
              icon: Icons.query_stats_rounded,
              title: 'REAL-TIME DATA',
              detail: 'Up-to-the-minute\nplayer & line data',
            ),
            _Feature(
              width: dense ? 108 : 120,
              icon: Icons.gps_fixed_rounded,
              title: 'SHARP ANALYTICS',
              detail: 'AI-powered models\nto find value',
            ),
            _Feature(
              width: dense ? 108 : 120,
              icon: Icons.emoji_events_outlined,
              title: 'HIGHER HIT RATE',
              detail: 'Data-driven picks\nthat win',
            ),
            _Feature(
              width: dense ? 108 : 120,
              icon: Icons.verified_user_outlined,
              title: 'MULTI-SPORT',
              detail: 'NBA, NFL, MLB, WNBA,\nNHL, UFC & more',
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutBullet extends StatelessWidget {
  final String text;

  const _AboutBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, color: _gold, size: 6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutNotice extends StatelessWidget {
  final String title;
  final String text;

  const _AboutNotice({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _gold.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final double width;
  final IconData icon;
  final String title;
  final String detail;

  const _Feature({
    required this.width,
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Icon(icon, color: _gold, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldLabel({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget leading;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.label,
    required this.leading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: SizedBox(width: 24, child: Center(child: leading)),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF0D1114),
          side: const BorderSide(color: Color(0xFF35393B)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFF303335))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFF303335))),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xB3000305),
        border: Border(top: BorderSide(color: Color(0xFF111619))),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 12),
          SizedBox(width: 7),
          Flexible(
            child: Text(
              '© 2026 PI PROP INTELLIGENCE. ALL RIGHTS RESERVED.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
                letterSpacing: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsBackground extends StatelessWidget {
  const _AnalyticsBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _pageBackground),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.35, -0.1),
              radius: 0.8,
              colors: [
                const Color(0xFF17202A).withValues(alpha: 0.64),
                Colors.transparent,
              ],
            ),
          ),
        ),
        CustomPaint(painter: _MarketGridPainter()),
      ],
    );
  }
}

class _MarketGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _gold.withValues(alpha: 0.055)
      ..strokeWidth = 0.6;
    const spacing = 38.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final chartPaint = Paint()
      ..color = _gold.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..moveTo(0, size.height * 0.73)
      ..lineTo(size.width * 0.12, size.height * 0.66)
      ..lineTo(size.width * 0.21, size.height * 0.7)
      ..lineTo(size.width * 0.34, size.height * 0.48)
      ..lineTo(size.width * 0.44, size.height * 0.56)
      ..lineTo(size.width * 0.57, size.height * 0.39)
      ..lineTo(size.width * 0.7, size.height * 0.44)
      ..lineTo(size.width * 0.84, size.height * 0.25)
      ..lineTo(size.width, size.height * 0.31);
    canvas.drawPath(path, chartPaint);

    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 0.75,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
