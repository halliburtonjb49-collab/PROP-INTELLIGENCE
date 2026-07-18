import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/active_slip_controller.dart';
import '../models/line_movement_alert.dart';
import '../services/api_service.dart';
import '../services/prop_watchlist_service.dart';
import '../widgets/slip_history_panel.dart';
import '../widgets/context_help.dart';

class PropWatchlistScreen extends StatefulWidget {
  const PropWatchlistScreen({super.key, required this.activeSlipController});

  final ActiveSlipController activeSlipController;

  @override
  State<PropWatchlistScreen> createState() => _PropWatchlistScreenState();
}

class _PropWatchlistScreenState extends State<PropWatchlistScreen> {
  static const List<String> _defaultReplacementSites = [
    'PrizePicks',
    'Underdog',
    'Sleeper',
    'FanDuel',
    'Draft Picks',
  ];

  final PropWatchlistService _watchlistService = PropWatchlistService();
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _props = [];
  final Set<String> _selectedPropIds = {};
  final List<LineMovementAlert> _movementAlerts = [];
  Map<String, Map<String, dynamic>> _previousSnapshots = {};
  bool _showAlerts = false;
  bool _isLoading = true;
  bool _isCheckingLines = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  String _propId(Map<String, dynamic> prop) {
    return prop['prop_id']?.toString() ?? '';
  }

  Future<void> _loadWatchlist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final props = await _watchlistService.loadWatchlist(
        includeCloudSync: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _props = props;
        _previousSnapshots = _createSnapshots(props);
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
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeProp(Map<String, dynamic> prop) async {
    final propId = _propId(prop);
    if (propId.isEmpty) {
      return;
    }

    await _watchlistService.removeProp(propId);
    if (!mounted) {
      return;
    }
    setState(() {
      _props.removeWhere((item) => _propId(item) == propId);
      _selectedPropIds.remove(propId);
    });
  }

  Future<void> _clearWatchlist() async {
    final lockedProps = _props.where(_isLocked).toList();
    if (lockedProps.isNotEmpty) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Clear Watchlist?'),
            content: Text(
              '${lockedProps.length} locked prop${lockedProps.length == 1 ? '' : 's'} will also be removed.',
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
                child: const Text('CLEAR ALL'),
              ),
            ],
          );
        },
      );
      if (shouldContinue != true) {
        return;
      }
    }

    await _watchlistService.clearWatchlist();
    if (!mounted) {
      return;
    }
    setState(() {
      _props.clear();
      _selectedPropIds.clear();
      _movementAlerts.clear();
      _previousSnapshots.clear();
    });
  }

  Future<void> _checkLines() async {
    if (_props.isEmpty || _isCheckingLines) {
      return;
    }

    setState(() {
      _isCheckingLines = true;
      _error = null;
    });

    try {
      final response = await _apiService.checkPropLineMovement(
        legs: _props,
        refresh: true,
      );
      final rawLegs = response['legs'] as List<dynamic>? ?? [];
      final updated = rawLegs
          .whereType<Map<String, dynamic>>()
          .map((leg) => Map<String, dynamic>.from(leg))
          .toList();

      _processWatchlistMovements(updated);

      await _watchlistService.saveWatchlist(updated);
      await widget.activeSlipController.updateMatchingLegs(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _props = updated;
        if (_movementAlerts.isNotEmpty) {
          _showAlerts = true;
        }
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
          _isCheckingLines = false;
        });
      }
    }
  }

  void _toggleSelected(Map<String, dynamic> prop) {
    final propId = _propId(prop);
    if (propId.isEmpty) {
      return;
    }

    setState(() {
      if (_selectedPropIds.contains(propId)) {
        _selectedPropIds.remove(propId);
      } else {
        _selectedPropIds.add(propId);
      }
    });
  }

  Future<void> _addSelectedToActiveSlip() async {
    final selected = _props
        .where((prop) => _selectedPropIds.contains(_propId(prop)))
        .toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one watched prop.')),
      );
      return;
    }

    final addedCount = await widget.activeSlipController.addLegs(
      selected.map((leg) => Map<String, dynamic>.from(leg)).toList(),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedCount == 0
              ? 'Selected props are already active.'
              : '$addedCount watched prop${addedCount == 1 ? '' : 's'} added to Active Slip.',
        ),
      ),
    );
  }

  bool _isLocked(Map<String, dynamic> prop) {
    return prop['is_locked'] == true;
  }

  Future<void> _toggleLock(Map<String, dynamic> prop) async {
    setState(() {
      prop['is_locked'] = !_isLocked(prop);
    });
    await _watchlistService.addProp(prop);
  }

  Future<void> _addOneToActiveSlip(Map<String, dynamic> prop) async {
    final addedCount = await widget.activeSlipController.addLegs([
      Map<String, dynamic>.from(prop),
    ]);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedCount == 0
              ? 'This prop is already active.'
              : '${prop['player'] ?? 'Prop'} added to Active Slip.',
        ),
      ),
    );
  }

  Future<void> _editNote(Map<String, dynamic> prop) async {
    final labelController = TextEditingController(
      text: prop['custom_label']?.toString() ?? '',
    );
    final noteController = TextEditingController(
      text: prop['manual_note']?.toString() ?? '',
    );
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Watched Prop'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'Custom label',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Manual note',
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
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      prop['custom_label'] = result['custom_label'] ?? '';
      prop['manual_note'] = result['manual_note'] ?? '';
    });
    await _watchlistService.addProp(prop);
  }

  Map<String, dynamic> _snapshot(Map<String, dynamic> prop) {
    return {
      'movement_status':
          prop['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED',
      'current_line': (prop['current_line'] as num?)?.toDouble(),
      'current_odds': (prop['current_odds'] as num?)?.toInt(),
    };
  }

  Map<String, Map<String, dynamic>> _createSnapshots(
    List<Map<String, dynamic>> props,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final prop in props) {
      final id = _propId(prop);
      if (id.isEmpty) {
        continue;
      }
      result[id] = _snapshot(prop);
    }
    return result;
  }

  void _createMovementAlert({
    required Map<String, dynamic> prop,
    required String severity,
    required String message,
  }) {
    final propId = _propId(prop);
    if (propId.isEmpty) {
      return;
    }
    final status =
        prop['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    final line = prop['current_line']?.toString() ?? '';
    final odds = prop['current_odds']?.toString() ?? '';
    final alertId = '$propId-$status-$line-$odds';
    if (_movementAlerts.any((alert) => alert.id == alertId)) {
      return;
    }
    _movementAlerts.insert(
      0,
      LineMovementAlert(
        id: alertId,
        propId: propId,
        player: prop['player']?.toString() ?? 'Unknown player',
        message: message,
        severity: severity,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _processWatchlistMovements(List<Map<String, dynamic>> updated) {
    for (final prop in updated) {
      final propId = _propId(prop);
      if (propId.isEmpty) {
        continue;
      }
      final previous = _previousSnapshots[propId];
      final previousStatus =
          previous?['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
      final currentStatus =
          prop['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
      final previousLine = previous?['current_line'];
      final currentLine = prop['current_line'];
      final statusChanged = previousStatus != currentStatus;
      final lineChanged = previousLine != currentLine;
      if (!statusChanged && !lineChanged) {
        continue;
      }

      final player = prop['player']?.toString() ?? 'Unknown player';
      final side = prop['side']?.toString() ?? '';
      final market = prop['market']?.toString() ?? '';
      final originalLine = prop['original_line'] ?? prop['line'] ?? 'N/A';
      final newLine = prop['current_line'] ?? 'N/A';

      switch (currentStatus) {
        case 'WORSE':
          _createMovementAlert(
            prop: prop,
            severity: 'CRITICAL',
            message:
                '$player moved to a worse line: $side $originalLine → $newLine $market.',
          );
          break;
        case 'BETTER':
          _createMovementAlert(
            prop: prop,
            severity: 'POSITIVE',
            message:
                '$player improved to a better line: $side $originalLine → $newLine $market.',
          );
          break;
        case 'UNAVAILABLE':
          _createMovementAlert(
            prop: prop,
            severity: 'CRITICAL',
            message: '$player is no longer available for $market.',
          );
          break;
        default:
          _createMovementAlert(
            prop: prop,
            severity: 'INFO',
            message: '$player has a new line update.',
          );
      }
    }

    _previousSnapshots = _createSnapshots(updated);
  }

  int get _unreadAlertCount {
    return _movementAlerts.where((alert) => !alert.wasRead).length;
  }

  void _markAlertsRead() {
    setState(() {
      for (var index = 0; index < _movementAlerts.length; index++) {
        _movementAlerts[index] = _movementAlerts[index].copyWith(wasRead: true);
      }
    });
  }

  void _clearAlerts() {
    setState(() {
      _movementAlerts.clear();
    });
  }

  Widget _buildAlertsPanel() {
    if (!_showAlerts) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
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
                  'WATCHLIST ALERTS',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: _movementAlerts.isEmpty ? null : _markAlertsRead,
                child: const Text('MARK READ'),
              ),
              TextButton(
                onPressed: _movementAlerts.isEmpty ? null : _clearAlerts,
                child: const Text('CLEAR'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_movementAlerts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No watchlist alerts.')),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _movementAlerts.length,
                itemBuilder: (context, index) {
                  final alert = _movementAlerts[index];
                  final icon = alert.severity == 'CRITICAL'
                      ? Icons.error_outline
                      : alert.severity == 'POSITIVE'
                      ? Icons.trending_up
                      : Icons.info_outline;
                  return ListTile(
                    leading: Icon(icon),
                    title: Text(
                      alert.player,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(alert.message),
                    trailing: alert.wasRead
                        ? null
                        : const Icon(Icons.circle, size: 9),
                    onTap: () {
                      setState(() {
                        _movementAlerts[index] = alert.copyWith(wasRead: true);
                      });
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _replaceWatchedProp(Map<String, dynamic> currentProp) async {
    final currentId = _propId(currentProp);
    if (currentId.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sport = currentProp['sport']?.toString() ?? '';
      final market = currentProp['market']?.toString() ?? '';
      final response = await _apiService.replacePropLeg(
        currentPropId: currentId,
        sports: [sport].where((value) => value.isNotEmpty).toList(),
        propSites: _defaultReplacementSites,
        markets: [market].where((value) => value.isNotEmpty).toList(),
        riskMode: 'BALANCED',
        correlationGuardEnabled: true,
        maximumLegsPerGame: 1,
        maximumLegsPerTeam: 2,
        maximumLegsPerPlayer: 1,
        minimumEdge: 60,
        minimumConfidence: 65,
        buildMode: 'SAME_SPORT',
        sidePreference: 'ANY',
        excludedPropIds: _props
            .map((prop) => _propId(prop))
            .where((id) => id.isNotEmpty && id != currentId)
            .toList(),
        excludedPlayers: _props
            .where((prop) => _propId(prop) != currentId)
            .map((prop) => prop['player']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList(),
        excludedEventIds: _props
            .where((prop) => _propId(prop) != currentId)
            .map((prop) => prop['event_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
      );

      final replacement = Map<String, dynamic>.from(response);
      replacement['custom_label'] = currentProp['custom_label'] ?? '';
      replacement['manual_note'] = currentProp['manual_note'] ?? '';
      replacement['is_locked'] = currentProp['is_locked'] == true;

      final index = _props.indexWhere((prop) => _propId(prop) == currentId);
      if (index < 0) {
        return;
      }

      await _watchlistService.removeProp(currentId);
      await _watchlistService.addProp(replacement);

      if (!mounted) {
        return;
      }

      setState(() {
        _props[index] = replacement;
        _selectedPropIds.remove(currentId);
        _previousSnapshots = _createSnapshots(_props);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to replace prop: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _movementLabel(Map<String, dynamic> prop) {
    final status =
        prop['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    switch (status) {
      case 'BETTER':
        return 'Better Line';
      case 'WORSE':
        return 'Worse Line';
      case 'UNAVAILABLE':
        return 'Unavailable';
      case 'MOVED':
        return 'Line Moved';
      default:
        return 'No Change';
    }
  }

  IconData _movementIcon(Map<String, dynamic> prop) {
    final status =
        prop['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    switch (status) {
      case 'BETTER':
        return Icons.trending_up;
      case 'WORSE':
        return Icons.trending_down;
      case 'UNAVAILABLE':
        return Icons.remove_circle_outline;
      case 'MOVED':
        return Icons.swap_vert;
      default:
        return Icons.horizontal_rule;
    }
  }

  Widget _buildWatchlistCard(Map<String, dynamic> prop) {
    final propId = _propId(prop);
    final selected = _selectedPropIds.contains(propId);
    final player = prop['player']?.toString() ?? 'Unknown Player';
    final side = prop['side']?.toString() ?? '';
    final line = prop['current_line'] ?? prop['line'] ?? '';
    final market = prop['market']?.toString() ?? '';
    final matchup = prop['matchup']?.toString() ?? '';
    final site = prop['prop_site']?.toString() ?? '';
    final label = prop['custom_label']?.toString() ?? '';
    final note = prop['manual_note']?.toString() ?? '';
    final edge = (prop['edge'] as num?)?.toDouble() ?? 0;
    final confidence = (prop['confidence'] as num?)?.toDouble() ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: (_) {
                _toggleSelected(prop);
              },
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
                          player,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_isLocked(prop))
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.lock, size: 18),
                        ),
                      if (label.isNotEmpty) Chip(label: Text(label)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text('$side $line $market'),
                  const SizedBox(height: 4),
                  Text(
                    matchup,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(site)),
                      Chip(label: Text('Edge ${edge.toStringAsFixed(1)}%')),
                      Chip(
                        label: Text(
                          'Confidence ${confidence.toStringAsFixed(1)}%',
                        ),
                      ),
                      Chip(
                        avatar: Icon(_movementIcon(prop), size: 16),
                        label: Text(_movementLabel(prop)),
                      ),
                      if (_isLocked(prop))
                        const Chip(
                          avatar: Icon(Icons.lock, size: 15),
                          label: Text('Locked'),
                        ),
                    ],
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      note,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: 'Watchlist actions',
              onSelected: (action) {
                switch (action) {
                  case 'active_slip':
                    unawaited(_addOneToActiveSlip(prop));
                    break;
                  case 'lock':
                    _toggleLock(prop);
                    break;
                  case 'replace':
                    _replaceWatchedProp(prop);
                    break;
                  case 'note':
                    _editNote(prop);
                    break;
                  case 'remove':
                    _removeProp(prop);
                    break;
                }
              },
              itemBuilder: (context) {
                return [
                  const PopupMenuItem(
                    value: 'active_slip',
                    child: ListTile(
                      leading: Icon(Icons.add_circle_outline),
                      title: Text('Add to Active Slip'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'lock',
                    child: ListTile(
                      leading: Icon(
                        _isLocked(prop) ? Icons.lock_open : Icons.lock,
                      ),
                      title: Text(
                        _isLocked(prop) ? 'Unlock Prop' : 'Lock Prop',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'replace',
                    enabled: !_isLocked(prop),
                    child: ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(
                        _isLocked(prop) ? 'Unlock to Replace' : 'Replace Prop',
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'note',
                    child: ListTile(
                      leading: Icon(Icons.edit_note),
                      title: Text('Edit Note and Label'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Remove from Watchlist'),
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWatchlist() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 180;
        final verticalPadding = compact ? 16.0 : 36.0;
        final iconSize = compact ? 32.0 : 46.0;
        final titleSize = compact ? 15.0 : 17.0;

        return SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: iconSize),
                const SizedBox(height: 12),
                Text(
                  'No watched props yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: titleSize,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add props from Prop Builder to monitor line movement and quickly move picks into Active Slip.',
                  textAlign: TextAlign.center,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prop Watchlist'),
        actions: [
          const ContextHelp(
            title: 'Watchlist',
            message:
                'Save props here without adding them to a slip. Check all lines to spot movement, enable alerts for meaningful changes, and move selected props into the active slip when ready.',
          ),
          IconButton(
            tooltip: 'Refresh watchlist',
            onPressed: _isLoading ? null : _loadWatchlist,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Clear watchlist',
            onPressed: _props.isEmpty ? null : _clearWatchlist,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _props.isEmpty || _isCheckingLines
                      ? null
                      : _checkLines,
                  icon: _isCheckingLines
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.show_chart),
                  label: Text(
                    _isCheckingLines ? 'CHECKING LINES' : 'CHECK ALL LINES',
                  ),
                ),
                Badge(
                  isLabelVisible: _unreadAlertCount > 0,
                  label: Text('$_unreadAlertCount'),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAlerts = !_showAlerts;
                      });
                    },
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('ALERTS'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _selectedPropIds.isEmpty
                      ? null
                      : _addSelectedToActiveSlip,
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text('ADD SELECTED (${_selectedPropIds.length})'),
                ),
              ],
            ),
            _buildAlertsPanel(),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final watchlistPane = _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _props.isEmpty
                      ? Center(child: _buildEmptyWatchlist())
                      : ListView.builder(
                          itemCount: _props.length,
                          itemBuilder: (context, index) {
                            return _buildWatchlistCard(_props[index]);
                          },
                        );

                  if (constraints.maxWidth < 1100) {
                    return Column(
                      children: [
                        Expanded(flex: 3, child: watchlistPane),
                        const SizedBox(height: 18),
                        Expanded(
                          flex: 2,
                          child: SlipHistoryPanel(
                            activeSlipController: widget.activeSlipController,
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: watchlistPane),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF081723),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF8B6813)),
                          ),
                          child: SlipHistoryPanel(
                            activeSlipController: widget.activeSlipController,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
