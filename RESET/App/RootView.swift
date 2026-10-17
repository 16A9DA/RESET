import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.onboardingDone {
                    tabs
                } else {
                    OnboardingView(profile: profile)
                }
            } else {
                ProgressView().task { context.insert(UserProfile()) }
            }
        }
        .background(GlassBackdrop())
        .tint(Theme.accent)
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            TodayView().tag(AppTab.today).tabItem { Label("Today", systemImage: "sun.max") }
            ActivityView().tag(AppTab.activity).tabItem { Label("Activity", systemImage: "figure.walk") }
            NutritionView().tag(AppTab.nutrition).tabItem { Label("Nutrition", systemImage: "fork.knife") }
            InsightsView().tag(AppTab.insights).tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            CoachView().tag(AppTab.coach).tabItem { Label("Coach", systemImage: "sparkles") }
        }
    }
}
