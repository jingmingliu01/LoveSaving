import XCTest
@testable import LoveSaving

@MainActor
final class OnboardingFlowControllerTests: XCTestCase {
    func testSignedInSessionWithoutCompletedOnboardingStaysInOnboarding() async {
        let session = AppSession(container: .uiTest(scenario: .linked))
        let controller = OnboardingFlowController()

        await waitUntil("UI test session resolves auth state") {
            session.hasResolvedInitialAuthState
        }

        await controller.refresh(using: session)

        XCTAssertEqual(controller.route, .part1)
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTFail("Timed out waiting for \(description)")
    }
}
