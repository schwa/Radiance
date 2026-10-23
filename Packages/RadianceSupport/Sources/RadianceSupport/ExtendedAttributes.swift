import Darwin
import Foundation

/// Reads and writes a file's extended attributes.
nonisolated public enum ExtendedAttributes {
    /// The attribute's bytes, or `nil` when the file has no attribute with that name.
    public static func data(named name: String, at url: URL) throws -> Data? {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let size = getxattr(path, name, nil, 0, 0, 0)
            if size < 0 {
                if errno == ENOATTR {
                    return nil
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, name, buffer.baseAddress, size, 0, 0)
            }
            guard read >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return data.prefix(read)
        }
    }

    /// Creates or replaces the attribute.
    public static func setData(_ data: Data, named name: String, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let result = data.withUnsafeBytes { buffer in
                setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0)
            }
            guard result == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    /// Removes the attribute. Not an error when it does not exist.
    public static func remove(named name: String, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            guard removexattr(path, name, 0) == 0 || errno == ENOATTR else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }
}
