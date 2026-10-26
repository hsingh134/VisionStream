import Foundation

/// One native handoff per explicit webpage play gesture. A failure, cancellation
/// or Return to page never retries until a new gesture arrives. No URL history
/// or credentials are retained here.
public struct AutomaticPlayback: Sendable {
    private var generation: Int?
    private var consumed: [String] = []
    public init() {}

    public static func actionable(in candidates: [MediaCandidate]) -> [MediaCandidate] {
        candidates.filter { $0.compatibility == .candidate }
    }

    public mutating func next(in candidates: [MediaCandidate], navigation: Int, pageAge: Double, enabled: Bool = true) -> MediaCandidate? {
        if generation != navigation { generation=navigation; consumed.removeAll() }
        // Stop automatic handoffs on an unusually busy page rather than evicting
        // a used token and accidentally reopening it. Manual Watch stays usable.
        guard consumed.count < 512 else { return nil }
        let recent=candidates.filter { media in
            guard let intent=media.playIntent, UUID(uuidString:intent.id) != nil,
                  intent.age.isFinite, intent.age >= 0, intent.age <= 30,
                  pageAge >= 0, intent.age <= pageAge, !consumed.contains(intent.id) else { return false }
            return true
        }
        // Turning the preference off consumes current gestures, rather than
        // opening a stale video later if the user switches it on again.
        if !enabled { for media in recent { if let id=media.playIntent?.id { remember(id) } }; return nil }
        let playing=Self.actionable(in:recent).filter {
            $0.playIntent?.visible == true && $0.webMedia?.paused == false &&
            $0.webMedia?.errorCode == 0 && ($0.webMedia?.readyState ?? 0) >= 2 && $0.width > 0 && $0.height > 0
        }
        // If multiple elements started, the newest gesture wins; alternatives
        // for that element still use normal ready-source selection.
        guard let newest=playing.min(by: { ($0.playIntent?.age ?? 30) < ($1.playIntent?.age ?? 30) }),
              let intent=newest.playIntent,
              let chosen=MediaCandidate.preferredForPlayback(in:playing.filter { $0.playIntent?.id == intent.id }) else { return nil }
        remember(intent.id)
        return chosen
    }
    private mutating func remember(_ id: String) {
        if !consumed.contains(id) { consumed.append(id) }
        if consumed.count > 512 { consumed.removeLast(consumed.count-512) }
    }
}
