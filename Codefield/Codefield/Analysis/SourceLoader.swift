import Foundation

nonisolated struct SourceText: Equatable, Sendable {
    var path: String
    var text: String
}

nonisolated struct SkippedFile: Equatable, Sendable {
    var path: String
    var reason: SkipReason
}

nonisolated struct SourceBatch: Equatable, Sendable {
    var files: [SourceText] = []
    var skipped: [SkippedFile] = []
    // Index of the first path not read yet.
    var next: Int
    // Source text read so far in this analysis, including this batch.
    var textUnits: Int
    // Set when the text read so far is over ReadLimits.sourceTextInMemory.
    var exceeded = false
}

// Source text goes to the page in batches, so neither side holds a second
// copy of the whole repository while it is being sent.
nonisolated enum SourceLoader {
    static let maxBatchUnits = 8 * 1024 * 1024
    static let maxBatchFiles = 400

    @concurrent
    static func readBatch(
        _ reader: SourceReader,
        paths: [String],
        from start: Int,
        textUnits: Int,
        limit: Int = ReadLimits.sourceTextInMemory
    ) async throws -> SourceBatch {
        var batch = SourceBatch(next: start, textUnits: textUnits)
        var batchUnits = 0
        while batch.next < paths.count, batch.files.count + batch.skipped.count < maxBatchFiles, batchUnits < maxBatchUnits {
            try Task.checkCancellation()
            let path = paths[batch.next]
            batch.next += 1
            switch reader.read(path, maxBytes: ReadLimits.sourceFileBytes) {
            case .text(let text):
                let units = text.utf16.count
                batch.textUnits += units
                batchUnits += units
                batch.files.append(SourceText(path: path, text: text))
                if batch.textUnits > limit {
                    batch.exceeded = true
                    return batch
                }
            case .skipped(let reason):
                batch.skipped.append(SkippedFile(path: path, reason: reason))
            }
        }
        return batch
    }

    // Configuration files that cannot be read are left out, as upstream
    // does: the analyzers treat a missing config like an absent one.
    @concurrent
    static func readConfigs(_ reader: SourceReader, paths: [String]) async -> [SourceText] {
        paths.compactMap { path in
            if case .text(let text) = reader.read(path, maxBytes: ReadLimits.configFileBytes) {
                return SourceText(path: path, text: text)
            }
            return nil
        }
    }
}
