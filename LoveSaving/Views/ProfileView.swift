import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession

    @State private var newDisplayName = ""
    @State private var newPassword = ""
    @State private var isShowingCrashlyticsTestAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.pink)
                        VStack(alignment: .leading) {
                            Text(session.profile?.displayName ?? "Unknown")
                                .font(.headline)
                            Text(session.profile?.email ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("New Display Name", text: $newDisplayName)
                        .accessibilityIdentifier("profile.displayName.input")

                    Button("Change Display Name") {
                        Task {
                            await session.changeDisplayName(newDisplayName)
                            newDisplayName = ""
                        }
                    }
                    .disabled(newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("profile.displayName.change")
                }

                Section("Security") {
                    SecureField("New Password", text: $newPassword)
                    Button("Change Password") {
                        Task {
                            await session.changePassword(newPassword)
                            newPassword = ""
                        }
                    }
                    .disabled(newPassword.count < 6)
                }

                Section("Group") {
                    if let group = session.group {
                        Text("Group: \(group.groupName)")
                        Text("Members: \(group.memberIds.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Unlink", role: .destructive) {
                        Task {
                            await session.softUnlinkCurrentGroup()
                        }
                    }
                    .accessibilityIdentifier("profile.unlink")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        session.signOut()
                    }
                    .accessibilityIdentifier("profile.signOut")
                }

#if DEBUG
                Section {
                    Button("Crashlytics Test Crash", role: .destructive) {
                        isShowingCrashlyticsTestAlert = true
                    }
                    .accessibilityIdentifier("profile.crashlytics.testCrash")
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Use this only to verify Crashlytics. The app will terminate immediately.")
                }
#endif
            }
            .navigationTitle("Profile")
            .alert("Trigger test crash?", isPresented: $isShowingCrashlyticsTestAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Crash App", role: .destructive) {
                    fatalError("Crashlytics test crash triggered from ProfileView")
                }
            } message: {
                Text("This is a manual Crashlytics verification action for debug builds.")
            }
        }
    }
}
