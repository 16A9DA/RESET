import Testing
import Foundation
@testable import ResetCore

private final class Capture: HTTPClient, @unchecked Sendable {
    var last: URLRequest?
    let reply: String
    init(_ reply: String) { self.reply = reply }
    func send(_ request: URLRequest) async throws -> Data { last = request; return Data(reply.utf8) }
}

private func bodyJSON(_ c: Capture) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: c.last!.httpBody!) as! [String: Any]
}

@Test func anthropicRequestShape() async throws {
    let http = Capture(#"{"content":[{"type":"text","text":"hi"},{"type":"tool_use","id":"t1","name":"log_water","input":{"ml":250}}],"stop_reason":"tool_use"}"#)
    let p = AnthropicProvider(apiKey: "k", model: "claude-sonnet-5-5", http: http)
    let tool = AITool(name: "log_water", description: "d", schema: .object(["type": .string("object")]))
    let r = try await p.complete(AIRequest(system: "sys", messages: [AIMessage(role: .user, parts: [.image(mime: "image/jpeg", base64: "AAA"), .text("x")])], tools: [tool]))
    #expect(http.last?.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(http.last?.value(forHTTPHeaderField: "x-api-key") == "k")
    #expect(http.last?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let b = try bodyJSON(http)
    #expect(b["system"] as? String == "sys" && b["max_tokens"] as? Int == 1500)
    let content = ((b["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]])
    #expect((content[0]["source"] as? [String: String])?["media_type"] == "image/jpeg")
    #expect(((b["tools"] as! [[String: Any]])[0])["input_schema"] != nil)
    #expect(r.text == "hi" && r.toolCalls.first?.input["ml"]?.int == 250)
}

@Test func missingKeyIsTypedError() async {
    let p = AnthropicProvider(apiKey: "", http: Capture("{}"))
    await #expect(throws: AIError.missingCredentials) { try await p.complete(AIRequest(system: "", messages: [])) }
}

@Test func openAICompatibleShape() async throws {
    let http = Capture(#"{"choices":[{"message":{"content":"ok","tool_calls":[{"id":"c1","type":"function","function":{"name":"f","arguments":"{\"a\":1}"}}]}}]}"#)
    let p = OpenAICompatibleProvider(apiKey: "k", model: "m", baseURL: URL(string: "https://example.test/v1")!, http: http)
    let r = try await p.complete(AIRequest(system: "s", messages: [AIMessage(role: .user, parts: [.image(mime: "image/jpeg", base64: "AAA"), .text("x")])]))
    #expect(http.last?.url?.absoluteString == "https://example.test/v1/chat/completions")
    #expect(http.last?.value(forHTTPHeaderField: "Authorization") == "Bearer k")
    let msgs = try bodyJSON(http)["messages"] as! [[String: Any]]
    #expect(msgs[0]["role"] as? String == "system")
    let img = (msgs[1]["content"] as! [[String: Any]])[0]
    #expect(((img["image_url"] as! [String: String])["url"])! == "data:image/jpeg;base64,AAA")
    #expect(r.text == "ok" && r.toolCalls.first?.input["a"]?.int == 1)
}

@Test func proxyWireFormatRoundTrips() throws {
    let req = AIRequest(system: "s", messages: [AIMessage(role: .user, parts: [.text("a"), .image(mime: "image/png", base64: "B"),
        .toolResult(id: "1", text: "r", isError: false)])])
    let data = try JSONEncoder().encode(req)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains(#""type":"text""#) && json.contains(#""type":"tool_result""#) && json.contains("is_error"))
    #expect(try JSONDecoder().decode(AIRequest.self, from: data) == req)
}

@Test func analyzerEndToEndWithStubs() async throws {
    struct Stub: AIProvider {
        func complete(_ r: AIRequest) async throws -> AIResponse {
            AIResponse(text: "```json\n{\"items\":[{\"name\":\"Hell energy drink\",\"grams\":250,\"confidence\":\"high\",\"estimate\":{\"kcal\":110,\"caffeineMg\":80}}],\"mealType\":\"snack\",\"uncertainties\":[]}\n```")
        }
    }
    let a = try await FoodAnalyzer.analyze(text: "a Hell energy drink", imageJPEG: nil, provider: Stub(), lookup: nil)
    #expect(a.items.count == 1 && !a.items[0].verified && a.items[0].nutrition.caffeineMg == 80)
    #expect(a.mealType == .snack && a.canAutoSave)
}

@Test func uncertaintiesBlockAutoSave() async throws {
    let a = try await FoodAnalyzer.finish(#"{"items":[{"name":"Rice","grams":200,"confidence":"high","estimate":{"kcal":260}}],"uncertainties":["oil amount unknown"]}"#, lookup: nil)
    #expect(!a.canAutoSave)
}
