# Audit Checklist

Internal review before each release.

## Pre-Release Audit

### Privacy
- [ ] NSPrivacyTracking = false in PrivacyInfo.xcprivacy
- [ ] No `latitude`, `longitude`, `email`, or `CLLocation` in network calls (grep check)
- [ ] kCLLocationAccuracyKilometer used for weather location
- [ ] HealthKit data never transmitted externally
- [ ] No analytics or telemetry

### Legal
- [ ] CoinGecko ToS — paid plan active OR explicit sign-off documented
- [ ] Yahoo Finance replacement reviewed (paid provider or documented risk acceptance)
- [ ] Terms of Service current and legally reviewed
- [ ] Privacy Policy accurate and matches actual data practices

### App Store
- [ ] Screenshots: 6.7" (iPhone 16 Pro) and 6.1" (iPhone 16)
- [ ] App preview video: 30s walkthrough
- [ ] Privacy labels updated to match actual data collection
- [ ] "Designed with HIPAA principles" — NOT "HIPAA-compliant"
- [ ] HealthKit usage description in Info.plist
- [ ] Location usage description in Info.plist

### Build
- [ ] Release build succeeds (xcodebuild archive)
- [ ] No simulator-only code paths in release
- [ ] Privacy manifest present at build
- [ ] Bundle ID matches App Store Connect

### Testing
- [ ] Test notification fires on physical device
- [ ] Deep link `morningvault://briefing` opens correct view
- [ ] BGTaskScheduler precomputation completes before alarm
- [ ] Local-only mode disables all network calls
- [ ] Settings toggles reflect immediately in briefing

## Release Audit

- [ ] TestFlight internal build uploaded
- [ ] HealthKit entitlement active in provisioning profile
- [ ] Build certified with development certificate
- [ ] 2–3 day review buffer accounted for (HealthKit = longer review)