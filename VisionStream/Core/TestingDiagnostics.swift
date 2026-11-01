import Foundation

/// Explicit testing exports can contain signed links. Credential headers and
/// URL user-info are never copied into this structure.
public struct TestingDiagnosticDetails: Codable, Sendable {
    public var resourceID: UUID?
    public var url: String?
    public var role: String?
    public var method: String?
    public var requestHeaders: [String: String]?
    public var responseHeaders: [String: String]?
    public var requestHeaderNames: [String]?
    public var responseHeaderNames: [String]?
    public var httpStatus: Int?
    public var networkProtocol: String?
    public var localAddress: String?
    public var remoteAddress: String?
    public var flags: [String: Bool]?
    public var timings: [String: Double]?
    public var cookieMetadata: [TestingCookieMetadata]?
    public var browser: TestingBrowserState?

    public init() {}

    public static func link(_ value: String) -> String? {
        guard value.utf8.count <= 16_384, var parts = URLComponents(string: value),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil else { return nil }
        parts.user = nil; parts.password = nil
        let credentials: Set<String> = ["password", "passwd", "pwd", "authorization", "cookie", "client_secret"]
        if let items = parts.queryItems, items.contains(where: { credentials.contains($0.name.lowercased()) }) {
            parts.queryItems = items.map { credentials.contains($0.name.lowercased()) ? URLQueryItem(name: $0.name, value: "REDACTED") : $0 }
        }
        return parts.url?.absoluteString
    }

    public static func headers(_ source: [String: String], response: Bool) -> [String: String] {
        let request: Set<String> = ["user-agent", "accept", "accept-encoding", "accept-language", "range", "if-match", "if-none-match", "if-modified-since", "if-unmodified-since", "if-range", "origin", "referer", "cache-control", "pragma"]
        let reply: Set<String> = ["content-type", "content-length", "content-range", "content-encoding", "accept-ranges", "cache-control", "date", "age", "expires", "vary", "etag", "last-modified", "retry-after", "server", "via", "location", "access-control-allow-origin", "access-control-allow-credentials"]
        var result: [String: String] = [:]
        for (key, value) in source where (response ? reply : request).contains(key.lowercased()) {
            guard value.utf8.count <= 16_384, value.rangeOfCharacter(from: .controlCharacters) == nil else { continue }
            if ["location", "origin", "referer"].contains(key.lowercased()), value.contains("://") {
                result[key.lowercased()] = link(value)
            } else if key.lowercased()=="location", let resolved=URL(string:value,relativeTo:URL(string:"https://testing.invalid/")), let safe=link(resolved.absoluteURL.absoluteString) {
                if value.hasPrefix("//") { result["location"]=safe }
                else if let parts=URLComponents(string:safe) { result["location"]=parts.percentEncodedPath+(parts.percentEncodedQuery.map { "?"+$0 } ?? "")+(parts.percentEncodedFragment.map { "#"+$0 } ?? "") }
            } else { result[key.lowercased()] = String(value.prefix(1024)) }
        }
        return result
    }

    public static func headerNames(_ names: [String]) -> [String] {
        Array(Set(names.filter { $0.range(of: #"^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,128}$"#, options: .regularExpression) != nil }.map { $0.lowercased() })).sorted().prefix(64).map { $0 }
    }

    public func sanitized() -> Self {
        var value = self
        value.url = url.flatMap(Self.link)
        value.role = ["page", "media", "constructed-request", "response", "network-transaction", "browser-readiness", "cookie-snapshot", "paused-native-probe"].contains(role ?? "") ? role : nil
        value.method = ["GET", "HEAD", "POST"].contains(method ?? "") ? method : nil
        value.requestHeaders = requestHeaders.map { Self.headers($0, response: false) }
        value.responseHeaders = responseHeaders.map { Self.headers($0, response: true) }
        value.requestHeaderNames = requestHeaderNames.map(Self.headerNames)
        value.responseHeaderNames = responseHeaderNames.map(Self.headerNames)
        value.httpStatus = httpStatus.flatMap { (100...599).contains($0) ? $0 : nil }
        value.networkProtocol = networkProtocol.flatMap { $0.utf8.count <= 32 && $0.rangeOfCharacter(from: .controlCharacters) == nil ? $0:nil }
        func address(_ text: String?) -> String? { text.flatMap { $0.range(of: #"^[0-9A-Fa-f:.%]{1,128}$"#,options:.regularExpression) != nil ? $0:nil } }
        value.localAddress=address(localAddress); value.remoteAddress=address(remoteAddress)
        value.flags=flags.map { $0.filter { ["proxyConnection","reusedConnection","cellular","expensive","constrained"].contains($0.key) } }
        value.timings = timings.map { Dictionary(uniqueKeysWithValues: $0.filter { $0.key.utf8.count < 64 && $0.key.range(of: #"^[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil && $0.value.isFinite }.sorted { $0.key < $1.key }.prefix(32).map { ($0.key, $0.value) }) }
        value.cookieMetadata = cookieMetadata.map { Array($0.prefix(64)).map { $0.sanitized() } }
        value.browser = browser?.sanitized()
        return value
    }

    public static func request(_ request: URLRequest, role: String = "constructed-request") -> Self {
        var value = Self(); value.url = request.url?.absoluteString; value.role = role; value.method = request.httpMethod ?? "GET"
        let headers = request.allHTTPHeaderFields ?? [:]
        value.requestHeaders = headers; value.requestHeaderNames = Array(headers.keys)
        return value.sanitized()
    }

    public static func response(_ response: HTTPURLResponse) -> Self {
        var value = Self(); value.url = response.url?.absoluteString; value.role = "response"; value.httpStatus = response.statusCode
        let headers = Dictionary(response.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) }, uniquingKeysWith: { _, new in new })
        value.responseHeaders = headers; value.responseHeaderNames = Array(headers.keys)
        return value.sanitized()
    }

    public static func transaction(_ transaction: URLSessionTaskTransactionMetrics) -> Self {
        var value = request(transaction.request, role: "network-transaction")
        if let response = transaction.response as? HTTPURLResponse {
            let reply=Self.response(response); value.httpStatus=reply.httpStatus; value.responseHeaders=reply.responseHeaders; value.responseHeaderNames=reply.responseHeaderNames
        }
        value.networkProtocol=transaction.networkProtocolName
        value.localAddress=transaction.localAddress; value.remoteAddress=transaction.remoteAddress
        value.flags=["proxyConnection":transaction.isProxyConnection,"reusedConnection":transaction.isReusedConnection,"cellular":transaction.isCellular,"expensive":transaction.isExpensive,"constrained":transaction.isConstrained]
        var timings:[String:Double]=[:]
        func interval(_ key:String,_ start:Date?,_ end:Date?) { if let start,let end { timings[key]=max(0,end.timeIntervalSince(start)*1000) } }
        interval("dnsMs",transaction.domainLookupStartDate,transaction.domainLookupEndDate)
        interval("connectMs",transaction.connectStartDate,transaction.connectEndDate)
        interval("tlsMs",transaction.secureConnectionStartDate,transaction.secureConnectionEndDate)
        interval("requestMs",transaction.requestStartDate,transaction.requestEndDate)
        interval("timeToFirstByteMs",transaction.requestEndDate,transaction.responseStartDate)
        interval("responseMs",transaction.responseStartDate,transaction.responseEndDate)
        interval("totalMs",transaction.fetchStartDate,transaction.responseEndDate)
        if let version=transaction.negotiatedTLSProtocolVersion { timings["tlsProtocolVersion"]=Double(version.rawValue) }
        value.timings=timings; return value.sanitized()
    }
}

public struct TestingCookieMetadata: Codable, Sendable {
    public let name: String
    public let domain: String
    public let path: String
    public let secure: Bool
    public let httpOnly: Bool
    public let expires: Date?
    public init(_ cookie: HTTPCookie) {
        name = String(cookie.name.prefix(128)); domain = String(cookie.domain.prefix(253)); path = String(cookie.path.prefix(1024))
        secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly; expires = cookie.expiresDate
    }
    func sanitized() -> Self { Self(name: String(name.prefix(128)), domain: String(domain.prefix(253)), path: String(path.prefix(1024)), secure: secure, httpOnly: httpOnly, expires: expires) }
    private init(name: String, domain: String, path: String, secure: Bool, httpOnly: Bool, expires: Date?) {
        self.name=name; self.domain=domain; self.path=path; self.secure=secure; self.httpOnly=httpOnly; self.expires=expires
    }
}

public struct TestingBrowserState: Codable, Sendable {
    public var url: String?
    public var readyState: String
    public var visibility: String
    public var userAgent: String
    public var observedAtMs: Double
    public var navigation: [String: Double]
    public var videos: [Video]
    public var scriptErrors: [ScriptError]
    public var resources: [ResourceTiming]?
    public struct Video: Codable, Sendable {
        public var videoID: String
        public var source: String?
        public var attributeSource: String?
        public var readyState: Int
        public var networkState: Int
        public var errorCode: Int
        public var paused: Bool
        public var muted: Bool
        public var visible: Bool
        public var adMarked: Bool
        public var width: Int
        public var height: Int
        public var currentTime: Double
        public var duration: Double?
        public var frames: Int?
        public var droppedFrames: Int?
        public var buffered: [[Double]]
        public var seekable: [[Double]]
        public var events: [Event]
    }
    public struct Event: Codable, Sendable { public var name: String; public var timeMs: Double }
    public struct ScriptError: Codable, Sendable { public var name: String; public var source: String?; public var line: Int; public var column: Int; public var timeMs: Double }
    public struct ResourceTiming: Codable, Sendable {
        public var url:String?; public var initiator:String; public var nextHop:String
        public var startMs:Double; public var durationMs:Double; public var requestStartMs:Double; public var responseStartMs:Double; public var responseEndMs:Double
        public var transferBytes:Double; public var encodedBytes:Double; public var decodedBytes:Double
    }
    public func sanitized() -> Self {
        var value=self; value.url=url.flatMap(TestingDiagnosticDetails.link)
        value.readyState=["loading","interactive","complete"].contains(readyState) ? readyState : "unknown"
        value.visibility=["visible","hidden","prerender"].contains(visibility) ? visibility : "unknown"
        value.userAgent=String(userAgent.prefix(1024)); value.observedAtMs=observedAtMs.isFinite ? observedAtMs : 0
        value.navigation=navigation.filter { $0.key.range(of: #"^[A-Za-z][A-Za-z0-9]{0,63}$"#,options:.regularExpression) != nil && $0.value.isFinite }
        if value.navigation.count > 32 { value.navigation=Dictionary(uniqueKeysWithValues:value.navigation.sorted { $0.key < $1.key }.prefix(32).map { ($0.key,$0.value) }) }
        let names: Set<String>=["loadedmetadata","loadeddata","play","playing","emptied","durationchange","error","waiting","stalled","pause","ended","seeking","seeked","canplay","canplaythrough"]
        value.videos=Array(videos.prefix(16)).map { video in
            var v=video; v.videoID=String(v.videoID.prefix(128)); v.source=v.source.flatMap(TestingDiagnosticDetails.link); v.attributeSource=v.attributeSource.flatMap(TestingDiagnosticDetails.link)
            v.currentTime=v.currentTime.isFinite ? v.currentTime : 0; v.duration=v.duration.flatMap { $0.isFinite ? $0:nil }
            v.buffered=Array(v.buffered.prefix(8)).filter { $0.count==2 && $0.allSatisfy(\.isFinite) }; v.seekable=Array(v.seekable.prefix(8)).filter { $0.count==2 && $0.allSatisfy(\.isFinite) }
            v.events=Array(v.events.filter { names.contains($0.name) && $0.timeMs.isFinite }.suffix(32)); return v
        }
        value.scriptErrors=Array(scriptErrors.suffix(16)).map { error in
            var e=error; e.source=e.source.flatMap(TestingDiagnosticDetails.link)
            e.name=["Error","TypeError","ReferenceError","SyntaxError","RangeError","URIError","EvalError","resource-error"].contains(e.name) ? e.name : "Error"
            e.timeMs=e.timeMs.isFinite ? e.timeMs:0; return e
        }
        value.resources=resources.map { Array($0.suffix(64)).map { resource in
            var r=resource; r.url=r.url.flatMap(TestingDiagnosticDetails.link)
            r.initiator=String(r.initiator.prefix(32)); r.nextHop=String(r.nextHop.prefix(32))
            return r
        } }
        return value
    }
}
