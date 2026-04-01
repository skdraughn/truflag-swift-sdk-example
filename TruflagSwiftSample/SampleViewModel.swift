import Foundation
import TruflagSDK
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SampleViewModel: ObservableObject {
    actor FetchFaultInjector {
        private var pendingFlagFailures: Int = 0

        func addFlagFailures(_ count: Int) -> Int {
            pendingFlagFailures = max(0, pendingFlagFailures + count)
            return pendingFlagFailures
        }

        func consumeIfNeeded(for request: URLRequest) -> Bool {
            guard pendingFlagFailures > 0 else { return false }
            guard request.httpMethod?.uppercased() == "GET" else { return false }
            guard request.url?.path == "/v1/flags" else { return false }
            pendingFlagFailures -= 1
            return true
        }

        func pendingCount() -> Int {
            pendingFlagFailures
        }
    }

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
    @Published var flagKey: String = "economyvariation" {
        didSet {
            Task { @MainActor in
                self.restartFlagStreamObservation()
            }
        }
    }
    @Published var fallbackType: FallbackType = .string
    @Published var fallbackRawValue: String = "coins"
    @Published var eventName: String = "demo_event"
    @Published var eventPropertiesJSON: String = "{\n  \"source\": \"ios-swift-sample\"\n}"
    @Published var trackImmediateFlush: Bool = false
    @Published var autoExposeOnStateRead: Bool = true

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
    @Published private(set) var pendingInjectedRefreshFailures: Int = 0
    @Published private(set) var logs: [String] = []

    private var client = TruflagClient()
    private let fetchFaultInjector = FetchFaultInjector()
    private var refreshTask: Task<Void, Never>?
    private var stateStreamTask: Task<Void, Never>?
    private var logStreamTask: Task<Void, Never>?
    private var flagStreamTask: Task<Void, Never>?
    private var observedFlagKey: String = ""
    private var lastObservedStreamStatus: String = ""
    private var lastObservedPollingActive: Bool?
    private var lastObservedStreamEventAt: String?
    private var cachedState: TruflagClientState?
    private var lastActionStartedAtMs: Int64 = 0

    func configure() {
        guard startAction("Configuring SDK...") else { return }
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
        let injector = fetchFaultInjector
        let fetchFn: TruflagFetchFunction = { request in
            if await injector.consumeIfNeeded(for: request) {
                throw URLError(.timedOut)
            }
            return try await URLSession.shared.data(for: request)
        }
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
            telemetryEnabled: options.telemetryEnabled,
            fetchFn: fetchFn,
            debugLoggingEnabled: true
        )

        Task {
            defer { endAction() }
            do {
                try await client.configure(tunedOptions)
                appendLog("Configured SDK. streamEnabled=\(tunedOptions.streamEnabled), streamURL=\(tunedOptions.streamURL.absoluteString)")
                isConfigured = true
                activeUserID = user.id
                await ensureClientStreams()
                await syncFromClientState(status: "Configured. Waiting for first refresh...")
                await refreshPendingInjectedFailures()
                setBannerSuccess("SDK configured. Initial refresh runs in background.")
            } catch {
                setFailure("Configure failed", error: error)
            }
        }
    }

    func refresh() {
        guard guardConfigured() else { return }
        guard startAction("Refreshing flags...") else { return }
        appendLog("UI action -> refresh()")
        Task {
            defer { endAction() }
            do {
                try await client.refresh()
                appendLog("Manual refresh succeeded")
                await syncFromClientState(status: "Refresh succeeded @ \(isoNow())")
                await refreshPendingInjectedFailures()
                clearError()
                setBannerSuccess("Flags refreshed.")
            } catch {
                lastRefreshStatus = "Refresh failed @ \(isoNow())"
                await refreshPendingInjectedFailures()
                setFailure("Refresh failed", error: error)
            }
        }
    }

    func readFlag() {
        appendLog("UI action -> readFlag(state)")
        guard guardConfigured() else { return }
        if let state = cachedState {
            applyReadResult(from: state, status: "Read from current SDK state @ \(isoNow())")
            let payload = payloadFromState(state, flagKey: flagKey)
            assignmentReason = payload["reason"] as? String ?? ""
            configVersion = state.configVersion ?? (payload["configVersion"] as? String ?? "")
            rawPayload = prettyJSON(payload)
        } else {
            Task {
                await syncFromClientState(status: "Read from current SDK state @ \(isoNow())")
            }
        }
        if autoExposeOnStateRead {
            client.notifyFlagRead(flagKey: flagKey)
            appendLog("Auto exposure enqueued for \(flagKey) via notifyFlagRead()")
        }
        setBannerSuccess("Read \(flagKey) from current state.")
    }

    func refreshAndReadFlag() {
        appendLog("UI action -> refreshAndReadFlag()")
        guard guardConfigured() else { return }
        guard startAction("Reading flag...") else { return }
        Task {
            defer { endAction() }
            do {
                try await client.refresh()
                await syncFromClientState(status: "Read after refresh @ \(isoNow())")
            } catch {
                setBannerError("Refresh before read failed. Reading cached value.")
                appendLog("Refresh before read failed; using cached state")
            }

            let state = await client.getState()
            applyReadResult(from: state, status: nil)
            let payload = payloadFromState(state, flagKey: flagKey)
            assignmentReason = payload["reason"] as? String ?? ""
            configVersion = state.configVersion ?? (payload["configVersion"] as? String ?? "")
            rawPayload = prettyJSON(payload)
            setBannerSuccess("Refreshed and read \(flagKey).")
        }
    }

    func login() {
        guard guardConfigured() else { return }
        guard startAction("Logging in...") else { return }
        appendLog("UI action -> login()")
        Task {
            defer { endAction() }
            do {
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
        }
    }

    func setAttributes() {
        guard guardConfigured() else { return }
        guard startAction("Updating attributes...") else { return }
        appendLog("UI action -> setAttributes()")
        Task {
            defer { endAction() }
            do {
                try await client.setAttributes(buildAttributes())
                await syncFromClientState(status: "Attributes updated")
                clearError()
                setBannerSuccess("Attributes updated.")
                appendLog("Updated attributes")
            } catch {
                setFailure("Set attributes failed", error: error)
            }
        }
    }

    func logout() {
        guard guardConfigured() else { return }
        guard startAction("Logging out...") else { return }
        appendLog("UI action -> logout()")
        Task {
            defer { endAction() }
            do {
                try await client.logout()
                activeUserID = "anonymous"
                await syncFromClientState(status: "Logout succeeded")
                clearError()
                setBannerSuccess("Logged out.")
                appendLog("Logged out")
            } catch {
                setFailure("Logout failed", error: error)
            }
        }
    }

    func sendEvent() {
        guard guardConfigured() else { return }
        guard startAction("Sending event...") else { return }
        appendLog("UI action -> sendEvent()")
        Task {
            defer { endAction() }
            do {
                let props = parseProperties(eventPropertiesJSON)
                try await client.track(eventName: eventName, properties: props, immediate: trackImmediateFlush)
                lastRefreshStatus = "Event sent @ \(isoNow())"
                clearError()
                setBannerSuccess("Event \(eventName) sent.")
                appendLog("Sent event \(eventName) immediate=\(trackImmediateFlush)")
            } catch {
                setFailure("Track failed", error: error)
            }
        }
    }

    func exposeCurrentFlag() {
        guard guardConfigured() else { return }
        guard startAction("Sending exposure...") else { return }
        appendLog("UI action -> exposeCurrentFlag()")
        Task {
            defer { endAction() }
            do {
                try await client.expose(flagKey: flagKey)
                lastRefreshStatus = "Exposure sent @ \(isoNow())"
                clearError()
                setBannerSuccess("Exposure sent for \(flagKey).")
                appendLog("Sent exposure for \(flagKey)")
            } catch {
                setFailure("Expose failed", error: error)
            }
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

    func failNextRefresh() {
        guard guardConfigured() else { return }
        Task {
            let pending = await fetchFaultInjector.addFlagFailures(1)
            pendingInjectedRefreshFailures = pending
            setBannerSuccess("Next refresh failure injected. Pending failures: \(pending)")
            appendLog("Injected one /v1/flags failure. pending=\(pending)")
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

    private func ensureClientStreams() async {
        if stateStreamTask == nil {
            stateStreamTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let stream = await self.client.stateStream()
                for await state in stream {
                    self.applyStateSnapshot(state, status: nil)
                }
            }
        }

        if logStreamTask == nil {
            logStreamTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let stream = await self.client.debugLogStream()
                for await line in stream {
                    self.appendSDKLogIfRelevant(line)
                }
            }
        }

        restartFlagStreamObservation()
    }

    private func restartFlagStreamObservation() {
        let key = flagKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConfigured, !key.isEmpty else { return }
        guard observedFlagKey != key || flagStreamTask == nil else { return }

        flagStreamTask?.cancel()
        observedFlagKey = key
        flagStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.client.flagStream(key)
            for await flag in stream {
                self.applyFlagSnapshot(flag)
            }
        }
    }

    private func syncFromClientState(status: String? = nil) async {
        let state = await client.getState()
        applyStateSnapshot(state, status: status)
    }

    private func refreshPendingInjectedFailures() async {
        pendingInjectedRefreshFailures = await fetchFaultInjector.pendingCount()
    }

    private func applyStateSnapshot(_ state: TruflagClientState, status: String?) {
        cachedState = state
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
            applyReadResult(from: state, status: nil)
            let payload = payloadFromState(state, flagKey: flagKey)
            assignmentReason = payload["reason"] as? String ?? ""
            configVersion = state.configVersion ?? (payload["configVersion"] as? String ?? "")
            rawPayload = prettyJSON(payload)
        } else {
            configVersion = state.configVersion ?? ""
        }
    }

    private func applyFlagSnapshot(_ flag: TruflagFlag?) {
        guard !flagKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let raw = flag?.value.value {
            lastFlagValue = renderRawValue(raw)
        } else {
            switch fallbackType {
            case .bool:
                lastFlagValue = String((fallbackRawValue as NSString).boolValue)
            case .string:
                lastFlagValue = fallbackRawValue
            case .number:
                lastFlagValue = String(Double(fallbackRawValue) ?? 0)
            }
        }

        let payload = (flag?.payload ?? [:]).mapValues { $0.value }
        assignmentReason = payload["reason"] as? String ?? ""
        if configVersion.isEmpty {
            configVersion = payload["configVersion"] as? String ?? ""
        }
        rawPayload = prettyJSON(payload)
    }

    private func beginAction(_ title: String) {
        currentAction = title
    }

    private func startAction(_ title: String) -> Bool {
        if !currentAction.isEmpty {
            appendLog("Ignored action '\(title)' because '\(currentAction)' is in progress")
            return false
        }
        let now = nowMs()
        if now - lastActionStartedAtMs < 350 {
            appendLog("Ignored action '\(title)' due to tap cooldown")
            return false
        }
        lastActionStartedAtMs = now
        beginAction(title)
        return true
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

    func copyLogs() {
        let text = logs.joined(separator: "\n")
#if canImport(UIKit)
        UIPasteboard.general.string = text
        setBannerSuccess("Logs copied to clipboard.")
#else
        setBannerError("Clipboard copy is unavailable on this platform.")
#endif
        appendLog("Copied logs to clipboard")
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func payloadFromState(_ state: TruflagClientState, flagKey: String) -> [String: Any] {
        guard let payload = state.flags[flagKey]?.payload else { return [:] }
        return payload.mapValues { $0.value }
    }

    private func applyReadResult(from state: TruflagClientState, status: String?) {
        if let status {
            lastRefreshStatus = status
        }
        if let raw = state.flags[flagKey]?.value.value {
            lastFlagValue = renderRawValue(raw)
        } else {
            switch fallbackType {
            case .bool:
                lastFlagValue = String((fallbackRawValue as NSString).boolValue)
            case .string:
                lastFlagValue = fallbackRawValue
            case .number:
                lastFlagValue = String(Double(fallbackRawValue) ?? 0)
            }
        }
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

    private func appendSDKLogIfRelevant(_ line: String) {
        guard line.hasPrefix("[TruflagSDK][DEBUG]") else { return }
        guard shouldIncludeSDKLog(line) else { return }
        appendLogLine(line)
    }

    private func shouldIncludeSDKLog(_ line: String) -> Bool {
        let keys = [
            "Truflag refresh started",
            "Truflag stale config detected, retrying fresh fetch",
            "Truflag refresh succeeded",
            "Truflag refresh failed",
            "refresh() source=",
            "joined in-flight refresh",
            "Truflag stream",
            "Stream status",
            "HTTP GET",
            "HTTP POST",
            "telemetry",
            "track()",
            "expose()",
            "notifyFlagRead()",
        ]
        return keys.contains { line.contains($0) }
    }

    private func appendLogLine(_ line: String) {
        logs.append(line)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    private func appendLog(_ message: String) {
        appendLogLine("[Sample][\(isoNow())] \(message)")
    }
}
