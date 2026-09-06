const bool piSyncManagerEnabled = bool.fromEnvironment(
  'PI_SYNC_MANAGER_ENABLED',
  defaultValue: false,
);

const bool piPropRevisionFeedEnabled = bool.fromEnvironment(
  'PI_PROP_REVISION_FEED_ENABLED',
  defaultValue: false,
);

bool syncManagerPathEnabled({bool? override}) =>
    override ?? piSyncManagerEnabled;

bool propRevisionFeedEnabled({bool? override}) =>
    override ?? piPropRevisionFeedEnabled;
