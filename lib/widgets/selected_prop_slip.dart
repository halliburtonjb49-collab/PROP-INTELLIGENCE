import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class SelectedProp {
  final String id;
  final String playerName;
  final String team;
  final String position;
  final String propType;
  final String gameTime;
  final String sportsbook;
  final String imageUrl;
  final double line;
  final String selectedSide;
  final double edge;
  final int hitRate;
  final int bestOdds;
  final int liveOdds;

  const SelectedProp({
    required this.id,
    required this.playerName,
    required this.team,
    required this.position,
    required this.propType,
    required this.gameTime,
    required this.sportsbook,
    required this.imageUrl,
    required this.line,
    required this.selectedSide,
    required this.edge,
    required this.hitRate,
    required this.bestOdds,
    required this.liveOdds,
  });
}

class SelectedPropSlip extends StatefulWidget {
  final List<SelectedProp> props;
  final void Function(SelectedProp prop)? onRemove;
  final Future<void> Function()? onClear;
  final Future<void> Function()? onBuildTicket;
  final bool isBuilding;

  const SelectedPropSlip({
    super.key,
    required this.props,
    this.onRemove,
    this.onClear,
    this.onBuildTicket,
    this.isBuilding = false,
  });

  @override
  State<SelectedPropSlip> createState() => _SelectedPropSlipState();
}

class _SelectedPropSlipState extends State<SelectedPropSlip> {
  final ScrollController _scrollController = ScrollController();

  static const pageBackground = Color(0xFF050D14);
  static const raisedBackground = Color(0xFF0C1C28);
  static const borderColor = Color(0xFF273B49);
  static const gold = Color(0xFFFFC400);
  static const mutedText = Color(0xFF8EA0AD);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int get _estimatedOdds {
    if (widget.props.isEmpty) return 0;
    final decimal = widget.props.fold<double>(1, (total, prop) {
      final american = prop.liveOdds == 0 ? -110 : prop.liveOdds;
      final legDecimal = american > 0
          ? 1 + american / 100
          : 1 + 100 / american.abs();
      return total * legDecimal;
    });
    return decimal >= 2
        ? ((decimal - 1) * 100).round()
        : (-100 / (decimal - 1)).round();
  }

  String _formatOdds(int odds) => odds > 0 ? '+$odds' : '$odds';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: pageBackground,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: widget.props.isEmpty
                ? _buildEmptyState()
                : RawScrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 7,
                    radius: const Radius.circular(10),
                    thumbColor: gold,
                    trackColor: const Color(0xFF0A1620),
                    trackBorderColor: borderColor,
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(10, 6, 19, 10),
                      itemCount: widget.props.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final prop = widget.props[index];
                        return _SelectedPropCard(
                          prop: prop,
                          onRemove: () => widget.onRemove?.call(prop),
                        );
                      },
                    ),
                  ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: gold.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.people_alt_outlined, color: gold, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE SLIP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Review your selections',
                  style: TextStyle(color: mutedText, fontSize: 9),
                ),
              ],
            ),
          ),
          if (widget.props.isNotEmpty)
            IconButton(
              onPressed: widget.onClear == null
                  ? null
                  : () => widget.onClear!(),
              tooltip: 'Clear active slip',
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
            ),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: gold,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${widget.props.length}',
              style: TextStyle(
                color: Color(0xFF06111B),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, color: gold, size: 36),
            SizedBox(height: 11),
            Text(
              'No players selected',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Choose Over or Under on a player card to add it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText, height: 1.35, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: const BoxDecoration(
        color: raisedBackground,
        border: Border(top: BorderSide(color: borderColor)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'READY TO BUILD',
                    style: TextStyle(color: mutedText, fontSize: 7),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.props.length} ${widget.props.length == 1 ? 'PICK' : 'PICKS'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'ESTIMATED ODDS',
                    style: TextStyle(color: mutedText, fontSize: 7),
                  ),
                  Text(
                    _formatOdds(_estimatedOdds),
                    style: const TextStyle(
                      color: gold,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed:
                  widget.props.isEmpty ||
                      widget.isBuilding ||
                      widget.onBuildTicket == null
                  ? null
                  : () => widget.onBuildTicket!(),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                disabledBackgroundColor: const Color(0xFF35414A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: Text(
                widget.isBuilding ? 'BUILDING…' : 'BUILD TICKET',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedPropCard extends StatelessWidget {
  final SelectedProp prop;
  final VoidCallback onRemove;

  const _SelectedPropCard({required this.prop, required this.onRemove});

  static const cardBackground = Color(0xFF081722);
  static const raisedBackground = Color(0xFF0C1C28);
  static const borderColor = Color(0xFF273B49);
  static const gold = Color(0xFFFFC400);
  static const blue = Color(0xFF36B9FF);
  static const mutedText = Color(0xFF8EA0AD);

  bool get isOver => prop.selectedSide.toLowerCase() == 'over';
  String formatOdds(int odds) => odds > 0 ? '+$odds' : '$odds';

  Widget _playerImage() {
    if (prop.imageUrl.startsWith('assets/')) {
      return Image.asset(
        prop.imageUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.person, color: Colors.white54),
      );
    }
    if (prop.imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: prop.imageUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorWidget: (_, _, _) =>
            const Icon(Icons.person, color: Colors.white54),
      );
    }
    return const Icon(Icons.person, color: Colors.white54);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 7, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      prop.propType.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: blue,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    prop.gameTime,
                    style: const TextStyle(color: Colors.white, fontSize: 7),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    tooltip: 'Remove player',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 27,
                      height: 27,
                    ),
                    icon: const Icon(Icons.close, color: gold, size: 16),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF34495A)),
                    ),
                    child: ClipOval(child: _playerImage()),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prop.playerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            prop.team,
                            prop.position,
                          ].where((value) => value.isNotEmpty).join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: mutedText, fontSize: 7),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          prop.sportsbook.toUpperCase(),
                          style: const TextStyle(
                            color: gold,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: raisedBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF34495A)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _sideLabel(
                      '▲ OVER',
                      isOver ? blue : Colors.transparent,
                    ),
                  ),
                  SizedBox(
                    width: 55,
                    child: Text(
                      prop.line.toStringAsFixed(
                        prop.line == prop.line.roundToDouble() ? 0 : 1,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _sideLabel(
                      '▼ UNDER',
                      !isOver ? blue : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: _metric(
                      'EDGE',
                      '+${prop.edge.toStringAsFixed(1)}%',
                      blue,
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      'HIT RATE',
                      '${prop.hitRate}%',
                      Colors.white,
                    ),
                  ),
                  Expanded(
                    child: _metric('LIVE', formatOdds(prop.liveOdds), gold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideLabel(String text, Color color) {
    return Container(
      height: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: .58)),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 7,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: mutedText, fontSize: 6)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
