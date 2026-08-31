import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../layout/responsive_breakpoints.dart';

import '../models/prop_data.dart';
import '../models/scoreboard_game.dart';
import '../models/slip_selection.dart';
import '../services/api_service.dart';
import '../services/prop_book_group.dart';
import '../services/player_image_resolver.dart';
import '../services/slip_manager.dart';
import '../services/user_facing_error.dart';
import '../services/auth_manager.dart';
import '../services/engagement_tracker.dart';
import '../services/prop_board_engine.dart';
import '../services/prop_market_identity.dart';
import '../services/recommendation_access.dart';
import '../services/scoreboard_service.dart';
import '../theme/app_colors.dart' as app_colors;
import '../theme/app_spacing.dart';
import 'injury_impact_alert.dart';
import 'player_image_widget.dart';
import 'prop_board_loading.dart';
import 'prop_research_assistant.dart';
import 'prop_research_controls.dart';
import 'prop_trust_widgets.dart';
import 'recommendation_explainability_block.dart';
import 'tablet_prop_table.dart';

/// Keeps decision cards wide enough for verdict text, metrics, and pick actions.
@visibleForTesting
int propGridColumnCount(double availableWidth) {
  if (availableWidth >= 1240) return 3;
  if (availableWidth >= 720) return 2;
  return 1;
}

@visibleForTesting
double propGridSpacing(double availableWidth) {
  if (availableWidth < 600) return 8;
  if (availableWidth < 1000) return 10;
  return 12;
}

@visibleForTesting
bool useTabletPropTable(double availableWidth) =>
    ResponsiveBreakpoints.isTablet(availableWidth);

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
  // Which PI Verdicts the board is allowed to show. Sorting alone
  // could not solve this: the board pages in a few dozen props at a
  // time, so plays that sort to the top of two thousand still sit
  // behind pages of passes the moment any other order is chosen.
  final String verdictFilter;
  final String searchQuery;
  final void Function(List<PropData>, int, int, Map<String, int>)?
  onPropsLoaded;
  final ValueChanged<PropData>? onPropFocused;
  final ValueListenable<int> refreshListenable;
  final ValueChanged<String>? onStartupLog;
  final ApiService? apiService;
  final Future<List<ScoreboardGame>> Function(String sport)? scheduleLoader;
  final bool siteFirstLayout;

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
    this.verdictFilter = 'ALL',
    required this.searchQuery,
    this.onPropsLoaded,
    this.onPropFocused,
    required this.refreshListenable,
    this.onStartupLog,
    this.apiService,
    this.scheduleLoader,
    this.siteFirstLayout = false,
  });

  @override
  State<PropGrid> createState() => _PropGridState();
}

class _PropGridState extends State<PropGrid> with WidgetsBindingObserver {
  static const int _visiblePropStep = 24;
  static final Map<String, List<PropData>> _sessionViewCache =
      <String, List<PropData>>{};
  late final ApiService _apiService = widget.apiService ?? ApiService();
  late Future<List<PropData>> _propsFuture;
  List<PreparedBoardProp> _preparedProps = const [];
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  Timer? _autoRetryTimer;
  Timer? _expiryTimer;
  Timer? _lineRefreshTimer;
  bool _isLiveRefreshing = false;
  int _automaticRetryCount = 0;
  // Filtering, sorting and collapsing the board happens in build, so every
  // setState paid for it: expanding one card's research or switching one
  // card's book re-derived the whole board. None of those inputs change what
  // the board contains, so the result is kept until something that does.
  String _boardCacheKey = '';
  List<PropBookGroup> _boardCacheGroups = const [];
  int _visiblePropLimit = _visiblePropStep;
  final Set<String> _favoritePropIds = <String>{};
  Future<_SportSeasonStatus>? _seasonStatusFuture;
  String _seasonStatusSport = '';
  DateTime? _seasonStatusFetchedAt;
  bool _seasonNotificationEnabled = false;

  String get _queryKey => [
    widget.sportFilter,
    widget.selectedSite,
    widget.selectedCategory,
    widget.selectedSide,
    widget.selectedTier,
    widget.minConfidence.toString(),
    widget.verdictFilter,
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

  String _categoryFromApi(PropData prop) {
    return normalizedApiCategory(prop);
  }

  String _marketCategory(PropData prop) {
    final backendCategory = _categoryFromApi(prop);
    if (backendCategory.isNotEmpty) {
      return backendCategory;
    }
    return marketCategoryFor(
      normalizePropSport(prop.sport),
      propSearchableMarket(prop),
    );
  }

  Widget _playerPlaceholder(String player, {required double size}) {
    final initial = player.trim().isEmpty
        ? '?'
        : player.trim().substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: app_colors.AppColors.panel,
      child: Text(
        initial,
        style: TextStyle(
          color: app_colors.AppColors.gold,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _playerPhotoFrame(
    ImageProvider imageProvider,
    String player, {
    required double size,
  }) => Stack(
    fit: StackFit.expand,
    children: [
      _playerPlaceholder(player, size: size),
      Image(
        image: imageProvider,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    ],
  );

  Widget _fastPlayerPhoto(PropData prop, {double size = 44}) {
    final playerIdentity = prop.canonicalPlayerId.trim().isNotEmpty
        ? prop.canonicalPlayerId.trim()
        : prop.playerId.trim().isNotEmpty
        ? prop.playerId.trim()
        : prop.player.trim().toLowerCase();
    final imagePath = prop.imagePath.trim().isEmpty
        ? resolveCanonicalPlayerImagePath(
            player: prop.player,
            sport: prop.sport,
            identityKey: playerIdentity,
          )
        : resolvePlayerImagePath(prop.imagePath, identityKey: playerIdentity);
    final retryImagePath = resolvePlayerImageFallbackPath(
      prop.imagePath,
      identityKey: playerIdentity,
    );
    String photoKey(String path) =>
        'player-photo:${prop.sport}:$playerIdentity:${prop.sportsbook}:$path';
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
              imageBuilder: (_, imageProvider) =>
                  _playerPhotoFrame(imageProvider, prop.player, size: size),
              useOldImageOnUrlChange: true,
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

    if (kIsWeb) {
      final proxiedWebPath = resolvePlayerImagePath(
        prop.imagePath,
        useApiProxyForRemoteImages: true,
        identityKey: playerIdentity,
      );

      Widget webImage(String url, {String? retryUrl}) {
        final key = photoKey(url);
        return CachedNetworkImage(
          key: ValueKey(photoKey(url)),
          imageUrl: url,
          cacheKey: key,
          width: size,
          height: size,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          useOldImageOnUrlChange: true,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          maxWidthDiskCache: 800,
          maxHeightDiskCache: 800,
          imageBuilder: (_, imageProvider) =>
              _playerPhotoFrame(imageProvider, prop.player, size: size),
          placeholder: (_, _) => _playerPlaceholder(prop.player, size: size),
          errorWidget: (_, _, _) {
            if (retryUrl != null && retryUrl.isNotEmpty && retryUrl != url) {
              return webImage(retryUrl);
            }
            EngagementTracker.instance.recordProductOncePer(
              'PLAYER_IMAGE_FAILURE:${url.hashCode}',
              const Duration(minutes: 30),
            );
            return _playerPlaceholder(prop.player, size: size);
          },
        );
      }

      // The canonical identity in the URL and cache key prevents one player,
      // provider refresh, or stale browser response from replacing another
      // player's decoded bitmap when the board is left and reopened.
      return webImage(
        imagePath,
        retryUrl: proxiedWebPath.isEmpty ? null : proxiedWebPath,
      );
    }

    return CachedNetworkImage(
      key: ValueKey(photoKey(imagePath)),
      imageUrl: imagePath,
      imageBuilder: (_, imageProvider) =>
          _playerPhotoFrame(imageProvider, prop.player, size: size),
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      memCacheWidth: cacheSize,
      memCacheHeight: cacheSize,
      placeholder: (context, url) {
        return _playerPlaceholder(prop.player, size: size);
      },
      errorWidget: (context, url, error) {
        if (retryImagePath.isNotEmpty && retryImagePath != imagePath) {
          return CachedNetworkImage(
            key: ValueKey(photoKey(retryImagePath)),
            imageUrl: retryImagePath,
            imageBuilder: (_, imageProvider) =>
                _playerPhotoFrame(imageProvider, prop.player, size: size),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            fadeInDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            memCacheWidth: cacheSize,
            memCacheHeight: cacheSize,
            placeholder: (_, _) => _playerPlaceholder(prop.player, size: size),
            errorWidget: (_, _, _) =>
                _playerPlaceholder(prop.player, size: size),
          );
        }
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

  double _displayedLineValue(PropData prop) {
    return prop.currentLine != 0 ? prop.currentLine : prop.line;
  }

  String? _specialLineBadge(PropData prop, PickSide? advisedSide) {
    final combinedText =
        '${prop.customLabel} ${prop.manualNote} ${prop.recommendationExplanation} ${prop.recommendationUnavailableReason} ${prop.selectionReason}'
            .toLowerCase();

    if (combinedText.contains('taco')) {
      return 'SPECIAL: TACO TUESDAY';
    }
    if (combinedText.contains('special') ||
        combinedText.contains('promo') ||
        combinedText.contains('discount') ||
        combinedText.contains('flash')) {
      return 'SPECIAL LINE';
    }

    if (prop.openingLine == 0) {
      return null;
    }

    final opening = prop.openingLine;
    final current = _displayedLineValue(prop);
    final delta = current - opening;
    if (delta.abs() < 0.5) {
      return null;
    }

    final lineImprovedForOver = delta <= -0.5;
    final lineImprovedForUnder = delta >= 0.5;

    final taggedAsSpecial = advisedSide == PickSide.over
        ? lineImprovedForOver
        : advisedSide == PickSide.under
        ? lineImprovedForUnder
        : delta.abs() >= 1;
    if (!taggedAsSpecial) {
      return null;
    }

    return 'SPECIAL LINE ${opening.toStringAsFixed(1)}→${current.toStringAsFixed(1)}';
  }

  void _handleCardSelection(PropData prop, PickSide side) {
    widget.onSelect(prop, side);
  }

  Future<void> _showResearchOverlay(
    PropData prop,
    PickSide? selectedSide,
  ) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close research',
      barrierColor: Colors.black.withValues(alpha: .58),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: .97, end: 1).animate(animation),
              child: child,
            ),
          ),
      pageBuilder: (context, animation, secondaryAnimation) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 880,
                  maxHeight: MediaQuery.sizeOf(context).height * .92,
                ),
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.16)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildPortraitPropCard(
                      prop,
                      selectedSide,
                      fixedHeight: false,
                      researchOverlay: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitPropCard(
    PropData prop,
    PickSide? selectedSide, {
    // A desktop grid cell reserves 428px so the research control remains
    // inside the card border instead of overlapping the provider section.
    // A single-column phone list gives each card its natural height instead,
    // where a Spacer has no bounded height to expand into and would throw.
    bool fixedHeight = true,
    bool researchOverlay = false,
  }) {
    final researchOpen = researchOverlay;
    final compactCard = MediaQuery.sizeOf(context).width < 600;
    final hasProAccess = canShowSystemRecommendation(
      hasEdgeAccess: AuthManager.instance.sessionState.value.hasEdgeAccess,
    );
    // Never reconstruct or expose a system direction for Core/Free members,
    // even when an older device cache still contains model fields.
    final suggested = gatedSystemRecommendationSide(
      hasEdgeAccess: hasProAccess,
      recommendation: prop.proSuggestedSide,
    );
    final advisedSide = suggested == 'UNDER'
        ? PickSide.under
        : suggested == 'OVER'
        ? PickSide.over
        : null;
    final hasModelPick =
        hasProAccess && prop.proSuggestionUsesModel && advisedSide != null;
    final noPiPick = hasProAccess && advisedSide == null;
    final usesResearchFallback =
        hasProAccess && prop.proSuggestionUsesResearchFallback;
    final researchProjection = prop.projection ?? prop.projectionPreMarket;
    final rawFallbackSide = prop.proSuggestionUsesHistoricalStats
        ? researchProjection == null || researchProjection == prop.line
              ? null
              : researchProjection > prop.line
              ? 'OVER'
              : 'UNDER'
        : prop.proSuggestionUsesMarket
        ? prop.marketLeanSide
        : null;
    final signalConflict =
        !noPiPick && rawFallbackSide != null && rawFallbackSide != suggested;
    final specialLineBadge = _specialLineBadge(prop, advisedSide);
    final market = _marketCategory(prop);
    final signalLabel = hasModelPick
        ? 'MODEL PICK'
        : noPiPick
        ? 'NO PI PICK'
        : signalConflict
        ? 'PI SIGNAL'
        : prop.proSuggestionUsesHistoricalStats
        ? 'PI PICK'
        : usesResearchFallback
        ? 'RESEARCH PICK'
        : 'MARKET LEAN';
    final badgeExplanation = !hasProAccess
        ? 'PROP TYPE: the statistic and posted line available for manual research and selection.'
        : hasModelPick
        ? 'MODEL PICK: a released model direction. The PI Verdict is still the action guide after price and availability checks.'
        : noPiPick
        ? 'NO PI PICK: the final verdict does not back either side at this line. Both buttons remain available for your own read.'
        : signalConflict
        ? 'PI SIGNAL: the final verdict direction after probability and price checks differs from the raw fallback lean. The PI Verdict is the action guide.'
        : prop.proSuggestionUsesHistoricalStats
        ? 'PI PICK: the projection suggests a definite OVER or UNDER direction using the available evidence. Evidence source and PI Trust remain visible.'
        : usesResearchFallback
        ? 'RESEARCH PICK: a stable OVER or UNDER research direction is shown because no released model or priced market edge is available. It is low evidence and the PI Verdict remains the action guide.'
        : 'MARKET LEAN: direction inferred from prop-site pricing, not a released model selection. Follow the PI Verdict for the research decision.';
    final signalColor = prop.dataStale
        ? app_colors.AppColors.warning
        : noPiPick
        ? app_colors.AppColors.textMuted
        : hasModelPick || prop.proSuggestionUsesHistoricalStats
        ? app_colors.AppColors.blue
        : usesResearchFallback
        ? app_colors.AppColors.textMuted
        : app_colors.AppColors.gold;

    Widget metric(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: PiDesign.metadataFontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: app_colors.AppColors.gold.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: app_colors.AppColors.textMuted,
          fontSize: PiDesign.metadataFontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    Widget sideButton(PickSide side) {
      final selected = selectedSide == side;
      final systemRecommended = advisedSide == side;
      final sideLabel = side == PickSide.over ? 'OVER' : 'UNDER';
      final label = selected ? 'REMOVE $sideLabel' : sideLabel;
      return Expanded(
        child: OutlinedButton(
          onPressed: prop.isSelectable && !prop.dataStale
              ? () => _handleCardSelection(prop, side)
              : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: selected
                ? app_colors.AppColors.background
                : Colors.white,
            backgroundColor: selected
                ? app_colors.AppColors.piGoldBright
                : systemRecommended
                ? app_colors.AppColors.piGold.withValues(alpha: .18)
                : app_colors.AppColors.surfaceElevated,
            side: BorderSide(
              color: selected
                  ? app_colors.AppColors.goldHighlight
                  : systemRecommended
                  ? app_colors.AppColors.gold.withValues(alpha: .85)
                  : app_colors.AppColors.border,
              width: selected ? 1.4 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PiDesign.controlRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: selected
                          ? app_colors.AppColors.background
                          : app_colors.AppColors.gold,
                      letterSpacing: .4,
                    ),
                  ),
                  if (!selected && systemRecommended) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 11,
                      color: app_colors.AppColors.gold,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                prop.line.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: PiDesign.recommendationFontSize,
                  fontWeight: FontWeight.w900,
                  color: selected
                      ? app_colors.AppColors.background
                      : Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget lineDisplay() {
      return Container(
        constraints: const BoxConstraints(minWidth: 74),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1622),
          borderRadius: BorderRadius.circular(PiDesign.controlRadius),
          border: Border.all(
            color: app_colors.AppColors.gold.withValues(alpha: .28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'LINE',
              style: TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: PiDesign.metadataFontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              prop.line.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: PiDesign.recommendationFontSize,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1823), Color(0xFF06111A)],
        ),
        borderRadius: BorderRadius.circular(PiDesign.cardRadius),
        border: Border.all(
          color: selectedSide == null
              ? app_colors.AppColors.border
              : app_colors.AppColors.piGoldBright,
          width: selectedSide == null ? 1 : 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: app_colors.AppColors.gold),
                ),
                child: ClipOval(child: _fastPlayerPhoto(prop, size: 46)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 116,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prop.player,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: PiDesign.playerFontSize,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                prop.gameTime.trim().isEmpty
                                    ? prop.matchup
                                    : '${prop.matchup} • ${prop.gameTime}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: app_colors.AppColors.textMuted,
                                  fontSize: PiDesign.metadataFontSize,
                                  height: 1.4,
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
              const SizedBox(width: 8),
              Tooltip(
                message: badgeExplanation,
                triggerMode: TooltipTriggerMode.tap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: signalColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            prop.dataStale
                                ? 'DATA STATUS'
                                : !hasProAccess
                                ? 'PROP TYPE'
                                : signalLabel,
                            style: TextStyle(
                              color: signalColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.info_outline_rounded,
                            color: signalColor,
                            size: 10,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        prop.dataStale
                            ? 'UNAVAILABLE'
                            : !hasProAccess
                            ? market.toUpperCase()
                            : noPiPick
                            ? 'YOUR CHOICE'
                            : advisedSide == null
                            ? prop.line.toStringAsFixed(1)
                            : '${advisedSide == PickSide.over ? 'OVER' : 'UNDER'} ${prop.line.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: signalColor,
                          fontSize: PiDesign.recommendationFontSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: app_colors.AppColors.gold,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _propDateTimeLabel(prop),
                  key: ValueKey('prop-game-date-time-${prop.id}'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: PiDesign.metadataFontSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  market,
                  key: ValueKey('prop-market-label-${prop.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Every prop for ${prop.player} on ${prop.sportsbook}',
                child: Semantics(
                  button: true,
                  label: 'Every prop for ${prop.player} on ${prop.sportsbook}',
                  child: InkWell(
                    key: ValueKey('prop-every-prop-${prop.id}'),
                    onTap: () => widget.onPropFocused?.call(prop),
                    borderRadius: BorderRadius.circular(99),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: app_colors.AppColors.gold.withValues(
                              alpha: .12,
                            ),
                            border: Border.all(
                              color: app_colors.AppColors.gold,
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            'EP',
                            style: TextStyle(
                              color: app_colors.AppColors.gold,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Tooltip(
                message: _favoritePropIds.contains(prop.id)
                    ? 'Unpin this prop'
                    : 'Pin this prop to the top',
                child: Semantics(
                  button: true,
                  label: _favoritePropIds.contains(prop.id)
                      ? 'Unpin ${prop.player} prop from the top'
                      : 'Pin ${prop.player} prop to the top',
                  child: InkWell(
                    key: ValueKey('pin-prop-${prop.id}'),
                    onTap: () => setState(() {
                      if (!_favoritePropIds.add(prop.id)) {
                        _favoritePropIds.remove(prop.id);
                      }
                    }),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _favoritePropIds.contains(prop.id)
                            ? Icons.star
                            : Icons.star_border,
                        color: app_colors.AppColors.gold,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            key: ValueKey('prop-sport-${prop.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: app_colors.AppColors.gold.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: app_colors.AppColors.gold),
            ),
            child: Text(
              'SPORT: ${prop.sport.trim().isEmpty ? 'UNKNOWN' : prop.sport.toUpperCase()}  •  '
              'PROP SITE: ${prop.sportsbook.trim().isEmpty ? 'UNKNOWN' : prop.sportsbook.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          PiTrustBadge(prop: prop),
          const SizedBox(height: 9),
          // The conclusion first. Everything below it is the working that
          // led here, and a reader who stops at the top should still have
          // the answer rather than six signals to assemble themselves.
          // The verdict is what Pro is for. Everyone sees the prop, the
          // line, the book and both buttons; only Pro is told what we think
          // of it. Giving the opinion away leaves nothing to sell.
          if (hasProAccess && prop.verdict.isPresent && !prop.dataStale) ...[
            PiVerdictBlock(
              verdict: prop.verdict,
              // Keep every closed card scannable. The complete reason and
              // recheck instructions belong in the explicit research fold.
              compactSummary: !researchOpen,
            ),
            const SizedBox(height: 8),
          ],
          // Above the fold, never inside the research fold. When an event's
          // odds request fails the sync keeps the last known props and serves
          // them as current, so this line can be hours old while looking
          // exactly like one fetched a moment ago -- which is how a board
          // ends up disagreeing with the book it came from.
          if (prop.dataStale) ...[
            Container(
              key: ValueKey('prop-stale-warning-${prop.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: app_colors.AppColors.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: app_colors.AppColors.warning),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 13,
                    color: app_colors.AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      researchOpen
                          ? '${prop.freshnessLabel} — confirm this number on '
                                '${prop.sportsbook.trim().isEmpty ? 'the book' : prop.sportsbook} '
                                'before using it.'
                          : 'DATA UNAVAILABLE — live line verification required',
                      style: TextStyle(
                        color: app_colors.AppColors.warning,
                        fontSize: 8,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
          ],
          // On a collapsed phone card, the PI Trust badge and PI Pick already
          // carry the decision-critical values. Keep this secondary model row
          // for larger screens and reveal it with the research details on a
          // phone instead of repeating the same information above the fold.
          if (hasProAccess && (!compactCard || researchOpen)) ...[
            Row(
              children: [
                metric(
                  noPiPick
                      ? 'PI STATUS'
                      : signalConflict
                      ? 'VERDICT SIDE'
                      : hasModelPick
                      ? 'MODEL'
                      : 'PROJECTION',
                  noPiPick
                      ? 'NOT BACKED'
                      : signalConflict
                      ? suggested ?? '--'
                      : prop.displayModelValue.toStringAsFixed(2),
                ),
                metric('PI TRUST', '${prop.piTrustScore}/100'),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              sideButton(PickSide.under),
              const SizedBox(width: 7),
              lineDisplay(),
              const SizedBox(width: 7),
              sideButton(PickSide.over),
            ],
          ),
          if (selectedSide != null) ...[
            const SizedBox(height: 7),
            Container(
              key: ValueKey('remove-selection-${prop.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: app_colors.AppColors.gold.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: app_colors.AppColors.gold),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: app_colors.AppColors.gold,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${selectedSide == PickSide.over ? 'OVER' : 'UNDER'} SELECTED - TAP REMOVE ${selectedSide == PickSide.over ? 'OVER' : 'UNDER'} TO UNDO',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 7),
          // The decision ends here. Everything past this point is the working
          // behind it: worth reading second, and never worth making a reader
          // wade through before they know what the app thinks.
          ResearchToggle(
            open: researchOpen,
            onTap: researchOverlay
                ? () => Navigator.of(context).pop()
                : () => _showResearchOverlay(prop, selectedSide),
          ),
          if (researchOpen) ...[
            const SizedBox(height: 11),
            _buildPiIntelligenceDetail(prop),
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // What the model could confirm. A prop with no projection is
                // still a real line on a real market and stays selectable; the
                // chip says the model has no opinion rather than implying the
                // prop itself is suspect.
                if (prop.hasModelProjection)
                  chip('VERIFIED DATA')
                else
                  chip('NO MODEL PROJECTION'),
                // Gaps verification found but the card never mentioned. The
                // prop stays selectable; the reader just gets told which part
                // of it we could not confirm.
                for (final caveat in prop.dataCaveats) chip(caveat),
                chip('LINEUP ${prop.lineupStatus.toUpperCase()}'),
                chip(prop.injuryDisplayLabel),
                if (hasModelPick) chip('EVIDENCE: VERIFIED MODEL'),
                if (hasModelPick && prop.displayModelEstimateRating != null)
                  chip('MODEL ESTIMATE ${prop.displayModelEstimateRating}%'),
                if (hasModelPick && prop.displayRiskFloorRating != null)
                  chip('RISK FLOOR ${prop.displayRiskFloorRating}%'),
                if (!hasModelPick && prop.proSuggestionUsesHistoricalStats)
                  chip('EVIDENCE: 5/10/20 PROJECTION'),
                if (!hasModelPick && prop.proSuggestionUsesMarket)
                  chip('EVIDENCE: PROP-SITE PRICING'),
                if (usesResearchFallback)
                  chip('EVIDENCE: LOW-EVIDENCE RESEARCH'),
                if (prop.displayModelIsMarketBaseline) chip('MODEL: BASELINE'),
                if (hasProAccess) chip('PICK GRADE ${prop.pickGrade}'),
                if (hasProAccess && prop.projectedOpportunity != null)
                  chip(
                    'PROJECTED ${prop.projectedOpportunity!.toStringAsFixed(1)} ${prop.opportunityUnit}',
                  ),
                if (hasProAccess && prop.roleStatus != 'UNKNOWN')
                  chip('ROLE ${prop.roleStatus.replaceAll('_', ' ')}'),
                if (hasProAccess && prop.roleChange != 'UNKNOWN')
                  chip('ROLE TREND ${prop.roleChange.replaceAll('_', ' ')}'),
                if (specialLineBadge != null) chip(specialLineBadge),
                if (prop.openingLine != 0)
                  chip('OPEN ${prop.openingLine.toStringAsFixed(1)}'),
              ],
            ),
            const SizedBox(height: 10),
            WhyThisPropCapsule(prop: prop),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PropResearchAiButton(
                prop: prop,
                comparisonCandidates: _preparedProps
                    .map((item) => item.prop)
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            InjuryImpactAlert(prop: prop),
            if (buildInjuryImpactSummary(prop).isPresent)
              const SizedBox(height: 8),
            RecommendationExplainabilityBlock(prop: prop),
            const SizedBox(height: 8),
            const Text(
              'Standardized explainability is shown above. Confirm live line movement and player availability before adding to slip.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: app_colors.AppColors.textMuted,
                fontSize: 8,
                height: 1.3,
              ),
            ),
          ],
          // Only a bounded box can absorb a Spacer; the phone list cannot.
          if (fixedHeight && !researchOpen) const Spacer(),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // Kept temporarily as a visual rollback reference while the unified card
  // rolls out across every board.
  // ignore: unused_element
  Widget _buildPortraitPropCardLegacy(PropData prop, PickSide? selectedSide) {
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
    final confidence = prop.displayConfidenceRating ?? 0;
    final calculatedEdge = prop.calculatedEdge;
    final marketLean = prop.marketLeanPercentage;
    final marketEdge = calculatedEdge == null && marketLean != null
        ? (marketLean - 50).abs()
        : null;
    final edgeLabel = calculatedEdge != null ? 'EDGE' : 'PRICING EDGE';
    final edgeValue = calculatedEdge != null
        ? '+${calculatedEdge.toStringAsFixed(2)}'
        : marketEdge != null && marketEdge > 0
        ? '+${marketEdge.toStringAsFixed(0)}%'
        : '--';

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
                color: app_colors.AppColors.textMuted,
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
      final sideLabel = side == PickSide.over ? 'OVER' : 'UNDER';
      final label = selected ? 'REMOVE $sideLabel' : sideLabel;

      return Expanded(
        child: OutlinedButton(
          onPressed: () => _handleCardSelection(prop, side),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 54),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: selected
                ? app_colors.AppColors.background
                : Colors.white,
            backgroundColor: selected
                ? app_colors.AppColors.goldHighlight.withValues(alpha: .88)
                : const Color(0xFF1A2430),
            side: BorderSide(
              color: selected
                  ? app_colors.AppColors.goldHighlight
                  : advised
                  ? app_colors.AppColors.gold.withValues(alpha: .85)
                  : app_colors.AppColors.border,
              width: selected ? 1.4 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            children: [
              if (side == PickSide.under)
                Text(
                  '⌄',
                  style: TextStyle(
                    color: selected
                        ? app_colors.AppColors.background
                        : app_colors.AppColors.silver,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              if (side == PickSide.under) const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: selected
                            ? app_colors.AppColors.background
                            : app_colors.AppColors.gold,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prop.line.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: selected
                            ? app_colors.AppColors.background
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (side == PickSide.over) const SizedBox(width: 7),
              if (side == PickSide.over)
                Text(
                  '⌃',
                  style: TextStyle(
                    color: selected
                        ? app_colors.AppColors.background
                        : app_colors.AppColors.silver,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              if (!selected && advised) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 12,
                  color: app_colors.AppColors.gold,
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget lineDisplay() {
      return Container(
        constraints: const BoxConstraints(minWidth: 74),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1622),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: app_colors.AppColors.gold.withValues(alpha: .28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'LINE',
              style: TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              prop.line.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    Widget selectionHint() {
      return const Text(
        'Tap OVER or UNDER to add it to the active slip. Tap the selected side again to remove it.',
        textAlign: TextAlign.center,
        style: TextStyle(color: app_colors.AppColors.textMuted, fontSize: 7.5),
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
        border: Border.all(color: app_colors.AppColors.gold, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  key: ValueKey('prop-sport-${prop.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: app_colors.AppColors.blue.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: app_colors.AppColors.blue),
                  ),
                  child: Text(
                    '${prop.sport.trim().isEmpty ? 'SPORT' : prop.sport.toUpperCase()} • '
                    '${prop.sportsbook.trim().isEmpty ? 'SITE UNKNOWN' : prop.sportsbook.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: app_colors.AppColors.blue,
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Open every available prop for ${prop.player}',
                child: InkWell(
                  key: ValueKey('prop-all-player-props-${prop.id}'),
                  onTap: () => widget.onPropFocused?.call(prop),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: app_colors.AppColors.gold.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: app_colors.AppColors.gold),
                    ),
                    child: const Text(
                      'VIEW ALL PROPS',
                      style: TextStyle(
                        color: app_colors.AppColors.gold,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .3,
                      ),
                    ),
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
                  color: app_colors.AppColors.gold,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            market,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: app_colors.AppColors.gold,
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
              color: app_colors.AppColors.gold.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: app_colors.AppColors.gold),
            ),
            child: Text(
              hasModelRecommendation
                  ? '★ SYSTEM PICK: ${advisedSide == PickSide.over ? 'OVER' : 'UNDER'}'
                  : hasHistoricalLean
                  ? 'PI PICK: ${advisedSide == PickSide.over ? 'OVER' : 'UNDER'}'
                  : hasMarketLean
                  ? 'MARKET LEAN: ${advisedSide == PickSide.over ? 'OVER' : 'UNDER'}'
                  : hasProAccess
                  ? 'NO PI PICK'
                  : 'PRO SUGGESTIVE PICK',
              style: const TextStyle(
                color: app_colors.AppColors.gold,
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
              border: Border.all(
                color: app_colors.AppColors.gold.withValues(alpha: .28),
              ),
            ),
            child: Row(
              children: [
                intelligenceMetric(edgeLabel, hasProAccess ? edgeValue : '--'),
                intelligenceMetric(
                  'PROJECTION',
                  hasProAccess && prop.projection != null
                      ? prop.projection!.toStringAsFixed(1)
                      : '--',
                ),
                intelligenceMetric('PI TRUST', '${prop.piTrustScore}/100'),
                intelligenceMetric(
                  'PICK GRADE',
                  hasProAccess ? prop.pickGrade.toUpperCase() : '--',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              sideButton(PickSide.under),
              const SizedBox(width: 7),
              lineDisplay(),
              const SizedBox(width: 7),
              sideButton(PickSide.over),
            ],
          ),
          const SizedBox(height: 7),
          selectionHint(),
          const SizedBox(height: 8),
          RecommendationExplainabilityBlock(
            prop: prop,
            title: 'STANDARDIZED EXPLAINABILITY',
          ),
          const SizedBox(height: 3),
          Text(
            hasProAccess && prop.projectionModelVersion == 'baseline-v2'
                ? 'Experimental until 100 pregame predictions are graded'
                : hasProAccess
                ? 'Live pricing baseline'
                : 'Pro intelligence is locked',
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 7,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 66,
              height: 66,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: app_colors.AppColors.gold),
              ),
              child: ClipOval(child: _fastPlayerPhoto(prop, size: 62)),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: app_colors.AppColors.gold.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: app_colors.AppColors.gold),
              ),
              child: Text(
                prop.sportsbook.toUpperCase(),
                style: const TextStyle(
                  color: app_colors.AppColors.gold,
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
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 7,
            ),
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
                    color: app_colors.AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasProAccess ? edgeValue : '--',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    edgeLabel,
                    style: const TextStyle(
                      color: app_colors.AppColors.textMuted,
                      fontSize: 6,
                    ),
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
              color: app_colors.AppColors.gold,
              backgroundColor: app_colors.AppColors.border,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSiteFirstPropCard(PropData prop, PickSide? selectedSide) {
    final suggested = (prop.proSuggestedSide?.trim().isNotEmpty ?? false)
        ? prop.proSuggestedSide!.trim().toUpperCase()
        : prop.pickText.trim().toUpperCase();
    final recommendedSide = suggested.contains('UNDER')
        ? PickSide.under
        : PickSide.over;
    final market = prop.displayMarket.trim().isEmpty
        ? _marketCategory(prop)
        : prop.displayMarket.trim().toUpperCase();
    final projection = prop.projection?.toStringAsFixed(1) ?? '--';

    Widget action(PickSide side) {
      final selected = selectedSide == side;
      final recommended = recommendedSide == side;
      final label = side == PickSide.over ? 'OVER' : 'UNDER';
      return Expanded(
        child: OutlinedButton(
          key: ValueKey('phone-${label.toLowerCase()}-${prop.id}'),
          onPressed: prop.dataStale ? null : () => widget.onSelect(prop, side),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 50),
            foregroundColor: selected
                ? app_colors.AppColors.bgBase
                : Colors.white,
            backgroundColor: selected
                ? app_colors.AppColors.gold
                : const Color(0xFF091722),
            side: BorderSide(
              color: selected || recommended
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle_rounded, size: 16),
              ],
            ],
          ),
        ),
      );
    }

    Widget metric(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    return Material(
      key: ValueKey('phone-prop-card-${prop.id}'),
      color: const Color(0xFF081620),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: app_colors.AppColors.borderGold),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showResearchOverlay(prop, selectedSide),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E2330),
                      shape: BoxShape.circle,
                      border: Border.all(color: app_colors.AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: PlayerImageWidget(
                      imageUrl: prop.imagePath,
                      width: 72,
                      height: 72,
                      fit: BoxFit.contain,
                      fallbackIcon: Icons.person_rounded,
                      fallbackIconSize: 30,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prop.player,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          prop.matchup,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: app_colors.AppColors.silver,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          prop.sportsbook.toUpperCase(),
                          style: const TextStyle(
                            color: app_colors.AppColors.gold,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: app_colors.AppColors.gold.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: app_colors.AppColors.gold),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${prop.piTrustScore}',
                          style: const TextStyle(
                            color: app_colors.AppColors.gold,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'PI SCORE',
                          style: TextStyle(
                            color: app_colors.AppColors.textMuted,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                market,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  metric('LINE', prop.line.toStringAsFixed(1)),
                  metric('MODEL', projection),
                  metric(
                    'PI PICK',
                    recommendedSide == PickSide.over ? 'OVER' : 'UNDER',
                    color: app_colors.AppColors.gold,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  action(PickSide.under),
                  const SizedBox(width: 8),
                  action(PickSide.over),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: OutlinedButton(
                      key: ValueKey('phone-research-${prop.id}'),
                      onPressed: () => _showResearchOverlay(prop, selectedSide),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: app_colors.AppColors.gold,
                        side: const BorderSide(
                          color: app_colors.AppColors.gold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Icon(Icons.psychology_alt_rounded, size: 21),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSiteFirstPropCard(PropData prop, PickSide? selectedSide) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return _buildPhoneSiteFirstPropCard(prop, selectedSide);
    }
    final suggestedSide = prop.proSuggestedSide?.trim() ?? '';
    final pickSide = suggestedSide.isNotEmpty
        ? suggestedSide.toUpperCase()
        : prop.pickText.trim().toUpperCase();
    final pickLabel = pickSide.contains('UNDER') ? 'UNDER' : 'OVER';
    final market = prop.displayMarket.trim().isEmpty
        ? _marketCategory(prop)
        : prop.displayMarket.trim().toUpperCase();
    final projection = prop.projection?.toStringAsFixed(1) ?? '--';
    final learned = prop.probabilityCalibrationAdjustment.abs() >= .005;
    final favorite = _favoritePropIds.contains(prop.id);

    Widget sideButton(PickSide side) {
      final selected = selectedSide == side;
      final recommended =
          (side == PickSide.under && pickLabel == 'UNDER') ||
          (side == PickSide.over && pickLabel == 'OVER');
      final label = side == PickSide.over ? 'OVER' : 'UNDER';
      return Expanded(
        child: OutlinedButton(
          key: ValueKey('site-first-${label.toLowerCase()}-${prop.id}'),
          onPressed: prop.dataStale ? null : () => widget.onSelect(prop, side),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: selected
                ? app_colors.AppColors.bgBase
                : Colors.white,
            backgroundColor: selected
                ? app_colors.AppColors.gold
                : const Color(0xFF0B1A26),
            side: BorderSide(
              color: selected || recommended
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                side == PickSide.over
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 5),
                const Icon(Icons.check_circle_rounded, size: 15),
              ],
            ],
          ),
        ),
      );
    }

    return Material(
      key: ValueKey('site-first-prop-card-${prop.id}'),
      color: const Color(0xFF081620),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: app_colors.AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showResearchOverlay(prop, selectedSide),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
          child: Column(
            children: [
              // The one-column mobile list does not impose a height on each
              // card. An Expanded here therefore receives unbounded vertical
              // constraints and the entire loaded card list fails to paint.
              // Give the information row its intrinsic design height so the
              // same card works in both the self-sizing mobile list and the
              // fixed-height desktop grid.
              SizedBox(
                height: 116,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 112,
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.bottomCenter,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00081620), Color(0xFF0E2330)],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: PlayerImageWidget(
                              key: ValueKey(
                                'prop-photo-${prop.canonicalPlayerId.trim().isNotEmpty ? prop.canonicalPlayerId : prop.player.trim().toLowerCase()}-${prop.imagePath}',
                              ),
                              imageUrl: prop.imagePath,
                              width: 108,
                              height: 116,
                              fit: BoxFit.contain,
                              fallbackIcon: Icons.person_rounded,
                              fallbackIconSize: 38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prop.player,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            prop.matchup,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 9,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(
                                Icons.emoji_events_outlined,
                                size: 12,
                                color: app_colors.AppColors.gold,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  prop.sportsbook.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(
                      color: app_colors.AppColors.border,
                      width: 18,
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PI PICK',
                            style: TextStyle(
                              color: app_colors.AppColors.blue,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '$pickLabel ${prop.line.toStringAsFixed(1)}',
                            style: const TextStyle(
                              color: app_colors.AppColors.blue,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            market,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(
                      color: app_colors.AppColors.border,
                      width: 18,
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PI TRUST',
                            style: TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${prop.piTrustScore}',
                            style: const TextStyle(
                              color: app_colors.AppColors.success,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'PROJECTION',
                            style: TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            projection,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: favorite ? 'Remove favorite' : 'Favorite prop',
                      onPressed: () => setState(() {
                        if (!_favoritePropIds.add(prop.id)) {
                          _favoritePropIds.remove(prop.id);
                        }
                      }),
                      icon: Icon(
                        favorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: app_colors.AppColors.gold,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  sideButton(PickSide.under),
                  const SizedBox(width: 8),
                  sideButton(PickSide.over),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: OutlinedButton(
                      key: ValueKey('site-first-research-${prop.id}'),
                      onPressed: () => _showResearchOverlay(prop, selectedSide),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: app_colors.AppColors.gold,
                        side: const BorderSide(
                          color: app_colors.AppColors.gold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Icon(Icons.psychology_alt_rounded, size: 20),
                    ),
                  ),
                ],
              ),
              if (learned) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'PI LEARNING ACTIVE',
                    style: TextStyle(
                      color: app_colors.AppColors.silver,
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
    final market = _marketCategory(prop);

    Widget sideButton(PickSide side) {
      final advised = side == advisedSide;
      final selected = side == selectedSide;
      final isOver = side == PickSide.over;
      return Expanded(
        child: OutlinedButton(
          onPressed: prop.dataStale ? null : () => widget.onSelect(prop, side),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: selected
                ? app_colors.AppColors.background
                : Colors.white,
            backgroundColor: selected
                ? app_colors.AppColors.goldHighlight.withValues(alpha: .88)
                : const Color(0xFF1A2430),
            side: BorderSide(
              color: selected
                  ? app_colors.AppColors.goldHighlight
                  : advised
                  ? app_colors.AppColors.gold.withValues(alpha: .85)
                  : app_colors.AppColors.border,
              width: selected ? 1.4 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Row(
            children: [
              if (!isOver)
                Text(
                  '⌄',
                  style: TextStyle(
                    color: selected
                        ? app_colors.AppColors.background
                        : app_colors.AppColors.silver,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              if (!isOver) const SizedBox(width: 5),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isOver ? 'OVER' : 'UNDER',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: selected
                            ? app_colors.AppColors.background
                            : app_colors.AppColors.gold,
                        letterSpacing: .35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prop.line.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: selected
                            ? app_colors.AppColors.background
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOver) const SizedBox(width: 5),
              if (isOver)
                Text(
                  '⌃',
                  style: TextStyle(
                    color: selected
                        ? app_colors.AppColors.background
                        : app_colors.AppColors.silver,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              if (!selected && advised) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 10,
                  color: app_colors.AppColors.gold,
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget lineDisplay() {
      return Container(
        constraints: const BoxConstraints(minWidth: 58),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1622),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: app_colors.AppColors.gold.withValues(alpha: .28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'LINE',
              style: TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              prop.line.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
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
        border: Border.all(color: app_colors.AppColors.border),
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
                        : app_colors.AppColors.textMuted,
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
                      color: app_colors.AppColors.gold,
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
                              color: app_colors.AppColors.textMuted,
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
          Container(height: 1, color: app_colors.AppColors.border),
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
                          color: app_colors.AppColors.gold,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Text(
                      'BEST',
                      style: TextStyle(
                        color: app_colors.AppColors.textMuted,
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
                          color: app_colors.AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          advisedSide == PickSide.over ? 'O' : 'U',
                          style: const TextStyle(
                            color: app_colors.AppColors.bgBase,
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
                    sideButton(PickSide.under),
                    const SizedBox(width: 6),
                    lineDisplay(),
                    const SizedBox(width: 6),
                    sideButton(PickSide.over),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _compactMetric(
                        'EDGE',
                        prop.calculatedEdge == null
                            ? '--'
                            : '+${prop.calculatedEdge!.toStringAsFixed(2)}',
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
                        'PI TRUST',
                        '${prop.piTrustScore}/100',
                        prop.piTrustScore >= 75
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
          style: const TextStyle(
            color: app_colors.AppColors.textMuted,
            fontSize: 6,
          ),
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
        ? app_colors.AppColors.gold
        : key.contains('PICK6')
        ? const Color(0xFF53D337)
        : const Color(0xFF8D4DFF);
    final label = key.contains('FANDUEL')
        ? 'F'
        : key.contains('PRIZE')
        ? 'P'
        : key.contains('UNDERDOG')
        ? 'U'
        : key.contains('PICK6')
        ? '6'
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
              color: app_colors.AppColors.bgBase,
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

  Widget _buildPiIntelligenceDetail(PropData prop) {
    final adjustment = prop.probabilityCalibrationAdjustment;
    final learned = adjustment.abs() >= .005;
    final risks = <String>{
      ...prop.piTrustWarnings.where((value) => value.trim().isNotEmpty),
      ...prop.verificationReasons.where((value) => value.trim().isNotEmpty),
      ...prop.opportunityReasons.where((value) => value.trim().isNotEmpty),
    }.take(4).toList(growable: false);
    final explanation = prop.recommendationExplanation.trim().isNotEmpty
        ? prop.recommendationExplanation.trim()
        : prop.pickGradeExplanation.trim();
    Widget metric(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF06131D),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0C2230), Color(0xFF07131D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: app_colors.AppColors.borderGold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.psychology_alt_rounded,
                color: app_colors.AppColors.gold,
                size: 17,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'PI INTELLIGENCE DETAIL',
                  style: TextStyle(
                    color: app_colors.AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              metric(
                'PI DECISION',
                prop.pickText.trim().isEmpty ? 'NO PICK' : prop.pickText,
              ),
              metric(
                'CONFIDENCE',
                prop.confidence > 0
                    ? '${prop.confidence}%'
                    : prop.pickText.trim().toLowerCase() == 'no pick'
                    ? 'NOT QUALIFIED'
                    : 'PENDING DATA',
              ),
              metric('PI TRUST', '${prop.piTrustScore}/100'),
              metric('MODEL SAMPLE', '${prop.projectionSampleSize} games'),
              metric('PROJECTION', prop.projection?.toStringAsFixed(2) ?? '--'),
              metric('LINE', prop.line.toStringAsFixed(1)),
              metric(
                'OPEN / CURRENT',
                '${prop.openingLine.toStringAsFixed(1)} / ${prop.currentLine.toStringAsFixed(1)}',
              ),
              metric('DATA STATUS', prop.verificationStatus.toUpperCase()),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            explanation.isEmpty
                ? 'PI is still gathering enough verified evidence to explain this decision.'
                : explanation,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              height: 1.45,
            ),
          ),
          if (learned) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: app_colors.AppColors.gold.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: app_colors.AppColors.gold.withValues(alpha: .55),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_graph_rounded,
                    color: app_colors.AppColors.gold,
                    size: 15,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'PI LEARNED ADJUSTMENT: Confidence was '
                      '${adjustment > 0 ? 'increased' : 'reduced'} by '
                      '${(adjustment.abs() * 100).toStringAsFixed(1)} points after '
                      'guarded validation on unseen settled results.',
                      style: const TextStyle(
                        color: app_colors.AppColors.gold,
                        fontSize: 9.5,
                        height: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'WHAT COULD MAKE THIS WRONG',
            style: TextStyle(
              color: risks.isEmpty
                  ? app_colors.AppColors.textMuted
                  : const Color(0xFFFFB36B),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            risks.isEmpty
                ? 'No elevated data-quality warning is currently attached. Normal player and game variance still applies.'
                : risks.map((risk) => '• $risk').join('\n'),
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 9.5,
              height: 1.45,
            ),
          ),
        ],
      ),
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
    final confidence = (prop.displayConfidenceRating ?? 0).toDouble();
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
              border: Border.all(
                color: app_colors.AppColors.goldShadow,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: app_colors.AppColors.gold.withValues(alpha: 0.08),
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
                      color: app_colors.AppColors.gold,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (gameDayDate.isNotEmpty) ...[
                  Text(
                    gameDayDate,
                    style: const TextStyle(
                      color: app_colors.AppColors.gold,
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
                      border: Border.all(color: app_colors.AppColors.gold),
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
                        title: 'PI Trust Meaning',
                        description:
                            'PI Trust is a 0-100 reliability score for the underlying prop data. It measures freshness, completeness, confirming sources, line stability, verification, and sample quality—not whether a pick is guaranteed to win.',
                        icon: Icons.shield_outlined,
                      ),
                    );
                  },
                  child: Text(
                    'PI Trust: ${prop.piTrustScore}/100',
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
                      color: app_colors.AppColors.gold,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Live pricing baseline',
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
                            color: app_colors.AppColors.goldShadow,
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
                          color: app_colors.AppColors.goldSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: app_colors.AppColors.goldShadow,
                          ),
                        ),
                        child: Text(
                          prop.sportsbook.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: app_colors.AppColors.gold,
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
                                  : app_colors.AppColors.gold,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$lineDisplay ${propSearchableMarket(prop).toUpperCase()}',
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
                    valueColor: const AlwaysStoppedAnimation(
                      app_colors.AppColors.gold,
                    ),
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
                              ? app_colors.AppColors.gold
                              : const Color(0xFF0B1721),
                          side: BorderSide(
                            color: selectedSide == PickSide.over
                                ? app_colors.AppColors.gold
                                : app_colors.AppColors.chromeShadow,
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
                              ? app_colors.AppColors.gold
                              : const Color(0xFF0B1721),
                          side: BorderSide(
                            color: selectedSide == PickSide.under
                                ? app_colors.AppColors.gold
                                : app_colors.AppColors.chromeShadow,
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
    _startQueryLoad();
    widget.refreshListenable.addListener(_handleBoardRefreshRequest);
    _expiryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final active = activePropsInChronologicalOrder(
        _preparedProps.map((prepared) => prepared.prop),
      );
      if (active.length == _preparedProps.length) return;
      setState(() {
        _preparedProps = prepareBoardProps(active);
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
    widget.refreshListenable.removeListener(_handleBoardRefreshRequest);
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
    if (oldWidget.selectedSite != widget.selectedSite) {
      _favoritePropIds.clear();
    }
    if (oldWidget.sportFilter != widget.sportFilter ||
        oldWidget.selectedSite != widget.selectedSite ||
        oldWidget.selectedCategory != widget.selectedCategory ||
        oldWidget.selectedSide != widget.selectedSide ||
        oldWidget.selectedTier != widget.selectedTier ||
        oldWidget.minConfidence != widget.minConfidence ||
        oldWidget.sortBy != widget.sortBy ||
        oldWidget.verdictFilter != widget.verdictFilter ||
        oldWidget.searchQuery != widget.searchQuery) {
      _visiblePropLimit = _visiblePropStep;
      _autoRetryTimer?.cancel();
      _automaticRetryCount = 0;
      _seasonStatusFuture = null;
      _seasonStatusSport = '';
      _seasonNotificationEnabled = false;
      _startQueryLoad();
    }
  }

  /// Shows any page already downloaded during this app session immediately.
  /// Navigation must never blank the board while the same view is refreshed.
  void _startQueryLoad() {
    final requestKey = _queryKey;
    final cached = _sessionViewCache[requestKey];
    // Never restore an empty response as a valid board snapshot. Provider
    // markets are transient, so revisiting a sport must perform a fresh sync
    // instead of getting trapped on an earlier zero-result query.
    if (cached == null || cached.isEmpty) {
      _preparedProps = const [];
      _propsFuture = _loadProps();
      return;
    }

    final activeCached = activePropsInChronologicalOrder(cached);
    _preparedProps = prepareBoardProps(activeCached);
    _propsFuture = Future<List<PropData>>.value(activeCached);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestKey != _queryKey) return;
      unawaited(_refreshLiveLines());
    });
  }

  void _rememberCurrentView(String requestKey, List<PropData> props) {
    if (props.isEmpty) {
      _sessionViewCache.remove(requestKey);
      return;
    }
    _sessionViewCache[requestKey] = List<PropData>.unmodifiable(props);
  }

  bool _matchesVisibleSnapshot(List<PropData> fresh) {
    if (fresh.length != _preparedProps.length) return false;
    for (var index = 0; index < fresh.length; index++) {
      final previous = _preparedProps[index].prop;
      final current = fresh[index];
      if (previous.id != current.id ||
          previous.imagePath != current.imagePath ||
          previous.line != current.line ||
          previous.piTrustScore != current.piTrustScore ||
          previous.isSelectable != current.isSelectable) {
        return false;
      }
    }
    return true;
  }

  Future<List<PropData>> _loadProps() async {
    final requestKey = _queryKey;
    final fetchTimer = Stopwatch()..start();
    widget.onStartupLog?.call('fetchProps() start');
    // Start the live request immediately instead of making mobile startup
    // wait for SharedPreferences and cached JSON decoding first. A fast cache
    // still paints instantly; otherwise the already-running network request
    // wins without paying both waits serially.
    final liveOutcome = _fetchPropsPage(includeReliability: true).then(
      (props) =>
          (props: props, error: null as Object?, stack: null as StackTrace?),
      onError: (Object error, StackTrace stack) =>
          (props: <PropData>[], error: error, stack: stack),
    );
    final cachedFuture = _apiService
        .loadCachedProps(
          selectedSide: widget.selectedSide,
          selectedTier: widget.selectedTier,
          selectedSportsbook: widget.selectedSite,
          selectedSport: widget.sportFilter,
          selectedCategory: widget.selectedCategory,
          search: widget.searchQuery,
          minConfidence: widget.minConfidence,
          verdictFilter: widget.verdictFilter,
          sortBy: widget.sortBy,
        )
        .catchError((_) => <PropData>[]);
    final cached = await cachedFuture.timeout(
      const Duration(milliseconds: 350),
      onTimeout: () => <PropData>[],
    );
    if (!mounted || requestKey != _queryKey) return const [];
    if (shouldRenderCachedPropsOnLaunch(
      cached,
      selectedSport: widget.sportFilter,
    )) {
      _automaticRetryCount = 0;
      final activeCached = activePropsInChronologicalOrder(cached);
      _rememberCurrentView(requestKey, activeCached);
      _preparedProps = prepareBoardProps(activeCached);
      widget.onPropsLoaded?.call(
        activeCached,
        _apiService.lastPropsCount,
        _apiService.lastFacetCount,
        _apiService.lastCategoryCounts,
      );
      unawaited(
        _refreshFirstPageFromNetwork(
          requestKey,
          pending: liveOutcome.then((outcome) {
            if (outcome.error != null) {
              Error.throwWithStackTrace(outcome.error!, outcome.stack!);
            }
            return outcome.props;
          }),
        ),
      );
      return activeCached;
    }
    final outcome = await liveOutcome;
    if (outcome.error != null) {
      // JSON restoration can take longer than 350 ms on older phones. The
      // short launch race above keeps startup fast, but a failed live request
      // should wait briefly for that same cache instead of replacing a usable
      // board with an error panel.
      final recoveredCache = cached.isNotEmpty
          ? cached
          : await cachedFuture.timeout(
              const Duration(seconds: 3),
              onTimeout: () => <PropData>[],
            );
      final sessionCache = _sessionViewCache[requestKey] ?? const <PropData>[];
      final fallback = recoveredCache.isNotEmpty
          ? recoveredCache
          : sessionCache;
      if (fallback.isNotEmpty) {
        final activeFallback = activePropsInChronologicalOrder(fallback);
        _rememberCurrentView(requestKey, activeFallback);
        _preparedProps = prepareBoardProps(activeFallback);
        widget.onPropsLoaded?.call(
          activeFallback,
          _apiService.lastPropsCount,
          _apiService.lastFacetCount,
          _apiService.lastCategoryCounts,
        );
        _scheduleAutomaticRetry();
        return activeFallback;
      }
      Error.throwWithStackTrace(outcome.error!, outcome.stack!);
    }
    final liveProps = outcome.props;
    if (liveProps.isNotEmpty) {
      _automaticRetryCount = 0;
    }
    if (!mounted || requestKey != _queryKey) return const [];
    final props = activePropsInChronologicalOrder(liveProps);
    _rememberCurrentView(requestKey, props);
    widget.onStartupLog?.call(
      'fetchProps() complete in ${fetchTimer.elapsedMilliseconds}ms (${props.length} props)',
    );
    if (fetchTimer.elapsed > const Duration(seconds: 5)) {
      EngagementTracker.instance.recordProduct('SLOW_LOAD');
    }
    final prepareTimer = Stopwatch()..start();
    _preparedProps = prepareBoardProps(props);
    widget.onStartupLog?.call(
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

  Future<List<PropData>> _fetchPropsPage({
    int offset = 0,
    bool includeReliability = false,
  }) {
    return _apiService
        .fetchProps(
          selectedSide: widget.selectedSide,
          selectedTier: widget.selectedTier,
          selectedSportsbook: widget.selectedSite,
          selectedSport: widget.sportFilter,
          selectedCategory: widget.selectedCategory,
          search: widget.searchQuery,
          minConfidence: widget.minConfidence,
          verdictFilter: widget.verdictFilter,
          sortBy: widget.sortBy,
          limit: _visiblePropStep,
          offset: offset,
          includeReliability: includeReliability,
        )
        .timeout(
          propFetchTimeout,
          onTimeout: () => throw TimeoutException(
            'The prop feed did not respond within '
            '${propFetchTimeout.inSeconds} seconds.',
            propFetchTimeout,
          ),
        );
  }

  Future<void> _refreshFirstPageFromNetwork(
    String requestKey, {
    Future<List<PropData>>? pending,
  }) async {
    try {
      final fresh = activePropsInChronologicalOrder(
        await (pending ?? _fetchPropsPage()),
      );
      if (!mounted || requestKey != _queryKey) return;
      // Keeping the last page through an empty response protects the
      // board from a blip in the feed. Applied to a narrowed query it
      // does the opposite: it leaves the previous sport's props on
      // screen and makes the filter look like it did nothing.
      if (fresh.isEmpty && _preparedProps.isNotEmpty && !_isNarrowedQuery) {
        _autoRetryTimer = null;
        _scheduleAutomaticRetry();
        return;
      }
      _rememberCurrentView(requestKey, fresh);
      if (_matchesVisibleSnapshot(fresh)) {
        widget.onPropsLoaded?.call(
          fresh,
          _apiService.lastPropsCount,
          _apiService.lastFacetCount,
          _apiService.lastCategoryCounts,
        );
        return;
      }
      setState(() {
        _preparedProps = prepareBoardProps(fresh);
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
        _preparedProps = prepareBoardProps(merged);
        _visiblePropLimit = _preparedProps.length;
        _propsFuture = Future.value(merged);
      });
      _rememberCurrentView(requestKey, merged);
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
      // Ticket reconciliation and the visible board refresh are independent.
      // Running them together removes the pause where mobile users waited for
      // every saved leg before the first fresh prop card could appear.
      await Future.wait<void>([
        SlipManager.refreshSelectedProps(_apiService),
        _refreshFirstPageFromNetwork(_queryKey),
      ]);
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
      _seasonStatusFuture = null;
      _seasonStatusFetchedAt = null;
      _propsFuture = _loadProps();
    });
  }

  Future<_SportSeasonStatus> _loadSeasonStatus(String sport) async {
    try {
      final games = widget.scheduleLoader == null
          ? await _loadUpcomingScoreboardGames(sport)
          : await widget.scheduleLoader!(sport);
      return _SportSeasonStatus.fromGames(sport, games);
    } catch (_) {
      return _SportSeasonStatus.unavailable(sport);
    }
  }

  Future<List<ScoreboardGame>> _loadUpcomingScoreboardGames(
    String sport,
  ) async {
    final service = ScoreboardService(baseUrl: ApiService.baseUrl);
    final now = DateTime.now();
    final daily = <List<ScoreboardGame>>[
      await service.fetchGamesRange(startDate: now, days: 90),
    ];
    final normalized = normalizePropSport(sport);
    final unique = <String, ScoreboardGame>{};
    for (final game in daily.expand((games) => games)) {
      final gameSport = normalizePropSport(
        game.sport.isEmpty ? game.league : game.sport,
      );
      if (gameSport != normalized || !game.isUpcoming) continue;
      unique[game.id] = game;
    }
    final games = unique.values.toList()
      ..sort(
        (a, b) => (a.startTime ?? DateTime(2100)).compareTo(
          b.startTime ?? DateTime(2100),
        ),
      );
    return games;
  }

  Future<_SportSeasonStatus> _seasonStatus(String sport) {
    final normalized = normalizePropSport(sport);
    final fetchedAt = _seasonStatusFetchedAt;
    final stale =
        fetchedAt == null ||
        DateTime.now().difference(fetchedAt) >= const Duration(minutes: 5);
    if (_seasonStatusFuture == null ||
        _seasonStatusSport != normalized ||
        stale) {
      _seasonStatusSport = normalized;
      _seasonStatusFetchedAt = DateTime.now();
      _seasonStatusFuture = _loadSeasonStatus(normalized);
    }
    return _seasonStatusFuture!;
  }

  Future<void> _showUpcomingSchedule(_SportSeasonStatus status) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1822),
        title: Text(
          '${status.sport} UPCOMING GAMES',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final game in status.games.take(3))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.event_rounded,
                    color: app_colors.AppColors.gold,
                  ),
                  title: Text(
                    status.matchup(game),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    status.gameDate(game),
                    style: const TextStyle(
                      color: app_colors.AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  /// Whether the board has been narrowed by a filter.
  ///
  /// An empty response means opposite things either side of this. With
  /// nothing selected it means the feed is in trouble and the previous
  /// page is worth keeping. With a sport chosen it is simply the
  /// answer -- basketball in August has no props -- and retrying while
  /// showing another sport's props reads as the filter being ignored.
  bool get _isNarrowedQuery => isNarrowedBoardQuery(
    sport: widget.sportFilter,
    site: widget.selectedSite,
    category: widget.selectedCategory,
    side: widget.selectedSide,
    tier: widget.selectedTier,
    search: widget.searchQuery,
    minConfidence: widget.minConfidence,
  );
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
      if (props.isEmpty && !_isNarrowedQuery) {
        throw StateError('The live prop feed is temporarily empty.');
      }
      setState(() {
        _preparedProps = prepareBoardProps(props);
        _propsFuture = Future.value(props);
      });
      _rememberCurrentView(requestKey, props);
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

  Future<void> _showLineAlternatives(PropBookGroup group) async {
    final variants = [...group.variants]
      ..sort((left, right) {
        final provider = left.sportsbook.compareTo(right.sportsbook);
        if (provider != 0) return provider;
        return _displayedLineValue(left).compareTo(_displayedLineValue(right));
      });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF081620),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.swap_vert_circle_outlined,
                      color: app_colors.AppColors.gold,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.representative.player.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${group.representative.market} • ${variants.length} CURRENT OPTIONS',
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: app_colors.AppColors.border),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(14),
                  itemCount: variants.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final variant = variants[index];
                    final advisedSide =
                        variant.recommendedSide.trim().toUpperCase().contains(
                          'UNDER',
                        )
                        ? PickSide.under
                        : PickSide.over;
                    final special = _specialLineBadge(variant, advisedSide);
                    final lineValues = variants
                        .map(_displayedLineValue)
                        .toList(growable: false);
                    final currentLine = _displayedLineValue(variant);
                    final easiestLine = advisedSide == PickSide.over
                        ? lineValues.reduce((a, b) => a < b ? a : b)
                        : lineValues.reduce((a, b) => a > b ? a : b);
                    final lineBadge =
                        special ??
                        (group.linesDiffer && currentLine == easiestLine
                            ? advisedSide == PickSide.over
                                  ? 'LOWER LINE AVAILABLE'
                                  : 'HIGHER LINE AVAILABLE'
                            : null);
                    return Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C1B26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: lineBadge == null
                              ? app_colors.AppColors.border
                              : app_colors.AppColors.gold,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  variant.sportsbook.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (lineBadge != null)
                                Text(
                                  lineBadge,
                                  style: const TextStyle(
                                    color: app_colors.AppColors.gold,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: variant.dataStale
                                      ? null
                                      : () {
                                          Navigator.pop(sheetContext);
                                          widget.onSelect(
                                            variant,
                                            PickSide.under,
                                          );
                                        },
                                  child: Text(
                                    'UNDER ${_displayedLineValue(variant).toStringAsFixed(1)}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: variant.dataStale
                                      ? null
                                      : () {
                                          Navigator.pop(sheetContext);
                                          widget.onSelect(
                                            variant,
                                            PickSide.over,
                                          );
                                        },
                                  child: Text(
                                    'OVER ${_displayedLineValue(variant).toStringAsFixed(1)}',
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
            ],
          ),
        ),
      ),
    );
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
              return const PropLoadingSkeleton();
            }

            if (snapshot.hasError) {
              final normalizedSport = normalizePropSport(
                widget.displaySportFilter.isEmpty
                    ? widget.sportFilter
                    : widget.displaySportFilter,
              );
              const specialtySports = {'SOCCER'};
              final specialtyFeedUnavailable = specialtySports.contains(
                normalizedSport,
              );
              if (!specialtyFeedUnavailable) {
                _scheduleAutomaticRetry();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: PropLoadError(
                  title: specialtyFeedUnavailable
                      ? 'NO CURRENT $normalizedSport PROPS'
                      : 'Unable to load props',
                  message: specialtyFeedUnavailable
                      ? 'The selected providers have not returned current $normalizedSport props. The board will refresh automatically when an authorized feed posts them.'
                      : describeLoadFailure(snapshot.error),
                  onRetry: _retryLoad,
                  onSignIn: isAuthenticationLoadError(snapshot.error)
                      ? () => unawaited(
                          AuthManager.instance.signOut().catchError((_) {}),
                        )
                      : null,
                ),
              );
            }

            final allPrepared = _preparedProps.isNotEmpty
                ? _preparedProps
                : prepareBoardProps(snapshot.data ?? []);
            final selectedSport = widget.displaySportFilter.isEmpty
                ? widget.sportFilter
                : widget.displaySportFilter;
            final normalizedSport = normalizePropSport(selectedSport);
            final preparedSignature = Object.hashAll(
              allPrepared.map(
                (item) => Object.hash(
                  item.prop.id,
                  item.prop.line,
                  item.prop.currentLine,
                  item.prop.gameHasStarted,
                ),
              ),
            );
            final boardCacheKey = [
              preparedSignature,
              allPrepared.length,
              selectedSport,
              widget.selectedSite,
              widget.selectedCategory,
              widget.selectedSide,
              widget.selectedTier,
              widget.minConfidence,
              widget.searchQuery,
              widget.verdictFilter,
              widget.sortBy,
              // Pinning reorders the board, so it belongs in the key.
              _favoritePropIds.length,
              _favoritePropIds.fold<int>(0, (sum, id) => sum ^ id.hashCode),
            ].join('|');
            if (boardCacheKey != _boardCacheKey) {
              _boardCacheKey = boardCacheKey;
              _boardCacheGroups = collapsePropsByBook(
                filterAndSortBoardProps(
                  allPrepared,
                  selectedSport: selectedSport,
                  selectedSite: widget.selectedSite,
                  searchQuery: widget.searchQuery,
                  verdictFilter: widget.verdictFilter,
                  sortBy: widget.sortBy,
                  pinnedPropIds: _favoritePropIds,
                ),
              );
            }
            final props = _boardCacheGroups
                .map((group) => group.representative)
                .toList(growable: false);
            _favoritePropIds.retainAll(props.map((prop) => prop.id).toSet());
            if (props.isEmpty) {
              const specialtySports = {'SOCCER'};
              final specialtyFeedEmpty = specialtySports.contains(
                normalizedSport,
              );
              final hasFilters = hasActiveBoardFilters(
                sport: widget.sportFilter,
                site: widget.selectedSite,
                category: widget.selectedCategory,
                side: widget.selectedSide,
                tier: widget.selectedTier,
                verdict: widget.verdictFilter,
                search: widget.searchQuery,
                minConfidence: widget.minConfidence,
              );
              final hasSecondaryFilters = hasActiveBoardFilters(
                sport: 'ALL',
                site: widget.selectedSite,
                category: widget.selectedCategory,
                side: widget.selectedSide,
                tier: widget.selectedTier,
                verdict: widget.verdictFilter,
                search: widget.searchQuery,
                minConfidence: widget.minConfidence,
              );
              if (!hasFilters && _automaticRetryCount < 3) {
                _scheduleAutomaticRetry();
              }
              // A selected sport deserves a schedule-aware empty state even
              // when a book, side, or category is also selected. Previously
              // those normal board filters forced Soccer, NCAAF, and CFL into
              // the generic "no props" panel and hid known season dates.
              if (normalizedSport.isNotEmpty && normalizedSport != 'ALL') {
                return FutureBuilder<_SportSeasonStatus>(
                  future: _seasonStatus(normalizedSport),
                  builder: (context, statusSnapshot) {
                    if (statusSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const PropLoadingSkeleton();
                    }
                    final status =
                        statusSnapshot.data ??
                        _SportSeasonStatus.unavailable(normalizedSport);
                    return _SeasonStatusPanel(
                      status: status,
                      notificationEnabled: _seasonNotificationEnabled,
                      onCheckAgain: _retryLoad,
                      onViewSchedule: status.games.isEmpty
                          ? null
                          : () => _showUpcomingSchedule(status),
                      onNotify: () {
                        setState(
                          () => _seasonNotificationEnabled =
                              !_seasonNotificationEnabled,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _seasonNotificationEnabled
                                  ? '${status.sport} market notifications enabled for this session.'
                                  : '${status.sport} market notifications disabled.',
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              }
              return Container(
                margin: const EdgeInsets.only(top: 18),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 34,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF09141E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: app_colors.AppColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off_rounded,
                      color: app_colors.AppColors.gold,
                      size: 34,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      specialtyFeedEmpty
                          ? 'NO LICENSED $normalizedSport PROPS AVAILABLE'
                          : hasSecondaryFilters
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
                      specialtyFeedEmpty
                          ? 'The selected prop sites returned no current $normalizedSport player props. Categories remain available above and props will appear automatically when an authorized feed posts them.'
                          : hasSecondaryFilters
                          ? 'Try ALL sports, ALL sites and ALL categories. A sport may also be between games or out of season.'
                          : 'The live provider has no current or upcoming props. Refresh again when new games are posted.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: app_colors.AppColors.textMuted,
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
                final columns = propGridColumnCount(constraints.maxWidth);
                final cardSpacing = propGridSpacing(constraints.maxWidth);

                // Keep one current card per player/market. Every provider,
                // alternate line, and promotional line remains available
                // through the options picker instead of appearing as a
                // duplicate card or being silently discarded.
                final groups = _boardCacheGroups;
                final visibleCount = _visiblePropLimit.clamp(0, groups.length);
                final visibleGroups = groups.take(visibleCount).toList();
                final hasMore =
                    visibleCount < groups.length ||
                    _preparedProps.length < _apiService.lastPropsCount;

                if (widget.siteFirstLayout &&
                    useTabletPropTable(MediaQuery.sizeOf(context).width)) {
                  return TabletPropTable(
                    key: const ValueKey('tablet-prop-table'),
                    groups: visibleGroups,
                    selections: widget.selections,
                    onSelect: widget.onSelect,
                    onOpenProp: widget.onPropFocused,
                    onShowLineAlternatives: _showLineAlternatives,
                    hasMore: hasMore,
                    isLoadingMore: _isLoadingMore,
                    onLoadMore: () {
                      if (_isLoadingMore) return;
                      if (visibleCount < groups.length) {
                        setState(() {
                          _visiblePropLimit += _visiblePropStep;
                        });
                      } else {
                        unawaited(_loadMoreProps());
                      }
                    },
                  );
                }

                Widget cardFor(PropData prop, {required bool fixedHeight}) {
                  SlipSelection? selected;
                  for (final selection in widget.selections) {
                    if (selection.prop.id == prop.id) {
                      selected = selection;
                      break;
                    }
                  }
                  return RepaintBoundary(
                    // Without a key the framework matches cards by position,
                    // so a re-sort hands a card a different prop and its
                    // headshot reloads from scratch: the photos blink out and
                    // back on every refresh and every filter change.
                    key: ValueKey('card-${prop.id}'),
                    child: widget.siteFirstLayout
                        ? _buildSiteFirstPropCard(prop, selected?.side)
                        : _buildPortraitPropCard(
                            prop,
                            selected?.side,
                            fixedHeight: fixedHeight,
                          ),
                  );
                }

                Widget groupCardFor(
                  PropBookGroup group, {
                  required bool fixedHeight,
                }) {
                  final card = cardFor(
                    group.representative,
                    fixedHeight: fixedHeight,
                  );
                  if (!group.hasAlternatives) return card;
                  final optionsButton = SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showLineAlternatives(group),
                      icon: const Icon(Icons.swap_vert_rounded, size: 16),
                      label: Text(
                        '${group.variants.length} CURRENT LINE OPTIONS',
                      ),
                    ),
                  );
                  if (fixedHeight) {
                    return Column(
                      children: [
                        Expanded(child: card),
                        const SizedBox(height: 6),
                        optionsButton,
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [card, const SizedBox(height: 6), optionsButton],
                  );
                }

                Widget providerHeader(String provider, int count) => Container(
                  key: ValueKey('provider-section-$provider'),
                  margin: const EdgeInsets.only(top: 4, bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: app_colors.AppColors.gold.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: app_colors.AppColors.gold),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        size: 16,
                        color: app_colors.AppColors.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                      Text(
                        '$count ${count == 1 ? 'PROP' : 'PROPS'}',
                        style: const TextStyle(
                          color: app_colors.AppColors.gold,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );

                final providerSections = <String, List<PropBookGroup>>{};
                for (final group in visibleGroups) {
                  final shown = group.representative;
                  final provider = shown.sportsbook.trim().isEmpty
                      ? 'OTHER PROVIDER'
                      : shown.sportsbook.trim().toUpperCase();
                  providerSections
                      .putIfAbsent(provider, () => <PropBookGroup>[])
                      .add(group);
                }

                Widget providerCards(List<PropBookGroup> sectionGroups) {
                  if (columns == 1) {
                    return Column(
                      children: [
                        for (final group in sectionGroups) ...[
                          groupCardFor(group, fixedHeight: false),
                          SizedBox(height: cardSpacing),
                        ],
                      ],
                    );
                  }
                  final rowCount = (sectionGroups.length / columns).ceil();
                  final minimumPerRow = sectionGroups.length ~/ rowCount;
                  final fullerRows = sectionGroups.length % rowCount;
                  var groupIndex = 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var rowIndex = 0;
                        rowIndex < rowCount;
                        rowIndex++
                      ) ...[
                        if (rowIndex > 0) SizedBox(height: cardSpacing),
                        Builder(
                          builder: (context) {
                            final cardsInRow =
                                minimumPerRow + (rowIndex < fullerRows ? 1 : 0);
                            final rowGroups = sectionGroups.sublist(
                              groupIndex,
                              groupIndex += cardsInRow,
                            );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  var index = 0;
                                  index < rowGroups.length;
                                  index++
                                ) ...[
                                  if (index > 0) SizedBox(width: cardSpacing),
                                  Expanded(
                                    child: SizedBox(
                                      height: widget.siteFirstLayout
                                          ? 226
                                          : 474,
                                      child: groupCardFor(
                                        rowGroups[index],
                                        fixedHeight: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // On a phone the cards are a single column, so nothing is
                    // gained by forcing every one to the same 410px and much is
                    // lost: a collapsed card is far shorter than that, and the
                    // padding needed to reach it is what pushed the buttons off
                    // the first screen. A list lets each card be its own size.
                    for (final section in providerSections.entries) ...[
                      if (widget.selectedSite == 'ALL')
                        providerHeader(section.key, section.value.length),
                      providerCards(section.value),
                      SizedBox(height: cardSpacing),
                    ],
                    if (hasMore) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: _isLoadingMore
                              ? null
                              : () {
                                  if (visibleCount < groups.length) {
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
            border: Border.all(color: app_colors.AppColors.gold, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: app_colors.AppColors.gold.withValues(alpha: 0.2),
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
                  Icon(icon, color: app_colors.AppColors.gold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: app_colors.AppColors.gold,
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

class _SportSeasonStatus {
  const _SportSeasonStatus({
    required this.sport,
    required this.state,
    required this.title,
    required this.message,
    required this.games,
  });

  final String sport;
  final String state;
  final String title;
  final String message;
  final List<ScoreboardGame> games;

  static const _continuousSports = {'SOCCER'};

  factory _SportSeasonStatus.fromGames(
    String sport,
    List<ScoreboardGame> games,
  ) {
    final normalized = normalizePropSport(sport);
    final ordered = [...games]
      ..sort(
        (a, b) => (a.startTime ?? DateTime(2100)).compareTo(
          b.startTime ?? DateTime(2100),
        ),
      );
    if (ordered.isEmpty) {
      final continuous = _continuousSports.contains(normalized);
      final nhlOffseason = normalized == 'NHL';
      return _SportSeasonStatus(
        sport: normalized,
        state: continuous ? 'no_upcoming_markets' : 'offseason',
        title: nhlOffseason
            ? 'NHL OFFSEASON - NO CURRENT INVENTORY'
            : continuous
            ? '$normalized NO UPCOMING MARKETS'
            : '$normalized OFFSEASON',
        message: nhlOffseason
            ? 'No current NHL player-prop inventory is posted. PI will keep checking automatically and restore the board when preseason or regular-season markets open.'
            : continuous
            ? 'No upcoming supported events are currently available. PI will update this board automatically when a new market is posted.'
            : 'The next schedule is not available yet. PI will update this board automatically when the season calendar is released.',
        games: const [],
      );
    }
    final first = ordered.first.startTime;
    final until = first == null
        ? Duration.zero
        : first.difference(DateTime.now());
    final imminent = until <= const Duration(days: 1);
    final continuous = _continuousSports.contains(normalized);
    final soccerWithoutPlayerMarkets = normalized == 'SOCCER' && imminent;
    return _SportSeasonStatus(
      sport: normalized,
      state: imminent ? 'unavailable' : 'awaiting_markets',
      title: soccerWithoutPlayerMarkets
          ? 'SOCCER GAMES AVAILABLE - PLAYER PROPS UNAVAILABLE'
          : imminent
          ? '$normalized MARKETS CURRENTLY UNAVAILABLE'
          : continuous
          ? '$normalized EVENTS COMING SOON'
          : '$normalized PRESEASON - MARKETS OPENING SOON',
      message: soccerWithoutPlayerMarkets
          ? 'Games are scheduled, but supported feeds have not posted player-prop markets for the selected league, including Bundesliga when applicable. PI will keep checking automatically.'
          : imminent
          ? 'Games are scheduled, but supported books have not returned player props. The board will keep checking automatically.'
          : 'Player props will appear automatically when supported books release their markets.',
      games: List.unmodifiable(ordered),
    );
  }

  factory _SportSeasonStatus.unavailable(String sport) => _SportSeasonStatus(
    sport: normalizePropSport(sport),
    state: 'schedule_unavailable',
    title: '${normalizePropSport(sport)} SCHEDULE TEMPORARILY UNAVAILABLE',
    message:
        'The schedule feed could not be confirmed. Current prop markets will continue refreshing automatically.',
    games: const [],
  );

  ScoreboardGame? get nextGame => games.isEmpty ? null : games.first;

  String matchup(ScoreboardGame game) {
    if (game.isUfc) {
      return '${game.fighterOne ?? ''} vs ${game.fighterTwo ?? ''}'.trim();
    }
    return '${game.awayTeam} @ ${game.homeTeam}'.trim();
  }

  String gameDate(ScoreboardGame game) {
    final date = game.startTime?.toLocal();
    if (date == null) return game.displayTime ?? 'Time to be announced';
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
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day} - $hour:$minute $suffix';
  }

  String get countdown {
    final start = nextGame?.startTime;
    if (start == null) return 'SCHEDULE PENDING';
    final duration = start.difference(DateTime.now());
    if (duration.isNegative) return 'STARTING SOON';
    if (duration.inDays > 0) {
      return '${duration.inDays} ${duration.inDays == 1 ? 'DAY' : 'DAYS'} AWAY';
    }
    return '${duration.inHours.clamp(1, 23)} HOURS AWAY';
  }
}

class _SeasonStatusPanel extends StatelessWidget {
  const _SeasonStatusPanel({
    required this.status,
    required this.notificationEnabled,
    required this.onCheckAgain,
    required this.onViewSchedule,
    required this.onNotify,
  });

  final _SportSeasonStatus status;
  final bool notificationEnabled;
  final VoidCallback onCheckAgain;
  final VoidCallback? onViewSchedule;
  final VoidCallback onNotify;

  @override
  Widget build(BuildContext context) {
    final next = status.nextGame;
    return Container(
      key: const ValueKey('season-status-panel'),
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF09141E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: app_colors.AppColors.borderGold),
      ),
      child: Column(
        children: [
          Icon(
            next == null
                ? Icons.event_busy_rounded
                : Icons.event_available_rounded,
            color: app_colors.AppColors.gold,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            status.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          if (next != null) ...[
            const SizedBox(height: 16),
            const Text(
              'FIRST SCHEDULED GAME',
              style: TextStyle(
                color: app_colors.AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${status.gameDate(next)}  |  ${status.countdown}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            status.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onViewSchedule != null)
                OutlinedButton.icon(
                  onPressed: onViewSchedule,
                  icon: const Icon(Icons.calendar_month_rounded, size: 17),
                  label: const Text('VIEW SCHEDULE'),
                ),
              OutlinedButton.icon(
                onPressed: onNotify,
                icon: Icon(
                  notificationEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 17,
                ),
                label: Text(notificationEnabled ? 'NOTIFYING' : 'NOTIFY ME'),
              ),
              TextButton.icon(
                onPressed: onCheckAgain,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('CHECK AGAIN'),
              ),
            ],
          ),
          if (status.games.isNotEmpty) ...[
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 720
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 20) / 3;
                final games = status.games.take(3).toList();
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SeasonInfoTile(
                      width: width,
                      icon: Icons.lock_clock_rounded,
                      title: 'OPENING SOON',
                      detail:
                          'Prop-site markets commonly appear 1-7 days before games.',
                    ),
                    _SeasonInfoTile(
                      width: width,
                      icon: Icons.sports_score_rounded,
                      title: 'UPCOMING GAMES',
                      detail: games.map(status.matchup).join('  |  '),
                    ),
                    _SeasonInfoTile(
                      width: width,
                      icon: Icons.history_rounded,
                      title: 'LAST SEASON RESEARCH',
                      detail:
                          'Historical results remain available in Track Record.',
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Schedule checked ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonInfoTile extends StatelessWidget {
  const _SeasonInfoTile({
    required this.width,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 92),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: app_colors.AppColors.panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: app_colors.AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: app_colors.AppColors.gold, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: app_colors.AppColors.textMuted,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
