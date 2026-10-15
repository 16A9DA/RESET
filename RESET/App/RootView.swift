import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.onboardingDone {
                    NavigationStack {
                        List { NavigationLink("Work and University") { TimeTrackingView() } }
                            .navigationTitle("RE:SET AI")
                    }
                } else {
                    OnboardingView(profile: profile)
                }
            } else {
                ProgressView().task { context.insert(UserProfile()) }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
    }
}
