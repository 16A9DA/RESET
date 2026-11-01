import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Environment(AppRouter.self) private var router

    init() { TabBarStyle.apply() }

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.onboardingDone && Consent.current {
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
            TodayView().tag(AppTab.today).tabItem { Label("Today", image: "ic-house") }
            ActivityView().tag(AppTab.activity).tabItem { Label("Activity", image: "ic-footprints") }
            NutritionView().tag(AppTab.nutrition).tabItem { Label("Nutrition", image: "ic-utensils") }
            InsightsView().tag(AppTab.insights).tabItem { Label("Insights", image: "ic-chart") }
            CoachView().tag(AppTab.coach).tabItem { Label("Coach", image: "ic-message-circle") }
        }
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
