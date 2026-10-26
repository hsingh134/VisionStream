import Foundation
import Observation

/// Python is bundled in the app. Work runs serially away from the UI actor.
final class OnDeviceExtractor: @unchecked Sendable {
    static let shared = OnDeviceExtractor()
    private let queue = DispatchQueue(label: "personal.visionstream.extractor", qos: .userInitiated,
                                     autoreleaseFrequency: .workItem)
    private init() {}

    func resolve(_ address: String) async throws -> ExtractedMedia {
        let media = try await resolveUninspected(address)
        return try await NativeStreamInspector.refine(media)
    }

    /// Metadata-only extraction before optional native asset inspection.
    func resolveUninspected(_ address: String) async throws -> ExtractedMedia {
        try Task.checkCancellation()
        let job = ExtractionJob()
        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !job.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                    do {
                        let output = try VSExtractorBridge.resolveAddress(address)
                        guard !job.isCancelled else { throw CancellationError() }
                        guard output.utf8.count <= 1_048_576 else { throw ExtractionError.invalidResult }
                        continuation.resume(returning: Data(output.utf8))
                    } catch is CancellationError {
                        continuation.resume(throwing: CancellationError())
                    } catch {
                        continuation.resume(throwing: ExtractionError.runtime)
                    }
                }
            }
        } onCancel: {
            // A running Python request finishes under its network timeout. Queued
            // cancelled requests are skipped and all late results are discarded.
            job.cancel()
        }
        try Task.checkCancellation()
        return try ExtractedMedia.parse(data, pageURL: address)
    }
}

private final class ExtractionJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

@MainActor @Observable
final class ExtractorModel {
    @ObservationIgnored weak var diagnostics: SessionDiagnostics?
    private var diagnosticContext: DiagnosticContext?
    private(set) var streams: [ExtractedStream] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let resolve: @Sendable (String) async throws -> ExtractedMedia

    init(resolve: @escaping @Sendable (String) async throws -> ExtractedMedia = {
        try await OnDeviceExtractor.shared.resolve($0)
    }) { self.resolve = resolve }

    func find(_ address: String) {
        clear()
        guard let url = URL(string: address), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else {
            errorMessage = ExtractionError.status("invalid_url").localizedDescription; return
        }
        diagnosticContext=diagnostics?.begin(.extraction,page:url)
        let context=diagnosticContext
        let token = generation
        isLoading = true
        let resolve = resolve
        task = Task { @MainActor [weak self] in
            do {
                let result = try await resolve(address)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.diagnostics?.record(.extraction,context:context,labels:["phase":"completed"],numbers:["candidateCount":Double(result.streams.count)])
                for stream in result.streams {
                    self.diagnostics?.record(.mediaState,context:self.diagnostics?.mediaContext(stream.candidate,parent:context),labels:["phase":"finder-result","mimeType":stream.candidate.normalizedMIMEType],numbers:self.diagnostics?.mediaNumbers(stream.candidate) ?? [:])
                }
                self.streams = result.streams
                self.isLoading = false; self.task = nil
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.diagnostics?.record(.extraction,context:context,labels:["phase":"failed"],codes:PlaybackDiagnostics.failure(error))
                self.errorMessage = (error as? ExtractionError ?? .runtime).localizedDescription
                self.isLoading = false; self.task = nil
            }
        }
    }

    func clear() {
        if isLoading { diagnostics?.record(.extraction,context:diagnosticContext,labels:["phase":"cancelled"]) }
        generation = UUID(); task?.cancel(); task = nil
        streams = []; isLoading = false; errorMessage = nil
    }
}
