# MorningVault — iOS code review

**Scope:** `git log 3fcf939..HEAD` (6 commits, ~12.7k lines added). New `Packages/MeetingNotesKit` Swift package (recorder, on-device transcription, FluidAudio speaker diarization with bundled CoreML models, voice enrollment), its integration into MorningVault as a Meetings tab, a Units setting, briefing-side bug fixes, and a consistency/dead-code pass.

**Stack:** SwiftUI, Swift 6 strict concurrency, iOS 26 deployment target, Xcode 27.2 / iOS 27.2 SDK.
**Method:** read-only review. No files were modified. The package was compiled for macOS (`swift build`, succeeded) and for the iOS Simulator (`xcodebuild -scheme MeetingNotesKit -destination 'generic/platform=iOS Simulator'`, **BUILD SUCCEEDED**), so everything below is against code that actually builds. SDK headers and the pinned FluidAudio 0.18.2 source were read directly to confirm API semantics; two findings were confirmed by running the actual code.

---

## Verdict

**Ship-blocking fixes needed, but the architecture is sound.** The privacy posture is genuinely good — I found **no reachable network path** in `MeetingNotesKit` (the only `URL` use is `UIApplication.openSettingsURLString`), **no logging of personal content**, and the diarizer loads its models from the bundle via `MLModel(contentsOf:)` without touching FluidAudio's `ModelHub`. The real defects are concentrated in three places: a **duplication bug in the live transcript**, **silent data loss around action items and saved transcripts**, and **a data race in the fallback transcription path**.

Two of the top five are silent-corruption bugs that a user would experience as "the app lost my work" with no error shown.

---

## HIGH severity

### H1. Live transcript duplicates the finalised text
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Transcription/LiveTranscriber.swift:202-229`**

`apply(text:range:)` classifies a result as volatile by comparing `range.start` against `analyzer.volatileRange.start` (`CMTimeCompare(range.start, volatileRange.start) >= 0`). When a result is judged **final**, its text is appended to `finalText` — but `volatileText` is **never cleared** (the only writes are `= ""` in `reset()` at line 199 and `= text` at line 212). So the same phrase lands in `finalText` *and* stays in `volatileText`, and `text` (line 40-45) and `RecordingSession.join` (`Views/RecordingSession.swift:399-404`) concatenate both: `"final" + " " + "volatile"`.

This is the user-visible transcript for every meeting, and it is what gets persisted as `meeting.transcript` (`RecordingSession.swift:192`).

**Fix:** use the SDK's own finality flag instead of re-deriving it. `SpeechTranscriber.Result` conforms to `SpeechModuleResult`, and the SDK provides `public var isFinal: Bool` (verified in the iOS 27.2 `Speech.swiftinterface`, `extension Speech::SpeechModuleResult`). Track `isFinal` per result; on a final result, append to `finalText` **and clear `volatileText`**. Do not infer volatility from `volatileRange` — it is the analyser's *current* volatile window, not a property of the result you are holding.

### H2. Re-running "Enhance notes" silently wipes completed action items
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Storage/MeetingPersistence.swift:36-57`**, called from `Views/MeetingDetailScreen.swift:196` and `Views/RecordingSession.swift:285`

`replaceActionItems` deletes every `ActionItemRecord` for the meeting and re-inserts fresh ones. The new records default `isDone = false` and `exportedToReminders = false` (`Models/MeetingModels.swift:108-119`). A user who ticked off three action items and then ran "Enhance notes" again loses all three ticks, with no message. `isDone` is genuinely user state — it is written only in `Views/NotesComponents.swift:170` (`item.isDone.toggle()`).

**Fix:** reconcile by text instead of delete-and-reinsert. Match incoming items to existing rows (normalised title), update the payload in place, and preserve `isDone` / `exportedToReminders`. Only insert genuinely new items; only delete rows whose item no longer appears.

### H3. Data race in the fallback file-transcription path (`settled` + `task`)
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Transcription/FileTranscriptionService.swift:261-290`**

Inside `withCheckedThrowingContinuation`, `var settled = false` and `var task: SFSpeechRecognitionTask?` are captured by the recognition result handler and mutated from the Speech framework's callback thread, while the enclosing closure reads them. This is a genuine cross-thread race under Swift 6:

- `settled` is read and written on the handler thread with no synchronisation — two callbacks can both observe `settled == false` and both call `continuation.resume(...)`, which is a checked-continuation double-resume → **crash**.
- `task?.cancel()` is called from inside the handler while `task` is being assigned by the outer closure (`task = recognizer.recognitionTask(...)`). The handler can fire **before** the assignment completes, so `task` is still `nil` and the cancel is a no-op.
- The `task` variable is captured by the closure before it is initialised — Swift's definite-initialisation rules allow this only because it is a `var`, which is exactly why it is unsafe.

Note this path also has a **privacy dimension**: `request.requiresOnDeviceRecognition = true` (line 257) is correct and is the right guard, so the recognition itself stays on device.

**Fix:** move the mutable state into a small `final class` box protected by a lock, or use an `actor`/`@unchecked Sendable` holder with an atomic "settled" flag, and assign the task through a local that is only read after assignment. A minimal correct shape:

```swift
let state = TaskState()                     // final class, NSLock-guarded
let task = recognizer.recognitionTask(with: request) { result, error in
    guard state.claim() else { return }     // atomic test-and-set
    task?.cancel()
    ...
}
```

Capture `task` after the assignment by reading it through `state` rather than through the captured `var`.

### H4. Meeting transcripts are copied into the shared App Group and never deleted
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Storage/AppGroupMarkdownWriter.swift:23-33`** (writer), **`Views/HomeScreen.swift:159-171`** (delete path), **`Storage/MarkdownExporter.swift:131-138`** (naming)

The writer copies the full transcript, attendee names and scratchpad into `group.com.morningvault.app/Meetings/<name>.md` — a container shared with the widget extension. `HomeScreen.delete(_:)` removes the SwiftData rows and the audio file but **never** the `.md`, so transcripts of deleted meetings persist indefinitely in a shared container.

`MarkdownExporter.fileName(for:)` builds the name from date + title slug with **no meeting id**, so two same-titled meetings on one day overwrite each other, and renaming a meeting writes a *new* file and orphans the old one (`Views/MeetingDetailScreen.swift:77`, `Views/RecordingSession.swift:231`).

**Fix:** put `meeting.id.uuidString` in the file name, and delete the markdown in `HomeScreen.delete` and on rename. Better still: **remove the App Group writer entirely** — I grepped for readers and found none, so today it is a write-only channel that copies personal content into a shared container for no consumer. If it is kept for a planned consumer, it needs a matching delete path and a documented reason for putting transcripts in the widget's container.

### H5. Recordings, transcripts and the SwiftData store are included in iCloud backups
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Storage/MeetingNotesStore.swift:14-32`**

Everything the kit writes lives under `Library/Application Support/VaultNotes` (audio in `Meetings/<id>/`, store in `Store/MeetingNotes.store`). Application Support is included in iCloud/iTunes device backups by default. A repo-wide grep for `isExcludedFromBackup` returns **nothing** in the kit. The in-app privacy policy states "Your data never leaves your device" (`MorningVault/PrivacyPolicy/PrivacyPolicyView.swift:21`), and the README makes the same promise. Backups are technically not "the device", but the app's own claim is the product promise here, so this needs an explicit decision.

**Fix:** mark the `VaultNotes` folder excluded from backup and apply `.completeFileProtection` to the recordings and the store. Note `Speakers/VoiceProfileStore.swift:56` **already** does this for the voice profile — the transcripts and audio are the gap. If backups are intended to be allowed, change the copy instead; do not leave the promise and the behaviour divergent.

---

## MEDIUM severity

### M1. Weekday due dates resolve to dates in the year 2000
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Storage/MeetingPersistence.swift:221-252`**

`DueFormatter.formats` includes `"EEEE"` and `"EEE"`, so a due date of `"Friday"` is parsed by `DateFormatter` against its default reference date. **Verified by running the exact format list:**

```
input=Friday  ->  2000-01-07 00:00:00
input=Monday  ->  2000-01-03 00:00:00
input=2026-11-08  ->  2026-11-08 00:00:00   (correct)
```

The fallback block at lines 245-250 is unreachable — it reuses `"EEEE"` with the same locale and time zone the loop already tried — and would be wrong anyway (`Calendar.date(from:)` with only `yearForWeekOfYear`/`weekOfYear` yields `nil`). The wrong date reaches the notes UI and the Reminders note.

**Fix:** drop `"EEEE"`/`"EEE"` from `formats` and resolve weekday names explicitly against the next occurrence from today (e.g. `Calendar.nextDate(after:matching:matchingPolicy: .forward, direction: .forward)`).

### M2. Multiple `ModelContainer`s are opened on the same SQLite file, with failures swallowed
**`MorningVault/Views/ContentView.swift:18`**, **`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Digest/MeetingDigest.swift:10-13`**

`ContentView` holds `@State private var meetingsContainer: ModelContainer? = try? MeetingNotesStore.modelContainer()`. The initialiser expression is re-evaluated on every `ContentView` struct init — and the app forces rebuilds via `.id(themeRaw)` (`MorningVault/App/MorningVaultApp.swift:24`) — opening a fresh coordinator on the same `MeetingNotes.store` each time. Separately, `MeetingDigest.openActionItems(since:)` opens **another** container on the same file on every briefing refresh (`MorningVault/ViewModels/BriefingViewModel.swift:249`) and swallows failure with `try?` → `[]`, so meeting action items silently vanish from "Since yesterday".

I confirmed this is redundant connections rather than corruption (two containers on one file coexist and share data), but it is still needless connection churn plus hidden errors.

**Fix:** own exactly one container — a lazily-created static in `MeetingNotesStore`, or injected into the view model — and call the existing `openActionItems(since:in:)` overload with it. Replace `try?` with `do/catch` and surface the failure.

### M3. `exportedToReminders` is written but never read, so repeated exports duplicate reminders
**`Views/MeetingDetailScreen.swift:214`**, **`Views/MeetingScreen.swift:416`**, flag declared at **`Models/MeetingModels.swift:109`**

Grep shows the flag is only ever assigned `true` and never read. Tapping "Add to Reminders" twice creates duplicate reminders in the user's Reminders list.

**Fix:** filter out items already flagged `exportedToReminders` before exporting, or look up and update the existing reminder.

### M4. Kit calendar service treats write-only authorisation as read authorisation
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Calendar/CalendarService.swift:85`**, same at **`Reminders/RemindersService.swift:52`**

`case .fullAccess, .writeOnly: access = .granted` then `store.events(matching:)` — reading events requires **full** access; write-only permits creating only. The host app gets this right (`MorningVault/Services/CalendarService.swift:21` uses `== .fullAccess`).

**Fix:** require `.fullAccess` for the read path (`loadToday`); treat `.writeOnly` as "can write, cannot list".

### M5. Every persistence save is `try?`, so failures lose data invisibly
**`Storage/MeetingPersistence.swift:26, 56, 91, 116, 139`** and the view-level saves

A failed save (disk full, locked store) drops the transcript, summary or action items with no error and no user feedback — the UI shows "Enhanced" while nothing was written.

**Fix:** `do/catch` + `Logger`, and show a message when a save fails.

### M6. `audioFolder(for:)` creates directories as a side effect, leaving orphans
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Storage/MeetingNotesStore.swift:35-41`**

The path getter calls `createDirectory`. So viewing a meeting creates `Meetings/<id>/` even with no recording, and `deleteRecordings` (`Storage/MeetingPersistence.swift:207-211`) *creates* the folder it is deleting from and never removes it. Voice enrolment audio is written to `Meetings/<sessionUUID>/` (`Views/VoiceEnrollmentScreen.swift:32, 70, 139`) — the same tree as real meetings — and is only removed on `cancel()`, so a hard app kill mid-enrolment leaves an orphaned `.m4a` with no `Meeting` row and no sweep to find it.

**Fix:** split into a pure `audioFolderURL(for:)` and an explicit `ensureAudioFolder(for:)`; delete the whole per-meeting directory on removal; put enrolment audio under a separate `Enrolment/` root; add a startup sweep for meeting folders with no row.

### M7. `SFSpeechRecognizer` is used alongside the modern `SpeechAnalyzer`, with two different on-device stories
**`Transcription/FileTranscriptionService.swift:255-259`** vs **`Transcription/LiveTranscriber.swift:77-134`**

The live path uses `SpeechTranscriber`/`SpeechAnalyzer` with `AssetInventory` and `AnalyzerInputConverter`; the fallback path uses the older `SFSpeechRecognizer` + `SFSpeechAudioBufferRecognitionRequest`. Two consequences:

- The fallback path reads **all** audio into memory before recognising. `readBuffers` (`Transcription/FileTranscriptionService.swift:157-197`) builds `[AVAudioPCMBuffer]` for the whole file. At 16 kHz mono Float32 that is **230 MB for a 60-minute recording** (~57.6M samples × 4 bytes), plus the AAC-decode working set — a realistic jetsam risk on a long meeting. The diarizer path is fine: `Audio/AudioFileSamples.swift` streams in blocks and never holds the whole file.
- The fallback path does **not** pre-check that on-device assets are installed, so it can fail late, after the user has already waited.

**Fix:** prefer the modern `SpeechTranscriber` for the fallback path too (it already handles asset installation and `AnalyzerInputConverter`). If `SFSpeechRecognizer` must stay, stream the buffers into the request instead of materialising them all — append each converted block and release it.

### M8. `replaceTranscriptPieces`'s `speakerKeys` parameter has no caller
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Storage/MeetingPersistence.swift:74, 87`**

No call site passes it — all callers rely on `applySpeakers`. Dead parameter; a second fetch is performed to obtain data the caller already has.

**Fix:** remove the parameter, or use it from `applySpeakers` instead of the extra fetch.

### M9. `Meeting.calendarEventID` is stored but never read
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Models/MeetingModels.swift:21`**

Grep shows it is only ever assigned, never queried — dead state that implies a capability the app does not have. Related: the host's `CalendarEvent.id` falls back to `UUID().uuidString` (`MorningVault/Services/CalendarService.swift:52`), a non-deterministic id that could never be looked up.

**Fix:** either use `calendarEventID` to re-resolve the event, or drop the property; in the host use `ek.calendarItemIdentifier` rather than a random UUID.

---

## LOW severity

### L1. `attendeeNames` can contain empty strings
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Calendar/CalendarService.swift:59`** — `$0.name ?? ""` turns unnamed attendees into `""`, and exports render `**Attendees:** , , ` (`Storage/MarkdownExporter.swift:51`). Filter out empty names before storing.

### L2. `EKEventStore.authorizationStatus(for:)` static class method is deprecated since iOS 17
**`Calendar/CalendarService.swift:83`**, **`Reminders/RemindersService.swift:50`**, host **`MorningVault/Services/CalendarService.swift:21`**. Use the instance method `store.authorizationStatus(for:)`.

### L3. `RemindersService.list(named:)` can save a calendar with no source
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Reminders/RemindersService.swift:67-74`** — `calendar.source` is only set when a local/default calendar exists; otherwise `saveCalendar` fails at the Objective-C level, which Swift cannot catch. Throw a typed error instead.

### L4. `AudioRecorder` allocates an array per tap block on the audio realtime thread
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Audio/AudioRecorder.swift:406-414`** — `monoSamples(from:)` builds a new `[Float]` (and `Array(UnsafeBufferPointer(...))` for mono) on the realtime callback thread. This is a common Apple-sampled pattern, but heap allocation on the audio thread can cause glitches under load. Pre-allocate a reusable buffer pool, or use `AudioBufferList`/`AVAudioPCMBuffer` directly and let the downstream actor copy.

### L5. `__installTap` is a refined (underscored) API
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Audio/AudioRecorder.swift:365`** — `input.__installTap(onBus:bufferSize:format:error:block:)`. Confirmed in the iOS 27.2 SDK: `installTapOnBus:bufferSize:format:error:block:` is `NS_REFINED_FOR_SWIFT`, so the `__` prefix is the sanctioned Swift spelling, not a private API. It is App Store-safe **as written**. But it is new in iOS 27, and the `#else` branch (line 371) uses the deprecated `installTap`, which **traps** rather than throwing on a bad format. Given the iOS 26 deployment target, that deprecated path is what actually runs on iOS 26 devices — worth a comment and a regression test on iOS 26 hardware.

### L6. `installTap` error path leaves the engine half-configured
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Audio/AudioRecorder.swift:587-606`** — `handleConfigurationChange` removes the tap and reinstalls it, but if `installTap` throws, `input.removeTap(onBus: 0)` has already run and the engine is left without a tap while `state` still says `.recording` until `pause()` lands. The `pause()` call in the `catch` does set `.paused`, so this is recoverable — but the banner says "recording could not continue" while the state machine has already moved on. Tighten the ordering so the banner and state agree.

### L7. `meetingSampleMode` and the showcase views are shipping scaffolding
**`Packages/MeetingNotesKit/Sources/MeetingNotesKit/Views/SampleMode.swift`**, **`MeetingShowcaseView.swift`**, **`MeetingsRootView.swift`**, **`MeetingsHubView.swift`**

`MeetingsRootView` and `MeetingsHubView` are now identical (`init` ignores `initialTab`; both render `HomeScreen()`), and `MeetingsRootView.Tab` (`record`/`today`/`library`) is dead — the tab bar is gone. `MeetingShowcaseView` exists to let the host app screenshot a populated recorder; the README says as much. Shipping a public "sample mode" environment flag plus four near-duplicate entry points is a maintenance liability in a package the host consumes.

**Fix:** collapse to one public entry point (`MeetingsHubView`), delete `MeetingsRootView` and the `Tab` enum, and gate `meetingSampleMode` behind `#if DEBUG` (or keep it internal to the host app) rather than shipping it as public API.

---

## Verified clean (checked, not merely assumed)

- **No network path in the package.** Grepped `URLSession`, `URLRequest`, `http(s)://`, `import Network`, `NWConnection`, and FluidAudio's `ModelHub`/`fromRepository` across `Packages/MeetingNotesKit/Sources/` — the only hit is `UIApplication.openSettingsURLString` (`Audio/RecordingPermissions.swift:69`). The diarizer uses `MLModel(contentsOf:)` through `DiarizerModels.load(localSegmentationModel:localEmbeddingModel:)`, which never touches the network.
- **No personal content in logs.** No `print`, `NSLog`, `os_log` or `Logger` calls anywhere in the package sources.
- **The diarizer is memory-bounded.** `SpeakerDiarizer.blockSeconds = 300` and `AudioFileSamples.read` streams blocks — a 60-minute recording is never fully resident. Good design.
- **No app/widget SwiftData conflict.** The widget (`MorningVaultWidget/MorningVaultWidget.swift`) uses only App Group `UserDefaults` via `SharedBriefingStore`; it opens no SwiftData store, so there is no two-schema-one-file corruption risk. The host app defines no `@Model` types.
- **The package compiles clean** for macOS and for the iOS Simulator under Swift 6 language mode.
- **The private-looking API is not private.** `__installTap` is `NS_REFINED_FOR_SWIFT` — the intended Swift spelling (see L5).
- **Diarizer threshold is the library default.** `clusteringThreshold: 0.7` (`SpeakerDiarizer.swift:102`) matches `DiarizerConfig.default` exactly; FluidAudio derives `speakerThreshold = clusteringThreshold * 1.2` and compares **cosine distance** (`SpeakerManager.assignSpeaker`, `distance < speakerThreshold`), so 0.7 is not a mis-tuned value. The app's own "You" gate is a separate, stricter cosine **similarity** threshold of 0.5 (`SpeakerAssignment.youMatchThreshold`) with a correct justification in the doc comment.
- **`UnitsPreference` reaches the widget.** It lives in `MorningVault/Shared/`, which is a source path of the widget target in `project.yml`.
- **Speech asset handling is deliberate.** `LiveTranscriber` installs on-device assets via `AssetInventory` and degrades to file-based transcription when the pack is unavailable — the on-device-only guarantee is preserved by `requiresOnDeviceRecognition = true` on the legacy path.

---

## Notes and residual risk

- **SwiftData migration:** the `Meeting` schema gained optional properties (`speakerLabelsJSON`, `speakerKey`) in commit `37af19c` with no `VersionedSchema`/`SchemaMigrationPlan`. An added optional property migrates in place on the same model (verified locally), but a TestFlight build created before `37af19c` should be smoke-tested against the new store. This is low risk for a first release and worth a schema-versioning plan before the schema changes again.
- **FluidAudio model licensing:** `Resources/DiarizerModels/NOTICE.md` documents the pyannote/WeSpeaker provenance and licences, but `legal/3RD_PARTY.md` has **no entry** for FluidAudio, WeSpeaker or pyannote. Add them before shipping.
- **`docs/REVIEW-2026-11-04.md`** already covers the overlapping ground (diarizer threshold, backup exclusion, container duplication, diarizer allocation) and its "must fix before release" list should be treated as the authoritative checklist alongside this one.

---

## Top 5 to fix first

1. **H1 — live transcript duplication.** Every meeting's transcript is wrong. One-line-ish fix using `result.isFinal` (already in the SDK), but it changes the shape of `apply`, so do it first while the code is fresh.
2. **H2 — "Enhance notes" wipes completed action items.** Silent loss of user state; the user sees "Enhanced" and their ticks are gone. Reconcile by text instead of delete-and-reinsert.
3. **H3 — `settled`/`task` race in the fallback transcription path.** A double-resume of a checked continuation is a crash, and it is reachable whenever live transcription is unavailable — which is exactly when the fallback runs.
4. **H4 — App Group transcripts never deleted + filename collisions.** Two same-titled meetings on one day overwrite each other, and deleted meetings leave transcripts behind in a shared container. Either delete the writer (no reader exists) or give it an id-based name and a delete path.
5. **M1 — weekday due dates resolve to 2000.** A one-line fix with a verified wrong result; it produces nonsense dates in the notes UI and in Reminders.

After those, **H5 (backup exclusion + the privacy-promise wording)** is the next thing to settle, because it is a product decision rather than a code fix and it gates the App Store privacy answer.
