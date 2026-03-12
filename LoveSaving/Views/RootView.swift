import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            Group {
                if !session.isSignedIn {
                    rootContent(identifier: "root.auth") {
                        AuthView()
                    }
                } else if !session.isLinked {
                    rootContent(identifier: "root.linking") {
                        LinkingView()
                    }
                } else {
                    rootContent(identifier: "root.main") {
                        MainTabView()
                    }
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

    @ViewBuilder
    private func rootContent<Content: View>(
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            content()
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityIdentifier(identifier)
                .onAppear {
                    session.updateCrashlyticsRoute(identifier)
                }
        }
    }
}
