import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'controllers/active_slip_controller.dart';
import 'models/prop_data.dart';
import 'pages/analytics_page.dart';
import 'pages/line_movement_page.dart';
import 'pages/scoreboard_page.dart';
import 'screens/prop_builder_performance_screen.dart';
import 'screens/prop_builder_screen.dart';
import 'screens/prop_watchlist_screen.dart';
import 'models/slip_selection.dart';
import 'services/api_service.dart';
import 'theme/app_scroll_behavior.dart';
import 'widgets/active_slip_panel.dart';

final Stopwatch _startupStopwatch = Stopwatch()..start();

void _startupLog(String message) {
  debugPrint('[startup +${_startupStopwatch.elapsedMilliseconds}ms] $message');
}

Future<void> _configureDesktopWindow() async {
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
      title: 'The Daily Spin',
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
        return false;
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

  runApp(const DailySpinApp());
  _startupLog('runApp() called');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _startupLog('first frame rendered');
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
  searchPlayers,
  scoreboard,
  propAlerts,
  analytics,
  lineMovement,
  dataAdmin,
}

const Map<String, List<String>> sportPropCategories = {
  'NBA': [
    'ALL',
    'POINTS',
    'REBOUNDS',
    'ASSISTS',
    'PRA',
    'BLOCKS',
    'STEALS',
    '3-POINTERS MADE',
  ],
  'WNBA': [
    'ALL',
    'POINTS',
    'REBOUNDS',
    'ASSISTS',
    'PRA',
    'BLOCKS',
    'STEALS',
    '3-POINTERS MADE',
  ],
  'NFL': [
    'ALL',
    'PASSING YARDS',
    'RUSHING YARDS',
    'RECEIVING YARDS',
    'TOTAL TOUCHDOWNS',
    'RECEPTIONS',
    'PASS ATTEMPTS',
    'COMPLETIONS',
  ],
  'SOCCER': [
    'ALL',
    'SHOTS',
    'SHOTS ON TARGET',
    'GOALS',
    'ASSISTS',
    'PASSES ATTEMPTED',
    'SAVES',
    'TACKLES',
  ],
  'MLB': [
    'ALL',
    'PITCHER STRIKEOUTS',
    'PITCHER OUTS',
    'HITS',
    'HITS ALLOWED',
    'HOME RUNS',
    'RBIS',
    'TOTAL BASES',
  ],
  'TENNIS': ['ALL', 'ACES', 'TOTAL GAMES WON', 'MATCH WINNER'],
  'PGA': [
    'ALL',
    'BIRDIES OR BETTER',
    'ROUND SCORE',
    'FAIRWAYS HIT',
    'GREENS IN REGULATION',
    'HOLES PLAYED',
    'MAKE CUT',
  ],
  'UFC': [
    'ALL',
    'SIGNIFICANT STRIKES',
    'TOTAL STRIKES',
    'TAKEDOWNS',
    'TAKEDOWN ATTEMPTS',
    'CONTROL TIME',
    'KNOCKDOWNS',
    'SUBMISSION ATTEMPTS',
    'FIGHT TIME',
    'ROUNDS',
    'FIGHT WINNER',
    'METHOD OF VICTORY',
  ],
};

class AppColors {
  static const background = Color(0xFF050A0F);
  static const leftSidebar = Color(0xFF09131D);
  static const rightSidebar = Color(0xFF071019);
  static const panel = Color(0xFF0C1824);
  static const border = Color(0xFF283846);
  static const gold = Color(0xFFD99A17);
  static const goldBright = Color(0xFFF2BC35);
  static const text = Color(0xFFF3F1EC);
  static const muted = Color(0xFF8996A6);
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

class DailySpinApp extends StatelessWidget {
  const DailySpinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Daily Spin',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Segoe UI',
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.dragged)) {
              return AppColors.goldBright;
            }
            if (states.contains(MaterialState.hovered)) {
              return AppColors.gold;
            }
            return AppColors.gold.withValues(alpha: 0.82);
          }),
          trackColor: MaterialStateProperty.all(const Color(0xFF101D28)),
          trackBorderColor: MaterialStateProperty.all(const Color(0xFF8B6813)),
          radius: const Radius.circular(8),
          thickness: MaterialStateProperty.all(9),
          interactive: true,
        ),
      ),
      home: const DailySpinShell(),
    );
  }
}

class DailySpinShell extends StatelessWidget {
  const DailySpinShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C13),
      body: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD9A514), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD9A514).withValues(alpha: 0.2),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1100) {
              return const DesktopDashboard();
            }

            return const MobilePlaceholder();
          },
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
  bool _showSavedSlips = false;
  final List<SlipSelection> _slipSelections = [];
  bool _isSavingSlip = false;
  String? _slipMessage;
  AppPage _selectedPage = AppPage.board;
  String _selectedBoardSport = 'ALL';
  final Set<String> _selectedBuilderSports = {'WNBA'};
  bool _hasManualBuilderSportsSelection = false;

  @override
  void initState() {
    super.initState();
    _startupLog('active slip load start');
    unawaited(
      _activeSlipController.load().then(
        (_) {
          _startupLog(
            'active slip load complete (${_activeSlipController.legCount} legs)',
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          _startupLog('active slip load failed: $error');
        },
      ),
    );
  }

  @override
  void dispose() {
    _activeSlipController.dispose();
    super.dispose();
  }

  void _openSavedSlips() {
    setState(() {
      _showSavedSlips = true;
    });
  }

  void _switchToPage(AppPage page, {String source = 'ui'}) {
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

  void _openBuilder() {
    setState(() {
      _showSavedSlips = false;
      _seedBuilderSportFromBoardIfNeeded();
    });
    _switchToPage(AppPage.propBuilder, source: 'quick-open-builder');
  }

  void _seedBuilderSportFromBoardIfNeeded() {
    if (_hasManualBuilderSportsSelection || _selectedBoardSport == 'ALL') {
      return;
    }
    _selectedBuilderSports
      ..clear()
      ..add(_selectedBoardSport);
  }

  void _handleBuilderSportsChanged(List<String> sports) {
    setState(() {
      _selectedBuilderSports
        ..clear()
        ..addAll(sports.where((sport) => sport.trim().isNotEmpty));
      if (_selectedBuilderSports.isNotEmpty) {
        _hasManualBuilderSportsSelection = true;
      }
    });
  }

  void _resetBuilderSportsAutoSync() {
    setState(() {
      _hasManualBuilderSportsSelection = false;
      _seedBuilderSportFromBoardIfNeeded();
    });
  }

  void _selectBoardSport(String sport) {
    setState(() {
      _showSavedSlips = false;
      _selectedBoardSport = sport;
      if (!_hasManualBuilderSportsSelection && sport != 'ALL') {
        _selectedBuilderSports
          ..clear()
          ..add(sport);
      }
    });
    _switchToPage(AppPage.board, source: 'sport-filter');
  }

  int _mainPageIndex() {
    switch (_selectedPage) {
      case AppPage.board:
      case AppPage.searchPlayers:
      case AppPage.scoreboard:
      case AppPage.propAlerts:
      case AppPage.analytics:
      case AppPage.lineMovement:
      case AppPage.dataAdmin:
        return 0;
      case AppPage.propBuilder:
        return 1;
      case AppPage.watchlist:
        return 2;
      case AppPage.builderPerformance:
        return 3;
    }
  }

  Widget _buildMainContent() {
    return IndexedStack(
      index: _mainPageIndex(),
      children: [
        MainDashboard(
          selections: _slipSelections,
          onSelect: _toggleSelection,
          sportFilter: _selectedBoardSport,
          selectedPage: _selectedPage,
          onSelectTopPage: (page) {
            _switchToPage(page, source: 'top-nav');
          },
        ),
        PropBuilderScreen(
          activeSlipController: _activeSlipController,
          isManualSportsMode: _hasManualBuilderSportsSelection,
          initialSelectedSports: _selectedBuilderSports.toList(),
          onSelectedSportsChanged: _handleBuilderSportsChanged,
          onResetSportsAutoSync: _resetBuilderSportsAutoSync,
        ),
        PropWatchlistScreen(activeSlipController: _activeSlipController),
        const PropBuilderPerformanceScreen(),
      ],
    );
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
        } else {
          _slipSelections[existingIndex] = selection;
          unawaited(
            _activeSlipController.updateLeg(_selectionToLeg(selection)),
          );
        }
      } else {
        _slipSelections.add(selection);
        unawaited(_activeSlipController.addLegs([_selectionToLeg(selection)]));
      }
    });
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
      _slipMessage = null;
    });

    try {
      await _apiService.saveSlip(selections: selections, stake: stake);
      if (!mounted) {
        return;
      }
      await _activeSlipController.clear();
      setState(() {
        _slipSelections.clear();
        _slipMessage = 'Slip saved successfully.';
        _showSavedSlips = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _slipMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSlip = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: leftSidebarWidth,
          child: LeftSidebar(
            selectedPage: _selectedPage,
            selectedSport: _selectedBoardSport,
            onSelectPage: (page) {
              setState(() {
                _showSavedSlips = false;
                if (page == AppPage.propBuilder) {
                  _seedBuilderSportFromBoardIfNeeded();
                }
                if (page != AppPage.board) {
                  _selectedBoardSport = 'ALL';
                }
              });
              _switchToPage(page, source: 'left-sidebar');
            },
            onSelectSport: _selectBoardSport,
          ),
        ),
        Expanded(child: _buildMainContent()),
        SizedBox(
          width: rightSidebarWidth,
          child: RightSidebar(
            activeSlipController: _activeSlipController,
            onSave: _openLockSlipDialog,
            isSaving: _isSavingSlip,
            message: _slipMessage,
            showSavedSlips: _showSavedSlips,
            onShowSavedSlips: _openSavedSlips,
            onShowBuilder: _openBuilder,
          ),
        ),
      ],
    );
  }
}

class LeftSidebar extends StatefulWidget {
  final AppPage selectedPage;
  final String selectedSport;
  final ValueChanged<AppPage>? onSelectPage;
  final ValueChanged<String>? onSelectSport;

  const LeftSidebar({
    super.key,
    required this.selectedPage,
    required this.selectedSport,
    this.onSelectPage,
    this.onSelectSport,
  });

  @override
  State<LeftSidebar> createState() => _LeftSidebarState();
}

class _LeftSidebarState extends State<LeftSidebar> {
  final ScrollController _sidebarScrollController = ScrollController();

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
      'PGA',
      'WNBA',
      'TENNIS',
      'SOCCER',
      'NHL',
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
                  SidebarButton(
                    label: 'BOARD',
                    selected:
                        widget.selectedPage == AppPage.board &&
                        widget.selectedSport == 'ALL',
                    onTap: () => widget.onSelectSport?.call('ALL'),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'PROP BUILDER',
                    selected: widget.selectedPage == AppPage.propBuilder,
                    premium: true,
                    onTap: () => widget.onSelectPage?.call(AppPage.propBuilder),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'WATCHLIST',
                    selected: widget.selectedPage == AppPage.watchlist,
                    onTap: () => widget.onSelectPage?.call(AppPage.watchlist),
                  ),
                  const SizedBox(height: 6),
                  SidebarButton(
                    label: 'BUILDER PERFORMANCE',
                    selected: widget.selectedPage == AppPage.builderPerformance,
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.builderPerformance),
                  ),
                  const Divider(height: 22, color: AppColors.border),
                  ...sports.map(
                    (sport) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: SidebarButton(
                        label: sport,
                        selected:
                            widget.selectedPage == AppPage.board &&
                            widget.selectedSport == sport,
                        onTap: () => widget.onSelectSport?.call(sport),
                      ),
                    ),
                  ),
                ],
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'THE DAILY SPIN',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 5),
        Text(
          'PROP INTELLIGENCE',
          style: TextStyle(
            color: AppColors.goldBright,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class SidebarButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool premium;
  final String? badge;
  final VoidCallback? onTap;

  const SidebarButton({
    super.key,
    required this.label,
    this.selected = false,
    this.premium = false,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? const Color(0xFFFFC400) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (premium || badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC400),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge ?? 'PRO',
                  style: TextStyle(
                    color: Color(0xFF07131F),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
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
  final ValueChanged<AppPage> onSelectTopPage;

  const MainDashboard({
    super.key,
    required this.selections,
    required this.onSelect,
    required this.sportFilter,
    required this.selectedPage,
    required this.onSelectTopPage,
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
  String _searchQuery = '';
  String _selectedSite = 'ALL';
  String _selectedCategory = 'ALL';
  String _selectedSide = 'All';
  String _selectedTier = 'All';
  int _minConfidence = 0;
  String _sortBy = 'confidence';
  int _propCount = 0;
  DateTime _currentTime = DateTime.now();
  Timer? _clockTimer;
  DateTime? _lastUpdated;
  List<PropData> _latestProps = const [];
  List<_PropAlertData> _propAlerts = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPropAlerts());
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
      });
    }
  }

  void _handlePropsLoaded(List<PropData> props, int propCount) {
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
      _propCount = propCount;
      _lastUpdated = DateTime.now();
    });
    unawaited(_loadPropAlerts(fallbackProps: props));
  }

  _PropAlertData _parsePropAlert(Map<String, dynamic> value) {
    final edgeRaw = value['edge'];
    final edge = edgeRaw is num
        ? edgeRaw.toInt()
        : int.tryParse('$edgeRaw') ?? 0;
    return _PropAlertData(
      sport: value['sport']?.toString() ?? 'ALL',
      title: value['title']?.toString() ?? 'Prop Alert',
      message: value['message']?.toString() ?? '',
      edge: edge,
      book: value['book']?.toString() ?? 'All Books',
      time: value['time']?.toString() ?? 'now',
    );
  }

  List<_PropAlertData> _fallbackPropAlertsFromProps(List<PropData> props) {
    if (props.isEmpty) {
      return const [
        _PropAlertData(
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
      _PropAlertData(
        sport: _normalizeSport(top.sport),
        title: 'Best Edge Alert',
        message:
            '${top.player} has ${top.confidence}% confidence on ${_propMarket(top)}.',
        edge: top.confidence,
        book: top.sportsbook,
        time: 'now',
      ),
      _PropAlertData(
        sport: topSport.key,
        title: 'Most Active Sport',
        message:
            '${topSport.key} has ${topSport.value} props visible right now.',
        edge: top.confidence,
        book: 'All Books',
        time: 'now',
      ),
      if (hot > 0)
        _PropAlertData(
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

  String _formatLocalTime(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute:$second $period';
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

  String _formatDayOfWeek(DateTime value) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[value.weekday - 1];
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
    final sport = _normalizeSport(widget.sportFilter);
    return sportPropCategories[sport] ?? const ['ALL'];
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

  int _categoryCount(String category) {
    final scoped = _propsBeforeCategoryFilter;
    if (category == 'ALL') {
      return scoped.length;
    }
    return scoped.where((prop) => _marketCategory(prop) == category).length;
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

  @override
  Widget build(BuildContext context) {
    final visibleProps = _visibleProps;
    final alertsForPage = _propAlerts.isNotEmpty
        ? _propAlerts
        : _fallbackPropAlertsFromProps(_latestProps);
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          TopNavigation(
            selectedPage: widget.selectedPage,
            onOpenPropAlerts: () {
              unawaited(_showPropAlertsOverlay(visibleProps));
            },
            onTabSelected: widget.onSelectTopPage,
          ),
          Expanded(
            child: widget.selectedPage == AppPage.searchPlayers
                ? SearchPlayersPage(props: _latestProps)
                : widget.selectedPage == AppPage.scoreboard
                ? ScoreboardPage(selectedSport: widget.sportFilter)
                : widget.selectedPage == AppPage.propAlerts
                ? PropAlertsPage(alerts: alertsForPage)
                : widget.selectedPage == AppPage.analytics
                ? AnalyticsPage(selectedSport: widget.sportFilter)
                : widget.selectedPage == AppPage.lineMovement
                ? LineMovementPage(selectedSport: widget.sportFilter)
                : widget.selectedPage == AppPage.dataAdmin
                ? const DataAdminPage()
                : Scrollbar(
                    controller: _boardVerticalController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 8,
                    radius: const Radius.circular(8),
                    child: SingleChildScrollView(
                      controller: _boardVerticalController,
                      primary: false,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StatsPanel(
                            totalProps: _latestProps.length,
                            dayOfWeek: _formatDayOfWeek(_currentTime),
                            currentTime: _formatLocalTime(_currentTime),
                            currentDate: _formatLocalDate(_currentTime),
                            lastUpdated: _formatLastUpdated(_lastUpdated),
                          ),
                          const SizedBox(height: 20),
                          FilterBar(
                            selectedSite: _selectedSite,
                            onSelectSite: (site) {
                              setState(() {
                                _selectedSite = site;
                                _selectedCategory = 'ALL';
                              });
                            },
                            onReset: () {
                              setState(() {
                                _selectedSite = 'ALL';
                                _selectedCategory = 'ALL';
                                _selectedSide = 'All';
                                _selectedTier = 'All';
                                _minConfidence = 0;
                                _sortBy = 'confidence';
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text(
                                'PROP CATEGORIES',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${visibleProps.length} visible',
                                style: const TextStyle(
                                  color: Color(0xFF8191A5),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 42,
                            child: Scrollbar(
                              controller: _categoryHorizontalController,
                              thumbVisibility: false,
                              child: ListView.separated(
                                controller: _categoryHorizontalController,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                itemCount: _currentCategories.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 7),
                                itemBuilder: (context, index) {
                                  final category = _currentCategories[index];
                                  final selected =
                                      _effectiveSelectedCategory == category;
                                  final count = _categoryCount(category);
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () {
                                      setState(() {
                                        _selectedCategory = category;
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.goldBright
                                            : const Color(0xFF0C1C2A),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: selected
                                              ? AppColors.goldBright
                                              : const Color(0xFF294052),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            category,
                                            style: TextStyle(
                                              color: selected
                                                  ? const Color(0xFF07131F)
                                                  : Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? const Color(0xFF07131F)
                                                  : const Color(0xFF050A0F),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$count',
                                              style: TextStyle(
                                                color: selected
                                                    ? AppColors.goldBright
                                                    : AppColors.muted,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          ClipRRect(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(3),
                            ),
                            child: const LinearProgressIndicator(
                              minHeight: 4,
                              value: 0.56,
                              backgroundColor: AppColors.border,
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.gold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                'Props showing: $_propCount',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Sort: ${_sortBy[0].toUpperCase()}${_sortBy.substring(1)}',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
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

class ActiveTicketBadge extends StatefulWidget {
  final bool isSaving;
  final String? message;

  const ActiveTicketBadge({
    super.key,
    required this.isSaving,
    required this.message,
  });

  @override
  State<ActiveTicketBadge> createState() => _ActiveTicketBadgeState();
}

class _ActiveTicketBadgeState extends State<ActiveTicketBadge> {
  final ApiService _apiService = ApiService();
  int _activeTicketCount = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshActiveTickets());
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshActiveTickets(),
    );
  }

  @override
  void didUpdateWidget(covariant ActiveTicketBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSaving && !widget.isSaving) {
      unawaited(_refreshActiveTickets());
    }
    if (oldWidget.message != widget.message && widget.message != null) {
      unawaited(_refreshActiveTickets());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshActiveTickets() async {
    try {
      final slips = await _apiService.fetchSlips();
      final active = slips.where((slip) {
        final status = slip.status.trim().toLowerCase();
        return status == 'active' ||
            status == 'open' ||
            status == 'live' ||
            status == 'pending';
      }).length;
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTicketCount = active;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.confirmation_number_rounded,
          size: 16,
          color: AppColors.goldBright,
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF5A3B08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$_activeTicketCount',
            style: const TextStyle(
              color: AppColors.goldBright,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
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

  Widget _topNavItem(
    String title, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? const Color(0xFFFFC400) : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchIconButton(VoidCallback onTap) {
    final isSelected = selectedPage == AppPage.searchPlayers;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF07111C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(
              0xFFFFC400,
            ).withValues(alpha: isSelected ? 1 : 0.75),
            width: 1,
          ),
        ),
        child: const Icon(Icons.search, color: Color(0xFFFFC400), size: 18),
      ),
    );
  }

  Widget compactPropAlertsButton(VoidCallback onTap) {
    final isSelected = selectedPage == AppPage.propAlerts;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF07111C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(
              0xFFFFC72C,
            ).withValues(alpha: isSelected ? 1 : 0.75),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active,
              color: Color(0xFFFFC72C),
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              'ALERTS',
              style: TextStyle(
                color: Color(0xFFFFC72C),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _searchIconButton(() {
              onTabSelected(AppPage.searchPlayers);
            }),
            const SizedBox(width: 14),
            _topNavItem(
              'SCOREBOARD',
              selected: selectedPage == AppPage.scoreboard,
              onTap: () => onTabSelected(AppPage.scoreboard),
            ),
            const SizedBox(width: 28),
            _topNavItem(
              'ANALYTICS',
              selected: selectedPage == AppPage.analytics,
              onTap: () => onTabSelected(AppPage.analytics),
            ),
            const SizedBox(width: 28),
            _topNavItem(
              'LINE MOVEMENT',
              selected: selectedPage == AppPage.lineMovement,
              onTap: () => onTabSelected(AppPage.lineMovement),
            ),
            const SizedBox(width: 18),
            compactPropAlertsButton(() {
              onOpenPropAlerts();
            }),
          ],
        ),
      ),
    );
  }
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

class _PropAlertData {
  const _PropAlertData({
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

  final _PropAlertData alert;

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

  final List<_PropAlertData> alerts;

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
  final void Function(List<PropData>, int)? onPropsLoaded;

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
  final String category;
  final String searchText;

  const _PreparedProp({
    required this.prop,
    required this.normalizedSport,
    required this.normalizedSite,
    required this.category,
    required this.searchText,
  });
}

class _PropGridState extends State<PropGrid> {
  static const int _visiblePropStep = 180;
  final ApiService _apiService = ApiService();
  late Future<List<PropData>> _propsFuture;
  List<_PreparedProp> _preparedProps = const [];
  bool _isRefreshing = false;
  String? _refreshError;
  int _visiblePropLimit = _visiblePropStep;

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
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          return _playerPlaceholder(prop.player, size: size);
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: imagePath,
      fit: BoxFit.cover,
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
        category: _marketCategory(prop),
        searchText: searchText,
      );
    }).toList();
  }

  Future<List<PropData>> _loadProps() async {
    final fetchTimer = Stopwatch()..start();
    _startupLog('fetchProps() start');
    final props = await _apiService.fetchProps(
      selectedSide: widget.selectedSide,
      selectedTier: widget.selectedTier,
      minConfidence: widget.minConfidence,
      sortBy: widget.sortBy,
    );
    _startupLog(
      'fetchProps() complete in ${fetchTimer.elapsedMilliseconds}ms (${props.length} props)',
    );
    final prepareTimer = Stopwatch()..start();
    _preparedProps = _prepareProps(props);
    _startupLog(
      'prepareProps() complete in ${prepareTimer.elapsedMilliseconds}ms',
    );
    widget.onPropsLoaded?.call(props, _apiService.lastPropsCount);
    return props;
  }

  Future<void> _refreshProps() async {
    if (_isRefreshing) {
      return;
    }

    setState(() {
      _isRefreshing = true;
      _refreshError = null;
    });

    try {
      await _apiService.syncProps();
      if (!mounted) {
        return;
      }
      setState(() {
        _propsFuture = _loadProps();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshError = error.toString();
      });
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
      _refreshError = null;
      _propsFuture = _loadProps();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PropToolbar(
          isRefreshing: _isRefreshing,
          errorMessage: _refreshError,
          onRefresh: _refreshProps,
        ),
        FutureBuilder<List<PropData>>(
          future: _propsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.goldBright),
                ),
              );
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
              final categoryMatches =
                  widget.selectedCategory == 'ALL' ||
                  prepared.category == widget.selectedCategory;
              final searchMatches =
                  search.isEmpty || prepared.searchText.contains(search);
              return sportMatches &&
                  siteMatches &&
                  categoryMatches &&
                  searchMatches;
            }).toList();

            final props = filtered.map((prepared) => prepared.prop).toList();

            int _tierRank(String tier) {
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

            DateTime _propStartTime(PropData prop) {
              final raw = prop.startTimeUtc.isNotEmpty
                  ? prop.startTimeUtc
                  : prop.gameStartTime;
              final parsed = DateTime.tryParse(raw);
              return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
            }

            final sortedProps = [...props]
              ..sort((left, right) {
                switch (widget.sortBy) {
                  case 'edge':
                    return right.edge.compareTo(left.edge);
                  case 'premium':
                    final rankDiff =
                        _tierRank(right.tier) - _tierRank(left.tier);
                    if (rankDiff != 0) {
                      return rankDiff;
                    }
                    return right.confidence.compareTo(left.confidence);
                  case 'time':
                    return _propStartTime(
                      left,
                    ).compareTo(_propStartTime(right));
                  case 'confidence':
                  default:
                    return right.confidence.compareTo(left.confidence);
                }
              });
            if (props.isEmpty) {
              return const Center(
                child: Text(
                  'No props are currently available for this filter.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                int columns;
                if (constraints.maxWidth >= 980) {
                  columns = 4;
                } else if (constraints.maxWidth >= 640) {
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
                final hasMore = visibleCount < sortedProps.length;

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
                        mainAxisExtent: 420,
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
                          onPressed: () {
                            setState(() {
                              _visiblePropLimit += _visiblePropStep;
                            });
                          },
                          icon: const Icon(Icons.expand_more),
                          label: Text(
                            'LOAD MORE (${sortedProps.length - visibleCount} remaining)',
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

class _PropToolbar extends StatelessWidget {
  final bool isRefreshing;
  final String? errorMessage;
  final Future<void> Function() onRefresh;

  const _PropToolbar({
    required this.isRefreshing,
    required this.errorMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              errorMessage ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
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

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadError({required this.message, required this.onRetry});

  String _friendlyMessage() {
    final lower = message.toLowerCase();
    if (lower.contains('unable to connect') ||
        lower.contains('connection refused') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'The backend at http://127.0.0.1:8010 is offline. Start python_backend/main.py and retry.';
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
  final bool isSaving;
  final String? message;
  final bool showSavedSlips;
  final VoidCallback onShowSavedSlips;
  final VoidCallback onShowBuilder;

  const RightSidebar({
    super.key,
    required this.activeSlipController,
    required this.onSave,
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B151E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVE TICKETS',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ActiveTicketBadge(isSaving: isSaving, message: message),
                        const Spacer(),
                        Text(
                          'Current: ${activeSlipController.legCount} picks',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'CURRENT TICKET',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.receipt_long,
                    color: AppColors.goldBright,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ActiveSlipPanel(
                  controller: activeSlipController,
                  onViewOrLock: onSave,
                  isSaving: isSaving,
                  message: message,
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
  bool _loadingPreview = false;
  String? _error;
  double? _potentialPayout;
  double? _potentialProfit;

  @override
  void initState() {
    super.initState();
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

class MobilePlaceholder extends StatelessWidget {
  const MobilePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Mobile layout will be added later.'));
  }
}
