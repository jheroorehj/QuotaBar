import Foundation
import Testing
@testable import QuotaBarCore

@Suite("날짜·표시 형식")
struct FormattingTests {
    @Test func parsesISO8601Variants() {
        let expected = Date(timeIntervalSince1970: 1_791_442_800) // 2026-10-08T07:00:00Z
        #expect(DateParsing.iso8601("2026-10-08T07:00:00Z") == expected)
        #expect(DateParsing.iso8601("2026-10-08T07:00:00+00:00") == expected)
        #expect(DateParsing.iso8601("2026-10-08T07:00:00.512345+00:00") == expected)
        #expect(DateParsing.iso8601("2026-10-08T16:00:00.1+09:00") == expected)
        #expect(DateParsing.iso8601("2026-10-08T07:00:00") == expected)
        #expect(DateParsing.iso8601("") == nil)
        #expect(DateParsing.iso8601(nil) == nil)
        #expect(DateParsing.iso8601("not a date") == nil)
    }

    @Test func parsesUnixSecondsAndMilliseconds() {
        #expect(DateParsing.unix(1_791_442_800) == Date(timeIntervalSince1970: 1_791_442_800))
        #expect(DateParsing.unix(1_791_442_800_000) == Date(timeIntervalSince1970: 1_791_442_800))
        #expect(DateParsing.unix(0) == nil)
        #expect(DateParsing.unix(nil) == nil)
    }

    @Test func resetDescriptions() {
        let now = fixedNow
        let utc = TimeZone(identifier: "UTC")!
        #expect(UsageFormatting.resetDescription(nil, now: now) == nil)
        #expect(UsageFormatting.resetDescription(now.addingTimeInterval(30), now: now) == "곧 초기화")
        #expect(UsageFormatting.resetDescription(now.addingTimeInterval(-100), now: now) == "곧 초기화")
        #expect(UsageFormatting.resetDescription(now.addingTimeInterval(5 * 60), now: now) == "5분 후 초기화")
        #expect(UsageFormatting.resetDescription(now.addingTimeInterval(2 * 3600 + 13 * 60 + 20), now: now) == "2시간 13분 후 초기화")
        #expect(UsageFormatting.resetDescription(now.addingTimeInterval(3 * 3600), now: now) == "3시간 후 초기화")
        let later = date("2026-10-09T09:00:00Z")
        #expect(UsageFormatting.resetDescription(later, now: now, timeZone: utc) == "10월 9일 (금) 09:00 초기화")
    }

    @Test func windowLabels() {
        #expect(UsageFormatting.windowLabel(minutes: 300) == "5시간")
        #expect(UsageFormatting.windowLabel(minutes: 10080) == "주간")
        #expect(UsageFormatting.windowLabel(minutes: 1440) == "일간")
        #expect(UsageFormatting.windowLabel(minutes: 43200) == "월간")
        #expect(UsageFormatting.windowLabel(minutes: 2880) == "2일")
        #expect(UsageFormatting.windowLabel(minutes: 90) == "90분")
        #expect(UsageFormatting.windowLabel(minutes: nil) == "한도")
    }

    @Test func percentAndMoney() {
        #expect(UsageFormatting.percent(58.4) == "58%")
        #expect(UsageFormatting.percent(99.6) == "100%")
        #expect(UsageFormatting.dollars(cents: 1250) == "$12.50")
    }

    @Test func usageWindowClampsPercent() {
        #expect(UsageWindow(id: "a", label: "a", usedPercent: 140).usedPercent == 100)
        #expect(UsageWindow(id: "a", label: "a", usedPercent: -3).usedPercent == 0)
        #expect(UsageWindow(id: "a", label: "a", usedPercent: .nan).usedPercent == 0)
        let remaining = UsageWindow.fromRemainingFraction(id: "a", label: "a", remainingFraction: 0.86)
        #expect(abs(remaining.usedPercent - 14) < 0.0001)
    }
}

@Suite("ProviderError")
struct ProviderErrorTests {
    @Test func wrapsKnownErrors() {
        #expect(ProviderError.wrap(CancellationError()) == .cancelled)
        #expect(ProviderError.wrap(ProviderError.timeout(3)) == .timeout(3))
        #expect(ProviderError.wrap(JSONRPCError.launchFailed("x")) == .commandFailed(JSONRPCError.launchFailed("x").localizedDescription))
        #expect(ProviderError.wrap(ProcessRunnerError.timedOut(5)) == .commandFailed(ProcessRunnerError.timedOut(5).localizedDescription))
        #expect(ProviderError.setupRequired("x").requiresUserAction)
        #expect(!ProviderError.network("x").requiresUserAction)
    }

    @Test func messagesAreShortened() {
        let long = String(repeating: "가", count: 500)
        let message = ProviderError.httpStatus(500, long).localizedDescription
        #expect(message.count < 260)
        #expect(message.hasPrefix("서버 오류 (HTTP 500)"))
    }
}
