import Foundation
import XCTest
import TruflagSDK

final class TruflagSwiftSampleTests: XCTestCase {
    func testLiveSmokeConfigureReadTrack() async throws {
        let apiKey = ProcessInfo.processInfo.environment["TRUFLAG_CLIENT_SIDE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if apiKey.isEmpty {
            throw XCTSkip("Set TRUFLAG_CLIENT_SIDE_ID to run live smoke tests")
        }

        let baseURLString = ProcessInfo.processInfo.environment["TRUFLAG_BASE_URL"] ?? "https://sdk.truflag.com"
        guard let baseURL = URL(string: baseURLString) else {
            XCTFail("TRUFLAG_BASE_URL is invalid")
            return
        }

        let userID = ProcessInfo.processInfo.environment["TRUFLAG_SMOKE_USER_ID"] ?? "ios-smoke-\(UUID().uuidString.lowercased())"
        let flagKey = ProcessInfo.processInfo.environment["TRUFLAG_SMOKE_FLAG_KEY"] ?? "economyvariation"

        let client = TruflagClient(storage: UserDefaultsTruflagStorage())
        try await client.configure(
            TruflagConfigureOptions(
                apiKey: apiKey,
                user: TruflagUser(id: userID, attributes: [
                    "country": AnyCodable("US"),
                    "hasCompletedOnboarding": AnyCodable(true)
                ]),
                baseURL: baseURL
            )
        )

        let _: String = await client.getFlag(flagKey, defaultValue: "fallback")
        try await client.track(eventName: "ios_swift_sample_smoke", properties: ["suite": AnyCodable("TruflagSwiftSampleTests")])
        try await client.expose(flagKey: flagKey)

        let ready = await client.isReady()
        XCTAssertTrue(ready)
    }
}
