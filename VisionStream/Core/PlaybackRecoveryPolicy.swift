import Foundation

public enum PlaybackRecoveryPolicy {
    /// A single retry is allowed by the caller. Access, TLS, DRM and unknown
    /// format errors are never treated as transient transport failures.
    public static func allowsRetry(codes: [String], httpStatus: Int?) -> Bool {
        let statuses = codes.compactMap { $0.hasPrefix("HTTP:") ? Int($0.dropFirst(5)) : nil } + (httpStatus.map { [$0] } ?? [])
        if statuses.contains(where: { (400...499).contains($0) }) { return false }
        if codes.contains(where: { $0.hasPrefix("NSURLErrorDomain:-12") }) { return false }
        if codes.contains("AVFoundationErrorDomain:-11850") { return false }
        return statuses.contains(where: { [502,503,504].contains($0) }) ||
            [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost].contains {
                codes.contains("NSURLErrorDomain:\($0)")
            }
    }
}
