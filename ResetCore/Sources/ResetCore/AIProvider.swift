import Foundation

/// Arbitrary JSON, for tool schemas and tool inputs.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(key: String) -> JSONValue? { if case .object(let o) = self { return o[key] } else { return nil } }
    public var string: String? { if case .string(let s) = self { return s } else { return nil } }
    public var double: Double? { if case .number(let n) = self { return n } else { return nil } }
    public var int: Int? { double.map { Int($0) } }
    public var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
}

public struct AITool: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    /// JSON Schema object.
    public var schema: JSONValue
    public init(name: String, description: String, schema: JSONValue) {
        self.name = name; self.description = description; self.schema = schema
    }
}

public struct AIToolCall: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var input: JSONValue
    public init(id: String, name: String, input: JSONValue) { self.id = id; self.name = name; self.input = input }
}

public enum AIPart: Codable, Equatable, Sendable {
    case text(String)
    case image(mime: String, base64: String)
    case toolUse(AIToolCall)
    case toolResult(id: String, text: String, isError: Bool)

    // Tagged wire format shared with the backend proxy: {"type": "text", "text": "..."} and so on.
    private enum K: String, CodingKey { case type, text, mime, base64, id, name, input, isError = "is_error" }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "text": self = .text(try c.decode(String.self, forKey: .text))
        case "image": self = .image(mime: try c.decode(String.self, forKey: .mime), base64: try c.decode(String.self, forKey: .base64))
        case "tool_use":
            self = .toolUse(AIToolCall(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                                       input: try c.decode(JSONValue.self, forKey: .input)))
        case "tool_result":
            self = .toolResult(id: try c.decode(String.self, forKey: .id), text: try c.decode(String.self, forKey: .text),
                               isError: try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false)
        case let t: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown part type \(t)")
        }
    }

    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        switch self {
        case .text(let t): try c.encode("text", forKey: .type); try c.encode(t, forKey: .text)
        case .image(let m, let b): try c.encode("image", forKey: .type); try c.encode(m, forKey: .mime); try c.encode(b, forKey: .base64)
        case .toolUse(let call):
            try c.encode("tool_use", forKey: .type); try c.encode(call.id, forKey: .id)
            try c.encode(call.name, forKey: .name); try c.encode(call.input, forKey: .input)
        case .toolResult(let id, let t, let err):
            try c.encode("tool_result", forKey: .type); try c.encode(id, forKey: .id)
            try c.encode(t, forKey: .text); try c.encode(err, forKey: .isError)
        }
    }
}

public struct AIMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var role: Role
    public var parts: [AIPart]
    public init(role: Role, parts: [AIPart]) { self.role = role; self.parts = parts }
    public static func user(_ text: String) -> AIMessage { .init(role: .user, parts: [.text(text)]) }
}

public struct AIRequest: Codable, Equatable, Sendable {
    public var system: String
    public var messages: [AIMessage]
    public var tools: [AITool]
    public var maxTokens: Int
    public init(system: String, messages: [AIMessage], tools: [AITool] = [], maxTokens: Int = 1500) {
        self.system = system; self.messages = messages; self.tools = tools; self.maxTokens = maxTokens
    }
}

public struct AIResponse: Codable, Equatable, Sendable {
    public var text: String
    public var toolCalls: [AIToolCall]
    public init(text: String, toolCalls: [AIToolCall] = []) { self.text = text; self.toolCalls = toolCalls }
}

public enum AIError: Error, Equatable, LocalizedError {
    case missingCredentials
    case invalidReply(String)
    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "No AI service is set up. Add an API key in Settings, or keep logging manually."
        case .invalidReply(let m): "The AI service sent a reply the app could not read. \(m)"
        }
    }
}

public protocol AIProvider: Sendable {
    func complete(_ request: AIRequest) async throws -> AIResponse
}

// MARK: Anthropic Messages API

/// POST https://api.anthropic.com/v1/messages, headers x-api-key and anthropic-version.
/// Images are base64 blocks, tools use input_schema, results come back as tool_use blocks.
public struct AnthropicProvider: AIProvider {
    let http: HTTPClient
    let apiKey: String
    let model: String
    let baseURL: URL

    public init(apiKey: String, model: String = "claude-haiku-5-5", baseURL: URL = URL(string: "https://api.anthropic.com")!,
                http: HTTPClient = URLSessionClient()) {
        self.apiKey = apiKey; self.model = model; self.baseURL = baseURL; self.http = http
    }

    public func complete(_ r: AIRequest) async throws -> AIResponse {
        guard !apiKey.isEmpty else { throw AIError.missingCredentials }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: Self.body(r, model: model))
        return try Self.parse(try await http.send(req))
    }

    static func body(_ r: AIRequest, model: String) throws -> [String: Any] {
        func enc(_ v: JSONValue) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(v), options: .fragmentsAllowed) }
        var messages: [[String: Any]] = []
        for m in r.messages {
            var content: [[String: Any]] = []
            for p in m.parts {
                switch p {
                case .text(let t): content.append(["type": "text", "text": t])
                case .image(let mime, let b64):
                    content.append(["type": "image", "source": ["type": "base64", "media_type": mime, "data": b64]])
                case .toolUse(let c):
                    content.append(["type": "tool_use", "id": c.id, "name": c.name, "input": try enc(c.input)])
                case .toolResult(let id, let text, let isError):
                    content.append(["type": "tool_result", "tool_use_id": id, "content": text, "is_error": isError])
                }
            }
            messages.append(["role": m.role.rawValue, "content": content])
        }
        var body: [String: Any] = ["model": model, "max_tokens": r.maxTokens, "system": r.system, "messages": messages]
        if !r.tools.isEmpty {
            body["tools"] = try r.tools.map { ["name": $0.name, "description": $0.description, "input_schema": try enc($0.schema)] as [String: Any] }
        }
        return body
    }

    static func parse(_ data: Data) throws -> AIResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["content"] as? [[String: Any]] else { throw AIError.invalidReply("Missing content.") }
        var text = "", calls: [AIToolCall] = []
        for b in blocks {
            switch b["type"] as? String {
            case "text": text += (b["text"] as? String) ?? ""
            case "tool_use":
                guard let id = b["id"] as? String, let name = b["name"] as? String else { continue }
                let input = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: b["input"] ?? [:]))
                calls.append(AIToolCall(id: id, name: name, input: input))
            default: break
            }
        }
        if root["stop_reason"] as? String == "refusal" { throw AIError.invalidReply("The model declined this request.") }
        return AIResponse(text: text, toolCalls: calls)
    }
}

// MARK: OpenAI Chat Completions (OpenAI itself and compatible services)

/// POST {base}/chat/completions with a bearer token. Images go in as image_url data URLs and tools as functions.
/// OpenAI deprecated `max_tokens`; its newer and reasoning models require `max_completion_tokens`, which also counts
/// hidden reasoning tokens. Compatible services such as xAI often still expect `max_tokens`, so the name is configurable.
/// Request and response shapes are covered by unit tests with a stub client. They have NOT been run against a live
/// OpenAI or xAI account, so verify with your own key. Reasoning models may also reject function tools unless
/// reasoning effort is lowered (reported in Azure's docs, unverified against OpenAI's). Pick a non reasoning vision model if tool calls fail.
public struct OpenAICompatibleProvider: AIProvider {
    let http: HTTPClient
    let apiKey: String
    let model: String
    let baseURL: URL
    let tokenParameter: String
    let minTokens: Int

    public static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!

    /// `tokenParameter` is "max_completion_tokens" for OpenAI, "max_tokens" for most compatible services.
    /// `minTokens` leaves room for hidden reasoning tokens so structured replies are not cut off.
    public init(apiKey: String, model: String, baseURL: URL, tokenParameter: String = "max_tokens", minTokens: Int = 0,
                http: HTTPClient = URLSessionClient()) {
        self.apiKey = apiKey; self.model = model; self.baseURL = baseURL; self.tokenParameter = tokenParameter
        self.minTokens = minTokens; self.http = http
    }

    public static func openAI(apiKey: String, model: String, http: HTTPClient = URLSessionClient()) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(apiKey: apiKey, model: model, baseURL: openAIBaseURL, tokenParameter: "max_completion_tokens",
                                 minTokens: 4000, http: http)
    }

    public func complete(_ r: AIRequest) async throws -> AIResponse {
        guard !apiKey.isEmpty, !model.isEmpty else { throw AIError.missingCredentials }
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: try Self.body(r, model: model, tokenParameter: tokenParameter, minTokens: minTokens))
        return try Self.parse(try await http.send(req))
    }

    static func body(_ r: AIRequest, model: String, tokenParameter: String = "max_tokens", minTokens: Int = 0) throws -> [String: Any] {
        func enc(_ v: JSONValue) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(v), options: .fragmentsAllowed) }
        var messages: [[String: Any]] = [["role": "system", "content": r.system]]
        for m in r.messages {
            var content: [[String: Any]] = []
            var calls: [[String: Any]] = []
            for p in m.parts {
                switch p {
                case .text(let t): content.append(["type": "text", "text": t])
                case .image(let mime, let b64):
                    content.append(["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(b64)"]])
                case .toolUse(let c):
                    let args = String(data: try JSONEncoder().encode(c.input), encoding: .utf8) ?? "{}"
                    calls.append(["id": c.id, "type": "function", "function": ["name": c.name, "arguments": args]])
                case .toolResult(let id, let text, _):
                    messages.append(["role": "tool", "tool_call_id": id, "content": text])
                }
            }
            if !content.isEmpty || !calls.isEmpty {
                var msg: [String: Any] = ["role": m.role.rawValue]
                msg["content"] = content.isEmpty ? NSNull() : content
                if !calls.isEmpty { msg["tool_calls"] = calls }
                messages.append(msg)
            }
        }
        var body: [String: Any] = ["model": model, "messages": messages, tokenParameter: max(r.maxTokens, minTokens)]
        if !r.tools.isEmpty {
            body["tools"] = try r.tools.map {
                ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": try enc($0.schema)]] as [String: Any]
            }
        }
        return body
    }

    static func parse(_ data: Data) throws -> AIResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = (root["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        else { throw AIError.invalidReply("Missing choices.") }
        var calls: [AIToolCall] = []
        for c in (msg["tool_calls"] as? [[String: Any]]) ?? [] {
            guard let id = c["id"] as? String, let f = c["function"] as? [String: Any], let name = f["name"] as? String else { continue }
            let argText = (f["arguments"] as? String) ?? "{}"
            let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(argText.utf8))) ?? .object([:])
            calls.append(AIToolCall(id: id, name: name, input: input))
        }
        return AIResponse(text: (msg["content"] as? String) ?? "", toolCalls: calls)
    }
}

// MARK: RE:SET backend proxy

/// Sends the neutral request to the project's own FastAPI proxy, which holds the provider key server side.
public struct ProxyProvider: AIProvider {
    let http: HTTPClient
    let baseURL: URL
    let token: String

    public init(baseURL: URL, token: String, http: HTTPClient = URLSessionClient()) {
        self.baseURL = baseURL; self.token = token; self.http = http
    }

    public func complete(_ r: AIRequest) async throws -> AIResponse {
        guard !token.isEmpty else { throw AIError.missingCredentials }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/ai/complete"))
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(r)
        let data = try await http.send(req)
        do { return try JSONDecoder().decode(AIResponse.self, from: data) }
        catch { throw AIError.invalidReply("Proxy reply did not match the expected shape.") }
    }
}
