import Darwin

nonisolated struct FileStatus: Equatable, Sendable {
    enum FileType: Sendable {
        case directory, regular, symbolicLink, other
    }

    var type: FileType
    var size: Int
    var device: Int32
    var inode: UInt64

    init(_ info: stat) {
        switch info.st_mode & 0o170000 {
        case 0o040000: type = .directory
        case 0o100000: type = .regular
        case 0o120000: type = .symbolicLink
        default: type = .other
        }
        size = Int(info.st_size)
        device = info.st_dev
        inode = info.st_ino
    }

    // lstat: a symbolic link is reported as itself.
    static func of(_ path: String) -> FileStatus? {
        var info = stat()
        return lstat(path, &info) == 0 ? FileStatus(info) : nil
    }

    // stat: symbolic links are followed.
    static func follow(_ path: String) -> FileStatus? {
        var info = stat()
        return stat(path, &info) == 0 ? FileStatus(info) : nil
    }

    static func of(descriptor: Int32) -> FileStatus? {
        var info = stat()
        return fstat(descriptor, &info) == 0 ? FileStatus(info) : nil
    }
}
