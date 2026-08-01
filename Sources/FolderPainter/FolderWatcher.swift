import Foundation
import CoreServices

// FSEvents（macOSのフォルダ変化通知）でホームディレクトリを監視する
final class FolderWatcher {
    typealias Event = (path: String, flags: FSEventStreamEventFlags)

    var handler: (([Event]) -> Void)?

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "folderpainter.fsevents")

    func start(watching path: String) {
        stop()

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            var events: [Event] = []
            for i in 0..<count {
                events.append((path: paths[i], flags: eventFlags[i]))
            }
            watcher.handler?(events)
        }

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil, callback, &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5, // 秒。まとめて通知させる
            FSEventStreamCreateFlags(flags)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
