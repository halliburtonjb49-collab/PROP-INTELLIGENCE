import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'layout/app_shell.dart';
import 'controllers/active_slip_controller.dart';
import 'models/prop_data.dart';
import 'models/saved_slip.dart';
import 'pages/analytics_page.dart';
import 'pages/line_movement_page.dart';
import 'pages/owner_operations_page.dart';
import 'pages/prop_chat_page.dart';
import 'pages/referee_tracker_page.dart';
import 'screens/prop_builder_performance_screen.dart';
import 'screens/prop_builder_screen.dart';
import 'screens/strikeout_pro_gold_screen.dart';
import 'screens/game_markets_screen.dart';
import 'screens/login_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/password_recovery_screen.dart';
import 'models/slip_selection.dart';
import 'services/api_service.dart';
import 'services/app_sound_service.dart';
import 'services/onesignal_service.dart';
import 'services/auth_manager.dart';
import 'services/developer_mode_service.dart';
import 'services/prop_watchlist_service.dart';
import 'services/player_image_resolver.dart';
import 'services/prop_chat_service.dart';
import 'services/recommendation_access.dart';
import 'services/slip_manager.dart';
import 'services/scoreboard_service.dart';
import 'services/scoreboard_watchlist_service.dart';
import 'services/supabase_service.dart';
import 'services/user_facing_error.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_colors.dart' as app_colors;
import 'theme/app_theme.dart';
import 'pages/intelligence_lab_page.dart';
import 'widgets/active_slip_panel.dart';
import 'widgets/auth_account_panel.dart';
import 'widgets/current_slip_panel.dart';
import 'widgets/ev_scanner_card.dart';
import 'widgets/onboarding_dialog.dart';
import 'widgets/scoreboard_view.dart';
import 'widgets/selected_prop_slip.dart';
import 'widgets/slip_history_panel.dart';

final Stopwatch _startupStopwatch = Stopwatch()..start();
final ValueNotifier<int> boardPropCountNotifier = ValueNotifier<int>(0);
final ValueNotifier<int> boardRefreshRequestNotifier = ValueNotifier<int>(0);

const String kSupabaseProjectUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);
const String kSupabaseAnonPublicApiKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

void _startupLog(String message) {
  debugPrint('[startup +${_startupStopwatch.elapsedMilliseconds}ms] $message');
}

Future<void> _configureDesktopWindow() async {
  if (kIsWeb) {
    return;
  }

  // On Windows we rely on native runner window styles to preserve
  // standard caption buttons (minimize/maximize/close).
  if (Platform.isWindows) {
    _startupLog('Skipping windowManager on Windows to keep native title bar');
    return;
  }

  if (!(Platform.isMacOS || Platform.isLinux)) {
    return;
  }

  try {
    _startupLog('windowManager initialization start');
    await windowManager.ensureInitialized();
    _startupLog('windowManager initialized');
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(1024, 680),
      center: true,
      title: 'PROP INTELLIGENCE',
      backgroundColor: Color(0xFF050A0F),
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      _startupLog('window ready-to-show callback start');
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      }
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(true);
      await windowManager.setMinimizable(true);
      await windowManager.setSize(const Size(1280, 800));
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
      _startupLog('window shown/focused with normal OS frame controls');
    });
  } catch (error) {
    _startupLog('windowManager setup failed: $error');
  }
}

Future<void> main() async {
  _startupLog('main() entered');
  WidgetsFlutterBinding.ensureInitialized();
  _startupLog('WidgetsFlutterBinding initialized');

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _startupLog('FlutterError: ${details.exceptionAsString()}');
  };

  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stackTrace) {
        _startupLog('Unhandled async error: $error');
        return true;
      };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF2A0D10),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'UI ERROR\n${details.exceptionAsString()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  };

  await _configureDesktopWindow();
  await OneSignalService.instance.initialize();

  SupabaseService.configure(
    url: kSupabaseProjectUrl,
    anonKey: kSupabaseAnonPublicApiKey,
  );

  unawaited(AppSoundService.instance.load());
  runApp(const PropIntelligenceApp());
  _startupLog('runApp() called');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _startupLog('first frame rendered');
    unawaited(() async {
      try {
        await SupabaseService.initialize();
        AuthManager.instance.attach();
        await PropChatService().startGlobalMonitoring();
        await PropWatchlistService().syncLocalAndCloudWatchlist().timeout(
          const Duration(seconds: 5),
        );
      } catch (error) {
        _startupLog('Cloud startup skipped: $error');
      }
    }());
  });
}

const double leftSidebarWidth = 245;
const double rightSidebarWidth = 300;
const double cardHeight = 510;
const double avatarSize = 96;
const double cardGap = 12;

enum AppPage {
  board,
  gameMarkets,
  propBuilder,
  watchlist,
  pastSlipHistory,
  builderPerformance,
  strikeoutProGold,
  evScanner,
  searchPlayers,
  scoreboard,
  scoreboardWatchlist,
  propAlerts,
  analytics,
  lineMovement,
  dataAdmin,
  ownerOperations,
  intelligenceLab,
  refereeTracker,
  propChat,
}

@visibleForTesting
SubscriptionTier? requiredTierForPage(AppPage page) => switch (page) {
  AppPage.propBuilder ||
  AppPage.gameMarkets ||
  AppPage.watchlist ||
  AppPage.analytics ||
  AppPage.lineMovement ||
  AppPage.pastSlipHistory => SubscriptionTier.core,
  AppPage.propChat => SubscriptionTier.core,
  AppPage.builderPerformance ||
  AppPage.strikeoutProGold ||
  AppPage.evScanner ||
  AppPage.scoreboardWatchlist ||
  AppPage.propAlerts ||
  AppPage.intelligenceLab ||
  AppPage.refereeTracker => SubscriptionTier.edge,
  _ => null,
};

@visibleForTesting
bool canAccessOwnerOperations(String role) =>
    role.trim().toLowerCase() == 'owner';

@visibleForTesting
SubscriptionTier displayedTierForBadge({
  required SubscriptionTier requiredTier,
  required bool hasEdgeAccess,
  bool hasProUpgrade = false,
}) {
  // Most badges describe the minimum tier required by the feature. A small
  // group of pages has both a Core experience and a materially enhanced Pro
  // experience, so Pro members should see which version they are using.
  if (hasProUpgrade && hasEdgeAccess) {
    return SubscriptionTier.edge;
  }
  return requiredTier;
}

@visibleForTesting
List<PropData> boardIntelligenceScope({
  required List<SlipSelection> selections,
  required List<PropData> visibleProps,
  PropData? focusedProp,
}) {
  final selectedProps = <String, PropData>{
    for (final selection in selections) selection.prop.id: selection.prop,
  }.values.toList(growable: false);
  if (selectedProps.isNotEmpty) return selectedProps;
  if (focusedProp != null) return <PropData>[focusedProp];
  return visibleProps;
}

class AppColors {
  static const background = Color(0xFF080D15);
  static const leftSidebar = Color(0xFF0C131D);
  static const rightSidebar = Color(0xFF0A111A);
  static const panel = Color(0xFF111822);
  static const border = Color(0xFF29323E);
  static const gold = Color(0xFFA59256);
  static const goldBright = Color(0xFFFFE89D);
  static const text = Color(0xFFE5E2E2);
  static const muted = Color(0xFF868080);
}

final GlobalKey<NavigatorState> _oneSignalNavigatorKey =
    GlobalKey<NavigatorState>();

class PropIntelligenceApp extends StatefulWidget {
  const PropIntelligenceApp({super.key});

  @override
  State<PropIntelligenceApp> createState() => _PropIntelligenceAppState();
}

class _PropIntelligenceAppState extends State<PropIntelligenceApp> {
  String? _oneSignalUserId;
  String? _oneSignalSubscriptionId;

  @override
  void initState() {
    super.initState();
    AuthManager.instance.sessionState.addListener(_syncOneSignalIdentity);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OneSignalService.instance.observeRegistration((subscriptionId) {
        _oneSignalSubscriptionId = subscriptionId;
        unawaited(_registerPropChatPushSubscription());
      });
      _syncOneSignalIdentity();
      if (!kIsWeb) {
        unawaited(OneSignalService.instance.requestPermission());
      }
    });
  }

  Future<void> _registerPropChatPushSubscription() async {
    final subscriptionId = _oneSignalSubscriptionId;
    if (subscriptionId == null ||
        subscriptionId.isEmpty ||
        !AuthManager.instance.sessionState.value.authenticated) {
      return;
    }
    try {
      await PropChatService().registerPushSubscription(
        deviceKey: subscriptionId,
        endpoint: subscriptionId,
        platform: switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          _ => 'unknown',
        },
      );
    } catch (error) {
      debugPrint('Push subscription registration deferred: $error');
    }
  }

  void _syncOneSignalIdentity() {
    final session = AuthManager.instance.sessionState.value;
    final userId = session.authenticated ? session.userId : null;
    if (userId == _oneSignalUserId) return;
    _oneSignalUserId = userId;
    if (userId == null) {
      OneSignalService.instance.logout();
    } else {
      OneSignalService.instance.login(userId);
      final email = session.email;
      if (email != null && email.isNotEmpty) {
        OneSignalService.instance.setEmail(email);
      }
      OneSignalService.instance.setTag(
        'subscription_tier',
        session.subscriptionTier.name,
      );
      unawaited(_registerPropChatPushSubscription());
    }
  }

  @override
  void dispose() {
    AuthManager.instance.sessionState.removeListener(_syncOneSignalIdentity);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _oneSignalNavigatorKey,
      title: 'PROP INTELLIGENCE',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: AppTheme.theme,
      home: const PropIntelligenceShell(),
    );
  }
}

class PropIntelligenceShell extends StatelessWidget {
  const PropIntelligenceShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.isConfigured) {
      return _buildDashboardShell();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: DeveloperModeService.unlocked,
      builder: (context, devUnlocked, _) {
        return ValueListenableBuilder<AuthSessionState>(
          valueListenable: AuthManager.instance.sessionState,
          builder: (context, state, _) {
            if (!state.ready) {
              return const Scaffold(
                backgroundColor: Color(0xFF050C13),
                body: Center(child: CircularProgressIndicator()),
              );
            }

            return ValueListenableBuilder<bool>(
              valueListenable: AuthManager.instance.passwordRecoveryRequested,
              builder: (context, recoveringPassword, _) {
                if (recoveringPassword) {
                  return const PasswordRecoveryScreen();
                }
                if (!state.authenticated && !devUnlocked) {
                  return const CorporateLoginScreen();
                }
                if (state.requiresPaidPlan && !devUnlocked) {
                  return const SubscriptionRequiredScreen();
                }
                return _buildDashboardShell(authState: state);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDashboardShell({AuthSessionState? authState}) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C13),
      body: Column(
        children: [
          if (authState?.isAccessPreviewActive == true)
            _OwnerAccessPreviewBanner(
              tier: authState!.effectiveSubscriptionTier,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final accessKey =
                    authState?.effectiveSubscriptionTier.name ?? 'public';
                if (constraints.maxWidth >= 700) {
                  return DesktopDashboard(
                    key: ValueKey('desktop-access-$accessKey'),
                  );
                }

                return MobileDashboardViewport(
                  key: ValueKey('mobile-access-$accessKey'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerAccessPreviewBanner extends StatelessWidget {
  const _OwnerAccessPreviewBanner({required this.tier});

  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFC400),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => AuthManager.instance.setOwnerAccessPreview(null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.science_outlined, size: 17),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'OWNER ACCESS PREVIEW: '
                    '${tier == SubscriptionTier.free ? 'NO PLAN' : tier.name.toUpperCase()} — '
                    'UI ACCESS ONLY, BILLING UNCHANGED',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF050A0F),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'EXIT',
                  style: TextStyle(
                    color: Color(0xFF050A0F),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    decoration: TextDecoration.underline,
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

class DesktopDashboard extends StatefulWidget {
  const DesktopDashboard({super.key});

  @override
  State<DesktopDashboard> createState() => _DesktopDashboardState();
}

class _DesktopDashboardState extends State<DesktopDashboard> {
  final ApiService _apiService = ApiService();
  final ActiveSlipController _activeSlipController = ActiveSlipController();
  final List<SlipSelection> _slipSelections = [];
  bool _isSavingSlip = false;
  AppPage _selectedPage = AppPage.board;
  String _selectedBoardSport = 'ALL';
  bool _chatFloating = false;
  bool _chatMinimized = false;
  bool _chatBubbleVisible = true;
  final ValueNotifier<Offset> _chatOffset = ValueNotifier(
    const Offset(360, 110),
  );
  final ValueNotifier<Size> _chatSize = ValueNotifier(const Size(520, 620));

  @override
  void initState() {
    super.initState();
    PropChatService.latestNotification.addListener(_showChatNotification);
    ScoreboardWatchlistService.instance.latestAlert.addListener(
      _showScoreboardWatchAlert,
    );
    unawaited(
      ScoreboardWatchlistService.instance.start(
        ScoreboardService(baseUrl: ApiService.baseUrl),
      ),
    );
    _startupLog('active slip load start');
    unawaited(
      _activeSlipController.load().then(
        (_) async {
          final loadedCount = _activeSlipController.legCount;
          if (loadedCount > 0) {
            await _activeSlipController.clear();
            _startupLog(
              'active slip startup reset cleared $loadedCount persisted legs',
            );
          }
          _startupLog(
            'active slip load complete (${_activeSlipController.legCount} legs)',
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          _startupLog('active slip load failed: $error');
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AuthManager.instance.sessionState.value.authenticated) {
        unawaited(ProductOnboarding.showIfNeeded(context));
        unawaited(_loadLockedSlipCount());
      }
    });
  }

  void _showChatNotification() {
    final notification = PropChatService.latestNotification.value;
    if (!mounted || notification == null || _selectedPage == AppPage.propChat) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notification.isDirect
              ? 'Direct message from @${notification.username}: '
                    '${notification.body}'
              : '@${notification.username} mentioned you in '
                    '#${notification.roomId}: ${notification.body}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: 'OPEN',
          onPressed: () =>
              _switchToPage(AppPage.propChat, source: 'chat-notification'),
        ),
      ),
    );
  }

  void _showScoreboardWatchAlert() {
    final alert = ScoreboardWatchlistService.instance.latestAlert.value;
    if (!mounted || alert == null) return;
    unawaited(
      AppSoundService.instance.play(
        alert.type == ScoreboardWatchAlertType.finalResult
            ? AppSoundEvent.success
            : AppSoundEvent.warning,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(alert.message, maxLines: 2),
        action: SnackBarAction(
          label: 'WATCHLIST',
          onPressed: () => _switchToPage(
            AppPage.scoreboardWatchlist,
            source: 'scoreboard-watch-alert',
          ),
        ),
      ),
    );
  }

  /// So the SLIP WATCHER sidebar badge is correct immediately on load,
  /// not just after the user visits that page (which is what actually
  /// keeps it updated afterward, via SlipHistoryPanel).
  Future<void> _loadLockedSlipCount() async {
    try {
      final activeSlips = await _apiService.fetchSlips(status: 'active');
      if (!mounted) return;
      SlipManager.reserveActiveSlips(activeSlips);
      _activeSlipController.setLockedSlipCount(activeSlips.length);
    } catch (_) {
      // Non-critical - SlipHistoryPanel will populate it once visited.
    }
  }

  @override
  void dispose() {
    PropChatService.latestNotification.removeListener(_showChatNotification);
    ScoreboardWatchlistService.instance.latestAlert.removeListener(
      _showScoreboardWatchAlert,
    );
    ScoreboardWatchlistService.instance.stop();
    _activeSlipController.dispose();
    _chatOffset.dispose();
    _chatSize.dispose();
    super.dispose();
  }

  void _switchToPage(AppPage page, {String source = 'ui'}) {
    final dismissMobileChat =
        MediaQuery.sizeOf(context).width < 1000 && _chatFloating;
    final requiredTier = _requiredTier(page);
    final session = AuthManager.instance.sessionState.value;
    if (page == AppPage.ownerOperations &&
        !canAccessOwnerOperations(session.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner access is required.')),
      );
      return;
    }
    final allowed =
        !session.authenticated ||
        requiredTier == null ||
        (requiredTier == SubscriptionTier.core && session.hasCoreAccess) ||
        (requiredTier == SubscriptionTier.edge && session.hasEdgeAccess);
    if (!allowed) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const BrandedPaywallModalSheet(),
      );
      return;
    }
    if (_selectedPage == page && !dismissMobileChat) {
      return;
    }
    unawaited(AppSoundService.instance.play(AppSoundEvent.navigation));
    final timer = Stopwatch()..start();
    setState(() {
      if (dismissMobileChat) {
        _chatFloating = false;
        _chatMinimized = false;
      }
      _selectedPage = page;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupLog(
        'page switch ($source) -> ${page.name} in ${timer.elapsedMilliseconds}ms',
      );
    });
  }

  SubscriptionTier? _requiredTier(AppPage page) => requiredTierForPage(page);

  void _selectBoardSport(String sport) {
    setState(() {
      _selectedBoardSport = sport;
    });
    _switchToPage(AppPage.board, source: 'sport-filter');
  }

  int _mainPageIndex() {
    switch (_selectedPage) {
      case AppPage.board:
      case AppPage.gameMarkets:
      case AppPage.evScanner:
      case AppPage.searchPlayers:
      case AppPage.scoreboard:
      case AppPage.scoreboardWatchlist:
      case AppPage.propAlerts:
      case AppPage.analytics:
      case AppPage.lineMovement:
      case AppPage.dataAdmin:
      case AppPage.ownerOperations:
      case AppPage.intelligenceLab:
      case AppPage.refereeTracker:
      case AppPage.propChat:
        return 0;
      case AppPage.propBuilder:
        return 1;
      case AppPage.watchlist:
        return 2;
      case AppPage.builderPerformance:
        return 3;
      case AppPage.strikeoutProGold:
        return 4;
      case AppPage.pastSlipHistory:
        return 5;
    }
  }

  Widget _buildMainContent() {
    final hasProAccess = canShowSystemRecommendation(
      hasEdgeAccess: AuthManager.instance.sessionState.value.hasEdgeAccess,
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF06131E), Color(0xFF030A10)],
        ),
      ),
      child: IndexedStack(
        index: _mainPageIndex(),
        children: [
          MainDashboard(
            selections: _slipSelections,
            onSelect: _toggleSelection,
            onAddGameMarket: _addGameMarketLeg,
            onRemoveLabSelection: _removeLabSelection,
            onClearLabSelections: _clearCurrentSlip,
            onPropsRefreshed: _refreshActiveSlipProps,
            sportFilter: _selectedBoardSport,
            selectedPage: _selectedPage,
            onSelectPage: (page) =>
                _switchToPage(page, source: 'board-toolbar'),
            onFloatChat: _floatChat,
            onShowChatBubble: _showChatBubble,
            isChatBubbleVisible: _chatBubbleVisible,
          ),
          PropBuilderScreen(
            activeSlipController: _activeSlipController,
            isManualSportsMode: true,
            hasProAccess: hasProAccess,
            initialSelectedSports: [
              _selectedBoardSport == 'ALL' ? 'WNBA' : _selectedBoardSport,
            ],
          ),
          SlipHistoryPanel(
            activeSlipController: _activeSlipController,
            hasProAccess: hasProAccess,
            isActive: _selectedPage == AppPage.watchlist,
          ),
          const PropBuilderPerformanceScreen(),
          StrikeoutProGoldScreen(
            onSelect: _toggleSelection,
            onPropsRefreshed: _refreshActiveSlipProps,
            onPropsExpired: _removeExpiredStrikeoutProps,
          ),
          SlipHistoryPanel(
            activeSlipController: _activeSlipController,
            mode: SlipHistoryMode.history,
            hasProAccess: hasProAccess,
            isActive: _selectedPage == AppPage.pastSlipHistory,
          ),
        ],
      ),
    );
  }

  void _floatChat() {
    setState(() {
      _chatFloating = true;
      _chatMinimized = false;
      _chatBubbleVisible = true;
      if (_selectedPage == AppPage.propChat) {
        _selectedPage = AppPage.board;
      }
    });
  }

  void _dockChat() {
    setState(() {
      _chatFloating = false;
      _chatMinimized = false;
      _selectedPage = AppPage.propChat;
    });
  }

  void _showChatBubble() {
    setState(() {
      _chatFloating = false;
      _chatMinimized = false;
      _chatBubbleVisible = true;
      // The launcher is intentionally hidden on the full PROP CHAT page.
      // Return to the board so restoring it produces an immediate, visible
      // result instead of appearing to do nothing.
      _selectedPage = AppPage.board;
    });
  }

  void _closeFloatingChat() {
    if (!_chatFloating && !_chatMinimized && !_chatBubbleVisible) return;
    setState(() {
      _chatFloating = false;
      _chatMinimized = false;
      _chatBubbleVisible = false;
    });
  }

  Widget _buildFloatingChat(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 1000;
    final availableWidth = (constraints.maxWidth - (isMobile ? 32 : 24)).clamp(
      1.0,
      isMobile ? 520.0 : 760.0,
    );
    final availableHeight = isMobile
        ? (constraints.maxHeight * .68).clamp(320.0, 620.0)
        : (constraints.maxHeight - 24).clamp(1.0, 820.0);
    final minimumWidth = availableWidth.clamp(1.0, 360.0);
    final minimumHeight = availableHeight.clamp(1.0, 320.0);
    final maximumWidth = availableWidth;
    final maximumHeight = availableHeight;
    return ValueListenableBuilder<Offset>(
      valueListenable: _chatOffset,
      builder: (context, offset, _) => ValueListenableBuilder<Size>(
        valueListenable: _chatSize,
        builder: (context, panelSize, _) {
          if (_chatMinimized) {
            const bubbleSize = 58.0;
            final left = offset.dx.clamp(
              12.0,
              (constraints.maxWidth - bubbleSize - 12).clamp(
                12.0,
                double.infinity,
              ),
            );
            final top = offset.dy.clamp(
              12.0,
              (constraints.maxHeight - bubbleSize - 12).clamp(
                12.0,
                double.infinity,
              ),
            );
            return Positioned(
              left: left,
              top: top,
              width: bubbleSize,
              height: bubbleSize,
              child: GestureDetector(
                key: const ValueKey('floating-prop-chat-bubble'),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => _chatOffset.value += details.delta,
                onTap: () => setState(() => _chatMinimized = false),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(
                      child: Material(
                        elevation: 18,
                        color: app_colors.AppColors.gold,
                        shape: CircleBorder(
                          side: BorderSide(color: Colors.white, width: 1.5),
                        ),
                        child: Icon(
                          Icons.forum_rounded,
                          color: Color(0xFF06111B),
                          size: 27,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: _ChatBubbleCloseButton(
                        onPressed: _closeFloatingChat,
                      ),
                    ),
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: _ChatUnreadBadge(),
                    ),
                  ],
                ),
              ),
            );
          }
          final width = panelSize.width.clamp(minimumWidth, maximumWidth);
          final height = panelSize.height.clamp(minimumHeight, maximumHeight);
          final left = offset.dx.clamp(12.0, constraints.maxWidth - width - 12);
          final minimumTop = isMobile ? 76.0 : 12.0;
          final bottomClearance = isMobile ? 86.0 : 12.0;
          final maximumTop = (constraints.maxHeight - height - bottomClearance)
              .clamp(minimumTop, double.infinity);
          final top = offset.dy.clamp(minimumTop, maximumTop);
          return Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: RepaintBoundary(
              child: Material(
                key: const ValueKey('floating-prop-chat'),
                elevation: 22,
                color: app_colors.AppColors.background,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(
                    color: app_colors.AppColors.gold,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      key: const ValueKey('floating-prop-chat-drag-handle'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        _chatOffset.value += details.delta;
                      },
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.only(left: 14, right: 4),
                        color: app_colors.AppColors.sidebar,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.drag_indicator_rounded,
                              color: app_colors.AppColors.gold,
                            ),
                            const SizedBox(width: 7),
                            const Expanded(
                              child: Text(
                                'PROP CHAT · FLOATING',
                                style: TextStyle(
                                  color: app_colors.AppColors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: _chatMinimized
                                  ? 'Restore chat'
                                  : 'Minimize chat',
                              onPressed: () => setState(
                                () => _chatMinimized = !_chatMinimized,
                              ),
                              icon: Icon(
                                _chatMinimized
                                    ? Icons.open_in_full_rounded
                                    : Icons.minimize_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Dock PROP CHAT',
                              onPressed: _dockChat,
                              icon: const Icon(Icons.call_to_action_outlined),
                            ),
                            IconButton(
                              key: const ValueKey('close-floating-prop-chat'),
                              tooltip: 'Close floating chat',
                              onPressed: _closeFloatingChat,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: PropChatPage(
                        isFloating: true,
                        sharedAnalysis: {
                          'kind': 'slip',
                          'title':
                              '${_activeSlipController.legCount}-leg active slip',
                          'legs': _activeSlipController.legs,
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: GestureDetector(
                        key: const ValueKey('floating-prop-chat-resize-handle'),
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          _chatSize.value = Size(
                            (_chatSize.value.width + details.delta.dx).clamp(
                              minimumWidth,
                              maximumWidth,
                            ),
                            (_chatSize.value.height + details.delta.dy).clamp(
                              minimumHeight,
                              maximumHeight,
                            ),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 20,
                            color: app_colors.AppColors.gold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatBubble(BoxConstraints constraints) {
    const size = 58.0;
    return ValueListenableBuilder<Offset>(
      valueListenable: _chatOffset,
      builder: (context, offset, _) {
        final defaultLeft = constraints.maxWidth - size - 18;
        final defaultTop = constraints.maxHeight - size - 90;
        final left = (offset.dx == 360 ? defaultLeft : offset.dx).clamp(
          12.0,
          (constraints.maxWidth - size - 12).clamp(12.0, double.infinity),
        );
        final top = (offset.dy == 110 ? defaultTop : offset.dy).clamp(
          12.0,
          (constraints.maxHeight - size - 12).clamp(12.0, double.infinity),
        );
        return Positioned(
          left: left,
          top: top,
          width: size,
          height: size,
          child: Stack(
            key: const ValueKey('prop-chat-bubble-launcher'),
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    _chatOffset.value = Offset(left, top) + details.delta;
                  },
                  onTap: _floatChat,
                  child: const Material(
                    elevation: 18,
                    color: app_colors.AppColors.gold,
                    shape: CircleBorder(
                      side: BorderSide(color: Colors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.forum_rounded,
                        color: Color(0xFF06111B),
                        size: 27,
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: -2,
                bottom: -2,
                child: _ChatUnreadBadge(),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: _ChatBubbleCloseButton(onPressed: _closeFloatingChat),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeftSidebar() {
    return AnimatedBuilder(
      animation: _activeSlipController,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B1A28), Color(0xFF06111B)],
            ),
          ),
          child: LeftSidebar(
            selectedPage: _selectedPage,
            selectedSport: _selectedBoardSport,
            lockedSlipCount: _activeSlipController.lockedSlipCount,
            onSelectPage: (page) {
              setState(() {
                if (page != AppPage.board) {
                  _selectedBoardSport = 'ALL';
                }
              });
              _switchToPage(page, source: 'left-sidebar');
            },
            onSelectSport: _selectBoardSport,
          ),
        );
      },
    );
  }

  Widget _buildTopNavigation() {
    final hasProAccess = AuthManager.instance.sessionState.value.hasEdgeAccess;
    return TopNavigation(
      selectedPage: _selectedPage,
      soundService: AppSoundService.instance,
      accentColor: hasProAccess
          ? app_colors.AppColors.gold
          : const Color(0xFFC8CED6),
      onTabSelected: (page) {
        _switchToPage(page, source: 'top-nav');
      },
    );
  }

  Widget _buildRightPanel() {
    return AnimatedBuilder(
      animation: _activeSlipController,
      builder: (context, _) {
        return Container(
          color: app_colors.AppColors.sidebar,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            children: [
              const AuthAccountPanel(),
              const SizedBox(height: 10),
              Expanded(
                child: SelectedPropSlip(
                  props: _selectedPropModels(),
                  onRemove: (prop) {
                    unawaited(_activeSlipController.removeLeg(prop.id));
                  },
                  onClear: _clearCurrentSlip,
                  onBuildTicket: _openLockSlipDialog,
                  isBuilding: _isSavingSlip,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int _selectedPropAmericanOdds(Object? rawValue) {
    final value = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '') ?? -110;
    if (value.abs() >= 100) return value.round();
    if (value > 1 && value < 2) return (-100 / (value - 1)).round();
    if (value >= 2) return ((value - 1) * 100).round();
    return -110;
  }

  List<SelectedProp> _selectedPropModels() {
    return _activeSlipController.legs
        .map((leg) {
          final side = (leg['side'] ?? leg['pick'] ?? 'OVER').toString();
          final selectedOdds = leg['current_odds'] ?? leg['odds'];
          final bestRaw = side.toUpperCase() == 'UNDER'
              ? leg['under_odds'] ?? selectedOdds
              : leg['over_odds'] ?? selectedOdds;
          return SelectedProp(
            id: leg['prop_id']?.toString() ?? leg['id']?.toString() ?? '',
            playerName: leg['player']?.toString() ?? 'Unknown Player',
            team: leg['matchup']?.toString() ?? '',
            position: leg['sport']?.toString() ?? '',
            propType: leg['market']?.toString() ?? 'PLAYER PROP',
            gameTime:
                leg['display_time']?.toString() ??
                leg['game_time']?.toString() ??
                '',
            sportsbook:
                leg['prop_site']?.toString() ??
                leg['sportsbook']?.toString() ??
                '',
            imageUrl:
                leg['player_image']?.toString() ??
                leg['image_url']?.toString() ??
                leg['image_path']?.toString() ??
                '',
            line:
                ((leg['current_line'] as num?) ?? (leg['line'] as num?))
                    ?.toDouble() ??
                0,
            selectedSide: side,
            edge: (leg['edge'] as num?)?.toDouble() ?? 0,
            hitRate: (leg['confidence'] as num?)?.round() ?? 0,
            bestOdds: _selectedPropAmericanOdds(bestRaw),
            liveOdds: _selectedPropAmericanOdds(selectedOdds),
          );
        })
        .toList(growable: false);
  }

  void _toggleSelection(PropData prop, PickSide side) {
    if (SlipManager.isLockedInActiveSlip(prop.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'That prop is already locked in an active ticket. Complete or unlock the ticket before selecting it again.',
          ),
        ),
      );
      return;
    }
    unawaited(AppSoundService.instance.play(AppSoundEvent.selection));
    final selection = SlipSelection(prop: prop, side: side);

    setState(() {
      final existingIndex = _slipSelections.indexWhere(
        (item) => item.prop.id == prop.id,
      );

      if (existingIndex >= 0) {
        final existing = _slipSelections[existingIndex];
        if (existing.side == side) {
          _slipSelections.removeAt(existingIndex);
          unawaited(_activeSlipController.removeLeg(existing.prop.id));
          SlipManager.removePropById(existing.prop.id);
        } else {
          _slipSelections[existingIndex] = selection;
          unawaited(
            _activeSlipController.updateLeg(_selectionToLeg(selection)),
          );
          SlipManager.upsertProp(_selectionToLeg(selection));
        }
      } else {
        if (_isMixedSiteAttempt(selection)) {
          _showMixedSiteNotAllowedMessage();
          return;
        }
        _slipSelections.add(selection);
        unawaited(_activeSlipController.addLegs([_selectionToLeg(selection)]));
        SlipManager.upsertProp(_selectionToLeg(selection));
      }
    });
  }

  Future<int> _addGameMarketLeg(Map<String, dynamic> leg) async {
    final added = await _activeSlipController.addLegs([leg]);
    if (mounted) setState(() {});
    return added;
  }

  Future<void> _removeLabSelection(String propId) async {
    await _activeSlipController.removeLeg(propId);
    SlipManager.removePropById(propId);
    if (!mounted) return;
    setState(() {
      _slipSelections.removeWhere((selection) => selection.prop.id == propId);
    });
  }

  bool _isMixedSiteAttempt(SlipSelection incoming) {
    if (_activeSlipController.legs.isEmpty) {
      return false;
    }
    final activeSite = _normalizedSiteFromLeg(_activeSlipController.legs.first);
    final incomingSite = _normalizedSite(incoming.prop.sportsbook);
    if (activeSite.isEmpty || incomingSite.isEmpty) {
      return false;
    }
    return activeSite != incomingSite;
  }

  String _normalizedSiteFromLeg(Map<String, dynamic> leg) {
    for (final key in const ['prop_site', 'sportsbook', 'site']) {
      final value = leg[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return _normalizedSite(value);
    }
    return '';
  }

  String _normalizedSite(String value) {
    final normalized = value.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (normalized.contains('PRIZEPICKS')) {
      return 'PRIZEPICKS';
    }
    if (normalized.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    if (normalized.contains('SLEEPER')) {
      return 'SLEEPER';
    }
    if (normalized.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (normalized.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    if (normalized.contains('DRAFTPICKS')) {
      return 'DRAFTPICKS';
    }
    if (normalized.contains('BETMGM')) return 'BETMGM';
    if (normalized.contains('CAESARS')) return 'CAESARS';
    if (normalized.contains('BET365')) return 'BET365';
    if (normalized.contains('ESPNBET')) return 'ESPNBET';
    return normalized;
  }

  Future<void> _refreshActiveSlipProps(List<PropData> props) async {
    await _activeSlipController.refreshFromProps(props);
    if (!mounted || _slipSelections.isEmpty) return;
    final latestById = {for (final prop in props) prop.id: prop};
    PropData? semanticMatch(PropData selected) {
      final player = selected.player.trim().toLowerCase();
      final market = selected.market.trim().toLowerCase();
      final site = _normalizedSite(selected.sportsbook);
      final event = selected.eventId.trim().toLowerCase();
      for (final prop in props) {
        if (prop.player.trim().toLowerCase() != player ||
            prop.market.trim().toLowerCase() != market ||
            _normalizedSite(prop.sportsbook) != site) {
          continue;
        }
        if (event.isEmpty || prop.eventId.trim().toLowerCase() == event) {
          return prop;
        }
      }
      return null;
    }

    var changed = false;
    final refreshed = _slipSelections
        .map((selection) {
          final latest =
              latestById[selection.prop.id] ?? semanticMatch(selection.prop);
          if (latest == null) return selection;
          changed = true;
          return SlipSelection(prop: latest, side: selection.side);
        })
        .toList(growable: false);
    if (!changed) return;
    setState(() {
      _slipSelections
        ..clear()
        ..addAll(refreshed);
    });
    for (final selection in refreshed) {
      SlipManager.upsertProp(_selectionToLeg(selection));
    }
  }

  Future<void> _removeExpiredStrikeoutProps(Set<String> propIds) async {
    if (propIds.isEmpty) return;
    for (final propId in propIds) {
      await _activeSlipController.removeLeg(propId);
      SlipManager.removePropById(propId);
    }
    if (!mounted) return;
    setState(() {
      _slipSelections.removeWhere(
        (selection) => propIds.contains(selection.prop.id),
      );
    });
  }

  void _showMixedSiteNotAllowedMessage() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFE9A713),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        content: Text(
          'Not allowed: picks must be from the same prop site.',
          style: TextStyle(
            color: Color(0xFF050A0F),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Map<String, dynamic> _selectionToLeg(SlipSelection selection) {
    final prop = selection.prop;
    final selectedOdds = selection.odds;
    return {
      'prop_id': prop.id,
      'id': prop.id,
      'event_id': prop.eventId,
      'api_sports_game_id': prop.apiSportsGameId,
      'player_id': prop.playerId,
      'custom_label': prop.customLabel,
      'manual_note': prop.manualNote,
      'game_start_time': prop.gameStartTime,
      'player': prop.player,
      'sport': prop.sport,
      'matchup': prop.matchup,
      'prop_site': prop.sportsbook,
      'sportsbook': prop.sportsbook,
      'market': prop.market,
      'line': prop.line,
      'current_line': prop.line,
      'side': selection.sideLabel,
      'pick': selection.sideLabel,
      'recommended_side': prop.recommendedSide,
      'recommendedSide': prop.recommendedSide,
      'pick_text': prop.pickText,
      'pickText': prop.pickText,
      'recommendation_available': prop.recommendationAvailable,
      'recommendation_unavailable_reason': prop.recommendationUnavailableReason,
      'odds': selectedOdds,
      'current_odds': selectedOdds,
      'over_odds': prop.overOdds,
      'under_odds': prop.underOdds,
      'multiplier': prop.multiplier,
      'win_probability': prop.winProbability,
      'edge': prop.edge,
      'confidence': prop.confidence,
      'projection': prop.projection,
      'projection_source': prop.projectionSource,
      'projection_model_version': prop.projectionModelVersion,
      'projection_sample_size': prop.projectionSampleSize,
      'projection_volatility': prop.projectionVolatility,
      'projection_calibrated': prop.projectionCalibrated,
      'historical_hit_rate': prop.historicalHitRate,
      'fair_probability': prop.fairProbability,
      'model_probability': prop.modelProbability,
      'market_probability': prop.marketProbability,
      'push_probability': prop.pushProbability,
      'loss_probability': prop.lossProbability,
      'fair_decimal_odds': prop.fairDecimalOdds,
      'probability_method': prop.probabilityMethod,
      'probability_market_weight': prop.probabilityMarketWeight,
      'probability_uncertainty': prop.probabilityUncertainty,
      'probability_calibration_adjustment':
          prop.probabilityCalibrationAdjustment,
      'probability_calibration_sample_size':
          prop.probabilityCalibrationSampleSize,
      'ev_percentage': prop.evPercentage,
      'injury_status': prop.injuryStatus,
      'lineup_status': prop.lineupStatus,
      'recommendation_edge': prop.recommendationEdge,
      'opening_line': prop.openingLine,
      'line_moved_at_utc': prop.lineMovedAtUtc,
      'source_player_id': prop.sourcePlayerId,
      'canonical_player_id': prop.canonicalPlayerId,
      'player_identity_confidence': prop.playerIdentityConfidence,
      'fatigue_multiplier': prop.fatigueMultiplier,
      'rest_days': prop.restDays,
      'pace_multiplier': prop.paceMultiplier,
      'opponent_defense_multiplier': prop.opponentDefenseMultiplier,
      'usage_multiplier': prop.usageMultiplier,
      'home_away_multiplier': prop.homeAwayMultiplier,
      'matchup_multiplier': prop.matchupMultiplier,
      'matchup_context': prop.matchupContext,
      'officiating_adjustment': prop.officiatingAdjustment,
      'display_time': prop.localGameTimeDisplay,
      'game_time': prop.gameTime,
      'player_image': prop.imagePath,
      'image_url': prop.imagePath,
      'headshot': prop.imagePath,
      'photo_url': prop.imagePath,
      'player_photo': prop.imagePath,
      'avatar': prop.imagePath,
      'image_path': prop.imagePath,
    };
  }

  List<SlipSelection> _activeSlipSelections() {
    return _activeSlipController.legs.map((rawLeg) {
      final leg = Map<String, dynamic>.from(rawLeg);
      final propId = leg['prop_id']?.toString() ?? leg['id']?.toString() ?? '';
      final sideText =
          (leg['side']?.toString() ?? leg['pick']?.toString() ?? 'OVER')
              .toUpperCase();
      final side = sideText == 'UNDER' ? PickSide.under : PickSide.over;
      final oddsValue = ((leg['current_odds'] as num?) ?? (leg['odds'] as num?))
          ?.toDouble();

      final prop = PropData(
        id: propId,
        eventId: leg['event_id']?.toString() ?? '',
        apiSportsGameId: leg['api_sports_game_id']?.toString() ?? '',
        playerId: leg['player_id']?.toString() ?? '',
        player: leg['player']?.toString() ?? 'Unknown Player',
        sport: leg['sport']?.toString() ?? '',
        matchup: leg['matchup']?.toString() ?? '',
        sportsbook:
            leg['prop_site']?.toString() ?? leg['sportsbook']?.toString() ?? '',
        market: leg['market']?.toString() ?? '',
        gameStartTime: leg['game_start_time']?.toString() ?? '',
        line:
            ((leg['current_line'] as num?) ?? (leg['line'] as num?))
                ?.toDouble() ??
            0,
        pick: sideText,
        recommendedSide:
            leg['recommended_side']?.toString() ??
            leg['recommendedSide']?.toString() ??
            (sideText == 'UNDER' ? 'Under' : 'Over'),
        pickText:
            leg['pick_text']?.toString() ??
            leg['pickText']?.toString() ??
            '${sideText == 'UNDER' ? 'Under' : 'Over'} ${((leg['current_line'] as num?) ?? (leg['line'] as num?) ?? 0).toString()}',
        recommendationAvailable: leg['recommendation_available'] == true,
        recommendationUnavailableReason:
            leg['recommendation_unavailable_reason']?.toString() ?? '',
        edge: (leg['edge'] as num?)?.toDouble() ?? 0,
        recommendationEdge:
            (leg['recommendation_edge'] as num?)?.toDouble() ?? 0,
        confidence: (leg['confidence'] as num?)?.toInt() ?? 0,
        projection: (leg['projection'] as num?)?.toDouble(),
        projectionSource: leg['projection_source']?.toString() ?? '',
        projectionModelVersion:
            leg['projection_model_version']?.toString() ?? '',
        projectionSampleSize:
            (leg['projection_sample_size'] as num?)?.toInt() ?? 0,
        projectionVolatility: (leg['projection_volatility'] as num?)
            ?.toDouble(),
        projectionCalibrated: leg['projection_calibrated'] == true,
        historicalHitRate: (leg['historical_hit_rate'] as num?)?.toInt(),
        fairProbability: (leg['fair_probability'] as num?)?.toDouble(),
        modelProbability: (leg['model_probability'] as num?)?.toDouble(),
        marketProbability: (leg['market_probability'] as num?)?.toDouble(),
        pushProbability: (leg['push_probability'] as num?)?.toDouble() ?? 0,
        lossProbability: (leg['loss_probability'] as num?)?.toDouble(),
        fairDecimalOdds: (leg['fair_decimal_odds'] as num?)?.toDouble(),
        probabilityMethod: leg['probability_method']?.toString() ?? '',
        probabilityMarketWeight:
            (leg['probability_market_weight'] as num?)?.toDouble() ?? 0,
        probabilityUncertainty: (leg['probability_uncertainty'] as num?)
            ?.toDouble(),
        probabilityCalibrationAdjustment:
            (leg['probability_calibration_adjustment'] as num?)?.toDouble() ??
            0,
        probabilityCalibrationSampleSize:
            (leg['probability_calibration_sample_size'] as num?)?.toInt() ?? 0,
        evPercentage: (leg['ev_percentage'] as num?)?.toDouble(),
        injuryStatus: leg['injury_status']?.toString() ?? 'unknown',
        lineupStatus: leg['lineup_status']?.toString() ?? 'unknown',
        openingLine: (leg['opening_line'] as num?)?.toDouble() ?? 0,
        lineMovedAtUtc: leg['line_moved_at_utc']?.toString() ?? '',
        sourcePlayerId: leg['source_player_id']?.toString() ?? '',
        canonicalPlayerId: leg['canonical_player_id']?.toString() ?? '',
        playerIdentityConfidence:
            (leg['player_identity_confidence'] as num?)?.toDouble() ?? 0,
        fatigueMultiplier: (leg['fatigue_multiplier'] as num?)?.toDouble(),
        restDays: (leg['rest_days'] as num?)?.toDouble(),
        paceMultiplier: (leg['pace_multiplier'] as num?)?.toDouble(),
        opponentDefenseMultiplier: (leg['opponent_defense_multiplier'] as num?)
            ?.toDouble(),
        usageMultiplier: (leg['usage_multiplier'] as num?)?.toDouble(),
        homeAwayMultiplier: (leg['home_away_multiplier'] as num?)?.toDouble(),
        matchupMultiplier: (leg['matchup_multiplier'] as num?)?.toDouble(),
        matchupContext: leg['matchup_context']?.toString() ?? '',
        officiatingAdjustment: (leg['officiating_adjustment'] as num?)
            ?.toDouble(),
        imagePath:
            leg['image_path']?.toString() ?? leg['imagePath']?.toString() ?? '',
        customLabel: leg['custom_label']?.toString() ?? '',
        manualNote: leg['manual_note']?.toString() ?? '',
        multiplier: (leg['multiplier'] as num?)?.toDouble(),
        winProbability: (leg['win_probability'] as num?)?.toDouble(),
        overOdds: side == PickSide.over ? oddsValue : null,
        underOdds: side == PickSide.under ? oddsValue : null,
      );

      return SlipSelection(
        prop: prop,
        side: side,
        customSideLabel: sideText,
        customOdds: oddsValue,
      );
    }).toList();
  }

  Future<void> _openLockSlipDialog() async {
    final selections = _activeSlipSelections();
    if (selections.isEmpty || _isSavingSlip) {
      return;
    }

    final stake = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return LockSlipDialog(selections: selections, apiService: _apiService);
      },
    );

    if (stake == null || !mounted) {
      return;
    }

    await _saveSlip(stake, selections);
  }

  Future<void> _saveSlip(double stake, List<SlipSelection> selections) async {
    if (selections.isEmpty || _isSavingSlip) {
      return;
    }

    setState(() {
      _isSavingSlip = true;
    });

    final temporaryId =
        'pending-${DateTime.now().microsecondsSinceEpoch.toString()}';
    final optimisticSlip = SavedSlip(
      id: temporaryId,
      status: 'active',
      stake: stake,
      potentialPayout: stake,
      createdAt: DateTime.now(),
      legs: selections
          .map(
            (selection) => SavedSlipLeg(
              propId: selection.prop.id,
              eventId: selection.prop.eventId,
              player: selection.prop.player,
              imagePath: selection.prop.imagePath,
              sport: selection.prop.sport,
              matchup: selection.prop.matchup,
              sportsbook: selection.prop.sportsbook,
              market: selection.prop.market,
              line: selection.prop.line,
              entryLine: selection.prop.line,
              side: selection.sideLabel,
              odds: selection.odds,
              customLabel: selection.prop.customLabel,
              manualNote: selection.prop.manualNote,
              gameStatus: selection.prop.gameStatus.isEmpty
                  ? 'scheduled'
                  : selection.prop.gameStatus,
              gameStartTime: selection.prop.gameStartTime,
            ),
          )
          .toList(),
    );
    _activeSlipController.addOptimisticLockedSlip(optimisticSlip);
    await _activeSlipController.clear();
    if (!mounted) return;
    setState(() => _slipSelections.clear());
    _switchToPage(AppPage.watchlist, source: 'slip-locked');

    try {
      final response = await _apiService.saveSlip(
        selections: selections,
        stake: stake,
      );
      if (!mounted) {
        return;
      }
      _activeSlipController.replaceOptimisticLockedSlip(
        temporaryId,
        SavedSlip.fromJson(response),
      );

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF8CFFB2),
            content: Text(
              'Slip locked and moved to Slip Watcher!',
              style: TextStyle(
                color: Color(0xFF050A0F),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      _activeSlipController.removeOptimisticLockedSlip(temporaryId);
      await _activeSlipController.addLegs(
        selections.map(_selectionToLeg).toList(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFFF8A80),
          content: Text(
            'Failed to lock slip: $error',
            style: const TextStyle(
              color: Color(0xFF050A0F),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSlip = false;
        });
      }
    }
  }

  Future<void> _clearCurrentSlip() async {
    await _activeSlipController.clear();
    SlipManager.clearAllSlips();
    if (!mounted) {
      return;
    }
    setState(() {
      _slipSelections.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasProAccess = AuthManager.instance.sessionState.value.hasEdgeAccess;
    final membershipAccent = hasProAccess
        ? app_colors.AppColors.gold
        : const Color(0xFFC8CED6);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          AnimatedBuilder(
            animation: _activeSlipController,
            builder: (context, _) => AppShell(
              leftSidebar: _buildLeftSidebar(),
              topNavigation: _buildTopNavigation(),
              content: _buildMainContent(),
              rightSidebar: _buildRightPanel(),
              activeSlipCount: _activeSlipController.legCount,
              watchedSlipCount: _activeSlipController.lockedSlipCount,
              mobileSelectedIndex: switch (_selectedPage) {
                AppPage.board => 0,
                AppPage.gameMarkets => 1,
                AppPage.watchlist => 2,
                _ => 3,
              },
              onMobileWatchSlip: () =>
                  _switchToPage(AppPage.watchlist, source: 'mobile-bottom-nav'),
              onMobileChat: _floatChat,
              onMobileDismissOverlay: _closeFloatingChat,
              accentColor: membershipAccent,
            ),
          ),
          if (_chatFloating) _buildFloatingChat(constraints),
          if (_chatBubbleVisible &&
              !_chatFloating &&
              _selectedPage != AppPage.propChat)
            _buildChatBubble(constraints),
        ],
      ),
    );
  }
}

class _ChatBubbleCloseButton extends StatelessWidget {
  const _ChatBubbleCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Material(
        elevation: 6,
        color: const Color(0xFF101D28),
        shape: const CircleBorder(side: BorderSide(color: Color(0xFFC8CED6))),
        child: IconButton(
          key: const ValueKey('close-prop-chat-bubble'),
          tooltip: 'Remove chat bubble',
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          iconSize: 15,
          icon: const Icon(Icons.close_rounded, color: Color(0xFFC8CED6)),
        ),
      ),
    );
  }
}

class _ChatUnreadBadge extends StatelessWidget {
  const _ChatUnreadBadge();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PropChatService.unreadCount,
      builder: (context, unread, _) {
        if (unread <= 0) return const SizedBox.shrink();
        return Semantics(
          label: '$unread unread chat notifications',
          child: Container(
            key: const ValueKey('chat-unread-badge'),
            constraints: const BoxConstraints(minWidth: 21, minHeight: 21),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: app_colors.AppColors.gold,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF06111B), width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                color: Color(0xFF06111B),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}

class LeftSidebar extends StatefulWidget {
  final AppPage selectedPage;
  final String selectedSport;
  final int lockedSlipCount;
  final ValueChanged<AppPage>? onSelectPage;
  final ValueChanged<String>? onSelectSport;

  const LeftSidebar({
    super.key,
    required this.selectedPage,
    required this.selectedSport,
    required this.lockedSlipCount,
    this.onSelectPage,
    this.onSelectSport,
  });

  @override
  State<LeftSidebar> createState() => _LeftSidebarState();
}

class _LeftSidebarState extends State<LeftSidebar> {
  final ScrollController _sidebarScrollController = ScrollController();

  String _sportEmoji(String sport) {
    switch (sport) {
      case 'MLB':
        return '⚾';
      case 'NFL':
        return '🏈';
      case 'NBA':
        return '🏀';
      case 'WNBA':
        return '🏀';
      case 'PGA':
        return '⛳';
      case 'TENNIS':
        return '🎾';
      case 'SOCCER':
        return '⚽';
      case 'UFC':
        return '🥊';
      default:
        return '•';
    }
  }

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const sports = [
      'MLB',
      'NFL',
      'NBA',
      'WNBA',
      'PGA',
      'TENNIS',
      'SOCCER',
      'UFC',
    ];

    return Container(
      color: AppColors.leftSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SidebarHeader(
              onRefresh: () => boardRefreshRequestNotifier.value++,
              onOpenAlerts: () => widget.onSelectPage?.call(AppPage.propAlerts),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Scrollbar(
              controller: _sidebarScrollController,
              thumbVisibility: true,
              interactive: true,
              child: ListView(
                controller: _sidebarScrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                children: [
                  const _SidebarSectionLabel('WORKSPACE'),
                  const SizedBox(height: 7),
                  SidebarButton(
                    label: 'GAME MARKETS',
                    leadingIcons: const [Icons.sports_rounded],
                    leadingIconColors: const [AppColors.gold],
                    selected: widget.selectedPage == AppPage.gameMarkets,
                    requiredTier: SubscriptionTier.core,
                    showGoldBar: true,
                    onTap: () => widget.onSelectPage?.call(AppPage.gameMarkets),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'SCORE WATCH',
                    leadingIcons: const [Icons.notifications_active_rounded],
                    leadingIconColors: const [AppColors.gold],
                    selected:
                        widget.selectedPage == AppPage.scoreboardWatchlist,
                    requiredTier: SubscriptionTier.edge,
                    showGoldBar: true,
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.scoreboardWatchlist),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'THE LAB',
                    leadingIcons: const [Icons.science_outlined],
                    leadingIconColors: const [AppColors.gold],
                    selected: widget.selectedPage == AppPage.intelligenceLab,
                    requiredTier: SubscriptionTier.edge,
                    showGoldBar: true,
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.intelligenceLab),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'REFEREE\nTRACKER',
                    leadingIcons: const [Icons.sports_outlined],
                    leadingIconColors: const [AppColors.gold],
                    selected: widget.selectedPage == AppPage.refereeTracker,
                    requiredTier: SubscriptionTier.edge,
                    showGoldBar: true,
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.refereeTracker),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'PROP BUILDER',
                    leadingIcons: const [Icons.category_outlined],
                    selected: widget.selectedPage == AppPage.propBuilder,
                    requiredTier: SubscriptionTier.core,
                    showGoldBar: true,
                    onTap: () => widget.onSelectPage?.call(AppPage.propBuilder),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'BUILD\nPERFORM',
                    leadingIcons: const [Icons.grid_view_rounded],
                    selected: widget.selectedPage == AppPage.builderPerformance,
                    requiredTier: SubscriptionTier.edge,
                    showGoldBar: true,
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.builderPerformance),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'SLIP WATCHER',
                    badge: '${widget.lockedSlipCount}',
                    leadingIcons: const [Icons.receipt_long_rounded],
                    leadingIconColors: const [AppColors.gold],
                    selected: widget.selectedPage == AppPage.watchlist,
                    requiredTier: SubscriptionTier.core,
                    hasProUpgrade: true,
                    showGoldBar: true,
                    onTap: () => widget.onSelectPage?.call(AppPage.watchlist),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'PAST SLIP\nHISTORY',
                    leadingIcons: const [Icons.history_rounded],
                    leadingIconColors: const [AppColors.gold],
                    selected: widget.selectedPage == AppPage.pastSlipHistory,
                    requiredTier: SubscriptionTier.core,
                    hasProUpgrade: true,
                    showGoldBar: true,
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.pastSlipHistory),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'EV SCANNER',
                    selected: widget.selectedPage == AppPage.evScanner,
                    requiredTier: SubscriptionTier.edge,
                    showGoldBar: true,
                    leadingIcons: const [Icons.auto_graph],
                    leadingIconColors: const [Color(0xFF36B9FF)],
                    onTap: () => widget.onSelectPage?.call(AppPage.evScanner),
                  ),
                  if (MediaQuery.sizeOf(context).width < 700) ...[
                    const SizedBox(height: 6),
                    ValueListenableBuilder<int>(
                      valueListenable: PropChatService.unreadCount,
                      builder: (context, unread, _) => SidebarButton(
                        key: const ValueKey('mobile-sidebar-prop-chat'),
                        label: 'PROP CHAT',
                        badge: unread > 0 ? '$unread' : null,
                        selected: widget.selectedPage == AppPage.propChat,
                        showGoldBar: true,
                        leadingIcons: const [Icons.forum_rounded],
                        leadingIconColors: const [AppColors.gold],
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.propChat),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const _SidebarSectionLabel('SPORTS'),
                  const SizedBox(height: 7),
                  ...sports.map(
                    (sport) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: SidebarButton(
                        label: sport,
                        leadingEmojis: [_sportEmoji(sport)],
                        selected:
                            widget.selectedPage == AppPage.board &&
                            widget.selectedSport == sport,
                        onTap: () => widget.onSelectSport?.call(sport),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _SidebarSectionLabel('SPECIALTY'),
                  const SizedBox(height: 7),
                  SidebarButton(
                    label: 'STRIKEOUT\nPRO GOLD',
                    selected: widget.selectedPage == AppPage.strikeoutProGold,
                    requiredTier: SubscriptionTier.edge,
                    leadingIcons: const [Icons.sports_baseball_rounded],
                    leadingIconColors: const [AppColors.gold],
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.strikeoutProGold),
                  ),
                  if (AuthManager.instance.sessionState.value.isOwner) ...[
                    const SizedBox(height: 18),
                    const _SidebarSectionLabel('OWNER'),
                    const SizedBox(height: 7),
                    SidebarButton(
                      key: const ValueKey('owner-operations-sidebar-button'),
                      label: 'OPERATIONS\nCENTER',
                      selected: widget.selectedPage == AppPage.ownerOperations,
                      showGoldBar: true,
                      leadingIcons: const [Icons.admin_panel_settings_outlined],
                      leadingIconColors: const [AppColors.gold],
                      onTap: () =>
                          widget.onSelectPage?.call(AppPage.ownerOperations),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: ValueListenableBuilder<int>(
              valueListenable: boardPropCountNotifier,
              builder: (context, count, _) => Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF07131D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL PROPS',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Color(0xFF36B9FF),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.onRefresh, required this.onOpenAlerts});

  final VoidCallback onRefresh;
  final VoidCallback onOpenAlerts;

  Widget _action({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF091722),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: app_colors.AppColors.border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: app_colors.AppColors.gold, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFF07131D),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: app_colors.AppColors.borderGold),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/branding/prop_intelligence_icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE RESEARCH',
                    style: TextStyle(
                      color: AppColors.goldBright,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'WORKSPACE',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            const Icon(Icons.circle, color: app_colors.AppColors.blue, size: 7),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'SYSTEM ONLINE',
                style: TextStyle(
                  color: app_colors.AppColors.blue,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            _action(
              tooltip: 'Refresh props',
              icon: Icons.refresh_rounded,
              onTap: onRefresh,
            ),
            const SizedBox(width: 6),
            _action(
              tooltip: 'View prop alerts',
              icon: Icons.notifications_none_rounded,
              onTap: onOpenAlerts,
            ),
          ],
        ),
      ],
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  final String label;

  const _SidebarSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Text(
        label,
        style: const TextStyle(
          color: app_colors.AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.35,
        ),
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({
    required this.tier,
    this.compact = false,
    this.hasProUpgrade = false,
  });

  final SubscriptionTier tier;
  final bool compact;
  final bool hasProUpgrade;

  @override
  Widget build(BuildContext context) {
    final accountHasProAccess =
        AuthManager.instance.sessionState.value.hasEdgeAccess;
    final displayedTier = displayedTierForBadge(
      requiredTier: tier,
      hasEdgeAccess: accountHasProAccess,
      hasProUpgrade: hasProUpgrade,
    );
    final isCore = displayedTier == SubscriptionTier.core;
    final background = isCore
        ? const Color(0xFFC8CED6)
        : app_colors.AppColors.gold;
    const foreground = Color(0xFF06111B);

    return Container(
      key: ValueKey('tier-badge-${displayedTier.name}'),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: isCore
            ? Border.all(color: const Color(0xFFF1F4F7), width: .7)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(Icons.workspace_premium, size: 12, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            isCore ? 'CORE' : 'PRO',
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 7 : 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class SidebarButton extends StatelessWidget {
  final String label;
  final bool selected;
  final SubscriptionTier? requiredTier;
  final bool hasProUpgrade;
  final bool showGoldBar;
  final String? badge;
  final List<IconData>? leadingIcons;
  final List<Color>? leadingIconColors;
  final List<String>? leadingEmojis;
  final List<Color>? leadingEmojiGradient;
  final VoidCallback? onTap;

  const SidebarButton({
    super.key,
    required this.label,
    this.selected = false,
    this.requiredTier,
    this.hasProUpgrade = false,
    this.showGoldBar = false,
    this.badge,
    this.leadingIcons,
    this.leadingIconColors,
    this.leadingEmojis,
    this.leadingEmojiGradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActiveWatchlist = label.toUpperCase() == 'SLIP WATCHER';
    final watchlistHasActiveSlips =
        isActiveWatchlist && (int.tryParse((badge ?? '0').trim()) ?? 0) > 0;
    final textColor = selected || watchlistHasActiveSlips
        ? const Color(0xFFFFC400)
        : Colors.white;
    final textWeight = selected || watchlistHasActiveSlips
        ? FontWeight.w900
        : FontWeight.w700;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              unawaited(AppSoundService.instance.play(AppSoundEvent.button));
              onTap!();
            },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? app_colors.AppColors.gold.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? app_colors.AppColors.gold.withValues(alpha: 0.52)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (showGoldBar) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: selected
                      ? app_colors.AppColors.gold
                      : app_colors.AppColors.gold.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (leadingEmojis != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: leadingEmojis!
                    .map(
                      (emoji) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors:
                                  leadingEmojiGradient ??
                                  const [Color(0xFF203246), Color(0xFF314A60)],
                            ),
                            border: Border.all(color: const Color(0x73FFC72C)),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(width: 8),
            ] else if (leadingIcons != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(leadingIcons!.length, (index) {
                  final icon = leadingIcons![index];
                  final color =
                      leadingIconColors != null &&
                          index < leadingIconColors!.length
                      ? leadingIconColors![index]
                      : textColor;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(icon, size: 14, color: color),
                  );
                }),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: label.contains('\n')
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 2,
                        softWrap: false,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 10.5,
                          height: 1.15,
                          fontWeight: textWeight,
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  : Text(
                      label,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10.5,
                        height: 1.15,
                        fontWeight: textWeight,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC400),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Color(0xFF07131F),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (badge == null && requiredTier != null)
              _TierBadge(tier: requiredTier!, hasProUpgrade: hasProUpgrade),
          ],
        ),
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  final List<SlipSelection> selections;
  final void Function(PropData prop, PickSide side) onSelect;
  final Future<int> Function(Map<String, dynamic> leg) onAddGameMarket;
  final Future<void> Function(String propId) onRemoveLabSelection;
  final Future<void> Function() onClearLabSelections;
  final Future<void> Function(List<PropData> props) onPropsRefreshed;
  final String sportFilter;
  final AppPage selectedPage;
  final ValueChanged<AppPage>? onSelectPage;
  final VoidCallback? onFloatChat;
  final VoidCallback? onShowChatBubble;
  final bool isChatBubbleVisible;

  const MainDashboard({
    super.key,
    required this.selections,
    required this.onSelect,
    required this.onAddGameMarket,
    required this.onRemoveLabSelection,
    required this.onClearLabSelections,
    required this.onPropsRefreshed,
    required this.sportFilter,
    required this.selectedPage,
    this.onSelectPage,
    this.onFloatChat,
    this.onShowChatBubble,
    this.isChatBubbleVisible = true,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _boardVerticalController = ScrollController();
  final ScrollController _bookHorizontalController = ScrollController();
  final ScrollController _categoryHorizontalController = ScrollController();
  final ScrollController _sportHorizontalController = ScrollController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String _selectedSite = 'ALL';
  String _selectedSiteSport = '';
  String _selectedCategory = 'ALL';
  final String _selectedSide = 'All';
  final String _selectedTier = 'All';
  int _minConfidence = 0;
  String _sortBy = 'time';
  DateTime? _lastUpdated;
  List<PropData> _latestProps = const [];
  List<PropData> _siteInventoryProps = const [];
  Map<String, int> _siteSportCounts = const {};
  Map<String, Map<String, int>> _siteSportCategoryCounts = const {};
  Map<String, int> _categoryCounts = const {};
  List<PropData> _evScannerProps = const [];
  final TextEditingController _evSearchController = TextEditingController();
  String _evBook = 'ALL';
  String _evSort = 'EV';
  double _evMinimum = 0;
  PropData? _focusedProp;
  bool _isEvScannerLoading = false;
  String? _evScannerError;
  List<PropAlertData> _propAlerts = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPropAlerts());
    if (widget.selectedPage == AppPage.evScanner) {
      unawaited(_loadEvScannerProps());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _boardVerticalController.dispose();
    _bookHorizontalController.dispose();
    _categoryHorizontalController.dispose();
    _sportHorizontalController.dispose();
    _searchController.dispose();
    _evSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sportFilter != widget.sportFilter && mounted) {
      setState(() {
        _selectedCategory = 'ALL';
        _focusedProp = null;
        _latestProps = const [];
        _categoryCounts = const {};
        _lastUpdated = null;
      });
      if (widget.selectedPage == AppPage.evScanner) {
        unawaited(_loadEvScannerProps());
      }
    }
    if (oldWidget.selectedPage != widget.selectedPage &&
        widget.selectedPage == AppPage.evScanner) {
      unawaited(_loadEvScannerProps());
    }
  }

  Future<void> _loadEvScannerProps() async {
    if (_isEvScannerLoading) {
      return;
    }

    setState(() {
      _isEvScannerLoading = true;
      _evScannerError = null;
    });

    try {
      final props = await _apiService.fetchPositiveEvProps(
        minEv: 0.0,
        sport: widget.sportFilter,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _evScannerProps = props;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _evScannerError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isEvScannerLoading = false;
        });
      }
    }
  }

  PickSide _evSide(PropData prop) {
    final signal = '${prop.recommendedSide} ${prop.pick} ${prop.pickText}'
        .toLowerCase();
    if (signal.contains('under') || signal.contains('less')) {
      return PickSide.under;
    }
    if (prop.projection != null && prop.projection! < prop.line) {
      return PickSide.under;
    }
    return PickSide.over;
  }

  List<String> get _evBooks {
    final books =
        _evScannerProps
            .map((prop) => prop.sportsbook.trim().toUpperCase())
            .where((book) => book.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['ALL', ...books];
  }

  List<PropData> get _visibleEvProps {
    final query = _evSearchController.text.trim().toLowerCase();
    final props = _evScannerProps.where((prop) {
      final ev = prop.evPercentage ?? 0;
      final matchesBook =
          _evBook == 'ALL' || prop.sportsbook.trim().toUpperCase() == _evBook;
      final matchesQuery =
          query.isEmpty ||
          '${prop.player} ${prop.market} ${prop.sport} ${prop.sportsbook}'
              .toLowerCase()
              .contains(query);
      return ev >= _evMinimum && matchesBook && matchesQuery;
    }).toList();
    props.sort(
      (a, b) => switch (_evSort) {
        'PROBABILITY' => (b.fairProbability ?? 0).compareTo(
          a.fairProbability ?? 0,
        ),
        'ODDS' => (b.overOdds ?? -10000).compareTo(a.overOdds ?? -10000),
        _ => (b.evPercentage ?? 0).compareTo(a.evPercentage ?? 0),
      },
    );
    return props;
  }

  void _showEvDetails(PropData prop) {
    final probability = prop.fairProbability ?? 0;
    final fairDecimal =
        prop.fairDecimalOdds ?? (probability > 0 ? 1 / probability : 0);
    final side = _evSide(prop);
    final availableOdds = side == PickSide.over
        ? prop.overOdds
        : prop.underOdds;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: app_colors.AppColors.panel,
        title: Text('${prop.player} • ${_propMarket(prop)}'),
        content: SizedBox(
          width: 430,
          child: Text(
            'Sportsbook: ${prop.sportsbook}\n'
            'Recommended side: ${side.name.toUpperCase()} ${prop.line.toStringAsFixed(1)}\n'
            'Available odds: ${(availableOdds ?? -110).round()}\n'
            'Model probability: ${((prop.modelProbability ?? probability) * 100).toStringAsFixed(1)}%\n'
            'Sharp no-vig probability: ${prop.marketProbability == null ? '--' : '${(prop.marketProbability! * 100).toStringAsFixed(1)}%'}\n'
            'Blended fair probability: ${(probability * 100).toStringAsFixed(1)}%\n'
            'Push probability: ${(prop.pushProbability * 100).toStringAsFixed(1)}%\n'
            'Estimated fair decimal price: ${fairDecimal == 0 ? '--' : fairDecimal.toStringAsFixed(2)}\n'
            'Expected value: ${(prop.evPercentage ?? 0) >= 0 ? '+' : ''}${(prop.evPercentage ?? 0).toStringAsFixed(1)}%\n'
            'Method: ${prop.probabilityMethod.isEmpty ? 'calibrated model' : prop.probabilityMethod}\n'
            'Model version: ${prop.projectionModelVersion.isEmpty ? 'not available' : prop.projectionModelVersion}\n'
            'Sample size: ${prop.projectionSampleSize} games\n'
            'Data freshness: ${prop.freshnessLabel}\n'
            'Source: ${prop.sourceProvider.isEmpty ? prop.sportsbook : prop.sourceProvider}\n'
            'Market blend weight: ${(prop.probabilityMarketWeight * 100).toStringAsFixed(0)}%\n'
            'Out-of-sample calibration: ${prop.probabilityCalibrationSampleSize == 0 ? 'pending' : '${prop.probabilityCalibrationAdjustment >= 0 ? '+' : ''}${(prop.probabilityCalibrationAdjustment * 100).toStringAsFixed(1)}% from ${prop.probabilityCalibrationSampleSize} graded picks'}\n'
            'Probability uncertainty: ${prop.probabilityUncertainty == null ? '--' : '±${(prop.probabilityUncertainty! * 100).toStringAsFixed(1)}%'}\n\n'
            'Positive EV is a long-run estimate, not a guarantee. Confirm the current line and price before adding the prop.',
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onSelect(prop, _evSide(prop));
            },
            child: const Text('ADD TO SLIP'),
          ),
        ],
      ),
    );
  }

  Widget _buildEvScanner() {
    if (_isEvScannerLoading && _evScannerProps.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }
    if (_evScannerError != null && _evScannerProps.isEmpty) {
      return Center(
        child: OutlinedButton.icon(
          onPressed: _loadEvScannerProps,
          icon: const Icon(Icons.refresh),
          label: const Text('RETRY EV FEED'),
        ),
      );
    }
    final visible = _visibleEvProps;
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _loadEvScannerProps,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EV SCANNER',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Find mispriced props, compare fair probability, and move qualified value into Active Slip.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isEvScannerLoading ? null : _loadEvScannerProps,
                icon: const Icon(Icons.refresh),
                label: const Text('REFRESH ODDS'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _evSearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Player, market, sport, or site',
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _evBooks.contains(_evBook) ? _evBook : 'ALL',
                items: _evBooks
                    .map(
                      (book) =>
                          DropdownMenuItem(value: book, child: Text(book)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _evBook = value ?? 'ALL'),
              ),
              DropdownButton<String>(
                value: _evSort,
                items: const [
                  DropdownMenuItem(value: 'EV', child: Text('Highest EV')),
                  DropdownMenuItem(
                    value: 'PROBABILITY',
                    child: Text('Highest Fair Probability'),
                  ),
                  DropdownMenuItem(value: 'ODDS', child: Text('Best Odds')),
                ],
                onChanged: (value) => setState(() => _evSort = value ?? 'EV'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _evMinimum = 0;
                  _evBook = 'ALL';
                  _evSort = 'EV';
                  _evSearchController.clear();
                }),
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('RESET'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'MINIMUM EV: +${_evMinimum.toStringAsFixed(1)}%  •  ${visible.length} MATCHES',
          ),
          Slider(
            value: _evMinimum,
            min: 0,
            max: 20,
            divisions: 40,
            label: '+${_evMinimum.toStringAsFixed(1)}%',
            onChanged: (value) => setState(() => _evMinimum = value),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(
                child: Text('No props match the current EV filters.'),
              ),
            )
          else
            ...visible.map((prop) {
              final market = _propMarket(prop);
              return PositiveEvScannerCard(
                player: prop.player,
                propType: market.isEmpty ? prop.market : market,
                lineValue: prop.line,
                slowBookmaker: prop.sportsbook,
                slowBookOdds:
                    ((_evSide(prop) == PickSide.over
                                ? prop.overOdds
                                : prop.underOdds) ??
                            -110)
                        .round(),
                evPercentage: prop.evPercentage ?? 0,
                fairProbability: (prop.fairProbability ?? 0) * 100,
                onInspect: () => _showEvDetails(prop),
                onAdd: () => widget.onSelect(prop, _evSide(prop)),
              );
            }),
        ],
      ),
    );
  }

  void _handlePropsLoaded(
    List<PropData> props,
    int propCount,
    int facetTotal,
    Map<String, int> categoryCounts,
  ) {
    if (!mounted) {
      return;
    }
    if (props.isNotEmpty) {
      final first = props.first;
      debugPrint(
        'FIRST PROP: id=${first.id}, player=${first.player}, sport=${first.sport}, imagePath=${first.imagePath}',
      );
    }
    setState(() {
      _latestProps = props;
      _categoryCounts = categoryCounts;
      if (_selectedSite != 'ALL' && _selectedCategory == 'ALL') {
        _siteInventoryProps = props;
        if (_selectedSiteSport.isEmpty) {
          final normalizedSportCounts = <String, int>{};
          for (final entry in _apiService.lastSportCounts.entries) {
            final sport = _normalizeSport(entry.key);
            normalizedSportCounts[sport] =
                (normalizedSportCounts[sport] ?? 0) + entry.value;
          }
          final normalizedCategoryCounts = <String, Map<String, int>>{};
          for (final sportEntry
              in _apiService.lastSportCategoryCounts.entries) {
            final sport = _normalizeSport(sportEntry.key);
            final target = normalizedCategoryCounts.putIfAbsent(
              sport,
              () => <String, int>{},
            );
            for (final categoryEntry in sportEntry.value.entries) {
              target[categoryEntry.key] =
                  (target[categoryEntry.key] ?? 0) + categoryEntry.value;
            }
          }
          _siteSportCounts = normalizedSportCounts;
          _siteSportCategoryCounts = normalizedCategoryCounts;
        }
        final sports = _availableSiteSports;
        if (sports.isNotEmpty && !sports.contains(_selectedSiteSport)) {
          _selectedSiteSport = sports.first;
        }
      }
      _lastUpdated = DateTime.now();
    });
    boardPropCountNotifier.value = propCount;
    unawaited(widget.onPropsRefreshed(props));
    unawaited(_loadPropAlerts(fallbackProps: props));
  }

  PropAlertData _parsePropAlert(Map<String, dynamic> value) {
    final edgeRaw = value['edge'];
    final edge = edgeRaw is num
        ? edgeRaw.toInt()
        : int.tryParse('$edgeRaw') ?? 0;
    return PropAlertData(
      sport: value['sport']?.toString() ?? 'ALL',
      title: value['title']?.toString() ?? 'Prop Alert',
      message: value['message']?.toString() ?? '',
      edge: edge,
      book: value['book']?.toString() ?? 'All Books',
      time: value['time']?.toString() ?? 'now',
    );
  }

  List<PropAlertData> _fallbackPropAlertsFromProps(List<PropData> props) {
    if (props.isEmpty) {
      return const [
        PropAlertData(
          sport: 'ALL',
          title: 'No Props Loaded',
          message:
              'No props loaded yet. Alerts will appear as soon as data sync completes.',
          edge: 0,
          book: 'All Books',
          time: 'now',
        ),
      ];
    }

    final sortedByEdge = [...props]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final top = sortedByEdge.first;
    final bySport = <String, int>{};
    for (final prop in props) {
      final sport = _normalizeSport(prop.sport);
      bySport[sport] = (bySport[sport] ?? 0) + 1;
    }
    final topSport =
        (bySport.entries.toList()..sort((a, b) => b.value - a.value)).first;
    final hot = props.where((p) => p.confidence >= 90).length;

    return [
      PropAlertData(
        sport: _normalizeSport(top.sport),
        title: 'Best Edge Alert',
        message:
            '${top.player} has ${top.confidence}% confidence on ${_propMarket(top)}.',
        edge: top.confidence,
        book: top.sportsbook,
        time: 'now',
      ),
      PropAlertData(
        sport: topSport.key,
        title: 'Most Active Sport',
        message:
            '${topSport.key} has ${topSport.value} props visible right now.',
        edge: top.confidence,
        book: 'All Books',
        time: 'now',
      ),
      if (hot > 0)
        PropAlertData(
          sport: 'ALL',
          title: 'High Edge Cluster',
          message: '$hot props are at 90%+ edge right now.',
          edge: 90,
          book: 'All Books',
          time: 'now',
        ),
    ];
  }

  Future<void> _loadPropAlerts({
    List<PropData> fallbackProps = const [],
  }) async {
    try {
      final alerts = await _apiService.fetchPropAlerts();
      if (!mounted) {
        return;
      }
      final parsed = alerts
          .map(_parsePropAlert)
          .where((a) => a.message.isNotEmpty)
          .toList();
      setState(() {
        _propAlerts = parsed;
      });
    } catch (_) {
      if (!mounted || _propAlerts.isNotEmpty) {
        return;
      }
      setState(() {
        _propAlerts = _fallbackPropAlertsFromProps(fallbackProps);
      });
    }
  }

  String _formatLocalDate(DateTime value) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _formatLastUpdated(DateTime? value) {
    if (value == null) {
      return 'Not updated';
    }
    final localValue = value.toLocal();
    final hour = localValue.hour == 0
        ? 12
        : localValue.hour > 12
        ? localValue.hour - 12
        : localValue.hour;
    final minute = localValue.minute.toString().padLeft(2, '0');
    final period = localValue.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _normalizeSite(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('SLEEPER')) {
      return 'SLEEPER';
    }
    if (normalized.contains('PRIZEPICKS')) {
      return 'PRIZEPICKS';
    }
    if (normalized.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    if (normalized.contains('DRAFTPICKS')) {
      return 'DRAFT PICKS';
    }
    if (normalized.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (normalized.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    return normalized;
  }

  String _normalizeSport(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('UFC') ||
        normalized.contains('MMA') ||
        normalized.contains('ULTIMATEFIGHTING')) {
      return 'UFC';
    }
    if (normalized.contains('WNBA')) {
      return 'WNBA';
    }
    if (normalized.contains('NBA')) {
      return 'NBA';
    }
    if (normalized.contains('NFL') || normalized.contains('FOOTBALL')) {
      return 'NFL';
    }
    if (normalized.contains('MLB') || normalized.contains('BASEBALL')) {
      return 'MLB';
    }
    if (normalized.contains('SOCCER') ||
        normalized.contains('EPL') ||
        normalized.contains('MLS')) {
      return 'SOCCER';
    }
    if (normalized.contains('TENNIS') ||
        normalized.contains('ATP') ||
        normalized.contains('WTA')) {
      return 'TENNIS';
    }
    if (normalized.contains('PGA') || normalized.contains('GOLF')) {
      return 'PGA';
    }
    return normalized;
  }

  // ignore: unused_element
  Widget _filterButton(String label, String selectedValue, VoidCallback onTap) {
    final isSelected = label == selectedValue;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFFC72C)
                : const Color(0xFF07111C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFFC72C)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF06111C) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _confidenceButton(String label, int value) {
    final isSelected = _minConfidence == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _minConfidence = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFFC72C)
                : const Color(0xFF07111C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFFC72C)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF06111C) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _sortButton(String label, String value) {
    final isSelected = _sortBy == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _sortBy = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFFC72C)
                : const Color(0xFF07111C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFFC72C)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF06111C) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  List<String> get _currentCategories {
    if (_selectedSite != 'ALL' && _selectedSiteSport.isNotEmpty) {
      final counts = _selectedSportCategoryCounts;
      final available = counts.entries.toList()
        ..sort((left, right) {
          final countOrder = right.value.compareTo(left.value);
          return countOrder != 0 ? countOrder : left.key.compareTo(right.key);
        });
      return [
        'ALL',
        ...available
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key),
      ];
    }
    final available = _categoryCounts.entries.toList()
      ..sort((left, right) {
        final countOrder = right.value.compareTo(left.value);
        return countOrder != 0 ? countOrder : left.key.compareTo(right.key);
      });
    return [
      'ALL',
      ...available.where((entry) => entry.value > 0).map((entry) => entry.key),
    ];
  }

  List<String> get _availableSiteSports {
    if (_selectedSite == 'ALL') return const [];
    final sports =
        (_siteSportCounts.isNotEmpty
                ? _siteSportCounts.entries
                      .where((entry) => entry.value > 0)
                      .map((entry) => _normalizeSport(entry.key))
                : _siteInventoryProps
                      .where((prop) => !prop.gameHasStarted)
                      .map((prop) => _normalizeSport(prop.sport)))
            .where((sport) => sport.isNotEmpty && sport != 'ALL')
            .toSet()
            .toList();
    const order = [
      'NFL',
      'NBA',
      'WNBA',
      'MLB',
      'NHL',
      'PGA',
      'UFC',
      'TENNIS',
      'SOCCER',
    ];
    sports.sort((left, right) {
      final leftRank = order.indexOf(left);
      final rightRank = order.indexOf(right);
      final normalizedLeft = leftRank < 0 ? order.length : leftRank;
      final normalizedRight = rightRank < 0 ? order.length : rightRank;
      final rank = normalizedLeft.compareTo(normalizedRight);
      return rank != 0 ? rank : left.compareTo(right);
    });
    return sports;
  }

  Map<String, int> get _selectedSportCategoryCounts {
    if (_selectedSite == 'ALL' || _selectedSiteSport.isEmpty) {
      return _categoryCounts;
    }
    final backendCounts = _siteSportCategoryCounts[_selectedSiteSport];
    if (backendCounts != null && backendCounts.isNotEmpty) {
      return backendCounts;
    }
    final counts = <String, int>{};
    for (final prop in _siteInventoryProps) {
      if (prop.gameHasStarted ||
          _normalizeSport(prop.sport) != _selectedSiteSport) {
        continue;
      }
      final category = _marketCategory(prop);
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return counts;
  }

  String get _effectiveSelectedCategory {
    return _currentCategories.contains(_selectedCategory)
        ? _selectedCategory
        : 'ALL';
  }

  String _propMarket(PropData prop) {
    return (prop.market.isNotEmpty
            ? prop.market
            : prop.marketName.isNotEmpty
            ? prop.marketName
            : prop.statType.isNotEmpty
            ? prop.statType
            : prop.category.isNotEmpty
            ? prop.category
            : prop.propType.isNotEmpty
            ? prop.propType
            : prop.displayMarket.isNotEmpty
            ? prop.displayMarket
            : prop.marketKey.isNotEmpty
            ? prop.marketKey
            : '')
        .toString();
  }

  bool _containsAny(String value, List<String> matches) {
    return matches.any(value.contains);
  }

  String _categoryFromApi(PropData prop) {
    final normalized = prop.category.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }

    final sport = _normalizeSport(prop.sport);
    if (sport == 'NBA' || sport == 'WNBA') {
      switch (normalized) {
        case 'points':
          return 'POINTS';
        case 'rebounds':
          return 'REBOUNDS';
        case 'assists':
          return 'ASSISTS';
        case 'pra':
          return 'PRA';
        case 'blocks':
          return 'BLOCKS';
        case 'steals':
          return 'STEALS';
        case '3-pointers':
          return '3-POINTERS MADE';
      }
    }
    if (sport == 'NFL') {
      switch (normalized) {
        case 'passing yards':
          return 'PASSING YARDS';
        case 'rushing yards':
          return 'RUSHING YARDS';
        case 'receiving yards':
          return 'RECEIVING YARDS';
        case 'touchdowns':
          return 'TOTAL TOUCHDOWNS';
        case 'receptions':
          return 'RECEPTIONS';
        case 'rushing attempts':
          return 'PASS ATTEMPTS';
        case 'completions':
          return 'COMPLETIONS';
      }
    }
    if (sport == 'SOCCER') {
      switch (normalized) {
        case 'shots':
          return 'SHOTS';
        case 'shots on target':
          return 'SHOTS ON TARGET';
        case 'goals':
          return 'GOALS';
        case 'assists':
          return 'ASSISTS';
      }
    }
    if (sport == 'MLB') {
      switch (normalized) {
        case 'strikeouts':
          return 'PITCHER STRIKEOUTS';
        case 'outs recorded':
          return 'PITCHER OUTS';
        case 'hits allowed':
          return 'HITS ALLOWED';
        case 'hits':
          return 'HITS';
        case 'home runs':
          return 'HOME RUNS';
        case 'rbis':
          return 'RBIS';
        case 'total bases':
          return 'TOTAL BASES';
      }
    }
    if (sport == 'TENNIS') {
      switch (normalized) {
        case 'aces':
          return 'ACES';
        case 'games won':
          return 'TOTAL GAMES WON';
      }
    }
    if (sport == 'PGA') {
      switch (normalized) {
        case 'birdies':
          return 'BIRDIES OR BETTER';
        case 'fairways':
          return 'FAIRWAYS HIT';
        case 'greens':
          return 'GREENS IN REGULATION';
      }
    }
    if (sport == 'UFC') {
      switch (normalized) {
        case 'significant strikes':
          return 'SIGNIFICANT STRIKES';
        case 'takedowns':
          return 'TAKEDOWNS';
        case 'knockdowns':
          return 'KNOCKDOWNS';
        case 'submissions':
          return 'SUBMISSION ATTEMPTS';
        case 'fight time':
          return 'FIGHT TIME';
      }
    }
    return '';
  }

  String _marketCategory(PropData prop) {
    final backendCategory = _categoryFromApi(prop);
    if (backendCategory.isNotEmpty) {
      return backendCategory;
    }

    final sport = _normalizeSport(prop.sport);
    final raw = _propMarket(prop)
        .toUpperCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (sport == 'NBA' || sport == 'WNBA') {
      if (_containsAny(raw, [
        'PRA',
        'PTS REB AST',
        'POINTS REBOUNDS ASSISTS',
        'POINTS + REBOUNDS + ASSISTS',
      ])) {
        return 'PRA';
      }
      if (_containsAny(raw, [
        '3 POINTERS MADE',
        'THREE POINTERS MADE',
        '3PM',
        'MADE THREES',
      ])) {
        return '3-POINTERS MADE';
      }
      if (_containsAny(raw, ['POINTS', 'PLAYER POINTS'])) {
        return 'POINTS';
      }
      if (_containsAny(raw, ['REBOUNDS', 'PLAYER REBOUNDS'])) {
        return 'REBOUNDS';
      }
      if (_containsAny(raw, ['ASSISTS', 'PLAYER ASSISTS'])) {
        return 'ASSISTS';
      }
      if (raw.contains('BLOCK')) {
        return 'BLOCKS';
      }
      if (raw.contains('STEAL')) {
        return 'STEALS';
      }
    }
    if (sport == 'NFL') {
      if (raw.contains('PASSING YARD')) {
        return 'PASSING YARDS';
      }
      if (raw.contains('RUSHING YARD')) {
        return 'RUSHING YARDS';
      }
      if (raw.contains('RECEIVING YARD')) {
        return 'RECEIVING YARDS';
      }
      if (_containsAny(raw, [
        'TOTAL TOUCHDOWNS',
        'ANYTIME TOUCHDOWN',
        'TOUCHDOWNS',
        'TOTAL TDS',
      ])) {
        return 'TOTAL TOUCHDOWNS';
      }
      if (raw.contains('RECEPTION')) {
        return 'RECEPTIONS';
      }
      if (raw.contains('PASS ATTEMPT')) {
        return 'PASS ATTEMPTS';
      }
      if (_containsAny(raw, ['PASS COMPLETION', 'COMPLETIONS'])) {
        return 'COMPLETIONS';
      }
    }
    if (sport == 'SOCCER') {
      if (_containsAny(raw, ['SHOTS ON TARGET', 'SHOT ON TARGET', 'SOT'])) {
        return 'SHOTS ON TARGET';
      }
      if (raw.contains('SHOT')) {
        return 'SHOTS';
      }
      if (raw.contains('GOAL') && !raw.contains('GOALKEEPER')) {
        return 'GOALS';
      }
      if (raw.contains('ASSIST')) {
        return 'ASSISTS';
      }
      if (_containsAny(raw, [
        'PASSES ATTEMPTED',
        'PASS ATTEMPTS',
        'TOTAL PASSES',
      ])) {
        return 'PASSES ATTEMPTED';
      }
      if (raw.contains('SAVE')) {
        return 'SAVES';
      }
      if (raw.contains('TACKLE')) {
        return 'TACKLES';
      }
    }
    if (sport == 'MLB') {
      if (_containsAny(raw, [
        'PITCHER STRIKEOUTS',
        'PITCHING STRIKEOUTS',
        'STRIKEOUTS THROWN',
        'PITCHER KS',
      ])) {
        return 'PITCHER STRIKEOUTS';
      }
      if (_containsAny(raw, [
        'PITCHER OUTS',
        'OUTS RECORDED',
        'PITCHING OUTS',
      ])) {
        return 'PITCHER OUTS';
      }
      if (raw.contains('HITS ALLOWED')) {
        return 'HITS ALLOWED';
      }
      if (_containsAny(raw, ['HOME RUNS', 'HOME RUN'])) {
        return 'HOME RUNS';
      }
      if (_containsAny(raw, ['RBIS', 'RBI', 'RUNS BATTED IN'])) {
        return 'RBIS';
      }
      if (raw.contains('TOTAL BASE')) {
        return 'TOTAL BASES';
      }
      if (_containsAny(raw, ['PLAYER HITS', 'HITS'])) {
        return 'HITS';
      }
    }
    if (sport == 'TENNIS') {
      if (raw.contains('ACE')) {
        return 'ACES';
      }
      if (_containsAny(raw, ['TOTAL GAMES WON', 'GAMES WON', 'PLAYER GAMES'])) {
        return 'TOTAL GAMES WON';
      }
      if (_containsAny(raw, ['MATCH WINNER', 'MONEYLINE', 'TO WIN MATCH'])) {
        return 'MATCH WINNER';
      }
    }
    if (sport == 'PGA') {
      if (_containsAny(raw, ['BIRDIES OR BETTER', 'BIRDIES', 'BIRDIE'])) {
        return 'BIRDIES OR BETTER';
      }
      if (_containsAny(raw, ['ROUND SCORE', 'STROKES', 'ROUND STROKES'])) {
        return 'ROUND SCORE';
      }
      if (raw.contains('FAIRWAY')) {
        return 'FAIRWAYS HIT';
      }
      if (_containsAny(raw, ['GREENS IN REGULATION', 'GIR'])) {
        return 'GREENS IN REGULATION';
      }
      if (raw.contains('HOLES PLAYED')) {
        return 'HOLES PLAYED';
      }
      if (_containsAny(raw, ['MAKE CUT', 'MADE CUT', 'TO MAKE THE CUT'])) {
        return 'MAKE CUT';
      }
    }
    if (sport == 'UFC') {
      if (_containsAny(raw, [
        'SIGNIFICANT STRIKES',
        'SIG STRIKES',
        'SIG. STRIKES',
        'SIGNIFICANT STRIKES LANDED',
      ])) {
        return 'SIGNIFICANT STRIKES';
      }
      if (_containsAny(raw, [
        'TOTAL STRIKES',
        'STRIKES LANDED',
        'TOTAL STRIKES LANDED',
      ])) {
        return 'TOTAL STRIKES';
      }
      if (_containsAny(raw, [
        'TAKEDOWN ATTEMPTS',
        'TAKEDOWNS ATTEMPTED',
        'TD ATTEMPTS',
      ])) {
        return 'TAKEDOWN ATTEMPTS';
      }
      if (_containsAny(raw, ['TAKEDOWNS', 'TAKEDOWNS LANDED', 'TD LANDED'])) {
        return 'TAKEDOWNS';
      }
      if (_containsAny(raw, [
        'CONTROL TIME',
        'GROUND CONTROL TIME',
        'TOP CONTROL TIME',
      ])) {
        return 'CONTROL TIME';
      }
      if (_containsAny(raw, ['KNOCKDOWNS', 'KNOCKDOWNS LANDED'])) {
        return 'KNOCKDOWNS';
      }
      if (_containsAny(raw, ['SUBMISSION ATTEMPTS', 'SUB ATTEMPTS'])) {
        return 'SUBMISSION ATTEMPTS';
      }
      if (_containsAny(raw, [
        'FIGHT TIME',
        'TOTAL FIGHT TIME',
        'TIME OF FIGHT',
      ])) {
        return 'FIGHT TIME';
      }
      if (_containsAny(raw, [
        'TOTAL ROUNDS',
        'ROUNDS COMPLETED',
        'FIGHT ROUNDS',
      ])) {
        return 'ROUNDS';
      }
      if (_containsAny(raw, [
        'FIGHT WINNER',
        'MATCH WINNER',
        'MONEYLINE',
        'TO WIN',
      ])) {
        return 'FIGHT WINNER';
      }
      if (_containsAny(raw, [
        'METHOD OF VICTORY',
        'WIN METHOD',
        'KO TKO',
        'SUBMISSION',
        'DECISION',
      ])) {
        return 'METHOD OF VICTORY';
      }
    }
    return 'OTHER';
  }

  List<PropData> get _propsBeforeCategoryFilter {
    final selectedSport =
        _selectedSite != 'ALL' && _selectedSiteSport.isNotEmpty
        ? _selectedSiteSport
        : _normalizeSport(widget.sportFilter);
    final selectedSite = _normalizeSite(_selectedSite);
    final searchText = _searchQuery;

    return _latestProps.where((prop) {
      final propSport = _normalizeSport(prop.sport);
      final sportMatches = selectedSport == 'ALL' || propSport == selectedSport;
      final propSite = _normalizeSite(prop.sportsbook);
      final siteMatches = selectedSite == 'ALL' || propSite == selectedSite;
      final market = _propMarket(prop).toLowerCase();
      final searchMatches =
          searchText.isEmpty ||
          prop.player.toLowerCase().contains(searchText) ||
          market.contains(searchText);
      return sportMatches && siteMatches && searchMatches;
    }).toList();
  }

  List<PropData> get _visibleProps {
    final base = _propsBeforeCategoryFilter;
    if (_effectiveSelectedCategory == 'ALL') {
      return base;
    }
    return base
        .where((prop) => _marketCategory(prop) == _effectiveSelectedCategory)
        .toList();
  }

  Future<void> _showPlayerPropsOverlay(PropData focused) async {
    setState(() => _focusedProp = focused);
    List<PropData> playerProps;
    try {
      final fetched = await _apiService.fetchProps(
        selectedSportsbook: focused.sportsbook,
        selectedSport: focused.sport,
        search: focused.player,
        sortBy: 'time',
        limit: 500,
      );
      final playerKey = focused.player.trim().toLowerCase();
      final siteKey = _normalizeSite(focused.sportsbook);
      playerProps = fetched
          .where(
            (prop) =>
                prop.player.trim().toLowerCase() == playerKey &&
                _normalizeSite(prop.sportsbook) == siteKey,
          )
          .toList(growable: false);
    } catch (_) {
      playerProps = _latestProps
          .where(
            (prop) =>
                prop.player.trim().toLowerCase() ==
                    focused.player.trim().toLowerCase() &&
                _normalizeSite(prop.sportsbook) ==
                    _normalizeSite(focused.sportsbook),
          )
          .toList(growable: false);
    }
    if (!mounted) return;
    playerProps = activePropsInChronologicalOrder(playerProps);
    if (playerProps.isEmpty && !focused.gameHasStarted) playerProps = [focused];
    playerProps.sort((a, b) {
      final leftStart = propScheduledStart(a);
      final rightStart = propScheduledStart(b);
      if (leftStart == null && rightStart == null) {
        return _propMarket(a).compareTo(_propMarket(b));
      }
      if (leftStart == null) return 1;
      if (rightStart == null) return -1;
      final time = leftStart.compareTo(rightStart);
      return time != 0 ? time : _propMarket(a).compareTo(_propMarket(b));
    });

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .66),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          key: const ValueKey('same-player-props-overlay'),
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
          decoration: BoxDecoration(
            color: const Color(0xFF071520).withValues(alpha: .94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: .18),
                blurRadius: 28,
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.person_search, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            focused.player,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${focused.sportsbook.toUpperCase()} • ${playerProps.length} available props',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: AppColors.gold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: playerProps.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final prop = playerProps[index];
                    final start = DateTime.tryParse(
                      prop.startTimeUtc.isNotEmpty
                          ? prop.startTimeUtc
                          : prop.gameStartTime,
                    )?.toLocal();
                    final time = start == null
                        ? prop.displayTime
                        : '${start.month}/${start.day}/${start.year} '
                              '${start.hour % 12 == 0 ? 12 : start.hour % 12}:'
                              '${start.minute.toString().padLeft(2, '0')} '
                              '${start.hour >= 12 ? 'PM' : 'AM'}';
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1B27).withValues(alpha: .78),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _propMarket(prop).toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${prop.matchup} • ${time.isEmpty ? 'Time pending' : time}',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Over ${prop.overOdds?.round() ?? '--'}  •  Under ${prop.underOdds?.round() ?? '--'}',
                                      style: const TextStyle(
                                        color: Color(0xFFC8CED6),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(color: AppColors.gold),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'LINE',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 8,
                                      ),
                                    ),
                                    Text(
                                      prop.line.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: AppColors.gold,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: ValueKey(
                                    'player-overlay-over-${prop.id}',
                                  ),
                                  onPressed: prop.dataStale
                                      ? null
                                      : () {
                                          Navigator.pop(dialogContext);
                                          widget.onSelect(prop, PickSide.over);
                                        },
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'SELECT OVER ${prop.line.toStringAsFixed(1)}',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF7EE787),
                                    side: const BorderSide(
                                      color: Color(0xFF4CAF50),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: ValueKey(
                                    'player-overlay-under-${prop.id}',
                                  ),
                                  onPressed: prop.dataStale
                                      ? null
                                      : () {
                                          Navigator.pop(dialogContext);
                                          widget.onSelect(prop, PickSide.under);
                                        },
                                  icon: const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'SELECT UNDER ${prop.line.toStringAsFixed(1)}',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFFF8A93),
                                    side: const BorderSide(
                                      color: Color(0xFFEF5350),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Text(
                  'Live lines and prices can move. Confirm the current number on the listed prop site before completing a ticket.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showPropAlertsOverlay(List<PropData> visibleProps) async {
    if (_propAlerts.isEmpty) {
      await _loadPropAlerts(fallbackProps: visibleProps);
    }
    if (!mounted) {
      return;
    }

    final alerts = _propAlerts.isNotEmpty
        ? _propAlerts
        : _fallbackPropAlertsFromProps(visibleProps);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: isMobile ? screenWidth * 0.94 : 950,
            height: isMobile ? 620 : 720,
            decoration: BoxDecoration(
              color: const Color(0xFF06111C).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFC72C), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC72C).withValues(alpha: 0.25),
                  blurRadius: 32,
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        color: Color(0xFFFFC72C),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Prop Alerts',
                          style: TextStyle(
                            color: Color(0xFFFFC72C),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        icon: const Icon(Icons.close, color: Color(0xFFFFC72C)),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: const Color(0xFFFFC72C).withValues(alpha: 0.25),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: alerts.length,
                    itemBuilder: (context, index) {
                      return _PropAlertCard(alert: alerts[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoardSearchAndBooks() {
    const books = [
      'ALL',
      'PRIZEPICKS',
      'UNDERDOG',
      'FANDUEL',
      'SLEEPER',
      'DRAFTKINGS',
      'BETR',
    ];
    Widget bookMark(String book) {
      if (book == 'ALL') {
        return const Icon(Icons.keyboard_arrow_down, size: 13);
      }
      final (letter, color) = switch (book) {
        'PRIZEPICKS' => ('P', const Color(0xFF9B5CFF)),
        'UNDERDOG' => ('U', const Color(0xFFFFC400)),
        'FANDUEL' => ('F', const Color(0xFF1685F8)),
        'SLEEPER' => ('S', const Color(0xFF65D8EF)),
        'BETR' => ('B', const Color(0xFF34D399)),
        _ => ('D', const Color(0xFF8D4DFF)),
      };
      return Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          letter,
          style: const TextStyle(
            color: Color(0xFF06111B),
            fontSize: 7,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    void slideSites(double delta) {
      if (!_bookHorizontalController.hasClients) return;
      final target = (_bookHorizontalController.offset + delta).clamp(
        0.0,
        _bookHorizontalController.position.maxScrollExtent,
      );
      unawaited(
        _bookHorizontalController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }

    return Row(
      children: [
        IconButton(
          key: const ValueKey('prop-sites-scroll-left'),
          tooltip: 'Previous prop sites',
          onPressed: () => slideSites(-240),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.gold),
        ),
        Expanded(
          child: SizedBox(
            height: 48,
            child: Scrollbar(
              controller: _bookHorizontalController,
              thumbVisibility: true,
              trackVisibility: true,
              interactive: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              thickness: 4,
              radius: const Radius.circular(99),
              child: ListView.separated(
                key: const ValueKey('prop-sites-scroll-list'),
                controller: _bookHorizontalController,
                physics: const AlwaysScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: books.length + 3,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  if (index == 1) {
                    return SizedBox(
                      key: const ValueKey('board-player-search'),
                      width: 230,
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 250),
                            () {
                              if (!mounted) return;
                              setState(() {
                                _searchQuery = value.trim().toLowerCase();
                                _focusedProp = null;
                                _latestProps = const [];
                                _lastUpdated = null;
                              });
                            },
                          );
                        },
                        decoration: InputDecoration(
                          hintText: 'Search players',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                          ),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear player search',
                                  onPressed: () {
                                    _searchDebounce?.cancel();
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _focusedProp = null;
                                      _latestProps = const [];
                                      _lastUpdated = null;
                                    });
                                  },
                                  icon: const Icon(Icons.close, size: 17),
                                ),
                          filled: true,
                          fillColor: const Color(0xFF07131D),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(color: AppColors.gold),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: AppColors.gold,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  if (index == 2) {
                    return Tooltip(
                      message: 'Open PROP CHAT and join the community.',
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('board-prop-chat-button'),
                            onPressed: () =>
                                widget.onSelectPage?.call(AppPage.propChat),
                            icon: const Icon(Icons.forum_rounded, size: 17),
                            label: const Text('PROP CHAT'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.gold,
                              backgroundColor: AppColors.gold.withValues(
                                alpha: .08,
                              ),
                              side: const BorderSide(color: AppColors.gold),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                          const Positioned(
                            right: -7,
                            top: -7,
                            child: _ChatUnreadBadge(),
                          ),
                        ],
                      ),
                    );
                  }
                  if (index == 3) {
                    return OutlinedButton.icon(
                      onPressed: _showBoardFilterOptions,
                      icon: const Icon(Icons.filter_alt_outlined, size: 14),
                      label: const Text(
                        'FILTERS',
                        style: TextStyle(fontSize: 8),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF07131D),
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                      ),
                    );
                  }
                  final book = books[index > 3 ? index - 3 : index];
                  final selected = _selectedSite == book;
                  return OutlinedButton(
                    onPressed: () => setState(() {
                      _selectedSite = book;
                      _selectedSiteSport = '';
                      _selectedCategory = 'ALL';
                      _siteInventoryProps = const [];
                      _siteSportCounts = const {};
                      _siteSportCategoryCounts = const {};
                      _focusedProp = null;
                      _latestProps = const [];
                      _categoryCounts = const {};
                      _lastUpdated = null;
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: selected ? AppColors.gold : Colors.white,
                      backgroundColor: selected
                          ? AppColors.gold.withValues(alpha: .10)
                          : const Color(0xFF07131D),
                      side: BorderSide(
                        color: selected ? AppColors.gold : AppColors.border,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (book != 'ALL') ...[
                          bookMark(book),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          book == 'ALL' ? 'All Prop Sites' : book,
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (book == 'ALL') ...[
                          const SizedBox(width: 5),
                          bookMark(book),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('prop-sites-scroll-right'),
          tooltip: 'More prop sites',
          onPressed: () => slideSites(240),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded, color: AppColors.gold),
        ),
      ],
    );
  }

  // Retained for reference while the per-prop E+ intelligence panels are
  // validated in production.
  // ignore: unused_element
  Widget _buildBoardIntelligence() {
    if (!AuthManager.instance.sessionState.value.hasEdgeAccess) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF07131D),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFC8CED6)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.view_list_outlined,
                  color: Color(0xFFC8CED6),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CORE MARKET BOARD • ${_visibleProps.length} AVAILABLE PROPS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFC8CED6),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'PRO unlocks projections, confidence and edge ranking',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: AppColors.muted, fontSize: 8),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }
    final focusedProp = _focusedProp;
    final selectedProps = <String, PropData>{
      for (final selection in widget.selections)
        selection.prop.id: selection.prop,
    }.values.toList(growable: false);
    // Once a user adds props, the intelligence row summarizes the active
    // selection instead of remaining pinned to whichever card was last
    // focused. With no active selection, a card tap still opens the focused
    // single-prop view.
    final props = boardIntelligenceScope(
      selections: widget.selections,
      visibleProps: _visibleProps,
      focusedProp: focusedProp,
    );
    final showingFocusedProp = focusedProp != null && selectedProps.isEmpty;
    // Edge requires a real model projection - recommendationEdge/edge default
    // to exactly 0.0 (not "unknown") when no projection was supplied, so a
    // near-zero value here genuinely means "no edge data," not "zero edge."
    final focusedEdgeAvailable =
        focusedProp?.projection != null ||
        (focusedProp?.recommendationEdge ?? 0).abs() > .0001;
    // Confidence/hit rate is computed independently of edge and is populated
    // for virtually every prop, so it shouldn't be hidden just because edge
    // happens to be unavailable - matches the unfocused "HIGHEST HIT RATE"
    // tile below, which already shows confidence unconditionally.
    final focusedConfidenceAvailable = (focusedProp?.confidence ?? 0) > 0;
    final metricScope = selectedProps.isNotEmpty
        ? 'Across ${selectedProps.length} selected'
        : 'Across visible props';
    final modeledProps = props
        .where(
          (prop) =>
              prop.proSuggestionUsesModel ||
              prop.projection != null ||
              prop.recommendationEdge.abs() > .0001,
        )
        .toList(growable: false);
    final top = modeledProps.isEmpty
        ? null
        : ([...modeledProps]..sort(
                (a, b) =>
                    (b.calculatedEdge ?? 0).compareTo(a.calculatedEdge ?? 0),
              ))
              .first;
    final averageEdge = modeledProps.isEmpty
        ? null
        : modeledProps.fold<double>(
                0,
                (sum, prop) => sum + (prop.calculatedEdge ?? 0),
              ) /
              modeledProps.length;
    final confidenceProps = modeledProps
        .where(
          (prop) =>
              (prop.historicalHitRate ?? 0) > 0 ||
              (prop.projectionCalibrated && prop.confidence > 0),
        )
        .toList(growable: false);
    final hitLeader = confidenceProps.isEmpty
        ? null
        : ([...confidenceProps]..sort(
                (a, b) => (b.historicalHitRate ?? b.confidence).compareTo(
                  a.historicalHitRate ?? a.confidence,
                ),
              ))
              .first;
    final entries = showingFocusedProp
        ? <(String, String, String)>[
            (
              'PLAYER',
              focusedProp.player,
              '${focusedProp.sport} • ${focusedProp.sportsbook}',
            ),
            (
              'EDGE',
              focusedEdgeAvailable
                  ? '${focusedProp.edge >= 0 ? '+' : ''}${focusedProp.edge.toStringAsFixed(2)}%'
                  : '--',
              focusedEdgeAvailable
                  ? 'Model edge for this prop'
                  : 'Awaiting model projection',
            ),
            (
              'HIT RATE',
              focusedConfidenceAvailable ? '${focusedProp.confidence}%' : '--',
              focusedConfidenceAvailable
                  ? 'Current model confidence'
                  : 'Awaiting model projection',
            ),
            (
              'MARKET',
              _marketCategory(focusedProp),
              '${focusedProp.line.toStringAsFixed(1)} • ${focusedProp.recommendedSide}',
            ),
            (
              'LAST UPDATED',
              _formatLastUpdated(_lastUpdated),
              _formatLocalDate(DateTime.now()),
            ),
          ]
        : <(String, String, String)>[
            (
              'TOP EDGE',
              top?.player ?? 'Awaiting projection',
              top == null
                  ? '--'
                  : '${top.edge >= 0 ? '+' : ''}${top.edge.toStringAsFixed(2)}%',
            ),
            (
              'AVG EDGE',
              averageEdge == null
                  ? '--'
                  : '${averageEdge >= 0 ? '+' : ''}${averageEdge.toStringAsFixed(2)}%',
              metricScope,
            ),
            (
              'HIGHEST HIT RATE',
              hitLeader?.player ?? '--',
              hitLeader == null
                  ? '--'
                  : '${hitLeader.historicalHitRate ?? hitLeader.confidence}%',
            ),
            (
              'PROPS WITH EDGE',
              '${modeledProps.where((p) => p.edge > 0).length}',
              selectedProps.isNotEmpty
                  ? '${selectedProps.length} selected'
                  : '${modeledProps.length} modeled',
            ),
            (
              'LAST UPDATED',
              _formatLastUpdated(_lastUpdated),
              _formatLocalDate(DateTime.now()),
            ),
          ];
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xFF07131D),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            Expanded(
              flex: i == 0 || i == 2 ? 3 : 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entries[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entries[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (i == 0 || i == 2)
                          const SizedBox(
                            width: 40,
                            height: 20,
                            child: CustomPaint(
                              painter: _BoardSparklinePainter(),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entries[i].$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: i < 3
                            ? const Color(0xFF62E34F)
                            : AppColors.muted,
                        fontSize: 7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < entries.length - 1)
              Container(width: 1, height: 44, color: AppColors.border),
          ],
          OutlinedButton.icon(
            onPressed: _showBoardFilterOptions,
            icon: const Icon(Icons.filter_alt_outlined, size: 14),
            label: const Text('Filter Options', style: TextStyle(fontSize: 8)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 9),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Future<void> _showBoardFilterOptions() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xFF07131D),
        title: const Text(
          'Filter Options',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: [
          RadioGroup<String>(
            groupValue: _sortBy,
            onChanged: (value) => Navigator.pop(dialogContext, value),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: 'source',
                  activeColor: AppColors.gold,
                  title: Text(
                    'Board order',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                RadioListTile<String>(
                  value: 'edge',
                  activeColor: AppColors.gold,
                  title: Text(
                    'Highest edge',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                RadioListTile<String>(
                  value: 'confidence',
                  activeColor: AppColors.gold,
                  title: Text(
                    'Highest confidence',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      setState(() => _sortBy = selected);
    }
  }

  Widget _buildBoardCategories() {
    final categories = _currentCategories;
    IconData categoryIcon(String category) => switch (category) {
      'ALL' => Icons.grid_view_rounded,
      'POINTS' => Icons.control_point_rounded,
      'REBOUNDS' => Icons.sports_basketball,
      'ASSISTS' => Icons.hub_outlined,
      'PRA' => Icons.person_pin_circle_outlined,
      'PTS+REBS+ASTS' => Icons.account_tree_outlined,
      'BLOCKS+STEALS' => Icons.swap_calls_rounded,
      '3PT MADE' => Icons.adjust_rounded,
      _ => Icons.apps,
    };
    final localCounts = _selectedSportCategoryCounts;
    int categoryCount(String category) => category == 'ALL'
        ? localCounts.values.fold<int>(0, (sum, count) => sum + count)
        : localCounts[category] ?? 0;
    return SizedBox(
      height: 49,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              controller: _categoryHorizontalController,
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = _effectiveSelectedCategory == category;
                return OutlinedButton(
                  onPressed: () => setState(() {
                    _selectedCategory = category;
                    _focusedProp = null;
                    _latestProps = const [];
                    _lastUpdated = null;
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: selected ? AppColors.gold : Colors.white,
                    backgroundColor: const Color(0xFF07131D),
                    side: BorderSide(
                      color: selected ? AppColors.gold : AppColors.border,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(categoryIcon(category), size: 13),
                      const SizedBox(width: 6),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            category,
                            style: const TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${categoryCount(category)}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 6,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 42,
            height: 49,
            child: OutlinedButton(
              onPressed: () {
                if (!_categoryHorizontalController.hasClients) return;
                final target = (_categoryHorizontalController.offset + 220)
                    .clamp(
                      0.0,
                      _categoryHorizontalController.position.maxScrollExtent,
                    )
                    .toDouble();
                _categoryHorizontalController.animateTo(
                  target,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              },
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              child: const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardSports() {
    final sports = _availableSiteSports;
    if (sports.isEmpty) {
      return const SizedBox.shrink();
    }
    int sportCount(String sport) =>
        _siteSportCounts[sport] ??
        _siteInventoryProps
            .where(
              (prop) =>
                  !prop.gameHasStarted && _normalizeSport(prop.sport) == sport,
            )
            .length;
    IconData sportIcon(String sport) => switch (sport) {
      'NFL' => Icons.sports_football,
      'NBA' || 'WNBA' => Icons.sports_basketball,
      'MLB' => Icons.sports_baseball,
      'NHL' => Icons.sports_hockey,
      'PGA' => Icons.sports_golf,
      'UFC' => Icons.sports_mma,
      'TENNIS' => Icons.sports_tennis,
      'SOCCER' => Icons.sports_soccer,
      _ => Icons.emoji_events_outlined,
    };
    return SizedBox(
      height: 45,
      child: ListView.separated(
        key: const ValueKey('prop-site-sport-tabs'),
        controller: _sportHorizontalController,
        scrollDirection: Axis.horizontal,
        itemCount: sports.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final sport = sports[index];
          final selected = sport == _selectedSiteSport;
          return OutlinedButton.icon(
            key: ValueKey('prop-site-sport-$sport'),
            onPressed: () => setState(() {
              _selectedSiteSport = sport;
              _selectedCategory = 'ALL';
              _focusedProp = null;
            }),
            icon: Icon(sportIcon(sport), size: 14),
            label: Text('$sport  ${sportCount(sport)}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: selected
                  ? const Color(0xFF07131D)
                  : Colors.white,
              backgroundColor: selected
                  ? AppColors.gold
                  : const Color(0xFF07131D),
              side: BorderSide(
                color: selected ? AppColors.gold : AppColors.border,
                width: selected ? 1.4 : 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              textStyle: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alertsForPage = _propAlerts.isNotEmpty
        ? _propAlerts
        : _fallbackPropAlertsFromProps(_latestProps);
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: widget.selectedPage == AppPage.searchPlayers
                ? SearchPlayersPage(props: _latestProps)
                : widget.selectedPage == AppPage.gameMarkets
                ? GameMarketsScreen(onAddToSlip: widget.onAddGameMarket)
                : widget.selectedPage == AppPage.evScanner
                ? _buildEvScanner()
                : widget.selectedPage == AppPage.scoreboard
                ? const LiveScoreboardTickerGridWidget()
                : widget.selectedPage == AppPage.scoreboardWatchlist
                ? const LiveScoreboardTickerGridWidget(watchedOnly: true)
                : widget.selectedPage == AppPage.propAlerts
                ? PropAlertsPage(alerts: alertsForPage)
                : widget.selectedPage == AppPage.analytics
                ? AnalyticsAdminWorkspace(selectedSport: widget.sportFilter)
                : widget.selectedPage == AppPage.lineMovement
                ? LineMovementPage(
                    selectedSport: widget.sportFilter,
                    hasProAccess:
                        AuthManager.instance.sessionState.value.hasEdgeAccess,
                  )
                : widget.selectedPage == AppPage.dataAdmin
                ? AnalyticsAdminWorkspace(
                    selectedSport: widget.sportFilter,
                    startInDataAdmin: true,
                  )
                : widget.selectedPage == AppPage.ownerOperations
                ? const OwnerOperationsPage()
                : widget.selectedPage == AppPage.intelligenceLab
                ? IntelligenceLabPage(
                    selections: widget.selections,
                    onRemove: widget.onRemoveLabSelection,
                    onClear: widget.onClearLabSelections,
                  )
                : widget.selectedPage == AppPage.refereeTracker
                ? const RefereeTrackerPage()
                : widget.selectedPage == AppPage.propChat
                ? PropChatPage(
                    onPopOut: widget.onFloatChat,
                    onShowBubble: widget.onShowChatBubble,
                    isBubbleVisible: widget.isChatBubbleVisible,
                    sharedAnalysis: {
                      'kind': widget.selections.length == 1 ? 'prop' : 'slip',
                      'title': widget.selections.length == 1
                          ? 'Prop analysis'
                          : '${widget.selections.length}-leg slip',
                      'legs': widget.selections
                          .map(
                            (selection) => {
                              'player': selection.prop.player,
                              'market': selection.prop.propType,
                              'side': selection.sideLabel,
                              'line': selection.prop.line,
                              'odds': selection.odds,
                            },
                          )
                          .toList(growable: false),
                    },
                  )
                : Scrollbar(
                    controller: _boardVerticalController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 9,
                    radius: const Radius.circular(8),
                    scrollbarOrientation: ScrollbarOrientation.right,
                    child: SingleChildScrollView(
                      controller: _boardVerticalController,
                      primary: false,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBoardSearchAndBooks(),
                          const SizedBox(height: 12),
                          if (_selectedSite != 'ALL') ...[
                            _buildBoardSports(),
                            const SizedBox(height: 7),
                            _buildBoardCategories(),
                            const SizedBox(height: 10),
                          ],
                          /*Text(
                            '${visibleProps.length} visible props • $_propCount total loaded',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),*/
                          PropGrid(
                            selections: widget.selections,
                            onSelect: (prop, side) {
                              setState(() => _focusedProp = prop);
                              widget.onSelect(prop, side);
                            },
                            onPropFocused: _showPlayerPropsOverlay,
                            sportFilter: _selectedSite == 'ALL'
                                ? widget.sportFilter
                                : _selectedSiteSport.isEmpty
                                ? 'ALL'
                                : _selectedSiteSport,
                            displaySportFilter: _selectedSite == 'ALL'
                                ? widget.sportFilter
                                : _selectedSiteSport,
                            searchQuery: _searchQuery,
                            selectedSite: _selectedSite,
                            selectedCategory: _effectiveSelectedCategory,
                            selectedSide: _selectedSide,
                            selectedTier: _selectedTier,
                            minConfidence: _minConfidence,
                            sortBy: _sortBy,
                            onPropsLoaded: _handlePropsLoaded,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class AnalyticsAdminWorkspace extends StatefulWidget {
  const AnalyticsAdminWorkspace({
    super.key,
    required this.selectedSport,
    this.startInDataAdmin = false,
  });

  final String selectedSport;
  final bool startInDataAdmin;

  @override
  State<AnalyticsAdminWorkspace> createState() =>
      _AnalyticsAdminWorkspaceState();
}

class _AnalyticsAdminWorkspaceState extends State<AnalyticsAdminWorkspace> {
  late bool _showDataAdmin = widget.startInDataAdmin;

  Widget _viewButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? AppColors.gold : Colors.white,
        backgroundColor: selected
            ? AppColors.gold.withValues(alpha: .10)
            : const Color(0xFF07131D),
        side: BorderSide(color: selected ? AppColors.gold : AppColors.border),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthSessionState>(
      valueListenable: AuthManager.instance.sessionState,
      builder: (context, authState, _) {
        final canUseDataAdmin = authState.isOwner;
        final showDataAdmin = canUseDataAdmin && _showDataAdmin;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              decoration: const BoxDecoration(
                color: Color(0xFF07131D),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  _viewButton(
                    label: 'ANALYTICS',
                    icon: Icons.analytics_outlined,
                    selected: !showDataAdmin,
                    onPressed: () => setState(() => _showDataAdmin = false),
                  ),
                  if (canUseDataAdmin) ...[
                    const SizedBox(width: 8),
                    _viewButton(
                      label: 'DATA ADMIN',
                      icon: Icons.admin_panel_settings_outlined,
                      selected: showDataAdmin,
                      onPressed: () => setState(() => _showDataAdmin = true),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: authState.hasEdgeAccess
                          ? AppColors.gold
                          : const Color(0xFFC8CED6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      authState.hasEdgeAccess ? 'PRO' : 'CORE',
                      style: const TextStyle(
                        color: Color(0xFF06111B),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: showDataAdmin
                  ? const DataAdminPage()
                  : AnalyticsPage(
                      selectedSport: widget.selectedSport,
                      hasProAccess: authState.hasEdgeAccess,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class DataAdminPage extends StatefulWidget {
  const DataAdminPage({super.key});

  @override
  State<DataAdminPage> createState() => _DataAdminPageState();
}

class _DataAdminPageState extends State<DataAdminPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _identityController = TextEditingController();
  final TextEditingController _availabilityController = TextEditingController();

  bool _isBusy = false;
  String _identityMode = 'merge';
  String _availabilityMode = 'merge';
  String _statusText = '';
  String _unresolvedSummary = '';
  String _identityPreviewText = 'Identity preview: 0 entries';
  String _availabilityPreviewText = 'Availability preview: 0 players';
  Map<String, dynamic>? _lastUnresolvedGrouped;
  Map<String, dynamic>? _operations;
  Map<String, dynamic>? _acceptance;
  Map<String, dynamic>? _controlPanel;
  final List<String> _uploadAuditEntries = [];

  static const String _auditPrefKey = 'data_admin_upload_audit_v1';

  @override
  void initState() {
    super.initState();
    _identityController.text = const JsonEncoder.withIndent('  ').convert({
      'providers': {'odds-api': {}},
    });
    _availabilityController.text = const JsonEncoder.withIndent(
      '  ',
    ).convert({'players': {}});
    _identityController.addListener(_refreshPreviewCounts);
    _availabilityController.addListener(_refreshPreviewCounts);
    _refreshPreviewCounts();
    unawaited(_loadAuditEntries());
    unawaited(_refreshUnresolved());
    unawaited(_refreshOperations());
    unawaited(_refreshAcceptance());
    unawaited(_refreshControlPanel());
  }

  Future<void> _refreshControlPanel() async {
    try {
      final result = await _apiService.fetchLaunchControlPanel();
      if (mounted) {
        setState(() => _controlPanel = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusText = 'Launch control panel failed: $error');
      }
    }
  }

  Widget _buildLaunchControlPanel() {
    final api = _controlPanel?['api'] as Map? ?? const {};
    final redis = _controlPanel?['redis'] as Map? ?? const {};
    final workers = _controlPanel?['workers'] as Map? ?? const {};
    final providers = _controlPanel?['providers'] as Map? ?? const {};
    final freshness = _controlPanel?['propFreshness'] as Map? ?? const {};
    final scoreboard = _controlPanel?['scoreboardLatency'] as Map? ?? const {};
    final activeUsers = _controlPanel?['activeUsers'] as Map? ?? const {};
    final failedLogins = _controlPanel?['failedLogins'] as Map? ?? const {};
    final failedPayments = _controlPanel?['failedPayments'] as Map? ?? const {};
    final unsettledSlips = _controlPanel?['unsettledSlips'] as Map? ?? const {};
    final gradingReview = _controlPanel?['gradingReview'] as Map? ?? const {};
    final pipelines = _controlPanel?['pipelines'] as Map? ?? const {};

    Widget signal(
      String label,
      String value,
      IconData icon, {
      bool healthy = true,
      String? detail,
    }) {
      final color = healthy ? const Color(0xFF8CFFB2) : const Color(0xFFFFD166);
      return Container(
        width: 210,
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF101C28),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 17),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF8296AA),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(color: Color(0xFF8296AA), fontSize: 9),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }

    final queueAvailable = workers['available'] == true;
    final redisAvailable = redis['available'] == true;
    final feedHealthy = freshness['healthy'] == true;
    final quotaLow = providers['lowQuota'] == true;
    final failedLoginCount = failedLogins['count'];
    final version = api['version']?.toString() ?? 'Loading';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07121C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3D51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dashboard_customize_outlined,
                color: Color(0xFFFFC400),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'LAUNCH-DAY CONTROL PANEL',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              IconButton(
                onPressed: _refreshControlPanel,
                tooltip: 'Refresh launch telemetry',
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              signal(
                'API HEALTH',
                api['status']?.toString().toUpperCase() ?? 'LOADING',
                Icons.cloud_done_outlined,
                healthy: api['status'] == 'ok',
              ),
              signal(
                'REDIS HEALTH',
                redisAvailable
                    ? 'CONNECTED'
                    : (redis['mode']?.toString().toUpperCase() ?? 'LOADING'),
                Icons.storage_outlined,
                healthy: redisAvailable,
              ),
              signal(
                'WORKERS / QUEUE',
                queueAvailable
                    ? '${workers['workers'] ?? 0} workers'
                    : (workers['mode']?.toString().toUpperCase() ?? 'LOADING'),
                Icons.precision_manufacturing_outlined,
                healthy: queueAvailable,
                detail:
                    '${workers['queued'] ?? 0} queued • ${workers['failed'] ?? 0} failed',
              ),
              signal(
                'PROVIDER ERRORS',
                '${providers['errors'] ?? 0}',
                Icons.report_problem_outlined,
                healthy: (providers['errors'] ?? 0) == 0,
                detail:
                    '${providers['remainingQuota'] ?? 'Unknown'} quota remaining',
              ),
              signal(
                'PROP FRESHNESS',
                freshness['ageMinutes'] == null
                    ? 'UNKNOWN'
                    : '${freshness['ageMinutes']} min old',
                Icons.update_outlined,
                healthy: feedHealthy,
                detail: '${freshness['total'] ?? 0} live props',
              ),
              signal(
                'SCOREBOARD LATENCY',
                scoreboard['lastMs'] == null
                    ? 'NOT CHECKED'
                    : '${scoreboard['lastMs']} ms',
                Icons.speed_outlined,
                healthy: scoreboard['status'] == 'ok',
                detail: 'p95 ${scoreboard['p95Ms'] ?? '—'} ms',
              ),
              signal(
                'ACTIVE USERS',
                activeUsers['count']?.toString() ?? 'UNAVAILABLE',
                Icons.people_outline,
                healthy: activeUsers['instrumented'] == true,
                detail: 'Observed in the last 15 minutes',
              ),
              signal(
                'FAILED LOGINS',
                failedLoginCount?.toString() ?? 'NOT INSTRUMENTED',
                Icons.no_accounts_outlined,
                healthy: failedLoginCount == 0,
                detail: 'Supabase log integration required',
              ),
              signal(
                'FAILED PAYMENTS',
                '${failedPayments['count'] ?? 'Unknown'}',
                Icons.credit_card_off_outlined,
                healthy: (failedPayments['count'] ?? 0) == 0,
                detail: 'Last 24 hours',
              ),
              signal(
                'UNSETTLED SLIPS',
                '${unsettledSlips['count'] ?? 'Unknown'}',
                Icons.receipt_long_outlined,
                detail: 'Active tickets awaiting settlement',
              ),
              signal(
                'GRADING REVIEW',
                '${gradingReview['questionableCount'] ?? 'Unknown'}',
                Icons.fact_check_outlined,
                healthy: (gradingReview['questionableCount'] ?? 0) == 0,
                detail:
                    '${gradingReview['unsettledCount'] ?? 'Unknown'} overdue pending legs',
              ),
              signal(
                'DEPLOYMENT VERSION',
                version.length > 10 ? version.substring(0, 10) : version,
                Icons.rocket_launch_outlined,
                detail: 'API release commit',
              ),
              signal(
                'PIPELINES',
                pipelines['healthy'] == true ? 'HEALTHY' : 'ATTENTION',
                Icons.account_tree_outlined,
                healthy: pipelines['healthy'] == true,
                detail:
                    '${(pipelines['activeFailures'] as List?)?.length ?? 0} active failures',
              ),
            ],
          ),
          if (quotaLow) ...[
            const SizedBox(height: 10),
            const Text(
              'Provider quota is below the configured reserve.',
              style: TextStyle(
                color: Color(0xFFFFD166),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshAcceptance() async {
    try {
      final result = await _apiService.fetchProductionAcceptance();
      if (mounted) {
        setState(() => _acceptance = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusText = 'Production health failed: $error');
      }
    }
  }

  Widget _buildAcceptancePanel() {
    final status =
        _acceptance?['status']?.toString().toUpperCase() ?? 'LOADING';
    final feed = _acceptance?['propFeed'] as Map? ?? const {};
    final billing = _acceptance?['billing'] as Map? ?? const {};
    final quota = _acceptance?['providerQuota'] as Map? ?? const {};
    final issues = _acceptance?['issues'] as List? ?? const [];
    final color = status == 'HEALTHY'
        ? const Color(0xFF8CFFB2)
        : status == 'WARNING'
        ? const Color(0xFFFFD166)
        : const Color(0xFFFF8A80);
    Widget metric(String label, String value, IconData icon) => Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101C28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFC400), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8296AA),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07121C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'PRODUCTION ACCEPTANCE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              IconButton(
                onPressed: _refreshAcceptance,
                tooltip: 'Refresh production health',
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              metric(
                'LIVE PROPS',
                '${feed['total'] ?? 0}',
                Icons.analytics_outlined,
              ),
              metric(
                'FEED AGE',
                feed['ageMinutes'] == null
                    ? 'Unknown'
                    : '${feed['ageMinutes']} min',
                Icons.schedule,
              ),
              metric(
                'ODDS QUOTA',
                '${quota['remaining'] ?? 'Unknown'} remaining',
                Icons.speed,
              ),
              metric(
                'BILLING',
                billing['webhookConfigured'] == true &&
                        billing['coreProductsConfigured'] == true &&
                        billing['edgeProductsConfigured'] == true
                    ? 'Configured'
                    : 'Needs attention',
                Icons.payments_outlined,
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...issues.whereType<Map>().map(
              (issue) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${issue['message']}',
                  style: TextStyle(
                    color: issue['severity'] == 'critical'
                        ? const Color(0xFFFF8A80)
                        : const Color(0xFFFFD166),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Webhook delivery is only marked verified after a successful test or purchase event.',
            style: TextStyle(color: Color(0xFF8296AA), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshOperations() async {
    try {
      final result = await _apiService.fetchAdminOperations();
      if (mounted) {
        setState(() => _operations = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusText = 'Pipeline monitoring failed: $error');
      }
    }
  }

  Widget _buildOperationsPanel() {
    final runs = _operations?['runs'] as List? ?? const [];
    final latest = runs.isNotEmpty && runs.first is Map
        ? runs.first as Map
        : null;
    final valid =
        (_operations?['validCalibrationResults'] as num?)?.toInt() ?? 0;
    final pending = (_operations?['pendingPredictions'] as num?)?.toInt() ?? 0;
    final status = latest?['status']?.toString() ?? 'NO RUNS';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1520),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A3D51)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.monitor_heart_outlined,
            color: Color(0xFFFFC400),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'PIPELINE $status',
            style: TextStyle(
              color: status == 'FAILED'
                  ? const Color(0xFFFF8A80)
                  : const Color(0xFF8CFFB2),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            'Today: ${_operations?['snapshotsToday'] ?? 0} snapshots',
            style: const TextStyle(color: Color(0xFF9EB1C4), fontSize: 11),
          ),
          const SizedBox(width: 18),
          Text(
            'Pending: $pending',
            style: const TextStyle(color: Color(0xFF9EB1C4), fontSize: 11),
          ),
          const SizedBox(width: 18),
          Text(
            'Calibration: $valid / 100',
            style: const TextStyle(color: Color(0xFF9EB1C4), fontSize: 11),
          ),
          const Spacer(),
          IconButton(
            onPressed: _refreshOperations,
            tooltip: 'Refresh pipeline status',
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _identityController.removeListener(_refreshPreviewCounts);
    _availabilityController.removeListener(_refreshPreviewCounts);
    _identityController.dispose();
    _availabilityController.dispose();
    super.dispose();
  }

  void _refreshPreviewCounts() {
    final identityText = _buildIdentityPreview(_identityController.text);
    final availabilityText = _buildAvailabilityPreview(
      _availabilityController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _identityPreviewText = identityText;
      _availabilityPreviewText = availabilityText;
    });
  }

  Future<void> _loadAuditEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_auditPrefKey) ?? <String>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadAuditEntries
        ..clear()
        ..addAll(saved);
    });
  }

  Future<void> _appendAuditEntry(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '$timestamp | $message';

    if (mounted) {
      setState(() {
        _uploadAuditEntries.insert(0, entry);
        if (_uploadAuditEntries.length > 30) {
          _uploadAuditEntries.removeRange(30, _uploadAuditEntries.length);
        }
      });
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_auditPrefKey, _uploadAuditEntries);
  }

  Future<void> _exportUnresolvedGroupedJson() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });

    try {
      final grouped =
          _lastUnresolvedGrouped ??
          await _apiService.fetchIdentityUnresolvedGrouped();
      final count = (grouped['count'] as num?)?.toInt() ?? 0;
      final payload = const JsonEncoder.withIndent('  ').convert(grouped);

      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Save unresolved grouped export',
        fileName: 'identity_unresolved_grouped.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(payload)),
      );

      if (savePath == null || savePath.trim().isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _statusText = 'Export canceled.';
        });
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Exported unresolved JSON to $savePath';
      });
      await _appendAuditEntry(
        'unresolved export saved | count=$count | path=$savePath',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Unresolved export failed: $error';
      });
      await _appendAuditEntry('unresolved export failed | $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _copyUnresolvedGroupedJson() async {
    try {
      final grouped =
          _lastUnresolvedGrouped ??
          await _apiService.fetchIdentityUnresolvedGrouped();
      final count = (grouped['count'] as num?)?.toInt() ?? 0;
      final payload = const JsonEncoder.withIndent('  ').convert(grouped);
      await Clipboard.setData(ClipboardData(text: payload));
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Unresolved JSON copied to clipboard.';
      });
      await _appendAuditEntry('unresolved export copied | count=$count');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Copy unresolved JSON failed: $error';
      });
      await _appendAuditEntry('unresolved copy failed | $error');
    }
  }

  Widget _buildAuditLogPanel() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 90, maxHeight: 140),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1520),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A3D51)),
      ),
      child: _uploadAuditEntries.isEmpty
          ? const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No upload audit entries yet.',
                style: TextStyle(
                  color: Color(0xFF9EB1C4),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _uploadAuditEntries.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _uploadAuditEntries[index],
                    style: const TextStyle(
                      color: Color(0xFF9EB1C4),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _buildIdentityPreview(String rawJson) {
    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map<String, dynamic>) {
        return 'Identity preview: invalid JSON object';
      }
      final providers = parsed['providers'];
      if (providers is! Map<String, dynamic>) {
        return "Identity preview: missing 'providers' object";
      }
      int entries = 0;
      for (final value in providers.values) {
        if (value is Map<String, dynamic>) {
          entries += value.length;
        }
      }
      return 'Identity preview: $entries entries across ${providers.length} providers';
    } catch (_) {
      return 'Identity preview: invalid JSON syntax';
    }
  }

  String _buildAvailabilityPreview(String rawJson) {
    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map<String, dynamic>) {
        return 'Availability preview: invalid JSON object';
      }
      final players = parsed['players'];
      if (players is! Map<String, dynamic>) {
        return "Availability preview: missing 'players' object";
      }
      return 'Availability preview: ${players.length} players';
    } catch (_) {
      return 'Availability preview: invalid JSON syntax';
    }
  }

  Widget _previewBadge({required String text}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1520),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A3D51)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF9EB1C4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _refreshUnresolved() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });
    try {
      final grouped = await _apiService.fetchIdentityUnresolvedGrouped();
      final count = (grouped['count'] as num?)?.toInt() ?? 0;
      final sportsMap = grouped['sports'];
      final sportNames = <String>[];
      if (sportsMap is Map<String, dynamic>) {
        sportNames.addAll(sportsMap.keys);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _lastUnresolvedGrouped = grouped;
        _unresolvedSummary =
            'Unresolved players: $count (${sportNames.join(', ')})';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _unresolvedSummary = 'Unable to fetch unresolved identities: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _uploadIdentityPayload() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });
    try {
      final parsed = jsonDecode(_identityController.text);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Identity payload must be a JSON object.');
      }
      final providers = parsed['providers'];
      if (providers is! Map<String, dynamic>) {
        throw const FormatException(
          "Identity payload must include top-level 'providers' object.",
        );
      }
      final result = await _apiService.bulkUpsertIdentityMap(
        payload: parsed,
        mode: _identityMode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText =
            'Identity upload complete. Provider sizes: ${result['providerSizes']}';
      });
      await _appendAuditEntry(
        'identity upload success | mode=$_identityMode | processed=${result['processedEntries'] ?? '?'}',
      );
      await _refreshUnresolved();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Identity upload failed: $error';
      });
      await _appendAuditEntry(
        'identity upload failed | mode=$_identityMode | $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _validateJsonPayload({
    required TextEditingController controller,
    required String label,
    required String requiredTopLevelKey,
  }) {
    try {
      final parsed = jsonDecode(controller.text);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Payload root must be a JSON object.');
      }
      final topLevel = parsed[requiredTopLevelKey];
      if (topLevel is! Map<String, dynamic>) {
        throw FormatException(
          "Payload must include top-level '$requiredTopLevelKey' object.",
        );
      }
      setState(() {
        _statusText = '$label JSON is valid.';
      });
    } catch (error) {
      setState(() {
        _statusText = '$label JSON validation failed: $error';
      });
    }
  }

  Future<void> _loadPayloadFromFile({
    required TextEditingController controller,
    required String label,
    required String requiredTopLevelKey,
  }) async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final selected = picked.files.first;
      final content = utf8.decode(await selected.readAsBytes());

      if (content.trim().isEmpty) {
        throw const FormatException('Selected file is empty or unreadable.');
      }

      final parsed = jsonDecode(content);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Payload root must be a JSON object.');
      }
      final topLevel = parsed[requiredTopLevelKey];
      if (topLevel is! Map<String, dynamic>) {
        throw FormatException(
          "Payload must include top-level '$requiredTopLevelKey' object.",
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        controller.text = const JsonEncoder.withIndent('  ').convert(parsed);
        _statusText = '$label file loaded and validated.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = '$label load failed: $error';
      });
    }
  }

  Future<void> _uploadAvailabilityPayload() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });
    try {
      final parsed = jsonDecode(_availabilityController.text);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException(
          'Availability payload must be a JSON object.',
        );
      }
      final players = parsed['players'];
      if (players is! Map<String, dynamic>) {
        throw const FormatException(
          "Availability payload must include top-level 'players' object.",
        );
      }
      final result = await _apiService.bulkUpsertPlayerAvailability(
        payload: parsed,
        mode: _availabilityMode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Availability upload complete. Count: ${result['count']}';
      });
      await _appendAuditEntry(
        'availability upload success | mode=$_availabilityMode | processed=${result['processedEntries'] ?? '?'}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Availability upload failed: $error';
      });
      await _appendAuditEntry(
        'availability upload failed | mode=$_availabilityMode | $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Widget _modeDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9EB1C4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF0A1520),
          style: const TextStyle(color: Colors.white),
          underline: Container(height: 1, color: const Color(0xFF294052)),
          items: const [
            DropdownMenuItem(value: 'merge', child: Text('merge')),
            DropdownMenuItem(value: 'replace', child: Text('replace')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _jsonEditor({
    required String title,
    required String schemaHint,
    required TextEditingController controller,
    required VoidCallback onUpload,
    required VoidCallback onValidate,
    required VoidCallback onLoadFile,
    required String mode,
    required ValueChanged<String?> onModeChanged,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1520),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF294052)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFFFC400),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        schemaHint,
                        style: const TextStyle(
                          color: Color(0xFF9EB1C4),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _modeDropdown(
                  label: 'Mode',
                  value: mode,
                  onChanged: onModeChanged,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Consolas',
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF294052)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF294052)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFFFC400)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _isBusy ? null : onLoadFile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF3A5167)),
                  ),
                  child: const Text('Load File'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isBusy ? null : onValidate,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8CFFB2),
                    side: const BorderSide(color: Color(0xFF2B7A4B)),
                  ),
                  child: const Text('Validate'),
                ),
                const SizedBox(height: 4),
                ElevatedButton(
                  onPressed: _isBusy ? null : onUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC400),
                    foregroundColor: const Color(0xFF07131F),
                  ),
                  child: const Text('Upload JSON'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'DATA ADMIN',
                style: TextStyle(
                  color: Color(0xFFFFC400),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton(
                onPressed: _isBusy ? null : _refreshUnresolved,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D3144),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Refresh Unresolved'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _isBusy
                    ? null
                    : () => unawaited(_exportUnresolvedGroupedJson()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF3A5167)),
                ),
                child: const Text('Export Unresolved JSON'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _isBusy
                    ? null
                    : () => unawaited(_copyUnresolvedGroupedJson()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8CFFB2),
                  side: const BorderSide(color: Color(0xFF2B7A4B)),
                ),
                child: const Text('Copy Unresolved JSON'),
              ),
              if (_isBusy) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildLaunchControlPanel(),
          const SizedBox(height: 8),
          _buildOperationsPanel(),
          const SizedBox(height: 8),
          _buildAcceptancePanel(),
          const SizedBox(height: 8),
          Text(
            _unresolvedSummary,
            style: const TextStyle(
              color: Color(0xFF9EB1C4),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText,
            style: TextStyle(
              color: _statusText.toLowerCase().contains('failed')
                  ? const Color(0xFFFF8A80)
                  : const Color(0xFF8CFFB2),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _previewBadge(text: _identityPreviewText),
              const SizedBox(width: 10),
              _previewBadge(text: _availabilityPreviewText),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Upload Audit Log',
            style: TextStyle(
              color: Color(0xFFFFC400),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _buildAuditLogPanel(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                _jsonEditor(
                  title: 'Identity Bulk Payload',
                  schemaHint:
                      'Expected: providers -> odds-api -> {source_player_id: {...}}',
                  controller: _identityController,
                  onUpload: _uploadIdentityPayload,
                  onValidate: () {
                    _validateJsonPayload(
                      controller: _identityController,
                      label: 'Identity',
                      requiredTopLevelKey: 'providers',
                    );
                  },
                  onLoadFile: () {
                    unawaited(
                      _loadPayloadFromFile(
                        controller: _identityController,
                        label: 'Identity',
                        requiredTopLevelKey: 'providers',
                      ),
                    );
                  },
                  mode: _identityMode,
                  onModeChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _identityMode = value;
                    });
                  },
                ),
                const SizedBox(width: 12),
                _jsonEditor(
                  title: 'Availability Bulk Payload',
                  schemaHint: 'Expected: players -> {canonical_player: {...}}',
                  controller: _availabilityController,
                  onUpload: _uploadAvailabilityPayload,
                  onValidate: () {
                    _validateJsonPayload(
                      controller: _availabilityController,
                      label: 'Availability',
                      requiredTopLevelKey: 'players',
                    );
                  },
                  onLoadFile: () {
                    unawaited(
                      _loadPayloadFromFile(
                        controller: _availabilityController,
                        label: 'Availability',
                        requiredTopLevelKey: 'players',
                      ),
                    );
                  },
                  mode: _availabilityMode,
                  onModeChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _availabilityMode = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SearchPlayersPage extends StatelessWidget {
  final List<PropData> props;

  const SearchPlayersPage({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final searchController = TextEditingController();
    final unique = <String, PropData>{};
    for (final prop in props) {
      final key = prop.player.trim().toLowerCase();
      if (key.isEmpty) {
        continue;
      }
      unique.putIfAbsent(key, () => prop);
    }
    final players = unique.values.toList()
      ..sort((left, right) => left.player.compareTo(right.player));

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final query = searchController.text.trim().toLowerCase();
        final filtered = players.where((prop) {
          if (query.isEmpty) {
            return true;
          }
          return prop.player.toLowerCase().contains(query) ||
              prop.matchup.toLowerCase().contains(query) ||
              prop.market.toLowerCase().contains(query);
        }).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Players Directory',
                    style: TextStyle(
                      color: Color(0xFFFFC400),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1927),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFFFC400),
                          width: 1.1,
                        ),
                      ),
                      child: TextField(
                        controller: searchController,
                        onChanged: (_) {
                          setLocalState(() {});
                        },
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search players, teams, or markets...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF8191A5),
                            fontSize: 12,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFFFFC400),
                            size: 20,
                          ),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    searchController.clear();
                                    setLocalState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${filtered.length} of ${players.length} players',
                style: const TextStyle(
                  color: Color(0xFF9DB0C4),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1520),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF294052)),
                  ),
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFF1D2B39)),
                    itemBuilder: (context, index) {
                      final prop = filtered[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          prop.player,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${prop.matchup} • ${prop.market} • ${prop.sport}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF9DB0C4),
                            fontSize: 10.5,
                          ),
                        ),
                        trailing: Text(
                          '${prop.confidence}%',
                          style: const TextStyle(
                            color: Color(0xFFFFC400),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PropIntelligenceBrandBadge extends StatelessWidget {
  const PropIntelligenceBrandBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/branding/prop_intelligence_icon.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(
                  Icons.sports,
                  color: AppColors.goldBright,
                  size: 24,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class TopNavigation extends StatelessWidget {
  final AppPage selectedPage;
  final ValueChanged<AppPage> onTabSelected;
  final AppSoundService soundService;
  final Color accentColor;

  const TopNavigation({
    super.key,
    required this.selectedPage,
    required this.onTabSelected,
    required this.soundService,
    required this.accentColor,
  });

  String get _pageHowTo => switch (selectedPage) {
    AppPage.board =>
      'Use the sport, category and prop-site filters to narrow today\'s board. Compare the posted line with the projection, edge and confidence, then choose Over or Under to add a prop to the active slip.',
    AppPage.gameMarkets =>
      'Choose a sport and game, then compare moneyline, spread and total prices across sites. Use the best available number and confirm it again at the sportsbook before playing.',
    AppPage.propBuilder =>
      'Select sports, prop sites and categories, set your minimum edge and confidence, then build. Review the recommended 3-6 leg size and remove or replace any leg before saving the slip.',
    AppPage.watchlist =>
      'Saved slips appear here automatically while they\'re still unresolved. Refresh to update live scoring, and once a slip is marked Won or Lost it moves to Past Slip History.',
    AppPage.pastSlipHistory =>
      'Resolved slips live here. Use All, Won and Lost to filter, and track totals and sportsbook profit across your settled tickets.',
    AppPage.builderPerformance =>
      'Start with 30 days, then filter by sport, site, market or player. Compare slip win rate with individual-leg hit rate and use only meaningful sample sizes when changing your strategy.',
    AppPage.strikeoutProGold =>
      'Use All Props first, then filter by prop site, Over or Under. Compare the pitcher line, projection, edge and confidence; select the recommended side only after confirming the source site and current line.',
    AppPage.evScanner =>
      'Filter the available props, then rank by expected value, fair probability or edge. Open a prop for the calculation details and compare the model\'s fair price with the site\'s offered price before adding it.',
    AppPage.analytics =>
      'Choose a date range and filters to review results. Look for repeatable performance across enough settled picks instead of reacting to a short winning or losing streak.',
    AppPage.lineMovement =>
      'Select a sport or tracked prop and compare its opening, current and closing values. Favor current numbers that still preserve the projected edge and avoid chasing a line after the value disappears.',
    AppPage.intelligenceLab =>
      'Choose a sport, add players or props, then run correlation and scenario tools. Remove individual selections or clear the lab before starting a different game or strategy.',
    AppPage.refereeTracker =>
      'Choose NBA or WNBA, search for an official and compare sample-adjusted whistle rates with the league average. Treat tendencies as context, not a guaranteed prediction.',
    AppPage.scoreboard =>
      'Choose a date or sport to follow upcoming, live and completed games. Use scores and game status to confirm context before evaluating or grading a prop.',
    AppPage.scoreboardWatchlist =>
      'Games selected with WATCH appear here for quick access. Score changes, final winners, overtime and other extended play trigger an in-app alert.',
    AppPage.searchPlayers =>
      'Search a player, open the active research view and compare every available market and site before choosing a prop.',
    AppPage.propAlerts =>
      'Review triggered market conditions, open the affected prop and confirm the latest line before taking action.',
    AppPage.dataAdmin =>
      'Refresh unresolved identities, validate payloads before upload and use Production Acceptance to confirm feeds, quotas and billing are healthy.',
    AppPage.ownerOperations =>
      'Run all checks to refresh production health, review provider and pipeline warnings, and inspect unsettled or questionable grading items.',
    AppPage.propChat =>
      'Join the shared community room using your public username. Keep messages respectful, never post personal information, and use the message menu to report or block abusive content.',
  };

  void _showPageHelp(BuildContext context) {
    unawaited(AppSoundService.instance.play(AppSoundEvent.selection));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: app_colors.AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: app_colors.AppColors.borderGold),
        ),
        title: Row(
          children: [
            const Icon(Icons.school_outlined, color: app_colors.AppColors.gold),
            const SizedBox(width: 10),
            Expanded(child: Text('HOW TO USE $_pageTitle')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            _pageHowTo,
            style: const TextStyle(
              color: app_colors.AppColors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required String label,
    required AppPage page,
    required IconData icon,
    SubscriptionTier? requiredTier,
    bool hasProUpgrade = false,
  }) {
    final selected = selectedPage == page;

    return Tooltip(
      message: switch (page) {
        AppPage.board => 'Browse and compare today’s available props',
        AppPage.gameMarkets =>
          'Compare moneylines, spreads, and game totals across sportsbooks',
        AppPage.scoreboard => 'Follow live, upcoming, and final games',
        AppPage.scoreboardWatchlist =>
          'Quickly follow games selected from the scoreboard',
        AppPage.analytics =>
          'Review analytics and, for owners, manage platform data',
        AppPage.ownerOperations =>
          'Open the private owner production operations center',
        AppPage.lineMovement => 'Track changes across sportsbook lines',
        AppPage.intelligenceLab =>
          'Model correlation, scripts, and historical analogs',
        AppPage.refereeTracker => 'Compare NBA and WNBA officiating tendencies',
        AppPage.propChat => 'Chat with the PROP INTELLIGENCE community',
        _ => label,
      },
      child: InkWell(
        onTap: () => onTabSelected(page),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(11, 15, 11, 13),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: .07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accentColor : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? accentColor
                    : app_colors.AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 30),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: selected ? accentColor : app_colors.AppColors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (requiredTier != null) ...[
                const SizedBox(width: 7),
                _TierBadge(
                  tier: requiredTier,
                  compact: true,
                  hasProUpgrade: hasProUpgrade,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _pageTitle => switch (selectedPage) {
    AppPage.board => 'MARKET BOARD',
    AppPage.gameMarkets => 'GAME MARKETS',
    AppPage.scoreboard => 'LIVE SCOREBOARD',
    AppPage.scoreboardWatchlist => 'SCOREBOARD WATCHLIST',
    AppPage.analytics => 'PERFORMANCE ANALYTICS',
    AppPage.lineMovement => 'LINE MOVEMENT',
    AppPage.intelligenceLab => 'INTELLIGENCE LAB',
    AppPage.refereeTracker => 'REFEREE TRACKER',
    AppPage.searchPlayers => 'PLAYER SEARCH',
    AppPage.propAlerts => 'PROP ALERTS',
    AppPage.propBuilder => 'PROP BUILDER',
    AppPage.watchlist => 'SLIP WATCHER',
    AppPage.pastSlipHistory => 'PAST SLIP HISTORY',
    AppPage.builderPerformance => 'PERFORMANCE',
    AppPage.evScanner => 'EV SCANNER',
    AppPage.strikeoutProGold => 'STRIKEOUT PRO GOLD',
    AppPage.dataAdmin => 'DATA ADMIN',
    AppPage.ownerOperations => 'OWNER OPERATIONS',
    AppPage.propChat => 'PROP CHAT',
  };

  String get _pageSubtitle => switch (selectedPage) {
    AppPage.board => 'Scan today’s markets and compare available value',
    AppPage.gameMarkets =>
      'Compare moneylines, spreads and totals across sportsbooks',
    AppPage.scoreboard => 'Follow live, upcoming and completed games',
    AppPage.scoreboardWatchlist =>
      'Quick-view watched games with live score and result alerts',
    AppPage.analytics => 'Analytics and owner data-management workspace',
    AppPage.lineMovement => 'Monitor number and price changes in real time',
    AppPage.intelligenceLab => 'Stress-test correlation, context and scenarios',
    AppPage.refereeTracker =>
      'Compare sample-adjusted referee tendencies and assignments',
    AppPage.searchPlayers => 'Open focused player and market research',
    AppPage.propAlerts => 'Review monitored conditions and changes',
    AppPage.propBuilder => 'Build a disciplined, research-backed slip',
    AppPage.watchlist =>
      'Track live props, ticket results and sportsbook profit',
    AppPage.pastSlipHistory =>
      'Review resolved slips, win/loss totals and sportsbook profit',
    AppPage.builderPerformance => 'Review outcomes and improve your process',
    AppPage.evScanner => 'Surface estimated positive-value opportunities',
    AppPage.strikeoutProGold =>
      'Rank MLB strikeout over/under opportunities with model transparency',
    AppPage.dataAdmin => 'Manage platform data sources',
    AppPage.ownerOperations =>
      'Monitor production health, issues, queues and grading reviews',
    AppPage.propChat =>
      'Talk props with the community using your public username',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showContext = constraints.maxWidth >= 1150;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              if (showContext) ...[
                Container(
                  width: 4,
                  height: 42,
                  decoration: BoxDecoration(
                    color: app_colors.AppColors.gold,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x88FFC400), blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Open instructions for $_pageTitle',
                  child: InkWell(
                    onTap: () => _showPageHelp(context),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 230,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _pageTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: app_colors.AppColors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: app_colors.AppColors.blue.withValues(
                                    alpha: .12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: app_colors.AppColors.blue.withValues(
                                      alpha: .55,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: app_colors.AppColors.blue,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.help_outline_rounded,
                                size: 14,
                                color: app_colors.AppColors.gold,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pageSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 42,
                  color: app_colors.AppColors.border,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _TopNavScroller(
                  children: [
                    _buildNavItem(
                      label: 'BOARD',
                      page: AppPage.board,
                      icon: Icons.dashboard_customize_outlined,
                    ),
                    const SizedBox(width: 4),
                    _buildNavItem(
                      label: 'SCOREBOARD',
                      page: AppPage.scoreboard,
                      icon: Icons.sports_score_rounded,
                    ),
                    const SizedBox(width: 4),
                    _buildNavItem(
                      label: 'SCORE WATCH',
                      page: AppPage.scoreboardWatchlist,
                      icon: Icons.notifications_active_rounded,
                      requiredTier: SubscriptionTier.edge,
                      hasProUpgrade: true,
                    ),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<int>(
                      valueListenable: PropChatService.unreadCount,
                      builder: (context, unread, _) => _buildNavItem(
                        label: unread > 0 ? 'PROP CHAT ($unread)' : 'PROP CHAT',
                        page: AppPage.propChat,
                        icon: Icons.forum_rounded,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildNavItem(
                      label: 'GAME MARKETS',
                      page: AppPage.gameMarkets,
                      icon: Icons.sports_rounded,
                      requiredTier: SubscriptionTier.core,
                    ),
                    const SizedBox(width: 4),
                    _buildNavItem(
                      label: 'ANALYTICS',
                      page: AppPage.analytics,
                      icon: Icons.analytics_outlined,
                      requiredTier: SubscriptionTier.core,
                      hasProUpgrade: true,
                    ),
                    const SizedBox(width: 4),
                    _buildNavItem(
                      label: 'SLIP WATCHER',
                      page: AppPage.watchlist,
                      icon: Icons.receipt_long_rounded,
                      requiredTier: SubscriptionTier.core,
                      hasProUpgrade: true,
                    ),
                    const SizedBox(width: 4),
                    _buildNavItem(
                      label: 'PAST SLIP HISTORY',
                      page: AppPage.pastSlipHistory,
                      icon: Icons.history_rounded,
                      requiredTier: SubscriptionTier.core,
                      hasProUpgrade: true,
                    ),
                    const SizedBox(width: 4),
                    _buildNavItem(
                      label: 'LINE MOVEMENT',
                      page: AppPage.lineMovement,
                      icon: Icons.stacked_line_chart_rounded,
                      requiredTier: SubscriptionTier.core,
                      hasProUpgrade: true,
                    ),
                    if (AuthManager.instance.sessionState.value.isOwner) ...[
                      const SizedBox(width: 4),
                      _buildNavItem(
                        label: 'OWNER OPS',
                        page: AppPage.ownerOperations,
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: soundService,
                builder: (context, _) => IconButton(
                  key: const ValueKey('global-sound-toggle'),
                  tooltip: soundService.enabled
                      ? 'Mute app sounds'
                      : 'Turn on app sounds',
                  onPressed: () {
                    unawaited(soundService.setEnabled(!soundService.enabled));
                  },
                  style: IconButton.styleFrom(
                    foregroundColor: soundService.enabled
                        ? accentColor
                        : app_colors.AppColors.textMuted,
                    side: BorderSide(
                      color: soundService.enabled
                          ? accentColor.withValues(alpha: .7)
                          : app_colors.AppColors.border,
                    ),
                    backgroundColor: soundService.enabled
                        ? accentColor.withValues(alpha: .08)
                        : Colors.transparent,
                  ),
                  icon: Icon(
                    soundService.enabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopNavScroller extends StatefulWidget {
  const _TopNavScroller({required this.children});

  final List<Widget> children;

  @override
  State<_TopNavScroller> createState() => _TopNavScrollerState();
}

class _TopNavScrollerState extends State<_TopNavScroller> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      key: const ValueKey('top-navigation-scrollbar'),
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      thickness: 4,
      radius: const Radius.circular(99),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
      ),
    );
  }
}

class _BoardSparklinePainter extends CustomPainter {
  const _BoardSparklinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF36B9FF)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * .82)
      ..lineTo(size.width * .12, size.height * .58)
      ..lineTo(size.width * .25, size.height * .70)
      ..lineTo(size.width * .42, size.height * .25)
      ..lineTo(size.width * .57, size.height * .47)
      ..lineTo(size.width * .72, size.height * .18)
      ..lineTo(size.width * .86, size.height * .28)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StatsPanel extends StatelessWidget {
  final int totalProps;
  final String dayOfWeek;
  final String currentTime;
  final String currentDate;
  final String lastUpdated;

  const StatsPanel({
    super.key,
    required this.totalProps,
    required this.dayOfWeek,
    required this.currentTime,
    required this.currentDate,
    required this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    const timeValueStyle = TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      fontFamily: 'Segoe UI',
    );

    final statCards = [
      _buildDashboardStatCard(
        title: 'TOTAL PROPS',
        value: '$totalProps',
        valueStyle: timeValueStyle,
      ),
      _buildDashboardStatCard(
        title: 'DAY OF WEEK',
        value: dayOfWeek,
        valueStyle: timeValueStyle,
      ),
      _buildDashboardStatCard(
        title: 'CURRENT TIME',
        value: currentTime,
        valueStyle: timeValueStyle,
      ),
      _buildDashboardStatCard(
        title: 'LAST UPDATED',
        value: lastUpdated,
        subtitle: currentDate,
        trailing: lastUpdated == 'Not updated' ? null : 'LIVE',
        valueStyle: timeValueStyle,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: statCards.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 7,
          mainAxisExtent: 122,
        ),
        itemBuilder: (context, index) {
          return statCards[index];
        },
      ),
    );
  }

  Widget _buildDashboardStatCard({
    required String title,
    required String value,
    String? subtitle,
    String? trailing,
    TextStyle? valueStyle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF081723),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B6813), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFC400).withValues(alpha: 0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF201A06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF8B6813)),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFC400),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style:
                        valueStyle ??
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailing,
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF7E8B99), fontSize: 8),
            ),
          ],
        ],
      ),
    );
  }
}

class PropAlertData {
  const PropAlertData({
    required this.sport,
    required this.title,
    required this.message,
    required this.edge,
    required this.book,
    required this.time,
  });

  final String sport;
  final String title;
  final String message;
  final int edge;
  final String book;
  final String time;
}

class _PropAlertCard extends StatelessWidget {
  const _PropAlertCard({required this.alert});

  final PropAlertData alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1C2B).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFC72C).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC72C),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  alert.sport,
                  style: const TextStyle(
                    color: Color(0xFF06111C),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                alert.time,
                style: const TextStyle(color: Color(0xFF9DAEC0), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            alert.message,
            style: const TextStyle(
              color: Color(0xFFC9D4DF),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              Text(
                'Edge: ${alert.edge}%',
                style: const TextStyle(
                  color: Color(0xFFFFC72C),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Book: ${alert.book}',
                style: const TextStyle(
                  color: Color(0xFFFFC72C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PropAlertsPage extends StatelessWidget {
  const PropAlertsPage({super.key, required this.alerts});

  final List<PropAlertData> alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: Color(0xFFFFC72C),
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'PROP ALERTS',
                style: TextStyle(
                  color: Color(0xFFFFC72C),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${alerts.length} alerts',
                style: const TextStyle(
                  color: Color(0xFF9DAEC0),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...alerts.map((alert) => _PropAlertCard(alert: alert)),
        ],
      ),
    );
  }
}

class FilterBar extends StatefulWidget {
  final String selectedSite;
  final ValueChanged<String> onSelectSite;
  final VoidCallback onReset;

  const FilterBar({
    super.key,
    required this.selectedSite,
    required this.onSelectSite,
    required this.onReset,
  });

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  final ScrollController _siteHorizontalController = ScrollController();

  @override
  void dispose() {
    _siteHorizontalController.dispose();
    super.dispose();
  }

  static const List<String> _siteTabs = [
    'ALL',
    'FANDUEL',
    'DRAFTKINGS',
    'PRIZEPICKS',
    'UNDERDOG',
    'SLEEPER',
  ];

  Widget _buildSiteTab(String site) {
    final selected = widget.selectedSite == site;
    return InkWell(
      onTap: () {
        widget.onSelectSite(site);
      },
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF302A14) : const Color(0xFF0C1C2A),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? const Color(0xFFFFC400) : const Color(0xFF294052),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          site,
          style: TextStyle(
            color: selected ? const Color(0xFFFFC400) : Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return InkWell(
      onTap: widget.onReset,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0C1C2A),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF294052)),
        ),
        child: const Text(
          'RESET',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Scrollbar(
        controller: _siteHorizontalController,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _siteHorizontalController,
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              ..._siteTabs.map(
                (site) => Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: _buildSiteTab(site),
                ),
              ),
              _buildResetButton(),
            ],
          ),
        ),
      ),
    );
  }
}

// TODO: Reconnect this curated preview dataset to the public demo experience.
// ignore: unused_element
List<PropData> _boardPreviewProps() {
  const rows = <Map<String, dynamic>>[
    {
      'id': 'preview-jokic',
      'player': 'Nikola Jokic',
      'sport': 'NBA',
      'matchup': 'DEN @ MIN',
      'sportsbook': 'PRIZEPICKS',
      'market': 'POINTS',
      'line': 25.5,
      'projection': 27.8,
      'edge': 12.45,
      'confidence': 68,
      'pick': 'OVER',
      'pick_text': 'OVER 25.5',
      'recommended_side': 'OVER',
      'over_odds': 1.85,
      'under_odds': 1.85,
      'player_image': 'assets/players/nikola_jokic.png',
      'display_time': 'Today • 8:00 PM',
    },
    {
      'id': 'preview-shai',
      'player': 'Shai Gilgeous-Alexander',
      'sport': 'NBA',
      'matchup': 'OKC @ DAL',
      'sportsbook': 'UNDERDOG',
      'market': 'POINTS',
      'line': 29.5,
      'projection': 31.6,
      'edge': 9.31,
      'confidence': 64,
      'pick': 'OVER',
      'pick_text': 'OVER 29.5',
      'recommended_side': 'OVER',
      'over_odds': 1.90,
      'under_odds': 1.80,
      'player_image':
          'https://cdn.nba.com/headshots/nba/latest/1040x760/1628983.png',
      'display_time': 'Today • 8:30 PM',
    },
    {
      'id': 'preview-luka',
      'player': 'Luka Doncic',
      'sport': 'NBA',
      'matchup': 'LAL @ GS',
      'sportsbook': 'FANDUEL',
      'market': 'ASSISTS',
      'line': 8.5,
      'projection': 7.9,
      'edge': 8.72,
      'confidence': 63,
      'pick': 'UNDER',
      'pick_text': 'UNDER 8.5',
      'recommended_side': 'UNDER',
      'over_odds': 1.88,
      'under_odds': 1.88,
      'player_image':
          'https://cdn.nba.com/headshots/nba/latest/1040x760/1629029.png',
      'display_time': 'Today • 10:00 PM',
    },
    {
      'id': 'preview-aja',
      'player': "A'ja Wilson",
      'sport': 'WNBA',
      'matchup': 'LVA @ PHX',
      'sportsbook': 'SLEEPER',
      'market': 'POINTS',
      'line': 19.5,
      'projection': 21.7,
      'edge': 11.21,
      'confidence': 78,
      'pick': 'OVER',
      'pick_text': 'OVER 19.5',
      'recommended_side': 'OVER',
      'over_odds': 1.92,
      'under_odds': 1.78,
      'player_image': 'assets/players/a_ja_wilson.png',
      'display_time': 'Today • 9:00 PM',
    },
    {
      'id': 'preview-allen',
      'player': 'Josh Allen',
      'sport': 'NFL',
      'matchup': 'BUF @ KC',
      'sportsbook': 'PRIZEPICKS',
      'market': 'PASS YARDS',
      'line': 275.5,
      'projection': 289.3,
      'edge': 7.18,
      'confidence': 62,
      'pick': 'OVER',
      'pick_text': 'OVER 275.5',
      'recommended_side': 'OVER',
      'over_odds': 1.86,
      'under_odds': 1.84,
      'player_image': 'assets/players/josh_allen.png',
      'display_time': 'Sun 1:00 PM',
    },
    {
      'id': 'preview-burnes',
      'player': 'Corbin Burnes',
      'sport': 'MLB',
      'matchup': 'BAL @ NYY',
      'sportsbook': 'FANDUEL',
      'market': 'STRIKEOUTS',
      'line': 7.5,
      'projection': 6.8,
      'edge': 9.74,
      'confidence': 66,
      'pick': 'UNDER',
      'pick_text': 'UNDER 7.5',
      'recommended_side': 'UNDER',
      'over_odds': 1.80,
      'under_odds': 1.95,
      'player_image':
          'https://a.espncdn.com/i/headshots/mlb/players/full/39878.png',
      'display_time': 'Today • 7:05 PM',
    },
    {
      'id': 'preview-scottie',
      'player': 'Scottie Scheffler',
      'sport': 'PGA',
      'matchup': 'PGA Championship',
      'sportsbook': 'UNDERDOG',
      'market': 'TOURNAMENT',
      'line': 1.0,
      'projection': 19.4,
      'edge': 10.32,
      'confidence': 70,
      'pick': 'OVER',
      'pick_text': 'WINNER',
      'recommended_side': 'OVER',
      'over_odds': 1.95,
      'under_odds': 1.85,
      'player_image':
          'https://a.espncdn.com/i/headshots/golf/players/full/9478.png',
      'display_time': 'May 18 • 10:20 AM',
    },
    {
      'id': 'preview-israel',
      'player': 'Israel Adesanya',
      'sport': 'UFC',
      'matchup': 'ADESANYA vs STRICKLAND 2',
      'sportsbook': 'DRAFT PICKS',
      'market': 'FIGHT TO GO',
      'line': 5.0,
      'projection': 4.3,
      'edge': 6.55,
      'confidence': 52,
      'pick': 'UNDER',
      'pick_text': 'UNDER 5.0',
      'recommended_side': 'UNDER',
      'over_odds': 2.05,
      'under_odds': 1.70,
      'player_image':
          'https://a.espncdn.com/i/headshots/mma/players/full/4285679.png',
      'display_time': 'Sat 10:00 PM',
    },
  ];
  return rows.map(PropData.fromJson).toList(growable: false);
}

class PropGrid extends StatefulWidget {
  final List<SlipSelection> selections;
  final void Function(PropData prop, PickSide side) onSelect;
  final String sportFilter;
  final String displaySportFilter;
  final String selectedSite;
  final String selectedCategory;
  final String selectedSide;
  final String selectedTier;
  final int minConfidence;
  final String sortBy;
  final String searchQuery;
  final void Function(List<PropData>, int, int, Map<String, int>)?
  onPropsLoaded;
  final ValueChanged<PropData>? onPropFocused;

  const PropGrid({
    super.key,
    required this.selections,
    required this.onSelect,
    required this.sportFilter,
    required this.displaySportFilter,
    required this.selectedSite,
    required this.selectedCategory,
    required this.selectedSide,
    required this.selectedTier,
    required this.minConfidence,
    required this.sortBy,
    required this.searchQuery,
    this.onPropsLoaded,
    this.onPropFocused,
  });

  @override
  State<PropGrid> createState() => _PropGridState();
}

class _PreparedProp {
  final PropData prop;
  final String normalizedSport;
  final String normalizedSite;
  final String searchText;

  const _PreparedProp({
    required this.prop,
    required this.normalizedSport,
    required this.normalizedSite,
    required this.searchText,
  });
}

List<PropData> deprioritizeSoccerForAllSports(
  List<PropData> props, {
  required String selectedSport,
}) {
  if (selectedSport.trim().toUpperCase() != 'ALL' || props.length < 2) {
    return props;
  }
  final otherSports = <PropData>[];
  final soccer = <PropData>[];
  for (final prop in props) {
    final sport = prop.sport.trim().toUpperCase();
    if (sport == 'SOCCER' || sport.startsWith('SOCCER_')) {
      soccer.add(prop);
    } else {
      otherSports.add(prop);
    }
  }
  if (otherSports.isEmpty || soccer.isEmpty) return props;
  return [...otherSports, ...soccer];
}

DateTime? propScheduledStart(PropData prop) {
  final raw = prop.startTimeUtc.isNotEmpty
      ? prop.startTimeUtc
      : prop.gameStartTime;
  return DateTime.tryParse(raw);
}

List<PropData> activePropsInChronologicalOrder(Iterable<PropData> props) {
  final active = props.where((prop) => !prop.gameHasStarted).toList();
  active.sort((left, right) {
    final leftStart = propScheduledStart(left);
    final rightStart = propScheduledStart(right);
    if (leftStart == null && rightStart == null) {
      final player = left.player.compareTo(right.player);
      return player != 0 ? player : left.market.compareTo(right.market);
    }
    if (leftStart == null) return 1;
    if (rightStart == null) return -1;
    final start = leftStart.compareTo(rightStart);
    if (start != 0) return start;
    final player = left.player.compareTo(right.player);
    return player != 0 ? player : left.market.compareTo(right.market);
  });
  return active;
}

bool shouldRenderCachedPropsOnLaunch(
  List<PropData> props, {
  required String selectedSport,
}) {
  if (props.isEmpty) return false;
  if (selectedSport.trim().toUpperCase() != 'ALL') return true;
  return props.any((prop) {
    final sport = prop.sport.trim().toUpperCase();
    return sport != 'SOCCER' && !sport.startsWith('SOCCER_');
  });
}

class _PropGridState extends State<PropGrid> with WidgetsBindingObserver {
  static const int _visiblePropStep = 24;
  final ApiService _apiService = ApiService();
  late Future<List<PropData>> _propsFuture;
  List<_PreparedProp> _preparedProps = const [];
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  Timer? _autoRetryTimer;
  Timer? _expiryTimer;
  Timer? _lineRefreshTimer;
  bool _isLiveRefreshing = false;
  int _automaticRetryCount = 0;
  int _visiblePropLimit = _visiblePropStep;
  final Set<String> _favoritePropIds = <String>{};

  String get _queryKey => [
    widget.sportFilter,
    widget.selectedSite,
    widget.selectedCategory,
    widget.selectedSide,
    widget.selectedTier,
    widget.minConfidence.toString(),
    widget.sortBy,
    widget.searchQuery,
  ].join('|');

  Future<void> _showMetricMeaningOverlay({
    required String title,
    required String description,
    required IconData icon,
  }) async {
    if (!mounted) {
      return;
    }
    await _showPropMetricInfoDialog(
      context,
      title: title,
      description: description,
      icon: icon,
    );
  }

  String _normalizeSite(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('SLEEPER')) {
      return 'SLEEPER';
    }
    if (normalized.contains('PRIZEPICKS')) {
      return 'PRIZEPICKS';
    }
    if (normalized.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    if (normalized.contains('DRAFTPICKS')) {
      return 'DRAFT PICKS';
    }
    if (normalized.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (normalized.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    return normalized;
  }

  String _normalizeSport(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('UFC') ||
        normalized.contains('MMA') ||
        normalized.contains('ULTIMATEFIGHTING')) {
      return 'UFC';
    }
    if (normalized.contains('WNBA')) {
      return 'WNBA';
    }
    if (normalized.contains('NBA')) {
      return 'NBA';
    }
    if (normalized.contains('NFL') || normalized.contains('FOOTBALL')) {
      return 'NFL';
    }
    if (normalized.contains('MLB') || normalized.contains('BASEBALL')) {
      return 'MLB';
    }
    if (normalized.contains('SOCCER') ||
        normalized.contains('EPL') ||
        normalized.contains('MLS')) {
      return 'SOCCER';
    }
    if (normalized.contains('TENNIS') ||
        normalized.contains('ATP') ||
        normalized.contains('WTA')) {
      return 'TENNIS';
    }
    if (normalized.contains('PGA') || normalized.contains('GOLF')) {
      return 'PGA';
    }
    return normalized;
  }

  String _propMarket(PropData prop) {
    return (prop.market.isNotEmpty
            ? prop.market
            : prop.marketName.isNotEmpty
            ? prop.marketName
            : prop.statType.isNotEmpty
            ? prop.statType
            : prop.category.isNotEmpty
            ? prop.category
            : prop.propType.isNotEmpty
            ? prop.propType
            : prop.displayMarket.isNotEmpty
            ? prop.displayMarket
            : prop.marketKey.isNotEmpty
            ? prop.marketKey
            : '')
        .toString();
  }

  bool _containsAny(String value, List<String> matches) {
    return matches.any(value.contains);
  }

  String _categoryFromApi(PropData prop) {
    final normalized = prop.category.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }

    final sport = _normalizeSport(prop.sport);
    if (sport == 'NBA' || sport == 'WNBA') {
      switch (normalized) {
        case 'points':
          return 'POINTS';
        case 'rebounds':
          return 'REBOUNDS';
        case 'assists':
          return 'ASSISTS';
        case 'pra':
          return 'PRA';
        case 'blocks':
          return 'BLOCKS';
        case 'steals':
          return 'STEALS';
        case '3-pointers':
          return '3-POINTERS MADE';
      }
    }
    if (sport == 'NFL') {
      switch (normalized) {
        case 'passing yards':
          return 'PASSING YARDS';
        case 'rushing yards':
          return 'RUSHING YARDS';
        case 'receiving yards':
          return 'RECEIVING YARDS';
        case 'touchdowns':
          return 'TOTAL TOUCHDOWNS';
        case 'receptions':
          return 'RECEPTIONS';
        case 'rushing attempts':
          return 'PASS ATTEMPTS';
        case 'completions':
          return 'COMPLETIONS';
      }
    }
    if (sport == 'SOCCER') {
      switch (normalized) {
        case 'shots':
          return 'SHOTS';
        case 'shots on target':
          return 'SHOTS ON TARGET';
        case 'goals':
          return 'GOALS';
        case 'assists':
          return 'ASSISTS';
      }
    }
    if (sport == 'MLB') {
      switch (normalized) {
        case 'strikeouts':
          return 'PITCHER STRIKEOUTS';
        case 'outs recorded':
          return 'PITCHER OUTS';
        case 'hits allowed':
          return 'HITS ALLOWED';
        case 'hits':
          return 'HITS';
        case 'home runs':
          return 'HOME RUNS';
        case 'rbis':
          return 'RBIS';
        case 'total bases':
          return 'TOTAL BASES';
      }
    }
    if (sport == 'TENNIS') {
      switch (normalized) {
        case 'aces':
          return 'ACES';
        case 'games won':
          return 'TOTAL GAMES WON';
      }
    }
    if (sport == 'PGA') {
      switch (normalized) {
        case 'birdies':
          return 'BIRDIES OR BETTER';
        case 'fairways':
          return 'FAIRWAYS HIT';
        case 'greens':
          return 'GREENS IN REGULATION';
      }
    }
    if (sport == 'UFC') {
      switch (normalized) {
        case 'significant strikes':
          return 'SIGNIFICANT STRIKES';
        case 'takedowns':
          return 'TAKEDOWNS';
        case 'knockdowns':
          return 'KNOCKDOWNS';
        case 'submissions':
          return 'SUBMISSION ATTEMPTS';
        case 'fight time':
          return 'FIGHT TIME';
      }
    }
    return '';
  }

  String _marketCategory(PropData prop) {
    final backendCategory = _categoryFromApi(prop);
    if (backendCategory.isNotEmpty) {
      return backendCategory;
    }

    final sport = _normalizeSport(prop.sport);
    final raw = _propMarket(prop)
        .toUpperCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (sport == 'NBA' || sport == 'WNBA') {
      if (_containsAny(raw, [
        'PRA',
        'PTS REB AST',
        'POINTS REBOUNDS ASSISTS',
        'POINTS + REBOUNDS + ASSISTS',
      ])) {
        return 'PRA';
      }
      if (_containsAny(raw, [
        '3 POINTERS MADE',
        'THREE POINTERS MADE',
        '3PM',
        'MADE THREES',
      ])) {
        return '3-POINTERS MADE';
      }
      if (_containsAny(raw, ['POINTS', 'PLAYER POINTS'])) {
        return 'POINTS';
      }
      if (_containsAny(raw, ['REBOUNDS', 'PLAYER REBOUNDS'])) {
        return 'REBOUNDS';
      }
      if (_containsAny(raw, ['ASSISTS', 'PLAYER ASSISTS'])) {
        return 'ASSISTS';
      }
      if (raw.contains('BLOCK')) {
        return 'BLOCKS';
      }
      if (raw.contains('STEAL')) {
        return 'STEALS';
      }
    }
    if (sport == 'NFL') {
      if (raw.contains('PASSING YARD')) {
        return 'PASSING YARDS';
      }
      if (raw.contains('RUSHING YARD')) {
        return 'RUSHING YARDS';
      }
      if (raw.contains('RECEIVING YARD')) {
        return 'RECEIVING YARDS';
      }
      if (_containsAny(raw, [
        'TOTAL TOUCHDOWNS',
        'ANYTIME TOUCHDOWN',
        'TOUCHDOWNS',
        'TOTAL TDS',
      ])) {
        return 'TOTAL TOUCHDOWNS';
      }
      if (raw.contains('RECEPTION')) {
        return 'RECEPTIONS';
      }
      if (raw.contains('PASS ATTEMPT')) {
        return 'PASS ATTEMPTS';
      }
      if (_containsAny(raw, ['PASS COMPLETION', 'COMPLETIONS'])) {
        return 'COMPLETIONS';
      }
    }
    if (sport == 'SOCCER') {
      if (_containsAny(raw, ['SHOTS ON TARGET', 'SHOT ON TARGET', 'SOT'])) {
        return 'SHOTS ON TARGET';
      }
      if (raw.contains('SHOT')) {
        return 'SHOTS';
      }
      if (raw.contains('GOAL') && !raw.contains('GOALKEEPER')) {
        return 'GOALS';
      }
      if (raw.contains('ASSIST')) {
        return 'ASSISTS';
      }
      if (_containsAny(raw, [
        'PASSES ATTEMPTED',
        'PASS ATTEMPTS',
        'TOTAL PASSES',
      ])) {
        return 'PASSES ATTEMPTED';
      }
      if (raw.contains('SAVE')) {
        return 'SAVES';
      }
      if (raw.contains('TACKLE')) {
        return 'TACKLES';
      }
    }
    if (sport == 'MLB') {
      if (_containsAny(raw, [
        'PITCHER STRIKEOUTS',
        'PITCHING STRIKEOUTS',
        'STRIKEOUTS THROWN',
        'PITCHER KS',
      ])) {
        return 'PITCHER STRIKEOUTS';
      }
      if (_containsAny(raw, [
        'PITCHER OUTS',
        'OUTS RECORDED',
        'PITCHING OUTS',
      ])) {
        return 'PITCHER OUTS';
      }
      if (raw.contains('HITS ALLOWED')) {
        return 'HITS ALLOWED';
      }
      if (_containsAny(raw, ['HOME RUNS', 'HOME RUN'])) {
        return 'HOME RUNS';
      }
      if (_containsAny(raw, ['RBIS', 'RBI', 'RUNS BATTED IN'])) {
        return 'RBIS';
      }
      if (raw.contains('TOTAL BASE')) {
        return 'TOTAL BASES';
      }
      if (_containsAny(raw, ['PLAYER HITS', 'HITS'])) {
        return 'HITS';
      }
    }
    if (sport == 'TENNIS') {
      if (raw.contains('ACE')) {
        return 'ACES';
      }
      if (_containsAny(raw, ['TOTAL GAMES WON', 'GAMES WON', 'PLAYER GAMES'])) {
        return 'TOTAL GAMES WON';
      }
      if (_containsAny(raw, ['MATCH WINNER', 'MONEYLINE', 'TO WIN MATCH'])) {
        return 'MATCH WINNER';
      }
    }
    if (sport == 'PGA') {
      if (_containsAny(raw, ['BIRDIES OR BETTER', 'BIRDIES', 'BIRDIE'])) {
        return 'BIRDIES OR BETTER';
      }
      if (_containsAny(raw, ['ROUND SCORE', 'STROKES', 'ROUND STROKES'])) {
        return 'ROUND SCORE';
      }
      if (raw.contains('FAIRWAY')) {
        return 'FAIRWAYS HIT';
      }
      if (_containsAny(raw, ['GREENS IN REGULATION', 'GIR'])) {
        return 'GREENS IN REGULATION';
      }
      if (raw.contains('HOLES PLAYED')) {
        return 'HOLES PLAYED';
      }
      if (_containsAny(raw, ['MAKE CUT', 'MADE CUT', 'TO MAKE THE CUT'])) {
        return 'MAKE CUT';
      }
    }
    if (sport == 'UFC') {
      if (_containsAny(raw, [
        'SIGNIFICANT STRIKES',
        'SIG STRIKES',
        'SIG. STRIKES',
        'SIGNIFICANT STRIKES LANDED',
      ])) {
        return 'SIGNIFICANT STRIKES';
      }
      if (_containsAny(raw, [
        'TOTAL STRIKES',
        'STRIKES LANDED',
        'TOTAL STRIKES LANDED',
      ])) {
        return 'TOTAL STRIKES';
      }
      if (_containsAny(raw, [
        'TAKEDOWN ATTEMPTS',
        'TAKEDOWNS ATTEMPTED',
        'TD ATTEMPTS',
      ])) {
        return 'TAKEDOWN ATTEMPTS';
      }
      if (_containsAny(raw, ['TAKEDOWNS', 'TAKEDOWNS LANDED', 'TD LANDED'])) {
        return 'TAKEDOWNS';
      }
      if (_containsAny(raw, [
        'CONTROL TIME',
        'GROUND CONTROL TIME',
        'TOP CONTROL TIME',
      ])) {
        return 'CONTROL TIME';
      }
      if (_containsAny(raw, ['KNOCKDOWNS', 'KNOCKDOWNS LANDED'])) {
        return 'KNOCKDOWNS';
      }
      if (_containsAny(raw, ['SUBMISSION ATTEMPTS', 'SUB ATTEMPTS'])) {
        return 'SUBMISSION ATTEMPTS';
      }
      if (_containsAny(raw, [
        'FIGHT TIME',
        'TOTAL FIGHT TIME',
        'TIME OF FIGHT',
      ])) {
        return 'FIGHT TIME';
      }
      if (_containsAny(raw, [
        'TOTAL ROUNDS',
        'ROUNDS COMPLETED',
        'FIGHT ROUNDS',
      ])) {
        return 'ROUNDS';
      }
      if (_containsAny(raw, [
        'FIGHT WINNER',
        'MATCH WINNER',
        'MONEYLINE',
        'TO WIN',
      ])) {
        return 'FIGHT WINNER';
      }
      if (_containsAny(raw, [
        'METHOD OF VICTORY',
        'WIN METHOD',
        'KO TKO',
        'SUBMISSION',
        'DECISION',
      ])) {
        return 'METHOD OF VICTORY';
      }
    }
    return 'OTHER';
  }

  Widget _playerPlaceholder(String player, {required double size}) {
    final initial = player.trim().isEmpty
        ? '?'
        : player.trim().substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: AppColors.panel,
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.gold,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _fastPlayerPhoto(PropData prop, {double size = 44}) {
    final imagePath = resolvePlayerImagePath(prop.imagePath);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheSize = (size * pixelRatio * 2.0).round().clamp(128, 512);
    final isNetwork =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');
    if (!isNetwork) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) {
          final officialUrl = _officialMlbHeadshot(prop.player);
          if (officialUrl != null) {
            return CachedNetworkImage(
              imageUrl: officialUrl,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              memCacheWidth: cacheSize,
              memCacheHeight: cacheSize,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) =>
                  _playerPlaceholder(prop.player, size: size),
              errorWidget: (_, _, _) =>
                  _playerPlaceholder(prop.player, size: size),
            );
          }
          return _playerPlaceholder(prop.player, size: size);
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: imagePath,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      memCacheWidth: cacheSize,
      memCacheHeight: cacheSize,
      placeholder: (context, url) {
        return _playerPlaceholder(prop.player, size: size);
      },
      errorWidget: (context, url, error) {
        return _playerPlaceholder(prop.player, size: size);
      },
    );
  }

  String _propGameDayDate(PropData prop) {
    final rawStartTime = prop.startTimeUtc.isNotEmpty
        ? prop.startTimeUtc
        : prop.gameStartTime;
    if (rawStartTime.isEmpty) {
      return '';
    }

    final parsed = DateTime.tryParse(rawStartTime);
    if (parsed == null) {
      return '';
    }

    final local = parsed.toLocal();
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${days[local.weekday - 1]} ${months[local.month - 1]} ${local.day}';
  }

  String _propDateTimeLabel(PropData prop) {
    final date = _propGameDayDate(prop);
    final time = prop.localGameTimeDisplay.trim();
    if (date.isEmpty && time.isEmpty) return 'DATE & TIME TBD';
    if (date.isEmpty) return time;
    if (time.isEmpty) return date;
    return '$date  •  $time';
  }

  void _handleCardSelection(PropData prop, PickSide side) {
    widget.onSelect(prop, side);
  }

  Widget _buildPortraitPropCard(PropData prop, PickSide? selectedSide) {
    final hasProAccess = canShowSystemRecommendation(
      hasEdgeAccess: AuthManager.instance.sessionState.value.hasEdgeAccess,
    );
    final suggestedSide = prop.proSuggestedSide;
    final hasModelRecommendation =
        hasProAccess && prop.proSuggestionUsesModel && suggestedSide != null;
    final hasHistoricalLean =
        hasProAccess &&
        prop.proSuggestionUsesHistoricalStats &&
        suggestedSide != null;
    final hasMarketLean =
        hasProAccess && prop.proSuggestionUsesMarket && suggestedSide != null;
    final hasSuggestion =
        hasModelRecommendation || hasHistoricalLean || hasMarketLean;
    final PickSide? advisedSide = !hasSuggestion
        ? null
        : suggestedSide == 'UNDER'
        ? PickSide.under
        : PickSide.over;
    final market = _marketCategory(prop);
    final confidence = prop.confidence.clamp(0, 100);
    final calculatedEdge = prop.calculatedEdge;

    Widget intelligenceMetric(String label, String value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 6,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    Widget sideButton(PickSide side) {
      final selected = side == selectedSide;
      final advised = hasSuggestion && side == advisedSide;
      final label = side == PickSide.over ? 'OVER' : 'UNDER';

      // Green for OVER, Red for UNDER when selected
      final selectedColor = side == PickSide.over
          ? const Color(0xFF4CAF50) // Green
          : const Color(0xFFEF5350); // Red

      return Expanded(
        child: OutlinedButton(
          onPressed: () => _handleCardSelection(prop, side),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: selected
                ? Colors.white
                : (advised ? AppColors.gold : Colors.white),
            backgroundColor: selected
                ? selectedColor.withValues(alpha: .85)
                : (advised
                      ? AppColors.gold.withValues(alpha: .16)
                      : const Color(0xFF091620)),
            side: BorderSide(
              color: selected
                  ? selectedColor
                  : (advised ? AppColors.gold : AppColors.border),
              width: selected ? 2 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              advised
                  ? hasModelRecommendation
                        ? '$label  •  SYSTEM PICK'
                        : '$label  •  INFO LEAN'
                  : label,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1823), Color(0xFF06111A)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  market,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.gold),
                ),
                child: const Text(
                  'E+',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              InkWell(
                onTap: () => setState(() {
                  if (!_favoritePropIds.add(prop.id)) {
                    _favoritePropIds.remove(prop.id);
                  }
                }),
                child: Icon(
                  _favoritePropIds.contains(prop.id)
                      ? Icons.star
                      : Icons.star_border,
                  color: AppColors.gold,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: AppColors.gold,
                size: 12,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _propDateTimeLabel(prop),
                  key: ValueKey('prop-game-date-time-${prop.id}'),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.gold),
            ),
            child: Text(
              hasModelRecommendation
                  ? '★ SYSTEM PICK: ${advisedSide == PickSide.over ? 'OVER' : 'UNDER'}'
                  : hasHistoricalLean
                  ? 'STATS LEAN: ${advisedSide == PickSide.over ? 'OVER' : 'UNDER'}'
                  : hasMarketLean
                  ? 'MARKET LEAN: ${advisedSide == PickSide.over ? 'OVER' : 'UNDER'}'
                  : hasProAccess
                  ? 'NO QUALIFIED LEAN'
                  : 'PRO MODEL SIGNAL',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .055),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: .28)),
            ),
            child: Row(
              children: [
                intelligenceMetric(
                  'EDGE',
                  hasProAccess && calculatedEdge != null
                      ? '+${calculatedEdge.toStringAsFixed(2)}'
                      : '--',
                ),
                intelligenceMetric(
                  'PROJECTION',
                  hasProAccess && prop.projection != null
                      ? prop.projection!.toStringAsFixed(1)
                      : '--',
                ),
                intelligenceMetric(
                  'HIT RATE',
                  hasProAccess && confidence > 0 ? '$confidence%' : '--',
                ),
                intelligenceMetric(
                  'TIER',
                  hasProAccess ? prop.tier.toUpperCase() : '--',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasModelRecommendation
                ? prop.projectionModelVersion == 'baseline-v2'
                      ? 'Baseline historical model • ${prop.projectionSampleSize} games • ${prop.historicalHitRate ?? '--'}% historical hit rate'
                      : 'Verified provider projection • $confidence% confidence'
                : hasHistoricalLean
                ? '${prop.projectionLabel.isEmpty ? 'Historical stats' : prop.projectionLabel} • ${prop.projectionSampleSize} games • informational only'
                : hasMarketLean
                ? 'Based on current market pricing (${prop.marketLeanPercentage ?? 50}%) • not an AI projection'
                : !hasProAccess
                ? 'Upgrade to Pro for projections and edge metrics'
                : prop.recommendationUnavailableReason ==
                      'player_identity_unresolved'
                ? 'Player identity verification pending'
                : prop.recommendationUnavailableReason ==
                      'model_signal_below_threshold'
                ? 'Baseline projection available • no qualified edge'
                : 'Projection data pending',
            style: const TextStyle(color: AppColors.muted, fontSize: 7.5),
          ),
          if (hasModelRecommendation &&
              prop.recommendationExplanation.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              prop.recommendationExplanation,
              style: const TextStyle(color: Color(0xFFB8C7D6), fontSize: 7.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 3),
          Text(
            hasProAccess && prop.projectionModelVersion == 'baseline-v2'
                ? 'Experimental until 100 pregame predictions are graded'
                : hasProAccess
                ? 'Live market model'
                : 'Pro intelligence is locked',
            style: const TextStyle(color: AppColors.muted, fontSize: 7),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 66,
              height: 66,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold),
              ),
              child: ClipOval(child: _fastPlayerPhoto(prop, size: 62)),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.gold),
              ),
              child: Text(
                prop.sportsbook.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            prop.player,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            prop.matchup,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 7),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '${prop.line.toStringAsFixed(1)} PLAYER $market',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasProAccess && calculatedEdge != null
                        ? calculatedEdge.toStringAsFixed(2)
                        : '--',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'EDGE',
                    style: TextStyle(color: AppColors.muted, fontSize: 6),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: hasModelRecommendation ? confidence / 100 : 0,
              minHeight: 7,
              color: AppColors.gold,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              sideButton(PickSide.over),
              const SizedBox(width: 8),
              sideButton(PickSide.under),
            ],
          ),
        ],
      ),
    );
  }

  // TODO: Remove after the redesigned production prop card is accepted.
  // ignore: unused_element
  Widget _buildCompactPortraitPropCardOld(
    PropData prop,
    PickSide? selectedSide,
  ) {
    final advisedSide =
        prop.recommendedSide.toUpperCase().contains('UNDER') ||
            prop.pick.toUpperCase() == 'UNDER'
        ? PickSide.under
        : PickSide.over;
    final projection = prop.projection ?? prop.line;
    final overOdds = prop.overOdds ?? 1.85;
    final underOdds = prop.underOdds ?? 1.85;
    final market = _marketCategory(prop);

    String displayOdds(double odds) {
      if (odds.abs() >= 100) {
        final decimal = odds > 0 ? 1 + (odds / 100) : 1 + (100 / odds.abs());
        return decimal.toStringAsFixed(2);
      }
      return odds.toStringAsFixed(2);
    }

    Widget sideButton(PickSide side, double odds) {
      final advised = side == advisedSide;
      final selected = side == selectedSide;
      final isOver = side == PickSide.over;
      return Expanded(
        child: Tooltip(
          message: advised
              ? 'Model advised pick'
              : 'Select ${isOver ? 'OVER' : 'UNDER'}',
          child: OutlinedButton(
            onPressed: prop.dataStale
                ? null
                : () => widget.onSelect(prop, side),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              foregroundColor: selected ? AppColors.gold : Colors.white,
              backgroundColor: selected
                  ? AppColors.gold.withValues(alpha: .18)
                  : const Color(0xFF091620),
              side: BorderSide(
                color: selected ? AppColors.gold : AppColors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isOver ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isOver ? 'OVER' : 'UNDER',
                      style: const TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(displayOdds(odds), style: const TextStyle(fontSize: 7)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1823), Color(0xFF06111A)],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 5),
            child: Row(
              children: [
                Text(
                  prop.sport.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  prop.freshnessLabel,
                  style: TextStyle(
                    color: prop.dataStale
                        ? const Color(0xFFFF6B6B)
                        : AppColors.muted,
                    fontSize: 6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                _sportsbookMark(prop.sportsbook),
                const SizedBox(width: 7),
                InkWell(
                  onTap: () => setState(() {
                    if (!_favoritePropIds.add(prop.id)) {
                      _favoritePropIds.remove(prop.id);
                    }
                  }),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      _favoritePropIds.contains(prop.id)
                          ? Icons.star
                          : Icons.star_border,
                      color: AppColors.gold,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 65,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 58,
                    height: 64,
                    child: _fastPlayerPhoto(prop, size: 58),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prop.player,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            prop.matchup,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 7,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            prop.localGameTimeDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB9C3CD),
                              fontSize: 6.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 4, 9, 1),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        market,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Text(
                      'BEST',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Tooltip(
                      message: advisedSide == PickSide.over
                          ? 'Model suggests OVER'
                          : 'Model suggests UNDER',
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          advisedSide == PickSide.over ? 'O' : 'U',
                          style: const TextStyle(
                            color: Color(0xFF06111B),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'O/U ${prop.line.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    sideButton(PickSide.over, overOdds),
                    const SizedBox(width: 6),
                    sideButton(PickSide.under, underOdds),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _compactMetric(
                        'EDGE',
                        '+${prop.edge.toStringAsFixed(2)}%',
                        const Color(0xFF61E34D),
                      ),
                    ),
                    Expanded(
                      child: _compactMetric(
                        'PROJ',
                        projection.toStringAsFixed(1),
                        Colors.white,
                      ),
                    ),
                    Expanded(
                      child: _compactMetric(
                        'HIT RATE',
                        '${prop.confidence}%',
                        prop.confidence >= 75
                            ? const Color(0xFF61E34D)
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _officialMlbHeadshot(String player) {
    const ids = <String, int>{
      'Drew Cavanaugh': 701852,
      'Drew Gilbert': 687551,
      'Jacob Wilson': 805779,
      'Joey Meneses': 608841,
      'Joey Ortiz': 687401,
      'JT Ginn': 669372,
      'Kyle Teel': 691019,
      'Munetaka Murakami': 808959,
      'Noah Schultz': 702273,
      'Paul Skenes': 694973,
      'Trevor McDonald': 686790,
      'Troy Johnston': 687859,
      'Tyler Soderstrom': 691016,
    };
    final id = ids[player.trim()];
    if (id == null) return null;
    return 'https://img.mlbstatic.com/mlb-photos/image/upload/'
        'w_240,d_people:generic:headshot:67:current.png,q_auto:best/'
        'v1/people/$id/headshot/67/current';
  }

  Widget _compactMetric(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 6),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _sportsbookMark(String sportsbook) {
    final key = sportsbook.toUpperCase();
    final color = key.contains('FANDUEL')
        ? const Color(0xFF1685F8)
        : key.contains('PRIZE')
        ? const Color(0xFF9B5CFF)
        : key.contains('UNDERDOG')
        ? const Color(0xFFFFC400)
        : key.contains('SLEEPER')
        ? const Color(0xFF65D8EF)
        : const Color(0xFF8D4DFF);
    final label = key.contains('FANDUEL')
        ? 'F'
        : key.contains('PRIZE')
        ? 'P'
        : key.contains('UNDERDOG')
        ? 'U'
        : key.contains('SLEEPER')
        ? 'S'
        : 'D';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF06111B),
              fontSize: 7,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          sportsbook,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 7,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // Retained temporarily while the compact reference card is validated.
  // ignore: unused_element
  Widget _buildLegacyPortraitPropCard(PropData prop, PickSide? selectedSide) {
    final side = prop.pick.trim().isEmpty ? 'BEST' : prop.pick.toUpperCase();
    final recommendationText = prop.pickText.trim().isEmpty
        ? 'No Pick'
        : prop.pickText.trim();
    final recommendationSide = prop.recommendedSide.trim().toUpperCase();
    final normalizedRecommendationText = recommendationText.toUpperCase();
    final isUnderPick =
        side == 'UNDER' ||
        recommendationSide.startsWith('UNDER') ||
        normalizedRecommendationText.startsWith('UNDER');
    final sideAccentColor = isUnderPick
        ? Colors.white
        : const Color(0xFFFFD76A);
    final gameDayDate = _propGameDayDate(prop);
    final confidence = prop.confidence.clamp(0, 100).toDouble();
    final lineDisplay = prop.line == prop.line.roundToDouble()
        ? prop.line.toInt().toString()
        : prop.line.toStringAsFixed(1);
    final sourceLabel = prop.sourceProvider.trim().isEmpty
        ? prop.sportsbook
        : prop.sourceProvider;
    final updatedLabel = prop.lastUpdatedLocalDisplay;
    final hasLineMovement = (prop.openingLine - prop.currentLine).abs() >= 0.01;
    final openingLineText = prop.openingLine == prop.openingLine.roundToDouble()
        ? prop.openingLine.toInt().toString()
        : prop.openingLine.toStringAsFixed(1);
    final currentLineText = prop.currentLine == prop.currentLine.roundToDouble()
        ? prop.currentLine.toInt().toString()
        : prop.currentLine.toStringAsFixed(1);

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF081723),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8B6813), width: 1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC400).withValues(alpha: 0.08),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_marketCategory(prop)} • ${prop.localGameTimeDisplay.isNotEmpty ? prop.localGameTimeDisplay : '--:--'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.star_border,
                      color: Color(0xFFFFC400),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (gameDayDate.isNotEmpty) ...[
                  Text(
                    gameDayDate,
                    style: const TextStyle(
                      color: Color(0xFFFFC400),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () {
                    unawaited(
                      _showMetricMeaningOverlay(
                        title: 'Premium Pick Meaning',
                        description:
                            'Premium/Best Pick highlights the side our model currently favors based on edge, line quality, market agreement, and data freshness. It is a rank signal, not a guaranteed outcome.',
                        icon: Icons.workspace_premium,
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4A3B14), Color(0xFF2F2610)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFFFC400)),
                    ),
                    child: Text(
                      '★ BEST PICK: $side',
                      style: TextStyle(
                        color: sideAccentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pick: $recommendationText',
                  style: const TextStyle(color: Color(0xFFB0B8C4), fontSize: 9),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () {
                    unawaited(
                      _showMetricMeaningOverlay(
                        title: 'Confidence Meaning',
                        description:
                            'Confidence is a 0-100 model score representing relative strength of the pick given current inputs. Higher confidence means stronger model alignment, but it is not a win probability guarantee.',
                        icon: Icons.insights,
                      ),
                    );
                  },
                  child: Text(
                    'Confidence: ${prop.confidence}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: () {
                    unawaited(
                      _showMetricMeaningOverlay(
                        title: 'Tier Meaning',
                        description:
                            'Tier is a quick strength bucket for the play. Premium is the strongest blend of edge and model support, Strong is solid but slightly below top conviction, and Lean is playable with less margin.',
                        icon: Icons.layers,
                      ),
                    );
                  },
                  child: Text(
                    'Tier: ${prop.tier}',
                    style: const TextStyle(
                      color: Color(0xFFFFC400),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Live market model',
                  style: TextStyle(color: Color(0xFF7E8B99), fontSize: 8),
                ),
                const SizedBox(height: 3),
                Text(
                  updatedLabel.isEmpty
                      ? 'Source: $sourceLabel'
                      : 'Updated: $updatedLabel • Source: $sourceLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF7E8B99), fontSize: 8),
                ),
                if (hasLineMovement)
                  Text(
                    'Line: $openingLineText → $currentLineText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9DB0C4),
                      fontSize: 8,
                    ),
                  ),
                const SizedBox(height: 4),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF8B6813),
                            width: 1.2,
                          ),
                        ),
                        child: ClipOval(
                          child: _fastPlayerPhoto(prop, size: 60),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF211C0B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF8B6813)),
                        ),
                        child: Text(
                          prop.sportsbook.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFC400),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        prop.player,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        prop.matchup,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF7E8B99),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recommendationText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUnderPick
                                  ? Colors.white
                                  : const Color(0xFFFFC400),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$lineDisplay ${_propMarket(prop).toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB0B8C4),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: (confidence / 100).clamp(0, 1),
                    minHeight: 7,
                    backgroundColor: const Color(0xFF263746),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC400)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          widget.onSelect(prop, PickSide.over);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: EdgeInsets.zero,
                          foregroundColor: selectedSide == PickSide.over
                              ? Colors.black
                              : const Color(0xFFE6EEF8),
                          backgroundColor: selectedSide == PickSide.over
                              ? const Color(0xFFFFC400)
                              : const Color(0xFF0B1721),
                          side: BorderSide(
                            color: selectedSide == PickSide.over
                                ? const Color(0xFFFFC400)
                                : const Color(0xFF294052),
                          ),
                        ),
                        child: const Text(
                          'OVER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          widget.onSelect(prop, PickSide.under);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: EdgeInsets.zero,
                          foregroundColor: selectedSide == PickSide.under
                              ? Colors.black
                              : const Color(0xFFE6EEF8),
                          backgroundColor: selectedSide == PickSide.under
                              ? const Color(0xFFFFC400)
                              : const Color(0xFF0B1721),
                          side: BorderSide(
                            color: selectedSide == PickSide.under
                                ? const Color(0xFFFFC400)
                                : const Color(0xFF294052),
                          ),
                        ),
                        child: const Text(
                          'UNDER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _propsFuture = _loadProps();
    boardRefreshRequestNotifier.addListener(_handleBoardRefreshRequest);
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final active = activePropsInChronologicalOrder(
        _preparedProps.map((prepared) => prepared.prop),
      );
      if (active.length == _preparedProps.length) return;
      setState(() {
        _preparedProps = _prepareProps(active);
        _propsFuture = Future.value(active);
      });
    });
    _lineRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_refreshLiveLines());
    });
  }

  void _handleBoardRefreshRequest() {
    unawaited(_refreshProps());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRetryTimer?.cancel();
    _expiryTimer?.cancel();
    _lineRefreshTimer?.cancel();
    boardRefreshRequestNotifier.removeListener(_handleBoardRefreshRequest);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLiveLines());
    }
  }

  @override
  void didUpdateWidget(covariant PropGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sportFilter != widget.sportFilter ||
        oldWidget.selectedSite != widget.selectedSite ||
        oldWidget.selectedCategory != widget.selectedCategory ||
        oldWidget.selectedSide != widget.selectedSide ||
        oldWidget.selectedTier != widget.selectedTier ||
        oldWidget.minConfidence != widget.minConfidence ||
        oldWidget.sortBy != widget.sortBy ||
        oldWidget.searchQuery != widget.searchQuery) {
      _visiblePropLimit = _visiblePropStep;
      _preparedProps = const [];
      _propsFuture = _loadProps();
    }
  }

  List<_PreparedProp> _prepareProps(List<PropData> props) {
    return props.map((prop) {
      final market = _propMarket(prop);
      final searchText = '${prop.player} ${prop.matchup} ${prop.sport} $market'
          .toLowerCase();
      return _PreparedProp(
        prop: prop,
        normalizedSport: _normalizeSport(prop.sport),
        normalizedSite: _normalizeSite(prop.sportsbook),
        searchText: searchText,
      );
    }).toList();
  }

  Future<List<PropData>> _loadProps() async {
    final requestKey = _queryKey;
    final fetchTimer = Stopwatch()..start();
    _startupLog('fetchProps() start');
    final cached = await _apiService.loadCachedProps(
      selectedSide: widget.selectedSide,
      selectedTier: widget.selectedTier,
      selectedSportsbook: widget.selectedSite,
      selectedSport: widget.sportFilter,
      selectedCategory: widget.selectedCategory,
      search: widget.searchQuery,
      minConfidence: widget.minConfidence,
      sortBy: widget.sortBy,
    );
    if (!mounted || requestKey != _queryKey) return const [];
    if (shouldRenderCachedPropsOnLaunch(
      cached,
      selectedSport: widget.sportFilter,
    )) {
      _automaticRetryCount = 0;
      final activeCached = activePropsInChronologicalOrder(cached);
      _preparedProps = _prepareProps(activeCached);
      widget.onPropsLoaded?.call(
        activeCached,
        _apiService.lastPropsCount,
        _apiService.lastFacetCount,
        _apiService.lastCategoryCounts,
      );
      unawaited(_refreshFirstPageFromNetwork(requestKey));
      return activeCached;
    }
    final liveProps = await _fetchPropsPage();
    if (liveProps.isNotEmpty) {
      _automaticRetryCount = 0;
    }
    if (!mounted || requestKey != _queryKey) return const [];
    final props = activePropsInChronologicalOrder(liveProps);
    _startupLog(
      'fetchProps() complete in ${fetchTimer.elapsedMilliseconds}ms (${props.length} props)',
    );
    final prepareTimer = Stopwatch()..start();
    _preparedProps = _prepareProps(props);
    _startupLog(
      'prepareProps() complete in ${prepareTimer.elapsedMilliseconds}ms',
    );
    widget.onPropsLoaded?.call(
      props,
      _apiService.lastPropsCount,
      _apiService.lastFacetCount,
      _apiService.lastCategoryCounts,
    );
    return props;
  }

  Future<List<PropData>> _fetchPropsPage({int offset = 0}) {
    return _apiService.fetchProps(
      selectedSide: widget.selectedSide,
      selectedTier: widget.selectedTier,
      selectedSportsbook: widget.selectedSite,
      selectedSport: widget.sportFilter,
      selectedCategory: widget.selectedCategory,
      search: widget.searchQuery,
      minConfidence: widget.minConfidence,
      sortBy: widget.sortBy,
      limit: _visiblePropStep,
      offset: offset,
    );
  }

  Future<void> _refreshFirstPageFromNetwork(String requestKey) async {
    try {
      final fresh = activePropsInChronologicalOrder(await _fetchPropsPage());
      if (!mounted || requestKey != _queryKey) return;
      if (fresh.isEmpty && _preparedProps.isNotEmpty) {
        _autoRetryTimer = null;
        _scheduleAutomaticRetry();
        return;
      }
      setState(() {
        _preparedProps = _prepareProps(fresh);
        _propsFuture = Future.value(fresh);
      });
      widget.onPropsLoaded?.call(
        fresh,
        _apiService.lastPropsCount,
        _apiService.lastFacetCount,
        _apiService.lastCategoryCounts,
      );
    } catch (_) {
      // Keep the saved page visible while the connection recovers.
      _autoRetryTimer = null;
      _scheduleAutomaticRetry();
    }
  }

  Future<void> _refreshLiveLines() async {
    if (!mounted || _isRefreshing || _isLiveRefreshing) return;
    _isLiveRefreshing = true;
    try {
      await _refreshFirstPageFromNetwork(_queryKey);
    } finally {
      _isLiveRefreshing = false;
    }
  }

  Future<void> _loadMoreProps() async {
    if (_isLoadingMore || _preparedProps.length >= _apiService.lastPropsCount) {
      return;
    }
    final requestKey = _queryKey;
    setState(() => _isLoadingMore = true);
    try {
      final next = await _fetchPropsPage(offset: _preparedProps.length);
      if (!mounted || requestKey != _queryKey) return;
      final merged = activePropsInChronologicalOrder(
        <String, PropData>{
          for (final prepared in _preparedProps)
            prepared.prop.id: prepared.prop,
          for (final prop in next) prop.id: prop,
        }.values,
      );
      setState(() {
        _preparedProps = _prepareProps(merged);
        _visiblePropLimit = _preparedProps.length;
        _propsFuture = Future.value(merged);
      });
      widget.onPropsLoaded?.call(
        merged,
        _apiService.lastPropsCount,
        _apiService.lastFacetCount,
        _apiService.lastCategoryCounts,
      );
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refreshProps() async {
    if (_isRefreshing) {
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      await SlipManager.refreshSelectedProps(_apiService);
      if (!mounted) {
        return;
      }
      await _refreshFirstPageFromNetwork(_queryKey);
    } catch (_) {
      if (!mounted) {
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _retryLoad() {
    _autoRetryTimer?.cancel();
    _automaticRetryCount = 0;
    setState(() {
      _propsFuture = _loadProps();
    });
  }

  void _scheduleAutomaticRetry() {
    if (_autoRetryTimer?.isActive == true || _automaticRetryCount >= 3) return;
    _automaticRetryCount += 1;
    _autoRetryTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_runAutomaticRetry());
    });
  }

  Future<void> _runAutomaticRetry() async {
    if (!mounted) return;
    try {
      final requestKey = _queryKey;
      final props = activePropsInChronologicalOrder(await _fetchPropsPage());
      if (!mounted || requestKey != _queryKey) return;
      if (props.isEmpty) {
        throw StateError('The live prop feed is temporarily empty.');
      }
      setState(() {
        _preparedProps = _prepareProps(props);
        _propsFuture = Future.value(props);
      });
      widget.onPropsLoaded?.call(
        props,
        _apiService.lastPropsCount,
        _apiService.lastFacetCount,
        _apiService.lastCategoryCounts,
      );
      _autoRetryTimer = null;
      _automaticRetryCount = 0;
    } catch (_) {
      if (!mounted) return;
      _autoRetryTimer = null;
      _scheduleAutomaticRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<List<PropData>>(
          future: _propsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _PropLoadingSkeleton();
            }

            if (snapshot.hasError) {
              _scheduleAutomaticRetry();
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: _LoadError(
                  message: snapshot.error.toString(),
                  onRetry: _retryLoad,
                ),
              );
            }

            final allPrepared = _preparedProps.isNotEmpty
                ? _preparedProps
                : _prepareProps(snapshot.data ?? []);
            final normalizedSport = _normalizeSport(
              widget.displaySportFilter.isEmpty
                  ? widget.sportFilter
                  : widget.displaySportFilter,
            );
            final normalizedSite = _normalizeSite(widget.selectedSite);
            final search = widget.searchQuery;

            final filtered = allPrepared.where((prepared) {
              final sportMatches =
                  normalizedSport == 'ALL' ||
                  prepared.normalizedSport == normalizedSport;
              final siteMatches =
                  widget.selectedSite == 'ALL' ||
                  prepared.normalizedSite == normalizedSite;
              final searchMatches =
                  search.isEmpty || prepared.searchText.contains(search);
              return !prepared.prop.gameHasStarted &&
                  sportMatches &&
                  siteMatches &&
                  searchMatches;
            }).toList();

            final props = filtered.map((prepared) => prepared.prop).toList();

            int tierRank(String tier) {
              switch (tier.trim().toLowerCase()) {
                case 'premium':
                  return 3;
                case 'strong':
                  return 2;
                case 'lean':
                  return 1;
                default:
                  return 0;
              }
            }

            var sortedProps = [...props]
              ..sort((left, right) {
                switch (widget.sortBy) {
                  case 'source':
                    final leftStart = propScheduledStart(left);
                    final rightStart = propScheduledStart(right);
                    if (leftStart == null && rightStart == null) return 0;
                    if (leftStart == null) return 1;
                    if (rightStart == null) return -1;
                    return leftStart.compareTo(rightStart);
                  case 'edge':
                    return right.edge.compareTo(left.edge);
                  case 'premium':
                    final rankDiff = tierRank(right.tier) - tierRank(left.tier);
                    if (rankDiff != 0) {
                      return rankDiff;
                    }
                    return right.confidence.compareTo(left.confidence);
                  case 'time':
                    final leftStart = propScheduledStart(left);
                    final rightStart = propScheduledStart(right);
                    if (leftStart == null && rightStart == null) return 0;
                    if (leftStart == null) return 1;
                    if (rightStart == null) return -1;
                    return leftStart.compareTo(rightStart);
                  case 'confidence':
                  default:
                    return right.confidence.compareTo(left.confidence);
                }
              });
            sortedProps = deprioritizeSoccerForAllSports(
              sortedProps,
              selectedSport: widget.displaySportFilter.isEmpty
                  ? widget.sportFilter
                  : widget.displaySportFilter,
            );
            if (props.isEmpty) {
              _scheduleAutomaticRetry();
              final hasFilters =
                  widget.sportFilter.toUpperCase() != 'ALL' ||
                  widget.selectedSite.toUpperCase() != 'ALL' ||
                  widget.selectedCategory.toUpperCase() != 'ALL' ||
                  widget.selectedSide.toUpperCase() != 'ALL' ||
                  widget.selectedTier.toUpperCase() != 'ALL' ||
                  widget.minConfidence > 0 ||
                  widget.searchQuery.isNotEmpty;
              return Container(
                margin: const EdgeInsets.only(top: 18),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 34,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF09141E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off_rounded,
                      color: AppColors.gold,
                      size: 34,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasFilters
                          ? 'NO LIVE PROPS MATCH THESE FILTERS'
                          : 'NO LIVE PROPS AVAILABLE',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasFilters
                          ? 'Try ALL sports, ALL sites and ALL categories. A sport may also be between games or out of season.'
                          : 'The live provider has no current or upcoming props. Refresh again when new games are posted.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _retryLoad,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('CHECK AGAIN'),
                    ),
                  ],
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                int columns;
                if (constraints.maxWidth >= 760) {
                  columns = 3;
                } else if (constraints.maxWidth >= 560) {
                  columns = 3;
                } else if (constraints.maxWidth >= 480) {
                  columns = 2;
                } else {
                  columns = 1;
                }

                final visibleCount = _visiblePropLimit.clamp(
                  0,
                  sortedProps.length,
                );
                final visibleProps = sortedProps.take(visibleCount).toList();
                final hasMore =
                    visibleCount < sortedProps.length ||
                    _preparedProps.length < _apiService.lastPropsCount;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      primary: false,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visibleProps.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 410,
                      ),
                      itemBuilder: (context, index) {
                        final prop = visibleProps[index];
                        SlipSelection? selected;
                        for (final selection in widget.selections) {
                          if (selection.prop.id == prop.id) {
                            selected = selection;
                            break;
                          }
                        }
                        return RepaintBoundary(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onPropFocused?.call(prop),
                            child: _buildPortraitPropCard(prop, selected?.side),
                          ),
                        );
                      },
                    ),
                    if (hasMore) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: _isLoadingMore
                              ? null
                              : () {
                                  if (visibleCount < sortedProps.length) {
                                    setState(() {
                                      _visiblePropLimit += _visiblePropStep;
                                    });
                                  } else {
                                    unawaited(_loadMoreProps());
                                  }
                                },
                          icon: _isLoadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more),
                          label: Text(
                            _isLoadingMore
                                ? 'LOADING MORE'
                                : 'LOAD MORE (${(_apiService.lastPropsCount - visibleCount).clamp(0, _apiService.lastPropsCount)} remaining)',
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// TODO: Reconnect this toolbar when manual feed refresh is exposed to users.
// ignore: unused_element
class _PropToolbar extends StatelessWidget {
  final bool isRefreshing;
  final String? errorMessage;
  final Future<void> Function() onRefresh;

  const _PropToolbar({
    required this.isRefreshing,
    required this.errorMessage,
    required this.onRefresh,
  });

  String _formatStatus(BackendRefreshStatus status) {
    if (status.lastRefreshAt == null || status.sourceUrl.isEmpty) {
      return status.message;
    }
    final value = status.lastRefreshAt!.toLocal();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return 'Last refresh $hour:$minute:$second via ${status.sourceUrl}';
  }

  Color _statusColor(BackendRefreshStatus status) {
    if (status.lastRefreshAt == null || status.sourceUrl.isEmpty) {
      return const Color(0xFFFFC72C);
    }
    return const Color(0xFF56D38A);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  errorMessage ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                ValueListenableBuilder<BackendRefreshStatus>(
                  valueListenable: ApiService.refreshStatusNotifier,
                  builder: (context, status, _) {
                    return Text(
                      _formatStatus(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: isRefreshing ? null : onRefresh,
            icon: isRefreshing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.goldBright,
                    ),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(isRefreshing ? 'SYNCING' : 'REFRESH'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.goldBright,
              textStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropLoadingSkeleton extends StatelessWidget {
  const _PropLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 480
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
                const Text(
                  'Loading live props…',
                  style: TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadError({required this.message, required this.onRetry});

  String _friendlyMessage() {
    return userFacingLoadError(message, noun: 'live prop feed');
  }

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
              color: AppColors.goldBright,
              size: 38,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load props',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyMessage(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.goldBright,
                side: const BorderSide(color: AppColors.gold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));

  if (parts.isEmpty || parts.first.isEmpty) {
    return '';
  }

  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }

  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

Future<void> _showPropMetricInfoDialog(
  BuildContext context, {
  required String title,
  required String description,
  required IconData icon,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xE60A1520),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFC400), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFC400).withValues(alpha: 0.2),
                blurRadius: 22,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xFFFFC400), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFFD7E3EF),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class PropCard extends StatelessWidget {
  final PropData prop;
  final PickSide? selectedSide;
  final ValueChanged<PickSide> onSelect;

  const PropCard({
    super.key,
    required this.prop,
    required this.selectedSide,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1F2F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF263B4B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  prop.player,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.star_border, color: Color(0xFFFFC400), size: 17),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${prop.sport} • ${prop.matchup}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF8191A5), fontSize: 8.5),
          ),
          const SizedBox(height: 2),
          Text(
            prop.lastUpdatedLocalDisplay.isEmpty
                ? 'Source: ${prop.sourceProvider.isEmpty ? prop.sportsbook : prop.sourceProvider}'
                : 'Updated ${prop.lastUpdatedLocalDisplay} • ${prop.sourceProvider.isEmpty ? prop.sportsbook : prop.sourceProvider}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF607285), fontSize: 8),
          ),
          if ((prop.openingLine - prop.currentLine).abs() >= 0.01)
            Text(
              'Line ${prop.openingLine.toStringAsFixed(1)} → ${prop.currentLine.toStringAsFixed(1)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF607285), fontSize: 8),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFC400), width: 1),
                ),
                child: ClipOval(child: _buildPropCardImage(context, prop)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${prop.pick} ${prop.line}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      prop.market,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              InkWell(
                onTap: () {
                  unawaited(
                    _showPropMetricInfoDialog(
                      context,
                      title: 'Confidence Meaning',
                      description:
                          'Confidence is a 0-100 model score representing relative strength of the pick given current inputs. Higher confidence means stronger model alignment, but it is not a win probability guarantee.',
                      icon: Icons.insights,
                    ),
                  );
                },
                child: Text(
                  'Confidence: ${prop.confidence}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  unawaited(
                    _showPropMetricInfoDialog(
                      context,
                      title: 'Tier Meaning',
                      description:
                          'Tier is a quick strength bucket for the play. Premium is the strongest blend of edge and model support, Strong is solid but slightly below top conviction, and Lean is playable with less margin.',
                      icon: Icons.layers,
                    ),
                  );
                },
                child: Text(
                  'Tier: ${prop.tier}',
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  prop.sportsbook,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8191A5),
                    fontSize: 8.5,
                  ),
                ),
              ),
              Text(
                '${prop.edge.toStringAsFixed(2)} edge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: PickButton(
                  label: 'OVER',
                  selected: selectedSide == PickSide.over,
                  onPressed: () {
                    onSelect(PickSide.over);
                  },
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PickButton(
                  label: 'UNDER',
                  selected: selectedSide == PickSide.under,
                  onPressed: () {
                    onSelect(PickSide.under);
                  },
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPropCardImage(BuildContext context, PropData prop) {
    final imagePath = resolvePlayerImagePath(prop.imagePath);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheSize = (96 * pixelRatio).round().clamp(144, 384);
    final isNetwork =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');
    if (!isNetwork) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        alignment: Alignment.center,
        errorBuilder: (_, _, _) {
          return Container(
            color: AppColors.panel,
            alignment: Alignment.center,
            child: Text(
              _initials(prop.player),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: imagePath,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      alignment: Alignment.center,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      memCacheWidth: cacheSize,
      memCacheHeight: cacheSize,
      placeholder: (context, url) {
        return Container(
          color: AppColors.panel,
          alignment: Alignment.center,
          child: Text(
            _initials(prop.player),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        );
      },
      errorWidget: (context, url, error) {
        return Container(
          color: AppColors.panel,
          alignment: Alignment.center,
          child: Text(
            _initials(prop.player),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        );
      },
    );
  }
}

class PickButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool compact;

  const PickButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 31 : 38,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          backgroundColor: selected ? AppColors.gold : const Color(0xFF0B1721),
          foregroundColor: selected ? Colors.black : AppColors.text,
          side: BorderSide(
            color: selected ? AppColors.goldBright : AppColors.border,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class StatItem extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final String? trailing;

  const StatItem({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1C2A),
        border: Border.all(color: const Color(0xFF294052)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8A9AAF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFFF1EDF5),
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 7),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF7F90A5), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class RightSidebar extends StatelessWidget {
  final ActiveSlipController activeSlipController;
  final Future<void> Function() onSave;
  final Future<void> Function() onClear;
  final bool isSaving;
  final String? message;
  final bool showSavedSlips;
  final VoidCallback onShowSavedSlips;
  final VoidCallback onShowBuilder;

  const RightSidebar({
    super.key,
    required this.activeSlipController,
    required this.onSave,
    required this.onClear,
    required this.isSaving,
    required this.message,
    required this.showSavedSlips,
    required this.onShowSavedSlips,
    required this.onShowBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: activeSlipController,
      builder: (context, _) {
        return Container(
          color: AppColors.rightSidebar,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 4, bottom: 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: const PropIntelligenceBrandBadge(),
                ),
              ),
              const SizedBox(height: 10),
              const AuthAccountPanel(),
              const SizedBox(height: 10),
              Expanded(
                flex: 8,
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: SlipManager.selectedProps,
                  builder: (context, selectedProps, child) {
                    if (selectedProps.isNotEmpty) {
                      return const CurrentSlipPanelContainer();
                    }

                    return ActiveSlipPanel(
                      controller: activeSlipController,
                      onViewOrLock: onSave,
                      onClear: onClear,
                      isSaving: isSaving,
                      message: message,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class LockSlipDialog extends StatefulWidget {
  final List<SlipSelection> selections;
  final ApiService apiService;

  const LockSlipDialog({
    super.key,
    required this.selections,
    required this.apiService,
  });

  @override
  State<LockSlipDialog> createState() => _LockSlipDialogState();
}

class _LockSlipDialogState extends State<LockSlipDialog> {
  final _formKey = GlobalKey<FormState>();
  final _stakeController = TextEditingController(text: '10.00');
  String _selectedSite = 'PRIZEPICKS';
  String _prizePicksPlayType = 'POWER';
  bool _loadingPreview = false;
  String? _error;
  double? _potentialPayout;
  double? _potentialProfit;

  bool get _isPrizePicksSlip {
    return _selectedSite == 'PRIZEPICKS';
  }

  List<String> get _siteOptions {
    final options = <String>{
      for (final selection in widget.selections)
        _normalizeSite(
          '${selection.prop.sportsbook} ${selection.prop.sourceProvider}',
        ),
    }..removeWhere((site) => site.isEmpty);
    if (options.isEmpty) {
      options.add('PRIZEPICKS');
    }
    return options.toList(growable: false);
  }

  String _normalizeSite(String value) {
    final source = value.toUpperCase();
    if (source.contains('PRIZEPICKS') || source.contains('PRIZE PICKS')) {
      return 'PRIZEPICKS';
    }
    if (source.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    if (source.contains('SLEEPER')) {
      return 'SLEEPER';
    }
    if (source.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (source.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    return 'PRIZEPICKS';
  }

  List<String> _entryTypesForSite(String site) {
    switch (site) {
      case 'PRIZEPICKS':
        return const ['POWER', 'FLEX'];
      case 'UNDERDOG':
        return const ['POWER'];
      case 'SLEEPER':
        return const ['POWER'];
      case 'FANDUEL':
      case 'DRAFTKINGS':
        return const ['PARLAY'];
      default:
        return const ['POWER'];
    }
  }

  double _prizePicksPowerMultiplier(int legCount) {
    switch (legCount) {
      case 2:
        return 3;
      case 3:
        return 5;
      case 4:
        return 10;
      case 5:
        return 20;
      case 6:
        return 37.5;
      default:
        return 1;
    }
  }

  double _prizePicksFlexMultiplier(int legCount) {
    switch (legCount) {
      case 3:
        return 2.25;
      case 4:
        return 5;
      case 5:
        return 10;
      case 6:
        return 25;
      default:
        return 1;
    }
  }

  double _selectedPrizePicksMultiplier(int legCount) {
    if (_prizePicksPlayType == 'FLEX') {
      return _prizePicksFlexMultiplier(legCount);
    }
    return _prizePicksPowerMultiplier(legCount);
  }

  double _underdogMultiplier(int legCount) {
    switch (legCount) {
      case 2:
        return 3;
      case 3:
        return 6;
      case 4:
        return 10;
      case 5:
        return 20;
      case 6:
        return 40;
      default:
        return 1;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedSite = _siteOptions.first;
    final entryTypes = _entryTypesForSite(_selectedSite);
    _prizePicksPlayType = entryTypes.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePreview();
    });
  }

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  double? _readStake() {
    return double.tryParse(_stakeController.text.replaceAll(r'$', '').trim());
  }

  Future<void> _updatePreview() async {
    final stake = _readStake();
    if (stake == null || stake <= 0) {
      setState(() {
        _potentialPayout = null;
        _potentialProfit = null;
      });
      return;
    }

    if (_selectedSite == 'PRIZEPICKS' || _selectedSite == 'UNDERDOG') {
      final multiplier = _selectedSite == 'PRIZEPICKS'
          ? _selectedPrizePicksMultiplier(widget.selections.length)
          : _underdogMultiplier(widget.selections.length);
      if (multiplier <= 1) {
        setState(() {
          _error =
              'Selected play type is not available for ${widget.selections.length} legs.';
          _potentialPayout = null;
          _potentialProfit = null;
          _loadingPreview = false;
        });
        return;
      }

      setState(() {
        _error = null;
        _potentialPayout = stake * multiplier;
        _potentialProfit = _potentialPayout! - stake;
        _loadingPreview = false;
      });
      return;
    }

    setState(() {
      _loadingPreview = true;
      _error = null;
    });

    try {
      final preview = await widget.apiService.previewSlip(
        selections: widget.selections,
        stake: stake,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _potentialPayout = preview['potentialPayout'];
        _potentialProfit = preview['potentialProfit'];
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(_readStake());
  }

  @override
  Widget build(BuildContext context) {
    final entryTypes = _entryTypesForSite(_selectedSite);
    final selectedEntryType = entryTypes.contains(_prizePicksPlayType)
        ? _prizePicksPlayType
        : entryTypes.first;
    final entryTypeLabel = selectedEntryType == 'PARLAY'
        ? 'Parlay'
        : selectedEntryType == 'POWER'
        ? 'Power Play'
        : 'Flex Play';

    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text(
        'LOCK SLIP',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.selections.length} LEG SLIP',
                style: const TextStyle(
                  color: AppColors.goldBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedSite,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Prop Site',
                  border: OutlineInputBorder(),
                ),
                items: _siteOptions
                    .map(
                      (site) =>
                          DropdownMenuItem(value: site, child: Text(site)),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedSite = value;
                  });
                  _updatePreview();
                },
              ),
              if (_isPrizePicksSlip) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'POWER',
                      label: Text('POWER PLAY'),
                      icon: Icon(Icons.bolt),
                    ),
                    ButtonSegment<String>(
                      value: 'FLEX',
                      label: Text('FLEX PLAY'),
                      icon: Icon(Icons.shield_outlined),
                    ),
                  ],
                  selected: {selectedEntryType},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _prizePicksPlayType = selection.first;
                    });
                    _updatePreview();
                  },
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Entry Type: ${entryTypes.first}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Site: $_selectedSite • Entry: $entryTypeLabel',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stakeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Stake',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final stake = double.tryParse(
                    value?.replaceAll(r'$', '').trim() ?? '',
                  );
                  if (stake == null || stake <= 0) {
                    return 'Enter a stake greater than \$0.';
                  }
                  return null;
                },
                onChanged: (_) {
                  _updatePreview();
                },
              ),
              const SizedBox(height: 18),
              _PreviewRow(
                label: 'Potential payout',
                value: _potentialPayout,
                loading: _loadingPreview,
              ),
              const SizedBox(height: 8),
              _PreviewRow(
                label: 'Potential profit',
                value: _potentialProfit,
                loading: _loadingPreview,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF9EA6),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _loadingPreview ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
          ),
          child: const Text(
            'LOCK SLIP',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final double? value;
  final bool loading;

  const _PreviewRow({
    required this.label,
    required this.value,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const Spacer(),
        if (loading)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.goldBright,
            ),
          )
        else
          Text(
            value == null ? '--' : '\$${value!.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.goldBright,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

class EmptySlip extends StatelessWidget {
  const EmptySlip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 38,
            color: AppColors.goldBright,
          ),
          SizedBox(height: 12),
          Text(
            'No picks in this view',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 7),
          Text(
            'Select Over or Under on a prop card.',
            style: TextStyle(color: AppColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class SlipSelectionCard extends StatelessWidget {
  final SlipSelection selection;
  final VoidCallback onRemove;

  const SlipSelectionCard({
    super.key,
    required this.selection,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final prop = selection.prop;
    final customLabel = prop.customLabel;
    final manualNote = prop.manualNote;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  prop.player,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 16, color: AppColors.muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          if (customLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Chip(label: Text(customLabel)),
          ],
          const SizedBox(height: 5),
          Text(
            '${selection.sideLabel} ${prop.line} ${prop.market}',
            style: const TextStyle(
              color: AppColors.goldBright,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${prop.sportsbook} • ${prop.matchup}',
            style: const TextStyle(color: AppColors.muted, fontSize: 9),
          ),
          if (manualNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              manualNote,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MobileDashboardViewport extends StatelessWidget {
  const MobileDashboardViewport({super.key});

  @override
  Widget build(BuildContext context) {
    return const DesktopDashboard();
  }
}
