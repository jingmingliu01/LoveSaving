import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession

    @State private var newDisplayName = ""
    @State private var newPassword = ""

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
            }
            .navigationTitle("Profile")
        }
    }
}
