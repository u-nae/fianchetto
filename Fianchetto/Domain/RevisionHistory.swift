import Foundation

/// 날짜 시점 조회(PRD §6-D, W17). 기록 시각은 절대 시각으로 비교하고, 날짜·시각 선택만 시스템 시간대 달력으로 계산한다.
enum RevisionLookup {
    /// 기록 시각이 `instant` 이하인 revision 중 기록 시각이 가장 늦은 것. 같은 시각이면 순번이 큰 것(시계 역행 대응). 없으면 nil(이 시점의 기록 없음).
    static func latest<Revisions: Sequence>(atOrBefore instant: Date, in revisions: Revisions) -> RevisionSummary?
    where Revisions.Element == RevisionSummary {
        revisions
            .filter { $0.recordedAt <= instant }
            .max { ($0.recordedAt, $0.sequence) < ($1.recordedAt, $1.sequence) }
    }

    /// 분 단위로 고른 시각의 찾기 기준 시각: 고른 순간이 속한 분의 끝(59.999초)이다(0023).
    static func threshold(forPickedMinute picked: Date, calendar: Calendar) -> Date {
        let minute = calendar.dateInterval(of: .minute, for: picked) ?? DateInterval(start: picked, duration: 60)
        return minute.end.addingTimeInterval(-0.001)
    }
}

/// 이력 탭 날짜 구역 머리글의 종류(결정 history_day_heading, DESIGN.md 16.2). 문구는 화면이 만든다.
struct HistoryDayHeading: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case today
        case yesterday
        /// 오늘·어제가 아닌 같은 해의 날(시계 역행으로 생긴 미래 날짜 포함).
        case sameYear
        case otherYear
    }

    var kind: Kind
    /// 기록 시각이 속한 날의 시작(시스템 시간대).
    var day: Date

    static func classify(_ recordedAt: Date, now: Date, calendar: Calendar) -> HistoryDayHeading {
        let day = calendar.startOfDay(for: recordedAt)
        let today = calendar.startOfDay(for: now)
        let kind: Kind
        if day == today {
            kind = .today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday {
            kind = .yesterday
        } else if calendar.component(.year, from: day) == calendar.component(.year, from: today) {
            kind = .sameYear
        } else {
            kind = .otherYear
        }
        return HistoryDayHeading(kind: kind, day: day)
    }
}

/// 이력 목록의 날짜 구역. 놓인 순서(순번 역순)를 지키고, 바로 앞 행과 날짜가 다를 때마다 구역을 연다.
/// 기록이 없는 날은 구역이 없고, 시계가 뒤로 갔으면 같은 날 구역이 다시 나올 수 있다.
enum HistorySections {
    static func group<Row>(_ rows: [Row], recordedAt: (Row) -> Date, calendar: Calendar) -> [(day: Date, rows: [Row])] {
        var sections: [(day: Date, rows: [Row])] = []
        for row in rows {
            let day = calendar.startOfDay(for: recordedAt(row))
            if sections.last?.day == day {
                sections[sections.count - 1].rows.append(row)
            } else {
                sections.append((day, [row]))
            }
        }
        return sections
    }
}
