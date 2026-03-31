import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SampleViewModel()
    @State private var showFlagPayload = false
    @State private var showLogs = true

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if !vm.currentAction.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(vm.currentAction)
                                    .font(.subheadline)
                            }
                        } else {
                            Text(vm.bannerMessage)
                                .font(.subheadline)
                                .foregroundColor(vm.bannerIsError ? .red : .green)
                        }
                    }
                }

                Section("Configure") {
                    TextField("Client-side ID (env_c_...)", text: $vm.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("Relay URL", text: $vm.relayURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Button("Configure SDK") {
                        vm.configure()
                    }
                    .disabled(!vm.currentAction.isEmpty)
                }

                Section("Identity") {
                    TextField("User ID", text: $vm.userId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("country", text: $vm.country)
                    Toggle("hasCompletedOnboarding", isOn: $vm.hasCompletedOnboarding)
                    TextField("createdAt ISO", text: $vm.createdAtISO)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    HStack {
                        Button("Login") { vm.login() }
                        Spacer()
                        Button("Set attributes") { vm.setAttributes() }
                        Spacer()
                        Button("Logout") { vm.logout() }
                    }
                    .disabled(!vm.currentAction.isEmpty)
                }

                Section("Flags") {
                    TextField("Flag key", text: $vm.flagKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Picker("Fallback type", selection: $vm.fallbackType) {
                        ForEach(SampleViewModel.FallbackType.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    TextField("Fallback value", text: $vm.fallbackRawValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    HStack {
                        Button("Refresh + Read flag") { vm.readFlag() }
                        Spacer()
                        Button("Send exposure") { vm.exposeCurrentFlag() }
                    }
                    .disabled(!vm.currentAction.isEmpty)
                    Text("Last value: \(vm.lastFlagValue)")
                    Text("Reason: \(vm.assignmentReason.isEmpty ? "-" : vm.assignmentReason)")
                    Text("Config version: \(vm.configVersion.isEmpty ? "-" : vm.configVersion)")
                    DisclosureGroup("Flag payload JSON", isExpanded: $showFlagPayload) {
                        TextEditor(text: .constant(vm.rawPayload))
                            .frame(minHeight: 56)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }

                Section("Refresh / fallback polling") {
                    HStack {
                        Button("Refresh now") { vm.refresh() }
                        Spacer()
                        Button(vm.autoRefreshEnabled ? "Stop auto-refresh" : "Start auto-refresh") {
                            vm.toggleAutoRefresh()
                        }
                    }
                    .disabled(!vm.currentAction.isEmpty)
                }

                Section("Events") {
                    TextField("Event name", text: $vm.eventName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextEditor(text: $vm.eventPropertiesJSON)
                        .frame(minHeight: 56)
                        .font(.system(.footnote, design: .monospaced))
                    Button("Send event") {
                        vm.sendEvent()
                    }
                    .disabled(!vm.currentAction.isEmpty)
                }

                Section("Debug") {
                    DebugRow(label: "Configured", value: vm.isConfigured ? "yes" : "no")
                    DebugRow(label: "Ready", value: vm.isReady ? "yes" : "no")
                    DebugRow(label: "Stream", value: vm.streamStatus)
                    DebugRow(label: "Polling", value: vm.pollingActive ? "active" : "off")
                    DebugRow(label: "Active user", value: vm.activeUserID.isEmpty ? "-" : vm.activeUserID)
                    DebugRow(label: "Last refresh", value: vm.lastRefreshStatus)
                    if !vm.lastError.isEmpty {
                        Text(vm.lastError)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    DisclosureGroup("Live SDK logs", isExpanded: $showLogs) {
                        if vm.logs.isEmpty {
                            Text("No logs yet.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(.caption2, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxHeight: 220)
                        }
                        Button("Clear logs") {
                            vm.clearLogs()
                        }
                    }
                }
            }
            .navigationTitle("Truflag iOS Sample")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

private struct DebugRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
