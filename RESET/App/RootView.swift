import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.onboardingDone {
                    TabView {
                        ActivityView().tabItem { Label("Activity", systemImage: "figure.walk") }
                        NutritionView().tabItem { Label("Nutrition", systemImage: "fork.knife") }
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
