import Testing
import Foundation
@testable import ResetCore

private struct StubLookup: FoodLookup {
    var results: [ReferenceFood]
    var fail = false
    func search(_ query: String) async throws -> [ReferenceFood] {
        if fail { throw NetError.offline }
        return results
    }
}

private let chicken = ReferenceFood(name: "Chicken, breast, raw", per100g: Nutrition(kcal: 110, proteinG: 22.5, carbsG: 0, fatG: 2), source: "USDA")

@Test func usdaParsesFoundationShape() throws {
    let json = """
    {"foods":[{"fdcId":2646170,"description":"Chicken, breast, boneless, skinless, raw","dataType":"Foundation",
    "foodNutrients":[{"nutrientId":1093,"value":65.8},{"nutrientId":1004,"value":1.93},{"nutrientId":1003,"value":22.5},
    {"nutrientId":1005,"value":0.0},{"nutrientId":2047,"value":106},{"nutrientId":2048,"value":112}]},
    {"fdcId":1,"description":"No energy","foodNutrients":[{"nutrientId":1003,"value":5}]}]}
    """
    let r = try USDAClient.parse(Data(json.utf8))
    #expect(r.count == 1)
    #expect(r[0].per100g.kcal == 106 && r[0].per100g.proteinG == 22.5 && r[0].per100g.sodiumMg == 65.8)
}

@Test func offParsesNutellaShapeAndConvertsSodium() throws {
    let json = """
    {"status":1,"product":{"product_name":"Nutella","brands":"Nutella, Ferrero","nutriments":
    {"energy-kcal_100g":539,"proteins_100g":6.3,"carbohydrates_100g":57.5,"fat_100g":30.9,"sodium_100g":0.0428}}}
    """
    let f = try OpenFoodFactsClient.parse(Data(json.utf8))!
    #expect(f.brand == "Nutella" && f.per100g.kcal == 539)
    #expect(abs(f.per100g.sodiumMg! - 42.8) < 1e-9)
    #expect(try OpenFoodFactsClient.parse(Data(#"{"status":0}"#.utf8)) == nil)
}

@Test func validatorStripsFencesAndClamps() throws {
    let text = """
    Here you go:
    ```json
    {"items":[{"name":"Waffle cake","grams":100,"estimate":{"kcal":450,"proteinG":5,"carbsG":50,"fatG":25}},
    {"name":"","grams":50},{"name":"Ghost","grams":-5},{"name":"Huge","grams":99999,"estimate":{"kcal":99999}}]}
    ```
    """
    let m = try FoodValidator.parse(text)
    #expect(m.items.map(\.name) == ["Waffle cake", "Huge"])
    #expect(m.items[1].grams == 3000 && m.items[1].estimate?.kcal == nil)
}

@Test func validatorRejectsGarbage() {
    #expect(throws: FoodValidationError.notJSON) { try FoodValidator.parse("sorry I cannot") }
    #expect(throws: FoodValidationError.noItems) { try FoodValidator.parse(#"{"items":[]}"#) }
}

@Test func impossibleMacrosDropped() throws {
    let m = try FoodValidator.parse(#"{"items":[{"name":"x","grams":10,"estimate":{"kcal":50,"proteinG":8,"carbsG":8,"fatG":8}}]}"#)
    #expect(m.items[0].estimate?.proteinG == nil && m.items[0].estimate?.kcal == 50)
}

@Test func resolverPrefersDatabase() async {
    let p = ParsedItem(name: "Chicken breast", grams: 200, estimate: ParsedEstimate(kcal: 999))
    let i = await FoodResolver.resolve(p, lookup: StubLookup(results: [chicken]))
    #expect(i.verified && i.nutrition.kcal == 220 && i.nutrition.proteinG == 45)
}

@Test func resolverFallsBackToLabelledEstimateOffline() async {
    let p = ParsedItem(name: "Chicken breast", grams: 100, estimate: ParsedEstimate(kcal: 120, proteinG: 25))
    let i = await FoodResolver.resolve(p, lookup: StubLookup(results: [], fail: true))
    #expect(!i.verified && i.nutrition.kcal == 120 && i.dataSource.contains("AI estimate"))
}

@Test func resolverWithNothingKeepsEntryAtZeroLowConfidence() async {
    let i = await FoodResolver.resolve(ParsedItem(name: "Mystery", grams: 50), lookup: nil)
    #expect(i.nutrition == .zero && i.confidence == .low)
}

@Test func unrelatedDatabaseHitIsRejected() async {
    let p = ParsedItem(name: "Chocolate waffle", grams: 100, estimate: ParsedEstimate(kcal: 450))
    let i = await FoodResolver.resolve(p, lookup: StubLookup(results: [chicken]))
    #expect(!i.verified && i.nutrition.kcal == 450)
}

@Test func notConsumedIsNotCounted() {
    let a = FoodItem(name: "a", grams: 100, nutrition: Nutrition(kcal: 100), dataSource: "x", verified: true, confidence: .high)
    var b = FoodItem(name: "b", grams: 100, nutrition: Nutrition(kcal: 500), dataSource: "x", verified: false, confidence: .low)
    b.consumed = false
    let now = Date.now
    let d = NutritionTotals.day([(now, [a, b])], on: now)
    #expect(d.total.kcal == 100 && d.mealCount == 1 && d.estimatedItemCount == 0)
}

@Test func duplicateGuard() {
    let t = Date.now
    let ex = [(text: "Chicken sandwich, and a cappuccino!", at: t)]
    #expect(Duplicates.isLikelyDuplicate(text: "chicken sandwich and a cappuccino", at: t.addingTimeInterval(300), existing: ex))
    #expect(!Duplicates.isLikelyDuplicate(text: "chicken sandwich and a cappuccino", at: t.addingTimeInterval(3600), existing: ex))
}
