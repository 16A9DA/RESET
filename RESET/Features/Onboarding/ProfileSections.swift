import SwiftUI
import ResetCore

/// Shared by onboarding and Settings so every answer can be changed later.
struct BodySection: View {
    @Bindable var profile: UserProfile

    private var imperial: Bool { profile.units == .imperial }

    private var weight: Binding<Double> {
        Binding(get: { imperial ? Units.kgToLb(profile.weightKg) : profile.weightKg },
                set: { profile.weightKg = imperial ? Units.lbToKg($0) : $0 })
    }
    private var height: Binding<Double> {
        Binding(get: { imperial ? Units.cmToIn(profile.heightCm) : profile.heightCm },
                set: { profile.heightCm = imperial ? Units.inToCm($0) : $0 })
    }
    private var target: Binding<Double> {
        Binding(get: { (imperial ? profile.targetWeightKg.map(Units.kgToLb) : profile.targetWeightKg) ?? 0 },
                set: { v in profile.targetWeightKg = v <= 0 ? nil : (imperial ? Units.lbToKg(v) : v) })
    }
    private var ageShared: Binding<Bool> {
        Binding(get: { profile.age != nil }, set: { profile.age = $0 ? (profile.age ?? 30) : nil })
    }
    private var sexChoice: Binding<String> {
        Binding(get: { profile.sex?.rawValue ?? "none" }, set: { profile.sex = Sex(rawValue: $0) })
    }

    var body: some View {
        Section("Units") {
            Picker("Units", selection: $profile.units) {
                Text("Metric").tag(UnitSystem.metric)
                Text("Imperial").tag(UnitSystem.imperial)
            }.pickerStyle(.segmented)
        }
        Section {
            HStack {
                Text("Height (\(imperial ? "in" : "cm"))")
                Spacer()
                TextField("", value: height, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
            HStack {
                Text("Weight (\(imperial ? "lb" : "kg"))")
                Spacer()
                TextField("", value: weight, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
            HStack {
                Text("Target weight, optional")
                Spacer()
                TextField("None", value: target, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
        } header: {
            Text("Body")
        }
        Section {
            Toggle("Use my age for calorie estimates", isOn: ageShared)
            if let age = profile.age {
                Stepper("Age: \(age)", value: Binding(get: { age }, set: { profile.age = $0 }), in: 16...100)
            }
            Picker("Sex, optional", selection: sexChoice) {
                Text("Prefer not to say").tag("none")
                Text("Female").tag(Sex.female.rawValue)
                Text("Male").tag(Sex.male.rawValue)
            }
        } header: {
            Text("Optional")
        } footer: {
            Text("Used only for the resting energy equation. Skip them and RE:SET shows general estimates, or you can enter your own maintenance calories.")
        }
    }
}

struct GoalSection: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Section("Main goal") {
            Picker("Goal", selection: $profile.goal) {
                ForEach(Goal.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        Section("Typical day") {
            Picker("Activity", selection: $profile.activityLevel) {
                ForEach(ActivityLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Stepper("Gym days per week: \(profile.gymDaysPerWeek)", value: $profile.gymDaysPerWeek, in: 0...7)
            Picker("Training experience", selection: $profile.trainingLevel) {
                ForEach(TrainingLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Equipment", selection: $profile.equipment) {
                ForEach(Equipment.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }
}

struct ScheduleSection: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Section("Sleep") {
            DatePicker("Usually wake up", selection: $profile.wakeMinute.asTimeOfDay(), displayedComponents: .hourAndMinute)
            DatePicker("Usually go to bed", selection: $profile.bedMinute.asTimeOfDay(), displayedComponents: .hourAndMinute)
        }
        Section {
            NavigationLink("Add work, university or gym") { PlacesView() }
        } header: { Text("Automatic tracking") } footer: {
            Text("Search the name. RE:SET then notes when you arrive and leave by itself. Choose Always for location.")
        }
        GoalHoursSection(title: "Work", hours: $profile.workGoalHours, onChange: profile.syncDays)
        GoalHoursSection(title: "University", hours: $profile.uniGoalHours, onChange: profile.syncDays)
    }
}

/// Hours per weekday. Each day has its own goal, 0 is a day off. Places tell the app when you are there.
struct GoalHoursSection: View {
    let title: String
    @Binding var hours: [Double]
    var onChange: () -> Void

    var body: some View {
        Section {
            ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { i, name in
                Stepper(value: Binding(get: { hours[i] }, set: { hours[i] = $0; onChange() }), in: 0...16, step: 0.5) {
                    HStack {
                        Text(name)
                        Spacer()
                        Text(hours[i] == 0 ? "Off" : "\(hours[i].formatted()) h").foregroundStyle(Theme.secondaryText).monospacedDigit()
                    }
                }
            }
        } header: { Text(title) }
    }
}

struct HabitsSection: View {
    @Bindable var profile: UserProfile
    @State private var diet = ""
    @State private var allergy = ""

    private func list(_ title: String, text: Binding<String>, items: Binding<[String]>) -> some View {
        Group {
            HStack {
                TextField(title, text: text).textInputAutocapitalization(.never)
                Button("Add") {
                    let t = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty && !items.wrappedValue.contains(t) { items.wrappedValue.append(t) }
                    text.wrappedValue = ""
                }.disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(items.wrappedValue, id: \.self) { item in
                Text(item)
            }
            .onDelete { items.wrappedValue.remove(atOffsets: $0) }
        }
    }

    var body: some View {
        Section("Dietary preferences") {
            list("e.g. no pork, vegetarian", text: $diet, items: $profile.dietaryPreferences)
        }
        Section("Allergies, optional") {
            list("e.g. peanuts", text: $allergy, items: $profile.allergies)
        }
        Section {
            TextField("e.g. 2 energy drinks a day", text: $profile.caffeineHabit)
        } header: {
            Text("Caffeine habits")
        }
    }
}
