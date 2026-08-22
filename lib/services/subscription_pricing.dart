/// Customer-facing subscription terms.
///
/// RevenueCat and the underlying store/Stripe products remain the source of
/// truth at checkout. Keep those products aligned with these published terms.
abstract final class SubscriptionPricing {
  static const coreMonthly = r'$24.99 / MONTH';
  static const proMonthly = r'$59.99 / MONTH';
  static const foundingProMonthly = r'$49.99 / MONTH';
  static const coreAnnual = r'$249.99 / YEAR';
  static const proAnnual = r'$599.99 / YEAR';
  static const foundingProAnnual = r'$499.99 / YEAR';

  static const monthlyTrialDays = 3;
  static const annualTrialDays = 7;
  static const foundingProMemberLimit = 100;

  static const monthlyTrialLabel = '3-DAY FREE TRIAL';
  static const annualTrialLabel = '7-DAY FREE TRIAL WITH ANNUAL';
}
