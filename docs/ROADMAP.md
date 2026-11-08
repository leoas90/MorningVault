# MorningVault — product roadmap and execution plan

Written 2026-11-07. Owner: Yezid. Builder: Hermes (with delegated subagents). Source of truth for this plan is this file; update it in place.

## 1. Where we are

- iPhone app on TestFlight, build 57 building from `3e0ec7a`. iOS 26+. Swift 6, SwiftUI, no third-party SDKs.
- Four tabs: Brief (weather, AI day summary, next events, changes since yesterday, markets, health, headlines, spoken brief), Markets (watchlist with real intraday sparklines, entry price and P&L), Meetings (record, live transcript, speaker separation, on-device summary and action items, widgets and Live Activity), Settings.
- Everything personal stays on the phone. The only server is the price proxy at `api.morningvault.app` (Cloudflare Worker, no keys, 5-minute cache).
- Design: "editorial morning paper". Serif display type, warm canvas, full-bleed sky that follows the real hour and weather, one continuous flow with hairlines, no card boxes. New app icon (dark dawn). Design rules live in `MorningVault/Views/Components/DesignSystem.swift`.
- App Store Connect: app record exists, age rating 12+, privacy "Data Not Collected". Not submitted.

What is unproven: everything above has been verified by builds, tests and simulator previews. Real-device verification of recording, transcription, the 6:55 background refresh, widgets and the Live Activity rests on Yezid's phone.

## 2. Product thesis

One app that answers "what do I need to know this morning, and what needs me today" for a traveling sales manager, without sending a byte of personal data anywhere. Three jobs:

1. **Brief**: the morning read in 20 seconds (screen or voice).
2. **Meetings**: capture the meeting in the car or the room, get notes and action items without typing.
3. **Markets**: the few positions you care about, at a glance, no brokerage login.

Non-goals: social features, accounts, cloud sync beyond iCloud key-value, Android, a Mac app (until Meetings on Mac is wanted for video calls).

## 3. Roadmap

### M1. Stable daily driver (now to 2026-11-21)

Goal: Yezid uses it every morning for two weeks without a crash or a wrong fact.

- Field-verify on device: morning background refresh at the briefing time (watch for the Swift 6 isolation crash class), Kokoro voice start time and fallback, widget timeline, Meetings record/pause/stop/Live Activity, zoom transition back to the live block.
- Markets: confirm the daily-change fix (vs yesterday's close) against Robinhood numbers; add "market closed / pre-market" state to the Updated line.
- Brief: regenerate the AI summary when the calendar changes after 6 a.m.; show "last refreshed" honestly; empty states per source (already) tested on device.
- Bugs found in the field get fixed the same day; nothing new ships to the Brief until the two weeks are clean.
- Exit criteria: 10 consecutive mornings with a correct brief, zero crash reports in App Store Connect.

### M2. App Store 1.0 (2026-11-22 to 2026-12-12)

Goal: public listing, free, no account.

- Yezid: 3 to 5 screenshots on the 16 Pro Max (Brief, Meetings recording, Markets, widget), enroll in the Small Business Program, confirm the privacy questionnaire.
- Hermes: upload screenshots via the API, App Store description and keywords in the app's voice, review notes explaining on-device processing and the price proxy, Privacy manifest check, Accessibility pass (Dynamic Type at AX sizes, VoiceOver labels on the Brief and Meetings), Reduce Motion pass.
- Onboarding: one screen per permission with a reason, "Your voice" enrollment prompt, skip everywhere.
- Settings: Sources editor reachable from the Headlines block (open item from the November review), "Saved" headlines or remove the action.
- Exit criteria: approved by App Review; 1.0 on the store.

### M3. Meetings that pay for themselves (2026-12-13 to 2027-01-16)

Goal: the recorder becomes the reason to open the app during the day.

- Partial saves every minute and on pause (no lost recordings on a crash).
- Transcript timestamps with tap-to-seek playback.
- Streaming enhanced notes while the summary is written.
- Action items to Reminders in one tap with owner and due date; "yesterday's open items" on the Brief as tappable rows (data already flows).
- Calendar-aware: meeting title, attendees and talking points prefilled from the event; Siri "Start a meeting" from the car.
- Export: Markdown and share sheet; optional iCloud Drive folder so the Mac agents can read notes.
- Exit criteria: Yezid records three real meetings a week and uses the action items.

### M4. The brief gets smarter (2027-01-17 to 2027-02-27)

Goal: the summary reads like a chief of staff wrote it.

- Private Cloud Compute path (compiled out behind `PCC_ENABLED`) once Apple grants the entitlement, used only when the on-device model declines; still no third-party servers.
- Headline gists from the on-device model (already partly there), source quality ranking, "why this matters to you" when a headline touches a tracked symbol or a calendar company.
- Commute line: leave-by time for the first event using MapKit ETA, on device.
- Health: trend lines (7-day sleep, HRV) instead of single numbers; honest labeling.
- Price alerts: wire or delete the anomaly service (currently dead code). If wired: on-device threshold alerts from the proxy, no push server.

### M5. Reach (2027-03 onward, decide after M2 data)

- Mac companion for video-call capture (ScreenCaptureKit), sharing the Meetings package.
- iPad layout.
- Localization: Spanish first.
- Paid tier only if there is a real cost to cover (PCC usage or a paid data feed). Default stays free.

## 4. Execution plan

### Cadence

- One TestFlight build per working day at most, from `main`. Xcode Cloud builds on push; builds are numbered by CI.
- Weekly: Sunday evening, Hermes posts a one-screen status to Telegram: what shipped, what Yezid should test on the phone, what's blocked.
- Design changes go through the preview-and-review loop (render, strict reviewer, fix) before merge. Standing rules: no rounded containers, one flow with hairlines, serif only for display, SF Symbols only, accent for one control per screen.

### Division of labor

- Yezid: phone testing and feedback, screenshots, Apple account actions (Small Business Program, privacy questionnaire, PCC entitlement follow-up), taste calls on design.
- Hermes: everything in the repo, the Worker, App Store Connect via API, crash triage from TestFlight feedback, this document.

### Quality gates (every merge)

- Release build of app and widget with zero errors; package tests green (the one EPERM test is environmental).
- No raw `UIColor { }` providers; grep before merge (crash class from builds 37, 45, 46, 47).
- Previews render for every changed screen, light and dark.
- No new permission without an onboarding reason and a privacy-manifest entry.

### Risks

- Apple review on "Data Not Collected" with a network call: mitigated by review notes (only ticker symbols leave the phone).
- Kokoro on iOS 27 (FluidAudio advisory): guard already trips to the system voice after two failures; keep it.
- Yahoo's unofficial chart endpoint: if it breaks, swap the Worker to another source without an app update.
- Single tester: field bugs surface slowly. Add 2 to 3 TestFlight testers in M2 (Anna, one colleague).

## 5. Decisions (2026-11-07, Yezid)

1. App Store 1.0 target: 2026-12-12.
2. Price alerts: wire them (M4), on-device thresholds, no push server.
3. External testers in M2: Anna and Omar.
4. Mac companion: yes, planned for 2027 Q1 (M5 moves earlier for Mac only).

## 6. Monetization (proposed, pending Yezid's pricing call)

Recommendation: freemium with a subscription, no ads. Ads would require an ad SDK that tracks users, which breaks the "Data Not Collected" label, triggers the App Tracking Transparency prompt, and contradicts the product's whole promise. At this audience size ad revenue would be cents.

- Free: full Brief (weather, calendar, AI summary, headlines, spoken brief), Markets up to 3 symbols, Meetings up to 3 recordings a month, small widget.
- Pro (proposed $4.99/month or $39.99/year, 7-day free trial, Family Sharing on): unlimited Meetings with speaker labels and Reminders export, 10 symbols with price alerts, all widget sizes and the Live Activity, the Mac companion, Private Cloud Compute summaries when available.
- Implementation: StoreKit 2 subscriptions verified on device (no server, no account), one paywall screen in the app's design language, restore purchases in Settings. Small Business Program keeps Apple's cut at 15%.
- Timing: ship 1.0 free on 2026-12-12 to collect usage; turn on Pro with M3 (Meetings) in January, so the paid tier launches with the feature that justifies it.

## 7. Running cost at scale (estimate, 2026-11-07)

Pricing approved by Yezid: Free + Pro $4.99/mo or $39.99/yr. Assumptions: ~150 WeatherKit calls per user per month (weather cached 30 min, a few opens a day plus the morning refresh), ~180 price-proxy requests per user per month, 3% of users pay, ~$34/yr net per payer after Apple's 15%.

| Monthly users | WeatherKit | Worker | Market data license | Est. Pro revenue/mo |
|---|---|---|---|---|
| 1,000 | $0 (free tier) | $5 | needed before App Store | ~$85 |
| 10,000 | $100 | $5 | TBD | ~$850 |
| 100,000 | $1,000 | ~$10 | TBD | ~$8,500 |
| 1,000,000 | $7,500 | ~$60 | TBD | ~$85,000 |

Fixed: Apple Developer $99/yr, domain ~$15/yr. On-device AI, voice and transcription cost nothing to run. Private Cloud Compute pricing for developers is unpublished.

Actions: (1) replace Yahoo with a licensed quote feed before 1.0 (Yahoo's endpoint is not licensed for commercial redistribution); get quotes for delayed data. (2) Cut WeatherKit calls ~60% by fetching only when older than 60 min. (3) Set Cloudflare and WeatherKit billing alerts.
