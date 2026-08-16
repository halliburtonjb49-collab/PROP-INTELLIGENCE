import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/prop_board_engine.dart';

PropData _prop(
  String id, {
  String player = 'Test Player',
  String sport = 'NBA',
  String sportsbook = 'Prize Picks',
  String sourceProvider = '',
  String market = 'Points',
  String marketName = '',
  String startTimeUtc = '2099-07-20T20:00:00Z',
  String decision = 'WAIT',
  bool actionable = false,
  bool selectable = true,
  int confidence = 50,
}) {
  return PropData.fromJson({
    'id': id,
    'player': player,
    'sport': sport,
    'sportsbook': sportsbook,
    'sourceProvider': sourceProvider,
    'market': market,
    'market_name': marketName,
    'category': market,
    'startTimeUtc': startTimeUtc,
    'confidence': confidence,
    'selectable': selectable,
    'verdict': {
      'decision': decision,
      'actionable': actionable,
      'confidence': confidence,
    },
  });
}

List<PropData> _query(
  Iterable<PropData> props, {
  String sport = 'ALL',
  String site = 'ALL',
  String search = '',
  String verdict = 'ALL',
  String sortBy = 'source',
  Set<String> pinned = const {},
}) {
  return filterAndSortBoardProps(
    prepareBoardProps(props),
    selectedSport: sport,
    selectedSite: site,
    searchQuery: search,
    verdictFilter: verdict,
    sortBy: sortBy,
    pinnedPropIds: pinned,
  );
}

void main() {
  test('normalizes provider and sport aliases used by live feeds', () {
    expect(normalizePropSite('Prize Picks'), 'PRIZEPICKS');
    expect(normalizePropSite('DraftKings Pick6'), 'PICK6');
    expect(normalizePropSport('soccer_usa_mls'), 'SOCCER');
    expect(normalizePropSport('basketball_wnba'), 'WNBA');
    expect(normalizePropSport('basketball_ncaab'), 'NCAAB');
    expect(normalizePropSport('americanfootball_ncaaf'), 'NCAAF');
    expect(normalizePropSport('americanfootball_cfl'), 'CFL');
  });

  test('filters by site, sport and search and excludes unsafe props', () {
    final matching = _prop(
      'matching',
      player: 'Alyssa Thomas',
      sport: 'basketball_wnba',
      sportsbook: 'PrizePicks',
      market: 'Other',
      marketName: 'Rebounds',
    );
    final wrongSite = _prop(
      'wrong-site',
      player: 'Alyssa Thomas',
      sport: 'WNBA',
      sportsbook: 'Underdog',
      market: 'Rebounds',
    );
    final unsafe = _prop(
      'unsafe',
      player: 'Alyssa Thomas',
      sport: 'WNBA',
      sportsbook: 'PrizePicks',
      market: 'Rebounds',
      selectable: false,
    );

    final result = _query(
      [wrongSite, unsafe, matching],
      sport: 'WNBA',
      site: 'Prize Picks',
      search: 'rebounds',
    );

    expect(result.map((prop) => prop.id), ['matching']);
  });

  test('actionable filter uses the backend verdict contract', () {
    final play = _prop('play', decision: 'PLAY_NOW', actionable: true);
    final shop = _prop('shop', decision: 'SHOP', actionable: true);
    final wait = _prop('wait', decision: 'WAIT');

    expect(
      _query([
        wait,
        shop,
        play,
      ], verdict: 'ACTIONABLE').map((prop) => prop.id).toSet(),
      {'play', 'shop'},
    );
  });

  test('verdict sorting follows the board action hierarchy', () {
    final result = _query([
      _prop('pass', decision: 'PASS'),
      _prop('lean', decision: 'LEAN'),
      _prop('play', decision: 'PLAY_NOW'),
      _prop('wait', decision: 'WAIT'),
      _prop('shop', decision: 'SHOP'),
    ], sortBy: 'verdict');

    expect(result.map((prop) => prop.id), [
      'play',
      'shop',
      'lean',
      'wait',
      'pass',
    ]);
  });

  test('time sorting keeps undated props last', () {
    final result = _query([
      _prop('missing', startTimeUtc: ''),
      _prop('late', startTimeUtc: '2099-07-22T20:00:00Z'),
      _prop('early', startTimeUtc: '2099-07-20T20:00:00Z'),
    ]);

    expect(result.map((prop) => prop.id), ['early', 'late', 'missing']);
  });

  test('selected props remain chronological across different start times', () {
    final result = _query(
      [
        _prop('late', startTimeUtc: '2099-07-22T20:00:00Z'),
        _prop('early', startTimeUtc: '2099-07-20T20:00:00Z'),
        _prop('middle', startTimeUtc: '2099-07-21T20:00:00Z'),
      ],
      pinned: {'middle'},
    );

    expect(result.map((prop) => prop.id), ['early', 'middle', 'late']);
  });
  test('verdict ranking only breaks ties within the same start time', () {
    final result = _query([
      _prop(
        'later-play',
        decision: 'PLAY_NOW',
        startTimeUtc: '2099-07-21T20:00:00Z',
      ),
      _prop(
        'earlier-wait',
        decision: 'WAIT',
        startTimeUtc: '2099-07-20T20:00:00Z',
      ),
    ], sortBy: 'verdict');

    expect(result.map((prop) => prop.id), ['earlier-wait', 'later-play']);
  });

  test('board query helpers distinguish broad and narrowed states', () {
    expect(
      isNarrowedBoardQuery(
        sport: 'ALL',
        site: 'ALL',
        category: 'ALL',
        side: 'ALL',
        tier: 'ALL',
        search: '',
        minConfidence: 0,
      ),
      isFalse,
    );
    expect(
      hasActiveBoardFilters(
        sport: 'ALL',
        site: 'ALL',
        category: 'ALL',
        side: 'ALL',
        tier: 'ALL',
        verdict: 'PLAY_NOW',
        search: '',
        minConfidence: 0,
      ),
      isTrue,
    );
  });
}
