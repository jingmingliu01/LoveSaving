import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            JourneyView()
                .tabItem {
                    Label("Journey", systemImage: "map.fill")
                }

            InsightPlaceholderView()
                .tabItem {
                    Label("Insights", systemImage: "sparkles")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
