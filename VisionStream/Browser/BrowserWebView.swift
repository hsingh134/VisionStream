import SwiftUI
import WebKit

@MainActor struct BrowserWebView: UIViewRepresentable {
    let browser: BrowserModel
    var hidden=false
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.isHidden=hidden
        uiView.isUserInteractionEnabled = !hidden
    }
}
