import SwiftUI
import SwiftData
import PhotosUI
import ResetCore

enum PurchaseStore {
    /// Adds candidates as pending drafts, skipping ones already waiting or recently handled.
    @MainActor @discardableResult
    static func add(_ candidates: [PurchaseCandidate], source: String, context: ModelContext, showAll: Bool = false) -> Int {
        let known = ((try? context.fetch(FetchDescriptor<PurchaseDraft>())) ?? []).map(\.text)
        let wanted = PurchaseParser.removingKnown(showAll ? candidates : PurchaseParser.relevant(candidates), known: known)
        for c in wanted { context.insert(PurchaseDraft(text: c.text, category: c.category, source: source)) }
        try? context.save()
        return wanted.count
    }

    /// Handled drafts older than two weeks are removed. Pending ones stay until you decide.
    @MainActor
    static func prune(context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        for d in (try? context.fetch(FetchDescriptor<PurchaseDraft>())) ?? [] where !d.pending && d.createdAt < cutoff { context.delete(d) }
        try? context.save()
    }
}

struct PurchasesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PurchaseDraft.createdAt, order: .reverse) private var drafts: [PurchaseDraft]
    @Query private var ruleRecords: [PurchaseRuleRecord]
    @Query private var profiles: [UserProfile]
    @State private var pasted = ""
    @State private var showAll = false
    @State private var message: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var busy = false
    @State private var eating: PurchaseDraft?
    @State private var newKeyword = ""
    @State private var newPrefill = ""

    private var pending: [PurchaseDraft] { drafts.filter(\.pending) }
    private var rules: [PurchaseRule] { ruleRecords.map(\.rule) }

    var body: some View {
        List {
            Section {
                Text("Purchases are not meals. A bought item only becomes a food entry after you say you ate it. Prices, totals and card numbers are removed and never stored.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }

            Section("Paste receipt text") {
                TextEditor(text: $pasted).frame(minHeight: 110).font(.footnote)
                Toggle("Include non-food lines", isOn: $showAll).font(.footnote)
                Button("Find items") { importPasted() }.disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.secondaryText) }
            }

            Section {
                if let p = profiles.first, AIConfig.provider(for: p) != nil {
                    HStack {
                        if CameraPicker.available { Button("Take photo") { showCamera = true } }
                        PhotosPicker("Choose photo", selection: $pickerItem, matching: .images)
                    }
                    if busy { ProgressView() }
                } else {
                    Text("Reading a receipt photo needs an AI provider. Set one up under Settings, AI and data sources. Pasting text works without one.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            } header: { Text("Receipt photo") } footer: {
                Text("The photo is sent to your selected AI provider to read the item names. It is not saved on this phone.")
            }

            Section("Waiting for you") {
                if pending.isEmpty {
                    EmptyNote(systemImage: "bag", title: "Nothing waiting", message: "Paste a receipt, photograph one, or send text from the Shortcuts app.")
                }
                ForEach(pending) { d in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.text).font(.headline)
                        Text(subtitle(d)).font(.caption).foregroundStyle(Theme.secondaryText)
                        HStack {
                            Button("I ate this") { eating = d }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                            Button("Not eaten") { d.statusRaw = "dismissed"; try? context.save() }.buttonStyle(.bordered)
                        }.font(.footnote)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { context.delete(d); try? context.save() } }
                }
            }

            Section {
                ForEach(ruleRecords) { r in
                    VStack(alignment: .leading) { Text(r.keyword).font(.subheadline); Text("fills in: \(r.prefill)").font(.caption).foregroundStyle(Theme.secondaryText) }
                }
                .onDelete { $0.map { ruleRecords[$0] }.forEach(context.delete); try? context.save() }
                TextField("When the purchase contains", text: $newKeyword).textInputAutocapitalization(.never)
                TextField("Prefill the food box with", text: $newPrefill)
                Button("Add rule") {
                    let r = PurchaseRule(keyword: newKeyword, prefill: newPrefill)
                    guard PurchaseRules.isValid(r), ruleRecords.count < PurchaseRules.maxRules else { return }
                    context.insert(PurchaseRuleRecord(keyword: r.keyword, prefill: r.prefill)); try? context.save()
                    newKeyword = ""; newPrefill = ""
                }.disabled(!PurchaseRules.isValid(PurchaseRule(keyword: newKeyword, prefill: newPrefill)))
            } header: { Text("Your rules") } footer: {
                Text("Example: \"uni cafe\" fills in \"cafeteria lunch, chicken and rice\". Rules only save you typing. They never log food on their own, and you always confirm.")
            }

            Section("Automation") {
                Text("In the Shortcuts app, build a shortcut that accepts text and runs Add purchase text from RE:SET, then turn on Show in Share Sheet. Sharing a receipt, email or note text to it adds items here as drafts. iOS does not let apps read other apps or notifications, so nothing is captured automatically.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle("Purchases")
        .onAppear { PurchaseStore.prune(context: context) }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { readReceipt($0) }.ignoresSafeArea() }
        .onChange(of: pickerItem) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { readReceipt(img) } }
        }
        .sheet(item: $eating) { d in
            let text = PurchaseRules.prefill(for: d.text, rules: rules)
            AddFoodView(initialItems: d.items.map { var i = $0; i.consumed = true; return i }, initialText: text,
                        startWith: .describe)
                .onDisappear { markAteIfLogged(d) }
        }
    }

    private func subtitle(_ d: PurchaseDraft) -> String {
        let kind: String
        switch d.category {
        case .groceries: kind = "Grocery shop. Tell me what you actually ate."
        case .drink: kind = "Drink"
        case .food: kind = "Food"
        default: kind = "Not sure what this is"
        }
        let src = d.sourceRaw == "receipt" ? "from a receipt photo" : (d.sourceRaw == "shortcut" ? "from Shortcuts" : "pasted")
        return "\(kind), \(src)"
    }

    private func importPasted() {
        let all = PurchaseParser.parse(pasted)
        let n = PurchaseStore.add(all, source: "paste", context: context, showAll: showAll)
        message = n == 0 ? (all.isEmpty ? "No item lines found." : "Nothing new to add. Non-food lines and repeats are skipped.") : "Added \(n) item(s) for you to review."
        if n > 0 { pasted = "" }
    }

    private func readReceipt(_ image: UIImage) {
        guard let provider = AIConfig.provider(for: profiles.first), let jpeg = ImagePrep.jpeg(image) else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let a = try await ReceiptAnalyzer.analyze(imageJPEG: jpeg, provider: provider, lookup: USDAClient(apiKey: Keychain.get(Keychain.usdaKey)),
                                                          brandLookup: OpenFoodFactsSearch())
                let known = drafts.map(\.text)
                var added = 0
                for i in a.items where !PurchaseParser.removingKnown([PurchaseCandidate(text: i.name, category: .food)], known: known).isEmpty {
                    context.insert(PurchaseDraft(text: i.name, category: PurchaseParser.categorize(i.name), source: "receipt", items: [i])); added += 1
                }
                try? context.save()
                message = added == 0 ? "Those items are already in your list." : "Read \(added) item(s) from the receipt. Check them before saying you ate anything."
            } catch { message = "\(error.localizedDescription) Nothing was added. You can paste the text instead." }
        }
    }

    /// The sheet closing does not prove a meal was saved. Only mark the draft handled if a matching meal now exists.
    private func markAteIfLogged(_ d: PurchaseDraft) {
        let recent = ((try? context.fetch(FetchDescriptor<MealRecord>())) ?? []).filter { $0.createdAt > Date.now.addingTimeInterval(-300) }
        if !recent.isEmpty { d.statusRaw = "ate"; try? context.save() }
    }
}
