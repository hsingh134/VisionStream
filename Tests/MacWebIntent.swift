import AppKit
import WebKit
import Foundation

/// Public AppKit input through a real WKWebView, using original local CC0
/// media only. Tests the shipped JavaScript with actual WebKit isTrusted events;
/// does not represent physical Vision Pro gaze/pinch acceptance.
@MainActor final class IntentDriver:NSObject,WKScriptMessageHandler {
    var latest:[[String:Any]]=[]
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        latest=(message.body as? [String:Any])?["candidates"] as? [[String:Any]] ?? []
    }
    func wait(_ name:String,_ condition:()->Bool) async throws {
        let end=Date().addingTimeInterval(15)
        while !condition(),Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        guard condition() else { throw NSError(domain:"MacIntentCheck",code:1,userInfo:[NSLocalizedDescriptionKey:name]) }
    }
    var hasIntent:Bool { latest.contains { $0["playIntent"] is [String:Any] } }
    var playing:Bool { latest.contains { ($0["webMedia"] as? [String:Any])?["paused"] as? Bool == false } }
    func run(root:URL) async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("VisionStream-CC0-Input-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.copyItem(at:root.appendingPathComponent("Fixtures/generated/vr180-sbs.mp4"),to:folder.appendingPathComponent("fixture.mp4"))
        let html="""
        <!doctype html><meta charset="utf-8"><title>VisionStream automated CC0 input test</title>
        <style>body{margin:20px;background:#183044;color:white;font:18px system-ui}video{width:600px;height:300px}button{position:absolute;left:220px;top:120px;width:140px;height:70px}</style>
        <video id="video" muted playsinline preload="auto" src="fixture.mp4"></video>
        <button id="play" onclick="document.body.dataset.trusted=String(event.isTrusted);this.hidden=true;document.querySelector('video').play()">Play CC0</button>
        """
        let file=folder.appendingPathComponent("index.html");try Data(html.utf8).write(to:file)
        let config=WKWebViewConfiguration();config.mediaTypesRequiringUserActionForPlayback=[]
        config.userContentController.add(self,contentWorld:.defaultClient,name:"visionStream")
        config.userContentController.addUserScript(WKUserScript(source:try String(contentsOf:root.appendingPathComponent("VisionStream/Resources/VideoDetector.js"),encoding:.utf8),injectionTime:.atDocumentEnd,forMainFrameOnly:false,in:.defaultClient))
        let web=WKWebView(frame:NSRect(x:0,y:0,width:680,height:400),configuration:config)
        let window=NSWindow(contentRect:web.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="VisionStream — automated CC0 input test";window.contentView=web;window.center();window.makeKeyAndOrderFront(nil)
        defer { web.stopLoading();window.orderOut(nil);config.userContentController.removeScriptMessageHandler(forName:"visionStream",contentWorld:.defaultClient) }
        web.loadFileURL(file,allowingReadAccessTo:folder)
        try await wait("local video metadata") { latest.contains { ($0["width"] as? Int ?? 0)>0 } }
        _ = try await web.evaluateJavaScript("document.querySelector('#play').click();true")
        try await wait("synthetic website playback") { playing }
        guard !hasIntent else { throw NSError(domain:"MacIntentCheck",code:2) }
        let synthetic=try await web.evaluateJavaScript("document.body.dataset.trusted") as? String
        guard synthetic=="false" else { throw NSError(domain:"MacIntentCheck",code:3) }
        print("PASS: real WebKit synthetic click starts page playback without automatic VR intent")
        _ = try await web.evaluateJavaScript("document.querySelector('video').pause();document.querySelector('#play').hidden=false;true")
        try await wait("paused before trusted input") { !playing }
        guard let point=try await web.evaluateJavaScript("(()=>{const r=document.querySelector('#play').getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2}})()") as? [String:Double],let x=point["x"],let y=point["y"] else { throw NSError(domain:"MacIntentCheck",code:4) }
        let location=web.convert(NSPoint(x:x,y:web.isFlipped ? y:web.bounds.height-y),to:nil)
        if #available(macOS 14,*) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps:true) }
        window.makeKeyAndOrderFront(nil);window.makeFirstResponder(web)
        try await Task.sleep(for:.milliseconds(300))
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            guard let event=NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:type == .leftMouseDown ? 1:0) else { throw NSError(domain:"MacIntentCheck",code:5) }
            window.sendEvent(event)
        }
        do { try await wait("trusted AppKit click creates isolated play intent") { hasIntent && playing } }
        catch {
            let state=try? await web.evaluateJavaScript("({trusted:document.body.dataset.trusted,visibility:document.visibilityState,focused:document.hasFocus(),paused:document.querySelector('video').paused,width:innerWidth,height:innerHeight})")
            print("OWNED_CC0_WINDOW_STATE: \(String(describing:state))")
            throw error
        }
        let trusted=try await web.evaluateJavaScript("document.body.dataset.trusted") as? String
        guard trusted=="true" else { throw NSError(domain:"MacIntentCheck",code:6) }
        print("PASS: public AppKit click is trusted by real WebKit and produces the shipped play intent")
        print("2 real WebKit input checks passed; original local CC0 media only")
    }
}
@main struct MacIntentCheck {
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        Task { @MainActor in
            do { try await IntentDriver().run(root:root);exit(0) }
            catch { print("FAIL: real WebKit input check: \(error.localizedDescription)");exit(1) }
        }
        app.run()
    }
}
