import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .home

    private enum Tab: Hashable {
        case home
        case journey
        case insights
        case profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(Tab.home)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            JourneyView()
                .tag(Tab.journey)
                .tabItem {
                    Label("Journey", systemImage: "map.fill")
                }

            InsightPlaceholderView()
                .tag(Tab.insights)
                .tabItem {
                    Label("Insights", systemImage: "sparkles")
                }

            ProfileView()
                .tag(Tab.profile)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
