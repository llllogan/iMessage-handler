import Darwin
import Foundation

final class SyncScheduler {
    private let indexer: Indexer
    private let paths: [String]
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "imessage-handler.sync-scheduler")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var timer: DispatchSourceTimer?
    private var debounce: DispatchWorkItem?

    init(indexer: Indexer, messagesDBPath: String, interval: TimeInterval) {
        self.indexer = indexer
        self.paths = [messagesDBPath, messagesDBPath + "-wal", messagesDBPath + "-shm"]
        self.interval = interval
    }

    func start() {
        startTimer()
        startFileWatchers()
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.indexer.scheduleSync()
        }
        timer.resume()
        self.timer = timer
    }

    private func startFileWatchers() {
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.debouncedSync()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }

    private func debouncedSync() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.indexer.scheduleSync()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
