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
import 'pages/analytics_page.dart';
import 'pages/line_movement_page.dart';
import 'screens/prop_builder_performance_screen.dart';
import 'screens/goblins_demons_screen.dart';
import 'screens/login_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/password_recovery_screen.dart';
import 'screens/cloud_watchlist_screen.dart';
import 'screens/central_props_display_grid_canvas.dart';
import 'models/slip_selection.dart';
import 'services/api_service.dart';
import 'services/auth_manager.dart';
import 'services/developer_mode_service.dart';
import 'services/prop_watchlist_service.dart';
import 'services/slip_manager.dart';
import 'services/supabase_service.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_colors.dart' as app_colors;
import 'theme/prop_intelligence_colors.dart' as brand;
import 'pages/intelligence_lab_page.dart';
import 'widgets/active_slip_panel.dart';
import 'widgets/auth_account_panel.dart';
import 'widgets/current_slip_panel.dart';
import 'widgets/ev_scanner_card.dart';
import 'widgets/interactive_prop_builder.dart';
import 'widgets/onboarding_dialog.dart';
import 'widgets/scoreboard_view.dart';
import 'widgets/selected_prop_slip.dart';

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

  SupabaseService.configure(
    url: kSupabaseProjectUrl,
    anonKey: kSupabaseAnonPublicApiKey,
  );

  runApp(const PropIntelligenceApp());
  _startupLog('runApp() called');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _startupLog('first frame rendered');
    unawaited(() async {
      try {
        await SupabaseService.initialize();
        AuthManager.instance.attach();
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
  propBuilder,
  watchlist,
  builderPerformance,
  goblinsDemons,
  evScanner,
  searchPlayers,
  scoreboard,
  propAlerts,
  analytics,
  lineMovement,
  dataAdmin,
  intelligenceLab,
}

class AppColors {
  static const background = Color(0xFF050A0F);
  static const leftSidebar = Color(0xFF09131D);
  static const rightSidebar = Color(0xFF071019);
  static const panel = Color(0xFF0C1824);
  static const border = Color(0xFF283846);
  static const gold = Color(0xFFFFC400);
  static const goldBright = Color(0xFFFFC400);
  static const text = Color(0xFFF3F1EC);
  static const muted = Color(0xFF8996A6);
}

ThemeData buildPropIntelligenceBrandedTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: brand.PropIntelligenceColors.darkCanvasBg,
    cardColor: brand.PropIntelligenceColors.darkCardBg,
    dividerColor: Colors.white10,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: brand.PropIntelligenceColors.metallicSilver),
      titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF08131D),
      labelStyle: const TextStyle(color: app_colors.AppColors.textSecondary),
      helperStyle: const TextStyle(color: app_colors.AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          width: 1.4,
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF152534),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      textStyle: const TextStyle(
        color: app_colors.AppColors.white,
        fontSize: 12,
      ),
      waitDuration: const Duration(milliseconds: 450),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: app_colors.AppColors.gold,
        foregroundColor: const Color(0xFF06111B),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: .3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: app_colors.AppColors.gold,
        foregroundColor: const Color(0xFF06111B),
        elevation: 0,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: .35,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: app_colors.AppColors.white,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        side: const BorderSide(color: app_colors.AppColors.border),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: app_colors.AppColors.textSecondary,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .25,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: app_colors.AppColors.textSecondary,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return brand.PropIntelligenceColors.premiumGold;
        }
        if (states.contains(WidgetState.hovered)) {
          return brand.PropIntelligenceColors.premiumGold.withValues(
            alpha: 0.9,
          );
        }
        return brand.PropIntelligenceColors.premiumGold.withValues(alpha: 0.82);
      }),
      trackColor: WidgetStateProperty.all(const Color(0xFF101D28)),
      trackBorderColor: WidgetStateProperty.all(const Color(0xFF8B6813)),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(9),
      interactive: true,
    ),
  );
}

String _resolvePlayerImagePath(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.startsWith('assets/')) {
    return trimmed;
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final base = ApiService.baseUrl.trim();
  final normalizedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  final normalizedPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return '$normalizedBase$normalizedPath';
}

class PropIntelligenceApp extends StatelessWidget {
  const PropIntelligenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PROP INTELLIGENCE',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: buildPropIntelligenceBrandedTheme(),
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
                return _buildDashboardShell();
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDashboardShell() {
    return Scaffold(
      backgroundColor: const Color(0xFF050C13),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 700) {
            return const DesktopDashboard();
          }

          return const MobileDashboardViewport();
        },
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

  @override
  void initState() {
    super.initState();
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
      }
    });
  }

  @override
  void dispose() {
    _activeSlipController.dispose();
    super.dispose();
  }

  void _switchToPage(AppPage page, {String source = 'ui'}) {
    final requiredTier = _requiredTier(page);
    final session = AuthManager.instance.sessionState.value;
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
    if (_selectedPage == page) {
      return;
    }
    final timer = Stopwatch()..start();
    setState(() {
      _selectedPage = page;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupLog(
        'page switch ($source) -> ${page.name} in ${timer.elapsedMilliseconds}ms',
      );
    });
  }

  SubscriptionTier? _requiredTier(AppPage page) => switch (page) {
    AppPage.propBuilder ||
    AppPage.watchlist ||
    AppPage.analytics ||
    AppPage.lineMovement ||
    AppPage.propAlerts => SubscriptionTier.core,
    AppPage.builderPerformance ||
    AppPage.goblinsDemons ||
    AppPage.evScanner ||
    AppPage.intelligenceLab => SubscriptionTier.edge,
    _ => null,
  };

  void _selectBoardSport(String sport) {
    setState(() {
      _selectedBoardSport = sport;
    });
    _switchToPage(AppPage.board, source: 'sport-filter');
  }

  int _mainPageIndex() {
    switch (_selectedPage) {
      case AppPage.board:
      case AppPage.evScanner:
      case AppPage.searchPlayers:
      case AppPage.scoreboard:
      case AppPage.propAlerts:
      case AppPage.analytics:
      case AppPage.lineMovement:
      case AppPage.dataAdmin:
      case AppPage.intelligenceLab:
        return 0;
      case AppPage.propBuilder:
        return 1;
      case AppPage.watchlist:
        return 2;
      case AppPage.builderPerformance:
        return 3;
      case AppPage.goblinsDemons:
        return 4;
    }
  }

  Widget _buildMainContent() {
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
            sportFilter: _selectedBoardSport,
            selectedPage: _selectedPage,
          ),
          const InteractiveConstructorEngineWidget(),
          const CloudWatchlistScreen(),
          const PropBuilderPerformanceScreen(),
          GoblinsDemonsScreen(onSelect: _toggleSelection),
        ],
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
              colors: [Color(0xFF0B1A28), Color(0xFF06111B)],
            ),
          ),
          child: LeftSidebar(
            selectedPage: _selectedPage,
            selectedSport: _selectedBoardSport,
            activeSlipCount: _activeSlipController.legCount,
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
    return TopNavigation(
      selectedPage: _selectedPage,
      onOpenPropAlerts: () {
        _switchToPage(AppPage.propAlerts, source: 'top-nav-alerts');
      },
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
    return _normalizedSite(
      leg['prop_site']?.toString() ??
          leg['sportsbook']?.toString() ??
          leg['site']?.toString() ??
          '',
    );
  }

  String _normalizedSite(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
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
      return 'DRAFT PICKS';
    }
    return normalized;
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
      'odds': selectedOdds,
      'current_odds': selectedOdds,
      'over_odds': prop.overOdds,
      'under_odds': prop.underOdds,
      'multiplier': prop.multiplier,
      'win_probability': prop.winProbability,
      'edge': prop.edge,
      'confidence': prop.confidence,
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
        edge: (leg['edge'] as num?)?.toDouble() ?? 0,
        imagePath:
            leg['image_path']?.toString() ?? leg['imagePath']?.toString() ?? '',
        customLabel: leg['custom_label']?.toString() ?? '',
        manualNote: leg['manual_note']?.toString() ?? '',
        multiplier: (leg['multiplier'] as num?)?.toDouble(),
        winProbability: (leg['win_probability'] as num?)?.toDouble(),
        overOdds: side == PickSide.over ? oddsValue : null,
        underOdds: side == PickSide.under ? oddsValue : null,
      );

      return SlipSelection(prop: prop, side: side);
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

    try {
      await _apiService.saveSlip(selections: selections, stake: stake);
      if (!mounted) {
        return;
      }
      await _activeSlipController.clear();
      setState(() {
        _slipSelections.clear();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
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
    return AppShell(
      leftSidebar: _buildLeftSidebar(),
      topNavigation: _buildTopNavigation(),
      content: _buildMainContent(),
      rightSidebar: _buildRightPanel(),
    );
  }
}

class LeftSidebar extends StatefulWidget {
  final AppPage selectedPage;
  final String selectedSport;
  final int activeSlipCount;
  final ValueChanged<AppPage>? onSelectPage;
  final ValueChanged<String>? onSelectSport;

  const LeftSidebar({
    super.key,
    required this.selectedPage,
    required this.selectedSport,
    required this.activeSlipCount,
    this.onSelectPage,
    this.onSelectSport,
  });

  @override
  State<LeftSidebar> createState() => _LeftSidebarState();
}

class _LeftSidebarState extends State<LeftSidebar> {
  final ScrollController _sidebarScrollController = ScrollController();

  void _openPremiumPaywallSheetMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const BrandedPaywallModalSheet(),
    );
  }

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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _SidebarHeader(),
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
                    label: 'PROP BUILDER',
                    leadingIcons: const [Icons.category_outlined],
                    selected: widget.selectedPage == AppPage.propBuilder,
                    premium: true,
                    showGoldBar: true,
                    onTap: () => widget.onSelectPage?.call(AppPage.propBuilder),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'ACTIVE SLIPS',
                    leadingIcons: const [Icons.groups_outlined],
                    selected: widget.selectedPage == AppPage.watchlist,
                    badge: '${widget.activeSlipCount}',
                    onTap: () => widget.onSelectPage?.call(AppPage.watchlist),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'BUILDER PERFORMANCE',
                    leadingIcons: const [Icons.grid_view_rounded],
                    selected: widget.selectedPage == AppPage.builderPerformance,
                    premium: true,
                    showGoldBar: true,
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.builderPerformance),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'EV SCANNER',
                    selected: widget.selectedPage == AppPage.evScanner,
                    premium: true,
                    showGoldBar: true,
                    leadingIcons: const [Icons.auto_graph],
                    leadingIconColors: const [Color(0xFF36B9FF)],
                    onTap: () => widget.onSelectPage?.call(AppPage.evScanner),
                  ),
                  ValueListenableBuilder<AuthSessionState>(
                    valueListenable: AuthManager.instance.sessionState,
                    builder: (context, authState, _) {
                      if (authState.isPremium) {
                        return Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF122030),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF36B9FF)),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.verified,
                                color: Color(0xFF36B9FF),
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'ELITE ACTIVE',
                                style: TextStyle(
                                  color: Color(0xFF36B9FF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SidebarButton(
                          label: 'UPGRADE',
                          premium: true,
                          showGoldBar: true,
                          leadingIcons: const [Icons.workspace_premium],
                          leadingIconColors: const [Color(0xFFFFC72C)],
                          onTap: _openPremiumPaywallSheetMenu,
                        ),
                      );
                    },
                  ),
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
                    label: 'GOBLINS / DEMONS',
                    selected: widget.selectedPage == AppPage.goblinsDemons,
                    premium: true,
                    leadingIcons: const [Icons.masks_outlined, Icons.whatshot],
                    leadingIconColors: const [
                      Color(0xFF36B9FF),
                      Color(0xFFFF5656),
                    ],
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.goblinsDemons),
                  ),
                  ValueListenableBuilder<AuthSessionState>(
                    valueListenable: AuthManager.instance.sessionState,
                    builder: (context, authState, _) {
                      if (!authState.isOwner) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SidebarButton(
                          label: 'DATA ADMIN',
                          selected: widget.selectedPage == AppPage.dataAdmin,
                          showGoldBar: true,
                          leadingIcons: const [
                            Icons.admin_panel_settings_outlined,
                          ],
                          leadingIconColors: const [app_colors.AppColors.gold],
                          onTap: () =>
                              widget.onSelectPage?.call(AppPage.dataAdmin),
                        ),
                      );
                    },
                  ),
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
  const _SidebarHeader();

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
        const Row(
          children: [
            Icon(Icons.circle, color: app_colors.AppColors.blue, size: 7),
            SizedBox(width: 6),
            Text(
              'SYSTEM ONLINE',
              style: TextStyle(
                color: app_colors.AppColors.blue,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
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

class SidebarButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool premium;
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
    this.premium = false,
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
    final isActiveWatchlist = label.toUpperCase() == 'ACTIVE SLIPS';
    final watchlistHasActiveSlips =
        isActiveWatchlist && (int.tryParse((badge ?? '0').trim()) ?? 0) > 0;
    final textColor = selected || watchlistHasActiveSlips
        ? const Color(0xFFFFC400)
        : Colors.white;
    final textWeight = selected || watchlistHasActiveSlips
        ? FontWeight.w900
        : FontWeight.w700;
    return InkWell(
      onTap: onTap,
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
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 10.5,
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
            if (badge == null && premium)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC400),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium,
                      size: 12,
                      color: Color(0xFF07131F),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'PRO',
                      style: TextStyle(
                        color: Color(0xFF07131F),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  final List<SlipSelection> selections;
  final void Function(PropData prop, PickSide side) onSelect;
  final String sportFilter;
  final AppPage selectedPage;

  const MainDashboard({
    super.key,
    required this.selections,
    required this.onSelect,
    required this.sportFilter,
    required this.selectedPage,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _boardVerticalController = ScrollController();
  final ScrollController _categoryHorizontalController = ScrollController();
  Timer? _searchDebounce;
  final String _searchQuery = '';
  String _selectedSite = 'PRIZEPICKS';
  String _selectedCategory = 'ALL';
  final String _selectedSide = 'All';
  final String _selectedTier = 'All';
  int _minConfidence = 0;
  String _sortBy = 'source';
  DateTime _currentTime = DateTime.now();
  Timer? _clockTimer;
  DateTime? _lastUpdated;
  List<PropData> _latestProps = const [];
  int _facetTotal = 0;
  Map<String, int> _categoryCounts = const {};
  List<PropData> _evScannerProps = const [];
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
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _clockTimer?.cancel();
    _boardVerticalController.dispose();
    _categoryHorizontalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sportFilter != widget.sportFilter && mounted) {
      setState(() {
        _selectedCategory = 'ALL';
        _latestProps = const [];
        _facetTotal = 0;
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
      _facetTotal = facetTotal;
      _categoryCounts = categoryCounts;
      _lastUpdated = DateTime.now();
    });
    boardPropCountNotifier.value = propCount;
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
    final selectedSport = _normalizeSport(widget.sportFilter);
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
      'DRAFT PICKS',
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

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: books.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final book = books[index];
                final selected = _selectedSite == book;
                return OutlinedButton(
                  onPressed: () => setState(() {
                    _selectedSite = book;
                    _selectedCategory = 'ALL';
                    _latestProps = const [];
                    _facetTotal = 0;
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
      ],
    );
  }

  Widget _buildBoardIntelligence() {
    final selectedProps = <String, PropData>{
      for (final selection in widget.selections)
        selection.prop.id: selection.prop,
    }.values.toList(growable: false);
    final props = selectedProps.isNotEmpty ? selectedProps : _visibleProps;
    final metricScope = selectedProps.isNotEmpty
        ? 'Across selected props'
        : 'Across visible props';
    final top = props.isEmpty
        ? null
        : ([...props]..sort((a, b) => b.edge.compareTo(a.edge))).first;
    final averageEdge = props.isEmpty
        ? 0.0
        : props.fold<double>(0, (sum, prop) => sum + prop.edge) / props.length;
    final hitLeader = props.isEmpty
        ? null
        : ([
            ...props,
          ]..sort((a, b) => b.confidence.compareTo(a.confidence))).first;
    final entries = <(String, String, String)>[
      (
        'TOP EDGE',
        top?.player ?? 'Waiting for props',
        top == null ? '--' : '+${top.edge.toStringAsFixed(2)}%',
      ),
      (
        'AVG EDGE',
        '${averageEdge >= 0 ? '+' : ''}${averageEdge.toStringAsFixed(2)}%',
        metricScope,
      ),
      (
        'HIGHEST HIT RATE',
        hitLeader?.player ?? '--',
        hitLeader == null ? '--' : '${hitLeader.confidence}%',
      ),
      (
        'PROPS WITH EDGE',
        '${props.where((p) => p.edge > 0).length}',
        '${props.length} visible',
      ),
      (
        'LAST UPDATED',
        _formatLastUpdated(_lastUpdated),
        _formatLocalDate(_currentTime),
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
    int categoryCount(String category) =>
        category == 'ALL' ? _facetTotal : _categoryCounts[category] ?? 0;
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
                : widget.selectedPage == AppPage.evScanner
                ? _isEvScannerLoading && _evScannerProps.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.gold,
                          ),
                        )
                      : _evScannerError != null && _evScannerProps.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Unable to load +EV feed.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _evScannerError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF9AA7B6),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton(
                                  onPressed: () {
                                    unawaited(_loadEvScannerProps());
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _evScannerProps.isEmpty
                      ? const Center(
                          child: Text(
                            'No positive EV props available yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.gold,
                          onRefresh: _loadEvScannerProps,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 16),
                            itemCount: _evScannerProps.length,
                            itemBuilder: (context, index) {
                              final prop = _evScannerProps[index];
                              final market = _propMarket(prop);
                              return PositiveEvScannerCard(
                                player: prop.player,
                                propType: market.isEmpty ? prop.market : market,
                                lineValue: prop.line,
                                slowBookmaker: prop.sportsbook,
                                slowBookOdds: (prop.overOdds ?? -110).round(),
                                evPercentage: prop.evPercentage ?? 0,
                                fairProbability: prop.fairProbability ?? 0,
                              );
                            },
                          ),
                        )
                : widget.selectedPage == AppPage.scoreboard
                ? const LiveScoreboardTickerGridWidget()
                : widget.selectedPage == AppPage.propAlerts
                ? PropAlertsPage(alerts: alertsForPage)
                : widget.selectedPage == AppPage.analytics
                ? AnalyticsPage(selectedSport: widget.sportFilter)
                : widget.selectedPage == AppPage.lineMovement
                ? LineMovementPage(selectedSport: widget.sportFilter)
                : widget.selectedPage == AppPage.dataAdmin
                ? const DataAdminPage()
                : widget.selectedPage == AppPage.intelligenceLab
                ? IntelligenceLabPage(selections: widget.selections)
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
                          _buildBoardIntelligence(),
                          const SizedBox(height: 12),
                          if (_selectedSite != 'ALL') ...[
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
                            onSelect: widget.onSelect,
                            sportFilter: widget.sportFilter,
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

      await File(savePath).writeAsString(payload, flush: true);
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
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final selected = picked.files.first;
      String? content;

      final bytes = selected.bytes;
      if (bytes != null) {
        content = utf8.decode(bytes);
      } else if (selected.path != null) {
        content = await File(selected.path!).readAsString();
      }

      if (content == null || content.trim().isEmpty) {
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
        child: ClipOval(
          child: Image.asset(
            'assets/branding/prop_intelligence_logo.png',
            fit: BoxFit.cover,
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

class _GuideSectionHeader extends StatelessWidget {
  const _GuideSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: app_colors.AppColors.gold.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: app_colors.AppColors.borderGold),
            ),
            child: Icon(icon, color: app_colors.AppColors.gold, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: app_colors.AppColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: app_colors.AppColors.textMuted,
                    fontSize: 11,
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

class _GuideTip extends StatelessWidget {
  const _GuideTip({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: app_colors.AppColors.gold,
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF06111B),
                fontSize: 11,
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
                  title,
                  style: const TextStyle(
                    color: app_colors.AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: app_colors.AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
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

class _GuideCallout extends StatelessWidget {
  const _GuideCallout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: app_colors.AppColors.gold.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: app_colors.AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: app_colors.AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideTerm extends StatelessWidget {
  const _GuideTerm({required this.term, required this.definition});

  final String term;
  final String definition;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            term,
            style: const TextStyle(
              color: app_colors.AppColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            definition,
            style: const TextStyle(
              color: app_colors.AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class TopNavigation extends StatelessWidget {
  final AppPage selectedPage;
  final VoidCallback onOpenPropAlerts;
  final ValueChanged<AppPage> onTabSelected;

  const TopNavigation({
    super.key,
    required this.selectedPage,
    required this.onOpenPropAlerts,
    required this.onTabSelected,
  });

  void _showGlossary(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: app_colors.AppColors.panel,
        title: const Row(
          children: [
            Icon(Icons.school_outlined, color: app_colors.AppColors.gold),
            SizedBox(width: 10),
            Text('Prop Intelligence Guide'),
          ],
        ),
        content: const SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GuideSectionHeader(
                  icon: Icons.route_rounded,
                  title: 'QUICK START',
                  subtitle: 'A repeatable four-step research workflow',
                ),
                _GuideTip(
                  number: '1',
                  title: 'Start with the board',
                  body:
                      'Choose a sport, compare available lines and open a player when the market fits your research goal.',
                ),
                _GuideTip(
                  number: '2',
                  title: 'Check multiple signals',
                  body:
                      'Use projection, edge, recent form, matchup and line movement together—not one metric alone.',
                ),
                _GuideTip(
                  number: '3',
                  title: 'Verify before saving',
                  body:
                      'Confirm the live line, injury status and game time before adding a selection to your slip.',
                ),
                _GuideTip(
                  number: '4',
                  title: 'Track and learn',
                  body:
                      'Save researched slips and review graded performance to identify what is and is not working.',
                ),
                SizedBox(height: 18),
                _GuideSectionHeader(
                  icon: Icons.menu_book_rounded,
                  title: 'KEY TERMS',
                  subtitle: 'Plain-language definitions used across the app',
                ),
                _GuideTerm(
                  term: 'Edge',
                  definition:
                      'The model’s estimated advantage compared with the offered line or odds.',
                ),
                _GuideTerm(
                  term: 'Confidence',
                  definition:
                      'How strongly the available model inputs support a projection. It is not the same as hit probability.',
                ),
                _GuideTerm(
                  term: '+EV',
                  definition:
                      'A long-run expected-value advantage based on estimated fair probability and available odds.',
                ),
                _GuideTerm(
                  term: 'Correlation',
                  definition:
                      'How two prop outcomes tend to move together. Positive helps parlay alignment; negative can create conflict.',
                ),
                _GuideTerm(
                  term: 'Line movement',
                  definition:
                      'A change in the sportsbook’s posted number or price. Confirm the current value before acting.',
                ),
                _GuideTerm(
                  term: 'Goblin / Demon',
                  definition:
                      'A visual risk tier. Goblins represent more conservative or favorable profiles; Demons represent more aggressive, volatile profiles.',
                ),
                _GuideTerm(
                  term: 'Game script',
                  definition:
                      'A hypothetical game environment—such as a blowout or shootout—used to stress-test projections.',
                ),
                SizedBox(height: 12),
                _GuideSectionHeader(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'PRO TIPS',
                  subtitle: 'Small habits that strengthen the process',
                ),
                _GuideCallout(
                  icon: Icons.compare_arrows_rounded,
                  text:
                      'Shop the line. Even a half-point difference can materially change the quality of a prop.',
                ),
                _GuideCallout(
                  icon: Icons.warning_amber_rounded,
                  text:
                      'Treat unusually strong outputs as a reason to investigate—not as a guaranteed result.',
                ),
                _GuideCallout(
                  icon: Icons.health_and_safety_outlined,
                  text:
                      'Set limits, never chase losses and keep play recreational. Analytics are decision support only.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideButton(BuildContext context) {
    return Tooltip(
      message: 'Open the platform guide and betting glossary',
      child: IconButton(
        onPressed: () => _showGlossary(context),
        icon: const Icon(
          Icons.help_center_outlined,
          color: app_colors.AppColors.gold,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required String label,
    required AppPage page,
    required IconData icon,
    bool premium = false,
  }) {
    final selected = selectedPage == page;

    return Tooltip(
      message: switch (page) {
        AppPage.board => 'Browse and compare today’s available props',
        AppPage.scoreboard => 'Follow live, upcoming, and final games',
        AppPage.analytics => 'Review model edge and market coverage',
        AppPage.lineMovement => 'Track changes across sportsbook lines',
        AppPage.intelligenceLab =>
          'Model correlation, scripts, and historical analogs',
        _ => label,
      },
      child: InkWell(
        onTap: () => onTabSelected(page),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(14, 15, 14, 13),
          decoration: BoxDecoration(
            color: selected
                ? app_colors.AppColors.gold.withValues(alpha: .07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? app_colors.AppColors.gold : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? app_colors.AppColors.gold
                    : app_colors.AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? app_colors.AppColors.gold
                      : app_colors.AppColors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              if (premium) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: app_colors.AppColors.gold,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: Color(0xFF06111B),
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchPlayersButton() {
    return Tooltip(
      message: 'Search players and open detailed prop research',
      child: InkWell(
        onTap: () => onTabSelected(AppPage.searchPlayers),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF091722),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: app_colors.AppColors.borderGold),
          ),
          child: const Icon(
            Icons.search_rounded,
            color: app_colors.AppColors.gold,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildAlertButton() {
    return Tooltip(
      message: 'View prop alerts and monitored conditions',
      child: InkWell(
        onTap: onOpenPropAlerts,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF091722),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: app_colors.AppColors.border),
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            color: app_colors.AppColors.gold,
            size: 19,
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton() {
    return Tooltip(
      message: 'Refresh props',
      child: InkWell(
        onTap: () => boardRefreshRequestNotifier.value++,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF091722),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: app_colors.AppColors.border),
          ),
          child: const Icon(
            Icons.refresh_rounded,
            color: app_colors.AppColors.gold,
            size: 19,
          ),
        ),
      ),
    );
  }

  String get _pageTitle => switch (selectedPage) {
    AppPage.board => 'MARKET BOARD',
    AppPage.scoreboard => 'LIVE SCOREBOARD',
    AppPage.analytics => 'PERFORMANCE ANALYTICS',
    AppPage.lineMovement => 'LINE MOVEMENT',
    AppPage.intelligenceLab => 'INTELLIGENCE LAB',
    AppPage.searchPlayers => 'PLAYER SEARCH',
    AppPage.propAlerts => 'PROP ALERTS',
    AppPage.propBuilder => 'PROP BUILDER',
    AppPage.watchlist => 'ACTIVE SLIPS',
    AppPage.builderPerformance => 'BUILDER PERFORMANCE',
    AppPage.evScanner => 'EV SCANNER',
    AppPage.goblinsDemons => 'GOBLINS / DEMONS',
    AppPage.dataAdmin => 'DATA ADMIN',
  };

  String get _pageSubtitle => switch (selectedPage) {
    AppPage.board => 'Scan today’s markets and compare available value',
    AppPage.scoreboard => 'Follow live, upcoming and completed games',
    AppPage.analytics => 'Measure model signals and market coverage',
    AppPage.lineMovement => 'Monitor number and price changes in real time',
    AppPage.intelligenceLab => 'Stress-test correlation, context and scenarios',
    AppPage.searchPlayers => 'Open focused player and market research',
    AppPage.propAlerts => 'Review monitored conditions and changes',
    AppPage.propBuilder => 'Build a disciplined, research-backed slip',
    AppPage.watchlist => 'Review props and slips you are actively monitoring',
    AppPage.builderPerformance => 'Review outcomes and improve your process',
    AppPage.evScanner => 'Surface estimated positive-value opportunities',
    AppPage.goblinsDemons => 'Compare conservative and aggressive profiles',
    AppPage.dataAdmin => 'Manage platform data sources',
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
                SizedBox(
                  width: 210,
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
                          const SizedBox(width: 7),
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
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 42,
                  color: app_colors.AppColors.border,
                ),
                const SizedBox(width: 10),
              ],
              _buildSearchPlayersButton(),
              const SizedBox(width: 9),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildNavItem(
                        label: 'BOARD',
                        page: AppPage.board,
                        icon: Icons.dashboard_customize_outlined,
                      ),
                      const SizedBox(width: 6),
                      _buildNavItem(
                        label: 'SCOREBOARD',
                        page: AppPage.scoreboard,
                        icon: Icons.sports_score_rounded,
                      ),
                      const SizedBox(width: 6),
                      _buildNavItem(
                        label: 'ANALYTICS',
                        page: AppPage.analytics,
                        icon: Icons.analytics_outlined,
                        premium: true,
                      ),
                      const SizedBox(width: 6),
                      _buildNavItem(
                        label: 'LINE MOVEMENT',
                        page: AppPage.lineMovement,
                        icon: Icons.stacked_line_chart_rounded,
                        premium: true,
                      ),
                      const SizedBox(width: 6),
                      _buildNavItem(
                        label: 'LAB',
                        page: AppPage.intelligenceLab,
                        icon: Icons.science_outlined,
                        premium: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              _buildGuideButton(context),
              _buildRefreshButton(),
              const SizedBox(width: 6),
              _buildAlertButton(),
            ],
          ),
        );
      },
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
  final String selectedSite;
  final String selectedCategory;
  final String selectedSide;
  final String selectedTier;
  final int minConfidence;
  final String sortBy;
  final String searchQuery;
  final void Function(List<PropData>, int, int, Map<String, int>)?
  onPropsLoaded;

  const PropGrid({
    super.key,
    required this.selections,
    required this.onSelect,
    required this.sportFilter,
    required this.selectedSite,
    required this.selectedCategory,
    required this.selectedSide,
    required this.selectedTier,
    required this.minConfidence,
    required this.sortBy,
    required this.searchQuery,
    this.onPropsLoaded,
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

class _PropGridState extends State<PropGrid> {
  static const int _visiblePropStep = 75;
  final ApiService _apiService = ApiService();
  late Future<List<PropData>> _propsFuture;
  List<_PreparedProp> _preparedProps = const [];
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
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
    final imagePath = _resolvePlayerImagePath(prop.imagePath);
    final isNetwork =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');
    if (!isNetwork) {
      return Image.asset(
        imagePath,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) {
          final officialUrl = _officialMlbHeadshot(prop.player);
          if (officialUrl != null) {
            return CachedNetworkImage(
              imageUrl: officialUrl,
              fit: BoxFit.contain,
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
      fit: BoxFit.contain,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      memCacheWidth: (size * 2).round(),
      memCacheHeight: (size * 2).round(),
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

  Widget _buildPortraitPropCard(PropData prop, PickSide? selectedSide) {
    final advisedSide =
        prop.recommendedSide.toUpperCase().contains('UNDER') ||
            prop.pick.toUpperCase() == 'UNDER'
        ? PickSide.under
        : PickSide.over;
    final market = _marketCategory(prop);
    final confidence = prop.confidence.clamp(0, 100);

    Widget sideButton(PickSide side) {
      final selected = side == selectedSide;
      final advised = side == advisedSide;
      final label = side == PickSide.over ? 'OVER' : 'UNDER';
      return Expanded(
        child: OutlinedButton(
          onPressed: () => widget.onSelect(prop, side),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            foregroundColor: selected || advised
                ? AppColors.gold
                : Colors.white,
            backgroundColor: selected
                ? AppColors.gold.withValues(alpha: .16)
                : const Color(0xFF091620),
            side: BorderSide(
              color: selected || advised ? AppColors.gold : AppColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
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
                  '$market • ${prop.localGameTimeDisplay}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
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
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.gold),
            ),
            child: Text(
              '★ BEST PICK: ${advisedSide == PickSide.over ? 'OVER' : 'UNDER'}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'EDGE • Model leans $confidence%',
            style: const TextStyle(color: AppColors.muted, fontSize: 7.5),
          ),
          const SizedBox(height: 3),
          const Text(
            'Live market model',
            style: TextStyle(color: AppColors.muted, fontSize: 7),
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
                    '$confidence%',
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
              value: confidence / 100,
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
            onPressed: () => widget.onSelect(prop, side),
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
    _propsFuture = _loadProps();
    boardRefreshRequestNotifier.addListener(_handleBoardRefreshRequest);
  }

  void _handleBoardRefreshRequest() {
    unawaited(_refreshProps());
  }

  @override
  void dispose() {
    boardRefreshRequestNotifier.removeListener(_handleBoardRefreshRequest);
    super.dispose();
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
    if (cached.isNotEmpty) {
      _preparedProps = _prepareProps(cached);
      widget.onPropsLoaded?.call(
        cached,
        _apiService.lastPropsCount,
        _apiService.lastFacetCount,
        _apiService.lastCategoryCounts,
      );
      unawaited(_refreshFirstPageFromNetwork(requestKey));
      return cached;
    }
    final liveProps = await _fetchPropsPage();
    if (!mounted || requestKey != _queryKey) return const [];
    final props = liveProps;
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
      final fresh = await _fetchPropsPage();
      if (!mounted || requestKey != _queryKey) return;
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
      final merged = <String, PropData>{
        for (final prepared in _preparedProps) prepared.prop.id: prepared.prop,
        for (final prop in next) prop.id: prop,
      }.values.toList(growable: false);
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
      await _apiService.wakeBackend();
      await _apiService.syncProps();
      await SlipManager.refreshSelectedProps(_apiService);
      if (!mounted) {
        return;
      }
      setState(() {
        _propsFuture = _loadProps();
      });
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
    setState(() {
      _propsFuture = _loadProps();
    });
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
            final normalizedSport = _normalizeSport(widget.sportFilter);
            final normalizedSite = _normalizeSite(widget.selectedSite);
            final search = widget.searchQuery;

            final filtered = allPrepared.where((prepared) {
              final sportMatches =
                  widget.sportFilter == 'ALL' ||
                  prepared.normalizedSport == normalizedSport;
              final siteMatches =
                  widget.selectedSite == 'ALL' ||
                  prepared.normalizedSite == normalizedSite;
              final searchMatches =
                  search.isEmpty || prepared.searchText.contains(search);
              return sportMatches && siteMatches && searchMatches;
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

            DateTime propStartTime(PropData prop) {
              final raw = prop.startTimeUtc.isNotEmpty
                  ? prop.startTimeUtc
                  : prop.gameStartTime;
              final parsed = DateTime.tryParse(raw);
              return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
            }

            final sortedProps = [...props]
              ..sort((left, right) {
                switch (widget.sortBy) {
                  case 'source':
                    return 0;
                  case 'edge':
                    return right.edge.compareTo(left.edge);
                  case 'premium':
                    final rankDiff = tierRank(right.tier) - tierRank(left.tier);
                    if (rankDiff != 0) {
                      return rankDiff;
                    }
                    return right.confidence.compareTo(left.confidence);
                  case 'time':
                    return propStartTime(left).compareTo(propStartTime(right));
                  case 'confidence':
                  default:
                    return right.confidence.compareTo(left.confidence);
                }
              });
            if (props.isEmpty) {
              return const CentralPropsDisplayGridCanvas();
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
                        mainAxisExtent: 330,
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
                          child: _buildPortraitPropCard(prop, selected?.side),
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
    final lower = message.toLowerCase();
    if (lower.contains('timeoutexception') || lower.contains('timed out')) {
      return 'The live prop feed is taking longer than expected. The backend is online; retry while it finishes loading the full dataset.';
    }
    if (lower.contains('unable to connect') ||
        lower.contains('connection refused') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'The live prop service is temporarily unavailable. Your last saved board remains protected; check your connection and retry.';
    }
    return message;
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
                child: ClipOval(child: _buildPropCardImage(prop)),
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

  Widget _buildPropCardImage(PropData prop) {
    final imagePath = _resolvePlayerImagePath(prop.imagePath);
    final isNetwork =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');
    if (!isNetwork) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
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
      alignment: Alignment.topCenter,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      memCacheWidth: 72,
      memCacheHeight: 72,
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
