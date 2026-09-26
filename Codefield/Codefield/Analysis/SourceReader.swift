import Darwin
import Foundation

// The reasons upstream's SkippedSource uses, sent to the page as is.
nonisolated enum SkipReason: String, Equatable, Sendable {
    case tooLarge = "too_large"
    case notUTF8 = "not_utf8"
    case symlink
    case unreadable
}

nonisolated enum ReadResult: Equatable, Sendable {
    case text(String)
    case skipped(SkipReason)
}

// Limits from upstream lib/resources.ts and lib/analysis/config.ts.
nonisolated enum ReadLimits {
    static let sourceFileBytes = 1024 * 1024
    static let configFileBytes = 64 * 1024
    // Measured in UTF-16 code units, as upstream measures JavaScript strings.
    static let sourceTextInMemory = 768 * 1024 * 1024
}

// Reads files below one root the way upstream's lib/local/read.ts does. A
// file that is too large, not UTF-8, or no longer a regular file inside the
// root is skipped with its reason.
nonisolated struct SourceReader: Sendable {
    let root: String
    // The root as the kernel names it, to compare with the path of each file
    // opened. Both come from F_GETPATH, so firmlinks such as /Users are
    // reported the same way on both sides.
    private let openedRoot: String?

    init(root: String) {
        self.root = root
        let descriptor = open(root, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if descriptor >= 0 {
            openedRoot = Self.path(of: descriptor)
            close(descriptor)
        } else {
            openedRoot = nil
        }
    }

    func read(_ path: String, maxBytes: Int) -> ReadResult {
        // O_NOFOLLOW makes opening a file that was replaced by a symbolic link
        // after it was listed fail; O_NONBLOCK keeps a file replaced by a FIFO
        // from blocking the open.
        let descriptor = open(root + "/" + path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return .skipped(errno == ELOOP ? .symlink : .unreadable) }
        defer { close(descriptor) }

        guard let status = FileStatus.of(descriptor: descriptor), status.type == .regular else { return .skipped(.unreadable) }
        // A directory on the way could have been swapped for a link since the
        // listing; the file actually opened must still be inside the root.
        guard let opened = Self.path(of: descriptor), isInsideRoot(opened) else { return .skipped(.symlink) }
        guard status.size <= maxBytes else { return .skipped(.tooLarge) }

        // One byte more than allowed, to notice a file that grew after fstat.
        let capacity = status.size + 1
        var bytes = [UInt8](repeating: 0, count: capacity)
        var length = 0
        let failed = bytes.withUnsafeMutableBytes { buffer -> Bool in
            while length < capacity {
                let count = Darwin.read(descriptor, buffer.baseAddress! + length, capacity - length)
                if count < 0 {
                    if errno == EINTR { continue }
                    return true
                }
                if count == 0 { break }
                length += count
            }
            return false
        }
        if failed { return .skipped(.unreadable) }
        if length > maxBytes { return .skipped(.tooLarge) }

        return Self.decode(bytes[..<length]).map(ReadResult.text) ?? .skipped(.notUTF8)
    }

    // Strict UTF-8, dropping a leading byte order mark as the TextDecoder
    // upstream uses does.
    static func decode(_ bytes: ArraySlice<UInt8>) -> String? {
        let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? bytes.dropFirst(3) : bytes
        return String(validating: body, as: UTF8.self)
    }

    func isInsideRoot(_ path: String) -> Bool {
        guard let openedRoot else { return false }
        return path == openedRoot || path.hasPrefix(openedRoot.hasSuffix("/") ? openedRoot : openedRoot + "/")
    }

    private static func path(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return buffer.withUnsafeMutableBufferPointer { pointer in
            guard fcntl(descriptor, F_GETPATH, pointer.baseAddress!) != -1 else { return nil }
            return String(cString: pointer.baseAddress!)
        }
    }
}
