import SwiftUI

/// Settings tab for the AI Usage widget: which providers show, in which order
/// (drag to reorder), and user-defined custom providers.
struct AIUsageSettings: View {
    @Bindable var settings: AppSettings

    @State private var editing: CustomAIProvider?

    /// Every source, enabled ones first in their saved order.
    private var allKeys: [String] {
        let all = AIProvider.allCases.map(\.rawValue) + settings.customProviders.map(\.key)
        return settings.usageSourceKeys.filter(all.contains) + all.filter { !settings.usageSourceKeys.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $settings.aiUsageEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show AI Usage in the notch").font(.system(size: 13, weight: .semibold))
                    Text("Adds a tab with your coding assistants' usage limits.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Text("Drag to reorder. The notch shows enabled providers left to right, and hides tools that aren't set up on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            List {
                Section("Providers") {
                    ForEach(allKeys, id: \.self) { key in
                        if let source = UsageSource.resolve(key, customs: settings.customProviders) {
                            SourceRow(source: source,
                                      isOn: binding(for: key),
                                      edit: source.custom.map { custom in { editing = custom } })
                        }
                    }
                    .onMove(perform: move)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .disabled(!settings.aiUsageEnabled)
            .opacity(settings.aiUsageEnabled ? 1 : 0.5)

            HStack {
                Button {
                    editing = CustomAIProvider()
                } label: {
                    Label("Add Custom Provider…", systemImage: "plus")
                }
                Spacer()
                Text("Sign-ins are read from each tool; Lenotch never stores a login.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .sheet(item: $editing) { provider in
            CustomProviderEditor(provider: provider,
                                 isNew: !settings.customProviders.contains { $0.id == provider.id },
                                 save: save, delete: delete)
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { settings.usageSourceKeys.contains(key) },
            set: { isOn in
                if isOn {
                    // Keep the visible order: insert where it sits in the full list.
                    settings.usageSourceKeys = allKeys.filter { $0 == key || settings.usageSourceKeys.contains($0) }
                } else {
                    settings.usageSourceKeys.removeAll { $0 == key }
                }
            })
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var keys = allKeys
        keys.move(fromOffsets: offsets, toOffset: destination)
        settings.usageSourceKeys = keys.filter(settings.usageSourceKeys.contains)
    }

    private func save(_ provider: CustomAIProvider, apiKey: String?) {
        if let index = settings.customProviders.firstIndex(where: { $0.id == provider.id }) {
            settings.customProviders[index] = provider
        } else {
            settings.customProviders.append(provider)
            settings.usageSourceKeys.append(provider.key)
        }
        if let apiKey { provider.saveAPIKey(apiKey) }
        editing = nil
    }

    private func delete(_ provider: CustomAIProvider) {
        provider.deleteAPIKey()
        settings.customProviders.removeAll { $0.id == provider.id }
        settings.usageSourceKeys.removeAll { $0 == provider.key }
        editing = nil
    }
}

private struct SourceRow: View {
    let source: UsageSource
    @Binding var isOn: Bool
    let edit: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            ZStack {
                Circle().fill(Color.primary.opacity(0.08))
                ProviderGlyphView(glyph: source.glyph, size: 15)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title).font(.system(size: 13, weight: .medium))
                Text(source.custom.map { $0.url.isEmpty ? "Custom endpoint" : $0.url }
                        ?? AIProvider(rawValue: source.id)?.source ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let edit {
                Button("Edit…", action: edit).buttonStyle(.borderless)
            }
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

/// Sheet for adding or editing a custom provider, with a live test.
private struct CustomProviderEditor: View {
    @State var provider: CustomAIProvider
    let isNew: Bool
    let save: (CustomAIProvider, String?) -> Void
    let delete: (CustomAIProvider) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var keyEdited = false
    @State private var testResult: ProviderUsage?
    @State private var isTesting = false

    private static let symbols = ["sparkles", "brain", "cpu", "bolt.fill", "wand.and.stars", "cloud.fill",
                                  "server.rack", "terminal.fill", "star.fill", "flame.fill"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Provider") {
                    TextField("Name", text: $provider.name)
                    Picker("Symbol", selection: $provider.symbol) {
                        ForEach(Self.symbols, id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                    TextField("Label", text: $provider.label, prompt: Text("Usage"))
                }
                Section {
                    TextField("URL", text: $provider.url, prompt: Text("https://api.example.com/v1/usage"))
                    TextField("Auth header", text: $provider.authHeader, prompt: Text("Authorization"))
                    TextField("Prefix", text: $provider.authPrefix, prompt: Text("Bearer "))
                    SecureField(isNew ? "API key" : "API key (leave empty to keep)", text: $apiKey)
                        .onChange(of: apiKey) { keyEdited = true }
                } header: {
                    Text("Request")
                } footer: {
                    Text("Sent as a GET request. The key is stored in your keychain.")
                }
                Section {
                    Picker("Response has", selection: $provider.mode) {
                        ForEach(CustomAIProvider.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    TextField(provider.mode == .percent ? "Percent path" : provider.mode == .usedAndLimit ? "Used path" : "Remaining path",
                              text: $provider.valuePath, prompt: Text("data.usage.percent"))
                    if provider.mode != .percent {
                        TextField("Limit path", text: $provider.limitPath, prompt: Text("data.usage.limit"))
                    }
                    TextField("Reset path (optional)", text: $provider.resetPath, prompt: Text("data.usage.resets_at"))
                } header: {
                    Text("Reading the JSON")
                } footer: {
                    Text("Dot paths into the response; use numbers for list items, e.g. limits.0.used.")
                }
                Section("Test") {
                    HStack {
                        Button(isTesting ? "Testing…" : "Test Request", action: test).disabled(isTesting)
                        Spacer()
                        testLabel
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { delete(provider) }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save(provider, keyEdited ? apiKey : nil) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(provider.name.isEmpty || provider.url.isEmpty || provider.valuePath.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480, height: 600)
    }

    @ViewBuilder
    private var testLabel: some View {
        switch testResult {
        case .ok(_, let windows)?:
            if let window = windows.first {
                Text("\(window.label): \(Int((window.used * 100).rounded()))% used").foregroundStyle(.green)
            }
        case .problem(let message)?:
            Text(message).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private func test() {
        isTesting = true
        // Test with the key as typed, without saving it: a throwaway id keeps the real one untouched.
        var probe = provider
        if keyEdited {
            probe.id = UUID()
            probe.saveAPIKey(apiKey)
        }
        Task {
            testResult = await AIUsageService.test(probe)
            if keyEdited { probe.deleteAPIKey() }
            isTesting = false
        }
    }
}
