import SwiftUI

enum SimulatorPanel: String {
    case videoBar, browser, address, stream, finder, library, details, playback, immersive, format, quality, position, downloads, bookmarks, settings
}

extension View {
    @ViewBuilder func simulatorPanel(_ panel: SimulatorPanel) -> some View {
        #if targetEnvironment(simulator)
        self.onAppear { SimulatorTestMonitor.panel(panel, mounted: true) }
            .onDisappear { SimulatorTestMonitor.panel(panel, mounted: false) }
        #else
        self
        #endif
    }
}
