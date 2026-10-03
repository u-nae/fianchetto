import Foundation
import Testing
@testable import Fianchetto

/// 시스템 시간대 기준 지역 시각을 절대 시각으로 바꾼다. "yyyy-MM-dd HH:mm:ss" 또는 ".SSS"까지.
func localTime(_ text: String, in zone: String = "Asia/Seoul") -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: zone)
    formatter.dateFormat = text.contains(".") ? "yyyy-MM-dd HH:mm:ss.SSS" : "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: text)!
}

func calendar(in zone: String = "Asia/Seoul") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

/// 순번과 기록 시각만 의미 있는 revision 목록 정보.
func summary(_ sequence: Int, at recordedAt: Date, cause: RevisionCause = .edited(.renameNode)) -> RevisionSummary {
    RevisionSummary(id: fixedID(9000 + sequence), projectID: fixedID(900), sequence: sequence, recordedAt: recordedAt, cause: cause, projectName: "서비스 A")
}

@Suite("날짜 시점 조회(W17)")
struct RevisionLookupTests {
    static let base = [
        summary(1, at: localTime("2026-10-01 09:00:00")),
        summary(2, at: localTime("2026-10-02 14:20:30")),
        summary(3, at: localTime("2026-10-03 08:00:00")),
    ]

    @Test("[W17-lookup-latest] 고른 시각 이하의 기록 중 가장 늦은 시각의 기록을 고른다", .tags(.A05), arguments: [
        ("2026-10-01 09:00:00", 1), ("2026-10-02 14:20:29", 1), ("2026-10-02 14:20:30", 2),
        ("2026-10-02 23:59:59", 2), ("2026-10-05 00:00:00", 3),
    ])
    func latest(picked: String, expected: Int) {
        #expect(RevisionLookup.latest(atOrBefore: localTime(picked), in: Self.base)?.sequence == expected)
    }

    @Test("[W17-lookup-latest] 순서가 섞여 들어와도 결과는 같다")
    func orderIndependent() {
        #expect(RevisionLookup.latest(atOrBefore: localTime("2026-10-02 20:00:00"), in: Self.base.reversed())?.sequence == 2)
    }

    @Test("[W17-lookup-clock-back] 시계가 뒤로 간 기록이 있으면 순번이 아니라 기록 시각으로 고른다")
    func clockBack() {
        let revisions = [
            summary(1, at: localTime("2026-10-01 09:00:00")),
            summary(2, at: localTime("2026-10-03 10:00:00")),
            summary(3, at: localTime("2026-10-02 12:00:00")),
        ]
        #expect(RevisionLookup.latest(atOrBefore: localTime("2026-10-02 13:00:00"), in: revisions)?.sequence == 3)
        #expect(RevisionLookup.latest(atOrBefore: localTime("2026-10-03 10:00:00"), in: revisions)?.sequence == 2)
    }

    @Test("[W17-lookup-same-time] 같은 기록 시각이 여럿이면 순번이 큰 기록을 고른다")
    func sameTime() {
        let revisions = [
            summary(1, at: localTime("2026-10-01 09:00:00")),
            summary(2, at: localTime("2026-10-01 09:00:00")),
            summary(3, at: localTime("2026-10-01 08:59:00")),
        ]
        #expect(RevisionLookup.latest(atOrBefore: localTime("2026-10-01 09:00:00"), in: revisions)?.sequence == 2)
        #expect(RevisionLookup.latest(atOrBefore: localTime("2026-10-01 09:00:00"), in: revisions.reversed())?.sequence == 2)
    }

    @Test("[W17-lookup-before-creation] 모든 기록보다 이른 시각이나 빈 목록이면 기록 없음이다", .tags(.A05))
    func beforeCreation() {
        #expect(RevisionLookup.latest(atOrBefore: localTime("2026-09-30 23:59:59"), in: Self.base) == nil)
        #expect(RevisionLookup.latest(atOrBefore: localTime("2026-10-05 00:00:00"), in: []) == nil)
    }

    @Test("[W17-minute-threshold] 분 단위로 고른 시각은 그 분의 끝을 기준 시각으로 삼는다", arguments: [
        ("2026-10-02 14:20:00", "2026-10-02 14:20:59.999"),
        ("2026-10-02 14:20:42", "2026-10-02 14:20:59.999"),
        ("2026-10-02 23:59:00", "2026-10-02 23:59:59.999"),
        ("2026-10-03 00:00:00", "2026-10-03 00:00:59.999"),
    ])
    func minuteThreshold(picked: String, expected: String) {
        let threshold = RevisionLookup.threshold(forPickedMinute: localTime(picked), calendar: calendar())
        #expect(abs(threshold.timeIntervalSince(localTime(expected))) < 0.0005)
    }

    @Test("[W17-minute-threshold] 다음 분의 시작은 기준 시각에 들지 않는다")
    func nextMinuteExcluded() {
        let threshold = RevisionLookup.threshold(forPickedMinute: localTime("2026-10-02 14:20:00"), calendar: calendar())
        #expect(threshold < localTime("2026-10-02 14:21:00"))
        #expect(threshold > localTime("2026-10-02 14:20:59.998"))
    }

    @Test("[W17-minute-threshold] 일광 절약 시간이 끝나 되풀이되는 시각도 고른 순간이 속한 분의 끝이다")
    func daylightSaving() {
        // 2026-11-01 01:30 PDT(UTC-7)와 01:30 PST(UTC-8)는 같은 지역 시각이 되풀이된다. 고른 순간 기준으로 그 분의 끝을 쓴다.
        let pdt = Date(timeIntervalSince1970: 1_793_521_800) // 2026-11-01T08:30:00Z
        let pst = pdt.addingTimeInterval(3600)
        let la = calendar(in: "America/Los_Angeles")
        #expect(abs(RevisionLookup.threshold(forPickedMinute: pdt, calendar: la).timeIntervalSince(pdt.addingTimeInterval(59.999))) < 0.0005)
        #expect(abs(RevisionLookup.threshold(forPickedMinute: pst, calendar: la).timeIntervalSince(pst.addingTimeInterval(59.999))) < 0.0005)
    }

    @Test("[W17-lookup-minute-boundary] 행에 보이는 분을 그대로 고르면 그 분 안의 기록이 찾아진다", .tags(.A05))
    func pickedMinuteFindsRecordInsideMinute() {
        let revisions = [
            summary(1, at: localTime("2026-10-02 14:19:00")),
            summary(2, at: localTime("2026-10-02 14:20:30")),
            summary(3, at: localTime("2026-10-02 14:21:00")),
        ]
        func find(_ picked: String) -> Int? {
            RevisionLookup.latest(atOrBefore: RevisionLookup.threshold(forPickedMinute: localTime(picked), calendar: calendar()), in: revisions)?.sequence
        }
        #expect(find("2026-10-02 14:20:00") == 2)
        #expect(find("2026-10-02 14:19:00") == 1)
    }
}

@Suite("이력 날짜 구역(W17)")
struct HistoryDayHeadingTests {
    @Test("[W17-day-heading] 날짜 구역 머리글은 결정 history_day_heading을 따른다", arguments: [
        ("2026-10-03", "2026-10-03", HistoryDayHeading.Kind.today),
        ("2026-10-03", "2026-10-02", .yesterday),
        ("2026-10-03", "2026-10-01", .sameYear),
        ("2026-10-03", "2025-12-30", .otherYear),
        ("2027-01-01", "2026-12-31", .yesterday),
        ("2026-10-03", "2026-10-05", .sameYear),
    ])
    func heading(today: String, recorded: String, expected: HistoryDayHeading.Kind) {
        let now = localTime("\(today) 12:00:00"), at = localTime("\(recorded) 23:30:00")
        #expect(HistoryDayHeading.classify(at, now: now, calendar: calendar()).kind == expected)
    }

    @Test("[W17-day-heading] 오늘은 자정부터 시작한다")
    func midnightBoundary() {
        let now = localTime("2026-10-03 00:00:00")
        #expect(HistoryDayHeading.classify(localTime("2026-10-03 00:00:00"), now: now, calendar: calendar()).kind == .today)
        #expect(HistoryDayHeading.classify(localTime("2026-10-02 23:59:59"), now: now, calendar: calendar()).kind == .yesterday)
    }

    @Test("[W17-day-sections] 날짜 구역은 기록이 있는 날에만 만들고 순번 역순을 지킨다")
    func sectionsOnlyForRecordedDays() {
        let rows = [
            summary(4, at: localTime("2026-10-03 15:00:00")), summary(3, at: localTime("2026-10-03 09:00:00")),
            summary(2, at: localTime("2026-10-01 10:00:00")), summary(1, at: localTime("2025-12-30 10:00:00")),
        ]
        let sections = HistorySections.group(rows, recordedAt: \.recordedAt, calendar: calendar())
        #expect(sections.map { $0.rows.map(\.sequence) } == [[4, 3], [2], [1]])
        #expect(sections.map(\.day) == [localTime("2026-10-03 00:00:00"), localTime("2026-10-01 00:00:00"), localTime("2025-12-30 00:00:00")])
    }

    @Test("[W17-day-sections-clock-back] 시계가 뒤로 간 기록은 순번 순서를 지키고 날짜가 바뀔 때마다 구역을 다시 연다")
    func clockBackReopensSection() {
        let rows = [
            summary(3, at: localTime("2026-10-02 12:00:00")), summary(2, at: localTime("2026-10-03 10:00:00")),
            summary(1, at: localTime("2026-10-02 09:00:00")),
        ]
        let sections = HistorySections.group(rows, recordedAt: \.recordedAt, calendar: calendar())
        #expect(sections.map { $0.rows.map(\.sequence) } == [[3], [2], [1]])
    }

    @Test("[W17-day-sections] 빈 목록은 구역이 없다")
    func emptyRows() {
        #expect(HistorySections.group([RevisionSummary](), recordedAt: \.recordedAt, calendar: calendar()).isEmpty)
    }

    @Test("[W17-time-zone] 같은 절대 시각도 시간대에 따라 다른 날짜 구역에 든다", .tags(.A05))
    func timeZoneChangesDay() {
        let at = ISO8601DateFormatter().date(from: "2026-10-02T15:30:00Z")!
        let now = ISO8601DateFormatter().date(from: "2026-10-03T06:00:00Z")!
        #expect(HistoryDayHeading.classify(at, now: now, calendar: calendar(in: "Asia/Seoul")) == .init(kind: .today, day: localTime("2026-10-03 00:00:00")))
        #expect(HistoryDayHeading.classify(at, now: now, calendar: calendar(in: "America/Los_Angeles"))
            == .init(kind: .today, day: localTime("2026-10-02 00:00:00", in: "America/Los_Angeles")))
    }
}
