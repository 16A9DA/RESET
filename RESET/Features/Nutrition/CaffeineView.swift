import SwiftUI
import SwiftData
import ResetCore

extension CaffeineRecord {
    var dose: CaffeineDose { CaffeineDose(at: at, mg: totalMg) }
}

struct CaffeineCard: View {
    @Query(sort: \CaffeineRecord.at, order: .reverse) private var records: [CaffeineRecord]
    @Query private var profiles: [UserProfile]

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
