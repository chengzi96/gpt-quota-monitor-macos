import XCTest
@testable import AIQuotaBar

final class CodexUsageClientTests: XCTestCase {
    func testParsesPrimaryAndSecondaryWindows() throws {
        let data = Data(
            """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 12,
                  "reset_at": 1770000000,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 34,
                  "reset_at": 1770500000,
                  "limit_window_seconds": 604800
                }
              }
            }
            """.utf8
        )

        let pool = try CodexUsageClient().parseUsageData(data)

        XCTAssertEqual(pool.id, .workCodex)
        XCTAssertEqual(pool.availability, .available)
        XCTAssertEqual(pool.planLabel, "Plus")
        XCTAssertEqual(pool.windows.map(\.kind), [.session, .weekly])
        XCTAssertEqual(pool.windows.map(\.remainingPercent), [88, 66])
        XCTAssertEqual(pool.windows.map(\.title), ["近 5 小时", "本周"])
    }

    func testWeeklyAndSessionWindowsStayIndependentlyAddressable() throws {
        let data = Data(
            """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 2,
                  "reset_at": 1770000000,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 49,
                  "reset_at": 1770500000,
                  "limit_window_seconds": 604800
                }
              }
            }
            """.utf8
        )

        let pool = try CodexUsageClient().parseUsageData(data)
        XCTAssertEqual(pool.weeklyWindow?.title, "本周")
        XCTAssertEqual(pool.weeklyWindow?.remainingPercent, 51)
        XCTAssertEqual(pool.sessionWindow?.title, "近 5 小时")
        XCTAssertEqual(pool.sessionWindow?.remainingPercent, 98)
        XCTAssertEqual(pool.mostConstrainedWindow?.kind, .weekly)
    }

    func testLegacyUsageSampleWithoutWindowKindStillDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(
            """
            {
              "id": "4E7E36EE-0D63-4145-9428-B50D72391B42",
              "poolID": "workCodex",
              "date": "2026-09-01T00:00:00Z",
              "usedPercent": 37
            }
            """.utf8
        )
        let sample = try decoder.decode(UsageSample.self, from: data)
        XCTAssertNil(sample.windowKind)
        XCTAssertEqual(sample.usedPercent, 37)
    }

    func testRejectsPayloadWithoutQuotaWindows() {
        let data = Data(#"{"plan_type":"plus","rate_limit":null}"#.utf8)
        XCTAssertThrowsError(try CodexUsageClient().parseUsageData(data))
    }

    func testResetCountdownUsesChineseUnits() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(4 * 3_600 + 18 * 60)
        XCTAssertEqual(QuotaFormatters.resetCountdown(to: reset, now: now), "4 小时 18 分后重置")
    }

    func testStaleAgeShowsElapsedMinutes() {
        let now = Date(timeIntervalSince1970: 10_000)
        let previous = now.addingTimeInterval(-18 * 60)
        XCTAssertEqual(QuotaFormatters.staleDataAge(previous, now: now), "18 分钟前数据")
    }

    func testRepeatedFailureCanPreserveAlreadyStalePool() {
        let now = Date()
        let original = QuotaPool(
            id: .workCodex,
            availability: .available,
            windows: [
                QuotaWindow(
                    id: "primary",
                    kind: .session,
                    title: "近 5 小时",
                    remainingPercent: 10,
                    resetsAt: now.addingTimeInterval(3_600),
                    durationMinutes: 300
                )
            ],
            updatedAt: now,
            planLabel: "Plus",
            message: nil,
            sourceLabel: "OpenAI Codex"
        )

        let firstFailure = original.preservingAsStale(errorMessage: "网络超时")
        XCTAssertEqual(firstFailure?.availability, .stale)
        XCTAssertEqual(firstFailure?.remainingPercent, 10)

        let secondFailure = firstFailure?.preservingAsStale(errorMessage: "仍然超时")
        XCTAssertEqual(secondFailure?.availability, .stale)
        XCTAssertEqual(secondFailure?.remainingPercent, 10)
        XCTAssertEqual(secondFailure?.updatedAt, now)
    }

    func testCodexOverrideRequiresExplicitDevelopmentFlag() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executable = temporaryDirectory.appendingPathComponent("codex-app-server")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let withoutFlag = CodexExecutableLocator(
            fileManager: .default,
            environment: ["CODEX_APP_SERVER_PATH": executable.path]
        ).executableCandidates()
        XCTAssertFalse(withoutFlag.contains(executable))

        let withFlag = CodexExecutableLocator(
            fileManager: .default,
            environment: [
                "AIQUOTABAR_ALLOW_CODEX_OVERRIDE": "1",
                "CODEX_APP_SERVER_PATH": executable.path
            ]
        ).executableCandidates()
        XCTAssertTrue(withFlag.contains(executable))
    }
}
