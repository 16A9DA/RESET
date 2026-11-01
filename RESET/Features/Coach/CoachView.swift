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
    /// The chat new messages go to. Set by the view before any send.
    var sessionID: UUID?
    private(set) var backend: AppCoachBackend?

    func configure(container: ModelContainer, health: HealthService) {
        if backend == nil { backend = AppCoachBackend(container: container, health: health) }
    }

    var drafts: [FoodDraft] {
        get { backend?.drafts ?? [] }
        set { backend?.drafts = newValue }
    }

    private func say(_ role: String, _ text: String, in context: ModelContext) {
        context.insert(ChatMessage(role: role, text: text, sessionID: sessionID))
        if let id = sessionID, let chat = (try? context.fetch(FetchDescriptor<ChatSession>(predicate: #Predicate { $0.id == id })))?.first {
            chat.updatedAt = .now
            if role == "user", chat.title == "New chat" { chat.title = String(text.prefix(40)) }
        }
        try? context.save()
    }

    func send(_ text: String, context: ModelContext, profile: UserProfile?, health: HealthService) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let backend else { return }
        error = nil; needsAI = false
        say("user", t, in: context)

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
            if provider == nil, MealSuggester.wantsIdeas(t) {
                let slot = MealSuggester.slot(in: t, fallback: AddFoodView.guessMealType())
                let eating = MealSuggester.context(in: t, fallback: EatingContext(rawValue: UserDefaults.standard.string(forKey: "meal.context") ?? "") ?? .cafeteria)
                let req = MealIdeaBuilder.request(context: context, profile: profile, health: health, slot: slot, eating: eating)
                let text = MealSuggester.describe(MealSuggester.suggest(req), remainingKcal: req.remainingKcal, remainingProteinG: req.remainingProteinG)
                say("assistant", text, in: context); return
            }
            if let a = LocalCoach.answer(t, summary: summary, foodsToday: foods, bedtime: bed, wake: nil) {
                say("assistant", a, in: context); return
            }
            if provider == nil { needsAI = true; return }
        }
        guard let provider else { return }

        busy = true
        defer { busy = false }
        // Recent text only. Tool traces are not stored, which keeps requests small.
        let sid = sessionID
        let recent = ((try? context.fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.sessionID == sid }, sortBy: [SortDescriptor(\.at, order: .reverse)]))) ?? []).prefix(13).reversed().dropLast()
        let history = recent.map { AIMessage(role: $0.role == "user" ? .user : .assistant, parts: [.text($0.text)]) }
        let sys = CoachEngine.system(now: .now, goal: profile?.goal.title ?? "general health", units: profile?.units.rawValue ?? "metric")
        do {
            let turn = try await CoachEngine.respond(history: Self.alternating(history), user: t, system: sys, provider: provider, backend: backend)
            pending += turn.pending
            say("assistant", turn.reply.isEmpty ? "Done." : turn.reply, in: context)
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
        say("assistant", r.isError ? "Could not do that: \(r.text)" : r.text, in: context)
    }

    func decline(_ p: PendingAction, context: ModelContext) {
        pending.removeAll { $0.id == p.id }
        say("assistant", "Okay, I did not do that.", in: context)
    }
}

struct CoachView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(CoachModel.self) private var model
    @Environment(AppRouter.self) private var router
    @FocusState private var inputFocused: Bool
    @Query(sort: \ChatMessage.at) private var allMessages: [ChatMessage]
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]
    @Query private var profiles: [UserProfile]
    @AppStorage("coach.session") private var activeRaw = ""
    @State private var input = ""
    @State private var editing: FoodDraft?
    @State private var showChats = false

    private let suggestions = ["What should I do today?", "I'm exhausted after work", "When should I go to sleep?"]

    private var activeID: UUID? { UUID(uuidString: activeRaw).flatMap { id in sessions.contains { $0.id == id } ? id : nil } }
    private var messages: [ChatMessage] { allMessages.filter { $0.sessionID == activeID && activeID != nil } }
    private var title: String { sessions.first { $0.id == activeID }?.title ?? "New chat" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if messages.isEmpty { intro }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            ForEach(model.pending) { p in pendingCard(p) }
                            ForEach(model.drafts) { d in draftCard(d) }
                            if model.busy { ProgressView().padding() }
                            if model.needsAI { needsAICard }
                            if let e = model.error { Text(e).font(.footnote).foregroundStyle(Theme.low) }
                        }.padding(.horizontal).padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in if let last = messages.last { withAnimation(.spring(duration: 0.35, bounce: 0)) { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
                inputBar
            }
            .background(GlassBackdrop())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { inputFocused = false; router.tab = .today } label: { Label("Back", systemImage: "chevron.left") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showChats = true } label: { Image(systemName: "text.justify.left") }.accessibilityLabel("All chats")
                    Button { newChat() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New chat").disabled(messages.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                }
            }
            .task { adoptOldMessages() }
            .sheet(item: $editing) { d in AddFoodView(initialItems: d.items, initialText: d.text) }
            .sheet(isPresented: $showChats) { chatList }
        }
    }

    // MARK: Chats

    private func newChat() {
        inputFocused = false
        model.drafts = []; model.pending = []; model.error = nil; model.needsAI = false
        activeRaw = ""
    }

    private func open(_ chat: ChatSession) {
        model.drafts = []; model.pending = []; model.error = nil; model.needsAI = false
        activeRaw = chat.id.uuidString
        showChats = false
    }

    private func delete(_ chat: ChatSession) {
        allMessages.filter { $0.sessionID == chat.id }.forEach(context.delete)
        if chat.id == activeID { activeRaw = "" }
        context.delete(chat)
        try? context.save()
    }

    /// Messages saved before chats existed become one chat, so nothing is lost.
    private func adoptOldMessages() {
        let old = allMessages.filter { $0.sessionID == nil }
        guard !old.isEmpty else { return }
        let chat = ChatSession(title: "Earlier chat")
        chat.createdAt = old.first?.at ?? .now
        chat.updatedAt = old.last?.at ?? .now
        context.insert(chat)
        old.forEach { $0.sessionID = chat.id }
        try? context.save()
        if activeID == nil { activeRaw = chat.id.uuidString }
    }

    private var chatList: some View {
        NavigationStack {
            List {
                ForEach(sessions) { chat in
                    Button { open(chat) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.title).font(.body.weight(chat.id == activeID ? .semibold : .regular)).lineLimit(1)
                            Text(chat.updatedAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions { Button("Delete", role: .destructive) { delete(chat) } }
                }
            }
            .overlay { if sessions.isEmpty { Text("No chats yet").foregroundStyle(Theme.secondaryText) } }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showChats = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var profile: UserProfile? { profiles.first }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about your day").font(.system(.title2, design: .rounded, weight: .bold)).tracking(-0.4)
            Text("You are talking to an AI, not a person or a doctor.").font(.footnote).foregroundStyle(Theme.secondaryText)
            ForEach(suggestions, id: \.self) { s in
                Button(s) { send(s) }.buttonStyle(.bordered).font(.footnote)
            }
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == "user" { Spacer(minLength: 40) }
            Text(m.text)
                .font(.body).lineSpacing(2)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(m.role == "user" ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { if m.role != "user" { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline) } }
                .foregroundStyle(m.role == "user" ? Color.black : Color.primary)
                .textSelection(.enabled)
            if m.role != "user" { Spacer(minLength: 40) }
        }
    }

    private func pendingCard(_ p: PendingAction) -> some View {
        Card {
            Text(p.text)
            HStack {
                Button("Confirm") { Task { await model.confirm(p, context: context) } }.buttonStyle(.borderedProminent)
                Button("No thanks") { model.decline(p, context: context) }.buttonStyle(.bordered)
            }
        }
    }

    private func draftCard(_ d: FoodDraft) -> some View {
        let total = d.items.filter(\.consumed).reduce(Nutrition.zero) { $0 + $1.nutrition }
        return Card {
            ForEach(d.items) { i in
                Text("\(i.name), \(Int(i.grams)) g, \(Int(i.nutrition.kcal)) kcal\(i.verified ? "" : " (estimate)")").font(.subheadline)
            }
            Text("About \(Int(total.kcal)) kcal, \(Int(total.proteinG)) g protein. Not saved yet.").font(.footnote).foregroundStyle(Theme.secondaryText)
            ForEach(d.uncertainties, id: \.self) { Text("Unsure: \($0)").font(.caption).foregroundStyle(Theme.warn) }
            HStack {
                Button("Save") { saveDraft(d) }.buttonStyle(.borderedProminent)
                Button("Edit") { editing = d; model.drafts.removeAll { $0.id == d.id } }.buttonStyle(.bordered)
                Button("Discard", role: .destructive) { model.drafts.removeAll { $0.id == d.id } }.buttonStyle(.bordered)
            }
        }
    }

    private var needsAICard: some View {
        Card {
            Text("Simple questions work now. For more, turn on AI.").font(.footnote)
            if let p = profile { NavigationLink("Turn on AI") { AISettingsView(profile: p) } }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom) {
            TextField("Message the AI coach", text: $input, axis: .vertical).lineLimit(1...4)
                .padding(10).glass(18)
                .focused($inputFocused)
                .submitLabel(.send).onSubmit { send(input) }
            Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                .buttonStyle(Press())
                .tint(Theme.accent)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
                .accessibilityLabel("Send")
        }
        .padding(10).background(.ultraThinMaterial)
    }

    private func send(_ text: String) {
        input = ""
        if activeID == nil {
            let chat = ChatSession()
            context.insert(chat)
            try? context.save()
            activeRaw = chat.id.uuidString
        }
        model.sessionID = activeID ?? UUID(uuidString: activeRaw)
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
        context.insert(ChatMessage(role: "assistant", text: "Saved to today's food log as estimates.", sessionID: activeID))
        try? context.save()
    }
}
