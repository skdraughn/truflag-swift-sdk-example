import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SampleViewModel()

    var body: some View {
        NavigationView {
            Form {
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
                        Button("Read flag") { vm.readFlag() }
                        Spacer()
                        Button("Send exposure") { vm.exposeCurrentFlag() }
                    }
                    Text("Last value: \(vm.lastFlagValue)")
                    Text("Reason: \(vm.assignmentReason.isEmpty ? "-" : vm.assignmentReason)")
                    Text("Config version: \(vm.configVersion.isEmpty ? "-" : vm.configVersion)")
                    TextEditor(text: .constant(vm.rawPayload))
                        .frame(minHeight: 100)
                        .font(.system(.footnote, design: .monospaced))
                }

                Section("Refresh") {
                    HStack {
                        Button("Refresh now") { vm.refresh() }
                        Spacer()
                        Button(vm.autoRefreshEnabled ? "Stop auto-refresh" : "Start auto-refresh") {
                            vm.toggleAutoRefresh()
                        }
                    }
                }

                Section("Events") {
                    TextField("Event name", text: $vm.eventName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextEditor(text: $vm.eventPropertiesJSON)
                        .frame(minHeight: 100)
                        .font(.system(.footnote, design: .monospaced))
                    Button("Send event") {
                        vm.sendEvent()
                    }
                }

                Section("Debug") {
                    DebugRow(label: "Configured", value: vm.isConfigured ? "yes" : "no")
                    DebugRow(label: "Ready", value: vm.isReady ? "yes" : "no")
                    DebugRow(label: "Active user", value: vm.activeUserID.isEmpty ? "-" : vm.activeUserID)
                    DebugRow(label: "Last refresh", value: vm.lastRefreshStatus)
                    if !vm.lastError.isEmpty {
                        Text(vm.lastError)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Truflag iOS Sample")
        }
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
