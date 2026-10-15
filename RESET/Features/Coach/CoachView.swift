import SwiftUI
import SwiftData
import Observation
import ResetCore

@MainActor
@Observable
final class CoachModel {
    var busy = false
    var error: String?
    var pending: [PendingAction] = []
    var needsAI = false
    private(set) var backend: AppCoachBackend?

    func configure(container: ModelContainer, health: HealthService) {
        if backend == nil { backend = AppCoachBackend(container: container, health: health) }
    }

    var drafts: [FoodDraft] {
        get { backend?.drafts ?? [] }
        set { backend?.drafts = newValue }
    }

    func send(_ text: String, context: ModelContext, profile: UserProfile?, health: HealthService) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let backend else { return }
        error = nil; needsAI = false
        context.insert(ChatMessage(role: "user", text: t))
        try? context.save()

        // Urgent wording and simple data questions never need a model.
        let summary = DaySummaryBuilder.build(context: context, profile: profile, health: health)
        let foods = ((try? context.fetch(FetchDescriptor<MealRecord>())) ?? []).filter { Calendar.current.isDateInToday($0.at) }
            .map { "\($0.mealType.title): " + $0.items.map(\.name).joined(separator: ", ") }
        var bed: Date?
        if let p = profile {
            let wake = DayShape(wakeMinute: p.wakeMinute, bedMinute: p.bedMinute).window(on: .now).start
            bed = SleepPlanner.bedtime(wake: wake, targetHours: p.sleepTargetHours)
        }
        let provider = AIConfig.provider(for: profile)
        if provider == nil || Safety.needsUrgentCare(t) {
            if let a = LocalCoach.answer(t, summary: summary, foodsToday: foods, bedtime: bed, wake: nil) {
                context.insert(ChatMessage(role: "assistant", text: a)); try? context.save(); return
            }
            if provider == nil { needsAI = true; return }
        }
        guard let provider else { return }

        busy = true
        defer { busy = false }
        // Recent text only. Tool traces are not stored, which keeps requests small.
        let recent = ((try? context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.at, order: .reverse)]))) ?? []).prefix(13).reversed().dropLast()
        let history = recent.map { AIMessage(role: $0.role == "user" ? .user : .assistant, parts: [.text($0.text)]) }
        let sys = CoachEngine.system(now: .now, goal: profile?.goal.title ?? "general health", units: profile?.units.rawValue ?? "metric")
        do {
            let turn = try await CoachEngine.respond(history: Self.alternating(history), user: t, system: sys, provider: provider, backend: backend)
            pending += turn.pending
            context.insert(ChatMessage(role: "assistant", text: turn.reply.isEmpty ? "Done." : turn.reply))
            try? context.save()
        } catch {
            self.error = error.localizedDescription + " Your message was kept. Try again, or use the Nutrition and Today screens directly."
        }
    }

    /// The API needs strictly alternating roles starting with user. Drop anything that breaks that.
    static func alternating(_ msgs: [AIMessage]) -> [AIMessage] {
        var out: [AIMessage] = []
        for m in msgs where out.last?.role != m.role { out.append(m) }
        while out.first?.role == .assistant { out.removeFirst() }
        if out.last?.role == .user { out.removeLast() }
        return out
    }

    func confirm(_ p: PendingAction, context: ModelContext) async {
        guard let backend else { return }
        pending.removeAll { $0.id == p.id }
        let r = await backend.execute(p.action)
        context.insert(ChatMessage(role: "assistant", text: r.isError ? "Could not do that: \(r.text)" : r.text))
        try? context.save()
    }

    func decline(_ p: PendingAction, context: ModelContext) {
        pending.removeAll { $0.id == p.id }
        context.insert(ChatMessage(role: "assistant", text: "Okay, I did not do that."))
        try? context.save()
    }
}

struct CoachView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(CoachModel.self) private var model
    @Query(sort: \ChatMessage.at) private var messages: [ChatMessage]
    @Query private var profiles: [UserProfile]
    @State private var input = ""
    @State private var editing: FoodDraft?

    private let suggestions = ["What should I do today?", "How many calories do I have left?", "Should I go to the gym?",
                               "I'm exhausted after work", "Suggest a high-protein cafeteria meal", "When should I go to sleep?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if messages.isEmpty { intro }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            ForEach(model.pending) { p in pendingCard(p) }
                            ForEach(model.drafts) { d in draftCard(d) }
                            if model.busy { ProgressView().padding() }
                            if model.needsAI { needsAICard }
                            if let e = model.error { Text(e).font(.footnote).foregroundStyle(Theme.low) }
                        }.padding()
                    }
                    .onChange(of: messages.count) { _, _ in if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
                inputBar
            }
            .background(Theme.background)
            .navigationTitle("AI Coach")
            .toolbar {
                Menu {
                    Button("Clear conversation", role: .destructive) { messages.forEach(context.delete); try? context.save() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .sheet(item: $editing) { d in AddFoodView(initialItems: d.items, initialText: d.text) }
        }
    }

    private var profile: UserProfile? { profiles.first }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about your day").font(.title3.weight(.semibold))
            Text("The coach reads what you have logged. It says so when something is missing, and it never logs or changes settings without you being able to review it. It is not a doctor.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            ForEach(suggestions, id: \.self) { s in
                Button(s) { send(s) }.buttonStyle(.bordered).font(.footnote)
            }
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == "user" { Spacer(minLength: 40) }
            Text(m.text)
                .padding(12)
                .background(m.role == "user" ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(m.role == "user" ? Color.black : Color.white)
            if m.role != "user" { Spacer(minLength: 40) }
        }
    }

    private func pendingCard(_ p: PendingAction) -> some View {
        Card(title: "Needs your OK") {
            Text(p.text)
            HStack {
                Button("Confirm") { Task { await model.confirm(p, context: context) } }.buttonStyle(.borderedProminent)
                Button("No thanks") { model.decline(p, context: context) }.buttonStyle(.bordered)
            }
        }
    }

    private func draftCard(_ d: FoodDraft) -> some View {
        let total = d.items.filter(\.consumed).reduce(Nutrition.zero) { $0 + $1.nutrition }
        return Card(title: "Food draft, not saved yet") {
            ForEach(d.items) { i in
                Text("\(i.name), \(Int(i.grams)) g, \(Int(i.nutrition.kcal)) kcal\(i.verified ? "" : " (estimate)")").font(.subheadline)
            }
            Text("About \(Int(total.kcal)) kcal and \(Int(total.proteinG)) g protein. Estimates, check before saving.").font(.footnote).foregroundStyle(Theme.secondaryText)
            ForEach(d.uncertainties, id: \.self) { Text("Unsure: \($0)").font(.caption).foregroundStyle(Theme.warn) }
            HStack {
                Button("Save") { saveDraft(d) }.buttonStyle(.borderedProminent)
                Button("Edit") { editing = d; model.drafts.removeAll { $0.id == d.id } }.buttonStyle(.bordered)
                Button("Discard", role: .destructive) { model.drafts.removeAll { $0.id == d.id } }.buttonStyle(.bordered)
            }
        }
    }

    private var needsAICard: some View {
        Card(title: "AI is not set up") {
            Text("I can answer simple questions about your water, calories, protein, steps and work hours without AI. For anything else, add an API key.")
                .font(.footnote)
            if let p = profile { NavigationLink("Set up AI") { AISettingsView(profile: p) } }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom) {
            TextField("Message", text: $input, axis: .vertical).lineLimit(1...4)
                .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                .submitLabel(.send).onSubmit { send(input) }
            Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
                .accessibilityLabel("Send")
        }
        .padding(10).background(Theme.background)
    }

    private func send(_ text: String) {
        input = ""
        Task { await model.send(text, context: context, profile: profile, health: health) }
    }

    private func saveDraft(_ d: FoodDraft) {
        context.insert(MealRecord(at: .now, mealType: d.mealType, originalText: d.text, items: d.items, source: .aiEstimate,
                                  confidence: d.items.map(\.confidence).min() ?? .medium))
        for i in d.items where i.consumed && (i.nutrition.caffeineMg ?? 0) > 0 {
            context.insert(CaffeineRecord(name: i.name, servingMl: i.grams, mg: i.nutrition.caffeineMg!, mgSource: i.dataSource, source: .aiEstimate))
        }
        try? context.save()
        model.drafts.removeAll { $0.id == d.id }
        context.insert(ChatMessage(role: "assistant", text: "Saved to today's food log as estimates."))
        try? context.save()
    }
}
