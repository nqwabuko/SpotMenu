import SwiftUI

/// The menu bar item's view. Scroll events land on the view under the pointer, so this
/// is where volume scrolling is caught: an app-wide event monitor never sees them.
final class StatusItemHostingView: NSHostingView<StatusItemView> {
    var onScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if let onScroll { onScroll(event) } else { super.scrollWheel(with: event) }
    }
}

final class StatusItemConfigurator {
    static func configure(
        statusItem: NSStatusItem,
        statusItemModel: StatusItemModel,
        menuBarPreferencesModel: MenuBarPreferencesModel,
        musicPlayerPreferencesModel: MusicPlayerPreferencesModel,
        playBackModel: PlaybackModel,
        toggleAction: Selector,
        target: AnyObject,
        onScroll: @escaping (NSEvent) -> Void
    ) {
        let view = StatusItemView(
            model: statusItemModel,
            menuBarPreferencesModel: menuBarPreferencesModel,
            musicPlayerPreferencesModel: musicPlayerPreferencesModel,
            playbackModel: playBackModel
        )
        let hostingView = StatusItemHostingView(rootView: view)
        hostingView.onScroll = onScroll
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.layout()

        if let button = statusItem.button {
            button.image = NSImage()
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.centerXAnchor.constraint(
                    equalTo: button.centerXAnchor
                ),
                hostingView.centerYAnchor.constraint(
                    equalTo: button.centerYAnchor
                ),
            ])
            button.action = toggleAction
            button.target = target
        }
    }

    static func updateWidth(statusItem: NSStatusItem, maxWidth: CGFloat) {
        guard
            let hostingView = statusItem.button?.subviews.compactMap({
                $0 as? NSHostingView<StatusItemView>
            }).first
        else {
            return
        }
        hostingView.layout()
        statusItem.length = min(
            hostingView.intrinsicContentSize.width,
            maxWidth
        )
    }
}
