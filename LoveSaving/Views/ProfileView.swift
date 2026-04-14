import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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

                Section("Notifications") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(session.notificationSettings.authorizationStatus.displayTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(notificationStatusTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(notificationStatusTint.opacity(0.12), in: Capsule())
                    }

                    switch session.notificationSettings.authorizationStatus {
                    case .notDetermined:
                        Text("Enable notifications to get daily reminders to log meaningful moments.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Enable Notifications") {
                            Task {
                                await session.requestNotifications()
                            }
                        }
                    case .denied:
                        Text("Notifications are turned off in iPhone Settings. Open Settings to allow alerts for LoveSaving.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Open iPhone Settings") {
                            #if canImport(UIKit)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                            #endif
                        }
                    case .authorized:
                        Toggle(
                            "Daily Reflection Reminder",
                            isOn: Binding(
                                get: { session.notificationSettings.dailyReminderEnabled },
                                set: { newValue in
                                    Task {
                                        await session.setDailyReminderEnabled(newValue)
                                    }
                                }
                            )
                        )

                        DatePicker(
                            "Reminder Time",
                            selection: Binding(
                                get: { reminderDate },
                                set: { newValue in
                                    Task {
                                        await session.setDailyReminderTime(newValue)
                                    }
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .disabled(!session.notificationSettings.dailyReminderEnabled)

                        Text("Get a daily reminder to reflect and add a new journey moment.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            .refreshable {
                await session.refreshProfile()
                await session.refreshNotificationSettings()
            }
            .task {
                await session.refreshNotificationSettings()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await session.refreshNotificationSettings()
                }
            }
            .safeAreaInset(edge: .top) {
                RefreshStatusView(state: session.refreshState(for: .profile))
            }
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

    private var notificationStatusTint: Color {
        switch session.notificationSettings.authorizationStatus {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        }
    }

    private var reminderDate: Date {
        let now = Date()
        let calendar = Calendar.current
        let baseComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let reminderComponents = DateComponents(
            hour: session.notificationSettings.reminderHour,
            minute: session.notificationSettings.reminderMinute
        )
        return calendar.date(from: DateComponents(
            year: baseComponents.year,
            month: baseComponents.month,
            day: baseComponents.day,
            hour: reminderComponents.hour,
            minute: reminderComponents.minute
        )) ?? now
    }
}
