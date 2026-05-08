# App Store Compliance

Requirements for MorningVault listing on Apple App Store.

## Privacy Labels

| Data Type | Collected | Purpose | Shared with Third Parties |
|-----------|-----------|---------|--------------------------|
| Health | NO | N/A | N/A |
| Location | Approximate only | Weather queries | NO |
| Identifiers | None | N/A | N/A |
| Usage Data | NO | N/A | N/A |
| Contact Info | NO | N/A | N/A |
| Browsing History | NO | N/A | N/A |

## Privacy Manifest (PrivacyInfo.xcprivacy)

```xml
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyTrackingDomains</key><array/>
<key>NSPrivacyCollectedDataTypes</key><array/>
<key>NSPrivacyAccessedAPIType</key>
<!-- HealthKit: read sleep/activity/HRV only -->
<!-- Location: approximate, city-level, no GPS -->
```

## Required Disclosures

- HealthKit usage: "This app reads health data to include in your morning briefing"
- Location usage: "Used to provide local weather — approximated to city level, not precise GPS"
- Third-party SDKs: None that collect data

## App Store Review Guidance

**HealthKit review**: Apple scrutinizes HealthKit apps. Key talking points:
- Read-only, no health data leaves device
- Health data processed on-device via Apple Intelligence
- No sharing with third parties

**Location review**: Emphasize approximate city-level only. Demonstrate `kCLLocationAccuracyKilometer` usage.

**App naming**: "Morning Vault" — no medical claims.

## Rejection Risk Mitigation

- Avoid "HIPAA-compliant" — use "designed with HIPAA principles"
- No claim that app is a medical device
- No diagnostic or treatment claims based on health data
- Market data: include disclaimer that not financial advice

## Legal Flags to Resolve Before Submit

1. CoinGecko commercial ToS — requires paid API plan or explicit sign-off
2. Yahoo Finance scraping — no authorized API for third-party use; consider replacing with IEX Cloud or Alpha Vantage (both have free tiers)