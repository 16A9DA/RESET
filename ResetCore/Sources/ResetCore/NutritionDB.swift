import Foundation

/// Reference nutrition for 100 g of a food, from a database or label. Not from a language model.
public struct ReferenceFood: Sendable, Equatable {
    public var name: String
    public var brand: String?
    public var per100g: Nutrition
    public var source: String
    /// Typical serving in grams when the database provides one.
    public var servingG: Double?

    public init(name: String, brand: String? = nil, per100g: Nutrition, source: String, servingG: Double? = nil) {
        self.name = name; self.brand = brand; self.per100g = per100g; self.source = source; self.servingG = servingG
    }

    public func nutrition(forGrams g: Double) -> Nutrition { per100g.scaled(g / 100) }
}

public protocol FoodLookup: Sendable {
    func search(_ query: String) async throws -> [ReferenceFood]
}

// MARK: Open Food Facts (barcode)

/// API v2 product-by-barcode. Reads are limited to about 15 per minute per IP, so call only on user action.
/// Data licence: ODbL. Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
public struct OpenFoodFactsClient: Sendable {
    let http: HTTPClient
    let userAgent: String

    public init(http: HTTPClient = URLSessionClient(), userAgent: String = "RESET-AI/1.0 (personal app)") {
        self.http = http; self.userAgent = userAgent
    }

    public func product(barcode: String) async throws -> ReferenceFood? {
        let digits = barcode.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        var c = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(digits)")!
        c.queryItems = [.init(name: "fields", value: "product_name,brands,serving_quantity,nutriments")]
        var req = URLRequest(url: c.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try Self.parse(try await http.send(req))
    }

    static func parse(_ data: Data) throws -> ReferenceFood? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NetError.badResponse }
        guard (root["status"] as? Int) == 1, let p = root["product"] as? [String: Any],
              let n = p["nutriments"] as? [String: Any] else { return nil }
        func num(_ k: String) -> Double? { (n[k] as? Double) ?? (n[k] as? Int).map(Double.init) }
        // No energy value means the entry is too incomplete to trust.
        guard let kcal = num("energy-kcal_100g") ?? num("energy_100g").map({ $0 / 4.184 }) else { return nil }
        let nut = Nutrition(kcal: kcal, proteinG: num("proteins_100g") ?? 0, carbsG: num("carbohydrates_100g") ?? 0,
                            fatG: num("fat_100g") ?? 0, fiberG: num("fiber_100g"), sugarG: num("sugars_100g"),
                            sodiumMg: num("sodium_100g").map { $0 * 1000 }, // grams in OFF
                            caffeineMg: num("caffeine_100g").map { $0 * 1000 })
        let serving = (p["serving_quantity"] as? Double) ?? (p["serving_quantity"] as? String).flatMap(Double.init)
        let brand = (p["brands"] as? String)?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return ReferenceFood(name: (p["product_name"] as? String) ?? "Unnamed product", brand: brand, per100g: nut,
                             source: "Open Food Facts", servingG: serving)
    }
}

// MARK: USDA FoodData Central (text search)

/// foods/search. Public domain data (CC0). DEMO_KEY is limited to 30 requests per hour per IP, so users should add a free key.
/// Docs: https://fdc.nal.usda.gov/api-guide
public struct USDAClient: FoodLookup {
    let http: HTTPClient
    let apiKey: String

    public init(apiKey: String?, http: HTTPClient = URLSessionClient()) {
        self.apiKey = (apiKey?.isEmpty == false) ? apiKey! : "DEMO_KEY"
        self.http = http
    }

    public func search(_ query: String) async throws -> [ReferenceFood] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [
            .init(name: "query", value: q),
            .init(name: "dataType", value: "Foundation,SR Legacy,Branded"),
            .init(name: "pageSize", value: "8"),
            .init(name: "api_key", value: apiKey),
        ]
        return try Self.parse(try await http.send(URLRequest(url: c.url!)))
    }

    // Nutrient ids as returned by foods/search. Foundation foods report energy under 2047 or 2048 instead of 1008.
    private static let energy: Set<Int> = [1008, 2047, 2048]

    static func parse(_ data: Data) throws -> [ReferenceFood] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = root["foods"] as? [[String: Any]] else { throw NetError.badResponse }
        return foods.compactMap { f in
            guard let desc = f["description"] as? String, let list = f["foodNutrients"] as? [[String: Any]] else { return nil }
            var v: [Int: Double] = [:]
            for n in list {
                guard let id = n["nutrientId"] as? Int, let val = (n["value"] as? Double) ?? (n["value"] as? Int).map(Double.init) else { continue }
                if energy.contains(id), v[1008] != nil, id != 1008 { continue }
                v[energy.contains(id) ? 1008 : id] = val
            }
            guard let kcal = v[1008] else { return nil }
            let nut = Nutrition(kcal: kcal, proteinG: v[1003] ?? 0, carbsG: v[1005] ?? 0, fatG: v[1004] ?? 0,
                                fiberG: v[1079], sugarG: v[2000], sodiumMg: v[1093], caffeineMg: v[1057])
            let serving = (f["servingSizeUnit"] as? String)?.lowercased() == "g" ? f["servingSize"] as? Double : nil
            let type = (f["dataType"] as? String) ?? "USDA"
            return ReferenceFood(name: desc.capitalized, brand: (f["brandOwner"] as? String)?.capitalized, per100g: nut,
                                 source: "USDA FoodData Central (\(type))", servingG: serving)
        }
    }
}
