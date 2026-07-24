String userFacingLoadError(Object? error, {String noun = 'data'}) {
  final message = error?.toString().toLowerCase() ?? '';

  if (message.contains('timeout') || message.contains('timed out')) {
    return 'The $noun is taking longer than expected. Please retry in a moment.';
  }
  if (message.contains('401') ||
      message.contains('403') ||
      message.contains('unauthorized') ||
      message.contains('forbidden')) {
    return 'Your session may have expired. Sign in again, then retry.';
  }
  if (message.contains('clientexception') ||
      message.contains('socketexception') ||
      message.contains('failed to fetch') ||
      message.contains('failed host lookup') ||
      message.contains('connection refused') ||
      message.contains('unable to connect') ||
      message.contains('xmlhttprequest') ||
      message.contains('cors')) {
    return 'The $noun service is temporarily unavailable. Check your connection and retry.';
  }

  return 'We could not load the $noun right now. Please retry in a moment.';
}
