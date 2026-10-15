import Foundation
import UIKit
import ResetCore

/// Builds the configured AI provider from the Keychain and defaults. Returns nil when nothing is set up,
/// which keeps every non-AI feature working.
enum AIConfig {
    enum Kind: String, CaseIterable, Identifiable {
        case anthropic, openai, proxy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .anthropic: "Anthropic (Claude)"
            case .openai: "OpenAI-compatible (xAI, OpenAI)"
            case .proxy: "RE:SET backend proxy"
            }
        }
    }

    static let openAIBaseKey = "ai.openai.baseURL"
    static let proxyBaseKey = "ai.proxy.baseURL"

    static func provider(kind rawKind: String, model: String) -> AIProvider? {
        let kind = Kind(rawValue: rawKind) ?? .anthropic
        let d = UserDefaults.standard
        switch kind {
        case .anthropic:
            guard let k = Keychain.get(Keychain.anthropicKey), !k.isEmpty else { return nil }
            return AnthropicProvider(apiKey: k, model: model)
        case .openai:
            guard let k = Keychain.get(Keychain.openAIKey), !k.isEmpty,
                  let s = d.string(forKey: openAIBaseKey), let url = URL(string: s), url.scheme == "https" else { return nil }
            return OpenAICompatibleProvider(apiKey: k, model: model, baseURL: url)
        case .proxy:
            guard let t = Keychain.get(Keychain.proxyToken), !t.isEmpty,
                  let s = d.string(forKey: proxyBaseKey), let url = URL(string: s), ["https", "http"].contains(url.scheme) else { return nil }
            return ProxyProvider(baseURL: url, token: t)
        }
    }

    static func provider(for profile: UserProfile?) -> AIProvider? {
        guard let profile else { return nil }
        return provider(kind: profile.aiProviderRaw, model: profile.aiModel)
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
