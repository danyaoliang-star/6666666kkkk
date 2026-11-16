import XCTest
import SwiftUI
@testable import FamilyHealth

@MainActor
final class NativeClientTests: XCTestCase {
    private func fixture(_ key: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-contract", withExtension: "json"))
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: XCTUnwrap(dictionary[key]))
    }
    func testRealBackendResponsesDecodeIntoNativeModels() throws {
        let decoder = APIClient.decoder()
        let account = try decoder.decode(Account.self, from: fixture("account"))
        XCTAssertEqual(account.username, "demo")
        let member = try decoder.decode(Member.self, from: fixture("member"))
        XCTAssertTrue(member.allows("read"))
        XCTAssertEqual(member.relation, "本人")
        let report = try decoder.decode(MedicalReport.self, from: fixture("report"))
        XCTAssertEqual(report.mime, "image/png")
        let observations = try decoder.decode([Observation].self, from: fixture("observations"))
        XCTAssertEqual(observations.first?.value, 3.8)
        let care = try decoder.decode(CareOverview.self, from: fixture("care"))
        XCTAssertEqual(care.goals.first?.latest?.value, 3.8)
        let plans = try decoder.decode([DailyPlan].self, from: fixture("plans"))
        XCTAssertEqual(plans.first?.logs.first?.state, "完成")
        XCTAssertFalse(try decoder.decode([Conversation].self, from: fixture("conversations")).isEmpty)
        let messages = try decoder.decode([ChatMessage].self, from: fixture("messages"))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(try decoder.decode(ChatReply.self, from: fixture("reply")).messages.count, 2)
        XCTAssertEqual(try decoder.decode([AccessGrant].self, from: fixture("grants")).first?.scope, "read")
        let health = try decoder.decode(HealthConnection.self, from: fixture("health"))
        XCTAssertEqual(health.records.first?.value, 1128)
        XCTAssertTrue(health.scopes.contains(.steps))
    }
    func testDynamicEvidenceKeepsBackendKeys() throws {
        let decoder = APIClient.decoder()
        let review = try decoder.decode(JSONValue.self, from: fixture("confirmed_review"))
        XCTAssertFalse(review["report_date"].string.isEmpty)
        XCTAssertEqual(review["confirmation"]["records"].array.first?["value"].optionalNumber, 3.8)
        let weekly = try decoder.decode(JSONValue.self, from: fixture("weekly"))
        XCTAssertEqual(weekly["totals"]["done"].int, 1)
        let advice = try decoder.decode(JSONValue.self, from: fixture("lifestyle"))
        XCTAssertFalse(advice["actions"].array.isEmpty)
    }
    func testServerAddressRejectsCredentialsForeignPathsAndPublicHTTP() {
        XCTAssertNotNil(ServerAddress.parse("https://example.com", allowLocalHTTP: false))
        XCTAssertNotNil(ServerAddress.parse("http://192.168.1.5:8000", allowLocalHTTP: true))
        for text in ["https://user:password@example.com", "https://example.com/other", "https://example.com?key=secret", "http://example.com", "http://192.168.1.999", "http://192.bad.168.1.2", "file:///tmp/app"] {
            XCTAssertNil(ServerAddress.parse(text, allowLocalHTTP: true), text)
        }
        XCTAssertNil(ServerAddress.parse("http://192.168.1.5:8000", allowLocalHTTP: false))
    }
    func testEmptyReadingIsDistinctFromZero() throws {
        let decoder = APIClient.decoder()
        let data = Data("{\"code\":\"steps\",\"day\":\"2026-11-16\",\"value\":0}".utf8)
        XCTAssertEqual(try decoder.decode(HealthReading.self, from: data).value, 0)
        XCTAssertEqual(displayNumber(nil), "—")
        XCTAssertNotEqual(displayNumber(0), "—")
    }
    func testUnauthorizedResponseIsPropagatedAndClearsSession() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NativeURLProtocol.self]
        NativeURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/members")
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{\"detail\":\"请先登录\"}".utf8))
        }
        defer { NativeURLProtocol.handler = nil }
        let api = APIClient(server: URL(string: "https://example.com")!, session: URLSession(configuration: config))
        var expired = false
        api.onUnauthorized = { expired = true }
        do { let _: [Member] = try await api.request("/members"); XCTFail("Expected authentication failure") }
        catch { XCTAssertTrue(expired); XCTAssertEqual(error.localizedDescription, ClientError.expired.localizedDescription) }
        api.invalidate()
    }

    /// These images are rendered by the actual SwiftUI screens inside an iOS simulator.
    /// Network responses are synthetic fixtures; no server or health authorization is contacted.
    func testNativeScreenPreviews() async throws {
        let names = ["account", "member", "catalog", "report", "observations", "care", "health", "plans", "conversations", "messages", "memories"]
        var data: [String: Data] = [:]
        for name in names { data[name] = try fixture(name) }
        let memberValue = try XCTUnwrap(JSONSerialization.jsonObject(with: data["member"]!) as? [String: Any])
        let memberID = try XCTUnwrap(memberValue["id"] as? Int)
        let members = try JSONSerialization.data(withJSONObject: [memberValue])
        let reports = try JSONSerialization.data(withJSONObject: [JSONSerialization.jsonObject(with: data["report"]!)])
        let model = Data("{\"configured\":false,\"model\":null,\"memory_destination\":null,\"message\":\"合成预览资料\"}".utf8)
        let root = "/api/v1/members/\(memberID)"
        let replies: [String: Data] = [
            "/api/v1/sessions": data["account"]!, "/api/v1/members": members, "/api/v1/catalog": data["catalog"]!,
            "/api/v1/assistant/status": model, root + "/apple-health": data["health"]!,
            root + "/observations": data["observations"]!, root + "/care": data["care"]!,
            root + "/reports": reports, root + "/plans": data["plans"]!,
            root + "/assistant/conversations": data["conversations"]!, root + "/assistant/messages": data["messages"]!,
            root + "/memories": data["memories"]!
        ]
        NativeURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "native-preview.invalid")
            let body = replies[request.url?.path ?? ""]
            let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, body ?? Data("{\"detail\":\"No preview fixture\"}".utf8))
        }
        let previousServer = UserDefaults.standard.object(forKey: "healthServerURL")
        UserDefaults.standard.removeObject(forKey: "healthServerURL")
        defer {
            NativeURLProtocol.handler = nil
            if let previousServer = previousServer { UserDefaults.standard.set(previousServer, forKey: "healthServerURL") }
            else { UserDefaults.standard.removeObject(forKey: "healthServerURL") }
        }
        let store = AppStore(clientFactory: { url in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NativeURLProtocol.self]
            return APIClient(server: url, session: URLSession(configuration: configuration))
        })
        try await capture(LoginView().environmentObject(store), name: "01-native-login")
        await store.login(server: "https://native-preview.invalid", username: "demo", password: "synthetic-preview-password")
        let member = try XCTUnwrap(store.member)
        XCTAssertNotNil(store.account)
        for (tab, name) in [(0, "02-native-chat"), (1, "03-native-health"), (2, "04-native-plans"), (3, "05-native-account")] {
            try await capture(MainTabs(initialTab: tab).environmentObject(store), name: name)
        }
        try await capture(NavigationStack { HealthDeviceView(member: member) }.environmentObject(store), name: "06-native-health-permissions")
        try await capture(NavigationStack { ReportsView(member: member) }.environmentObject(store), name: "07-native-reports")
        try await capture(NavigationStack { CareView(member: member) }.environmentObject(store), name: "08-native-care")
        store.clearSession()
    }
    private func capture<Content: View>(_ content: Content, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: content.preferredColorScheme(.light).tint(AppTheme.accent))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKey?.makeKeyAndVisible() }
        // All data requests are in-memory; allow SwiftUI tasks and layout to commit before capture.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        var drawn = false
        let image = renderer.image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        XCTAssertTrue(drawn, "Native hierarchy failed to render: \(name)")
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000, "Unexpectedly empty native snapshot: \(name)")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class NativeURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, bytes) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
