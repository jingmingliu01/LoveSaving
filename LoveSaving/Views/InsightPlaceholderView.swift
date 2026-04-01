import SwiftUI

struct InsightPlaceholderView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                content
            }
            .padding()
            .navigationTitle("Insights")
            .task {
                session.refreshAIInsightsAvailabilityIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.aiInsightsAvailability {
        case .checking:
            ProgressView()
            Text(session.aiInsightsAvailability.title)
                .font(.title3.weight(.semibold))
            Text(session.aiInsightsAvailability.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .unavailable:
            Image(systemName: "sparkles.slash")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(session.aiInsightsAvailability.title)
                .font(.title3.weight(.semibold))
            Text(session.aiInsightsAvailability.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                session.refreshAIInsightsAvailabilityIfNeeded()
            }
            .buttonStyle(.borderedProminent)
        case .available:
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 52))
                .foregroundStyle(.pink)
            Text(session.aiInsightsAvailability.title)
                .font(.title3.weight(.semibold))
            Text(session.aiInsightsAvailability.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
