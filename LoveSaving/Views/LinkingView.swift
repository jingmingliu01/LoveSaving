import SwiftUI

struct LinkingView: View {
    @EnvironmentObject private var session: AppSession

    @State private var recipient = ""

    var body: some View {
        List {
            Section("Current Account") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.profile?.displayName ?? session.authUser?.displayName ?? "Signed In")
                        .font(.headline)
                    Text(session.profile?.email ?? session.authUser?.email ?? "Unknown email")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button("Sign Out", role: .destructive) {
                    session.signOut()
                }
                .accessibilityIdentifier("linking.signOut")
            }

            Section("Send Invitation") {
                TextField("Recipient UID or Email", text: $recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("linking.recipient")

                Button("Send Invitation") {
                    Task {
                        await session.sendInvite(to: recipient)
                        recipient = ""
                    }
                }
                .disabled(recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("linking.send")
            }

            Section("Incoming Invitations") {
                if session.inboundInvites.isEmpty {
                    Text("No pending invitations")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("linking.incoming.empty")
                }

                ForEach(session.inboundInvites) { invite in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("From: \(invite.fromDisplayName ?? invite.fromUid)")
                            .font(.headline)
                        Text(invite.fromEmail ?? invite.fromUid)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(AppDisplayTime.estDateTime(invite.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Accept") {
                                Task {
                                    await session.respond(invite: invite, accept: true)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reject") {
                                Task {
                                    await session.respond(invite: invite, accept: false)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Link to Start")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign Out", role: .destructive) {
                    session.signOut()
                }
                .accessibilityIdentifier("linking.signOut")
            }
        }
        .task {
            await session.refreshInvites()
        }
    }
}
