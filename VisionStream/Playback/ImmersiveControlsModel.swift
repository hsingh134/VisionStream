import Foundation
import Observation

/// UI state changes only on interaction/visibility edges, not on every render tick.
@MainActor @Observable final class ImmersiveControlsModel {
    static let hideDelay: TimeInterval = 5
    private(set) var isVisible = true
    private(set) var placementID = 0
    var interactionLocked = false
    @ObservationIgnored private var lastInteraction = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var neededAttention = false

    func reset(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        isVisible = true; placementID += 1; lastInteraction = now
        interactionLocked = false; wasPlaying = false; neededAttention = false
    }
    func interacted(now: TimeInterval = ProcessInfo.processInfo.systemUptime) { lastInteraction = now }
    func show(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        isVisible = true; placementID += 1; lastInteraction = now
    }
    func hide() { isVisible = false }
    func toggle() { if isVisible { hide() } else { show() } }
    func tick(playing: Bool, attention: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if !isVisible, (attention && !neededAttention) || (wasPlaying && !playing && !attention) { show(now: now) }
        wasPlaying = playing; neededAttention = attention
        guard playing, !attention, !interactionLocked else { lastInteraction = now; return }
        if isVisible, now - lastInteraction >= Self.hideDelay { hide() }
    }
}
