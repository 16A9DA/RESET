import SwiftUI
import SwiftData
import PhotosUI
import ResetCore

/// Ask before eating. Nothing is logged unless you tap "I ate it".
struct CanIEatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthService.self) private var health
    @Query private var profiles: [UserProfile]

    @State private var text = ""
    @State private var items: [FoodItem] = []
    @State private var verdict: EatVerdict?
    @State private var busy = false
    @State private var error: String?
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var logged = false

    private var profile: UserProfile? { profiles.first }
    private var provider: AIProvider? { AIConfig.provider(for: profile) }
    private var lookup: USDAClient { USDAClient(apiKey: Keychain.get(Keychain.usdaKey)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TextField("What is it?", text: $text, axis: .vertical)
                        .lineLimit(1...4).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .submitLabel(.go).onSubmit { ask(text: text, image: nil) }
                    HStack(spacing: 10) {
                        if CameraPicker.available { pill("camera.fill", "Photo") { showCamera = true } }
                        PhotosPicker(selection: $pickerItem, matching: .images) { pillLabel("photo", "Library") }
                        pill("barcode.viewfinder", "Barcode") { showScanner = true }
                        Spacer()
                        Button("Ask") { ask(text: text, image: nil) }
                            .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                            .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if busy { ProgressView() }
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.low) }
                    if provider == nil, let p = profile {
                        NavigationLink("Turn on AI for text and photos") { AISettingsView(profile: p) }.font(.subheadline)
                    }
                    if let v = verdict { result(v) }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Can I eat this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { ask(text: text, image: $0) }.ignoresSafeArea() }
            .sheet(isPresented: $showScanner) {
                BarcodeScanner { code in showScanner = false; Task { await scan(code) } }.ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                Task { if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { ask(text: text, image: img) } }
            }
        }
    }

    private func pill(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(icon, label) }.buttonStyle(Press())
    }

    private func pillLabel(_ icon: String, _ label: String) -> some View {
        Label(label, systemImage: icon).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.primary.opacity(0.1), in: Capsule())
    }

    private func result(_ v: EatVerdict) -> some View {
        let color = v.level == .yes ? Theme.good : (v.level == .maybe ? Theme.warn : Theme.low)
        let title = v.level == .yes ? "Yes" : (v.level == .maybe ? "Maybe not now" : "No")
        return Card {
            HStack {
                Image(systemName: v.level == .yes ? "checkmark.circle.fill" : (v.level == .maybe ? "exclamationmark.circle.fill" : "xmark.circle.fill"))
                    .foregroundStyle(color).font(.title)
                Text(title).font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
                Text("\(Int(v.kcal.rounded())) kcal").foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            ForEach(v.reasons, id: \.self) { Text($0).font(.subheadline) }
            Text("Estimate. \(EatCheck.allergyCaveat)").font(.caption).foregroundStyle(Theme.secondaryText)
            Button(logged ? "Logged" : "I ate it") { log() }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black).disabled(logged)
        }
        .sensoryFeedback(.impact, trigger: v)
    }

    private func ask(text: String, image: UIImage?) {
        guard let provider else { error = "Text and photos need AI. A barcode works without it."; return }
        busy = true; error = nil; verdict = nil; logged = false
        let jpeg = image.flatMap { ImagePrep.jpeg($0) }
        Task {
            defer { busy = false }
            do {
                let a = try await FoodAnalyzer.analyze(text: text, imageJPEG: jpeg, provider: provider, lookup: lookup, brandLookup: OpenFoodFactsSearch())
                guard !a.items.isEmpty else { error = "I could not tell what that is. Try describing it."; return }
                items = a.items
                verdict = check()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func scan(_ code: String) async {
        busy = true; error = nil; verdict = nil; logged = false
        defer { busy = false }
        do {
            guard let f = try await OpenFoodFactsClient().product(barcode: code) else { error = "Product not found. Try describing it."; return }
            let g = f.servingG ?? 100
            items = [FoodItem(name: f.name, brand: f.brand, grams: g, nutrition: f.nutrition(forGrams: g), dataSource: f.source, verified: true, confidence: .high)]
            verdict = check()
        } catch { self.error = error.localizedDescription }
    }

    private func check() -> EatVerdict {
        let s = DaySummaryBuilder.build(context: context, profile: profile, health: health)
        var hours: Double?
        if let p = profile {
            var bed = Day.date(.now, minutes: p.bedMinute)
            if p.bedMinute < 6 * 60 { bed = bed.addingTimeInterval(86_400) }
            let h = bed.timeIntervalSinceNow / 3600
            hours = h > 0 ? h : nil
        }
        return EatCheck.verdict(items: items, remainingKcal: s.calorieCounting ? s.kcalRemaining : nil, caffeineTodayMg: s.caffeineMg,
                                hoursToBed: hours, allergies: profile?.allergies ?? [])
    }

    private func log() {
        context.insert(MealRecord(at: .now, mealType: AddFoodView.guessMealType(), originalText: items.map(\.name).joined(separator: ", "), items: items,
                                  source: items.allSatisfy(\.verified) ? .confirmed : .aiEstimate, confidence: items.map(\.confidence).min() ?? .medium))
        for i in items {
            if let mg = i.nutrition.caffeineMg, mg > 0 {
                context.insert(CaffeineRecord(at: .now, name: i.name, servingMl: i.grams, mg: mg, mgSource: i.dataSource, source: i.verified ? .confirmed : .aiEstimate))
            }
        }
        try? context.save()
        logged = true
    }
}
