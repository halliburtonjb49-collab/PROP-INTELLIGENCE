import 'package:flutter/material.dart';

import '../models/slip_selection.dart';
import '../services/api_service.dart';
import '../services/pickem_payout_rules.dart';
import '../theme/app_colors.dart';

String normalizeSlipSite(String value) {
  return normalizePickemSite(value);
}

List<String> slipEntryTypesForSite(String site) =>
    pickemEntryTypesForSite(site);

double fixedSlipMultiplier({
  required String site,
  required String entryType,
  required int legCount,
}) {
  return basePickemMaxMultiplier(
        site: site,
        entryType: entryType,
        legCount: legCount,
      ) ??
      1;
}

class LockSlipResult {
  const LockSlipResult({
    required this.stake,
    required this.site,
    required this.entryType,
    this.payoutMultiplier,
  });

  final double stake;
  final String site;
  final String entryType;
  final double? payoutMultiplier;
}

class LockSlipDialog extends StatefulWidget {
  const LockSlipDialog({
    super.key,
    required this.selections,
    required this.apiService,
  });

  final List<SlipSelection> selections;
  final ApiService apiService;

  @override
  State<LockSlipDialog> createState() => _LockSlipDialogState();
}

class _LockSlipDialogState extends State<LockSlipDialog> {
  final _formKey = GlobalKey<FormState>();
  final _stakeController = TextEditingController(text: '10.00');
  String _selectedSite = 'PRIZEPICKS';
  String _entryType = 'POWER';
  bool _loadingPreview = false;
  String? _error;
  double? _potentialPayout;
  double? _potentialProfit;

  bool get _hasProviderModifiers => widget.selections.any((selection) {
    final multiplier = selection.prop.multiplier;
    return multiplier != null && (multiplier - 1).abs() > 0.001;
  });

  List<String> get _siteOptions {
    final options = <String>{
      for (final selection in widget.selections)
        normalizeSlipSite(
          '${selection.prop.sportsbook} ${selection.prop.sourceProvider}',
        ),
    }..removeWhere((site) => site.isEmpty);
    if (options.isEmpty) options.add('PRIZEPICKS');
    return options.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _selectedSite = _siteOptions.first;
    _entryType = slipEntryTypesForSite(_selectedSite).first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updatePreview();
    });
  }

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  double? _readStake() =>
      double.tryParse(_stakeController.text.replaceAll(r'$', '').trim());

  Future<void> _updatePreview() async {
    final stake = _readStake();
    if (stake == null || stake <= 0) {
      setState(() {
        _potentialPayout = null;
        _potentialProfit = null;
      });
      return;
    }

    final outcomes = basePickemPayoutOutcomes(
      site: _selectedSite,
      entryType: _entryType,
      legCount: widget.selections.length,
    );
    if (outcomes.isNotEmpty) {
      final multiplier = outcomes[widget.selections.length];
      if (_hasProviderModifiers) {
        setState(() {
          _loadingPreview = false;
          _error =
              'This research ticket contains provider-specific multipliers. Confirm the exact return shown by $_selectedSite before saving.';
          _potentialPayout = null;
          _potentialProfit = null;
        });
        return;
      }
      if (multiplier == null) return;
      setState(() {
        _loadingPreview = false;
        _error = null;
        _potentialPayout = stake * multiplier;
        _potentialProfit = _potentialPayout! - stake;
      });
      return;
    }

    if (isPoolBasedPayout(_selectedSite)) {
      setState(() {
        _loadingPreview = false;
        _error =
            'DraftKings Pick6 is pool-based. Its final result cannot be calculated from selection prices; use the return displayed by Pick6.';
        _potentialPayout = null;
        _potentialProfit = null;
      });
      return;
    }

    if (isDiscontinuedPickemProduct(_selectedSite)) {
      setState(() {
        _loadingPreview = false;
        _error = 'FanDuel Picks no longer accepts new contests.';
        _potentialPayout = null;
        _potentialProfit = null;
      });
      return;
    }

    if (!const {'FANDUEL', 'DRAFTKINGS'}.contains(_selectedSite)) {
      final multiplier = fixedSlipMultiplier(
        site: _selectedSite,
        entryType: _entryType,
        legCount: widget.selections.length,
      );
      setState(() {
        _loadingPreview = false;
        if (multiplier <= 1) {
          _error =
              'Selected play type is not available for ${widget.selections.length} legs.';
          _potentialPayout = null;
          _potentialProfit = null;
        } else {
          _error = null;
          _potentialPayout = stake * multiplier;
          _potentialProfit = _potentialPayout! - stake;
        }
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
      if (!mounted) return;
      setState(() {
        _potentialPayout = preview['potentialPayout'];
        _potentialProfit = preview['potentialProfit'];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  void _confirm() {
    if (_formKey.currentState?.validate() ?? false) {
      final stake = _readStake();
      if (stake == null) return;
      final payoutMultiplier = basePickemMaxMultiplier(
        site: _selectedSite,
        entryType: _entryType,
        legCount: widget.selections.length,
      );
      Navigator.of(context).pop(
        LockSlipResult(
          stake: stake,
          site: _selectedSite,
          entryType: _entryType,
          // Zero explicitly records that a pool-based or modified pick'em
          // payout is unknown instead of inventing sportsbook odds.
          payoutMultiplier:
              _hasProviderModifiers ||
                  isPoolBasedPayout(_selectedSite) ||
                  isDiscontinuedPickemProduct(_selectedSite) ||
                  (const {
                        'PRIZEPICKS',
                        'UNDERDOG',
                        'BETR',
                      }.contains(_selectedSite) &&
                      payoutMultiplier == null)
              ? 0
              : payoutMultiplier,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entryTypes = slipEntryTypesForSite(_selectedSite);
    final selectedEntryType = entryTypes.contains(_entryType)
        ? _entryType
        : entryTypes.first;
    final entryTypeLabel = switch (selectedEntryType) {
      'PARLAY' => 'Multi-selection',
      'POWER' => 'Power Play',
      'STANDARD' => 'Standard',
      'PERFECT' => 'Perfect Play',
      'CONTEST' => 'Pick6 Contest',
      'DISCONTINUED' => 'Discontinued',
      _ => 'Flex Play',
    };
    final outcomes = basePickemPayoutOutcomes(
      site: _selectedSite,
      entryType: selectedEntryType,
      legCount: widget.selections.length,
    );

    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'LOCK SLIP',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.selections.length} LEG SLIP',
                  style: const TextStyle(
                    color: AppColors.goldHighlight,
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
                    if (value == null) return;
                    setState(() {
                      _selectedSite = value;
                      _entryType = slipEntryTypesForSite(value).first;
                    });
                    _updatePreview();
                  },
                ),
                if (entryTypes.length > 1) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: entryTypes
                        .map(
                          (type) => ButtonSegment(
                            value: type,
                            label: Text(switch (type) {
                              'POWER' => 'POWER PLAY',
                              'STANDARD' => 'STANDARD',
                              'PERFECT' => 'PERFECT PLAY',
                              _ => 'FLEX PLAY',
                            }),
                            icon: Icon(
                              type == 'FLEX'
                                  ? Icons.shield_outlined
                                  : Icons.bolt,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    selected: {selectedEntryType},
                    onSelectionChanged: (selection) {
                      setState(() => _entryType = selection.first);
                      _updatePreview();
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    'Entry Type: ${entryTypes.first}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Site: $_selectedSite \u2022 Entry: $entryTypeLabel',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('lock-slip-stake'),
                  controller: _stakeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Entry amount',
                    prefixText: r'$',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final stake = double.tryParse(
                      value?.replaceAll(r'$', '').trim() ?? '',
                    );
                    return stake == null || stake <= 0
                        ? r'Enter an entry amount greater than $0.'
                        : null;
                  },
                  onChanged: (_) => _updatePreview(),
                ),
                const SizedBox(height: 18),
                _PreviewRow(
                  label: outcomes.isEmpty
                      ? 'Estimated return'
                      : 'Base maximum return',
                  value: _potentialPayout,
                  loading: _loadingPreview,
                ),
                const SizedBox(height: 8),
                _PreviewRow(
                  label: 'Potential profit',
                  value: _potentialProfit,
                  loading: _loadingPreview,
                ),
                if (outcomes.length > 1) ...[
                  const SizedBox(height: 10),
                  Text(
                    outcomes.entries
                        .map(
                          (outcome) =>
                              '${outcome.key}/${widget.selections.length} correct: ${formatPickemMultiplier(outcome.value)}x',
                        )
                        .join('  •  '),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      height: 1.35,
                    ),
                  ),
                ],
                if (outcomes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Standard selections only. Special picks, promotions, correlations, ties, and voids can change the return; the prop site display is final.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      height: 1.3,
                    ),
                  ),
                ],
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed:
              _loadingPreview || isDiscontinuedPickemProduct(_selectedSite)
              ? null
              : _confirm,
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
  const _PreviewRow({
    required this.label,
    required this.value,
    required this.loading,
  });

  final String label;
  final double? value;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const Spacer(),
        if (loading)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.goldHighlight,
            ),
          )
        else
          Text(
            value == null ? '--' : '\$${value!.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.goldHighlight,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}
