import SwiftUI
import SwiftData
import PhotosUI
import ResetCore

enum FoodMethod: String, CaseIterable, Identifiable {
    case describe = "Describe", photo = "Photo", barcode = "Barcode"
    var id: String { rawValue }
}

struct AddFoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MealRecord.at, order: .reverse) private var meals: [MealRecord]
    @Query private var profiles: [UserProfile]

    var initialItems: [FoodItem] = []
    var initialText = ""
    var startWith: FoodMethod = .describe

    @State private var method: FoodMethod = .describe
    @State private var items: [FoodItem] = []
    @State private var mealType: MealType = Self.guessMealType()
    @State private var at = Date.now
    @State private var text = ""
    @State private var results: [ReferenceFood] = []
    @State private var busy = false
    @State private var error: String?
    @State private var picked: ReferenceFood?
    @State private var grams = 100.0
    @State private var confirmDuplicate = false
    @State private var uncertainties: [String] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var photo: UIImage?
    @State private var aiSource = false

    static func guessMealType() -> MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }

    private var lookup: USDAClient { USDAClient(apiKey: Keychain.get(Keychain.usdaKey)) }
    /// Generic foods from USDA plus packaged products from Open Food Facts. One being down does not hide the other.
    private var combined: CombinedLookup { CombinedLookup([lookup, OpenFoodFactsSearch()]) }
    private var draftTotal: Nutrition { items.filter(\.consumed).reduce(.zero) { $0 + $1.nutrition } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Method", selection: $method) {
                    ForEach(FoodMethod.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding()

                Group {
                    switch method {
                    case .describe: describePane
                    case .photo: photoPane
                    case .barcode: barcodePane
                    }
                }
                .frame(maxHeight: .infinity)

                draftBar
            }
            .background(Theme.background)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: Binding(get: { picked.map(Picked.init) }, set: { picked = $0?.food })) { p in portionSheet(p.food) }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { photo = $0 }.ignoresSafeArea() }
            .onChange(of: pickerItem) { _, item in
                Task { if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { photo = img } }
            }
            // A photo is the whole input, so analyze it right away.
            .onChange(of: photo) { _, new in if new != nil { runAnalysis() } }
            .alert("Looks like a repeat", isPresented: $confirmDuplicate) {
                Button("Save anyway") { save() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You logged the same thing in the last 10 minutes. Save it again?") }
            .onAppear { items = initialItems; text = initialText; method = startWith }
        }
    }

    private struct Picked: Identifiable { let food: ReferenceFood; var id: String { food.name + (food.brand ?? "") } }

    // MARK: AI panes

    private var provider: AIProvider? { AIConfig.provider(for: profiles.first) }

    private var setupPrompt: some View {
        Group {
            if let p = profiles.first {
                NavigationLink("Turn on instant logging with AI") { AISettingsView(profile: p) }.font(.subheadline)
            }
        }
    }

    private var describePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("What did you have?", text: $text, axis: .vertical)
                    .lineLimit(2...5).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.done)
                Button { provider == nil ? runSearch() : runAnalysis() } label: {
                    HStack { if busy { ProgressView() }; Text("Add") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                if provider == nil { setupPrompt }
                if let error { Text(error).foregroundStyle(Theme.low).font(.footnote) }
                aiNotes
                ForEach(results, id: \.name) { r in
                    Button { picked = r; grams = r.servingG ?? 100 } label: {
                        VStack(alignment: .leading) {
                            Text(r.name).font(.headline).lineLimit(2)
                            Text("\(r.brand.map { $0 + ", " } ?? "")\(Int(r.per100g.kcal)) kcal per 100 g")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal)
        }
    }

    private var photoPane: some View {
        VStack(spacing: 12) {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if busy { ProgressView() }
            HStack {
                if CameraPicker.available { Button("Take photo") { showCamera = true }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black) }
                PhotosPicker("Choose photo", selection: $pickerItem, matching: .images).buttonStyle(.bordered)
            }
            if provider == nil { setupPrompt }
            if let error { Text(error).foregroundStyle(Theme.low).font(.footnote) }
            aiNotes
            Spacer()
        }.padding(.horizontal)
    }

    @ViewBuilder private var aiNotes: some View {
        if !uncertainties.isEmpty {
            Card(title: "Not sure about") {
                ForEach(uncertainties, id: \.self) { Text($0).font(.footnote) }
            }
        }
    }

    private func runAnalysis() {
        guard let provider else { return }
        busy = true; error = nil; uncertainties = []
        let jpeg = method == .photo ? photo.flatMap { ImagePrep.jpeg($0) } : nil
        let input = method == .photo ? "" : text
        Task {
            defer { busy = false }
            do {
                let a = try await FoodAnalyzer.analyze(text: input, imageJPEG: jpeg, provider: provider, lookup: lookup, brandLookup: OpenFoodFactsSearch())
                aiSource = true
                uncertainties = a.uncertainties
                if let t = a.mealType { mealType = t }
                if profiles.first?.autoSaveFood == true, a.canAutoSave {
                    items = a.items; save(); return
                }
                items += a.items
                text = ""
            } catch {
                self.error = "\(error.localizedDescription) Nothing was saved."
            }
        }
    }

    private var barcodePane: some View {
        VStack {
            if BarcodeScanner.supported {
                BarcodeScanner { code in Task { await scan(code) } }
                    .clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
            }
            HStack {
                TextField("Barcode number", text: $text).keyboardType(.numberPad)
                Button("Look up") { Task { await scan(text) } }.disabled(text.count < 8 || busy)
            }.padding()
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(Theme.low).font(.footnote).padding(.horizontal) }
        }
    }

    // MARK: Draft + save

    private var draftBar: some View {
        VStack(spacing: 8) {
            if !items.isEmpty {
                ForEach(items) { i in
                    HStack {
                        Text("\(i.name), \(Int(i.grams)) g").lineLimit(1)
                        Spacer()
                        Text("\(Int(i.nutrition.kcal)) kcal").monospacedDigit()
                        Button { items.removeAll { $0.id == i.id } } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Remove \(i.name)")
                    }.font(.footnote)
                }
                Button("Save \(Int(draftTotal.kcal)) kcal") {
                    if isDuplicate { confirmDuplicate = true } else { save() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            }
        }
        .padding().background(items.isEmpty ? Color.clear : Theme.card)
    }

    private var originalText: String { items.map(\.name).joined(separator: ", ") }

    private var isDuplicate: Bool {
        Duplicates.isLikelyDuplicate(text: originalText, at: at,
                                     existing: meals.prefix(20).map { ($0.originalText, $0.at) })
    }

    private func save() {
        let conf = items.map(\.confidence).min() ?? .medium
        let src: Source = aiSource ? .aiEstimate : (items.allSatisfy(\.verified) ? .confirmed : .manual)
        context.insert(MealRecord(at: at, mealType: mealType, originalText: originalText, items: items, source: src, confidence: conf))
        // Caffeine in anything logged, food or drink, lands in the caffeine log with where the number came from.
        for i in items where i.consumed {
            if let mg = i.nutrition.caffeineMg, mg > 0 {
                context.insert(CaffeineRecord(at: at, name: i.name, servingMl: i.grams, mg: mg, mgSource: i.dataSource,
                                              source: i.verified ? .confirmed : .aiEstimate))
            } else if let d = Caffeine.catalogMatch(i.name) {
                context.insert(CaffeineRecord(at: at, name: d.name, servingMl: d.servingMl, mg: d.mg,
                                              mgSource: "Typical value for \(d.name). Check your can.", source: .aiEstimate))
            }
        }
        try? context.save()
        dismiss()
    }

    // MARK: Actions

    private func runSearch() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                results = try await combined.search(text)
                if results.isEmpty { error = "No matches. Try simpler words." }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func scan(_ code: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            if let f = try await OpenFoodFactsClient().product(barcode: code) {
                let g = f.servingG ?? 100
                items.append(FoodItem(name: f.name, brand: f.brand, grams: g, nutrition: f.nutrition(forGrams: g),
                                      dataSource: f.source, verified: true, confidence: .high))
                text = ""
            } else {
                error = "Product not found. Try describing it instead."
            }
        } catch { self.error = "\(error.localizedDescription) Try again, or describe it instead." }
    }

    private func portionSheet(_ f: ReferenceFood) -> some View {
        NavigationStack {
            Form {
                Text(f.name).font(.headline)
                HStack {
                    Text("Amount (g)"); Spacer()
                    TextField("g", value: $grams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
                let n = f.nutrition(forGrams: grams)
                Text("\(Int(n.kcal)) kcal, \(Int(n.proteinG)) g protein, \(Int(n.carbsG)) g carbs, \(Int(n.fatG)) g fat")
            }
            .navigationTitle("Portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picked = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        items.append(FoodItem(name: f.name, brand: f.brand, grams: grams, nutrition: f.nutrition(forGrams: grams),
                                              dataSource: f.source, verified: true, confidence: .high))
                        picked = nil
                    }.disabled(grams <= 0)
                }
            }
        }.presentationDetents([.medium])
    }
}
