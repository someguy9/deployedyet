import CoreServices
import Foundation

/// Notices `git push` in a folder of repos, so the app can check right away instead of waiting for its next poll.
/// Local and read-only: it watches git's own log of remote-branch updates (`.git/logs/refs/remotes/…`) and reads
/// only the last line of that log, to tell a push from a fetch. It never runs git, never reads code, sends nothing.
@MainActor
final class PushWatcher {
    private var stream: FSEventStreamRef?
    private let onPush: () -> Void

    /// nil when the folder can't be watched. The owner calls `stop()` before letting it go.
    init?(folder: String, onPush: @escaping () -> Void) {
        self.onPush = onPush
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<PushWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            MainActor.assumeIsolated { watcher.handle(changed) } // the stream is scheduled on the main queue
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags)
        else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(_ paths: [String]) {
        // Cheap path filter first, so busy folders (node_modules, builds) cost nothing beyond the string check.
        if paths.contains(where: { $0.contains("/.git/logs/refs/remotes/") && Self.lastLineIsPush($0) }) {
            onPush()
        }
    }

    /// git's reflog marks pushes "update by push"; fetches and pulls write something else.
    nonisolated static func lastLineIsPush(_ path: String) -> Bool {
        guard let file = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? file.close() }
        let size = (try? file.seekToEnd()) ?? 0
        try? file.seek(toOffset: size > 512 ? size - 512 : 0)
        guard let data = try? file.readToEnd(), let tail = String(data: data, encoding: .utf8) else { return false }
        return tail.split(separator: "\n").last?.contains("update by push") == true
    }
}
