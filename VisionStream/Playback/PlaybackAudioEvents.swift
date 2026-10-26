#if os(visionOS)
import AVFAudio
import Foundation

/// Notification payloads are reduced to typed, non-sensitive events before
/// crossing to the main actor. Token removal follows the observer's lifetime.
final class PlaybackAudioEvents {
    enum Event: Sendable { case began, ended(resume: Bool), disconnected, reset }
    private var tokens: [NSObjectProtocol] = []
    init(deliver: @escaping @Sendable (Event) -> Void) {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { deliver(.began) }
            else {
                let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                deliver(.ended(resume: options.contains(.shouldResume)))
            }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { deliver(.disconnected) }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in deliver(.reset) })
    }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
#endif
