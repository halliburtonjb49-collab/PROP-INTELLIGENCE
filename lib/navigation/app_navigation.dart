import 'package:flutter/material.dart';

import '../services/auth_manager.dart';

enum AppPage {
  board,
  briefing,
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
  injuryImpact,
  dataAdmin,
  ownerOperations,
  intelligenceLab,
  refereeTracker,
  propChat,
  trackRecord,
}

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
  AppPage.injuryImpact ||
  AppPage.scoreboardWatchlist ||
  AppPage.propAlerts ||
  AppPage.intelligenceLab ||
  AppPage.refereeTracker => SubscriptionTier.edge,
  _ => null,
};

bool canAccessOwnerOperations(String role) =>
    role.trim().toLowerCase() == 'owner';

SubscriptionTier displayedTierForBadge({
  required SubscriptionTier requiredTier,
  required bool hasEdgeAccess,
  bool hasProUpgrade = false,
}) {
  if (hasProUpgrade && hasEdgeAccess) {
    return SubscriptionTier.edge;
  }
  return requiredTier;
}

typedef AppNavigationGroup = (
  String label,
  IconData icon,
  List<(String label, AppPage page)> entries,
);

const List<AppNavigationGroup> appNavigationGroups = [
  (
    'RESEARCH',
    Icons.travel_explore_rounded,
    [
      ("Today's Briefing", AppPage.briefing),
      ('Board', AppPage.board),
      ('Search Players', AppPage.searchPlayers),
      ('EV Scanner', AppPage.evScanner),
      ('Line Movement', AppPage.lineMovement),
      ('Injury Impact', AppPage.injuryImpact),
      ('Analytics', AppPage.analytics),
      ('Intelligence Lab', AppPage.intelligenceLab),
      ('Referee Tracker', AppPage.refereeTracker),
      ('Prop Chat', AppPage.propChat),
    ],
  ),
  (
    'BUILD',
    Icons.construction_rounded,
    [
      ('Prop Builder', AppPage.propBuilder),
      ('Slip Watcher', AppPage.watchlist),
      ('Prop Alerts', AppPage.propAlerts),
      ('Builder Performance', AppPage.builderPerformance),
      ('Strikeout Pro Gold', AppPage.strikeoutProGold),
    ],
  ),
  (
    'LIVE',
    Icons.sensors_rounded,
    [
      ('Scoreboard', AppPage.scoreboard),
      ('Score Watch', AppPage.scoreboardWatchlist),
    ],
  ),
  (
    'HISTORY',
    Icons.history_rounded,
    [
      ('Past Slip History', AppPage.pastSlipHistory),
      ('Track Record', AppPage.trackRecord),
    ],
  ),
  ('SPORTS', Icons.sports_rounded, [('Moneyline', AppPage.gameMarkets)]),
];

String appPageHowTo(AppPage page) => switch (page) {
  AppPage.board =>
    'Use the sport, category and prop-site filters to narrow today\'s board. Compare the posted line with the projection, edge and confidence, then choose Over or Under to add a prop to the active tracking slip.',
  AppPage.gameMarkets =>
    'Choose a sport and game, then compare moneyline, spread, and total prices across sites. Use the best available number and confirm it again with the named prop site.',
  AppPage.propBuilder =>
    'Select sports, prop sites and categories, set your minimum edge and confidence, then build. Review the recommended 3-6 leg size and remove or replace any leg before saving the slip.',
  AppPage.watchlist =>
    'Saved slips appear here automatically while they\'re still unresolved. Refresh to update live scoring, and once a slip is marked Won or Lost it moves to Past Slip History.',
  AppPage.pastSlipHistory =>
    'Resolved research tickets live here. Use All, Won, and Lost to filter and review totals and tracked results.',
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
  AppPage.injuryImpact =>
    'Start with blocked and high-severity alerts, then filter by sport. Review only the verified availability, role, usage, opportunity and with/without factors shown; recheck the live lineup before acting.',
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
  AppPage.trackRecord =>
    'Every graded pick the model has made, winners and losers, with the sample size beside each number. Rates stay hidden until enough picks have been graded to mean anything.',
  AppPage.briefing =>
    "Today's board reduced to what clears the bar, with what the board cannot tell you stated beside it. A day with nothing worth playing says so rather than promoting the best of a thin slate.",
};

String appPageTitle(AppPage page) => switch (page) {
  AppPage.board => 'MARKET BOARD',
  AppPage.gameMarkets => 'MONEYLINE',
  AppPage.scoreboard => 'LIVE SCOREBOARD',
  AppPage.scoreboardWatchlist => 'SCOREBOARD WATCHLIST',
  AppPage.analytics => 'PERFORMANCE ANALYTICS',
  AppPage.briefing => "TODAY'S PI BRIEFING",
  AppPage.trackRecord => 'TRACK RECORD',
  AppPage.lineMovement => 'LINE MOVEMENT',
  AppPage.injuryImpact => 'INJURY IMPACT',
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

String appPageSubtitle(AppPage page) => switch (page) {
  AppPage.board => 'Scan today’s markets and compare available value',
  AppPage.gameMarkets =>
    'Compare moneylines, spreads and totals across sportsbooks',
  AppPage.scoreboard => 'Follow live, upcoming and completed games',
  AppPage.scoreboardWatchlist =>
    'Quick-view watched games with live score and result alerts',
  AppPage.analytics => 'Analytics and owner data-management workspace',
  AppPage.briefing => "Today's board in one page, plays and caveats both",
  AppPage.trackRecord => 'Published model record, open to everyone',
  AppPage.lineMovement => 'Monitor number and price changes in real time',
  AppPage.injuryImpact =>
    'Verified availability, role, usage and teammate-context changes',
  AppPage.intelligenceLab => 'Stress-test correlation, context and scenarios',
  AppPage.refereeTracker =>
    'Compare sample-adjusted referee tendencies and assignments',
  AppPage.searchPlayers => 'Open focused player and market research',
  AppPage.propAlerts => 'Review monitored conditions and changes',
  AppPage.propBuilder => 'Build a disciplined, research-backed slip',
  AppPage.watchlist =>
    'Track live props, research-ticket results, and recorded performance',
  AppPage.pastSlipHistory => 'Review resolved slips, outcomes and performance',
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

String appPageTooltip(AppPage page, {required String fallback}) =>
    switch (page) {
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
      AppPage.lineMovement => 'Track changes across prop-site lines',
      AppPage.injuryImpact =>
        'Review verified availability and role-impact warnings',
      AppPage.intelligenceLab =>
        'Model correlation, scripts, and historical analogs',
      AppPage.refereeTracker => 'Compare NBA and WNBA officiating tendencies',
      AppPage.propChat => 'Chat with the PROP INTELLIGENCE community',
      _ => fallback,
    };
