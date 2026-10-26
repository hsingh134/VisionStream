import SwiftUI

@MainActor enum PublicationInfo {
    static func value(_ key:String)->String? {
        guard let value=Bundle.main.object(forInfoDictionaryKey:key) as? String,
              !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!value.contains("$(") else { return nil }
        return value
    }
    static func url(_ key:String)->URL? {
        guard let text=value(key),let url=URL(string:text),url.scheme=="https",url.host != nil,url.user==nil,url.password==nil else { return nil }
        return url
    }
}

@MainActor struct PrivacyPolicyView:View {
    @Environment(\.dismiss) private var dismiss
    @State private var showLicences=false
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Privacy").font(.title2.bold())
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text(policy)
                        .textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    if let publisher=PublicationInfo.value("VisionStreamPublisherName") { Text("Publisher: "+publisher).font(.headline) }
                    if let privacy=PublicationInfo.url("VisionStreamPrivacyPolicyURL") { Link("Public privacy policy",destination:privacy) }
                    if let support=PublicationInfo.url("VisionStreamSupportURL") { Link("Support",destination:support) }
                    if let email=PublicationInfo.value("VisionStreamSupportEmail") { Text("Contact: "+email).textSelection(.enabled) }
                    if PublicationInfo.value("VisionStreamPublisherName")==nil || PublicationInfo.url("VisionStreamSupportURL")==nil {
                        Text("Development build: publisher/contact information must be configured before public submission.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Third-party licences") { showLicences=true }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut("w",modifiers:.command)
            }
        }.padding(30).frame(width:700,height:620)
            .sheet(isPresented:$showLicences) { LicenceListView() }
    }
    private var policy:String {
        guard let file=Bundle.main.url(forResource:"PrivacyPolicy",withExtension:"txt"),let text=try? String(contentsOf:file,encoding:.utf8) else { return "The privacy policy could not be loaded." }
        return text
    }

}

@MainActor private struct LicenceListView:View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected="THIRD_PARTY_NOTICES.md"
    private let documents=["THIRD_PARTY_NOTICES.md","Apache-2.0.txt","EmbeddedRuntime.txt","FFmpeg-LGPL-2.1.txt","VisionStream-MIT.txt"]
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Third-party licences").font(.title2.bold())
            Picker("Document",selection:$selected) { ForEach(documents,id:\.self) { Text($0).tag($0) } }
            ScrollView { Text(text).font(.callout).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            Button("Done") { dismiss() }.keyboardShortcut("w",modifiers:.command)
        }.padding(30).frame(width:740,height:620)
    }
    private var text:String {
        let name=(selected as NSString).deletingPathExtension,ext=(selected as NSString).pathExtension
        guard let file=Bundle.main.url(forResource:name,withExtension:ext),let value=try? String(contentsOf:file,encoding:.utf8) else { return "The licence document could not be loaded." }
        return value
    }
}
