import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../services/developer_mode_service.dart';
import '../theme/prop_intelligence_colors.dart';

const _gold = PropIntelligenceColors.premiumGold;
const _silver = PropIntelligenceColors.metallicSilver;
const _silver70 = _silver;
const _silver60 = _silver;
const _silver54 = _silver;
const _silver38 = _silver;
const _pageBackground = Color(0xFF020609);
const _panelBackground = Color(0xE6070B0E);
const _fieldBackground = Color(0xFF111518);
const _mutedText = Color(0xFF9A9A9A);
const _publicSignupEnabled = bool.fromEnvironment(
  'ALLOW_PUBLIC_SIGNUP',
  defaultValue: true,
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
  PurchaseTier? _pendingPurchaseTier;

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
    if (result.success &&
        _pendingPurchaseTier != null &&
        Supabase.instance.client.auth.currentSession != null) {
      final tier = _pendingPurchaseTier!;
      _pendingPurchaseTier = null;
      final billing = RevenueCatBillingService();
      await billing.initializeBillingEngine();
      if (mounted) await billing.processSubscriptionPurchase(context, tier);
    }
  }

  void _startRegistration() {
    if (!_publicSignupEnabled) {
      _showFeedbackMessage(
        'New account creation is temporarily unavailable. Please contact support.',
      );
      return;
    }
    setState(() => _isRegistering = true);
  }

  void _choosePlan(BuildContext dialogContext, PurchaseTier tier) {
    Navigator.of(dialogContext).pop();
    setState(() {
      _pendingPurchaseTier = tier;
      _isRegistering = true;
    });
    _showFeedbackMessage(
      'Create your account to continue with the ${tier == PurchaseTier.core ? 'Core' : 'Pro / Edge'} plan.',
    );
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
    late final String title;
    late final String subtitle;
    late final IconData icon;
    late final List<Widget> content;

    switch (section) {
      case 'features':
        title = 'FEATURES';
        subtitle = 'A COMPLETE PROP RESEARCH WORKSPACE';
        icon = Icons.query_stats_rounded;
        content = const [
          _FeatureGroup(
            icon: Icons.travel_explore_rounded,
            title: 'DISCOVER & COMPARE',
            items: [
              'Live player props, game boards and multi-sportsbook lines',
              'Player search, market comparison and line-movement tracking',
              'Live, upcoming and final scoreboards across major sports',
            ],
          ),
          _FeatureGroup(
            icon: Icons.psychology_alt_rounded,
            title: 'MODEL INTELLIGENCE',
            items: [
              'Projections, confidence, edge and expected-value signals',
              'Matchup, fatigue, travel, officiating and game-script context',
              'Correlation analysis, simulations and historical analogs',
            ],
          ),
          _FeatureGroup(
            icon: Icons.receipt_long_rounded,
            title: 'BUILD & TRACK',
            items: [
              'Guided prop builder with same-sportsbook slip protection',
              'Saved watchlists, active slips and performance history',
              'Alerts for monitored conditions and stale-line changes',
            ],
          ),
          _FeatureGroup(
            icon: Icons.auto_awesome_rounded,
            title: 'ADVANCED EDGE TOOLS',
            items: [
              'EV Scanner and Goblins / Demons risk-tier views',
              'Prediction grading, calibration and model performance review',
              'Contextual tips and plain-language guidance throughout the app',
            ],
          ),
          _AboutNotice(
            title: 'BUILT FOR INFORMED DECISIONS',
            text:
                'PROP INTELLIGENCE organizes research and model estimates. It does not guarantee outcomes or replace your own judgment.',
          ),
        ];
      case 'how-it-works':
        title = 'HOW IT WORKS';
        subtitle = 'A SIMPLER RESEARCH PROCESS';
        icon = Icons.route_rounded;
        content = const [
          _OverlayStep(
            number: '01',
            title: 'CHOOSE YOUR MARKET',
            text: 'Select a sport, game, player and prop market to research.',
          ),
          _OverlayStep(
            number: '02',
            title: 'COMPARE THE INFORMATION',
            text:
                'Review lines, projections, confidence, trends and market movement in one place.',
          ),
          _OverlayStep(
            number: '03',
            title: 'BUILD YOUR SLIP',
            text:
                'Save the props that stand out and organize them before making a decision.',
          ),
          _OverlayStep(
            number: '04',
            title: 'TRACK AND LEARN',
            text:
                'Follow results over time and use performance history to improve your process.',
          ),
        ];
      case 'about':
        title = 'ABOUT';
        subtitle = 'WHY I BUILT PROP INTELLIGENCE';
        icon = Icons.person_outline_rounded;
        content = [
          const Text(
            'I created PROP INTELLIGENCE after spending money on prop bets and realizing I was not getting as much useful information as I needed before making a pick.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          SizedBox(height: 14),
          Text(
            'The information was often scattered across different places, difficult to compare, or presented in a way that felt more complicated than it needed to be. I wanted a simpler way to see the lines, trends, projections and other details that could help me make a more informed decision.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          SizedBox(height: 14),
          Text(
            'That idea became PROP INTELLIGENCE: one place that brings the most important prop research together in a clear, practical format. It does not promise a winning bet. It is designed to help people understand the information in front of them before they spend their money.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          SizedBox(height: 26),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'JBH',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 4.5,
                    shadows: [Shadow(color: _gold, blurRadius: 8)],
                  ),
                ),
                SizedBox(height: 5),
                SizedBox(
                  width: 154,
                  child: Divider(color: _gold, height: 1, thickness: 1),
                ),
                SizedBox(height: 7),
                Text(
                  'FOUNDER | PROP INTELLIGENCE',
                  style: TextStyle(
                    color: _silver60,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ];
      case 'pricing':
        title = 'PRICING';
        subtitle = 'CHOOSE THE INTELLIGENCE THAT FITS YOUR PROCESS';
        icon = Icons.workspace_premium_outlined;
        content = [
          const Text(
            'Choose the tools that match how deeply you want to analyze each play. Both subscriptions are month-to-month and can be canceled anytime.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          const SizedBox(height: 20),
          _PricingTierCard(
            name: 'CORE',
            price: '\$29.99 / MONTH',
            description: 'The daily essentials for organized prop research.',
            features: [
              'Full prop builder and player analytics',
              'Live scoreboard and standard stat tracking',
              'Save, organize and track prop slips',
              'Market comparisons and line movement tools',
              'Multi-sport research across major leagues',
            ],
            onPressed: (dialogContext) =>
                _choosePlan(dialogContext, PurchaseTier.core),
          ),
          const SizedBox(height: 12),
          _PricingTierCard(
            name: 'PRO / EDGE',
            price: '\$89.99 / MONTH',
            description:
                'The complete intelligence suite for advanced decision support.',
            featured: true,
            features: [
              'Everything in Core',
              'AI projections, confidence scores and edge metrics',
              'Fatigue, travel, officiating and matchup context',
              'Correlation engine and parlay compatibility flags',
              'Game-script and Monte Carlo simulations',
              'Historical similarity matching and sentiment signals',
              'Custom compound alerts and stale-line notifications',
              'Prediction history, grading and model calibration',
            ],
            onPressed: (dialogContext) =>
                _choosePlan(dialogContext, PurchaseTier.edge),
          ),
          const SizedBox(height: 16),
          const _AboutNotice(
            title: 'NO GUARANTEED OUTCOMES',
            text:
                'Plans provide research, modeling and organizational tools. Predictions are informational and do not guarantee winning wagers.',
          ),
        ];
      case 'contact':
        title = 'CONTACT';
        subtitle = 'QUESTIONS, FEEDBACK OR ACCOUNT SUPPORT';
        icon = Icons.forum_outlined;
        content = const [
          Text(
            'PROP INTELLIGENCE is being shaped with real user feedback. If you have a question, find an issue or want to share an idea, we want to hear it.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          SizedBox(height: 16),
          _AboutNotice(title: 'EMAIL', text: 'propsintell@gmail.com'),
          SizedBox(height: 10),
          _AboutNotice(
            title: 'MEMBER FEEDBACK',
            text:
                'Members can also continue using the support channel where they received assistance.',
          ),
        ];
      case 'terms':
        title = 'TERMS & CONDITIONS';
        subtitle = 'SUBSCRIPTIONS, RESPONSIBLE USE & ACCOUNT TERMS';
        icon = Icons.gavel_rounded;
        content = const [
          _LegalSection(
            title: 'SUBSCRIPTIONS & BILLING',
            text:
                'Core is \$29.99 per month and Edge is \$89.99 per month. Subscriptions renew automatically each month until canceled. Prices and applicable taxes are shown before purchase.',
          ),
          _LegalSection(
            title: 'CANCELLATION & ACCESS',
            text:
                'You may cancel at any time through the billing portal or the platform used to purchase. Cancellation stops future renewals; access generally continues through the end of the paid billing period.',
          ),
          _LegalSection(
            title: 'REFUNDS',
            text:
                'Except where required by law, subscription charges are non-refundable once a billing period begins. Contact support promptly if you believe a charge was made in error.',
          ),
          _LegalSection(
            title: 'INFORMATIONAL SERVICE',
            text:
                'PROP INTELLIGENCE provides sports information, analytics, projections and organizational tools. Results are estimates, not guarantees. Nothing in the service is financial, legal or gambling advice.',
          ),
          _LegalSection(
            title: 'RESPONSIBLE PLAY',
            text:
                'Only participate where lawful and only if you meet the legal age requirement in your location. Set limits, never chase losses and seek help if play stops being recreational.',
          ),
          _LegalSection(
            title: 'ACCOUNT RESPONSIBILITIES',
            text:
                'Keep your credentials secure, provide accurate account information and do not share, resell, scrape, reverse engineer or misuse the service. You are responsible for activity under your account.',
          ),
          _LegalSection(
            title: 'AVAILABILITY & LIABILITY',
            text:
                'Data may be delayed, incomplete or inaccurate, and features may change. Always verify live lines and market rules. To the fullest extent permitted by law, use of the service is at your own risk.',
          ),
          _AboutNotice(
            title: 'SUPPORT & EFFECTIVE DATE',
            text:
                'Questions: propsintell@gmail.com. Effective July 18, 2026. The complete published Terms and Privacy Policy govern use of the service.',
          ),
        ];
      default:
        return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panelBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _gold.withValues(alpha: 0.72)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        title: Row(
          children: [
            Icon(icon, color: _gold, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
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
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.7,
                  ),
                ),
                const SizedBox(height: 16),
                ...content,
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('BACK TO LOGIN'),
          ),
        ],
      ),
    );
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
                    color: _silver70,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'WHAT YOU CAN DO',
                  style: TextStyle(
                    color: _silver,
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
                  title: 'PAID MEMBERSHIP',
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
        title: const Text('Developer Access', style: TextStyle(color: _silver)),
        content: TextField(
          controller: pinController,
          obscureText: true,
          style: const TextStyle(color: _silver),
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
                                  child: Column(
                                    children: [
                                      if (compact)
                                        Column(
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
                                      else
                                        Row(
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
                                      SizedBox(height: compact ? 34 : 48),
                                      _InstallAnywhereSection(compact: compact),
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
                style: TextStyle(color: _silver, fontSize: dense ? 14 : 16),
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
                style: TextStyle(color: _silver, fontSize: dense ? 14 : 16),
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
                      color: _silver54,
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
              leading: Image.asset(
                'assets/branding/google_g_logo.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
              onPressed: _isLoading
                  ? null
                  : () => _handleSocialSignIn(OAuthProvider.google),
            ),
            const SizedBox(height: 8),
            _SocialButton(
              label: 'Continue with Apple',
              leading: const Icon(Icons.apple, color: _silver, size: 23),
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
                  style: const TextStyle(color: _silver54, fontSize: 11),
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
      hintStyle: const TextStyle(color: _silver38, fontSize: 14),
      prefixIcon: Icon(prefixIcon, color: _gold, size: 20),
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

class _InstallAnywhereSection extends StatelessWidget {
  final bool compact;

  const _InstallAnywhereSection({required this.compact});

  @override
  Widget build(BuildContext context) {
    const devices = [
      (
        Icons.android_rounded,
        'ANDROID',
        'Tap Install when prompted, or choose Install app from your browser menu.',
      ),
      (
        Icons.phone_iphone_rounded,
        'IPHONE & IPAD',
        'Open in Safari, tap Share, then choose Add to Home Screen.',
      ),
      (
        Icons.tablet_mac_rounded,
        'TABLETS',
        'Use portrait or landscape mode with the same account and full workspace.',
      ),
      (
        Icons.desktop_windows_rounded,
        'DESKTOP',
        'Install from Chrome or Edge for fast, app-like access from your desktop.',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 22 : 30),
      decoration: BoxDecoration(
        color: const Color(0xEC071017),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _gold.withValues(alpha: 0.48)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.48),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.install_mobile_rounded, color: _gold, size: 34),
          const SizedBox(height: 10),
          Text(
            'INSTALL ON ANY DEVICE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold,
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'PROP INTELLIGENCE is a secure Progressive Web App. Install it directly from your browser—no app-store download required.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1060
                  ? 4
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              final spacing = 12.0;
              final cardWidth =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final device in devices)
                    SizedBox(
                      width: cardWidth,
                      child: _DeviceInstallCard(
                        icon: device.$1,
                        title: device.$2,
                        instructions: device.$3,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sync_rounded, color: _gold, size: 16),
              SizedBox(width: 7),
              Flexible(
                child: Text(
                  'One account. Automatic updates. Your research stays available across devices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _silver,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceInstallCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String instructions;

  const _DeviceInstallCard({
    required this.icon,
    required this.title,
    required this.instructions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 138),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xD90B151D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF263744)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _gold, size: 23),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: _silver,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            instructions,
            style: const TextStyle(
              color: _silver60,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
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
                side: BorderSide(color: _gold.withValues(alpha: 0.65)),
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
              ('TERMS', 'terms'),
              ('CONTACT', 'contact'),
            ])
              TextButton(
                onPressed: () => onNavigate(item.$2),
                style: TextButton.styleFrom(
                  foregroundColor: _silver70,
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
              side: BorderSide(color: _gold.withValues(alpha: 0.65)),
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
            'assets/branding/prop_intelligence_logo_transparent.png',
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
                color: _silver70,
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

class _FeatureGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;

  const _FeatureGroup({
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _silver.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _gold, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: _silver,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          for (final item in items) _AboutBullet(item),
        ],
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  final String title;
  final String text;

  const _LegalSection({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _gold,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: _silver70,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingTierCard extends StatelessWidget {
  final String name;
  final String price;
  final String description;
  final List<String> features;
  final bool featured;
  final ValueChanged<BuildContext>? onPressed;

  const _PricingTierCard({
    required this.name,
    required this.price,
    required this.description,
    required this.features,
    this.featured = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: featured
            ? _gold.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: featured
              ? _gold.withValues(alpha: 0.82)
              : _silver.withValues(alpha: 0.16),
          width: featured ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: _silver,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        if (featured) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _gold,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'BEST VALUE',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: _silver70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                price,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: featured ? _gold : _silver,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: featured ? _gold : const Color(0xFF36B9FF),
                    size: 16,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: _silver70,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: featured
                ? FilledButton(
                    onPressed: onPressed == null
                        ? null
                        : () => onPressed!(context),
                    child: const Text('CHOOSE PRO / EDGE'),
                  )
                : OutlinedButton(
                    onPressed: onPressed == null
                        ? null
                        : () => onPressed!(context),
                    child: const Text('CHOOSE CORE'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OverlayStep extends StatelessWidget {
  final String number;
  final String title;
  final String text;

  const _OverlayStep({
    required this.number,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withValues(alpha: 0.55)),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: _gold,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _silver,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: _silver60,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
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
              color: _silver60,
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
          Icon(icon, color: _gold, size: 36),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _silver54, fontSize: 11, height: 1.5),
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
        Text(label, style: const TextStyle(color: _silver, fontSize: 12)),
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
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _silver,
          backgroundColor: const Color(0xFF0D1114),
          side: const BorderSide(color: _gold, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(fontSize: 14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 24, child: Center(child: leading)),
            const SizedBox(width: 10),
            SizedBox(width: 150, child: Text(label, textAlign: TextAlign.left)),
          ],
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
          child: Text('OR', style: TextStyle(color: _silver54, fontSize: 10)),
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
          Icon(Icons.lock_outline_rounded, color: _gold, size: 12),
          SizedBox(width: 7),
          Flexible(
            child: Text(
              '(C) 2026 PI PROP INTELLIGENCE. ALL RIGHTS RESERVED.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _silver38,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSportsAtmosphere = constraints.maxWidth >= 900;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _pageBackground),
            const ColoredBox(color: Color(0xFF12364D)),

            CustomPaint(painter: _MarketGridPainter()),
            if (showSportsAtmosphere) ...[
              const Positioned(
                left: 24,
                top: 120,
                child: _BackgroundSportIcon(
                  icon: Icons.sports_basketball_rounded,
                  size: 116,
                  rotation: -0.18,
                  opacity: 0.48,
                ),
              ),
              const Positioned(
                left: 42,
                bottom: 90,
                child: _BackgroundSportIcon(
                  icon: Icons.sports_baseball_rounded,
                  size: 104,
                  rotation: 0.16,
                  opacity: 0.48,
                ),
              ),
              const Positioned(
                right: 34,
                top: 155,
                child: _BackgroundSportIcon(
                  icon: Icons.sports_football_rounded,
                  size: 94,
                  rotation: -0.48,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BackgroundSportIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final double rotation;
  final double opacity;

  const _BackgroundSportIcon({
    required this.icon,
    required this.size,
    required this.rotation,
    this.opacity = 0.055,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Icon(
        icon,
        size: size,
        color: _gold.withValues(alpha: opacity),
        shadows: [
          Shadow(color: _gold.withValues(alpha: opacity * 0.9), blurRadius: 28),
        ],
      ),
    );
  }
}

class _MarketGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final isCompact = size.width < 900;
    final gridPaint = Paint()
      ..color = _gold.withValues(alpha: isCompact ? 0.08 : 0.13)
      ..strokeWidth = 0.55;
    final spacing = isCompact ? 44.0 : 38.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawDiagonalGeometry(canvas, size);
    _drawDotField(
      canvas,
      origin: Offset(size.width * 0.39, size.height * 0.08),
      columns: isCompact ? 10 : 22,
      rows: isCompact ? 6 : 14,
      step: isCompact ? 12 : 9,
    );
    _drawDotField(
      canvas,
      origin: Offset(size.width * 0.53, size.height * 0.69),
      columns: isCompact ? 9 : 20,
      rows: isCompact ? 6 : 13,
      step: isCompact ? 13 : 9,
      fadeRight: false,
    );

    final chartPaint = Paint()
      ..color = _gold.withValues(alpha: isCompact ? 0.12 : 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    final path = Path()
      ..moveTo(0, size.height * 0.67)
      ..lineTo(size.width * 0.09, size.height * 0.6)
      ..lineTo(size.width * 0.17, size.height * 0.64)
      ..lineTo(size.width * 0.28, size.height * 0.43)
      ..lineTo(size.width * 0.39, size.height * 0.52)
      ..lineTo(size.width * 0.51, size.height * 0.31)
      ..lineTo(size.width * 0.64, size.height * 0.39)
      ..lineTo(size.width * 0.79, size.height * 0.2)
      ..lineTo(size.width, size.height * 0.28);
    canvas.drawPath(path, chartPaint);

    final secondaryChart = Path()
      ..moveTo(size.width * 0.12, size.height * 0.36)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.29,
        size.width * 0.31,
        size.height * 0.42,
        size.width * 0.44,
        size.height * 0.27,
      )
      ..cubicTo(
        size.width * 0.57,
        size.height * 0.12,
        size.width * 0.71,
        size.height * 0.3,
        size.width * 0.9,
        size.height * 0.14,
      );
    canvas.drawPath(
      secondaryChart,
      Paint()
        ..color = const Color(0xFF95A6B3).withValues(alpha: 0.075)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    if (!isCompact) {
      _drawCallout(
        canvas,
        '+12.45%',
        Offset(size.width * 0.52, size.height * 0.15),
        18,
      );
      _drawCallout(
        canvas,
        '5.8',
        Offset(size.width * 0.55, size.height * 0.43),
        27,
      );
      _drawCallout(
        canvas,
        'EDGE',
        Offset(size.width * 0.55, size.height * 0.465),
        11,
      );
      _drawCallout(
        canvas,
        '67%',
        Offset(size.width * 0.12, size.height * 0.52),
        24,
      );
      _drawCallout(
        canvas,
        'PROBABILITY',
        Offset(size.width * 0.12, size.height * 0.555),
        9,
      );
    }

    final lowerGlow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF07131C).withValues(alpha: 0.46),
          Colors.black.withValues(alpha: 0.22),
        ],
      ).createShader(bounds);
    canvas.drawRect(bounds, lowerGlow);
  }

  void _drawDiagonalGeometry(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = _gold.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final softLinePaint = Paint()
      ..color = const Color(0xFF8EA0AC).withValues(alpha: 0.065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    for (var index = -2; index < 9; index++) {
      final startX = size.width * (index * 0.17);
      canvas.drawLine(
        Offset(startX, size.height),
        Offset(startX + size.height * 0.72, 0),
        index.isEven ? linePaint : softLinePaint,
      );
    }

    final rightFacet = Path()
      ..moveTo(size.width * 0.77, 0)
      ..lineTo(size.width, size.height * 0.28)
      ..lineTo(size.width * 0.9, size.height * 0.55)
      ..lineTo(size.width, size.height * 0.7);
    canvas.drawPath(rightFacet, linePaint);
  }

  void _drawDotField(
    Canvas canvas, {
    required Offset origin,
    required int columns,
    required int rows,
    required double step,
    bool fadeRight = true,
  }) {
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final horizontalFade = fadeRight
            ? 1 - (column / columns)
            : (column + 1) / columns;
        final verticalFade = 1 - ((row - rows / 2).abs() / rows);
        dotPaint.color = _gold.withValues(
          alpha: 0.22 * horizontalFade * verticalFade,
        );
        canvas.drawCircle(
          origin + Offset(column * step, row * step),
          column % 4 == 0 ? 1.25 : 0.8,
          dotPaint,
        );
      }
    }
  }

  void _drawCallout(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _gold.withValues(alpha: 0.2),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
