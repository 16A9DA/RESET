import SwiftUI
import SwiftData
import ResetCore

extension CaffeineRecord {
    var dose: CaffeineDose { CaffeineDose(at: at, mg: totalMg) }
}

struct CaffeineCard: View {
    @Query(sort: \CaffeineRecord.at, order: .reverse) private var records: [CaffeineRecord]
    @Query private var profiles: [UserProfile]
    var onLog: () -> Void

    private var doses: [CaffeineDose] { records.map(\.dose) }
    private var total: Double { Caffeine.dailyTotal(doses, on: .now) }

    var body: some View {
        let rem = Caffeine.remaining(doses, at: .now)
        Card(title: "Caffeine") {
            HStack(alignment: .top) {
                BigMetric(value: "\(Int(total.rounded()))", unit: "mg today", caption: levelText)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Still active").font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(rem.mid < 1 ? "Little" : "\(Int(rem.low.rounded())) to \(Int(rem.high.rounded())) mg")
                        .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                }
            }
            if let bed = bedtime {
                let cutoff = Caffeine.cutoff(bedtime: bed)
                Text(Date.now < cutoff ? "Aim to finish caffeine by \(cutoff.formatted(date: .omitted, time: .shortened)) to protect tonight's sleep."
                     : "It is past your usual caffeine cutoff. More now may make it harder to fall asleep.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Text("The remaining amount is a rough range. People clear caffeine at different speeds. About 400 mg a day is a commonly cited limit for healthy adults, not a target. If you feel unwell after caffeine, such as chest pain, fainting or a racing heart, seek medical care.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            Button("Log a drink", action: onLog)
        }
    }

    private var levelText: String {
        switch Caffeine.level(totalMg: total) {
        case .none: "None logged"
        case .moderate: "Well under the commonly cited 400 mg"
        case .near: "Approaching the commonly cited 400 mg"
        case .above: "Above the commonly cited 400 mg"
        }
    }

    private var bedtime: Date? {
        guard let p = profiles.first else { return nil }
        var d = Day.date(.now, minutes: p.bedMinute)
        if p.bedMinute < 6 * 60 { d = d.addingTimeInterval(86_400) }
        return d
    }
}

struct LogDrinkView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedDrink.name) private var saved: [SavedDrink]
    @State private var count = 1
    @State private var at = Date.now
    @State private var name = ""
    @State private var mg = 80.0
    @State private var ml = 250.0
    @State private var remember = false
    @State private var flaggedNote = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick pick") {
                    ForEach(Caffeine.catalog) { d in
                        Button { fill(d.name, d.mg, d.servingMl, "Typical value. \(d.note)") } label: {
                            HStack { VStack(alignment: .leading) { Text(d.name); Text("\(Int(d.servingMl)) ml").font(.caption).foregroundStyle(Theme.secondaryText) }
                                Spacer(); Text("\(Int(d.mg)) mg").foregroundStyle(Theme.secondaryText) }
                        }.buttonStyle(.plain)
                    }
                    ForEach(saved) { d in
                        Button { fill(d.name, d.mg, d.servingMl ?? 0, d.mgSource) } label: {
                            HStack { Text(d.name); Spacer(); Text("\(Int(d.mg)) mg").foregroundStyle(Theme.secondaryText) }
                        }.buttonStyle(.plain)
                    }.onDelete { $0.map { saved[$0] }.forEach(context.delete) }
                }
                Section {
                    TextField("Drink", text: $name)
                    HStack { Text("Caffeine per serving (mg)"); Spacer()
                        TextField("mg", value: $mg, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    Stepper("Servings: \(count)", value: $count, in: 1...10)
                    DatePicker("When", selection: $at)
                    Toggle("Save this drink", isOn: $remember)
                } header: { Text("Details") } footer: {
                    Text("Caffeine differs by product and country. Use the number on your can when it differs from the typical value.")
                }
            }
            .navigationTitle("Log a drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || mg < 0) }
            }
        }
    }

    private func fill(_ n: String, _ m: Double, _ v: Double, _ src: String) {
        name = n; mg = m; ml = v; flaggedNote = src
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let src = flaggedNote.isEmpty ? "Entered by you" : flaggedNote
        context.insert(CaffeineRecord(at: at, name: n, servingMl: ml > 0 ? ml : nil, mg: mg, count: count, mgSource: src))
        if remember && !saved.contains(where: { $0.name == n }) {
            context.insert(SavedDrink(name: n, servingMl: ml > 0 ? ml : nil, mg: mg, mgSource: src))
        }
        try? context.save()
        dismiss()
    }
}
