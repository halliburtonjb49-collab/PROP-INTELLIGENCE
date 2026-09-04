import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

/// How long the board waits before it stops claiming to be loading.
///
/// Keeps customer navigation bounded while cached data and background retry
/// cover a temporarily cold or unavailable feed.
const Duration propFetchTimeout = Duration(seconds: 12);

/// Explains how a live-feed wait is progressing instead of showing a silent
/// skeleton indefinitely.
String loadProgressMessage(Duration elapsed) {
  if (elapsed.inSeconds < 4) return 'Loading live props\u2026';
  if (elapsed.inSeconds < 10) return 'Pulling the latest lines\u2026';
  if (elapsed.inSeconds < 18) {
    return 'Still working. The feed is slower than usual.';
  }
  return 'The feed has not answered. This will stop shortly and offer a retry.';
}

/// Converts technical feed failures into an actionable reader-facing message.
String describeLoadFailure(Object? error) {
  if (error is TimeoutException) {
    return 'The prop feed did not respond in time. It is usually back within '
        'a moment -- retry, and the board will reload.';
  }
  if (error is SocketException) {
    return 'No connection to the prop feed. Check your network and retry.';
  }
  return error?.toString() ?? 'The board could not be loaded.';
}

class PropLoadingSkeleton extends StatefulWidget {
  const PropLoadingSkeleton({super.key});

  @override
  State<PropLoadingSkeleton> createState() => _PropLoadingSkeletonState();
}

class _PropLoadingSkeletonState extends State<PropLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  static const _stages = <String>[
    'SYNCING LIVE MARKETS',
    'ANALYZING PLAYER DATA',
    'CALCULATING PI TRUST',
    'PREPARING TOP PROPS',
  ];

  final Stopwatch _elapsed = Stopwatch()..start();
  Timer? _ticker;
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (!WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _scanController.repeat();
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scanController.dispose();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stages[(_elapsed.elapsed.inSeconds ~/ 2) % _stages.length];
    return Semantics(
      liveRegion: true,
      label: 'Prop Intelligence is loading. $stage',
      child: Container(
        constraints: const BoxConstraints(minHeight: 410),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B2230), Color(0xFF071722), Color(0xFF040D14)],
            stops: [0, 0.56, 1],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.72)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: CustomPaint(
          painter: const _PiLoadingGridPainter(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 142,
                  height: 142,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF09131C),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.82),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.2),
                              blurRadius: 30,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(7),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/branding/Prop_Intelligence_Master_Logo.png',
                            width: 128,
                            height: 128,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Text(
                                    'PI',
                                    style: TextStyle(
                                      color: AppColors.goldHighlight,
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedBuilder(
                          animation: _scanController,
                          builder: (context, child) => Align(
                            alignment: Alignment(
                              0,
                              (_scanController.value * 2) - 1,
                            ),
                            child: child,
                          ),
                          child: Container(
                            width: 126,
                            height: 1.5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7D878),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0xFFF7D878),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'PROP INTELLIGENCE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF3F6F9),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'INITIALIZING PROP ENGINE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.goldHighlight,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _PiEngineChip(label: 'LIVE LINES'),
                    _PiEngineChip(label: 'MODEL DATA'),
                    _PiEngineChip(label: 'PI TRUST'),
                  ],
                ),
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      minHeight: 3,
                      color: AppColors.gold,
                      backgroundColor: AppColors.border,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Text(
                    stage,
                    key: ValueKey(stage),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB8C4CF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  loadProgressMessage(_elapsed.elapsed),
                  key: const ValueKey('prop-loading-progress'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FIND THE EDGE.',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PiEngineChip extends StatelessWidget {
  const _PiEngineChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFB9C4CF).withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFB9C4CF).withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.goldHighlight,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB8C4CF),
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _PiLoadingGridPainter extends CustomPainter {
  const _PiLoadingGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFB9C4CF).withValues(alpha: 0.055)
      ..strokeWidth = 1;
    const spacing = 38.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final accent = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(size.width * 0.76, 0),
      Offset(size.width * 0.58, size.height),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PropLoadError extends StatelessWidget {
  const PropLoadError({
    super.key,
    this.title = 'Unable to load props',
    required this.message,
    required this.onRetry,
    this.onSignIn,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.goldHighlight,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              userFacingLoadError(message, noun: 'live prop feed'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
            const SizedBox(height: 15),
            if (onSignIn != null)
              FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.login_rounded),
                label: const Text('SIGN IN AGAIN'),
              )
            else
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('RETRY'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.goldHighlight,
                  side: const BorderSide(color: AppColors.gold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
