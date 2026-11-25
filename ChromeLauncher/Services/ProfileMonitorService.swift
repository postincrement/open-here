import Foundation

/// Watches the Chrome user data directory for atomic replacement of `Local State`.
/// Events are debounced. The watcher does not poll.
final class ProfileMonitorService {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var debounce: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.chromelauncher.profile-monitor")
    private var onChange: (() -> Void)?

    func start(directory: URL, onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            AppLog.profiles.error("Unable to watch the Chrome user data directory")
            return
        }
        descriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.schedule()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
        descriptor = -1
        onChange = nil
    }

    private func schedule() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
