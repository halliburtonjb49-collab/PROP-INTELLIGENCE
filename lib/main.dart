import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'layout/app_shell.dart';
import 'navigation/app_navigation.dart';
export 'navigation/app_navigation.dart';
import 'controllers/active_slip_controller.dart';
import 'models/prop_data.dart';
import 'models/saved_slip.dart';
import 'pages/prop_chat_page.dart';
export 'pages/search_players_page.dart';
export 'pages/prop_alerts_page.dart';
import 'screens/prop_builder_performance_screen.dart';
import 'screens/prop_builder_screen.dart';
import 'screens/strikeout_pro_gold_screen.dart';
import 'screens/login_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/password_recovery_screen.dart';
import 'models/slip_selection.dart';
import 'services/api_service.dart';
export 'services/prop_market_identity.dart' show marketCategoryFor;
export 'services/prop_board_engine.dart';
import 'services/app_sound_service.dart';
import 'services/onesignal_service.dart';
import 'services/auth_manager.dart';
import 'services/developer_mode_service.dart';
import 'services/engagement_tracker.dart';
import 'services/prop_watchlist_service.dart';
import 'services/prop_chat_service.dart';
import 'services/recommendation_access.dart';
import 'services/slip_manager.dart';
import 'services/scoreboard_service.dart';
import 'services/scoreboard_watchlist_service.dart';
import 'services/supabase_service.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_colors.dart' as app_colors;
import 'theme/app_theme.dart';
import 'widgets/auth_account_panel.dart';
import 'widgets/left_sidebar.dart';
import 'widgets/top_navigation.dart';
export 'widgets/top_navigation.dart';
import 'widgets/onboarding_dialog.dart';
import 'widgets/main_dashboard.dart';
export 'widgets/main_dashboard.dart'
    show
        boardIntelligenceScope,
        boardContentPadding,
        compactBoardControlWidth,
        providerCoverageIssueForSport,
        resolveVerdictFilterCount,
        shouldWrapVerdictFilters,
        useCompactBoardControls,
        visibleCategoryFilters;
export 'widgets/prop_board_loading.dart';
import 'widgets/lock_slip_dialog.dart';
export 'widgets/lock_slip_dialog.dart';
export 'widgets/prop_research_controls.dart';
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
      backgroundColor: app_colors.AppColors.bgBase,
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
    EngagementTracker.instance.recordError(details.exception);
  };

  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stackTrace) {
        _startupLog('Unhandled async error: $error');
        EngagementTracker.instance.recordError(error);
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
    EngagementTracker.instance.recordProduct('APP_OPEN');
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
      color: app_colors.AppColors.gold,
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
                      color: app_colors.AppColors.bgBase,
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
                    color: app_colors.AppColors.bgBase,
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
  final ValueNotifier<bool> _isSavingSlipNotifier = ValueNotifier(false);
  bool get _isSavingSlip => _isSavingSlipNotifier.value;
  Timer? _selectionExpiryTimer;
  Timer? _ticketSyncRetryTimer;
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
    EngagementTracker.instance.recordProduct('DASHBOARD_READY');
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
          _startupLog(
            'active slip load complete ($loadedCount persisted legs restored)',
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
    _selectionExpiryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _removeClosedDraftSelections(),
    );
  }

  void _removeClosedDraftSelections() {
    if (!mounted) return;
    final expired = _slipSelections
        .where((selection) => !selection.prop.isSelectable)
        .toList(growable: false);
    if (expired.isEmpty) return;
    final expiredIds = expired.map((item) => item.prop.id).toSet();
    setState(() {
      _slipSelections.removeWhere(
        (selection) => expiredIds.contains(selection.prop.id),
      );
    });
    for (final selection in expired) {
      unawaited(_activeSlipController.removeLeg(selection.prop.id));
      SlipManager.removePropById(selection.prop.id);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: app_colors.AppColors.gold,
        content: Text(
          '${expired.length} prop${expired.length == 1 ? '' : 's'} removed because the pregame selection window closed.',
          style: const TextStyle(
            color: app_colors.AppColors.bgBase,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
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
    _isSavingSlipNotifier.dispose();
    _selectionExpiryTimer?.cancel();
    _ticketSyncRetryTimer?.cancel();
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
      case AppPage.briefing:
      case AppPage.gameMarkets:
      case AppPage.evScanner:
      case AppPage.searchPlayers:
      case AppPage.scoreboard:
      case AppPage.scoreboardWatchlist:
      case AppPage.propAlerts:
      case AppPage.analytics:
      case AppPage.lineMovement:
      case AppPage.injuryImpact:
      case AppPage.dataAdmin:
      case AppPage.ownerOperations:
      case AppPage.intelligenceLab:
      case AppPage.refereeTracker:
      case AppPage.propChat:
      case AppPage.trackRecord:
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
            propCountNotifier: boardPropCountNotifier,
            refreshRequestNotifier: boardRefreshRequestNotifier,
            onStartupLog: _startupLog,
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
            onClose: () =>
                _switchToPage(AppPage.board, source: 'slip-watcher-close'),
          ),
          const PropBuilderPerformanceScreen(),
          StrikeoutProGoldScreen(
            onSelect: _toggleStrikeoutSelection,
            onPropsRefreshed: _refreshActiveSlipProps,
            onPropsExpired: _removeExpiredStrikeoutProps,
          ),
          SlipHistoryPanel(
            activeSlipController: _activeSlipController,
            mode: SlipHistoryMode.history,
            hasProAccess: hasProAccess,
            isActive: _selectedPage == AppPage.pastSlipHistory,
            onClose: () =>
                _switchToPage(AppPage.board, source: 'slip-history-close'),
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
                          color: app_colors.AppColors.bgBase,
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
                      child: ChatUnreadBadge(),
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
                        color: app_colors.AppColors.bgBase,
                        size: 27,
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(right: -2, bottom: -2, child: ChatUnreadBadge()),
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

  Widget _buildChatRestoreButton() {
    return Positioned(
      right: 18,
      bottom: 92,
      child: SafeArea(
        minimum: const EdgeInsets.all(4),
        child: Material(
          key: const ValueKey('restore-prop-chat-bubble'),
          elevation: 14,
          color: app_colors.AppColors.bgPanel,
          shape: const CircleBorder(
            side: BorderSide(color: app_colors.AppColors.gold, width: 1.5),
          ),
          child: IconButton(
            tooltip: 'Bring back PROP CHAT bubble',
            onPressed: _showChatBubble,
            icon: const Icon(
              Icons.add_comment_rounded,
              color: app_colors.AppColors.gold,
            ),
          ),
        ),
      ),
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
              colors: [Color(0xFF0B1A28), app_colors.AppColors.bgBase],
            ),
          ),
          child: LeftSidebar(
            selectedPage: _selectedPage,
            selectedSport: _selectedBoardSport,
            lockedSlipCount: _activeSlipController.lockedSlipCount,
            propCountListenable: boardPropCountNotifier,
            onRefresh: () => boardRefreshRequestNotifier.value++,
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
          : app_colors.AppColors.silver,
      onTabSelected: (page) {
        _switchToPage(page, source: 'top-nav');
      },
    );
  }

  Widget _buildRightPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _activeSlipController,
        _isSavingSlipNotifier,
      ]),
      builder: (context, _) {
        return Container(
          color: app_colors.AppColors.sidebar,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            children: [
              const AuthAccountPanel(),
              const SizedBox(height: 8),
              _buildFeedbackActionButton(),
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
                  syncPhase: _activeSlipController.syncPhase,
                  syncAttempts: _activeSlipController.syncAttempts,
                  onRetrySync: _activeSlipController.canRetrySync
                      ? _retrySlipSync
                      : null,
                  onSendDiagnostic:
                      _activeSlipController.syncPhase == TicketSyncPhase.error
                      ? _sendTicketSyncDiagnostic
                      : null,
                  onRebuildSyncState:
                      _activeSlipController.syncPhase == TicketSyncPhase.error
                      ? _rebuildTicketSyncState
                      : null,
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
    _applySelection(prop, side, rebuildDashboard: true);
  }

  void _toggleStrikeoutSelection(PropData prop, PickSide side) {
    // Strikeout Pro Gold owns its button state. Avoid rebuilding the complete
    // IndexedStack (including every hidden dashboard page) for each leg.
    _applySelection(prop, side, rebuildDashboard: false);
  }

  void _applySelection(
    PropData prop,
    PickSide side, {
    required bool rebuildDashboard,
  }) {
    final existingIndex = _slipSelections.indexWhere(
      (item) => item.prop.id == prop.id,
    );
    final removingExisting =
        existingIndex >= 0 && _slipSelections[existingIndex].side == side;
    if (!prop.isSelectable && !removingExisting) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: app_colors.AppColors.gold,
          content: Text(
            // Say which of the two reasons applies rather than always
            // blaming the clock.
            prop.selectionBlockedReason,
            style: TextStyle(
              color: app_colors.AppColors.bgBase,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
      return;
    }
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
    if (existingIndex < 0 && _isMixedSiteAttempt(selection)) {
      _showMixedSiteNotAllowedMessage();
      return;
    }

    SlipSelection? removed;
    Map<String, dynamic>? upsertedLeg;
    var shouldAdd = false;

    void updateSelectionState() {
      if (existingIndex >= 0) {
        final existing = _slipSelections[existingIndex];
        if (existing.side == side) {
          removed = existing;
          _slipSelections.removeAt(existingIndex);
        } else {
          _slipSelections[existingIndex] = selection;
          upsertedLeg = _selectionToLeg(selection);
        }
      } else {
        _slipSelections.add(selection);
        upsertedLeg = _selectionToLeg(selection);
        shouldAdd = true;
      }
    }

    if (rebuildDashboard) {
      setState(updateSelectionState);
    } else {
      updateSelectionState();
    }

    if (removed != null) {
      unawaited(_activeSlipController.removeLeg(removed!.prop.id));
      SlipManager.removePropById(removed!.prop.id);
    } else if (upsertedLeg != null) {
      if (shouldAdd) {
        EngagementTracker.instance.recordProduct('PROP_SELECTED');
        unawaited(_activeSlipController.addLegs([upsertedLeg!]));
      } else {
        unawaited(_activeSlipController.updateLeg(upsertedLeg!));
      }
      SlipManager.upsertProp(upsertedLeg!);
    }
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
    if (normalized.contains('BETR')) {
      return 'BETR';
    }
    if (normalized.contains('PICK6') || normalized.contains('PICK 6')) {
      return 'PICK6';
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
            color: app_colors.AppColors.bgBase,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openFeedbackDialog() async {
    final messageController = TextEditingController();
    var category = 'suggestion';
    var sending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF0B1825),
            title: const Text('SEND FEEDBACK TO OWNER'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Share any recommendation, issue, or request. This goes directly to the owner operations inbox.',
                    style: TextStyle(
                      color: app_colors.AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(
                        value: 'suggestion',
                        child: Text('Suggestion'),
                      ),
                      DropdownMenuItem(value: 'issue', child: Text('Issue')),
                      DropdownMenuItem(
                        value: 'recommendation',
                        child: Text('Recommendation'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: sending
                        ? null
                        : (value) {
                            setDialogState(
                              () => category = value ?? 'suggestion',
                            );
                          },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: messageController,
                    maxLines: 6,
                    maxLength: 1200,
                    enabled: !sending,
                    decoration: const InputDecoration(
                      labelText: 'Your feedback',
                      hintText:
                          'Example: Add an alert when line moves by 0.5 in the last hour.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('CANCEL'),
              ),
              FilledButton.icon(
                onPressed: sending
                    ? null
                    : () async {
                        final text = messageController.text.trim();
                        final messenger = ScaffoldMessenger.of(context);
                        if (text.length < 5) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter at least 5 characters.',
                              ),
                            ),
                          );
                          return;
                        }
                        setDialogState(() => sending = true);
                        try {
                          await _apiService.submitUserFeedback(
                            category: category,
                            message: text,
                            page: _selectedPage.name,
                            metadata: {
                              'selectedPage': _selectedPage.name,
                              'platform': kIsWeb
                                  ? 'web'
                                  : defaultTargetPlatform.name,
                            },
                          );
                          if (!mounted || !dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Feedback sent to owner. Thank you.',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!mounted) return;
                          setDialogState(() => sending = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Unable to send feedback: $error'),
                            ),
                          );
                        }
                      },
                icon: sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(sending ? 'SENDING' : 'SEND'),
              ),
            ],
          ),
        );
      },
    );

    messageController.dispose();
  }

  Widget _buildFeedbackActionButton() {
    return SizedBox(
      width: double.infinity,
      child: Material(
        elevation: 6,
        color: app_colors.AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: app_colors.AppColors.gold, width: 1.3),
        ),
        child: InkWell(
          key: const ValueKey('open-user-feedback-dialog'),
          onTap: _openFeedbackDialog,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.campaign_outlined,
                  size: 16,
                  color: app_colors.AppColors.gold,
                ),
                SizedBox(width: 6),
                Text(
                  'FEEDBACK',
                  style: TextStyle(
                    color: app_colors.AppColors.gold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .6,
                  ),
                ),
              ],
            ),
          ),
        ),
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
      'game_start_time': prop.startTimeUtc.isNotEmpty
          ? prop.startTimeUtc
          : prop.gameStartTime,
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
      'confidence': prop.displayConfidenceRating,
      'projection': prop.projection,
      'projection_source': prop.projectionSource,
      'projection_model_version': prop.projectionModelVersion,
      'projection_sample_size': prop.projectionSampleSize,
      'projection_volatility': prop.projectionVolatility,
      'projection_calibrated': prop.projectionCalibrated,
      'historical_hit_rate': prop.historicalHitRate,
      'pi_trust_score': prop.piTrustScore,
      'pi_trust_band': prop.piTrustBand,
      'pi_trust_warnings': prop.piTrustWarnings,
      'data_quality_score': prop.dataQualityScore,
      'data_stale': prop.dataStale,
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

  Future<void> _saveSlip(
    double stake,
    List<SlipSelection> selections, {
    bool automaticRetry = false,
  }) async {
    if (selections.isEmpty || _isSavingSlip) {
      return;
    }
    if (selections.any((selection) => !selection.prop.isSelectable)) {
      _removeClosedDraftSelections();
      return;
    }

    final requestId = await _activeSlipController.prepareSync(stake);
    _isSavingSlipNotifier.value = true;
    _activeSlipController.markSyncing();

    try {
      final response = await _apiService.saveSlip(
        selections: selections,
        stake: stake,
        clientRequestId: requestId,
      );
      if (!mounted) {
        return;
      }
      final savedSlip = SavedSlip.fromJson(response);
      _ticketSyncRetryTimer?.cancel();
      _activeSlipController.addOptimisticLockedSlip(savedSlip);
      await _activeSlipController.clear();
      _activeSlipController.markSynced();
      if (!mounted) return;
      setState(() => _slipSelections.clear());
      SlipManager.reserveActiveSlips(_activeSlipController.recentLockedSlips);
      EngagementTracker.instance.recordProduct('SLIP_LOCKED');
      _switchToPage(AppPage.watchlist, source: 'slip-locked');

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: app_colors.AppColors.gold,
            content: Text(
              'Slip locked and moved to Slip Watcher!',
              style: TextStyle(
                color: app_colors.AppColors.bgBase,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      _activeSlipController.markSyncFailed(error);
      _scheduleTicketSyncRecovery();
      if (!mounted) {
        return;
      }
      if (!automaticRetry) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFFF8A80),
            content: Text(
              'Slip was not locked. Your draft is safe and will retry automatically. $error',
              style: const TextStyle(
                color: app_colors.AppColors.bgBase,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        _isSavingSlipNotifier.value = false;
      }
    }
  }

  Future<void> _retrySlipSync() async {
    final stake = _activeSlipController.pendingStake;
    final selections = _activeSlipSelections();
    if (stake == null || selections.isEmpty) return;
    await _saveSlip(stake, selections);
  }

  void _scheduleTicketSyncRecovery() {
    _ticketSyncRetryTimer?.cancel();
    if (!_activeSlipController.canRetrySync ||
        _activeSlipController.syncAttempts >= 6) {
      return;
    }
    final requestId = _activeSlipController.pendingRequestId;
    final delaySeconds = (5 * (1 << (_activeSlipController.syncAttempts - 1)))
        .clamp(5, 30);
    _ticketSyncRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted ||
          _isSavingSlip ||
          !_activeSlipController.canRetrySync ||
          _activeSlipController.pendingRequestId != requestId) {
        return;
      }
      final stake = _activeSlipController.pendingStake;
      final selections = _activeSlipSelections();
      if (stake == null || selections.isEmpty) return;
      unawaited(_saveSlip(stake, selections, automaticRetry: true));
    });
  }

  Future<void> _sendTicketSyncDiagnostic() async {
    try {
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
      final id = await _apiService.sendTicketSyncDiagnostic(
        _activeSlipController.syncDiagnosticPayload(platform: platform),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Diagnostic report sent. Reference: $id')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Diagnostic report could not be sent. Your draft is still safe.',
          ),
        ),
      );
    }
  }

  Future<void> _rebuildTicketSyncState() async {
    await _activeSlipController.rebuildSyncState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sync state rebuilt. Your draft picks were preserved.'),
      ),
    );
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
        : app_colors.AppColors.silver;
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
              mobileRouteKey: _selectedPage,
              onMobileWatchSlip: () =>
                  _switchToPage(AppPage.watchlist, source: 'mobile-bottom-nav'),
              onMobileDismissOverlay: _closeFloatingChat,
              onMobileNavigateIndex: (index) {
                switch (index) {
                  case 0:
                    _switchToPage(AppPage.board, source: 'mobile-swipe');
                    break;
                  case 1:
                    _switchToPage(AppPage.gameMarkets, source: 'mobile-swipe');
                    break;
                  case 2:
                    _switchToPage(AppPage.watchlist, source: 'mobile-swipe');
                    break;
                }
              },
              accentColor: membershipAccent,
            ),
          ),
          if (_chatFloating) _buildFloatingChat(constraints),
          if (_chatBubbleVisible &&
              !_chatFloating &&
              _selectedPage != AppPage.propChat)
            _buildChatBubble(constraints),
          if (!_chatBubbleVisible &&
              !_chatFloating &&
              _selectedPage != AppPage.propChat)
            _buildChatRestoreButton(),
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
        color: app_colors.AppColors.bgPanel,
        shape: const CircleBorder(
          side: BorderSide(color: app_colors.AppColors.silver),
        ),
        child: IconButton(
          key: const ValueKey('close-prop-chat-bubble'),
          tooltip: 'Remove chat bubble',
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          iconSize: 15,
          icon: const Icon(
            Icons.close_rounded,
            color: app_colors.AppColors.silver,
          ),
        ),
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
