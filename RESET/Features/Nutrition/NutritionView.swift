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

    @State private var chooser = false
    @State private var pendingMethod: FoodMethod?
    @State private var addMethod: FoodMethod?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    eatenCard
                    if today.isEmpty {
                        EmptyNote(systemImage: "fork.knife", title: "Nothing logged yet",
                                  message: "Not logging does not mean you skipped.", actionTitle: "Add food") { chooser = true }
                    } else {
                        ForEach(MealType.allCases, id: \.self) { type in mealGroup(type) }
                    }
                    ListGroup {
                        NavigationLink { ScrollView { WaterCard().padding() }.background(GlassBackdrop()).navigationTitle("Water") } label: {
                            GroupRow(title: "Water", icon: "drop", tint: Theme.water)
                        }.buttonStyle(Press())
                        GroupDivider()
                        NavigationLink { ScrollView { CaffeineCard().padding() }.background(GlassBackdrop()).navigationTitle("Caffeine") } label: {
                            GroupRow(title: "Caffeine", icon: "cup.and.saucer", value: caffeineMg > 0 ? "\(Int(caffeineMg.rounded())) mg" : nil, tint: Theme.carbs)
                        }.buttonStyle(Press())
                        GroupDivider()
                        Button { canEat = true } label: { GroupRow(title: "Can I eat this?", icon: "questionmark.circle", tint: Theme.accent) }.buttonStyle(Press())
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
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 12)
            }
            .background(GlassBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { addBar }
            .sheet(isPresented: $chooser, onDismiss: { if let m = pendingMethod { pendingMethod = nil; addMethod = m } }) {
                AddFoodChooser { pendingMethod = $0; chooser = false }
                    .presentationDetents([.height(340)]).presentationDragIndicator(.visible)
            }
            .sheet(item: $addMethod) { AddFoodView(startWith: $0) }
            .sheet(isPresented: $adding) { AddFoodView() }
            .sheet(isPresented: $canEat) { CanIEatView() }
            .sheet(item: $editing) { MealEditor(meal: $0) }
        }
    }

    private var header: some View {
        PageHeader(title: "Nutrition", subtitle: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
            Button { chooser = true } label: { Image(systemName: "plus").font(.title3) }.foregroundStyle(.primary).accessibilityLabel("Add food")
        }
    }

    @ViewBuilder private var eatenCard: some View {
        let plan = profile?.energyPlan
        let t = totals.total
        if profile?.calorieCountingEnabled != false, let target = plan?.targetKcal {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Int(t.kcal.rounded()).formatted()).font(.system(size: 48, weight: .bold)).tracking(-1.2).monospacedDigit()
                    Text("kcal eaten").font(.body).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    let left = target - t.kcal
                    Text(left >= 0 ? "\(Int(left.rounded())) left" : "\(Int((-left).rounded())) over")
                        .font(.body).foregroundStyle(left >= 0 ? Theme.food : Theme.warn).monospacedDigit()
                }
                ProgressBar(fraction: t.kcal / target, tint: Theme.food).frame(height: 6)
                Text("Daily guide \(Int(target.rounded()).formatted()) kcal · Not a limit").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).glass(24)
        } else {
            summary
        }
    }

    @ViewBuilder private func mealGroup(_ type: MealType) -> some View {
        let group = today.filter { $0.mealType == type }.sorted { $0.at < $1.at }
        if !group.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Text(type == .snack ? "Snacks" : type.title).font(.headline)
                    Spacer()
                    Text("\(Int(group.reduce(0) { $0 + $1.nutrition.kcal }.rounded())) kcal").font(.subheadline).foregroundStyle(Theme.secondaryText).monospacedDigit()
                }
                .padding(.horizontal, 2).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(group) { m in
                        Button { editing = m } label: {
                            VStack(spacing: 0) {
                                ForEach(Array(m.items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name).font(.body).lineLimit(2)
                                            Text("\(Int(item.grams)) g · \(m.at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))")
                                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                                        }
                                        Spacer()
                                        Text("\(Int(item.nutrition.kcal.rounded()))").font(.body).monospacedDigit()
                                    }
                                    .padding(.vertical, 10)
                                }
                            }
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .frame(maxWidth: .infinity).glass(22)
            }
        }
    }

    private var addBar: some View {
        VStack(spacing: 10) {
            if !today.isEmpty {
                Text("Estimates are enough. You can always adjust them.").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { chooser = true } label: {
                Label("Add food", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(Press())
            .background(Theme.accent, in: Capsule()).foregroundStyle(.black)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Theme.background)
    }

    private var caffeineMg: Double { Caffeine.dailyTotal(caffeines.map(\.dose), on: .now) }

    private var summary: some View {
        let plan = profile?.energyPlan
        let t = totals.total
        return FoodSummary(kcal: t.kcal, target: plan?.targetKcal, counting: profile?.calorieCountingEnabled != false,
                           protein: (t.proteinG, plan?.proteinG ?? 0), carbs: (t.carbsG, plan?.carbsG ?? 0), fat: (t.fatG, plan?.fatG ?? 0))
            .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).glass(Theme.cardRadius)
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

/// Bottom sheet that asks how to add food, so the next screen opens straight on that method.
struct AddFoodChooser: View {
    @Environment(\.dismiss) private var dismiss
    var pick: (FoodMethod) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Add food").font(.system(size: 28, weight: .bold)).tracking(-0.5)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).padding(8) }
                    .foregroundStyle(.primary).accessibilityLabel("Close")
            }
            .padding(.top, 22)
            Text("Choose whatever takes the least effort.").font(.subheadline).foregroundStyle(Theme.secondaryText).padding(.bottom, 12)
            row("Describe it", "A few words is enough", "character.cursor.ibeam", .describe)
            row("Photograph it", "Let AI estimate your meal", "camera", .photo)
            row("Scan a barcode", "Quickly add packaged food", "barcode.viewfinder", .barcode)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassBackdrop())
    }

    private func row(_ title: String, _ sub: String, _ icon: String, _ m: FoodMethod) -> some View {
        Button { pick(m) } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(sub).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText.opacity(0.7))
            }
            .padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(Press())
    }
}
