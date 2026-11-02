import Foundation
import IOKit.ps

/// Calls back on the main run loop whenever macOS reports a power source change: adapter
/// plugged in or out, battery percent changed, charging started or stopped.
@MainActor
final class PowerSourceMonitor {
    private final class Box {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
    }

    private let box: Box
    private var source: CFRunLoopSource?

    init(onChange: @escaping () -> Void) {
        box = Box(onChange)
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<Box>.fromOpaque(context).takeUnretainedValue().handler()
        }, context)?.takeRetainedValue() else { return }
        source = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
    }

    deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
    }
}
