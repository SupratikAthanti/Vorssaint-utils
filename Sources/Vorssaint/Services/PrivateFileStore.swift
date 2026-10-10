// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Owner-only storage, not encryption or protection against the same account.
/// Descriptor-relative operations reject redirected paths and never publish a
/// file before its permissions are established. macOS inherited ACLs are removed.
enum PrivateFileStore {
    static var containerURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    private static func path(_ url: URL) -> String {
        var value = url.standardizedFileURL.path
        #if canImport(Darwin)
        // These system-owned aliases are standard macOS paths, not store links.
        for alias in ["/var", "/tmp"] where value.hasPrefix(alias + "/") {
            value = "/private" + value
            break
        }
        #endif
        return value
    }

    private static func makePrivate(_ descriptor: Int32, mode: mode_t) -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid() else { return false }
        #if canImport(Darwin)
        guard let acl = acl_init(0) else { return false }
        defer { acl_free(acl) }
        guard acl_set_fd(descriptor, acl) == 0 else { return false }
        #endif
        guard fchmod(descriptor, mode) == 0, fstat(descriptor, &info) == 0 else { return false }
        return info.st_mode & 0o777 == mode
    }

    /// Opens each ancestor without following symlinks. Only directories within
    /// the declared store root are created/tightened; system parents are untouched.
    private static func directory(_ url: URL, create: Bool, container: URL?) -> Int32? {
        let target = path(url)
        let root = container.map(path) ?? target
        guard target == root || target.hasPrefix(root + "/") else { return nil }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        var current = ""
        for component in target.split(separator: "/") {
            current += "/" + component
            let privatePart = current == root || current.hasPrefix(root + "/")
            if create && privatePart {
                if mkdirat(fd, String(component), 0o700) != 0 && errno != EEXIST {
                    close(fd); return nil
                }
            }
            let next = openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { return nil }
            fd = next
            if privatePart && !makePrivate(fd, mode: 0o700) { close(fd); return nil }
        }
        return fd
    }

    @discardableResult
    static func createDirectory(at url: URL, container: URL? = containerURL) -> Bool {
        guard url.isFileURL, let fd = directory(url, create: true, container: container) else { return false }
        close(fd)
        return true
    }

    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let parent = url.deletingLastPathComponent()
        guard let directoryFD = directory(parent, create: false, container: parent) else { return false }
        defer { close(directoryFD) }
        let temporary = ".private-" + UUID().uuidString
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd); unlinkat(directoryFD, temporary, 0) }
        guard makePrivate(fd, mode: 0o600) else { return false }
        let written = data.withUnsafeBytes { bytes -> Bool in
            var offset = 0
            while offset < bytes.count {
                #if canImport(Darwin)
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                #else
                let count = Glibc.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                #endif
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard written, fsync(fd) == 0 else { return false }
        // Replaces a leaf symlink itself, never its target.
        return renameat(directoryFD, temporary, directoryFD, url.lastPathComponent) == 0
    }

    static func directoriesToTighten(from url: URL, container: URL?) -> [URL] {
        var chain = [url.standardizedFileURL]
        guard let containerPath = container?.standardizedFileURL.path else { return chain }
        var current = chain[0]
        while current.path != containerPath, current.path.hasPrefix(containerPath + "/") {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            chain.append(parent)
            current = parent
        }
        return chain
    }
}
