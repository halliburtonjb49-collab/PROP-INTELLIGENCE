import '../services/auth_manager.dart';

enum MemberIdentityRole {
  user,
  core,
  pro,
  proFounder,
  admin,
  owner;

  static MemberIdentityRole fromValues({
    required String accountRole,
    String? assignedRole,
    SubscriptionTier subscriptionTier = SubscriptionTier.free,
  }) {
    final account = accountRole.trim().toLowerCase();
    if (account == 'owner') return owner;
    if (account == 'admin') return admin;
    return switch (assignedRole?.trim().toLowerCase()) {
      'pro_founder' => proFounder,
      'pro' || 'edge' => pro,
      'core' => core,
      _ => switch (subscriptionTier) {
        SubscriptionTier.edge => pro,
        SubscriptionTier.core => core,
        SubscriptionTier.free => user,
      },
    };
  }

  String get databaseValue => switch (this) {
    proFounder => 'pro_founder',
    _ => name,
  };

  String get label => switch (this) {
    user => 'MEMBER',
    core => 'CORE',
    pro => 'PRO',
    proFounder => 'PRO FOUNDER',
    admin => 'ADMIN',
    owner => 'OWNER',
  };

  String? get assetPath => switch (this) {
    core => 'assets/branding/founder_roles/core.png',
    pro => 'assets/branding/founder_roles/pro.png',
    proFounder => 'assets/branding/founder_roles/pro_founder.png',
    admin => 'assets/branding/founder_roles/admin.png',
    owner => 'assets/branding/founder_roles/owner.png',
    user => null,
  };

  String get description => switch (this) {
    user => 'Registered PROP INTELLIGENCE member.',
    core => 'Core access granted by subscription or directly by the owner.',
    pro => 'Full Pro access granted by subscription or directly by the owner.',
    proFounder =>
      'Numbered founding member with complimentary full Pro access.',
    admin =>
      'Staff administrator. May request application changes for owner approval.',
    owner =>
      'Verified owner. The only role permitted to approve application changes.',
  };
}

SubscriptionTier grantedTierForRole(String? assignedRole) =>
    switch (assignedRole?.trim().toLowerCase()) {
      'core' => SubscriptionTier.core,
      'pro' || 'pro_founder' || 'edge' => SubscriptionTier.edge,
      _ => SubscriptionTier.free,
    };

SubscriptionTier highestSubscriptionTier(
  SubscriptionTier paid,
  SubscriptionTier granted,
) => paid.index >= granted.index ? paid : granted;
