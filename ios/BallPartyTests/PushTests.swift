import XCTest
@testable import BallParty

@MainActor
private final class FakePushSystem: PushSystem {
    var status: PushAuthorization = .notDetermined
    var grants = true
    private(set) var prompts = 0
    private(set) var registrations = 0
    private(set) var unregistrations = 0
    private(set) var badges: [Int] = []

    func authorization() async -> PushAuthorization { status }

    func requestAuthorization() async -> Bool {
        prompts += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func registerForRemoteNotifications() { registrations += 1 }
    func unregisterForRemoteNotifications() { unregistrations += 1 }
    func setBadge(_ count: Int) async { badges.append(count) }
}

private final class FakeDeviceTokenClient: DeviceTokenClient, @unchecked Sendable {
    var offline = false
    private(set) var registered: [(token: String, environment: PushEnvironment)] = []
    private(set) var unregistered: [String] = []

    func register(token: String, environment: PushEnvironment) async throws {
        if offline { throw FakeFriendsClient.Offline() }
        registered.append((token, environment))
    }

    func unregister(token: String) async throws {
        if offline { throw FakeFriendsClient.Offline() }
        unregistered.append(token)
    }
}

@MainActor
final class PushCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var system: FakePushSystem!
    private var client: FakeDeviceTokenClient!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        let suite = "push-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        system = FakePushSystem()
        client = FakeDeviceTokenClient()
    }

    private func makeCoordinator() -> PushCoordinator {
        PushCoordinator(
            system: system, client: client, defaults: defaults, environment: .sandbox, now: { self.clock }
        )
    }

    private let token = Data([0x0a, 0xff, 0x01, 0x7e])

    // MARK: Permission flow

    func testNothingIsAskedBeforeAMeaningfulAction() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        XCTAssertFalse(push.showingPrePrompt)
        XCTAssertEqual(system.prompts, 0)
    }

    func testFirstMeaningfulActionShowsThePrePromptNotTheSystemPrompt() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.meaningfulActionCompleted()
        XCTAssertTrue(push.showingPrePrompt)
        XCTAssertEqual(system.prompts, 0)
    }

    func testAcceptingThePrePromptShowsTheSystemPromptAndRegisters() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.meaningfulActionCompleted()
        await push.acceptPrePrompt()
        XCTAssertFalse(push.showingPrePrompt)
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 1)
    }

    func testRefusingTheSystemPromptDoesNotRegister() async {
        system.grants = false
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.meaningfulActionCompleted()
        await push.acceptPrePrompt()
        XCTAssertEqual(system.registrations, 0)
    }

    func testNotNowSpendsNoSystemPromptAndWaitsBeforeAskingAgain() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.meaningfulActionCompleted()
        push.deferPrePrompt()
        XCTAssertEqual(system.prompts, 0)

        await push.meaningfulActionCompleted()
        XCTAssertFalse(push.showingPrePrompt, "not asked again straight away")

        clock = clock.addingTimeInterval(PushCoordinator.deferral + 1)
        await push.meaningfulActionCompleted()
        XCTAssertTrue(push.showingPrePrompt, "asked again once the wait is over")
    }

    func testNeverAsksOnceTheSystemHasAnAnswer() async {
        for status in [PushAuthorization.authorized, .denied] {
            system.status = status
            let push = makeCoordinator()
            await push.sessionStarted()
            await push.meaningfulActionCompleted()
            XCTAssertFalse(push.showingPrePrompt)
        }
    }

    func testNoPromptWithoutASession() async {
        let push = makeCoordinator()
        await push.meaningfulActionCompleted()
        XCTAssertFalse(push.showingPrePrompt)
    }

    func testTurningOnFromProfileAsksIOSDirectlyAndRegisters() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        let status = await push.enableFromSettings()
        XCTAssertEqual(status, .authorized)
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 1)
        XCTAssertFalse(push.showingPrePrompt)
    }

    func testTurningOnFromProfileClearsAnEarlierNotNow() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.meaningfulActionCompleted()
        push.deferPrePrompt()
        await push.enableFromSettings()
        system.status = .notDetermined
        await push.meaningfulActionCompleted()
        XCTAssertTrue(push.showingPrePrompt, "Not now no longer applies once the player turned it on here")
    }

    func testTurningOnFromProfileAfterARefusalReportsDeniedWithoutRegistering() async {
        system.status = .denied
        let push = makeCoordinator()
        await push.sessionStarted()
        let status = await push.enableFromSettings()
        XCTAssertEqual(status, .denied)
        XCTAssertEqual(system.prompts, 0, "iOS only prompts once")
        XCTAssertEqual(system.registrations, 0)
    }

    func testTurningOnFromProfileWhenAlreadyAllowedRegistersAgain() async {
        system.status = .authorized
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.enableFromSettings()
        XCTAssertEqual(system.prompts, 0)
        XCTAssertEqual(system.registrations, 2, "launch and the button")
    }

    // MARK: Registration

    func testAuthorizedLaunchRegistersWithAPNs() async {
        system.status = .authorized
        await makeCoordinator().sessionStarted()
        XCTAssertEqual(system.registrations, 1)
    }

    func testTokenIsUploadedAsHexWithItsEnvironment() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.didRegister(deviceToken: token)
        XCTAssertEqual(client.registered.map(\.token), ["0aff017e"])
        XCTAssertEqual(client.registered.map(\.environment), [.sandbox])
        XCTAssertEqual(push.storedToken, "0aff017e")
    }

    func testAFailedUploadIsNotFatalAndTheTokenIsKept() async {
        client.offline = true
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.didRegister(deviceToken: token)
        XCTAssertTrue(client.registered.isEmpty)
        XCTAssertEqual(push.storedToken, "0aff017e")
    }

    func testAnAPNsFailureDoesNothing() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        push.didFailToRegister(FakeFriendsClient.Offline())
        XCTAssertTrue(client.registered.isEmpty)
    }

    func testTurningNotificationsOffInSettingsRemovesTheDevice() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.didRegister(deviceToken: token)
        system.status = .denied
        await push.sessionStarted()
        XCTAssertEqual(client.unregistered, ["0aff017e"])
        XCTAssertNil(push.storedToken)
    }

    // MARK: Sign-out

    func testSignOutRemovesTheTokenAndClearsTheBadge() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.didRegister(deviceToken: token)
        await push.willSignOut()
        XCTAssertEqual(client.unregistered, ["0aff017e"])
        XCTAssertNil(push.storedToken)
        XCTAssertEqual(system.unregistrations, 1)
        XCTAssertEqual(system.badges, [0])
    }

    func testSignOutWithoutATokenStillCompletes() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.willSignOut()
        XCTAssertTrue(client.unregistered.isEmpty)
    }

    func testAFailedRemovalKeepsTheTokenForNextTime() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.didRegister(deviceToken: token)
        client.offline = true
        await push.willSignOut()
        XCTAssertEqual(push.storedToken, "0aff017e")
    }

    func testNoBadgeOrTokenUploadAfterSignOut() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.willSignOut()
        await push.setBadge(3)
        await push.didRegister(deviceToken: token)
        XCTAssertEqual(system.badges, [0])
        XCTAssertTrue(client.registered.isEmpty)
    }

    func testBadgeFollowsTheUnreadCountWhileSignedIn() async {
        let push = makeCoordinator()
        await push.sessionStarted()
        await push.setBadge(4)
        XCTAssertEqual(system.badges, [4])
    }

    // MARK: Taps

    func testATapWaitsForTheShellAndIsConsumedOnce() throws {
        let push = makeCoordinator()
        let payload = try XCTUnwrap(PushPayload(userInfo: ["kind": "friend_request", "item_key": "n:1"]))
        push.didTap(payload)
        XCTAssertEqual(push.consumeRoute(), PushRoute(kind: .item(.friendRequest), itemKey: "n:1"))
        XCTAssertNil(push.consumeRoute())
    }

    func testSigningOutDropsAPendingTap() async throws {
        let push = makeCoordinator()
        await push.sessionStarted()
        push.didTap(try XCTUnwrap(PushPayload(userInfo: ["kind": "room_invite"])))
        await push.willSignOut()
        XCTAssertNil(push.pendingRoute)
    }
}

final class PushPayloadTests: XCTestCase {
    private let post = UUID()

    func testEveryInboxKindIsRecognised() {
        XCTAssertEqual(PushPayload(userInfo: ["kind": "friend_request", "item_key": "n:1"])?.kind, .item(.friendRequest))
        XCTAssertEqual(PushPayload(userInfo: ["kind": "take_reply", "item_key": "n:2"])?.kind, .item(.takeReply))
        XCTAssertEqual(PushPayload(userInfo: ["kind": "room_invite", "item_key": "i:3"])?.kind, .item(.roomInvite))
    }

    func testTheItemKeyIsKept() {
        XCTAssertEqual(PushPayload(userInfo: ["kind": "take_reply", "item_key": "n:2"])?.itemKey, "n:2")
    }

    func testANewPromptCarriesThePost() {
        let payload = PushPayload(userInfo: ["kind": "new_prompt", "post_id": post.uuidString])
        XCTAssertEqual(payload?.kind, .newPrompt)
        XCTAssertEqual(payload?.postId, post)
        XCTAssertNil(payload?.itemKey)
    }

    func testUnknownOrMissingKindIsIgnored() {
        XCTAssertNil(PushPayload(userInfo: ["kind": "something_new"]))
        XCTAssertNil(PushPayload(userInfo: [:]))
    }

    func testAnItemPushWithoutAKeyStillParses() {
        XCTAssertNotNil(PushPayload(userInfo: ["kind": "room_invite"]))
        XCTAssertNil(PushPayload(userInfo: ["kind": "room_invite"])?.itemKey)
    }
}
