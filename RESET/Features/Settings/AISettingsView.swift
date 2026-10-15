import SwiftUI

struct AISettingsView: View {
    @Bindable var profile: UserProfile
    @State private var anthropic = Keychain.get(Keychain.anthropicKey) ?? ""
    @State private var openAI = Keychain.get(Keychain.openAIKey) ?? ""
    @State private var proxyToken = Keychain.get(Keychain.proxyToken) ?? ""
    @State private var usda = Keychain.get(Keychain.usdaKey) ?? ""
    @State private var openAIBase = UserDefaults.standard.string(forKey: AIConfig.openAIBaseKey) ?? "https://api.x.ai/v1"
    @State private var proxyBase = UserDefaults.standard.string(forKey: AIConfig.proxyBaseKey) ?? ""

    private var kind: AIConfig.Kind { AIConfig.Kind(rawValue: profile.aiProviderRaw) ?? .anthropic }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $profile.aiProviderRaw) {
                    ForEach(AIConfig.Kind.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if kind != .proxy { TextField("Model", text: $profile.aiModel).textInputAutocapitalization(.never).autocorrectionDisabled() }
                switch kind {
                case .anthropic:
                    SecureField("Anthropic API key", text: $anthropic).onSubmit { Keychain.set(anthropic, for: Keychain.anthropicKey) }
                case .openai:
                    TextField("Base URL (https)", text: $openAIBase).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API key", text: $openAI).onSubmit { Keychain.set(openAI, for: Keychain.openAIKey) }
                    Text("This adapter follows the Chat Completions format and has not been tested against a live account. Check your provider's docs for the right base URL and a vision model.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                case .proxy:
                    TextField("Proxy URL", text: $proxyBase).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Proxy token", text: $proxyToken).onSubmit { Keychain.set(proxyToken, for: Keychain.proxyToken) }
                }
                Button("Save credentials", action: save)
            } header: {
                Text("AI service")
            } footer: {
                Text("Keys are stored in the iOS Keychain on this device only. For anything beyond personal use, run the included backend proxy so the provider key never sits on the phone. Descriptions and meal photos you analyze are sent to the provider. Location and history are not.")
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
        .onDisappear(perform: save)
    }

    private func save() {
        Keychain.set(anthropic, for: Keychain.anthropicKey)
        Keychain.set(openAI, for: Keychain.openAIKey)
        Keychain.set(proxyToken, for: Keychain.proxyToken)
        Keychain.set(usda, for: Keychain.usdaKey)
        let d = UserDefaults.standard
        d.set(openAIBase.trimmingCharacters(in: .whitespaces), forKey: AIConfig.openAIBaseKey)
        d.set(proxyBase.trimmingCharacters(in: .whitespaces), forKey: AIConfig.proxyBaseKey)
    }
}
