import SwiftUI
import SwiftData
import PhotosUI
import ResetCore

enum FoodMethod: String, CaseIterable, Identifiable {
    case describe = "Describe", photo = "Photo", search = "Search", barcode = "Barcode", manual = "Manual", saved = "Saved", recent = "Recent"
    var id: String { rawValue }
}

struct AddFoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedMeal.useCount, order: .reverse) private var saved: [SavedMeal]
    @Query(sort: \MealRecord.at, order: .reverse) private var meals: [MealRecord]
    @Query private var profiles: [UserProfile]

    var initialItems: [FoodItem] = []
    var initialText = ""

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
    @State private var manual = FoodItem(name: "", grams: 100, nutrition: .zero, dataSource: "Entered by you", verified: false, confidence: .high)
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
                    case .search: searchPane
                    case .barcode: barcodePane
                    case .manual: manualPane
                    case .saved: savedPane
                    case .recent: recentPane
                    }
                }
                .frame(maxHeight: .infinity)

                draftBar
            }
            .background(Theme.background)
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: Binding(get: { picked.map(Picked.init) }, set: { picked = $0?.food })) { p in portionSheet(p.food) }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { photo = $0 }.ignoresSafeArea() }
            .onChange(of: pickerItem) { _, item in
                Task { if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { photo = img } }
            }
            .alert("Looks like a repeat", isPresented: $confirmDuplicate) {
                Button("Save anyway") { save() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You logged the same thing in the last 10 minutes. Save it again?") }
            .onAppear { items = initialItems; text = initialText }
        }
    }

    private struct Picked: Identifiable { let food: ReferenceFood; var id: String { food.name + (food.brand ?? "") } }

    // MARK: AI panes

    private var provider: AIProvider? { AIConfig.provider(for: profiles.first) }

    private var setupPrompt: some View {
        VStack(spacing: 8) {
            EmptyNote(systemImage: "sparkles", title: "AI is not set up",
                      message: "Describing or photographing food needs an AI service key. Search, barcode, manual entry and saved meals work without one.")
            if let p = profiles.first {
                NavigationLink("Set up AI") { AISettingsView(profile: p) }
            }
        }
    }

    private var describePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if provider == nil { setupPrompt }
                TextField("e.g. chicken, rice, salad and some dressing at the cafeteria", text: $text, axis: .vertical)
                    .lineLimit(3...6).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                Button { runAnalysis() } label: {
                    HStack { if busy { ProgressView() }; Text(busy ? "Working out nutrition" : "Estimate nutrition") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                .disabled(busy || provider == nil || text.trimmingCharacters(in: .whitespaces).isEmpty)
                if let error { Text(error).foregroundStyle(Theme.low).font(.footnote) }
                aiNotes
                Text("Tip: tap the microphone on the keyboard to dictate. Amounts like \"100 g\" are used exactly. Everything else is a portion estimate.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }.padding(.horizontal)
        }
    }

    private var photoPane: some View {
        ScrollView {
            VStack(spacing: 12) {
                if provider == nil { setupPrompt }
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    if CameraPicker.available { Button("Take photo") { showCamera = true } }
                    PhotosPicker("Choose photo", selection: $pickerItem, matching: .images)
                }
                TextField("Anything to add? e.g. small portion, no dressing", text: $text)
                    .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                Button { runAnalysis() } label: {
                    HStack { if busy { ProgressView() }; Text(busy ? "Analyzing" : "Estimate from photo") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                .disabled(busy || provider == nil || photo == nil)
                if let error { Text(error).foregroundStyle(Theme.low).font(.footnote) }
                aiNotes
                Text("A photo cannot show exact calories. Oil, sauces and portion size are guesses, so check the result before saving.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }.padding(.horizontal)
        }
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
        let input = text
        Task {
            defer { busy = false }
            do {
                let a = try await FoodAnalyzer.analyze(text: input, imageJPEG: jpeg, provider: provider, lookup: lookup)
                aiSource = true
                uncertainties = a.uncertainties
                if let t = a.mealType { mealType = t }
                if profiles.first?.autoSaveFood == true, a.canAutoSave {
                    items = a.items; save(); return
                }
                items += a.items
            } catch {
                self.error = "\(error.localizedDescription) Nothing was saved. You can add the food by search or manually."
            }
        }
    }

    // MARK: Panes

    private var searchPane: some View {
        List {
            Section {
                HStack {
                    TextField("e.g. chicken breast cooked", text: $text).submitLabel(.search).onSubmit(runSearch)
                    Button("Search", action: runSearch).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                if Keychain.get(Keychain.usdaKey) == nil {
                    Text("Using the shared demo key, which is limited to 30 searches an hour. Add a free USDA key in Settings for more.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(Theme.low).font(.footnote) }
            ForEach(results, id: \.name) { r in
                Button { picked = r; grams = r.servingG ?? 100 } label: {
                    VStack(alignment: .leading) {
                        Text(r.name).font(.headline).lineLimit(2)
                        Text("\(r.brand.map { $0 + ", " } ?? "")\(Int(r.per100g.kcal)) kcal and \(Int(r.per100g.proteinG)) g protein per 100 g. \(r.source)")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }.buttonStyle(.plain)
            }
        }.scrollContentBackground(.hidden)
    }

    private var barcodePane: some View {
        VStack {
            if BarcodeScanner.supported {
                BarcodeScanner { code in Task { await scan(code) } }
                    .clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
            } else {
                EmptyNote(systemImage: "barcode.viewfinder", title: "Scanner unavailable",
                          message: "Camera scanning needs a real iPhone with camera permission. Type the number below instead.")
            }
            HStack {
                TextField("Barcode number", text: $text).keyboardType(.numberPad)
                Button("Look up") { Task { await scan(text) } }.disabled(text.count < 8 || busy)
            }.padding()
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(Theme.low).font(.footnote).padding(.horizontal) }
            Text("Product data from Open Food Facts (ODbL). Check it against the label.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var manualPane: some View {
        Form {
            TextField("Food name", text: $manual.name)
            numberRow("Amount (g)", $manual.grams)
            numberRow("Calories", $manual.nutrition.kcal)
            numberRow("Protein (g)", $manual.nutrition.proteinG)
            numberRow("Carbs (g)", $manual.nutrition.carbsG)
            numberRow("Fat (g)", $manual.nutrition.fatG)
            Button("Add to meal") {
                var m = manual; m.name = m.name.trimmingCharacters(in: .whitespaces)
                items.append(m)
                manual = FoodItem(name: "", grams: 100, nutrition: .zero, dataSource: "Entered by you", verified: false, confidence: .high)
            }.disabled(manual.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }.scrollContentBackground(.hidden)
    }

    private func numberRow(_ title: String, _ v: Binding<Double>) -> some View {
        HStack {
            Text(title); Spacer()
            TextField("0", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }

    private var savedPane: some View {
        List {
            if saved.isEmpty {
                EmptyNote(systemImage: "bookmark", title: "No saved meals",
                          message: "Open any logged meal and choose Save as meal to reuse it in one tap.")
            }
            ForEach(saved) { s in
                Button {
                    items += s.items.map { var c = $0; c.id = UUID(); return c }
                    s.useCount += 1; s.lastUsed = .now
                } label: {
                    HStack {
                        Text(s.name)
                        Spacer()
                        Text("\(Int(s.items.reduce(0) { $0 + $1.nutrition.kcal })) kcal").foregroundStyle(Theme.secondaryText)
                    }
                }.buttonStyle(.plain)
            }
            .onDelete { $0.map { saved[$0] }.forEach(context.delete) }
        }.scrollContentBackground(.hidden)
    }

    private var recentPane: some View {
        List {
            let recent = Dictionary(grouping: meals.flatMap(\.items), by: { $0.name.lowercased() })
                .values.compactMap(\.first).prefix(25)
            if recent.isEmpty {
                EmptyNote(systemImage: "clock", title: "No recent foods", message: "Foods you log will show up here.")
            }
            ForEach(Array(recent)) { i in
                Button { var c = i; c.id = UUID(); items.append(c) } label: {
                    HStack { Text(i.name); Spacer(); Text("\(Int(i.grams)) g").foregroundStyle(Theme.secondaryText) }
                }.buttonStyle(.plain)
            }
        }.scrollContentBackground(.hidden)
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
                HStack {
                    Picker("", selection: $mealType) { ForEach(MealType.allCases, id: \.self) { Text($0.title).tag($0) } }
                    DatePicker("", selection: $at).labelsHidden()
                }
                Button("Save \(Int(draftTotal.kcal)) kcal, \(Int(draftTotal.proteinG)) g protein") {
                    if isDuplicate { confirmDuplicate = true } else { save() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            }
        }
        .padding().background(Theme.card)
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
        try? context.save()
        dismiss()
    }

    // MARK: Actions

    private func runSearch() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                results = try await lookup.search(text)
                if results.isEmpty { error = "No matches. Try simpler words, or add it manually." }
            } catch { self.error = "\(error.localizedDescription) You can still add the food manually." }
        }
    }

    private func scan(_ code: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            if let f = try await OpenFoodFactsClient().product(barcode: code) {
                picked = f; grams = f.servingG ?? 100
            } else {
                error = "Product not found or has no nutrition data. Add it manually from the label."
            }
        } catch { self.error = "\(error.localizedDescription) Try again, or add it manually." }
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
                Text("Values per 100 g from \(f.source).").font(.caption).foregroundStyle(Theme.secondaryText)
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
