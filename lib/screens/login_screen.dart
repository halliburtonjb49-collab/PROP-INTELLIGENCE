import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../legal/legal_content.dart';

import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../services/subscription_pricing.dart';
import '../services/developer_mode_service.dart';
import '../services/pwa_install_bridge.dart';
import '../theme/prop_intelligence_colors.dart';
import '../widgets/compliance_notice_badge.dart';

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

/// Tries the browser's native install prompt first (Chrome/Edge/Android);
/// falls back to a device-specific instructions dialog where the platform
/// doesn't support programmatic installs (iOS Safari, unsupported browsers).
Future<void> _handleDeviceInstallTap(
  BuildContext context, {
  required String title,
  required String instructions,
  required IconData icon,
}) async {
  if (kIsWeb && isPwaInstallAvailable()) {
    final outcome = await triggerPwaInstall();
    if (outcome == 'accepted' || outcome == 'dismissed') return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: _panelBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _gold.withValues(alpha: 0.72)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          Icon(icon, color: _gold, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _gold,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        instructions,
        style: const TextStyle(color: _silver70, fontSize: 14, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('GOT IT'),
        ),
      ],
    ),
  );
}

class _PwaInstallNavButton extends StatelessWidget {
  final Future<void> Function(String section) onFallback;

  const _PwaInstallNavButton({required this.onFallback});

  Future<void> _handleTap(BuildContext context) async {
    if (kIsWeb && isPwaInstallAvailable()) {
      final outcome = await triggerPwaInstall();
      if (outcome == 'accepted' || outcome == 'dismissed') return;
    }
    await onFallback('install');
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Install PROP INTELLIGENCE',
      child: IconButton(
        onPressed: () => _handleTap(context),
        icon: const Icon(
          Icons.install_mobile_rounded,
          size: 18,
          color: _silver70,
        ),
        style: IconButton.styleFrom(
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(34, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class CorporateLoginScreen extends StatefulWidget {
  const CorporateLoginScreen({super.key});

  @override
  State<CorporateLoginScreen> createState() => _CorporateLoginScreenState();
}

class _CorporateLoginScreenState extends State<CorporateLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = SportsAppAuthService();
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _obscurePassword = true;
  int _resendCooldownSeconds = 0;
  Timer? _resendCooldownTimer;
  PurchaseTier? _pendingPurchaseTier;
  PurchaseInterval _pendingPurchaseInterval = PurchaseInterval.monthly;

  @override
  void dispose() {
    _resendCooldownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
    if (_isRegistering && password.length < 8) {
      _showFeedbackMessage(
        'Create an app password with at least 8 characters.',
      );
      return;
    }
    if (_isRegistering && password != _confirmPasswordController.text) {
      _showFeedbackMessage('The app passwords do not match.');
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
      final interval = _pendingPurchaseInterval;
      _pendingPurchaseTier = null;
      final billing = RevenueCatBillingService();
      await billing.initializeBillingEngine();
      if (mounted) {
        await billing.processSubscriptionPurchase(
          context,
          tier,
          interval: interval,
        );
      }
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

  void _choosePlan(
    BuildContext dialogContext,
    PurchaseTier tier, {
    PurchaseInterval interval = PurchaseInterval.monthly,
  }) {
    Navigator.of(dialogContext).pop();
    setState(() {
      _pendingPurchaseTier = tier;
      _pendingPurchaseInterval = interval;
      _isRegistering = true;
    });
    _showFeedbackMessage(
      'Create your account to continue with the ${tier == PurchaseTier.core ? 'Core' : 'Pro'} plan.',
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
              'Sport-first market board that opens on an active in-season league',
              'Provider-separated props with site-specific sport filtering',
              'Live player props, moneylines, spreads, totals and line comparison',
              'Live, upcoming and final scoreboards across major sports',
              'Provider freshness, no-inventory, stale-feed and recovery indicators',
            ],
          ),
          _FeatureGroup(
            icon: Icons.psychology_alt_rounded,
            title: 'MODEL INTELLIGENCE',
            items: [
              'PI Adaptive Intelligence grades outcomes and learns from verified wins and losses',
              'Guarded challenger calibration must improve on unseen results before promotion',
              'PI Trust, projections, edge and expected-value research signals',
              'Matchup, fatigue, travel, officiating and game-script context',
              'Correlation analysis, simulations and historical analogs',
              'Poisson and Monte Carlo modeling with de-vigged market probabilities',
              'Transparent model-version, calibration and evidence reporting',
            ],
          ),
          _FeatureGroup(
            icon: Icons.receipt_long_rounded,
            title: 'BUILD & TRACK',
            items: [
              'Add or remove Over and Under research picks directly from each card',
              'Provider-safe active slips with same-site protection and clear undo controls',
              'Slip Watcher with live scoring, ticket results and profit by site',
              'Build Performance by sport, player, site and category',
              'Shared props and slips with a clear path from research to tracking',
            ],
          ),
          _FeatureGroup(
            icon: Icons.forum_rounded,
            title: 'PROP CHAT & ALERTS',
            items: [
              'Main community chat, direct messages and shared research',
              'Pro sport rooms, game threads and verified expert or creator badges',
              'A movable mobile chat bubble that keeps the board visible',
              'Web and mobile push notifications for important activity and updates',
            ],
          ),
          _FeatureGroup(
            icon: Icons.auto_awesome_rounded,
            title: 'ADVANCED PRO TOOLS',
            items: [
              'Actionable EV Scanner with fair-price and prop-site comparison',
              'Strikeout Pro Gold with all-site and individual-site views',
              'Multi-sport Intelligence Lab and the updated PI Guide',
              'Owner monitoring for outages, stale providers and inventory gaps',
            ],
          ),
          _AboutNotice(
            title: 'BUILT FOR INFORMED DECISIONS',
            text:
                'PROP INTELLIGENCE is a professional sports-research workspace. Start with an in-season sport, review props organized by provider, inspect the evidence, and organize the selections you want to monitor.',
          ),
          _AboutNotice(
            title: 'INDEPENDENT ANALYTICS ONLY',
            text:
                'PROP INTELLIGENCE provides independent sports research, analytics, pick tracking, and community features. We do not accept wagers, operate a sportsbook, or facilitate betting transactions.',
          ),
        ];
      case 'how-it-works':
        title = 'HOW IT WORKS';
        subtitle = 'A SIMPLER RESEARCH PROCESS';
        icon = Icons.route_rounded;
        content = const [
          _OverlayStep(
            number: '01',
            title: 'START WITH A LIVE SPORT',
            text:
                'The board opens on an in-season league. Switch sports at any time from the top banner.',
          ),
          _OverlayStep(
            number: '02',
            title: 'CHOOSE A PROVIDER',
            text:
                'Review separated provider sections or filter to one prop site and its available sports.',
          ),
          _OverlayStep(
            number: '03',
            title: 'RESEARCH THE PICK',
            text:
                'Compare the line, PI Trust, recommendation, context and detailed research before selecting a side.',
          ),
          _OverlayStep(
            number: '04',
            title: 'ORGANIZE AND REVIEW',
            text:
                'Add or remove picks, monitor changes, and review graded history to improve your process.',
          ),
        ];
      case 'install':
        title = 'INSTALL APP';
        subtitle = 'FAST, FULL-SCREEN ACCESS ON EVERY DEVICE';
        icon = Icons.install_mobile_rounded;
        content = const [
          _AboutNotice(
            title: 'IPHONE & IPAD',
            text:
                'Open app.propsintell.com in Safari, tap Share, then choose Add to Home Screen.',
          ),
          SizedBox(height: 10),
          _AboutNotice(
            title: 'ANDROID',
            text:
                'Open the site in Chrome and tap Install when prompted, or choose Install app from the browser menu.',
          ),
          SizedBox(height: 10),
          _AboutNotice(
            title: 'DESKTOP',
            text:
                'Open the site in Chrome or Edge and choose Install when prompted or from the address-bar install icon.',
          ),
          SizedBox(height: 14),
          Text(
            'Installation gives you a dedicated app window, faster access and automatic updates without visiting an app store.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.55),
          ),
        ];
      case 'about':
        title = 'ABOUT';
        subtitle = 'WHY I BUILT PROP INTELLIGENCE';
        icon = Icons.person_outline_rounded;
        content = [
          const Text(
            'I created PROP INTELLIGENCE because serious sports research should not require jumping between disconnected feeds, spreadsheets and generic pick pages.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          SizedBox(height: 14),
          Text(
            'The product brings live markets, provider-separated props, scoreboards, model context, active-slip organization and performance review into one consistent workspace.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          SizedBox(height: 14),
          Text(
            'PROP INTELLIGENCE does not promise outcomes or place wagers. It is designed to make information clearer, expose freshness and limitations, and help members follow a disciplined research process.',
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
            'Choose Core for live research, provider comparison and organization, or Pro for deeper model intelligence, advanced scanners and specialty research tools. An active subscription is required; there is no permanent free tier.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          const SizedBox(height: 20),
          _PricingTierCard(
            name: 'CORE',
            price: SubscriptionPricing.coreMonthly,
            description:
                'Silver access for everyday research, manual building and standard tracking.',
            features: [
              'Manual prop builder and standard player research',
              'Live scoreboard and standard stat tracking',
              'Save, organize and track prop slips',
              'Game-market and prop-site comparisons',
              'Basic analytics and recent line changes',
              '14-day slip history with standard grading',
              'Multi-sport research across major leagues',
              'Read and participate in the main Prop Chat room',
              'Web and mobile push notifications',
            ],
            notIncluded: [
              'No AI projections, confidence scores or edge percentages',
              'No alerts, simulations, EV Scanner or Intelligence Lab',
              'No Strikeout Pro Gold or advanced performance reports',
              'No Pro sport rooms, game threads, expert badges or advanced chat tools',
            ],
            onPressed: (dialogContext) =>
                _choosePlan(dialogContext, PurchaseTier.core),
            onAnnualPressed: (dialogContext) => _choosePlan(
              dialogContext,
              PurchaseTier.core,
              interval: PurchaseInterval.annual,
            ),
            annualPrice: SubscriptionPricing.coreAnnual,
          ),
          const SizedBox(height: 12),
          _PricingTierCard(
            name: 'PRO',
            price: SubscriptionPricing.proMonthly,
            description:
                'Gold access to the complete model and automation suite.',
            featured: true,
            features: [
              'Everything in Core',
              'Advanced analytics, projections and edge metrics',
              'Advanced line intelligence and stale-line alerts',
              'Full history, profit tracking and model calibration',
              'Fatigue, travel, officiating and matchup context',
              'Correlation engine and multi-selection compatibility flags',
              'Game-script and Monte Carlo simulations',
              'Historical similarity matching and sentiment signals',
              'EV Scanner, Intelligence Lab and Strikeout Pro Gold',
              'Advanced performance reports and prediction history',
              'Pro sport rooms, game threads and direct messages',
              'Shared Pro analysis, props and slips',
              'Verified expert or creator badges and future advanced chat tools',
              'Priority push alerts for tracked tickets and community activity',
            ],
            onPressed: (dialogContext) =>
                _choosePlan(dialogContext, PurchaseTier.edge),
            onAnnualPressed: (dialogContext) => _choosePlan(
              dialogContext,
              PurchaseTier.edge,
              interval: PurchaseInterval.annual,
            ),
            annualPrice: SubscriptionPricing.proAnnual,
          ),
          const SizedBox(height: 12),
          _PricingTierCard(
            name: 'FOUNDING PRO',
            price: SubscriptionPricing.foundingProMonthly,
            description:
                'The complete Pro experience at a locked founding-member price.',
            featured: true,
            buttonLabel: 'CLAIM FOUNDING PRO',
            features: const [
              'Everything in Pro',
              'Founding price while the subscription remains active',
              'Limited to the first 100 members',
              '3-day monthly trial or 7-day annual trial',
            ],
            onPressed: (dialogContext) =>
                _choosePlan(dialogContext, PurchaseTier.foundingEdge),
            onAnnualPressed: (dialogContext) => _choosePlan(
              dialogContext,
              PurchaseTier.foundingEdge,
              interval: PurchaseInterval.annual,
            ),
            annualPrice: SubscriptionPricing.foundingProAnnual,
          ),
          const SizedBox(height: 16),
          const _AboutNotice(
            title: 'NO GUARANTEED OUTCOMES',
            text:
                'Plans provide research, modeling, and organizational tools. Predictions are informational and do not guarantee successful outcomes.',
          ),
        ];
      case 'contact':
        title = 'CONTACT';
        subtitle = 'QUESTIONS, FEEDBACK OR ACCOUNT SUPPORT';
        icon = Icons.forum_outlined;
        content = const [
          Text(
            'PROP INTELLIGENCE is actively improved using member feedback and reliability monitoring. Contact us for account support, provider-data concerns, accessibility issues or product suggestions.',
            style: TextStyle(color: _silver70, fontSize: 14, height: 1.65),
          ),
          SizedBox(height: 16),
          _AboutNotice(title: 'EMAIL', text: 'propsintell@gmail.com'),
          SizedBox(height: 10),
          _AboutNotice(
            title: 'MEMBER FEEDBACK',
            text:
                'Signed-in members can also use Prop Chat and the in-app feedback controls to report workflow issues.',
          ),
        ];
      case 'terms':
        title = 'TERMS & CONDITIONS';
        subtitle = 'SUBSCRIPTIONS, RESPONSIBLE USE & ACCOUNT TERMS';
        icon = Icons.gavel_rounded;
        content = termsSections
            .map((section) => LegalSectionView(section: section))
            .toList();
      case 'privacy':
        title = 'PRIVACY POLICY';
        subtitle = 'HOW PROP INTELLIGENCE HANDLES YOUR DATA';
        icon = Icons.privacy_tip_outlined;
        content = privacySections
            .map((section) => LegalSectionView(section: section))
            .toList();
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
                  'PI LEARNING INTELLIGENCE\nPREDICT. GRADE. LEARN. IMPROVE.',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'PI Adaptive Intelligence transforms live player, matchup and market data into clear prop research, grades verified outcomes, and uses proven lessons from wins and losses to improve future confidence rankings.',
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
                _AboutBullet('Learn from verified wins and losses'),
                _AboutBullet('Promote only validated model improvements'),
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
                      'For informational and entertainment purposes only. Predictions are not guaranteed. Users must meet applicable age requirements and follow all local rules.',
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
                      onLogin: () {
                        if (_isRegistering) {
                          setState(() => _isRegistering = false);
                        }
                      },
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
                                            _buildLoginCard(dense: true),
                                            const SizedBox(height: 24),
                                            _HeroBrand(
                                              compact: true,
                                              dense: true,
                                              onLongPress:
                                                  _openDeveloperBypassPrompt,
                                            ),
                                          ],
                                        )
                                      else
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                      SizedBox(height: compact ? 24 : 34),
                                      _Footer(onNavigate: _openSiteSection),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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
              _isRegistering ? 'CREATE YOUR LOGIN' : 'WELCOME BACK',
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
                  ? 'Step 1 of 3 · Create your PROP INTELLIGENCE login'
                  : 'Returning member? Log in to access your dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedText, fontSize: dense ? 15 : 16),
            ),
            const SizedBox(height: 10),
            ComplianceNoticeBadge(
              size: dense ? 26 : 28,
              fontSize: dense ? 10.5 : 11.5,
              textColor: _silver70.withValues(alpha: 0.38),
              alwaysShowNotice: true,
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
                key: const ValueKey('login-email-field'),
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
              label: _isRegistering ? 'Create App Password' : 'Password',
              child: TextField(
                key: const ValueKey('login-password-field'),
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
                      ? 'Use at least 8 characters'
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
            if (_isRegistering) ...[
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'This is your PROP INTELLIGENCE password—not your Gmail password.',
                  style: TextStyle(color: _silver54, fontSize: 11),
                ),
              ),
              const SizedBox(height: 14),
              _FieldLabel(
                label: 'Confirm App Password',
                child: TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  onSubmitted: (_) => _handleAuthentication(),
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  style: TextStyle(color: _silver, fontSize: dense ? 14 : 16),
                  decoration: _fieldDecoration(
                    hint: 'Enter the same app password again',
                    prefixIcon: Icons.lock_reset_rounded,
                  ),
                ),
              ),
            ],
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
                key: const ValueKey('login-submit-action'),
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
                        _isRegistering
                            ? 'CONTINUE TO EMAIL VERIFICATION'
                            : 'LOGIN',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
              ),
            ),
            if (_isRegistering) ...[
              const SizedBox(height: 10),
              const Text(
                'Next: verify your email, then choose Core or Pro. You will not be charged on this screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _silver54, fontSize: 11, height: 1.35),
              ),
            ],
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
            const SizedBox(height: 10),
            _SocialButton(
              label: 'Continue with Apple',
              leading: const Icon(
                Icons.apple,
                size: 22,
                color: Colors.white,
              ),
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
                      : 'Already created your login? Resend verification email',
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
        'Install PI Prop Intelligence from the Apple App Store, or add the secure web app from Safari.',
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
            'INSTALL PI YOUR WAY',
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
            'Use the native iPhone and iPad app or install the secure PI web app from your browser. The same account and research follow you everywhere.',
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
    return Material(
      color: const Color(0xD90B151D),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _handleDeviceInstallTap(
          context,
          title: title,
          instructions: instructions,
          icon: icon,
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 138),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
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
              const SizedBox(height: 8),
              const Text(
                'TAP TO INSTALL',
                style: TextStyle(
                  color: _gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopNavigation extends StatelessWidget {
  final bool compact;
  final bool tight;
  final VoidCallback onBrandTap;
  final Future<void> Function(String section) onNavigate;
  final VoidCallback onLogin;
  final VoidCallback onSignUp;

  const _TopNavigation({
    required this.compact,
    required this.tight,
    required this.onBrandTap,
    required this.onNavigate,
    required this.onLogin,
    required this.onSignUp,
  });

  Future<void> _showMobileMenu(BuildContext context) async {
    const items = <(String, String, IconData)>[
      ('FEATURES', 'features', Icons.query_stats_rounded),
      ('HOW PI LEARNS', 'how-it-works', Icons.route_rounded),
      ('PRICING', 'pricing', Icons.workspace_premium_outlined),
      ('ABOUT', 'about', Icons.info_outline_rounded),
      ('INSTALL APP', 'install', Icons.install_mobile_rounded),
      ('TERMS', 'terms', Icons.gavel_rounded),
      ('PRIVACY', 'privacy', Icons.privacy_tip_outlined),
      ('CONTACT', 'contact', Icons.forum_outlined),
    ];
    final section = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panelBackground,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text(
                'EXPLORE PROP INTELLIGENCE',
                style: TextStyle(
                  color: _gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            for (final item in items)
              ListTile(
                leading: Icon(item.$3, color: _gold, size: 21),
                title: Text(
                  item.$1,
                  style: const TextStyle(
                    color: _silver,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: _silver60,
                ),
                onTap: () => Navigator.of(sheetContext).pop(item.$2),
              ),
          ],
        ),
      ),
    );
    if (section != null && context.mounted) {
      await onNavigate(section);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessibleCompact =
        compact || MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Container(
      height: accessibleCompact ? 58 : 66,
      padding: EdgeInsets.symmetric(
        horizontal: accessibleCompact ? 8 : (tight ? 18 : 42),
      ),
      decoration: const BoxDecoration(
        color: Color(0xD9000305),
        border: Border(bottom: BorderSide(color: Color(0xFF29220F))),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'About PROP INTELLIGENCE',
            child: OutlinedButton(
              onPressed: onBrandTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withValues(alpha: 0.65)),
                padding: EdgeInsets.symmetric(
                  horizontal: accessibleCompact ? 9 : (tight ? 10 : 16),
                  vertical: accessibleCompact ? 9 : (tight ? 10 : 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: accessibleCompact
                  ? const Icon(
                      Icons.query_stats_rounded,
                      color: _gold,
                      size: 18,
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.query_stats_rounded, color: _gold, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'PROP INTELLIGENCE',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const Spacer(),
          if (!accessibleCompact) ...[
            for (final item in [
              const ('FEATURES', 'features'),
              const ('HOW PI LEARNS', 'how-it-works'),
              const ('PRICING', 'pricing'),
              const ('ABOUT', 'about'),
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
            _PwaInstallNavButton(onFallback: onNavigate),
            const SizedBox(width: 4),
          ] else ...[
            // Install guidance already lives in the mobile menu below -
            // no room for a separate icon on a phone-width top bar.
            IconButton(
              key: const ValueKey('mobile-info-menu'),
              tooltip: 'Explore information and installation',
              onPressed: () => _showMobileMenu(context),
              icon: const Icon(Icons.menu_rounded, color: _gold),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),
          ],
          SizedBox(width: accessibleCompact ? 2 : 10),
          TextButton(
            key: const ValueKey('header-login-action'),
            onPressed: onLogin,
            style: TextButton.styleFrom(
              foregroundColor: _gold,
              padding: EdgeInsets.symmetric(
                horizontal: accessibleCompact ? 5 : 14,
                vertical: accessibleCompact ? 9 : 12,
              ),
            ),
            child: const Text(
              'LOGIN TO APP',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ),
          SizedBox(width: accessibleCompact ? 0 : 6),
          OutlinedButton(
            onPressed: onSignUp,
            style: OutlinedButton.styleFrom(
              foregroundColor: _gold,
              side: BorderSide(color: _gold.withValues(alpha: 0.65)),
              padding: EdgeInsets.symmetric(
                horizontal: accessibleCompact ? 7 : (tight ? 14 : 22),
                vertical: accessibleCompact ? 9 : (tight ? 11 : 15),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'CREATE ACCOUNT',
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
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: _gold.withValues(alpha: .55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.query_stats_rounded, color: _gold, size: 15),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                  compact ? 'LIVE SPORTS RESEARCH' : 'LIVE MULTI-SPORT RESEARCH',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _gold,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 16 : 20),
        Text(
          'RESEARCH THE MARKET.\nBUILD WITH CLARITY.',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 30 : (dense ? 34 : 44),
            height: 1.02,
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 13),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Text(
            'Compare live props by sport and provider, understand every PI signal, and organize your research in one professional workspace.',
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              color: _silver70,
              fontSize: compact ? 14 : 16,
              height: 1.5,
            ),
          ),
        ),
        SizedBox(height: compact ? 18 : 22),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: const [
            _HeroCapability(Icons.sports_rounded, 'SPORT-FIRST BOARD'),
            _HeroCapability(Icons.storefront_rounded, 'PROVIDER SECTIONS'),
            _HeroCapability(Icons.scoreboard_rounded, 'LIVE SCOREBOARD'),
            _HeroCapability(Icons.receipt_long_rounded, 'ACTIVE SLIPS'),
          ],
        ),
        SizedBox(height: compact ? 20 : 26),
        _ProductPreview(compact: compact),
      ],
    );
  }
}

class _HeroCapability extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroCapability(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xCC08141D),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _silver.withValues(alpha: .16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _gold),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: _silver,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: .45,
          ),
        ),
      ],
    ),
  );
}

class _ProductPreview extends StatelessWidget {
  final bool compact;

  const _ProductPreview({required this.compact});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxWidth: 720),
    padding: EdgeInsets.all(compact ? 13 : 16),
    decoration: BoxDecoration(
      color: const Color(0xF2071119),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gold.withValues(alpha: .55)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .45),
          blurRadius: 30,
          offset: const Offset(0, 16),
        ),
      ],
    ),
    child: Column(
      children: [
        const Row(
          children: [
            Icon(Icons.grid_view_rounded, color: _gold, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'MARKET BOARD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            Icon(Icons.circle, color: Color(0xFF55D6A3), size: 8),
            SizedBox(width: 6),
            Text(
              'LIVE',
              style: TextStyle(
                color: Color(0xFF55D6A3),
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        const Row(
          children: [
            _PreviewSport('MLB', true),
            SizedBox(width: 7),
            _PreviewSport('NBA', false),
            SizedBox(width: 7),
            _PreviewSport('WNBA', false),
            SizedBox(width: 7),
            _PreviewSport('NFL', false),
          ],
        ),
        const SizedBox(height: 13),
        const _PreviewProvider(
          provider: 'DRAFTKINGS',
          player: 'PLAYER PROPS',
          signal: 'PI TRUST 91',
        ),
        const SizedBox(height: 8),
        const _PreviewProvider(
          provider: 'FANDUEL',
          player: 'MARKET COMPARISON',
          signal: 'LIVE LINES',
        ),
      ],
    ),
  );
}

class _PreviewSport extends StatelessWidget {
  final String label;
  final bool selected;
  const _PreviewSport(this.label, this.selected);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? _gold.withValues(alpha: .16) : _fieldBackground,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: selected ? _gold : const Color(0xFF293640)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? _gold : _silver70,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _PreviewProvider extends StatelessWidget {
  final String provider;
  final String player;
  final String signal;
  const _PreviewProvider({
    required this.provider,
    required this.player,
    required this.signal,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: BoxDecoration(
      color: _fieldBackground,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF293640)),
    ),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Text(
            provider.substring(0, 1),
            style: const TextStyle(
              color: _gold,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                player,
                style: const TextStyle(color: _silver54, fontSize: 8),
              ),
            ],
          ),
        ),
        Text(
          signal,
          style: const TextStyle(
            color: Color(0xFF55D6A3),
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
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

class _PricingTierCard extends StatelessWidget {
  final String name;
  final String price;
  final String description;
  final List<String> features;
  final List<String> notIncluded;
  final bool featured;
  final ValueChanged<BuildContext>? onPressed;
  final ValueChanged<BuildContext>? onAnnualPressed;
  final String? buttonLabel;
  final String? annualPrice;

  const _PricingTierCard({
    required this.name,
    required this.price,
    required this.description,
    required this.features,
    this.notIncluded = const [],
    this.featured = false,
    this.onPressed,
    this.onAnnualPressed,
    this.buttonLabel,
    this.annualPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: featured
            ? _gold.withValues(alpha: 0.08)
            : _silver.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: featured
              ? _gold.withValues(alpha: 0.82)
              : _silver.withValues(alpha: 0.58),
          width: featured ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: _silver,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: featured ? _gold : _silver,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  featured ? 'GOLD ACCESS' : 'SILVER ACCESS',
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(width: 8),
              Text(
                price,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: featured ? _gold : _silver,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: const TextStyle(color: _silver70, fontSize: 12, height: 1.4),
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
                    color: featured ? _gold : _silver,
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
          if (notIncluded.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'PRO-ONLY FEATURES',
              style: TextStyle(
                color: _silver,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 7),
            for (final feature in notIncluded)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: _gold,
                      size: 15,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(
                          color: _silver70,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: featured
                ? FilledButton(
                    onPressed: onPressed == null
                        ? null
                        : () => onPressed!(context),
                    child: Text(buttonLabel ?? 'CHOOSE PRO'),
                  )
                : OutlinedButton(
                    onPressed: onPressed == null
                        ? null
                        : () => onPressed!(context),
                    child: Text(buttonLabel ?? 'CHOOSE CORE'),
                  ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onAnnualPressed == null
                ? null
                : () => onAnnualPressed!(context),
            child: Text(
              'CHOOSE ANNUAL • ${annualPrice ?? ''} • 7-DAY FREE TRIAL',
            ),
          ),
          const Center(
            child: Text(
              'Monthly plans start with a 3-day free trial',
              style: TextStyle(color: _silver60, fontSize: 10),
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
  final Future<void> Function(String section) onNavigate;

  const _Footer({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xB3000305),
        border: Border(top: BorderSide(color: Color(0xFF111619))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              for (final item in const [
                ('ABOUT', 'about'),
                ('TERMS', 'terms'),
                ('PRIVACY', 'privacy'),
                ('CONTACT', 'contact'),
              ])
                TextButton(
                  onPressed: () => onNavigate(item.$2),
                  child: Text(
                    item.$1,
                    style: const TextStyle(
                      color: _silver70,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const Row(
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
          // The one place the notice stays permanently visible: fine print
          // under the copyright line, where it can't cover any UI.
          const SizedBox(height: 5),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              kComplianceNotice,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _silver38,
                fontSize: 8.5,
                letterSpacing: 0.3,
                height: 1.4,
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
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _pageBackground),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B2B40), Color(0xFF07151F)],
                ),
              ),
            ),

            CustomPaint(painter: _MarketGridPainter()),
          ],
        );
      },
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
