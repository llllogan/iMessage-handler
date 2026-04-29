import Foundation
import Testing
@testable import CalendarHandlerCore

struct DateParsingTests {
    @Test func dateOnlyUntilUsesEndOfDay() throws {
        let date = try parseDateBoundary("2026-04-29", useEndOfDay: true)
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        #expect(components.hour == 23)
        #expect(components.minute == 59)
        #expect(components.second == 59)
    }
}
