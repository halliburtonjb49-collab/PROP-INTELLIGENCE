import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

/// How long the board waits before it stops claiming to be loading.
///
/// Generous on purpose: a cold backend genuinely takes seconds, while a feed
/// that never answers must eventually become a retryable error.
const Duration propFetchTimeout = Duration(seconds: 25);

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

class _PropLoadingSkeletonState extends State<PropLoadingSkeleton> {
  final Stopwatch _elapsed = Stopwatch()..start();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 650
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: columns * 2,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 220,
          ),
          itemBuilder: (context, index) => Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 16, width: 150, color: AppColors.border),
                const SizedBox(height: 14),
                Container(height: 10, width: 210, color: AppColors.border),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Container(height: 44, color: AppColors.border),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(height: 44, color: AppColors.border),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  loadProgressMessage(_elapsed.elapsed),
                  key: const ValueKey('prop-loading-progress'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
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
