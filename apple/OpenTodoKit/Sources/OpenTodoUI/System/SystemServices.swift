// macOS: the parts of the app that live outside its windows — the menu bar
// window and the global quick-add shortcut with its panel. They share one
// `AppModel` (the "accessory" model, on the same database as the windows;
// the app's `AppServices`), made when first needed.
//
// The app shell calls `SystemServices.shared.start(services:debug:)` once at launch
// and adds `MenuBarScene()` to its scenes.

#if os(macOS)
import AppKit
import OpenTodoSystem
import SwiftUI

@MainActor @Observable
public final class SystemServices {
    public static let shared = SystemServices()

    /// The shortcut couldn't be registered (another app has it).
    public private(set) var hotKeyFailed = false

    @ObservationIgnored private var debug: DebugLaunch?
    @ObservationIgnored private var services: AppServices?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var registered: HotKey?
    @ObservationIgnored private var defaultsObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var _model: AppModel?

    private init() {}

    /// Registers the shortcut and follows changes to it in 设置. `services`
    /// are the app's (the one database, repository and settings).
    public func start(services: AppServices, debug: DebugLaunch?) {
        guard defaultsObserver == nil else { return }
        self.services = services
        self.debug = debug
        updateHotKey()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SystemServices.shared.updateHotKey() }
        }
    }

    /// The model the menu bar window and the panel use, on the app's
    /// services. Its view is 收集箱, so quick add without a date goes to the
    /// inbox.
    public var model: AppModel {
        if let _model { return _model }
        let services = self.services ?? AppModel.launchServices(debug)
        self.services = services
        let model = AppModel(repo: services.repo, settings: services.settings, services: services)
        model.select(.smart(.inbox))
        if case .system("quickpanel")? = debug?.open { model.taskList.prefill = debug?.quickAddText }
        _model = model
        SystemSync.shared.register(model)
        Task { await model.start() }
        return model
    }

    private func updateHotKey() {
        // Scripted debug runs (screenshots, on a database of their own)
        // leave the person's keyboard alone.
        let wanted = debug?.databasePath == nil ? IntegrationPrefs.hotKey() : nil
        guard wanted != registered || (wanted != nil && hotKey == nil && !hotKeyFailed) else { return }
        hotKey?.invalidate()
        hotKey = nil
        registered = wanted
        guard let wanted else {
            hotKeyFailed = false
            return
        }
        hotKey = GlobalHotKey(wanted) { [weak self] in
            guard let self else { return }
            QuickAddPanelController.shared.toggle(model: self.model)
        }
        hotKeyFailed = hotKey == nil
    }
}
#endif
