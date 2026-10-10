// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PrivateFileStoreSecurityTests {
    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("PrivateSecurity-" + UUID().uuidString)
        let outside = manager.temporaryDirectory.appendingPathComponent("PrivateOutside-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root); try? manager.removeItem(at: outside) }
        suite.expect(PrivateFileStore.createDirectory(at: root, container: root), "private test root created")
        try? manager.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try? manager.createSymbolicLink(at: link, withDestinationURL: outside)
        suite.expect(!PrivateFileStore.createDirectory(at: link.appendingPathComponent("child"), container: root),
                     "symlink ancestors cannot redirect private creation")
        suite.expect(!PrivateFileStore.write(Data([1]), to: link.appendingPathComponent("secret")),
                     "symlink ancestors cannot redirect private writes")
        suite.expect(!manager.fileExists(atPath: outside.appendingPathComponent("secret").path),
                     "rejected writes do not touch the redirected destination")
        let target = outside.appendingPathComponent("target")
        try? Data([7]).write(to: target)
        let leaf = root.appendingPathComponent("leaf")
        try? manager.createSymbolicLink(at: leaf, withDestinationURL: target)
        suite.expect(PrivateFileStore.write(Data([2]), to: leaf)
                     && (try? Data(contentsOf: target)) == Data([7])
                     && (try? Data(contentsOf: leaf)) == Data([2]),
                     "atomic publication replaces a leaf link rather than following it")
        suite.expect(!PrivateFileStore.write(Data([3]), to: root.appendingPathComponent("missing/file")),
                     "missing parent is reported as a write failure")
        suite.expect(!PrivateFileStore.write(Data([3]), to: root), "directory cannot be replaced by a private file")
        suite.expect(!PrivateFileStore.createDirectory(at: outside, container: root),
                     "explicit container rejects paths outside its authority")
    }
}
