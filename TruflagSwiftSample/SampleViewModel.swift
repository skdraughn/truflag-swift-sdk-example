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
    @Published private(set) var currentAction: String = ""
    @Published private(set) var bannerMessage: String = "Ready"
    @Published private(set) var bannerIsError: Bool = false
    @Published private(set) var streamStatus: String = "idle"
    @Published private(set) var pollingActive: Bool = false
    @Published private(set) var lastStreamEventAt: String = "-"
    @Published private(set) var lastStreamEventVersion: String = "-"
    @Published private(set) var logs: [String] = []

    private var client = TruflagClient()
    private var refreshTask: Task<Void, Never>?
    private var clientSubscriptionToken: UUID?
    private var lastObservedStreamStatus: String = ""
    private var lastObservedPollingActive: Bool?
    private var lastObservedStreamEventAt: String?

    func configure() {
        clearError()
        logs.removeAll(keepingCapacity: true)
        appendLog("Starting configure")
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
        let tunedOptions = TruflagConfigureOptions(
            apiKey: options.apiKey,
            user: options.user,
            baseURL: options.baseURL,
            streamURL: options.streamURL,
            streamEnabled: options.streamEnabled,
            pollingIntervalMs: 5_000,
            requestTimeoutMs: options.requestTimeoutMs,
            cacheTtlMs: options.cacheTtlMs,
            telemetryFlushIntervalMs: options.telemetryFlushIntervalMs,
            telemetryBatchSize: options.telemetryBatchSize,
            telemetryEnabled: options.telemetryEnabled
        )

        Task {
            do {
                beginAction("Configuring SDK...")
                try await client.configure(tunedOptions)
                appendLog("Configured SDK. streamEnabled=\(tunedOptions.streamEnabled), streamURL=\(tunedOptions.streamURL.absoluteString)")
                isConfigured = true
                activeUserID = user.id
                await ensureClientSubscription()
                await syncFromClientState(status: "Configured. Waiting for first refresh...")
                setBannerSuccess("SDK configured. Initial refresh runs in background.")
            } catch {
                setFailure("Configure failed", error: error)
            }
            endAction()
        }
    }

    func refresh() {
        guard guardConfigured() else { return }
        Task {
            do {
                beginAction("Refreshing flags...")
                try await client.refresh()
                appendLog("Manual refresh succeeded")
                await syncFromClientState(status: "Refresh succeeded @ \(isoNow())")
                clearError()
                setBannerSuccess("Flags refreshed.")
            } catch {
                lastRefreshStatus = "Refresh failed @ \(isoNow())"
                setFailure("Refresh failed", error: error)
            }
            endAction()
        }
    }

    func readFlag() {
        readFlag(refreshFirst: false)
    }

    func refreshAndReadFlag() {
        readFlag(refreshFirst: true)
    }

    private func readFlag(refreshFirst: Bool) {
        guard guardConfigured() else { return }
        Task {
            beginAction("Reading flag...")
            if refreshFirst {
                do {
                    try await client.refresh()
                    await syncFromClientState(status: "Read after refresh @ \(isoNow())")
                } catch {
                    setBannerError("Refresh before read failed. Reading cached value.")
                    appendLog("Refresh before read failed; using cached state")
                }
            } else {
                await client.waitForInFlightRefresh(timeoutMs: 1800)
                await syncFromClientState(status: "Read from current SDK state @ \(isoNow())")
            }

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

            let state = await client.getState()
            if let raw = state.flags[flagKey]?.value.value {
                lastFlagValue = renderRawValue(raw)
            }

            let payload = payloadFromState(state, flagKey: flagKey)
            assignmentReason = payload["reason"] as? String ?? ""
            let stateAfterRead = await client.getState()
            configVersion = stateAfterRead.configVersion ?? (payload["configVersion"] as? String ?? "")
            rawPayload = prettyJSON(payload)
            setBannerSuccess(refreshFirst ? "Refreshed and read \(flagKey)." : "Read \(flagKey) from current state.")
            endAction()
        }
    }

    func login() {
        guard guardConfigured() else { return }
        Task {
            do {
                beginAction("Logging in...")
                let user = TruflagUser(id: userId.trimmingCharacters(in: .whitespacesAndNewlines), attributes: buildAttributes())
                try await client.login(user: user)
                activeUserID = user.id
                await syncFromClientState(status: "Login succeeded")
                clearError()
                setBannerSuccess("Logged in as \(user.id).")
                appendLog("Logged in as \(user.id)")
            } catch {
                setFailure("Login failed", error: error)
            }
            endAction()
        }
    }

    func setAttributes() {
        guard guardConfigured() else { return }
        Task {
            do {
                beginAction("Updating attributes...")
                try await client.setAttributes(buildAttributes())
                await syncFromClientState(status: "Attributes updated")
                clearError()
                setBannerSuccess("Attributes updated.")
                appendLog("Updated attributes")
            } catch {
                setFailure("Set attributes failed", error: error)
            }
            endAction()
        }
    }

    func logout() {
        guard guardConfigured() else { return }
        Task {
            do {
                beginAction("Logging out...")
                try await client.logout()
                activeUserID = "anonymous"
                await syncFromClientState(status: "Logout succeeded")
                clearError()
                setBannerSuccess("Logged out.")
                appendLog("Logged out")
            } catch {
                setFailure("Logout failed", error: error)
            }
            endAction()
        }
    }

    func sendEvent() {
        guard guardConfigured() else { return }
        Task {
            do {
                beginAction("Sending event...")
                let props = parseProperties(eventPropertiesJSON)
                try await client.track(eventName: eventName, properties: props)
                lastRefreshStatus = "Event sent @ \(isoNow())"
                clearError()
                setBannerSuccess("Event \(eventName) sent.")
                appendLog("Sent event \(eventName)")
            } catch {
                setFailure("Track failed", error: error)
            }
            endAction()
        }
    }

    func exposeCurrentFlag() {
        guard guardConfigured() else { return }
        Task {
            do {
                beginAction("Sending exposure...")
                try await client.expose(flagKey: flagKey)
                lastRefreshStatus = "Exposure sent @ \(isoNow())"
                clearError()
                setBannerSuccess("Exposure sent for \(flagKey).")
                appendLog("Sent exposure for \(flagKey)")
            } catch {
                setFailure("Expose failed", error: error)
            }
            endAction()
        }
    }

    func toggleAutoRefresh() {
        autoRefreshEnabled.toggle()
        refreshTask?.cancel()
        guard autoRefreshEnabled else {
            appendLog("Stopped manual auto-refresh loop")
            return
        }
        appendLog("Started manual auto-refresh loop (15s)")

        refreshTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    try await client.refresh()
                    await MainActor.run {
                        self.lastRefreshStatus = "Manual auto-refresh succeeded @ \(self.isoNow())"
                        self.setBannerSuccess("Auto refresh succeeded.")
                        self.appendLog("Manual auto-refresh succeeded")
                    }
                } catch {
                    await MainActor.run {
                        self.lastRefreshStatus = "Auto refresh failed @ \(self.isoNow())"
                        self.setFailure("Auto refresh failed", error: error)
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
            setBannerError(lastError)
            return false
        }
        return true
    }

    private func clearError() {
        lastError = ""
    }

    private func ensureClientSubscription() async {
        guard clientSubscriptionToken == nil else { return }
        let token = await client.subscribe { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.syncFromClientState(status: "Live update received @ \(self.isoNow())")
            }
        }
        clientSubscriptionToken = token
    }

    private func syncFromClientState(status: String? = nil) async {
        let state = await client.getState()
        isReady = state.ready
        activeUserID = state.userId.isEmpty ? activeUserID : state.userId
        streamStatus = state.streamStatus
        pollingActive = state.pollingActive
        lastStreamEventAt = state.lastStreamEventAt ?? "-"
        lastStreamEventVersion = state.lastStreamEventVersion ?? "-"
        if let status {
            lastRefreshStatus = status
        }
        if let lastError = state.lastError, !lastError.isEmpty {
            self.lastError = lastError
        }
        if lastObservedStreamStatus != state.streamStatus {
            appendLog("Stream status -> \(state.streamStatus)")
            lastObservedStreamStatus = state.streamStatus
        }
        if lastObservedPollingActive != state.pollingActive {
            appendLog("Polling active -> \(state.pollingActive ? "yes" : "no")")
            lastObservedPollingActive = state.pollingActive
        }
        if lastObservedStreamEventAt != state.lastStreamEventAt {
            if let at = state.lastStreamEventAt {
                let version = state.lastStreamEventVersion ?? "-"
                appendLog("Stream event received @ \(at), version=\(version)")
            }
            lastObservedStreamEventAt = state.lastStreamEventAt
        }

        if !flagKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let payload = payloadFromState(state, flagKey: flagKey)
            assignmentReason = payload["reason"] as? String ?? ""
            configVersion = state.configVersion ?? (payload["configVersion"] as? String ?? "")
            rawPayload = prettyJSON(payload)
        } else {
            configVersion = state.configVersion ?? ""
        }
    }

    private func beginAction(_ title: String) {
        currentAction = title
    }

    private func endAction() {
        currentAction = ""
    }

    private func setBannerSuccess(_ message: String) {
        bannerMessage = message
        bannerIsError = false
    }

    private func setBannerError(_ message: String) {
        bannerMessage = message
        bannerIsError = true
    }

    private func setFailure(_ prefix: String, error: Error) {
        lastError = "\(prefix): \(error.localizedDescription)"
        setBannerError(lastError)
        appendLog(lastError)
    }

    func clearLogs() {
        logs.removeAll(keepingCapacity: true)
        appendLog("Logs cleared")
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func payloadFromState(_ state: TruflagClientState, flagKey: String) -> [String: Any] {
        guard let payload = state.flags[flagKey]?.payload else { return [:] }
        return payload.mapValues { $0.value }
    }

    private func renderRawValue(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double { return String(double) }
        if let string = value as? String { return string }
        if let object = value as? [String: Any] {
            return prettyJSON(object)
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private func appendLog(_ message: String) {
        let line = "[\(isoNow())] \(message)"
        logs.append(line)
        if logs.count > 400 {
            logs.removeFirst(logs.count - 400)
        }
    }
}
