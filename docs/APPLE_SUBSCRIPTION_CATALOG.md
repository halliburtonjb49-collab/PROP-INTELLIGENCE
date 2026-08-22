# Apple Subscription Catalog

Subscription group: `PI Memberships`

| Product | Product ID | Price | Trial | RevenueCat entitlement |
| --- | --- | ---: | ---: | --- |
| Core Monthly | `com.propintelligence.core.monthly` | $24.99/month | 3 days | `core` |
| Core Annual | `com.propintelligence.core.annual` | $249.99/year | 7 days | `core` |
| Pro Monthly | `com.propintelligence.pro.monthly` | $59.99/month | 3 days | `pro` |
| Pro Annual | `com.propintelligence.pro.annual` | $599.99/year | 7 days | `pro` |
| Founding Pro Monthly | `com.propintelligence.founding.monthly` | $49.99/month | 3 days | `pro` plus founding-member identity |
| Founding Pro Annual | `com.propintelligence.founding.annual` | $499.99/year | 7 days | `pro` plus founding-member identity |

## RevenueCat offering

Offering identifier: `default`

| Package | Product |
| --- | --- |
| `$rc_monthly_core` | Core Monthly |
| `$rc_annual_core` | Core Annual |
| `$rc_monthly` | Pro Monthly |
| `$rc_annual` | Pro Annual |
| `founding_monthly` | Founding Pro Monthly |
| `founding_annual` | Founding Pro Annual |

The Apple products, RevenueCat products, entitlements, and Render product-ID
environment variables must use these identifiers exactly. App Store Connect
remains the source of truth for localized price presentation and tax handling.

## Submission prerequisites

- Accept the Paid Apps Agreement.
- Complete banking and tax information.
- Add English display names and descriptions.
- Configure introductory trials for each product.
- Attach all products to the `PI Memberships` subscription group.
- Import the products into RevenueCat and attach the package mappings above.
- Test purchase, renewal, cancellation, restore, upgrade, and downgrade paths in sandbox/TestFlight.
