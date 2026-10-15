import SwiftUI
import SwiftData
import ResetCore

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \MealRecord.at, order: .reverse) private var meals: [MealRecord]
    @State private var adding = false
    @State private var editing: MealRecord?
    @State private var logDrink = false

    private var profile: UserProfile? { profiles.first }
    private var today: [MealRecord] { meals.filter { Calendar.current.isDateInToday($0.at) } }
    private var totals: DayNutrition { NutritionTotals.day(meals.map { ($0.at, $0.items) }, on: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summary
                    MealIdeasCard()
                    WaterCard()
                    CaffeineCard { logDrink = true }
                    Card(title: "Today") {
                        if today.isEmpty {
                            EmptyNote(systemImage: "fork.knife", title: "Nothing logged yet",
                                      message: "Log what you ate. Not logging a meal does not mean you skipped it, so skip freely.",
                                      actionTitle: "Log food") { adding = true }
                        }
                        ForEach(today) { m in
                            Button { editing = m } label: { MealRow(meal: m) }.buttonStyle(.plain)
                            if m.id != today.last?.id { Divider() }
                        }
                    }
                    let older = meals.filter { !Calendar.current.isDateInToday($0.at) }.prefix(15)
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
            .background(Theme.background)
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NavigationLink { RemindersSettingsView() } label: { Image(systemName: "bell") }.accessibilityLabel("Reminders") }
                ToolbarItem(placement: .topBarLeading) { NavigationLink { PurchasesView() } label: { Image(systemName: "bag") }.accessibilityLabel("Purchases") }
                ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Log food") }
            }
            .sheet(isPresented: $adding) { AddFoodView() }
            .sheet(isPresented: $logDrink) { LogDrinkView() }
            .sheet(item: $editing) { MealEditor(meal: $0) }
        }
    }

    @ViewBuilder private var summary: some View {
        let plan = profile?.energyPlan
        Card(title: "Calories and protein") {
            if profile?.calorieCountingEnabled == false {
                Text("Calorie counting is off. Protein and meals are still tracked. Turn it back on in Settings.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                BigMetric(value: "\(Int(totals.total.proteinG.rounded()))", unit: "g protein",
                          caption: plan.map { "Target about \(Int($0.proteinG.rounded())) g" })
            } else {
                HStack(alignment: .top) {
                    BigMetric(value: "\(Int(totals.total.kcal.rounded()))", unit: "kcal",
                              caption: plan?.targetKcal.map { "Suggested about \(Int($0.rounded()))" } ?? "Target: Estimate unavailable")
                    Spacer()
                    BigMetric(value: "\(Int(totals.total.proteinG.rounded()))", unit: "g protein",
                              caption: plan.map { "Target about \(Int($0.proteinG.rounded())) g" })
                }
                if let t = plan?.targetKcal {
                    ProgressBar(fraction: totals.total.kcal / t)
                }
                if let bal = Energy.balance(consumedKcal: totals.total.kcal, maintenanceKcal: plan?.maintenanceKcal) {
                    Text("Balance so far: \(Int(bal.rounded())) kcal against estimated maintenance. The day is not over, so this is not a verdict.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            HStack(spacing: 16) {
                Text("Carbs \(Int(totals.total.carbsG.rounded())) g")
                Text("Fat \(Int(totals.total.fatG.rounded())) g")
                if let f = totals.total.fiberG { Text("Fiber \(Int(f.rounded())) g") }
            }.font(.footnote).foregroundStyle(Theme.secondaryText)
            if totals.estimatedItemCount > 0 {
                Text("\(totals.estimatedItemCount) item(s) are estimates, not database values.")
                    .font(.caption).foregroundStyle(Theme.warn)
            }
        }
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
