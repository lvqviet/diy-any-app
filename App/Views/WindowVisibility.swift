import AppKit
import SwiftUI

extension View {
    /// Reports whether the hosting window is on screen and not fully covered.
    ///
    /// Closed menu bar panels and windows stay alive in memory, so `onDisappear` is not a
    /// reliable signal; the window's occlusion state is.
    func onWindowVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibilityReader(onChange: action))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindowChange = { [coordinator = context.coordinator] window in
            coordinator.observe(window)
        }
        context.coordinator.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.onChange = onChange
    }

    final class TrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        var onChange: ((Bool) -> Void)?
        private weak var window: NSWindow?
        private var observer: NSObjectProtocol?
        private var lastValue: Bool?

        func observe(_ newWindow: NSWindow?) {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            window = newWindow
            if let newWindow {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: newWindow, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            report()
        }

        private func report() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            guard visible != lastValue else { return }
            lastValue = visible
            onChange?(visible)
        }
    }
}
