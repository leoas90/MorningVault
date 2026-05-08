# Privacy-First Morning Vaulting App - SPEC v2

## Overview
A privacy-first iOS application that delivers a personalized morning briefing using on-device processing, minimizing data exposure while providing weather, market insights, and personalized recommendations.

**Hard deadline:** v1.0 live before WWDC 2026 (June 8)

---

## Core Privacy Principles
1. **Data Minimization**: Only collect and process data necessary for the briefing
2. **On-Device Processing**: Maximize local processing using Apple's Foundation Models framework
3. **Local First**: Prefer local data sources and caching over external APIs
4. **Transparency**: Clear indication of what data is processed locally vs. externally
5. **No Tracking**: No analytics, telemetry, or user profiling

---

## Architecture Components

### Data Sources (Prioritized by Privacy)
- **Local First**: Device sensors (time, approximate location only), local cache, on-device Foundation Models (~3B parameter model)
- **Privacy-Preserving External**: Weather (approximate location), market data (public endpoints), RSS feeds (no user-specific tracking)
- **Opt-in External**: IMAP OAuth2 email (read-only, user-activated, separate privacy consent)

### Processing Pipeline
```
Data Collection → Local Preprocessing → On-Device AI Enhancement → Template Formatting → Delivery
```

### On-Device AI Features (Foundation Models Framework)
- **Summarization**: Condense lengthy research/articles into key points
- **Classification**: Categorize market sentiment, news relevance
- **Extraction**: Pull key metrics from raw data
- **Generation**: Create personalized insights based on user patterns (stored locally)
- **Constrained Generation**: `StructuredOutput` with `Schema` types — Swift `Codable` struct passed via `.structuredOutput()`, NOT raw JSON schema strings

### Modules
- **Weather Module**: Approximate location (city-level) + wttr.in `~city` (no GPS coords)
- **Market Module**: BTC via CoinGecko ⚠️ legal flag (see LEGAL.md), SPY/QQQ — CoinGecko paid plan or legal sign-off before App Store submission; local caching
- **Health Module**: HealthKit — sleep, step count, HRV (read-only, always local)
- **Calendar Module**: EventKit — today's events (always local)
- **RSS Module**: FeedKit, 2–3 hardcoded feeds
- **Email Module**: IMAP OAuth2 via `ASWebAuthenticationSession` — **OPT-IN**, separate privacy consent
- **Build Task Module**: Formats the day's technical/business objective from OpenClaw
- **System Status**: OpenClaw agent health (local only)

### Data Flow & Storage
- **Ephemeral**: Raw API responses discarded after processing
- **Cached**: Non-PII data cached locally with per-source TTLs (see Fallback Chain below)
- **User Preferences**: Stored locally in Keychain (credentials) / UserDefaults (settings)
- **Research Insights**: Processed and summarized, raw research not retained
- **No Cloud Sync**: All data remains on device unless explicitly shared

### External Dependencies
- **Weather**: wttr.in `~city` (approximate location, no lat/lon)
- **Market Data**: ⚠️ Yahoo Finance / yfinance — legal flag active: yfinance is a scraping library with no authorized API ToS for third-party display. CoinGecko has an explicit ToS. Resolution required: CoinGecko paid plan OR explicit legal sign-off on scraping risk before launch.
- **RSS**: FeedKit (SPM), 2–3 hardcoded feeds, no auth
- **Email**: IMAP over TLS via `ASWebAuthenticationSession` OAuth2 — opt-in only

---

## Fallback Chain (Explicit TTLs)

| Source | Fresh TTL | Stale Window | After Stale → |
|--------|-----------|--------------|---------------|
| Weather | 30 min | up to 2 hr | Hardcoded placeholder |
| Market | 5 min | up to 15 min | "market data unavailable" |
| RSS | 1 hr | up to 4 hr | Skip section |
| HealthKit | Always local | — | n/a |
| Calendar | Always local | — | n/a |
| Email | 15 min | up to 1 hr | Skip email section |

---

## v1 Scope

### ✅ IN
- HealthKit (sleep, steps, HRV — read-only)
- EventKit (today's calendar)
- WeatherKit / wttr.in (approximate location)
- RSS (FeedKit, 2–3 feeds)
- Foundation Models AI (on-device)
- AlarmKit (recurring 7AM weekday alarm)
- Local-only mode

### ❌ OUT (v2)
- Email/MailKit (deferred — IMAP OAuth2 path validated but opt-in only for v1)
- Custom model download (v2 ANEMLL)
- Nexa SDK (Android pivot)

### 🔄 FALLBACK
- AlarmKit → Local Notifications if Gate 0 fails

---

## Privacy Manifest (PrivacyInfo.xcprivacy)
```xml
<!-- REQUIRED — Apple rejects apps without this file -->
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyTrackingDomains</key><array/> <!-- empty — no tracking -->
<key>NSPrivacyCollectedDataTypes</key><array/> <!-- no data collection -->
<key>NSPrivacyAccessedAPIType</key>
<!-- HealthKit: read sleep/activity/HRV (no write) -->
<!-- Location: approximate only (city-level, ~1km, no GPS) -->
```
⚠️ Positioning: **"Designed with HIPAA principles"** — NOT "HIPAA-compliant" (App Store risk)

**Privacy policy page language:**
> "Location data is used solely for weather queries, approximated to ~1km, cached locally, and never transmitted with any user identifier."
> "All health data stays on your device. Morning Vault processes health information locally via Apple Intelligence and does not transmit it to any external service."
> "We do not collect, store, or transmit any personal information."

---

## Implementation Roadmap

### GATE 0 — Validation (Week 1, May 7–14)

| # | Item | Owner | Status |
|---|------|-------|--------|
| 1 | AlarmKit custom UI | Derick | ✅ VALIDATED — "View Brief" → AppIntent → deep link confirmed as correct UX |
| 2 | Foundation Models + HealthKit | Derick | ✅ Device available — iPhone Y (iOS arm64). FM spike moves to GATE 3 |
| 3 | IMAP OAuth2 | — | ✅ VALID — ASWebAuthenticationSession → OAuth2 → IMAP over TLS, opt-in v1 |

### GATE 1 — Project Setup (Week 2, May 14–21)
- [x] XcodeGen `project.yml` — iOS 26.1 minimum, A17 Pro+ target
- [x] SPM: Foundation Models, HealthKit, WeatherKit, FeedKit (in project.yml)
- [x] Entitlements: HealthKit, Calendar, WeatherKit, App Intents
- [x] Git repo + CI (Xcode Cloud or GitHub Actions) — **TODO: verify**
- [x] `PrivacyInfo.xcprivacy` manifest — EXISTS at `Resources/PrivacyInfo.xcprivacy`
- [x] Build: ✅ **BUILD SUCCEEDED** (MorningVault.xcodeproj)
- [x] Bundle ID: `com.yeziddr.morningvault.dev`
- [x] Target: iOS 26.1
- [x] Physical device available: iPhone Y (iOS arm64) ✅

**GATE 1 — Project Setup (Week 2, May 14–21) — ✅ CLOSED**
- [x] All items complete. Build succeeds. Physical device available.

**GATE 2 pending (opt-in, not blocking):**
- [ ] HealthKit module: `HKHealthStore` read (sleep, steps, HRV)
- [ ] EventKit module: `EKEventStore` fullAccess, today's events
- [ ] Weather module: approximate location → `CLGeocoder` city name → wttr.in `~city`
- [ ] RSS parser: FeedKit SPM, 2–3 hardcoded feeds
- [ ] Cache layer: `FileManager` `.cachesDirectory` + JSON files + `.expiry` metadata (NOT UserDefaults for blobs)
  - Source TTLs from Python `cache.py`: weather=1800s, market=300s, research=3600s
- [ ] Fallback chain: see Fallback Chain table above
- [ ] IMAP OAuth2: `ASWebAuthenticationSession` + NIO IMAP client, read-only scope, opt-in

### GATE 3 — AI Layer (Week 3–4, May 21–Jun 1)

**⚠️ CRITICAL PATH — route to Claude Code**

- [ ] **Foundation Models wiring:** Replace `aiText = nil` placeholder in `BriefingViewModel` with `LanguageModelSession` from iOS 26 SDK
  - Use `Schema` types + `StructuredOutput` (NOT raw JSON schema strings) — per GATE 3 spec
  - Swift `Codable` struct → `.structuredOutput()` on model session
  - Chunk data sources into ~4K token segments (Health 500t, Calendar 800t, Weather 200t, Markets 300t, RSS 2Kt)
- [ ] **Summarization prompt:** "Summarize into 3 bullets: [data]"
- [ ] **Market sentiment:** BTC/SPY → bullish/bearish/neutral classification
- [ ] **Latency target:** **<5s on 6:55 AM precomputation run** (not on alarm fire)
- [ ] **Test on physical device** (iPhone Y available) — simulator FM availability limited

### GATE 4 — Delivery & UI (Week 4, Jun 1–4)
- [ ] **6:55 AM precomputation** — `BGTaskScheduler` or background app refresh generates brief BEFORE alarm fires
- [ ] AlarmKit flow (v1 confirmed — NOT deferred to v1.1):
  1. 6:55 AM → background task precomputes full brief → caches to `.cachesDirectory`
  2. 7:00 AM alarm fires → system shows custom title "Morning Vault ☀️" + "View Brief" button
  3. User taps "View Brief" → `ViewBriefIntent` fires → app opens to `BriefingView`
  4. `BriefingView` loads from cache → instant display (no spinner)
- [ ] BriefingView: scrollable, sectioned, dark mode. **Priority stack (default order):**
  1. 🌤️ Weather (always useful, glanceable)
  2. ❤️ Health snapshot (sleep score, HRV, steps — "how am I" check)
  3. 📅 Calendar (today's events)
  4. 📈 Markets (BTC/SPY — trader audience)
  5. 📰 RSS headlines (if opted in)
  6. 🔧 Build task / system status (OpenClaw-specific)
  - Each section is a **self-contained `View` struct** — reorderable per user preference in Settings
- [ ] Settings screen: briefing time, data source toggles, privacy badge legend, local-only mode
- [ ] Local notification fallback (`UNUserNotificationCenter`) if AlarmKit fails

### GATE 5 — Privacy Hardening (Week 4, Jun 1–4)
- [ ] Network call audit: `grep -r "latitude\|longitude\|email\|CLLocation"` — zero PII in network calls
- [ ] `kCLLocationAccuracyKilometer` — city-level only, no background location
  - **Location caching rule:** Never call `CLLocationManager` again — reuse cached coordinates until >50km stale or expired
  - **WeatherKit:** API call sends lat/lon only, no device ID
  - **Privacy policy language:** "Location data is used solely for weather queries, approximated to ~1km, cached locally, and never transmitted with any user identifier."
  - Privacy win via: request km accuracy + cache city-level coords + pass cached coords to WeatherKit (not precise location)
- [ ] Network transparency badge (persists in nav bar):
  - 🟢 **LOCAL** — all on-device, zero network calls
  - 🟡 **ONLINE** — external fetches active (weather, market, RSS), no PII transmitted
  - ⚠️ **EMAIL** — IMAP connection active (opt-in only, user explicitly enabled)
  - Tap badge → popover showing exact active connections + data flow per source
  - **Competitive differentiator** — no comparable app in market has real-time network transparency
- [ ] Keychain: RSS auth tokens, IMAP OAuth tokens (biometric unlock optional)
- [ ] "Local-Only Mode" toggle — disables all external fetches, cache-only

### GATE 6 — App Store Prep (Jun 4–6)
- [ ] Privacy labels: HealthKit=YES(read), Analytics=NO, Tracking=NO, Location=Approximate
- [ ] "Designed with HIPAA principles" (NOT "HIPAA-compliant")
- [ ] Screenshots: 6.7" + 6.1" (iPhone 16 Pro, iPhone 16) — alarm → briefing → settings walkthrough
- [ ] App preview video: 30s walkthrough
- [ ] Privacy policy page (model on Risi.ai zero-collection language)
- [ ] TestFlight: internal team first

### GATE 7 — Ship (Jun 6–7)
- [ ] Submit to App Store (HealthKit = 2–3 day extra review buffer)
- [ ] If rejected: on-device-only processing = strongest review argument
- [ ] **v1.0 live before June 8 WWDC keynote**

---

## Success Metrics
- **Privacy**: Zero PII transmitted externally during normal operation
- **Reliability**: >95% successful brief generation (<5s on precomputation)
- **User Value**: Actionable insights delivered consistently
- **Battery Impact**: <5% daily drain from brief generation
- **Offline Functionality**: Core brief available with cached data

---

## Open Questions (resolved)
1. ~~Exact timing for daily brief generation~~ → 6:55 AM background precomputation, alarm at 7:00 AM
2. ~~Delivery mechanism~~ → AlarmKit primary, notification fallback
3. ~~Level of personalization vs. privacy trade-offs~~ → Local-only mode for max privacy users
4. ~~Email/MailKit access~~ → IMAP OAuth2 validated, opt-in for v1