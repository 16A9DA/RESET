import SwiftUI

struct AISettingsView: View {
    @Bindable var profile: UserProfile
    @State private var keys: [AIConfig.Kind: String] = [:]
    @State private var models: [AIConfig.Kind: String] = [:]
    @State private var usda = Keychain.get(Keychain.usdaKey) ?? ""
    @State private var customBase = UserDefaults.standard.string(forKey: AIConfig.customBaseKey) ?? "https://api.x.ai/v1"
    @State private var proxyBase = UserDefaults.standard.string(forKey: AIConfig.proxyBaseKey) ?? ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, message: String)?

    private var kind: AIConfig.Kind { AIConfig.Kind(rawValue: profile.aiProviderRaw) ?? .anthropic }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $profile.aiProviderRaw) {
                    ForEach(AIConfig.Kind.allCases) { k in
                        Text(k.title).tag(k.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                ForEach(AIConfig.Kind.allCases) { k in
                    HStack {
                        Text(k.title).font(.footnote)
                        Spacer()
                        Text(AIConfig.hasCredentials(k) ? "Key saved" : "No key").font(.caption)
                            .foregroundStyle(AIConfig.hasCredentials(k) ? Theme.good : Theme.secondaryText)
                    }
                }
            } header: {
                Text("Choose a provider")
            } footer: {
                Text("Only the selected provider is used. Each keeps its own key and model, so you can switch at any time.")
            }

            Section {
                switch kind {
                case .anthropic:
                    keyField("Anthropic API key", .anthropic)
                    modelField("Model", .anthropic, placeholder: AIConfig.Kind.anthropic.defaultModel)
                case .openai:
                    keyField("OpenAI API key", .openai)
                    modelField("Model", .openai, placeholder: "A vision capable model from your account")
                    Text("Enter a model name that supports images and tools, as listed in your OpenAI account. The app does not guess one. Some reasoning models reject tool calls; if Test connection or the coach fails, try a non-reasoning model.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                case .custom:
                    TextField("Base URL (https)", text: $customBase).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    keyField("API key", .custom)
                    modelField("Model", .custom, placeholder: "Model name from your provider")
                    Text("For services that copy the OpenAI Chat Completions format. Check your provider's docs for the base URL and a vision model. xAI documents a /v1/responses API that this option does not use.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                case .proxy:
                    TextField("Proxy URL", text: $proxyBase).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    keyField("Proxy token", .proxy)
                    Text("The proxy holds the provider key and chooses the model on the server. Setup steps are in section 7 of the repository README.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Button(testing ? "Testing" : "Save and test connection") { Task { await saveAndTest() } }.disabled(testing)
                if let t = testResult {
                    Text(t.message).font(.footnote).foregroundStyle(t.ok ? Theme.good : Theme.low)
                }
            } header: {
                Text(kind.title)
            } footer: {
                Text("Keys are stored in the iOS Keychain on this device only, never in the app's files or source. A test sends one short message and uses a tiny amount of credit. Descriptions and meal photos you analyze are sent to the selected provider. Location and history are not.")
            }

            Section {
                SecureField("USDA FoodData Central key", text: $usda).onSubmit { save() }
            } header: {
                Text("Nutrition database")
            } footer: {
                Text("Free key from fdc.nal.usda.gov. Without one the shared demo key allows about 30 searches an hour.")
            }
            Section {
                Toggle("Save food automatically when the AI is confident", isOn: $profile.autoSaveFood)
            } footer: {
                Text("Entries with uncertain portions, sauces or missing data always ask first. Auto-saved entries stay labeled as estimates.")
            }
        }
        .navigationTitle("AI and data sources")
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .onChange(of: profile.aiProviderRaw) { _, _ in testResult = nil }
    }

    private func keyField(_ title: String, _ k: AIConfig.Kind) -> some View {
        SecureField(title, text: Binding(get: { keys[k] ?? "" }, set: { keys[k] = $0 }))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
    }

    private func modelField(_ title: String, _ k: AIConfig.Kind, placeholder: String) -> some View {
        TextField(placeholder, text: Binding(get: { models[k] ?? "" }, set: { models[k] = $0 }))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
    }

    private func load() {
        for k in AIConfig.Kind.allCases {
            if let key = k.keychainKey { keys[k] = Keychain.get(key) ?? "" }
            models[k] = AIConfig.model(for: k, profile: profile)
        }
    }

    private func save() {
        for k in AIConfig.Kind.allCases {
            if let key = k.keychainKey, let v = keys[k] { Keychain.set(v.trimmingCharacters(in: .whitespacesAndNewlines), for: key) }
            if k != .proxy, let m = models[k] { AIConfig.setModel(m, for: k) }
        }
        Keychain.set(usda.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.usdaKey)
        let d = UserDefaults.standard
        d.set(customBase.trimmingCharacters(in: .whitespaces), forKey: AIConfig.customBaseKey)
        d.set(proxyBase.trimmingCharacters(in: .whitespaces), forKey: AIConfig.proxyBaseKey)
    }

    private func saveAndTest() async {
        save()
        testing = true; defer { testing = false }
        guard let p = AIConfig.provider(kind: kind.rawValue, profile: profile) else {
            testResult = (false, "Not fully set up yet. Check the key, model and URL fields.")
            return
        }
        testResult = await AIConfig.test(p)
    }
}
