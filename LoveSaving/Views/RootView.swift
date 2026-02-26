import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            Group {
                if !session.isSignedIn {
                    AuthView()
                        .accessibilityIdentifier("root.auth")
                } else if !session.isLinked {
                    LinkingView()
                        .accessibilityIdentifier("root.linking")
                } else {
                    MainTabView()
                        .accessibilityIdentifier("root.main")
                }
            }
            .overlay(alignment: .center) {
                if session.isBusy {
                    ProgressView("Loading...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { session.globalErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        session.globalErrorMessage = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    session.globalErrorMessage = nil
                }
            },
            message: {
                Text(session.globalErrorMessage ?? "Unknown error")
            }
        )
    }
}
