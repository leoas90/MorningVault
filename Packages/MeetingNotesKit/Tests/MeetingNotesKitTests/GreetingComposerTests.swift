import Foundation
import Testing
@testable import MeetingNotesKit

/// `GreetingComposer` is shared with the app via a symlink (like the other Shared files) so the
/// widget and the Brief agree; these tests pin the rules.
struct GreetingComposerTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func emptyNameHasNoTrailingComma() {
        let line = GreetingComposer.line(name: "   ", date: date(2026, 11, 4, 8), calendar: calendar)
        #expect(!line.contains(","))
        #expect(!line.contains("."))
        #expect(!line.isEmpty)
    }

    @Test func nameIsAppendedAfterComma() {
        let line = GreetingComposer.line(name: " Yezid ", date: date(2026, 11, 4, 8), calendar: calendar)
        #expect(line.hasSuffix(", Yezid"))
    }

    @Test func slotsFollowTheClock() {
        #expect(GreetingComposer.slot(for: date(2026, 11, 4, 3), calendar: calendar) == .earlyMorning)
        #expect(GreetingComposer.slot(for: date(2026, 11, 4, 8), calendar: calendar) == .morning)
        #expect(GreetingComposer.slot(for: date(2026, 11, 4, 14), calendar: calendar) == .afternoon)
        #expect(GreetingComposer.slot(for: date(2026, 11, 4, 19), calendar: calendar) == .evening)
        #expect(GreetingComposer.slot(for: date(2026, 11, 4, 23), calendar: calendar) == .night)
    }

    @Test func fridayMorningOffersHappyFriday() {
        // 2026-11-06 is a Friday.
        let weekday = calendar.component(.weekday, from: date(2026, 11, 6, 8))
        #expect(weekday == 6)
        let list = GreetingComposer.candidates(slot: .morning, weekday: weekday, calendar: calendar)
        #expect(list.contains("Happy Friday"))
        #expect(list.contains("Good morning"))
    }

    @Test func nightLinesAreNight() {
        let list = GreetingComposer.candidates(slot: .night, weekday: 4, calendar: calendar)
        #expect(list.contains("Late one tonight"))
        #expect(!list.contains("Good morning"))
    }

    @Test func sameDayIsStableAcrossRefreshes() {
        let a = GreetingComposer.line(name: "Yezid", date: date(2026, 11, 4, 7), calendar: calendar)
        let b = GreetingComposer.line(name: "Yezid", date: date(2026, 11, 4, 9), calendar: calendar)
        #expect(a == b)
    }

    @Test func morningsVaryAcrossAWeek() {
        var seen = Set<String>()
        for day in 2...8 {
            seen.insert(GreetingComposer.base(for: date(2026, 11, day, 8), calendar: calendar))
        }
        #expect(seen.count >= 2)
    }

    @Test func everyCandidateIsASentenceStart() {
        for slot in [GreetingComposer.Slot.earlyMorning, .morning, .afternoon, .evening, .night] {
            for weekday in 1...7 {
                for line in GreetingComposer.candidates(slot: slot, weekday: weekday, calendar: calendar) {
                    #expect(line.first?.isUppercase == true)
                    #expect(!line.hasSuffix(","))
                    #expect(!line.hasSuffix("."))
                }
            }
        }
    }

    @Test func baseNeverOutOfRange() {
        for day in 1...28 {
            for hour in [3, 8, 14, 19, 23] {
                let base = GreetingComposer.base(for: date(2026, 11, day, hour), calendar: calendar)
                #expect(!base.isEmpty)
            }
        }
    }
}
