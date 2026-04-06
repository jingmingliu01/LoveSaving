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
                if session.incomingInvites.isEmpty {
                    Text("No incoming invitations")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("linking.incoming.empty")
                }

                ForEach(session.incomingInvites) { invite in
                    inviteCard(
                        title: "From: \(invite.fromDisplayName ?? invite.fromUid)",
                        subtitle: invite.fromEmail ?? invite.fromUid,
                        invite: invite,
                        showActions: invite.status == .pending
                    )
                }
            }

            Section("Outgoing Invitations") {
                if session.outgoingInvites.isEmpty {
                    Text("No outgoing invitations")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("linking.outgoing.empty")
                }

                ForEach(session.outgoingInvites) { invite in
                    inviteCard(
                        title: "To: \(invite.toDisplayName ?? invite.toEmail ?? invite.toUid)",
                        subtitle: invite.toEmail == invite.toDisplayName ? nil : invite.toEmail,
                        invite: invite,
                        showActions: false
                    )
                }
            }
        }
        .navigationTitle("Link to Start")
        .task {
            await session.refreshInvites()
        }
    }

    @ViewBuilder
    private func inviteCard(
        title: String,
        subtitle: String?,
        invite: Invite,
        showActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(invite.status.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(invite.status.tint)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Sent \(AppDisplayTime.estDateTime(invite.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let respondedAt = invite.respondedAt {
                Text("Updated \(AppDisplayTime.estDateTime(respondedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let expiresAt = invite.expiresAt, invite.status == .pending {
                Text("Expires \(AppDisplayTime.estDateTime(expiresAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showActions {
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
        }
        .padding(.vertical, 4)
    }
}

private extension InviteStatus {
    var displayTitle: String {
        rawValue.capitalized
    }

    var tint: Color {
        switch self {
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .rejected:
            return .red
        case .expired:
            return .secondary
        }
    }
}
