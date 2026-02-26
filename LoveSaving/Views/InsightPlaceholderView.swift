import SwiftUI

struct InsightPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 52))
                    .foregroundStyle(.pink)
                Text("Insights (Phase 2)")
                    .font(.title3.weight(.semibold))
                Text("LLM-powered insight chat will be implemented in the next phase.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Insights")
        }
    }
}
