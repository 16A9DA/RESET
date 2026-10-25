import SwiftUI
import SwiftData
import ResetCore

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \MealRecord.at, order: .reverse) private var meals: [MealRecord]
    @State private var adding = false
    @State private var canEat = false
    @Query private var caffeines: [CaffeineRecord]
    @State private var editing: MealRecord?

    private var profile: UserProfile? { profiles.first }
    private var today: [MealRecord] { meals.filter { Calendar.current.isDateInToday($0.at) } }
    private var totals: DayNutrition { NutritionTotals.day(meals.map { ($0.at, $0.items) }, on: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    summary
                    nextMeal
                    WaterCard()
                    ListGroup {
                        NavigationLink { ScrollView { CaffeineCard().padding() }.background(GlassBackdrop()).navigationTitle("Caffeine") } label: {
                            GroupRow(title: "Caffeine", icon: "cup.and.saucer", value: caffeineMg > 0 ? "\(Int(caffeineMg.rounded())) mg" : nil, tint: Theme.carbs)
                        }.buttonStyle(Press())
                        GroupDivider()
                        Button { canEat = true } label: { GroupRow(title: "Can I eat this?", icon: "questionmark.circle", tint: Theme.accent) }.buttonStyle(Press())
                    }
                    if today.isEmpty {
                        EmptyNote(systemImage: "fork.knife", title: "Nothing logged yet",
                                  message: "Not logging does not mean you skipped.", actionTitle: "Log food") { adding = true }
                    } else {
                        Card(title: "Today") {
                            ForEach(today) { m in
                                Button { editing = m } label: { MealRow(meal: m) }.buttonStyle(.plain)
                                if m.id != today.last?.id { Divider() }
                            }
                        }
                    }
                    let older = meals.filter { !Calendar.current.isDateInToday($0.at) }.prefix(5)
                    if !older.isEmpty {
                        Card(title: "Earlier") {
                            ForEach(Array(older)) { m in
                                Button { editing = m } label: { MealRow(meal: m) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(GlassBackdrop())
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Log food") }
            }
            .sheet(isPresented: $adding) { AddFoodView() }
            .sheet(isPresented: $canEat) { CanIEatView() }
            .sheet(item: $editing) { MealEditor(meal: $0) }
        }
    }

    @ViewBuilder private var nextMeal: some View {
        let plan = profile?.energyPlan
        if let a = MacroCoach.advise(consumed: totals.total, targetKcal: profile?.calorieCountingEnabled == false ? nil : plan?.targetKcal,
                                     targetProteinG: plan?.proteinG ?? 0, weightKg: profile?.weightKg ?? 75,
                                     hour: Calendar.current.component(.hour, from: .now), mealsLogged: totals.mealCount) {
            VStack(alignment: .leading, spacing: 3) {
                Text(a.headline).font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(a.detail).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        }
    }

    private var caffeineMg: Double { Caffeine.dailyTotal(caffeines.map(\.dose), on: .now) }

    private var summary: some View {
        let plan = profile?.energyPlan
        let t = totals.total
        return FoodSummary(kcal: t.kcal, target: plan?.targetKcal, counting: profile?.calorieCountingEnabled != false,
                           protein: (t.proteinG, plan?.proteinG ?? 0), carbs: (t.carbsG, plan?.carbsG ?? 0), fat: (t.fatG, plan?.fatG ?? 0))
            .padding(18).glass(24)
    }
}

struct MealRow: View {
    let meal: MealRecord
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.items.map(\.name).joined(separator: ", ")).font(.headline).lineLimit(2)
                Text("\(meal.mealType.title), \(meal.at.formatted(date: .omitted, time: .shortened))\(meal.items.contains { !$0.verified } ? ", estimated" : "")")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text("\(Int(meal.nutrition.kcal.rounded())) kcal").font(.subheadline.monospacedDigit())
        }
        .contentShape(Rectangle())
    }
}

struct MealEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var meal: MealRecord
    @State private var savedName = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $meal.at)
                Picker("Meal", selection: $meal.mealType) {
                    ForEach(MealType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                ForEach($meal.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name", text: $item.name)
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("g", value: Binding(get: { item.grams }, set: { rescale(&item, to: $0) }), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                            Text("g")
                        }
                        HStack {
                            Text("kcal")
                            TextField("", value: $item.nutrition.kcal, format: .number).keyboardType(.decimalPad).frame(width: 60)
                            Text("P")
                            TextField("", value: $item.nutrition.proteinG, format: .number).keyboardType(.decimalPad).frame(width: 50)
                            Text("C")
                            TextField("", value: $item.nutrition.carbsG, format: .number).keyboardType(.decimalPad).frame(width: 50)
                            Text("F")
                            TextField("", value: $item.nutrition.fatG, format: .number).keyboardType(.decimalPad).frame(width: 50)
                        }.font(.footnote)
                        Text(item.verified ? item.dataSource : "Estimate. \(item.dataSource)")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                        Toggle("Actually eaten", isOn: $item.consumed).font(.footnote)
                    }
                }
                .onDelete { meal.items.remove(atOffsets: $0) }
                Section("Save for reuse") {
                    TextField("Name, e.g. Usual breakfast", text: $savedName)
                    Button("Save as meal") {
                        context.insert(SavedMeal(name: savedName, items: meal.items))
                        try? context.save(); savedName = ""
                    }.disabled(savedName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section {
                    Button("Delete meal", role: .destructive) { context.delete(meal); try? context.save(); dismiss() }
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { try? context.save(); dismiss() } }
        }
    }

    /// Changing grams scales nutrition proportionally. Editing the numbers directly afterwards still works.
    private func rescale(_ item: inout FoodItem, to g: Double) {
        guard g > 0, item.grams > 0 else { item.grams = max(0, g); return }
        item.nutrition = item.nutrition.scaled(g / item.grams)
        item.grams = g
    }
}
