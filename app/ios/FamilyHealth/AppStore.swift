import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var members: [Member] = []
    @Published private(set) var selectedID: Int?
    @Published private(set) var catalog: [String: Indicator] = [:]
    @Published private(set) var generation = UUID()
    @Published var error: String?
    @Published var busy = false
    private(set) var api: APIClient?
    private let clientFactory: @MainActor (URL) -> APIClient
    init(clientFactory: @escaping @MainActor (URL) -> APIClient = { APIClient(server: $0) }) { self.clientFactory = clientFactory }
    var member: Member? { members.first { $0.id == selectedID } }
    var savedServer: String { UserDefaults.standard.string(forKey: "healthServerURL") ?? (Bundle.main.object(forInfoDictionaryKey: "HealthAPIBaseURL") as? String ?? "") }
    func requireAPI() throws -> APIClient { guard let api = api else { throw ClientError.expired }; return api }
    func isCurrent(_ context: UUID) -> Bool { generation == context && account != nil }
    func select(_ member: Member) { guard selectedID != member.id else { return }; selectedID = member.id; generation = UUID() }
    func login(server: String, username: String, password: String) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        #if DEBUG
        let allowHTTP = true
        #else
        let allowHTTP = false
        #endif
        guard let url = ServerAddress.parse(server, allowLocalHTTP: allowHTTP) else { error = ClientError.invalidServer.localizedDescription; return }
        let client = clientFactory(url)
        do {
            let user: Account = try await client.request("/sessions", method: "POST", body: ["username": username, "password": password])
            let people: [Member] = try await client.request("/members")
            let indicators: [String: Indicator] = try await client.request("/catalog")
            api?.invalidate(); api = client
            client.onUnauthorized = { [weak self] in self?.clearSession(message: ClientError.expired.localizedDescription) }
            account = user; members = people; catalog = indicators
            selectedID = people.first(where: { $0.relation == "本人" })?.id ?? people.first?.id
            generation = UUID()
            UserDefaults.standard.set(url.absoluteString, forKey: "healthServerURL")
        } catch { client.invalidate(); self.error = error.localizedDescription }
    }
    func refreshMembers() async {
        guard let api = api else { return }; let context = generation
        do {
            let people: [Member] = try await api.request("/members")
            guard isCurrent(context) else { return }
            let previousAccess = members.map { "\($0.id):" + $0.scopes.sorted().joined(separator: ",") }.sorted()
            members = people
            if !people.contains(where: { $0.id == selectedID }) { selectedID = people.first?.id; generation = UUID() }
            else if previousAccess != people.map({ "\($0.id):" + $0.scopes.sorted().joined(separator: ",") }).sorted() { generation = UUID() }
        } catch { if isCurrent(context) { self.error = error.localizedDescription } }
    }
    func logout() async {
        guard !busy else { return }; busy = true
        do { try await api?.send("/sessions", method: "DELETE"); clearSession() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
    func clearSession(message: String? = nil) {
        api?.invalidate(); api = nil; account = nil; members = []; selectedID = nil; catalog = [:]
        generation = UUID(); error = message
    }
}
