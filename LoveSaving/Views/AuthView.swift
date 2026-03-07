import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: AppSession

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var mode: Mode = .signIn

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("LoveSaving")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("auth.title")

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .accessibilityIdentifier("auth.email")

                SecureField("Password", text: $password)
                    .accessibilityIdentifier("auth.password")

                if mode == .signUp {
                    TextField("Display Name", text: $displayName)
                        .accessibilityIdentifier("auth.displayName")
                }
            }
            .textFieldStyle(.roundedBorder)

            Button(mode.rawValue) {
                Task {
                    switch mode {
                    case .signIn:
                        await session.signIn(email: email, password: password)
                    case .signUp:
                        await session.signUp(email: email, password: password, displayName: displayName)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || (mode == .signUp && displayName.isEmpty))
            .accessibilityIdentifier("auth.submit")
        }
        .padding()
    }
}
