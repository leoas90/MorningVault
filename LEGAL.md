# Legal Overview

MorningVault is a privacy-first morning briefing application designed with data minimization principles. All health and calendar data remains on-device. External calls (weather, market data, RSS) transmit no PII.

## Legal Documents

- **TERMS.md** — Application Terms of Service
- **PRIVACY.md** — Privacy Policy
- **3RD_PARTY.md** — Third-party service disclosures (CoinGecko, Yahoo Finance, wttr.in)
- **GDPR_ADDENDUM.md** — GDPR rights and compliance
- **APP_STORE_COMPLIANCE.md** — Apple App Store compliance requirements
- **COOKIES.md** — Cookie usage disclosure
- **ACCESSIBILITY.md** — Accessibility compliance (ADA, Section 508)
- **AUDIT_CHECKLIST.md** — Internal audit checklist
- **CHANGE_CONTROL.md** — Document change log procedure
- **INVENTORY.md** — Data inventory and processing records
- **INCIDENT_LOG.md** — Security incident log
- **INSURANCE.md** — Cyber liability coverage notes

## Key Compliance Positions

### Data Collection
- **Health data**: On-device only, never transmitted
- **Location**: Approximate (~1km city-level), used only for weather
- **Market data**: Public endpoint calls, no user identifiers
- **RSS**: No authentication, no user-specific tracking

### Legal Flags (Open)
- CoinGecko ToS: Free tier acceptable for personal use; paid plan recommended for distribution
- Yahoo Finance scraping: No authorized API for third-party display — yfinance is a scraping library
- Both flags require legal sign-off before App Store submission

### Privacy Positioning
- **DO**: "Designed with HIPAA principles"
- **NEVER**: "HIPAA-compliant" (requires formal certification)

## Third-Party Services

| Service | Purpose | Data Shared | ToS Risk |
|---------|---------|------------|---------|
| wttr.in | Weather | City name only | Low |
| CoinGecko | Crypto prices | Symbol, no PII | Medium |
| Yahoo Finance | Stock prices | Symbol, no PII | High |
| Apple HealthKit | Health data | None (on-device) | None |
| Apple EventKit | Calendar | None (on-device) | None |
| Apple Foundation Models | AI processing | None (on-device) | None |