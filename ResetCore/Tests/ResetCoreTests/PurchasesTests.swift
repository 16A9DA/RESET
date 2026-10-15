import Testing
import Foundation
@testable import ResetCore

private let receipt = """
MEGA MARKET SRL
12/03/2026 14:32
2 x Monster Energy 500ml    7,98
Chicken wrap                 4.50
Total                       12.48
CARD **** 4821
Thank you!
"""

@Test func amountsDatesAndCardNumbersAreStripped() {
    let c = PurchaseParser.parse(receipt)
    let all = c.map(\.text).joined(separator: " | ")
    #expect(!all.contains("7,98") && !all.contains("4.50") && !all.contains("12.48") && !all.contains("4821") && !all.contains("14:32") && !all.contains("12/03"))
    #expect(c.contains { $0.text.lowercased().contains("monster") } && c.contains { $0.text.lowercased().contains("chicken wrap") })
}

@Test func totalsAndPaymentLinesAreDropped() {
    let c = PurchaseParser.parse(receipt).map { $0.text.lowercased() }
    #expect(!c.contains { $0.contains("total") || $0.contains("thank") || $0.contains("card") })
}

@Test func statementLinesBecomeMerchantNames() {
    let c = PurchaseParser.parse("CARD PAYMENT TO MCDONALDS BUCHAREST 15.30 EUR 03/04\nPOS PURCHASE STARBUCKS 4,20")
    #expect(c.count == 2)
    #expect(c[0].text.lowercased().hasPrefix("mcdonalds") && c[0].category == .food)
    #expect(c[1].text.lowercased().hasPrefix("starbucks"))
}

@Test func categories() {
    #expect(PurchaseParser.categorize("Hell energy drink") == .drink)
    #expect(PurchaseParser.categorize("Pizza Hut") == .food)
    #expect(PurchaseParser.categorize("Lidl") == .groceries)
    #expect(PurchaseParser.categorize("Uber trip") == .notFood)
    #expect(PurchaseParser.categorize("Netflix") == .notFood)
    #expect(PurchaseParser.categorize("Random Shop SRL") == .unknown)
    #expect(PurchaseParser.categorize("Starbucks coffee") != .notFood)
}

@Test func nonFoodIsHiddenUnknownIsKept() {
    let c = PurchaseParser.parse("Uber trip 12.00\nNetflix\nCafe Central 3.50\nRandom Shop SRL 9.00")
    let r = PurchaseParser.relevant(c).map(\.text)
    #expect(r == ["Cafe Central", "Random Shop SRL"])
}

@Test func duplicatesWithinPasteAndAgainstKnownAreRemoved() {
    let c = PurchaseParser.parse("Chicken wrap 4.50\nchicken wrap 4.50\nSalad 3.00")
    #expect(c.count == 2)
    #expect(PurchaseParser.removingKnown(c, known: ["Chicken Wrap"]).map(\.text) == ["Salad"])
}

@Test func garbageAndHugeInputAreSafe() {
    #expect(PurchaseParser.parse("").isEmpty)
    #expect(PurchaseParser.parse("12345 6789\n$$$\n--").isEmpty)
    let big = (0..<5000).map { "Item number \($0) chicken" }.joined(separator: "\n")
    #expect(PurchaseParser.parse(big).count <= 60)
    #expect(PurchaseParser.parse(String(repeating: "a", count: 500)).isEmpty)
}

@Test func rulesOnlyPrefillAndFirstMatchWins() {
    let rules = [PurchaseRule(keyword: "uni cafe", prefill: "cafeteria lunch with chicken and rice"), PurchaseRule(keyword: "cafe", prefill: "coffee")]
    #expect(PurchaseRules.prefill(for: "Uni Cafe Main Hall", rules: rules) == "cafeteria lunch with chicken and rice")
    #expect(PurchaseRules.prefill(for: "Cafe Central", rules: rules) == "coffee")
    #expect(PurchaseRules.prefill(for: "Lidl", rules: rules) == "Lidl")
    #expect(PurchaseRules.prefill(for: "x", rules: [PurchaseRule(keyword: "x", prefill: "y")]) == "x") // keyword too short
}

@Test func ruleValidation() {
    #expect(PurchaseRules.isValid(PurchaseRule(keyword: "uni", prefill: "lunch")))
    #expect(!PurchaseRules.isValid(PurchaseRule(keyword: "u", prefill: "lunch")))
    #expect(!PurchaseRules.isValid(PurchaseRule(keyword: "uni", prefill: "  ")))
}

private struct ReceiptProvider: AIProvider {
    var seen: Box = Box()
    final class Box: @unchecked Sendable { var request: AIRequest? }
    func complete(_ r: AIRequest) async throws -> AIResponse {
        seen.request = r
        // The model tries to claim the items were eaten. That must be ignored.
        return AIResponse(text: #"{"items":[{"name":"Monster Energy","brand":"Monster","grams":500,"consumed":true,"confidence":"high","estimate":{"kcal":225,"caffeineMg":160}},{"name":"Chicken wrap","grams":220,"estimate":{"kcal":450}}],"uncertainties":[]}"#)
    }
}

@Test func receiptItemsAreNeverConsumedEvenIfTheModelSaysSo() async throws {
    let p = ReceiptProvider()
    let a = try await ReceiptAnalyzer.analyze(imageJPEG: Data([1, 2, 3]), provider: p, lookup: nil)
    #expect(a.items.count == 2 && a.items.allSatisfy { !$0.consumed } && !a.canAutoSave)
    let total = NutritionTotals.day([(Date.now, a.items)], on: .now)
    #expect(total.total.kcal == 0) // bought is not eaten
    if case .image(let mime, _) = p.seen.request!.messages[0].parts[0] { #expect(mime == "image/jpeg") } else { Issue.record("no image sent") }
    #expect(p.seen.request!.system.contains("Never output money amounts"))
}

@Test func unreadableReceiptIsAnErrorNotAnEmptySuccess() async {
    struct Empty: AIProvider { func complete(_ r: AIRequest) async throws -> AIResponse { AIResponse(text: #"{"items":[],"uncertainties":["unreadable"]}"#) } }
    await #expect(throws: FoodValidationError.noItems) { try await ReceiptAnalyzer.analyze(imageJPEG: Data([1]), provider: Empty(), lookup: nil) }
}
