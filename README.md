# MorningVault

Privacy-first iPhone morning briefing. Four tabs: **Brief** (weather, health, calendar, headlines, markets, on-device AI summary), **Markets** (tracked symbols via the MorningVault proxy), **Meetings** (notes-first recorder with on-device transcription, speaker separation and summaries — `Packages/MeetingNotesKit`), **Settings**. Plus a Home/Lock Screen widget and Siri/Shortcuts intents that read the saved briefing.

Rule: the phone makes no third-party network calls. Weather is WeatherKit, markets go through `api.morningvault.app` only, RSS is fetched from the user's chosen feeds, AI runs on-device (Foundation Models), speaker diarization uses models bundled in the package (FluidAudio, Diarizer trait, no downloads).

- **Bundle ID:** `com.yeziddr.morningvault.dev` (widget: `.widget`, App Group `group.com.morningvault.app`)
- **Min iOS:** 26.0 (`project.yml`), Swift 6 strict concurrency
- **Project:** generated with XcodeGen — run `~/bin/xcodegen generate`, then open `MorningVault.xcodeproj` in Xcode 26
- **CI:** Xcode Cloud (`ci_scripts/`), push to `main` → TestFlight. The GitHub workflows under `.github/workflows` are disabled.
- **Backend:** `backend/` — FastAPI market proxy on Fly.io
- **Verify locally:** `xcodebuild -project MorningVault.xcodeproj -scheme MorningVault -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` and `cd Packages/MeetingNotesKit && swift test`
- **Docs:** `SPEC.md` is the original pre-build plan (historical); `docs/` holds reviews.
