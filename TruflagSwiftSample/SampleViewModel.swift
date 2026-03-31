import Foundation
import TruflagSDK

@MainActor
final class SampleViewModel: ObservableObject {
    enum FallbackType: String, CaseIterable, Identifiable {
        case bool = "Bool"
        case string = "String"
        case number = "Number"

        var id: String { rawValue }
    }

    @Published var apiKey: String = ""
    @Published var relayURL: String = "https://sdk.truflag.com"
    @Published var userId: String = "test-user-1"
    @Published var country: String = "US"
    @Published var hasCompletedOnboarding: Bool = true
    @Published var createdAtISO: String = "2026-03-27T19:19:50.621Z"
    @Published var flagKey: String = "economyvariation"
    @Published var fallbackType: FallbackType = .string
    @Published var fallbackRawValue: String = "coins"
    @Published var eventName: String = "demo_event"
    @Published var eventPropertiesJSON: String = "{\n  \"source\": \"ios-swift-sample\"\n}"

    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var isReady: Bool = false
    @Published private(set) var lastFlagValue: String = "-"
    @Published private(set) var lastRefreshStatus: String = "Not run"
    @Published private(set) var lastError: String = ""
    @Published private(set) var assignmentReason: String = ""
    @Published private(set) var configVersion: String = ""
    @Published private(set) var rawPayload: String = "{}"
    @Published private(set) var activeUserID: String = ""
    @Published private(set) var autoRefreshEnabled: Bool = false

    private var client = TruflagClient()
    private var refreshTask: Task<Void, Never>?

    func configure() {
        clearError()
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Client-side ID (API key) is required"
            return
        }
        guard let baseURL = URL(string: relayURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            lastError = "Relay URL is invalid"
            return
        }

        let attributes = buildAttributes()
        let user = TruflagUser(id: userId.trimmingCharacters(in: .whitespacesAndNewlines), attributes: attributes)
        let options = TruflagConfigureOptions(apiKey: apiKey, user: user, baseURL: baseURL)

        Task {
            do {
                try await client.configure(options)
                isConfigured = true
                activeUserID = user.id
                isReady = await client.isReady()
                lastRefreshStatus = "Configured and refreshed"
            } catch {
                lastError = "Configure failed: \(error.localizedDescription)"
            }
        }
    }

    func refresh() {
        guard guardConfigured() else { return }
        Task {
            do {
                try await client.refresh()
                isReady = await client.isReady()
                lastRefreshStatus = "Refresh succeeded @ \(isoNow())"
                clearError()
            } catch {
                lastRefreshStatus = "Refresh failed @ \(isoNow())"
                lastError = "Refresh failed: \(error.localizedDescription)"
            }
        }
    }

    func readFlag() {
        guard guardConfigured() else { return }
        Task {
            switch fallbackType {
            case .bool:
                let fallback = (fallbackRawValue as NSString).boolValue
                let value: Bool = await client.getFlag(flagKey, defaultValue: fallback)
                lastFlagValue = String(value)
            case .string:
                let value: String = await client.getFlag(flagKey, defaultValue: fallbackRawValue)
                lastFlagValue = value
            case .number:
                let fallback = Double(fallbackRawValue) ?? 0
                let value: Double = await client.getFlag(flagKey, defaultValue: fallback)
                lastFlagValue = String(value)
            }

            let payload = await client.getFlagPayload(flagKey) ?? [:]
            assignmentReason = payload["reason"] as? String ?? ""
            configVersion = payload["configVersion"] as? String ?? ""
            rawPayload = prettyJSON(payload)
        }
    }

    func login() {
        guard guardConfigured() else { return }
        Task {
            do {
                let user = TruflagUser(id: userId.trimmingCharacters(in: .whitespacesAndNewlines), attributes: buildAttributes())
                try await client.login(user: user)
                activeUserID = user.id
                isReady = await client.isReady()
                lastRefreshStatus = "Login succeeded"
                clearError()
            } catch {
                lastError = "Login failed: \(error.localizedDescription)"
            }
        }
    }

    func setAttributes() {
        guard guardConfigured() else { return }
        Task {
            do {
                try await client.setAttributes(buildAttributes())
                isReady = await client.isReady()
                lastRefreshStatus = "Attributes updated"
                clearError()
            } catch {
                lastError = "Set attributes failed: \(error.localizedDescription)"
            }
        }
    }

    func logout() {
        guard guardConfigured() else { return }
        Task {
            do {
                try await client.logout()
                activeUserID = "anonymous"
                isReady = await client.isReady()
                lastRefreshStatus = "Logout succeeded"
                clearError()
            } catch {
                lastError = "Logout failed: \(error.localizedDescription)"
            }
        }
    }

    func sendEvent() {
        guard guardConfigured() else { return }
        Task {
            do {
                let props = parseProperties(eventPropertiesJSON)
                try await client.track(eventName: eventName, properties: props)
                lastRefreshStatus = "Event sent @ \(isoNow())"
                clearError()
            } catch {
                lastError = "Track failed: \(error.localizedDescription)"
            }
        }
    }

    func exposeCurrentFlag() {
        guard guardConfigured() else { return }
        Task {
            do {
                try await client.expose(flagKey: flagKey)
                lastRefreshStatus = "Exposure sent @ \(isoNow())"
                clearError()
            } catch {
                lastError = "Expose failed: \(error.localizedDescription)"
            }
        }
    }

    func toggleAutoRefresh() {
        autoRefreshEnabled.toggle()
        refreshTask?.cancel()
        guard autoRefreshEnabled else { return }

        refreshTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    try await client.refresh()
                    await MainActor.run {
                        self.lastRefreshStatus = "Auto refresh succeeded @ \(self.isoNow())"
                    }
                } catch {
                    await MainActor.run {
                        self.lastRefreshStatus = "Auto refresh failed @ \(self.isoNow())"
                        self.lastError = "Auto refresh failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func buildAttributes() -> [String: AnyCodable] {
        var attrs: [String: AnyCodable] = [
            "country": AnyCodable(country),
            "hasCompletedOnboarding": AnyCodable(hasCompletedOnboarding)
        ]
        if !createdAtISO.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            attrs["createdAt"] = AnyCodable(createdAtISO)
        }
        return attrs
    }

    private func parseProperties(_ json: String) -> [String: AnyCodable] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object.mapValues { AnyCodable($0) }
    }

    private func prettyJSON(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private func guardConfigured() -> Bool {
        guard isConfigured else {
            lastError = "Configure the SDK before using actions"
            return false
        }
        return true
    }

    private func clearError() {
        lastError = ""
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
