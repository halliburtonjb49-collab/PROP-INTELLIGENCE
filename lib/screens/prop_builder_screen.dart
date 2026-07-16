import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/line_movement_alert.dart';
import '../controllers/active_slip_controller.dart';
import '../services/api_service.dart';
import '../services/prop_watchlist_service.dart';
import 'prop_watchlist_screen.dart';

enum SlipExportAction { copyText, saveImage, savePdf, printSlip }

class PropBuilderScreen extends StatefulWidget {
  const PropBuilderScreen({
    super.key,
    required this.activeSlipController,
    required this.isManualSportsMode,
    this.initialSelectedSports,
    this.onSelectedSportsChanged,
    this.onResetSportsAutoSync,
  });

  final ActiveSlipController activeSlipController;
  final bool isManualSportsMode;
  final List<String>? initialSelectedSports;
  final ValueChanged<List<String>>? onSelectedSportsChanged;
  final VoidCallback? onResetSportsAutoSync;

  @override
  State<PropBuilderScreen> createState() => _PropBuilderScreenState();
}

class _PropBuilderScreenState extends State<PropBuilderScreen> {
  static const Duration _criticalToastCooldown = Duration(seconds: 75);
  static const String _prefAlertOnBetterMovement =
      'prop_builder.alert_on_better_movement';
  static const String _prefAlertOnWorseMovement =
      'prop_builder.alert_on_worse_movement';
  static const String _prefAlertOnUnavailable =
      'prop_builder.alert_on_unavailable';
  static const String _prefAlertOnOddsMovement =
      'prop_builder.alert_on_odds_movement';
  static const String _prefSignificantOddsMovement =
      'prop_builder.significant_odds_movement';

  static const List<String> _availableSports = [
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

  static const List<String> _availablePropSites = [
    'PrizePicks',
    'Underdog',
    'Sleeper',
    'FanDuel',
    'Draft Picks',
  ];
  static const List<String> _availableMarkets = [
    'points',
    'rebounds',
    'assists',
    'pra',
    'three_pointers_made',
    'steals',
    'blocks',
    'turnovers',
    'strikeouts',
    'hits',
    'home_runs',
    'total_bases',
    'rbi',
    'passing_yards',
    'rushing_yards',
    'receiving_yards',
    'receptions',
    'shots_on_goal',
    'saves',
  ];

  static const List<String> _quickLabels = [
    'Best Bet',
    'High Confidence',
    'Watch Injury News',
    'Late Game',
    'Line Movement',
  ];

  final ApiService _apiService = ApiService();
  final PropWatchlistService _watchlistService = PropWatchlistService();

  final Set<String> _selectedSports = {};

  final Set<String> _selectedSites = {
    'PrizePicks',
    'Underdog',
    'Sleeper',
    'FanDuel',
    'Draft Picks',
  };
  final Set<String> _selectedMarkets = {};

  int _legCount = 3;
  double _minimumEdge = 60;
  double _minimumConfidence = 60;
  bool _sameGameAllowed = false;
  bool _isLoading = false;
  String _buildMode = 'SAME_SPORT';
  String _riskMode = 'BALANCED';
  bool _correlationGuardEnabled = true;
  int _maximumLegsPerGame = 1;
  int _maximumLegsPerTeam = 2;
  int _maximumLegsPerPlayer = 1;
  bool _isLoadingHistory = false;
  bool _isLoadingPresets = false;
  bool _isSavingPreset = false;
  bool _showBuildHistory = false;
  bool _isGradingHistory = false;
  String? _selectedPresetName;
  String? _error;
  int _requestedLegs = 0;
  int _generatedLegCount = 0;
  double _averageEdge = 0;
  double _averageConfidence = 0;
  String _responseBuildMode = '';
  List<String> _responseSites = [];
  List<String> _responseSports = [];
  List<String> _correlationWarnings = [];
  String? _expandedExplanationPropId;
  List<Map<String, dynamic>> _generatedLegs = [];
  List<Map<String, dynamic>> _buildHistory = [];
  List<Map<String, dynamic>> _presets = [];
  String _sidePreference = 'ANY';
  String? _replacingPropId;
  String? _editingNotePropId;
  final Set<String> _selectedGeneratedPropIds = {};
  final Set<String> _lockedGeneratedPropIds = {};
  Map<String, dynamic>? _builderStrategy;
  bool _isLoadingStrategy = false;
  final GlobalKey _exportCardKey = GlobalKey();
  bool _isExportingSlip = false;
  bool _isCheckingLines = false;
  DateTime? _lastLineMovementCheck;
  bool _autoCheckLines = false;
  Timer? _lineMovementTimer;
  final List<LineMovementAlert> _lineMovementAlerts = [];
  bool _alertOnBetterMovement = false;
  bool _alertOnWorseMovement = true;
  bool _alertOnUnavailable = true;
  bool _alertOnOddsMovement = true;
  int _significantOddsMovement = 15;
  final Map<String, GlobalKey> _generatedLegCardKeys = {};
  DateTime? _lastCriticalToastAt;
  String? _lastCriticalToastSignature;
  final Set<String> _watchlistedPropIds = {};
  bool _isLoadingWatchlist = false;
  bool _hasAttemptedBuild = false;
  bool? _backendOnline;
  int _availableCandidateCount = 0;
  int _filteredOutCount = 0;
  List<String> _buildMessages = [];
  final Set<String> _alertSeverityFilter = {
    'CRITICAL',
    'WARNING',
    'POSITIVE',
    'INFO',
  };

  @override
  void initState() {
    super.initState();
    _applyInitialSelectedSports(widget.initialSelectedSports);
    widget.activeSlipController.addListener(_handleActiveSlipChanged);
    _initializeLocalNotifications();
    _loadAlertSettings();
    _loadPresets();
    _loadBuildHistory();
    _loadBuilderStrategy();
    _loadWatchlistIds();
    _checkBackendStatus();
  }

  @override
  void didUpdateWidget(covariant PropBuilderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSportsSelection(
      oldWidget.initialSelectedSports,
      widget.initialSelectedSports,
    )) {
      _applyInitialSelectedSports(widget.initialSelectedSports);
    }
  }

  @override
  void dispose() {
    widget.activeSlipController.removeListener(_handleActiveSlipChanged);
    _lineMovementTimer?.cancel();
    super.dispose();
  }

  void _handleActiveSlipChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _emitSelectedSportsChanged() {
    widget.onSelectedSportsChanged?.call(
      _selectedSports.toList(growable: false),
    );
  }

  void _applyInitialSelectedSports(List<String>? sports) {
    final nextSports = sports?.where((sport) => sport.isNotEmpty).toSet();
    _selectedSports
      ..clear()
      ..addAll(
        nextSports == null || nextSports.isEmpty ? {'WNBA'} : nextSports,
      );
  }

  bool _sameSportsSelection(List<String>? left, List<String>? right) {
    final leftSet = left?.toSet() ?? const <String>{};
    final rightSet = right?.toSet() ?? const <String>{};
    if (leftSet.length != rightSet.length) {
      return false;
    }
    return leftSet.containsAll(rightSet);
  }

  Future<void> _initializeLocalNotifications() async {
    if (!Platform.isWindows) {
      return;
    }
    await localNotifier.setup(
      appName: 'PROP INTELLIGENCE',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }

  Future<void> _loadAlertSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _alertOnBetterMovement =
          preferences.getBool(_prefAlertOnBetterMovement) ?? false;
      _alertOnWorseMovement =
          preferences.getBool(_prefAlertOnWorseMovement) ?? true;
      _alertOnUnavailable =
          preferences.getBool(_prefAlertOnUnavailable) ?? true;
      _alertOnOddsMovement =
          preferences.getBool(_prefAlertOnOddsMovement) ?? true;
      _significantOddsMovement =
          preferences.getInt(_prefSignificantOddsMovement) ?? 15;
    });
  }

  Future<void> _saveAlertSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      _prefAlertOnBetterMovement,
      _alertOnBetterMovement,
    );
    await preferences.setBool(_prefAlertOnWorseMovement, _alertOnWorseMovement);
    await preferences.setBool(_prefAlertOnUnavailable, _alertOnUnavailable);
    await preferences.setBool(_prefAlertOnOddsMovement, _alertOnOddsMovement);
    await preferences.setInt(
      _prefSignificantOddsMovement,
      _significantOddsMovement,
    );
  }

  Widget _buildErrorPanel({required String message, VoidCallback? onRetry}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.error),
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.25),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          if (onRetry != null) ...[
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY'),
            ),
          ],
        ],
      ),
    );
  }

  String _friendlyBuilderError(Object error) {
    final message = error.toString();
    if (message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('SocketException')) {
      return 'The backend is not running. Start the FastAPI server and try again.';
    }
    if (message.contains('TimeoutException')) {
      return 'The request took too long. Check your internet connection and retry.';
    }
    if (message.contains('400')) {
      return 'The selected filters could not produce a valid slip. Adjust the filters and try again.';
    }
    if (message.contains('401') || message.contains('403')) {
      return 'The data provider rejected the request. Check the API key in the backend .env file.';
    }
    if (message.contains('429')) {
      return 'The data provider rate limit was reached. Wait a moment before trying again.';
    }
    if (message.contains('500')) {
      return 'The backend encountered an error. Check the FastAPI terminal for details.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  String? _validateBuilderSettings() {
    if (_selectedSports.isEmpty) {
      return 'Select at least one sport.';
    }
    if (_selectedSites.isEmpty) {
      return 'Select at least one prop site.';
    }
    if (_legCount < 2) {
      return 'Select at least two legs.';
    }
    if (_minimumEdge < 0 || _minimumEdge > 100) {
      return 'Minimum edge must be between 0% and 100%.';
    }
    if (_minimumConfidence < 0 || _minimumConfidence > 100) {
      return 'Minimum confidence must be between 0% and 100%.';
    }
    if (_buildMode == 'SAME_SPORT' && _selectedSports.length > 1) {
      return 'Same Sport mode requires one selected sport.';
    }
    if (_correlationGuardEnabled && _maximumLegsPerGame < 1) {
      return 'Maximum legs per game must be at least one.';
    }
    return null;
  }

  Widget _buildNoResultsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 46),
          const SizedBox(height: 14),
          const Text(
            'No props matched your filters',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try lowering edge or confidence, allowing more markets, or selecting another prop site.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _minimumEdge = 50;
                    _minimumConfidence = 55;
                  });
                },
                child: const Text('LOWER THRESHOLDS'),
              ),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedMarkets.clear();
                  });
                },
                child: const Text('ALLOW ALL MARKETS'),
              ),
              FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.refresh),
                label: const Text('TRY AGAIN'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInitialBuilderState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Column(
        children: [
          Icon(Icons.auto_awesome, size: 48),
          SizedBox(height: 14),
          Text(
            'Build your first prop slip',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Choose your sports, prop sites, markets, thresholds, and risk mode. Then press Build My Slip.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  bool get _isPartialBuild {
    return _generatedLegCount > 0 && _generatedLegCount < _requestedLegs;
  }

  Widget _buildPartialBuildWarning() {
    if (!_isPartialBuild) {
      return const SizedBox.shrink();
    }
    final missing = _requestedLegs - _generatedLegCount;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.tertiary),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Built $_generatedLegCount of $_requestedLegs requested legs. $missing additional ${missing == 1 ? 'prop was' : 'props were'} not available under the current filters.',
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _minimumEdge = (_minimumEdge - 5).clamp(0, 100).toDouble();
                _minimumConfidence = (_minimumConfidence - 5)
                    .clamp(0, 100)
                    .toDouble();
              });
              _generate();
            },
            child: const Text('RELAX FILTERS'),
          ),
        ],
      ),
    );
  }

  Widget _buildBuildDetailsPanel() {
    if (!_hasAttemptedBuild) {
      return const SizedBox.shrink();
    }
    if (_availableCandidateCount == 0 &&
        _filteredOutCount == 0 &&
        _buildMessages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BUILD DETAILS',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Candidates $_availableCandidateCount')),
              Chip(label: Text('Filtered out $_filteredOutCount')),
            ],
          ),
          if (_buildMessages.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._buildMessages.map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 17),
                    const SizedBox(width: 8),
                    Expanded(child: Text(message)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isUnavailable(Map<String, dynamic> leg) {
    return leg['movement_status']?.toString().toUpperCase() == 'UNAVAILABLE';
  }

  bool _isLineStale(Map<String, dynamic> leg) {
    final raw = leg['last_line_check']?.toString();
    if (raw == null || raw.isEmpty) {
      return false;
    }
    final checkedAt = DateTime.tryParse(raw);
    if (checkedAt == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(checkedAt.toUtc()).inMinutes > 10;
  }

  Future<bool> _confirmStaleLines(int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Lines May Be Stale'),
          content: Text(
            '$count selected ${count == 1 ? 'prop has' : 'props have'} not been checked recently.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop(false);
                await _checkLineMovement(refresh: true);
              },
              child: const Text('CHECK LINES'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('ADD ANYWAY'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _checkBackendStatus() async {
    final online = await _apiService.checkBackendHealth();
    if (!mounted) {
      return;
    }
    setState(() {
      _backendOnline = online;
    });
  }

  Widget _buildBuilderLoadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text(
            'Searching available props...',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 5),
          Text(
            'Comparing edge, confidence, correlation, and market filters.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _loadWatchlistIds() async {
    setState(() {
      _isLoadingWatchlist = true;
    });
    try {
      final props = await _watchlistService.loadWatchlist(
        includeCloudSync: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _watchlistedPropIds
          ..clear()
          ..addAll(
            props
                .map((prop) => prop['prop_id']?.toString() ?? '')
                .where((id) => id.isNotEmpty),
          );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWatchlist = false;
        });
      }
    }
  }

  Future<void> _generate() async {
    final validationError = _validateBuilderSettings();
    if (validationError != null) {
      setState(() {
        _hasAttemptedBuild = true;
        _error = validationError;
      });
      return;
    }
    if (_backendOnline == false) {
      setState(() {
        _hasAttemptedBuild = true;
        _error = 'Backend is offline. Start the API server before building.';
      });
      return;
    }

    _generatedLegCardKeys.clear();
    setState(() {
      _hasAttemptedBuild = true;
      _isLoading = true;
      _error = null;
      _requestedLegs = _legCount;
      _generatedLegCount = 0;
      _averageEdge = 0;
      _averageConfidence = 0;
      _responseBuildMode = '';
      _responseSites = [];
      _responseSports = [];
      _correlationWarnings = [];
      _expandedExplanationPropId = null;
      _lockedGeneratedPropIds.clear();
      _lastCriticalToastAt = null;
      _lastCriticalToastSignature = null;
      _availableCandidateCount = 0;
      _filteredOutCount = 0;
      _buildMessages = [];
    });

    try {
      final response = await _apiService.buildPropSlip(
        sports: _selectedSports.toList(),
        propSites: _selectedSites.toList(),
        markets: _selectedMarkets.toList(),
        riskMode: _riskMode,
        correlationGuardEnabled: _correlationGuardEnabled,
        maximumLegsPerGame: _maximumLegsPerGame,
        maximumLegsPerTeam: _maximumLegsPerTeam,
        maximumLegsPerPlayer: _maximumLegsPerPlayer,
        lockedLegs: const [],
        excludedPropIds: const [],
        legCount: _legCount,
        minimumEdge: _minimumEdge.round(),
        minimumConfidence: _minimumConfidence.round(),
        sameGameAllowed: _sameGameAllowed,
        buildMode: _buildMode,
        sidePreference: _sidePreference,
      );

      final rawLegs = response['legs'] as List<dynamic>? ?? [];

      if (!mounted) {
        return;
      }

      setState(() {
        _generatedLegs = _deduplicateLegs(
          rawLegs
              .whereType<Map<String, dynamic>>()
              .map((leg) => Map<String, dynamic>.from(leg))
              .toList(),
        );
        for (var index = 0; index < _generatedLegs.length; index++) {
          _generatedLegs[index]['builder_position'] = index;
        }
        _requestedLegs =
            (response['requested_legs'] as num?)?.toInt() ?? _legCount;
        _generatedLegCount =
            (response['generated_legs'] as num?)?.toInt() ??
            _generatedLegs.length;
        _averageEdge = (response['average_edge'] as num?)?.toDouble() ?? 0;
        _averageConfidence =
            (response['average_confidence'] as num?)?.toDouble() ?? 0;
        _responseBuildMode = response['build_mode']?.toString() ?? _buildMode;
        _responseSites = (response['prop_sites'] as List<dynamic>? ?? [])
            .map((site) => site.toString())
            .toList();
        _responseSports = (response['sports'] as List<dynamic>? ?? [])
            .map((sport) => sport.toString())
            .toList();
        _correlationWarnings =
            (response['correlation_warnings'] as List<dynamic>? ?? [])
                .map((warning) => warning.toString())
                .toList();
        _availableCandidateCount =
            (response['available_candidate_count'] as num?)?.toInt() ?? 0;
        _filteredOutCount =
            (response['filtered_out_count'] as num?)?.toInt() ?? 0;
        _buildMessages = (response['build_messages'] as List<dynamic>? ?? [])
            .map((message) => message.toString())
            .toList();
        _selectedGeneratedPropIds
          ..clear()
          ..addAll(
            _generatedLegs
                .map((leg) => leg['prop_id']?.toString() ?? '')
                .where((id) => id.isNotEmpty),
          );
        _lockedGeneratedPropIds.clear();
      });

      await _loadBuildHistory();
      await _loadBuilderStrategy();
      await _checkBackendStatus();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _friendlyBuilderError(error);
        _backendOnline = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _propId(Map<String, dynamic> leg) {
    return leg['prop_id']?.toString() ?? '';
  }

  bool _isGeneratedLegSelected(Map<String, dynamic> leg) {
    final propId = _propId(leg);
    return propId.isNotEmpty && _selectedGeneratedPropIds.contains(propId);
  }

  bool _isExplanationExpanded(Map<String, dynamic> leg) {
    return _expandedExplanationPropId == _propId(leg);
  }

  bool _isGeneratedLegLocked(Map<String, dynamic> leg) {
    final propId = _propId(leg);
    return propId.isNotEmpty && _lockedGeneratedPropIds.contains(propId);
  }

  bool _isInActiveSlip(Map<String, dynamic> leg) {
    return widget.activeSlipController.containsProp(_propId(leg));
  }

  bool _isPropWatchlisted(Map<String, dynamic> leg) {
    final propId = _propId(leg);
    return propId.isNotEmpty && _watchlistedPropIds.contains(propId);
  }

  String _generatedLegKey(Map<String, dynamic> leg, int index) {
    final propId = _propId(leg);
    if (propId.isNotEmpty) {
      return propId;
    }
    return 'generated-leg-$index';
  }

  GlobalKey _cardKeyForProp(String propId) {
    return _generatedLegCardKeys.putIfAbsent(propId, GlobalKey.new);
  }

  Future<void> _togglePropWatchlist(Map<String, dynamic> leg) async {
    final propId = _propId(leg);
    if (propId.isEmpty) {
      return;
    }
    final isWatchlisted = _watchlistedPropIds.contains(propId);
    setState(() {
      if (isWatchlisted) {
        _watchlistedPropIds.remove(propId);
      } else {
        _watchlistedPropIds.add(propId);
      }
    });

    try {
      if (isWatchlisted) {
        await _watchlistService.removeProp(propId);
      } else {
        final watchlistProp = Map<String, dynamic>.from(leg);
        watchlistProp['is_locked'] = _isGeneratedLegLocked(leg);
        watchlistProp['is_selected'] = _isGeneratedLegSelected(leg);
        await _watchlistService.addProp(watchlistProp);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (isWatchlisted) {
          _watchlistedPropIds.add(propId);
        } else {
          _watchlistedPropIds.remove(propId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update watchlist: $error')),
      );
    }
  }

  Future<void> _syncWatchlistedLeg(Map<String, dynamic> leg) async {
    if (!_isPropWatchlisted(leg)) {
      return;
    }
    final updatedLeg = Map<String, dynamic>.from(leg)
      ..['is_locked'] = _isGeneratedLegLocked(leg)
      ..['is_selected'] = _isGeneratedLegSelected(leg);
    await _watchlistService.addProp(updatedLeg);
  }

  Future<void> _syncWatchlistedLegsFromList(
    List<Map<String, dynamic>> legs,
  ) async {
    final watchedLegs = legs.where(_isPropWatchlisted).toList();
    if (watchedLegs.isEmpty) {
      return;
    }
    for (final leg in watchedLegs) {
      await _syncWatchlistedLeg(leg);
    }
  }

  List<Map<String, dynamic>> _deduplicateLegs(List<Map<String, dynamic>> legs) {
    final deduped = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final leg in legs) {
      final propId = _propId(leg);
      if (propId.isNotEmpty) {
        if (seen.contains(propId)) {
          continue;
        }
        seen.add(propId);
      }
      deduped.add(leg);
    }
    return deduped;
  }

  void _reorderGeneratedLegs(int oldIndex, int newIndex) {
    setState(() {
      final movedLeg = _generatedLegs.removeAt(oldIndex);
      _generatedLegs.insert(newIndex, movedLeg);
      for (var index = 0; index < _generatedLegs.length; index++) {
        _generatedLegs[index]['builder_position'] = index;
      }
    });
  }

  void _resetGeneratedLegOrder() {
    setState(() {
      _generatedLegs.sort((first, second) {
        final firstEdge = (first['edge'] as num?)?.toDouble() ?? 0;
        final secondEdge = (second['edge'] as num?)?.toDouble() ?? 0;
        final firstConfidence = (first['confidence'] as num?)?.toDouble() ?? 0;
        final secondConfidence =
            (second['confidence'] as num?)?.toDouble() ?? 0;
        final confidenceCompare = secondConfidence.compareTo(firstConfidence);
        if (confidenceCompare != 0) {
          return confidenceCompare;
        }
        return secondEdge.compareTo(firstEdge);
      });
      for (var index = 0; index < _generatedLegs.length; index++) {
        _generatedLegs[index]['builder_position'] = index;
      }
    });
  }

  Widget _buildGeneratedLegCard({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final isSelected = _isGeneratedLegSelected(leg);
    final isLocked = _isGeneratedLegLocked(leg);
    final isWatchlisted = _isPropWatchlisted(leg);
    final isInActiveSlip = _isInActiveSlip(leg);
    final propId = _propId(leg);
    final side = leg['side']?.toString() ?? '';
    final displayedLine =
        leg['current_line']?.toString() ?? leg['line']?.toString() ?? '';
    final builtLine =
        leg['original_line']?.toString() ?? leg['line']?.toString() ?? '';
    final market = leg['market']?.toString() ?? '';
    final propSite = leg['prop_site']?.toString() ?? '';
    final edge = leg['edge']?.toString() ?? '';
    final confidence = leg['confidence']?.toString() ?? '';
    final matchup = leg['matchup']?.toString() ?? '';
    final customLabel = leg['custom_label']?.toString() ?? '';
    final manualNote = leg['manual_note']?.toString() ?? '';
    final resultStatus = leg['result_status']?.toString() ?? 'pending';
    final resultValue = (leg['result_value'] as num?)?.toDouble();
    final movementStatus =
        leg['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    final originalLine = (leg['original_line'] as num?)?.toDouble();
    final currentLine = (leg['current_line'] as num?)?.toDouble();
    final originalOdds = (leg['original_odds'] as num?)?.toInt();
    final currentOdds = (leg['current_odds'] as num?)?.toInt();

    return KeyedSubtree(
      key: ValueKey(_generatedLegKey(leg, index)),
      child: Card(
        key: _cardKeyForProp(propId),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12, top: 4),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                leg['player']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (isLocked) const Icon(Icons.lock, size: 18),
                          ],
                        ),
                        if (customLabel.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Chip(
                            avatar: const Icon(Icons.label, size: 16),
                            label: Text(customLabel),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text('Current: $side $displayedLine $market'),
                        if (builtLine != displayedLine) ...[
                          const SizedBox(height: 3),
                          Text('Built at: $side $builtLine'),
                        ],
                        if (originalLine != null &&
                            currentLine != null &&
                            originalLine != currentLine) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Line moved: ${originalLine.toStringAsFixed(1)} → ${currentLine.toStringAsFixed(1)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                        if (originalOdds != null &&
                            currentOdds != null &&
                            originalOdds != currentOdds) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Odds moved: ${_formatAmericanOdds(originalOdds)} → ${_formatAmericanOdds(currentOdds)}',
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text(
                          '$propSite • Edge $edge% • Confidence $confidence%',
                        ),
                        const SizedBox(height: 5),
                        Text(
                          matchup,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (resultValue != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Final: ${resultValue.toStringAsFixed(1)} • ${resultStatus.toUpperCase()}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: resultStatus == 'won'
                                  ? Colors.greenAccent
                                  : resultStatus == 'lost'
                                  ? Colors.redAccent
                                  : null,
                            ),
                          ),
                        ],
                        if (manualNote.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.sticky_note_2_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(manualNote)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            Chip(label: Text('Edge $edge%')),
                            Chip(label: Text('Confidence $confidence%')),
                            if (leg['last_line_check'] != null)
                              Chip(
                                avatar: Icon(
                                  _movementIcon(movementStatus),
                                  size: 17,
                                ),
                                label: Text(_movementLabel(leg)),
                              ),
                            if (leg['historical_hit_rate'] != null)
                              Chip(
                                label: Text(
                                  'History ${(leg['historical_hit_rate'] as num).toStringAsFixed(1)}%',
                                ),
                              ),
                            if (isInActiveSlip)
                              const Chip(
                                avatar: Icon(Icons.check_circle, size: 16),
                                label: Text('Active Slip'),
                              ),
                          ],
                        ),
                        if (movementStatus != 'UNCHANGED') ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: movementStatus == 'BETTER'
                                    ? Colors.greenAccent
                                    : movementStatus == 'WORSE'
                                    ? Colors.redAccent
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(_movementIcon(movementStatus)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _movementLabel(leg),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          _toggleGeneratedLeg(leg);
                        },
                        icon: Icon(
                          isSelected
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                        ),
                        label: Text(isSelected ? 'REMOVE' : 'ADD'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          _toggleGeneratedLegLock(leg);
                        },
                        icon: Icon(isLocked ? Icons.lock : Icons.lock_open),
                        label: Text(isLocked ? 'LOCKED' : 'LOCK PICK'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _isLoadingWatchlist
                            ? null
                            : () {
                                _togglePropWatchlist(leg);
                              },
                        icon: Icon(
                          isWatchlisted
                              ? Icons.visibility
                              : Icons.visibility_outlined,
                        ),
                        label: Text(isWatchlisted ? 'WATCHING' : 'WATCHLIST'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: isLocked || _replacingPropId == propId
                            ? null
                            : () {
                                _replaceGeneratedLeg(leg);
                              },
                        icon: _replacingPropId == propId
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          isLocked
                              ? 'LOCKED'
                              : _replacingPropId == propId
                              ? 'REPLACING'
                              : 'REPLACE',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _editingNotePropId == propId
                            ? null
                            : () {
                                _editGeneratedLegNote(leg);
                              },
                        icon: const Icon(Icons.edit_note),
                        label: const Text('ADD NOTE'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          _showQuickLabelMenu(leg);
                        },
                        icon: const Icon(Icons.label_outline),
                        label: const Text('LABEL'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          _toggleExplanation(leg);
                        },
                        icon: Icon(
                          _isExplanationExpanded(leg)
                              ? Icons.expand_less
                              : Icons.info_outline,
                        ),
                        label: Text(
                          _isExplanationExpanded(leg)
                              ? 'HIDE DETAILS'
                              : 'WHY THIS PICK?',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_isExplanationExpanded(leg)) _pickExplanationPanel(leg),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editGeneratedLegNote(Map<String, dynamic> leg) async {
    final propId = _propId(leg);
    if (propId.isEmpty) {
      return;
    }
    final labelController = TextEditingController(
      text: leg['custom_label']?.toString() ?? '',
    );
    final noteController = TextEditingController(
      text: leg['manual_note']?.toString() ?? '',
    );
    setState(() {
      _editingNotePropId = propId;
    });
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Pick Details'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'Custom label',
                    hintText: 'Best Bet',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Manual note',
                    hintText: 'Watch injury news before locking this pick.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop({'custom_label': '', 'manual_note': ''});
              },
              child: const Text('CLEAR'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop({
                  'custom_label': labelController.text.trim(),
                  'manual_note': noteController.text.trim(),
                });
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
    labelController.dispose();
    noteController.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _editingNotePropId = null;
      if (result == null) {
        return;
      }
      leg['custom_label'] = result['custom_label'] ?? '';
      leg['manual_note'] = result['manual_note'] ?? '';
    });
    if (result != null) {
      await _syncWatchlistedLeg(leg);
    }
  }

  Future<void> _showQuickLabelMenu(Map<String, dynamic> leg) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Choose a Label',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ..._quickLabels.map(
                (label) => ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(label),
                  onTap: () {
                    Navigator.of(sheetContext).pop(label);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Remove Label'),
                onTap: () {
                  Navigator.of(sheetContext).pop('');
                },
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      leg['custom_label'] = selected;
    });
    await _syncWatchlistedLeg(leg);
  }

  void _toggleGeneratedLegLock(Map<String, dynamic> leg) {
    final propId = _propId(leg);
    if (propId.isEmpty) {
      return;
    }
    setState(() {
      if (_lockedGeneratedPropIds.contains(propId)) {
        _lockedGeneratedPropIds.remove(propId);
      } else {
        _lockedGeneratedPropIds.add(propId);
        _selectedGeneratedPropIds.add(propId);
      }
    });
    unawaited(_syncWatchlistedLeg(leg));
  }

  List<Map<String, dynamic>> _lockedGeneratedLegs() {
    return _generatedLegs.where(_isGeneratedLegLocked).toList();
  }

  void _toggleExplanation(Map<String, dynamic> leg) {
    final propId = _propId(leg);
    setState(() {
      if (_expandedExplanationPropId == propId) {
        _expandedExplanationPropId = null;
      } else {
        _expandedExplanationPropId = propId;
      }
    });
  }

  Future<void> _regenerateUnlockedLegs() async {
    if (_generatedLegs.isEmpty) {
      await _generate();
      return;
    }
    final lockedLegs = _lockedGeneratedLegs();
    if (lockedLegs.length >= _legCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unlock at least one pick before regenerating.'),
        ),
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _correlationWarnings = [];
    });
    try {
      final notesByPosition = <int, Map<String, String>>{};
      for (var index = 0; index < _generatedLegs.length; index++) {
        final leg = _generatedLegs[index];
        if (_isGeneratedLegLocked(leg)) {
          continue;
        }
        notesByPosition[index] = {
          'custom_label': leg['custom_label']?.toString() ?? '',
          'manual_note': leg['manual_note']?.toString() ?? '',
        };
      }
      final positionedLockedLegs = <Map<String, dynamic>>[];
      for (var index = 0; index < _generatedLegs.length; index++) {
        final leg = _generatedLegs[index];
        if (!_isGeneratedLegLocked(leg)) {
          continue;
        }
        final positionedLeg = Map<String, dynamic>.from(leg);
        positionedLeg['builder_position'] = index;
        positionedLockedLegs.add(positionedLeg);
      }
      final response = await _apiService.buildPropSlip(
        sports: _selectedSports.toList(),
        propSites: _selectedSites.toList(),
        markets: _selectedMarkets.toList(),
        legCount: _legCount,
        minimumEdge: _minimumEdge.round(),
        minimumConfidence: _minimumConfidence.round(),
        sameGameAllowed: _sameGameAllowed,
        buildMode: _buildMode,
        riskMode: _riskMode,
        sidePreference: _sidePreference,
        correlationGuardEnabled: _correlationGuardEnabled,
        maximumLegsPerGame: _maximumLegsPerGame,
        maximumLegsPerTeam: _maximumLegsPerTeam,
        maximumLegsPerPlayer: _maximumLegsPerPlayer,
        lockedLegs: positionedLockedLegs,
        excludedPropIds: _generatedLegs
            .where((leg) => !_isGeneratedLegLocked(leg))
            .map(_propId)
            .where((id) => id.isNotEmpty)
            .toList(),
      );
      final rawLegs = response['legs'] as List<dynamic>? ?? [];
      final newLegs = rawLegs
          .whereType<Map<String, dynamic>>()
          .map((leg) => Map<String, dynamic>.from(leg))
          .toList();
      for (var index = 0; index < newLegs.length; index++) {
        final saved = notesByPosition[index];
        if (saved == null) {
          continue;
        }
        newLegs[index]['custom_label'] = saved['custom_label'] ?? '';
        newLegs[index]['manual_note'] = saved['manual_note'] ?? '';
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _generatedLegs = _deduplicateLegs(newLegs);
        for (var index = 0; index < _generatedLegs.length; index++) {
          _generatedLegs[index]['builder_position'] = index;
        }
        _requestedLegs =
            (response['requested_legs'] as num?)?.toInt() ?? _legCount;
        _generatedLegCount =
            (response['generated_legs'] as num?)?.toInt() ?? newLegs.length;
        _averageEdge = (response['average_edge'] as num?)?.toDouble() ?? 0;
        _averageConfidence =
            (response['average_confidence'] as num?)?.toDouble() ?? 0;
        _correlationWarnings =
            (response['correlation_warnings'] as List<dynamic>? ?? [])
                .map((warning) => warning.toString())
                .toList();
        _availableCandidateCount =
            (response['available_candidate_count'] as num?)?.toInt() ?? 0;
        _filteredOutCount =
            (response['filtered_out_count'] as num?)?.toInt() ?? 0;
        _buildMessages = (response['build_messages'] as List<dynamic>? ?? [])
            .map((message) => message.toString())
            .toList();
        final validIds = _generatedLegs
            .map(_propId)
            .where((id) => id.isNotEmpty)
            .toSet();
        _lockedGeneratedPropIds.removeWhere((id) => !validIds.contains(id));
        _selectedGeneratedPropIds
          ..clear()
          ..addAll(validIds);
        _expandedExplanationPropId = null;
      });
      await _loadBuildHistory();
      await _checkBackendStatus();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
        _backendOnline = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleGeneratedLeg(Map<String, dynamic> leg) {
    final propId = _propId(leg);
    if (propId.isEmpty) {
      return;
    }
    setState(() {
      if (_selectedGeneratedPropIds.contains(propId)) {
        _selectedGeneratedPropIds.remove(propId);
      } else {
        _selectedGeneratedPropIds.add(propId);
      }
    });
  }

  List<Map<String, dynamic>> _selectedGeneratedLegs() {
    return _generatedLegs.where((leg) {
      return _isGeneratedLegSelected(leg);
    }).toList();
  }

  List<Map<String, dynamic>> _legsForExport() {
    final selected = _generatedLegs.where(_isGeneratedLegSelected).toList();
    if (selected.isNotEmpty) {
      return selected;
    }
    return List<Map<String, dynamic>>.from(_generatedLegs);
  }

  String _buildSlipExportText() {
    final legs = _legsForExport();
    if (legs.isEmpty) {
      return 'PROP INTELLIGENCE\nNo picks selected.';
    }
    final buffer = StringBuffer();
    buffer.writeln('PROP INTELLIGENCE');
    buffer.writeln('PROP BUILDER SLIP');
    buffer.writeln();
    buffer.writeln('Risk Mode: $_riskMode');
    buffer.writeln('Build Mode: ${_buildMode.replaceAll('_', ' ')}');
    buffer.writeln('Minimum Edge: ${_minimumEdge.round()}%');
    buffer.writeln('Minimum Confidence: ${_minimumConfidence.round()}%');
    buffer.writeln();
    buffer.writeln('${legs.length} PICKS');
    buffer.writeln('--------------------------------');
    for (var index = 0; index < legs.length; index++) {
      final leg = legs[index];
      final player = leg['player']?.toString() ?? 'Unknown Player';
      final side = leg['side']?.toString() ?? '';
      final line = leg['line']?.toString() ?? '';
      final market = leg['market']?.toString() ?? '';
      final site = leg['prop_site']?.toString() ?? '';
      final matchup = leg['matchup']?.toString() ?? '';
      final edge = (leg['edge'] as num?)?.toDouble() ?? 0;
      final confidence = (leg['confidence'] as num?)?.toDouble() ?? 0;
      final label = leg['custom_label']?.toString() ?? '';
      final note = leg['manual_note']?.toString() ?? '';
      buffer.writeln();
      buffer.writeln('${index + 1}. $player');
      buffer.writeln('   $side $line $market');
      if (matchup.isNotEmpty) {
        buffer.writeln('   $matchup');
      }
      if (site.isNotEmpty) {
        buffer.writeln('   Site: $site');
      }
      buffer.writeln(
        '   Edge: ${edge.toStringAsFixed(1)}% | Confidence: ${confidence.toStringAsFixed(1)}%',
      );
      if (label.isNotEmpty) {
        buffer.writeln('   Label: $label');
      }
      if (note.isNotEmpty) {
        buffer.writeln('   Note: $note');
      }
    }
    buffer.writeln();
    buffer.writeln('Generated by PROP INTELLIGENCE');
    return buffer.toString();
  }

  Future<void> _copySlipAsText() async {
    final legs = _legsForExport();
    if (legs.isEmpty) {
      _showExportMessage('Build a slip before copying.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: _buildSlipExportText()));
    if (!mounted) {
      return;
    }
    _showExportMessage('Slip copied to the clipboard.');
  }

  void _showExportMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic> _lineSnapshot(Map<String, dynamic> leg) {
    return {
      'movement_status':
          leg['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED',
      'current_line': (leg['current_line'] as num?)?.toDouble(),
      'current_odds': (leg['current_odds'] as num?)?.toInt(),
      'last_line_check': leg['last_line_check']?.toString(),
    };
  }

  Map<String, Map<String, dynamic>> _currentLineSnapshots() {
    final snapshots = <String, Map<String, dynamic>>{};
    for (final leg in _generatedLegs) {
      final propId = _propId(leg);
      if (propId.isEmpty) {
        continue;
      }
      snapshots[propId] = _lineSnapshot(leg);
    }
    return snapshots;
  }

  bool _shouldAlertForLeg(Map<String, dynamic> leg) {
    final propId = _propId(leg);
    if (propId.isEmpty) {
      return false;
    }
    final hasExplicitAlertTargets =
        _lockedGeneratedPropIds.isNotEmpty ||
        _selectedGeneratedPropIds.isNotEmpty;
    if (!hasExplicitAlertTargets) {
      return true;
    }
    return _lockedGeneratedPropIds.contains(propId) ||
        _selectedGeneratedPropIds.contains(propId);
  }

  String _lineValueText(dynamic value) {
    if (value is num) {
      return value.toDouble().toStringAsFixed(1);
    }
    return value?.toString() ?? 'N/A';
  }

  String _movementAlertMessage({
    required Map<String, dynamic> leg,
    required String status,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown player';
    final side = leg['side']?.toString() ?? '';
    final market = leg['market']?.toString() ?? '';
    final originalLine = leg['original_line'];
    final currentLine = leg['current_line'];
    switch (status) {
      case 'WORSE':
        return '$player moved to a worse line: $side ${_lineValueText(originalLine)} → ${_lineValueText(currentLine)} $market.';
      case 'BETTER':
        return '$player improved to a better line: $side ${_lineValueText(originalLine)} → ${_lineValueText(currentLine)} $market.';
      case 'UNAVAILABLE':
        return '$player is no longer available for $market.';
      default:
        return '$player has a new line movement update for $market.';
    }
  }

  void _addLineMovementAlert({
    required Map<String, dynamic> leg,
    required String message,
    required String severity,
  }) {
    final propId = _propId(leg);
    if (propId.isEmpty) {
      return;
    }
    final status =
        leg['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    final currentLine = leg['current_line']?.toString() ?? '';
    final currentOdds = leg['current_odds']?.toString() ?? '';
    final alertId = '$propId-$status-$currentLine-$currentOdds';
    final alreadyExists = _lineMovementAlerts.any(
      (alert) => alert.id == alertId,
    );
    if (alreadyExists) {
      return;
    }

    _lineMovementAlerts.insert(
      0,
      LineMovementAlert(
        id: alertId,
        propId: propId,
        player: leg['player']?.toString() ?? 'Unknown player',
        message: message,
        severity: severity,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _processLineMovementAlerts({
    required Map<String, Map<String, dynamic>> previousSnapshots,
    required List<Map<String, dynamic>> updatedLegs,
  }) {
    var criticalAlertCount = 0;
    for (final leg in updatedLegs) {
      if (!_shouldAlertForLeg(leg)) {
        continue;
      }
      final propId = _propId(leg);
      final previous = previousSnapshots[propId];
      final previousStatus =
          previous?['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
      final currentStatus =
          leg['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
      final previousLine = previous?['current_line'];
      final currentLine = leg['current_line'];
      final previousOdds = previous?['current_odds'] as int?;
      final currentOdds = (leg['current_odds'] as num?)?.toInt();
      final statusChanged = currentStatus != previousStatus;
      final lineChanged = currentLine != previousLine;
      final oddsDifference = previousOdds != null && currentOdds != null
          ? (currentOdds - previousOdds).abs()
          : 0;

      if (currentStatus == 'WORSE' &&
          _alertOnWorseMovement &&
          (statusChanged || lineChanged)) {
        _addLineMovementAlert(
          leg: leg,
          message: _movementAlertMessage(leg: leg, status: currentStatus),
          severity: 'CRITICAL',
        );
        criticalAlertCount += 1;
        continue;
      }
      if (currentStatus == 'UNAVAILABLE' &&
          _alertOnUnavailable &&
          statusChanged) {
        _addLineMovementAlert(
          leg: leg,
          message: _movementAlertMessage(leg: leg, status: currentStatus),
          severity: 'CRITICAL',
        );
        criticalAlertCount += 1;
        continue;
      }
      if (currentStatus == 'BETTER' &&
          _alertOnBetterMovement &&
          (statusChanged || lineChanged)) {
        _addLineMovementAlert(
          leg: leg,
          message: _movementAlertMessage(leg: leg, status: currentStatus),
          severity: 'POSITIVE',
        );
        continue;
      }
      if (_alertOnOddsMovement && oddsDifference >= _significantOddsMovement) {
        final player = leg['player']?.toString() ?? 'Unknown player';
        _addLineMovementAlert(
          leg: leg,
          message: '$player odds changed by $oddsDifference points.',
          severity: currentStatus == 'WORSE' ? 'WARNING' : 'INFO',
        );
      }
    }

    if (criticalAlertCount > 0) {
      _showCriticalMovementBanner(criticalAlertCount);
    }
  }

  void _showCriticalMovementBanner(int count) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          leading: const Icon(Icons.warning_amber_rounded),
          content: Text(
            '$count selected or locked pick${count == 1 ? ' has' : 's have'} a critical line update.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                unawaited(_openMovementAlertsOverlay());
              },
              child: const Text('VIEW ALERTS'),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              },
              child: const Text('DISMISS'),
            ),
          ],
        ),
      );
  }

  Future<void> _showWindowsCriticalToast(
    List<LineMovementAlert> criticalAlerts,
  ) async {
    if (!Platform.isWindows || criticalAlerts.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final signatureParts = criticalAlerts.map((alert) => alert.id).toList()
      ..sort();
    final signature = signatureParts.join('|');
    if (_lastCriticalToastAt != null &&
        _lastCriticalToastSignature == signature &&
        now.difference(_lastCriticalToastAt!) < _criticalToastCooldown) {
      return;
    }

    final topAlert = criticalAlerts.first;
    final notification = LocalNotification(
      title: 'Critical Line Movement Alert',
      body: criticalAlerts.length == 1
          ? topAlert.message
          : '${criticalAlerts.length} critical updates. ${topAlert.player} impacted.',
    );

    await notification.show();
    _lastCriticalToastAt = now;
    _lastCriticalToastSignature = signature;
  }

  int get _unreadMovementAlertCount {
    return _lineMovementAlerts.where((alert) => !alert.wasRead).length;
  }

  void _markAllMovementAlertsRead() {
    setState(() {
      for (var index = 0; index < _lineMovementAlerts.length; index++) {
        _lineMovementAlerts[index] = _lineMovementAlerts[index].copyWith(
          wasRead: true,
        );
      }
    });
  }

  void _clearMovementAlerts() {
    setState(() {
      _lineMovementAlerts.clear();
    });
  }

  Future<void> _openMovementAlertsOverlay() async {
    if (!mounted) {
      return;
    }
    _markAllMovementAlertsRead();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close alerts',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      pageBuilder: (dialogContext, _, _) {
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
              child: Material(
                color: Colors.transparent,
                child: _buildLineMovementAlertsPanel(
                  onClose: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, animation, _, child) {
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: eased,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(eased),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _scrollToGeneratedProp(String propId) async {
    final key = _generatedLegCardKeys[propId];
    final cardContext = key?.currentContext;
    if (cardContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      cardContext,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  Widget _buildMovementAlertRow(LineMovementAlert alert) {
    IconData icon;
    switch (alert.severity) {
      case 'CRITICAL':
        icon = Icons.error_outline;
        break;
      case 'WARNING':
        icon = Icons.warning_amber;
        break;
      case 'POSITIVE':
        icon = Icons.trending_up;
        break;
      default:
        icon = Icons.info_outline;
    }
    final time = TimeOfDay.fromDateTime(alert.createdAt).format(context);
    return InkWell(
      onTap: () {
        setState(() {
          final index = _lineMovementAlerts.indexOf(alert);
          if (index >= 0) {
            _lineMovementAlerts[index] = alert.copyWith(wasRead: true);
          }
        });
        _scrollToGeneratedProp(alert.propId);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.player,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!alert.wasRead) const Icon(Icons.circle, size: 9),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(alert.message),
                  const SizedBox(height: 5),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _buildLineMovementAlertsPanel({required VoidCallback onClose}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'LINE MOVEMENT ALERTS',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: _lineMovementAlerts.isEmpty
                    ? null
                    : _markAllMovementAlertsRead,
                child: const Text('MARK ALL READ'),
              ),
              TextButton(
                onPressed: _lineMovementAlerts.isEmpty
                    ? null
                    : _clearMovementAlerts,
                child: const Text('CLEAR'),
              ),
              IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _severityFilterChip('CRITICAL'),
              _severityFilterChip('WARNING'),
              _severityFilterChip('POSITIVE'),
              _severityFilterChip('INFO'),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Builder(
              builder: (_) {
                final filteredAlerts = _lineMovementAlerts
                    .where(
                      (alert) => _alertSeverityFilter.contains(alert.severity),
                    )
                    .toList();
                if (filteredAlerts.isEmpty) {
                  return const Center(
                    child: Text('No alerts match the active filters.'),
                  );
                }
                return ListView.builder(
                  itemCount: filteredAlerts.length,
                  itemBuilder: (context, index) {
                    return _buildMovementAlertRow(filteredAlerts[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _severityFilterChip(String severity) {
    final selected = _alertSeverityFilter.contains(severity);
    return FilterChip(
      selected: selected,
      onSelected: (value) {
        setState(() {
          if (value) {
            _alertSeverityFilter.add(severity);
          } else {
            _alertSeverityFilter.remove(severity);
          }
        });
      },
      label: Text(severity),
    );
  }

  Widget _buildLineAlertSettings() {
    return ExpansionTile(
      leading: const Icon(Icons.tune),
      title: const Text('Line Alert Settings'),
      children: [
        SwitchListTile(
          title: const Text('Alert on worse lines'),
          value: _alertOnWorseMovement,
          onChanged: (value) {
            setState(() {
              _alertOnWorseMovement = value;
            });
            _saveAlertSettings();
          },
        ),
        SwitchListTile(
          title: const Text('Alert when unavailable'),
          value: _alertOnUnavailable,
          onChanged: (value) {
            setState(() {
              _alertOnUnavailable = value;
            });
            _saveAlertSettings();
          },
        ),
        SwitchListTile(
          title: const Text('Alert on better lines'),
          value: _alertOnBetterMovement,
          onChanged: (value) {
            setState(() {
              _alertOnBetterMovement = value;
            });
            _saveAlertSettings();
          },
        ),
        SwitchListTile(
          title: const Text('Alert on major odds changes'),
          value: _alertOnOddsMovement,
          onChanged: (value) {
            setState(() {
              _alertOnOddsMovement = value;
            });
            _saveAlertSettings();
          },
        ),
        if (_alertOnOddsMovement) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Minimum odds change: $_significantOddsMovement'),
          ),
          Slider(
            value: _significantOddsMovement.toDouble(),
            min: 5,
            max: 50,
            divisions: 9,
            label: '$_significantOddsMovement',
            onChanged: (value) {
              setState(() {
                _significantOddsMovement = value.round();
              });
              _saveAlertSettings();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildExportSlipCard() {
    final legs = _legsForExport();
    return Container(
      width: 760,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF09111F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD6B35A), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sports_score, color: Color(0xFFD6B35A), size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROP INTELLIGENCE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    Text(
                      'PROP BUILDER SLIP',
                      style: TextStyle(
                        color: Color(0xFFD6B35A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _exportHeaderChip('Risk: $_riskMode'),
              _exportHeaderChip('${legs.length} Picks'),
              _exportHeaderChip('Edge ${_averageEdge.toStringAsFixed(1)}%'),
              _exportHeaderChip(
                'Confidence ${_averageConfidence.toStringAsFixed(1)}%',
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(legs.length, (index) {
            return _buildExportLegRow(leg: legs[index], index: index);
          }),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 10),
          const Text(
            'Generated by PROP INTELLIGENCE',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _checkLineMovement({
    bool refresh = true,
    bool showMessage = true,
  }) async {
    if (_generatedLegs.isEmpty || _isCheckingLines) {
      return;
    }
    final previousSnapshots = _currentLineSnapshots();
    setState(() {
      _isCheckingLines = true;
    });
    try {
      final response = await _apiService.checkPropLineMovement(
        legs: _generatedLegs,
        refresh: refresh,
      );
      final rawLegs = response['legs'] as List<dynamic>? ?? [];
      final updatedLegs = rawLegs
          .whereType<Map<String, dynamic>>()
          .map((leg) => Map<String, dynamic>.from(leg))
          .toList();
      final changedCount = (response['changed_count'] as num?)?.toInt() ?? 0;

      final criticalBefore = _lineMovementAlerts.length;
      _processLineMovementAlerts(
        previousSnapshots: previousSnapshots,
        updatedLegs: updatedLegs,
      );
      final criticalAlerts = _lineMovementAlerts
          .take(
            criticalBefore == _lineMovementAlerts.length
                ? 0
                : _lineMovementAlerts.length - criticalBefore,
          )
          .where((alert) => alert.severity == 'CRITICAL')
          .toList();
      _showWindowsCriticalToast(criticalAlerts);

      if (!mounted) {
        return;
      }
      setState(() {
        _generatedLegs = updatedLegs;
        _lastLineMovementCheck = DateTime.now();
      });

      await widget.activeSlipController.updateMatchingLegs(updatedLegs);

      await _syncWatchlistedLegsFromList(updatedLegs);

      if (showMessage) {
        _showExportMessage(
          changedCount == 0
              ? 'No line changes detected.'
              : '$changedCount line change${changedCount == 1 ? '' : 's'} detected.',
        );
      }
    } catch (error) {
      if (showMessage) {
        _showExportMessage('Line check failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingLines = false;
        });
      }
    }
  }

  void _setAutoLineCheck(bool enabled) {
    _lineMovementTimer?.cancel();
    setState(() {
      _autoCheckLines = enabled;
    });
    if (!enabled) {
      return;
    }
    _lineMovementTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      if (mounted && _generatedLegs.isNotEmpty && !_isCheckingLines) {
        _checkLineMovement(refresh: true, showMessage: false);
      }
    });
  }

  String _movementLabel(Map<String, dynamic> leg) {
    final status =
        leg['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    switch (status) {
      case 'BETTER':
        return 'BETTER LINE';
      case 'WORSE':
        return 'WORSE LINE';
      case 'MOVED':
        return 'LINE MOVED';
      case 'UNAVAILABLE':
        return 'LINE UNAVAILABLE';
      default:
        return 'NO CHANGE';
    }
  }

  IconData _movementIcon(String status) {
    switch (status.toUpperCase()) {
      case 'BETTER':
        return Icons.trending_up;
      case 'WORSE':
        return Icons.trending_down;
      case 'MOVED':
        return Icons.swap_vert;
      case 'UNAVAILABLE':
        return Icons.remove_circle_outline;
      default:
        return Icons.horizontal_rule;
    }
  }

  String _formatAmericanOdds(int odds) {
    return odds > 0 ? '+$odds' : '$odds';
  }

  Widget _exportHeaderChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildExportLegRow({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final side = leg['side']?.toString() ?? '';
    final line = leg['line']?.toString() ?? '';
    final market = leg['market']?.toString() ?? '';
    final matchup = leg['matchup']?.toString() ?? '';
    final site = leg['prop_site']?.toString() ?? '';
    final label = leg['custom_label']?.toString() ?? '';
    final note = leg['manual_note']?.toString() ?? '';
    final edge = (leg['edge'] as num?)?.toDouble() ?? 0;
    final confidence = (leg['confidence'] as num?)?.toDouble() ?? 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111A2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF29364C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFD6B35A),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFF09111F),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        player,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (label.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6B35A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF09111F),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '$side $line $market',
                  style: const TextStyle(
                    color: Color(0xFFD6B35A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (matchup.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    matchup,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Text(
                  '$site  •  Edge ${edge.toStringAsFixed(1)}%  •  Confidence ${confidence.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Note: $note',
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _captureSlipImage() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      throw Exception('Export card is not ready.');
    }
    final boundary =
        _exportCardKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('Export card is not ready.');
    }
    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw Exception('Unable to create PNG data.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _saveSlipAsImage() async {
    if (_legsForExport().isEmpty) {
      _showExportMessage('Build a slip before exporting.');
      return;
    }
    setState(() {
      _isExportingSlip = true;
    });
    try {
      final bytes = await _captureSlipImage();
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save PROP INTELLIGENCE Slip',
        fileName: 'prop_intelligence_slip.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      if (path == null) {
        return;
      }
      final finalPath = path.toLowerCase().endsWith('.png')
          ? path
          : '$path.png';
      await File(finalPath).writeAsBytes(bytes, flush: true);
      _showExportMessage('Slip image saved.');
    } catch (error) {
      _showExportMessage('Unable to save image: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isExportingSlip = false;
        });
      }
    }
  }

  Future<Uint8List> _buildSlipPdf() async {
    final legs = _legsForExport();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Text(
              'PROP INTELLIGENCE',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Prop Builder Slip',
              style: const pw.TextStyle(fontSize: 13),
            ),
            pw.SizedBox(height: 16),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pdfBadge('Risk: $_riskMode'),
                _pdfBadge('${legs.length} Picks'),
                _pdfBadge('Average Edge: ${_averageEdge.toStringAsFixed(1)}%'),
                _pdfBadge(
                  'Average Confidence: ${_averageConfidence.toStringAsFixed(1)}%',
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            ...List.generate(
              legs.length,
              (index) => _buildPdfLeg(legs[index], index),
            ),
            pw.SizedBox(height: 18),
            pw.Divider(),
            pw.Text(
              'Generated by PROP INTELLIGENCE',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ];
        },
      ),
    );
    return document.save();
  }

  pw.Widget _pdfBadge(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
  }

  pw.Widget _buildPdfLeg(Map<String, dynamic> leg, int index) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final side = leg['side']?.toString() ?? '';
    final line = leg['line']?.toString() ?? '';
    final market = leg['market']?.toString() ?? '';
    final site = leg['prop_site']?.toString() ?? '';
    final matchup = leg['matchup']?.toString() ?? '';
    final label = leg['custom_label']?.toString() ?? '';
    final note = leg['manual_note']?.toString() ?? '';
    final edge = (leg['edge'] as num?)?.toDouble() ?? 0;
    final confidence = (leg['confidence'] as num?)?.toDouble() ?? 0;
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                '${index + 1}. ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Expanded(
                child: pw.Text(
                  player,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (label.isNotEmpty)
                pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('$side $line $market'),
          if (matchup.isNotEmpty)
            pw.Text(
              matchup,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 5),
          pw.Text(
            '$site | Edge ${edge.toStringAsFixed(1)}% | Confidence ${confidence.toStringAsFixed(1)}%',
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (note.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Note: $note',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveSlipAsPdf() async {
    if (_legsForExport().isEmpty) {
      _showExportMessage('Build a slip before exporting.');
      return;
    }
    setState(() {
      _isExportingSlip = true;
    });
    try {
      final bytes = await _buildSlipPdf();
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save PROP INTELLIGENCE PDF',
        fileName: 'prop_intelligence_slip.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (path == null) {
        return;
      }
      final finalPath = path.toLowerCase().endsWith('.pdf')
          ? path
          : '$path.pdf';
      await File(finalPath).writeAsBytes(bytes, flush: true);
      _showExportMessage('Slip PDF saved.');
    } catch (error) {
      _showExportMessage('Unable to save PDF: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isExportingSlip = false;
        });
      }
    }
  }

  Future<void> _printSlip() async {
    if (_legsForExport().isEmpty) {
      _showExportMessage('Build a slip before printing.');
      return;
    }
    try {
      final bytes = await _buildSlipPdf();
      await Printing.layoutPdf(
        name: 'PROP INTELLIGENCE Slip',
        onLayout: (PdfPageFormat format) async {
          return bytes;
        },
      );
    } catch (error) {
      _showExportMessage('Unable to print slip: $error');
    }
  }

  Widget _buildExportMenu() {
    return PopupMenuButton<SlipExportAction>(
      enabled: !_isExportingSlip && _generatedLegs.isNotEmpty,
      tooltip: 'Export slip',
      onSelected: (action) {
        switch (action) {
          case SlipExportAction.copyText:
            _copySlipAsText();
            break;
          case SlipExportAction.saveImage:
            _saveSlipAsImage();
            break;
          case SlipExportAction.savePdf:
            _saveSlipAsPdf();
            break;
          case SlipExportAction.printSlip:
            _printSlip();
            break;
        }
      },
      itemBuilder: (context) {
        return const [
          PopupMenuItem(
            value: SlipExportAction.copyText,
            child: ListTile(
              leading: Icon(Icons.copy),
              title: Text('Copy as Text'),
            ),
          ),
          PopupMenuItem(
            value: SlipExportAction.saveImage,
            child: ListTile(
              leading: Icon(Icons.image_outlined),
              title: Text('Save as PNG'),
            ),
          ),
          PopupMenuItem(
            value: SlipExportAction.savePdf,
            child: ListTile(
              leading: Icon(Icons.picture_as_pdf_outlined),
              title: Text('Save as PDF'),
            ),
          ),
          PopupMenuItem(
            value: SlipExportAction.printSlip,
            child: ListTile(
              leading: Icon(Icons.print_outlined),
              title: Text('Print Slip'),
            ),
          ),
        ];
      },
      child: OutlinedButton.icon(
        onPressed: null,
        icon: _isExportingSlip
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share),
        label: const Text('EXPORT'),
      ),
    );
  }

  Future<void> _addSelectedToActiveSlip() async {
    final selectedLegs = _selectedGeneratedLegs();
    if (selectedLegs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one prop first.')),
      );
      return;
    }

    final unavailableCount = selectedLegs.where(_isUnavailable).length;
    if (unavailableCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$unavailableCount selected ${unavailableCount == 1 ? 'prop is' : 'props are'} unavailable. Replace or unselect before adding.',
          ),
        ),
      );
      return;
    }

    final staleCount = selectedLegs.where(_isLineStale).length;
    if (staleCount > 0) {
      final continueAdd = await _confirmStaleLines(staleCount);
      if (!continueAdd || !mounted) {
        return;
      }
    }

    final addedCount = await widget.activeSlipController.addLegs(
      _deduplicateLegs(
        selectedLegs.map((leg) => Map<String, dynamic>.from(leg)).toList(),
      ),
    );

    if (!mounted) {
      return;
    }

    final duplicateCount = selectedLegs.length - addedCount;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedCount == 0
              ? 'Those props are already in Active Slip.'
              : duplicateCount > 0
              ? '$addedCount added. $duplicateCount duplicate${duplicateCount == 1 ? '' : 's'} skipped.'
              : '$addedCount prop${addedCount == 1 ? '' : 's'} added to Active Slip.',
        ),
      ),
    );
  }

  Future<void> _addLegMapsToActiveSlip(List<Map<String, dynamic>> legs) async {
    await widget.activeSlipController.addLegs(
      legs.map((leg) => Map<String, dynamic>.from(leg)).toList(),
    );
  }

  Future<void> _loadPresets() async {
    setState(() {
      _isLoadingPresets = true;
    });
    try {
      final presets = await _apiService.fetchPropBuilderPresets();
      if (!mounted) {
        return;
      }
      setState(() {
        _presets = presets;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPresets = false;
        });
      }
    }
  }

  Future<void> _loadBuildHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });
    try {
      final history = await _apiService.fetchPropBuilderHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _buildHistory = history;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _loadBuilderStrategy() async {
    setState(() {
      _isLoadingStrategy = true;
    });
    try {
      final strategy = await _apiService.fetchPropBuilderStrategy();
      if (!mounted) {
        return;
      }
      setState(() {
        _builderStrategy = strategy;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStrategy = false;
        });
      }
    }
  }

  Map<String, dynamic>? _strategyItem(String key) {
    final item = _builderStrategy?[key];
    if (item is Map<String, dynamic>) {
      return item;
    }
    if (item is Map) {
      return Map<String, dynamic>.from(item);
    }
    return null;
  }

  String _strategyName(String key) {
    return _strategyItem(key)?['name']?.toString() ?? 'Not enough data';
  }

  double _strategyHitRate(String key) {
    return (_strategyItem(key)?['hit_rate'] as num?)?.toDouble() ?? 0;
  }

  int _strategySample(String key) {
    return (_strategyItem(key)?['sample_size'] as num?)?.toInt() ?? 0;
  }

  String _marketLabel(String value) {
    const labels = {
      'points': 'Points',
      'rebounds': 'Rebounds',
      'assists': 'Assists',
      'pra': 'PRA',
      'three_pointers_made': 'Three-Pointers Made',
      'steals': 'Steals',
      'blocks': 'Blocks',
      'turnovers': 'Turnovers',
      'strikeouts': 'Strikeouts',
      'hits': 'Hits',
      'home_runs': 'Home Runs',
      'total_bases': 'Total Bases',
      'rbi': 'RBIs',
      'passing_yards': 'Passing Yards',
      'rushing_yards': 'Rushing Yards',
      'receiving_yards': 'Receiving Yards',
      'receptions': 'Receptions',
      'shots_on_goal': 'Shots on Goal',
      'saves': 'Saves',
    };
    return labels[value] ?? value.replaceAll('_', ' ');
  }

  String _riskModeDescription() {
    switch (_riskMode) {
      case 'SAFE':
        return 'Higher confidence, fewer legs, and no same-game stacking.';
      case 'AGGRESSIVE':
        return 'More legs, lower thresholds, and same-game picks allowed.';
      default:
        return 'Balanced thresholds with moderate slip size.';
    }
  }

  void _applyRiskModeDefaults() {
    switch (_riskMode) {
      case 'SAFE':
        _minimumEdge = 70;
        _minimumConfidence = 75;
        _legCount = 3;
        _sameGameAllowed = false;
        _correlationGuardEnabled = true;
        _maximumLegsPerPlayer = 1;
        _maximumLegsPerGame = 1;
        _maximumLegsPerTeam = 1;
        break;
      case 'AGGRESSIVE':
        _minimumEdge = 50;
        _minimumConfidence = 55;
        _legCount = 6;
        _sameGameAllowed = true;
        _correlationGuardEnabled = true;
        _maximumLegsPerPlayer = 2;
        _maximumLegsPerGame = 3;
        _maximumLegsPerTeam = 4;
        break;
      default:
        _minimumEdge = 60;
        _minimumConfidence = 65;
        _legCount = 4;
        _sameGameAllowed = false;
        _correlationGuardEnabled = true;
        _maximumLegsPerPlayer = 1;
        _maximumLegsPerGame = 1;
        _maximumLegsPerTeam = 2;
    }
  }

  void _applyRecommendedStrategy() {
    final strategy = _builderStrategy;
    if (strategy == null) {
      return;
    }
    final sport = _strategyName('recommended_sport');
    final site = _strategyName('recommended_prop_site');
    final market = _strategyName('recommended_market');
    setState(() {
      if (sport != 'Not enough data') {
        _selectedSports
          ..clear()
          ..add(sport);
      }
      if (site != 'Not enough data') {
        _selectedSites
          ..clear()
          ..add(site);
      }
      if (market != 'Not enough data') {
        _selectedMarkets
          ..clear()
          ..add(market);
      }
      _minimumEdge =
          (strategy['recommended_minimum_edge'] as num?)?.toDouble() ?? 60;
      _minimumConfidence =
          (strategy['recommended_minimum_confidence'] as num?)?.toDouble() ??
          60;
      _legCount = (strategy['recommended_leg_count'] as num?)?.toInt() ?? 3;
      _buildMode = 'SAME_SPORT';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recommended strategy applied.')),
    );
  }

  void _openHistoryBuild(Map<String, dynamic> build) {
    final rawLegs = build['legs'] as List<dynamic>? ?? [];
    final sports = build['sports'] as List<dynamic>? ?? [];
    final sites = build['prop_sites'] as List<dynamic>? ?? [];
    setState(() {
      _hasAttemptedBuild = true;
      _generatedLegCardKeys.clear();
      _generatedLegs = _deduplicateLegs(
        rawLegs
            .whereType<Map<String, dynamic>>()
            .map((leg) => Map<String, dynamic>.from(leg))
            .toList(),
      );
      _generatedLegs.sort((first, second) {
        final firstPosition = (first['builder_position'] as num?)?.toInt() ?? 0;
        final secondPosition =
            (second['builder_position'] as num?)?.toInt() ?? 0;
        return firstPosition.compareTo(secondPosition);
      });
      for (var index = 0; index < _generatedLegs.length; index++) {
        _generatedLegs[index]['builder_position'] = index;
      }
      _selectedSports
        ..clear()
        ..addAll(sports.map((sport) => sport.toString()));
      _selectedSites
        ..clear()
        ..addAll(sites.map((site) => site.toString()));
      _requestedLegs =
          (build['requested_legs'] as num?)?.toInt() ?? _generatedLegs.length;
      _generatedLegCount =
          (build['generated_legs'] as num?)?.toInt() ?? _generatedLegs.length;
      _averageEdge = (build['average_edge'] as num?)?.toDouble() ?? 0;
      _averageConfidence =
          (build['average_confidence'] as num?)?.toDouble() ?? 0;
      _buildMode = build['build_mode']?.toString() ?? 'SAME_SPORT';
      _riskMode = build['risk_mode']?.toString() ?? 'BALANCED';
      _responseBuildMode = _buildMode;
      _selectedGeneratedPropIds
        ..clear()
        ..addAll(_generatedLegs.map(_propId).where((id) => id.isNotEmpty));
      _lockedGeneratedPropIds.clear();
      _lastCriticalToastAt = null;
      _lastCriticalToastSignature = null;
      _showBuildHistory = false;
      _availableCandidateCount =
          (build['available_candidate_count'] as num?)?.toInt() ?? 0;
      _filteredOutCount = (build['filtered_out_count'] as num?)?.toInt() ?? 0;
      _buildMessages = (build['build_messages'] as List<dynamic>? ?? [])
          .map((message) => message.toString())
          .toList();
    });
  }

  Future<void> _deleteHistoryItem(Map<String, dynamic> build) async {
    final historyId = (build['id'] as num?)?.toInt();
    if (historyId == null) {
      return;
    }
    try {
      await _apiService.deletePropBuilderHistoryItem(historyId);
      await _loadBuildHistory();
      await _loadBuilderStrategy();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    }
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear Build History?'),
          content: const Text(
            'This will permanently remove all saved Prop Builder history.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('CLEAR'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _apiService.clearPropBuilderHistory();
      await _loadBuildHistory();
      await _loadBuilderStrategy();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    }
  }

  Future<void> _gradeBuildHistory() async {
    setState(() {
      _isGradingHistory = true;
    });
    try {
      final gradeResponse = await _apiService.gradePropBuilderHistory();
      final rawGradedLegs =
          gradeResponse['graded_legs'] ?? gradeResponse['legs'] ?? [];
      final gradedLegs = rawGradedLegs is List<dynamic>
          ? rawGradedLegs
                .whereType<Map<String, dynamic>>()
                .map((leg) => Map<String, dynamic>.from(leg))
                .toList()
          : <Map<String, dynamic>>[];
      if (gradedLegs.isNotEmpty) {
        await widget.activeSlipController.updateMatchingLegs(gradedLegs);
      }
      await _loadBuildHistory();
      await _loadBuilderStrategy();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Build history graded and strategy refreshed.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGradingHistory = false;
        });
      }
    }
  }

  String _formatBuildDate(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) {
      return rawDate;
    }
    final local = parsed.toLocal();
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} $hour:$minute $period';
  }

  Widget _buildHistoryPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'BUILD HISTORY',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (_buildHistory.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isGradingHistory ? null : _gradeBuildHistory,
                      icon: _isGradingHistory
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_fix_high),
                      label: Text(_isGradingHistory ? 'GRADING' : 'GRADE'),
                    ),
                    TextButton(
                      onPressed: _clearAllHistory,
                      child: const Text('CLEAR ALL'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingHistory)
            const LinearProgressIndicator()
          else if (_buildHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('No previous builds yet.')),
            )
          else
            ..._buildHistory.map((build) {
              final sports = build['sports'] as List<dynamic>? ?? [];
              final sites = build['prop_sites'] as List<dynamic>? ?? [];
              final generated = (build['generated_legs'] as num?)?.toInt() ?? 0;
              final edge = (build['average_edge'] as num?)?.toDouble() ?? 0;
              final confidence =
                  (build['average_confidence'] as num?)?.toDouble() ?? 0;
              return Card(
                child: ListTile(
                  onTap: () {
                    _openHistoryBuild(build);
                  },
                  leading: const Icon(Icons.receipt_long),
                  title: Text(
                    '$generated-Leg ${build['risk_mode'] ?? 'BALANCED'} Build',
                  ),
                  subtitle: Text(
                    'Risk: ${build['risk_mode'] ?? 'BALANCED'}\n'
                    '${sports.join(', ')}\n'
                    '${sites.join(', ')}\n'
                    'Edge ${edge.toStringAsFixed(1)}% • '
                    'Confidence ${confidence.toStringAsFixed(1)}%\n'
                    '${_formatBuildDate(build['created_at']?.toString() ?? '')}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'open') {
                        _openHistoryBuild(build);
                      }
                      if (value == 'add') {
                        final rawLegs = build['legs'] as List<dynamic>? ?? [];
                        final legs = rawLegs
                            .whereType<Map<String, dynamic>>()
                            .map((leg) => Map<String, dynamic>.from(leg))
                            .toList();
                        unawaited(_addLegMapsToActiveSlip(legs));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${legs.length} previous props added to Active Slip.',
                            ),
                          ),
                        );
                      }
                      if (value == 'delete') {
                        _deleteHistoryItem(build);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'open', child: Text('Open build')),
                      PopupMenuItem(
                        value: 'add',
                        child: Text('Add to Active Slip'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _applyPreset(Map<String, dynamic> preset) {
    final sports = preset['sports'] as List<dynamic>? ?? [];
    final propSites = preset['prop_sites'] as List<dynamic>? ?? [];
    final markets = preset['markets'] as List<dynamic>? ?? [];
    setState(() {
      _selectedSports
        ..clear()
        ..addAll(sports.map((sport) => sport.toString()));
      _selectedSites
        ..clear()
        ..addAll(propSites.map((site) => site.toString()));
      _selectedMarkets
        ..clear()
        ..addAll(markets.map((market) => market.toString()));
      _legCount = (preset['leg_count'] as num?)?.toInt() ?? 3;
      _minimumEdge = (preset['minimum_edge'] as num?)?.toDouble() ?? 60;
      _minimumConfidence =
          (preset['minimum_confidence'] as num?)?.toDouble() ?? 60;
      _sameGameAllowed = preset['same_game_allowed'] == true;
      _buildMode = preset['build_mode']?.toString() ?? 'SAME_SPORT';
      _riskMode = preset['risk_mode']?.toString() ?? 'BALANCED';
      _sidePreference = preset['side_preference']?.toString() ?? 'ANY';
      _selectedPresetName = preset['name']?.toString();
    });
    _emitSelectedSportsChanged();
  }

  Future<void> _showSavePresetDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Save Builder Preset'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              hintText: 'WNBA Safe 3',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                final candidateName = controller.text.trim();
                if (candidateName.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(candidateName);
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (name == null || name.isEmpty) {
      return;
    }

    setState(() {
      _isSavingPreset = true;
      _error = null;
    });
    try {
      await _apiService.savePropBuilderPreset(
        name: name,
        sports: _selectedSports.toList(),
        propSites: _selectedSites.toList(),
        markets: _selectedMarkets.toList(),
        riskMode: _riskMode,
        legCount: _legCount,
        minimumEdge: _minimumEdge.round(),
        minimumConfidence: _minimumConfidence.round(),
        sameGameAllowed: _sameGameAllowed,
        buildMode: _buildMode,
        sidePreference: _sidePreference,
      );
      await _loadPresets();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedPresetName = name;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Preset "$name" saved.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPreset = false;
        });
      }
    }
  }

  Future<void> _deletePreset(Map<String, dynamic> preset) async {
    final presetId = (preset['id'] as num?)?.toInt();
    if (presetId == null) {
      return;
    }
    try {
      await _apiService.deletePropBuilderPreset(presetId);
      await _loadPresets();
      if (!mounted) {
        return;
      }
      if (_selectedPresetName == preset['name']?.toString()) {
        setState(() {
          _selectedPresetName = null;
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    }
  }

  String _qualityLabel() {
    if (_generatedLegs.isEmpty) {
      return 'NO QUALIFIED SLIP';
    }
    if (_averageConfidence >= 80 && _averageEdge >= 75) {
      return 'ELITE';
    }
    if (_averageConfidence >= 70 && _averageEdge >= 65) {
      return 'STRONG';
    }
    if (_averageConfidence >= 60 && _averageEdge >= 55) {
      return 'SOLID';
    }
    return 'LOW CONFIDENCE';
  }

  IconData _qualityIcon() {
    final label = _qualityLabel();
    switch (label) {
      case 'ELITE':
        return Icons.workspace_premium;
      case 'STRONG':
        return Icons.trending_up;
      case 'SOLID':
        return Icons.check_circle_outline;
      case 'LOW CONFIDENCE':
        return Icons.warning_amber_rounded;
      default:
        return Icons.search_off;
    }
  }

  Map<String, int> _siteBreakdown() {
    final counts = <String, int>{};
    for (final leg in _generatedLegs) {
      final site = leg['prop_site']?.toString() ?? 'Unknown';
      counts[site] = (counts[site] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _sportBreakdown() {
    final counts = <String, int>{};
    for (final leg in _generatedLegs) {
      final sport = leg['sport']?.toString() ?? 'Unknown';
      counts[sport] = (counts[sport] ?? 0) + 1;
    }
    return counts;
  }

  List<String> _builderWarnings() {
    final warnings = <String>[];
    if (_generatedLegs.isEmpty) {
      warnings.add('No props matched the selected filters.');
      return warnings;
    }
    if (_generatedLegCount < _requestedLegs) {
      warnings.add(
        'Only $_generatedLegCount of $_requestedLegs requested legs were found.',
      );
    }
    if (_averageConfidence < 60) {
      warnings.add('Average confidence is below 60%.');
    }
    if (_averageEdge < 55) {
      warnings.add('Average edge is below 55%.');
    }
    final siteBreakdown = _siteBreakdown();
    final selectedSiteCount = _responseSites.isNotEmpty
        ? _responseSites.length
        : _selectedSites.length;
    if (siteBreakdown.length == 1 && selectedSiteCount > 1) {
      warnings.add('All generated props came from one site.');
    }
    final sportBreakdown = _sportBreakdown();
    final effectiveBuildMode = _responseBuildMode.isNotEmpty
        ? _responseBuildMode
        : _buildMode;
    final selectedSportCount = _responseSports.isNotEmpty
        ? _responseSports.length
        : _selectedSports.length;
    if (effectiveBuildMode == 'MIXED_SPORTS' &&
        selectedSportCount > 1 &&
        sportBreakdown.length == 1) {
      warnings.add(
        'Mixed Sports mode could only find qualified props from one sport.',
      );
    }
    if (_generatedLegs.isNotEmpty &&
        _lockedGeneratedPropIds.length == _generatedLegs.length) {
      warnings.add(
        'Every generated pick is locked. Unlock one to regenerate the slip.',
      );
    }
    final worseMovementCount = _generatedLegs.where((leg) {
      return leg['movement_status']?.toString().toUpperCase() == 'WORSE';
    }).length;
    final unavailableCount = _generatedLegs.where((leg) {
      return leg['movement_status']?.toString().toUpperCase() == 'UNAVAILABLE';
    }).length;
    if (worseMovementCount > 0) {
      warnings.add(
        '$worseMovementCount pick${worseMovementCount == 1 ? ' has' : 's have'} moved to a worse line.',
      );
    }
    if (unavailableCount > 0) {
      warnings.add(
        '$unavailableCount pick${unavailableCount == 1 ? ' is' : 's are'} no longer available.',
      );
    }
    warnings.addAll(_correlationWarnings);
    return warnings;
  }

  Widget _qualityMeter({required String label, required double value}) {
    final normalized = (value / 100).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${value.toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: normalized,
          minHeight: 8,
          borderRadius: BorderRadius.circular(20),
        ),
      ],
    );
  }

  Widget _breakdownChips(Map<String, int> breakdown) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: breakdown.entries.map((entry) {
        return Chip(label: Text('${entry.key}: ${entry.value}'));
      }).toList(),
    );
  }

  Widget _summaryTile({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityPanel() {
    final warnings = _builderWarnings();
    final qualityLabel = _qualityLabel();
    final modeLabel =
        (_responseBuildMode.isNotEmpty ? _responseBuildMode : _buildMode) ==
            'SAME_SPORT'
        ? 'Same Sport'
        : 'Mixed Sports';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_qualityIcon()),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'BUILDER QUALITY',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              Chip(
                avatar: const Icon(Icons.lock, size: 16),
                label: Text('Locked: ${_lockedGeneratedPropIds.length}'),
              ),
              const SizedBox(width: 8),
              Chip(label: Text('Risk: $_riskMode')),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  'Better: ${_generatedLegs.where((leg) => leg['movement_status']?.toString().toUpperCase() == 'BETTER').length}',
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  'Worse: ${_generatedLegs.where((leg) => leg['movement_status']?.toString().toUpperCase() == 'WORSE').length}',
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  _correlationGuardEnabled
                      ? 'Correlation Guard: ON'
                      : 'Correlation Guard: OFF',
                ),
              ),
              const SizedBox(width: 8),
              Chip(label: Text(qualityLabel)),
            ],
          ),
          const SizedBox(height: 18),
          _qualityMeter(label: 'Average Edge', value: _averageEdge),
          const SizedBox(height: 16),
          _qualityMeter(label: 'Average Confidence', value: _averageConfidence),
          const SizedBox(height: 10),
          Text('Mode: $modeLabel'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  label: 'Requested',
                  value: '$_requestedLegs',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryTile(
                  label: 'Generated',
                  value: '$_generatedLegCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryTile(
                  label: 'Selected',
                  value: '${_selectedGeneratedPropIds.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'SOURCE BREAKDOWN',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _breakdownChips(_siteBreakdown()),
          const SizedBox(height: 16),
          const Text(
            'SPORT BREAKDOWN',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _breakdownChips(_sportBreakdown()),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'WARNINGS',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(warning)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _strategyMetric({
    required String label,
    required String value,
    required String detail,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyPanel() {
    if (_isLoadingStrategy) {
      return const LinearProgressIndicator();
    }
    final strategy = _builderStrategy;
    if (strategy == null) {
      return const Text('Strategy recommendations are unavailable.');
    }
    final enoughData = strategy['enough_data'] == true;
    final resolvedLegs = (strategy['resolved_legs'] as num?)?.toInt() ?? 0;
    final requiredLegs =
        (strategy['minimum_required_legs'] as num?)?.toInt() ?? 10;
    final warnings = strategy['warnings'] as List<dynamic>? ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'RECOMMENDED STRATEGY',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Chip(
                label: Text(
                  enoughData
                      ? 'DATA READY'
                      : '$resolvedLegs/$requiredLegs LEGS',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 3 : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 1 ? 4 : 1.8,
                children: [
                  _strategyMetric(
                    label: 'BEST SPORT',
                    value: _strategyName('recommended_sport'),
                    detail:
                        '${_strategyHitRate('recommended_sport').toStringAsFixed(1)}% hit rate • ${_strategySample('recommended_sport')} legs',
                    icon: Icons.sports,
                  ),
                  _strategyMetric(
                    label: 'BEST PROP SITE',
                    value: _strategyName('recommended_prop_site'),
                    detail:
                        '${_strategyHitRate('recommended_prop_site').toStringAsFixed(1)}% hit rate • ${_strategySample('recommended_prop_site')} legs',
                    icon: Icons.storefront,
                  ),
                  _strategyMetric(
                    label: 'BEST MARKET',
                    value: _marketLabel(_strategyName('recommended_market')),
                    detail:
                        '${_strategyHitRate('recommended_market').toStringAsFixed(1)}% hit rate • ${_strategySample('recommended_market')} legs',
                    icon: Icons.query_stats,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  'Minimum Edge: ${strategy['recommended_minimum_edge']}%',
                ),
              ),
              Chip(
                label: Text(
                  'Minimum Confidence: ${strategy['recommended_minimum_confidence']}%',
                ),
              ),
              Chip(
                label: Text(
                  'Recommended Legs: ${strategy['recommended_leg_count']}',
                ),
              ),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 17),
                    const SizedBox(width: 7),
                    Expanded(child: Text(warning.toString())),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enoughData ? _applyRecommendedStrategy : null,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('APPLY RECOMMENDED STRATEGY'),
            ),
          ),
        ],
      ),
    );
  }

  void _recalculateBuilderQuality() {
    if (_generatedLegs.isEmpty) {
      _averageEdge = 0;
      _averageConfidence = 0;
      _generatedLegCount = 0;
      return;
    }

    double edgeTotal = 0;
    double confidenceTotal = 0;
    for (final leg in _generatedLegs) {
      edgeTotal += (leg['edge'] as num?)?.toDouble() ?? 0;
      confidenceTotal += (leg['confidence'] as num?)?.toDouble() ?? 0;
    }

    _generatedLegCount = _generatedLegs.length;
    _averageEdge = edgeTotal / _generatedLegs.length;
    _averageConfidence = confidenceTotal / _generatedLegs.length;
  }

  Future<void> _replaceGeneratedLeg(Map<String, dynamic> currentLeg) async {
    final currentPropId = currentLeg['prop_id']?.toString() ?? '';
    if (currentPropId.isEmpty) {
      return;
    }
    final oldWasWatchlisted = _watchlistedPropIds.contains(currentPropId);
    Map<String, dynamic>? replacementLegForWatchlist;

    setState(() {
      _replacingPropId = currentPropId;
      _error = null;
    });

    try {
      final replacement = await _apiService.replacePropLeg(
        currentPropId: currentPropId,
        sports: _selectedSports.toList(),
        propSites: _selectedSites.toList(),
        markets: _selectedMarkets.toList(),
        riskMode: _riskMode,
        correlationGuardEnabled: _correlationGuardEnabled,
        maximumLegsPerGame: _maximumLegsPerGame,
        maximumLegsPerTeam: _maximumLegsPerTeam,
        maximumLegsPerPlayer: _maximumLegsPerPlayer,
        minimumEdge: _minimumEdge.round(),
        minimumConfidence: _minimumConfidence.round(),
        buildMode: _buildMode,
        sidePreference: _sidePreference,
        excludedPropIds: _generatedLegs
            .map((leg) => leg['prop_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
        excludedPlayers: _generatedLegs
            .where((leg) => leg['prop_id']?.toString() != currentPropId)
            .map((leg) => leg['player']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList(),
        excludedEventIds: _sameGameAllowed
            ? []
            : _generatedLegs
                  .where((leg) => leg['prop_id']?.toString() != currentPropId)
                  .map((leg) => leg['event_id']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toList(),
      );
      final replacementId = replacement['prop_id']?.toString() ?? '';

      if (!mounted) {
        return;
      }

      setState(() {
        final index = _generatedLegs.indexWhere(
          (leg) => leg['prop_id']?.toString() == currentPropId,
        );
        if (index == -1) {
          return;
        }

        final wasSelected = _selectedGeneratedPropIds.contains(currentPropId);
        final previousLabel = currentLeg['custom_label']?.toString() ?? '';
        final previousNote = currentLeg['manual_note']?.toString() ?? '';
        final replacementLeg = Map<String, dynamic>.from(replacement);
        replacementLeg['builder_position'] = index;
        replacementLeg['custom_label'] = previousLabel;
        replacementLeg['manual_note'] = previousNote;
        replacementLeg['original_line'] = replacementLeg['line'];
        replacementLeg['original_odds'] = replacementLeg['odds'];
        replacementLeg['current_line'] = replacementLeg['line'];
        replacementLeg['current_odds'] = replacementLeg['odds'];
        replacementLeg['line_change'] = 0;
        replacementLeg['odds_change'] = 0;
        replacementLeg['movement_status'] = 'UNCHANGED';
        replacementLeg['last_line_check'] = null;
        replacementLegForWatchlist = replacementLeg;
        _generatedLegs[index] = replacementLeg;
        _selectedGeneratedPropIds.remove(currentPropId);
        if (wasSelected && replacementId.isNotEmpty) {
          _selectedGeneratedPropIds.add(replacementId);
        }
        if (_expandedExplanationPropId == currentPropId) {
          _expandedExplanationPropId = replacementId;
        }

        _recalculateBuilderQuality();
      });

      if (oldWasWatchlisted && replacementLegForWatchlist != null) {
        await _watchlistService.removeProp(currentPropId);
        await _watchlistService.addProp(replacementLegForWatchlist!);
        if (mounted) {
          setState(() {
            _watchlistedPropIds.remove(currentPropId);
            if (replacementId.isNotEmpty) {
              _watchlistedPropIds.add(replacementId);
            }
          });
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyBuilderError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _replacingPropId = null;
        });
      }
    }
  }

  Widget _siteChip(String site) {
    final selected = _selectedSites.contains(site);
    return FilterChip(
      label: Text(site),
      selected: selected,
      onSelected: (value) {
        setState(() {
          if (value) {
            _selectedSites.add(site);
          } else {
            _selectedSites.remove(site);
          }
        });
      },
    );
  }

  Widget _sportChip(String sport) {
    final selected = _selectedSports.contains(sport);
    return FilterChip(
      label: Text(sport),
      selected: selected,
      onSelected: (value) {
        setState(() {
          if (value) {
            _selectedSports.add(sport);
          } else {
            _selectedSports.remove(sport);
          }
        });
        _emitSelectedSportsChanged();
      },
    );
  }

  Widget _marketChip(String market) {
    final selected = _selectedMarkets.contains(market);
    return FilterChip(
      label: Text(_marketLabel(market)),
      selected: selected,
      onSelected: (value) {
        setState(() {
          if (value) {
            _selectedMarkets.add(market);
          } else {
            _selectedMarkets.remove(market);
          }
        });
      },
    );
  }

  Widget _pickExplanationPanel(Map<String, dynamic> leg) {
    final reason =
        leg['selection_reason']?.toString() ?? 'No explanation is available.';
    final strategyMatch = leg['strategy_match'] == true;
    final hitRate = (leg['historical_hit_rate'] as num?)?.toDouble();
    final sampleSize = (leg['historical_sample_size'] as num?)?.toInt() ?? 0;
    final risks = (leg['risk_factors'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18),
              SizedBox(width: 7),
              Text(
                'WHY THIS PICK?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(reason),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  strategyMatch ? Icons.check_circle : Icons.info_outline,
                  size: 17,
                ),
                label: Text(
                  strategyMatch ? 'Matches strategy' : 'Qualified selection',
                ),
              ),
              if (hitRate != null)
                Chip(
                  label: Text('Market history: ${hitRate.toStringAsFixed(1)}%'),
                ),
              if (sampleSize > 0) Chip(label: Text('Sample: $sampleSize')),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'RISK FACTORS',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          if (risks.isEmpty)
            const Text('No major correlation or threshold risks detected.')
          else
            ...risks.map(
              (risk) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 17),
                    const SizedBox(width: 7),
                    Expanded(child: Text(risk)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PROP BUILDER',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Build the highest-rated slip from your selected prop sites.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(
                      _backendOnline == false
                          ? Icons.cloud_off
                          : Icons.cloud_done,
                      size: 16,
                    ),
                    label: Text(
                      _backendOnline == false
                          ? 'Backend offline'
                          : 'Backend online',
                    ),
                  ),
                  if (_backendOnline == false)
                    TextButton.icon(
                      onPressed: _checkBackendStatus,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('RECHECK'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'BUILDER PRESETS',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (_isLoadingPresets)
                const LinearProgressIndicator()
              else if (_presets.isEmpty)
                const Text('No saved presets yet.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presets.map((preset) {
                    final name = preset['name']?.toString() ?? 'Preset';
                    final selected = _selectedPresetName == name;
                    return InputChip(
                      label: Text(name),
                      selected: selected,
                      onPressed: () {
                        _applyPreset(preset);
                      },
                      onDeleted: () {
                        _deletePreset(preset);
                      },
                      deleteIcon: const Icon(Icons.close),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSavingPreset ? null : _showSavePresetDialog,
                icon: _isSavingPreset
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_add),
                label: Text(
                  _isSavingPreset ? 'SAVING...' : 'SAVE CURRENT SETUP',
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showBuildHistory = !_showBuildHistory;
                  });
                },
                icon: const Icon(Icons.history),
                label: Text(
                  _showBuildHistory
                      ? 'HIDE BUILD HISTORY'
                      : 'SHOW BUILD HISTORY',
                ),
              ),
              if (_showBuildHistory) ...[
                const SizedBox(height: 16),
                _buildHistoryPanel(),
              ],
              const SizedBox(height: 20),
              _buildStrategyPanel(),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text(
                    'SPORTS',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Chip(
                    avatar: Icon(
                      widget.isManualSportsMode ? Icons.tune : Icons.sync_alt,
                      size: 16,
                    ),
                    label: Text(
                      widget.isManualSportsMode
                          ? 'Manual Sports Mode'
                          : 'Sidebar Sync Mode',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _availableSports.map(_sportChip).toList(),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSports
                          ..clear()
                          ..addAll(_availableSports);
                      });
                      _emitSelectedSportsChanged();
                    },
                    child: const Text('SELECT ALL'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSports.clear();
                      });
                      _emitSelectedSportsChanged();
                    },
                    child: const Text('CLEAR'),
                  ),
                  if (widget.onResetSportsAutoSync != null)
                    TextButton(
                      onPressed: widget.onResetSportsAutoSync,
                      child: const Text('RESET TO SIDEBAR SYNC'),
                    ),
                ],
              ),
              const Text(
                'BUILD MODE',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'SAME_SPORT',
                    icon: Icon(Icons.sports_basketball),
                    label: Text('SAME SPORT'),
                  ),
                  ButtonSegment<String>(
                    value: 'MIXED_SPORTS',
                    icon: Icon(Icons.shuffle),
                    label: Text('MIXED SPORTS'),
                  ),
                ],
                selected: {_buildMode},
                onSelectionChanged: (Set<String> selection) {
                  setState(() {
                    _buildMode = selection.first;
                  });
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'RISK MODE',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'SAFE',
                    icon: Icon(Icons.shield_outlined),
                    label: Text('SAFE'),
                  ),
                  ButtonSegment<String>(
                    value: 'BALANCED',
                    icon: Icon(Icons.balance),
                    label: Text('BALANCED'),
                  ),
                  ButtonSegment<String>(
                    value: 'AGGRESSIVE',
                    icon: Icon(Icons.local_fire_department),
                    label: Text('AGGRESSIVE'),
                  ),
                ],
                selected: {_riskMode},
                onSelectionChanged: (Set<String> selection) {
                  setState(() {
                    _riskMode = selection.first;
                    _applyRiskModeDefaults();
                  });
                },
              ),
              const SizedBox(height: 12),
              Text(_riskModeDescription()),
              const SizedBox(height: 12),
              const Text(
                'CORRELATION GUARD',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Protect against correlated picks'),
                subtitle: const Text(
                  'Limits repeated players, games, and teams in one generated slip.',
                ),
                value: _correlationGuardEnabled,
                onChanged: (value) {
                  setState(() {
                    _correlationGuardEnabled = value;
                  });
                },
              ),
              if (_correlationGuardEnabled) ...[
                const SizedBox(height: 10),
                Text('Maximum per player: $_maximumLegsPerPlayer'),
                Slider(
                  value: _maximumLegsPerPlayer.toDouble(),
                  min: 1,
                  max: 2,
                  divisions: 1,
                  label: '$_maximumLegsPerPlayer',
                  onChanged: (value) {
                    setState(() {
                      _maximumLegsPerPlayer = value.round();
                    });
                  },
                ),
                Text('Maximum per game: $_maximumLegsPerGame'),
                Slider(
                  value: _maximumLegsPerGame.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_maximumLegsPerGame',
                  onChanged: (value) {
                    setState(() {
                      _maximumLegsPerGame = value.round();
                    });
                  },
                ),
                Text('Maximum per team: $_maximumLegsPerTeam'),
                Slider(
                  value: _maximumLegsPerTeam.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_maximumLegsPerTeam',
                  onChanged: (value) {
                    setState(() {
                      _maximumLegsPerTeam = value.round();
                    });
                  },
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'PROP SITES',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _availablePropSites.map(_siteChip).toList(),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSites
                          ..clear()
                          ..addAll(_availablePropSites);
                      });
                    },
                    child: const Text('SELECT ALL'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSites.clear();
                      });
                    },
                    child: const Text('CLEAR'),
                  ),
                ],
              ),
              const Text(
                'MARKETS',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedMarkets.isEmpty
                    ? 'All markets are currently allowed.'
                    : 'Only selected markets will be used.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableMarkets.map(_marketChip).toList(),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedMarkets
                          ..clear()
                          ..addAll(_availableMarkets);
                      });
                    },
                    child: const Text('SELECT ALL'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedMarkets.clear();
                      });
                    },
                    child: const Text('ALL MARKETS'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'LEGS: $_legCount',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: _legCount.toDouble(),
                min: 2,
                max: 8,
                divisions: 6,
                label: '$_legCount',
                onChanged: (value) {
                  setState(() {
                    _legCount = value.round();
                  });
                },
              ),
              Text('MINIMUM EDGE: ${_minimumEdge.round()}%'),
              Slider(
                value: _minimumEdge,
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (value) {
                  setState(() {
                    _minimumEdge = value;
                  });
                },
              ),
              Text('MINIMUM CONFIDENCE: ${_minimumConfidence.round()}%'),
              Slider(
                value: _minimumConfidence,
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (value) {
                  setState(() {
                    _minimumConfidence = value;
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow multiple legs from the same game'),
                value: _sameGameAllowed,
                onChanged: (value) {
                  setState(() {
                    _sameGameAllowed = value;
                  });
                },
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build mode: ${_buildMode == 'SAME_SPORT' ? 'Same Sport' : 'Mixed Sports'}',
                    ),
                    const SizedBox(height: 6),
                    Text('Selected sports: ${_selectedSports.join(', ')}'),
                    const SizedBox(height: 6),
                    Text('Selected sites: ${_selectedSites.join(', ')}'),
                    const SizedBox(height: 6),
                    Text(
                      'Selected markets: ${_selectedMarkets.isEmpty ? 'All' : _selectedMarkets.map(_marketLabel).join(', ')}',
                    ),
                    const SizedBox(height: 6),
                    Text('Risk mode: $_riskMode'),
                    const SizedBox(height: 6),
                    Text('Slip size: $_legCount legs'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        _selectedSites.isEmpty ||
                            _selectedSports.isEmpty ||
                            _backendOnline == false ||
                            _isLoading
                        ? null
                        : _generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _backendOnline == false
                          ? 'BACKEND OFFLINE'
                          : _isLoading
                          ? 'BUILDING...'
                          : 'BUILD MY SLIP',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute<void>(
                              builder: (context) {
                                return PropWatchlistScreen(
                                  activeSlipController:
                                      widget.activeSlipController,
                                );
                              },
                            ),
                          )
                          .then((_) {
                            _loadWatchlistIds();
                          });
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text('WATCHLIST (${_watchlistedPropIds.length})'),
                  ),
                  _buildExportMenu(),
                ],
              ),
              if (_isLoading) ...[
                const SizedBox(height: 14),
                _buildBuilderLoadingState(),
              ],
              if (_generatedLegs.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _regenerateUnlockedLegs,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      'REGENERATE UNLOCKED '
                      '(${_generatedLegs.length - _lockedGeneratedPropIds.length})',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _generatedLegs.isEmpty || _isCheckingLines
                          ? null
                          : () {
                              _checkLineMovement(refresh: true);
                            },
                      icon: _isCheckingLines
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.show_chart),
                      label: Text(
                        _isCheckingLines
                            ? 'CHECKING LINES'
                            : 'CHECK LINE MOVEMENT',
                      ),
                    ),
                    FilterChip(
                      selected: _autoCheckLines,
                      avatar: const Icon(Icons.autorenew, size: 17),
                      label: const Text('AUTO CHECK'),
                      onSelected: _setAutoLineCheck,
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        unawaited(_openMovementAlertsOverlay());
                      },
                      icon: const Icon(Icons.notifications),
                      label: Text(
                        _unreadMovementAlertCount > 0
                            ? 'ALERTS ($_unreadMovementAlertCount)'
                            : 'ALERTS',
                      ),
                    ),
                    if (_lastLineMovementCheck != null)
                      Text(
                        'Last checked ${TimeOfDay.fromDateTime(_lastLineMovementCheck!).format(context)}',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildLineAlertSettings(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _buildErrorPanel(message: _error!, onRetry: _generate),
              ],
              if (_hasAttemptedBuild) ...[
                const SizedBox(height: 12),
                _buildBuildDetailsPanel(),
              ],
              if (_generatedLegs.isNotEmpty || _requestedLegs > 0) ...[
                const SizedBox(height: 24),
                _buildQualityPanel(),
              ],
              if (_generatedLegs.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildPartialBuildWarning(),
              ],
              if (!_isLoading &&
                  _requestedLegs > 0 &&
                  _generatedLegs.isEmpty) ...[
                const SizedBox(height: 20),
                _buildNoResultsState(),
              ],
              if (!_isLoading && !_hasAttemptedBuild) ...[
                const SizedBox(height: 20),
                _buildInitialBuilderState(),
              ],
              const SizedBox(height: 24),
              if (_generatedLegs.isNotEmpty) ...[
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedGeneratedPropIds
                            ..clear()
                            ..addAll(
                              _generatedLegs
                                  .map(_propId)
                                  .where((id) => id.isNotEmpty),
                            );
                        });
                      },
                      child: const Text('SELECT ALL'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedGeneratedPropIds.clear();
                        });
                      },
                      child: const Text('CLEAR'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _lockedGeneratedPropIds
                            ..clear()
                            ..addAll(
                              _generatedLegs
                                  .map(_propId)
                                  .where((id) => id.isNotEmpty),
                            );
                        });
                      },
                      child: const Text('LOCK ALL'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _lockedGeneratedPropIds.clear();
                        });
                      },
                      child: const Text('UNLOCK ALL'),
                    ),
                    TextButton.icon(
                      onPressed: _generatedLegs.length < 2
                          ? null
                          : _resetGeneratedLegOrder,
                      icon: const Icon(Icons.sort, size: 18),
                      label: const Text('RESET ORDER'),
                    ),
                  ],
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _generatedLegs.length,
                  onReorderItem: _reorderGeneratedLegs,
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final leg = _generatedLegs[index];
                    return _buildGeneratedLegCard(leg: leg, index: index);
                  },
                ),
              ],
              if (_generatedLegs.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selectedGeneratedPropIds.isEmpty
                        ? null
                        : _addSelectedToActiveSlip,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(
                      'ADD SELECTED (${_selectedGeneratedPropIds.length})',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: -5000,
          top: 0,
          child: RepaintBoundary(
            key: _exportCardKey,
            child: Material(
              color: Colors.transparent,
              child: _buildExportSlipCard(),
            ),
          ),
        ),
      ],
    );
  }
}
