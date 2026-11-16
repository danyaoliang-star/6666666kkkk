import Foundation

enum ClientError: LocalizedError {
    case invalidServer, invalidResponse, expired, server(Int, String), staleContext, oversizedFile
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "请输入有效的 HTTPS 服务根地址。开发版可使用局域网 HTTP 地址。"
        case .invalidResponse: return "服务返回了无法识别的数据，请确认地址指向家和后端。"
        case .expired: return "登录已过期，请重新登录。"
        case .server(_, let message): return message
        case .staleContext: return "当前账号或成员已变化，请重新操作。"
        case .oversizedFile: return "请选择不超过 10 MB 的 JPG、PNG 或 PDF 文件。"
        }
    }
}
enum ServerAddress {
    static func parse(_ text: String, allowLocalHTTP: Bool) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        if url.scheme == "https" { return url }
        guard allowLocalHTTP, url.scheme == "http" else { return nil }
        let raw = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = raw.compactMap { Int($0) }
        let localIP = raw.count == 4 && octets.count == 4 && octets.allSatisfy { (0...255).contains($0) } &&
            (octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) ||
             (octets[0] == 172 && (16...31).contains(octets[1])))
        return host == "localhost" || host.hasSuffix(".local") || localIP ? url : nil
    }
}

@MainActor
final class APIClient {
    let server: URL
    private let session: URLSession
    private var epoch = UUID()
    var onUnauthorized: (() -> Void)?
    init(server: URL, session: URLSession? = nil) {
        self.server = server
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 120
        self.session = session ?? URLSession(configuration: configuration, delegate: OriginRedirectPolicy(server: server), delegateQueue: nil)
    }
    func invalidate() { epoch = UUID(); session.invalidateAndCancel() }
    func url(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: "/api/v1" + path, relativeTo: server)?.absoluteURL,
              url.host == server.host, url.scheme == server.scheme, url.port == server.port else { throw ClientError.invalidResponse }
        return url
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: try url(path))
        request.httpMethod = method
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let bytes = try await perform(request)
        do { return try Self.decoder().decode(T.self, from: bytes) }
        catch { throw ClientError.invalidResponse }
    }
    func send(_ path: String, method: String, body: [String: Any]? = nil) async throws {
        let _: JSONValue = try await request(path, method: method, body: body)
    }
    func bytes(_ path: String) async throws -> Data { try await perform(URLRequest(url: try url(path))) }
    func upload(memberID: Int, data: Data, filename: String, mime: String) async throws -> MedicalReport {
        guard data.count <= 10 * 1024 * 1024 else { throw ClientError.oversizedFile }
        let boundary = "jiahe-" + UUID().uuidString
        let safeName = filename.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\"", with: "_")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: try url("/members/\(memberID)/reports"))
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try Self.decoder().decode(MedicalReport.self, from: await perform(request))
    }
    private func perform(_ request: URLRequest) async throws -> Data {
        let captured = epoch
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard captured == epoch else { throw ClientError.staleContext }
        guard let response = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if response.statusCode == 401 { onUnauthorized?(); throw ClientError.expired }
        guard (200...299).contains(response.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = object?["detail"] as? String ?? "提交内容有误或服务暂时不可用，请检查后重试。"
            throw ClientError.server(response.statusCode, message)
        }
        return data
    }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }
}

private final class OriginRedirectPolicy: NSObject, URLSessionTaskDelegate {
    let server: URL
    init(server: URL) { self.server = server }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == server.scheme, url.host == server.host,
              (url.port ?? (url.scheme == "https" ? 443 : 80)) == (server.port ?? (server.scheme == "https" ? 443 : 80)) else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}
