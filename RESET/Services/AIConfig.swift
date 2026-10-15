import Foundation
import UIKit
import ResetCore

/// Builds the selected AI provider from the Keychain and defaults. Returns nil when it is not fully set up,
/// which keeps every non-AI feature working. Each provider keeps its own key and model so switching is safe.
enum AIConfig {
    enum Kind: String, CaseIterable, Identifiable {
        case anthropic, openai, custom, proxy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .anthropic: "Anthropic (Claude)"
            case .openai: "OpenAI"
            case .custom: "Other OpenAI-compatible (xAI and similar)"
            case .proxy: "RE:SET backend proxy"
            }
        }
        var keychainKey: String? {
            switch self {
            case .anthropic: Keychain.anthropicKey
            case .openai: Keychain.openAIKey
            case .custom: Keychain.customKey
            case .proxy: Keychain.proxyToken
            }
        }
        /// Only Anthropic has a suggested model. OpenAI and others rename models often, so the user enters one
        /// that supports images from their own account instead of the app guessing.
        var defaultModel: String { self == .anthropic ? "claude-sonnet-5-5" : "" }
    }

    static let customBaseKey = "ai.custom.baseURL"
    static let proxyBaseKey = "ai.proxy.baseURL"
    private static func modelKey(_ k: Kind) -> String { "ai.model.\(k.rawValue)" }

    static func model(for kind: Kind, profile: UserProfile? = nil) -> String {
        if let m = UserDefaults.standard.string(forKey: modelKey(kind)), !m.isEmpty { return m }
        // Earlier builds kept one model on the profile, used by Anthropic.
        if kind == .anthropic, let m = profile?.aiModel, !m.isEmpty { return m }
        return kind.defaultModel
    }

    static func setModel(_ m: String, for kind: Kind) {
        UserDefaults.standard.set(m.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelKey(kind))
    }

    static func hasCredentials(_ kind: Kind) -> Bool {
        guard let k = kind.keychainKey, let v = Keychain.get(k), !v.isEmpty else { return false }
        return true
    }

    static func provider(kind rawKind: String, profile: UserProfile? = nil) -> AIProvider? {
        let kind = Kind(rawValue: rawKind) ?? .anthropic
        let d = UserDefaults.standard
        guard let k = kind.keychainKey.flatMap(Keychain.get), !k.isEmpty else { return nil }
        let model = model(for: kind, profile: profile)
        switch kind {
        case .anthropic:
            guard !model.isEmpty else { return nil }
            return AnthropicProvider(apiKey: k, model: model)
        case .openai:
            guard !model.isEmpty else { return nil }
            return OpenAICompatibleProvider.openAI(apiKey: k, model: model)
        case .custom:
            guard !model.isEmpty, let s = d.string(forKey: customBaseKey), let url = URL(string: s), url.scheme == "https" else { return nil }
            return OpenAICompatibleProvider(apiKey: k, model: model, baseURL: url)
        case .proxy:
            guard let s = d.string(forKey: proxyBaseKey), let url = URL(string: s), ["https", "http"].contains(url.scheme) else { return nil }
            return ProxyProvider(baseURL: url, token: k)
        }
    }

    static func provider(for profile: UserProfile?) -> AIProvider? {
        guard let profile else { return nil }
        return provider(kind: profile.aiProviderRaw, profile: profile)
    }

    /// One tiny request to confirm the key, model and network work. Returns a message for the user.
    static func test(_ provider: AIProvider) async -> (ok: Bool, message: String) {
        do {
            let r = try await provider.complete(AIRequest(system: "Reply with the single word OK.", messages: [.user("Test")], maxTokens: 20))
            return (true, r.text.isEmpty ? "Connected. The service replied." : "Connected. The service replied: \(r.text.prefix(40))")
        } catch let e as NetError {
            switch e {
            case .unauthorized: return (false, "The service rejected the key. Check that it is correct and has access to this model.")
            case .rateLimited: return (false, "Connected, but you are being rate limited. Try again shortly.")
            case .offline: return (false, "No internet connection.")
            default: return (false, e.localizedDescription + " If this is a 4xx error, the model name may be wrong for your account.")
            }
        } catch { return (false, error.localizedDescription) }
    }
}

enum ImagePrep {
    /// Downscale and compress before upload. Smaller photos are cheaper, faster and reveal less.
    static func jpeg(_ image: UIImage, maxDimension: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let out = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: quality)
    }
}
