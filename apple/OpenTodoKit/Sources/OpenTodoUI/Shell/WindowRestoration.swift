// Window restoration: each window remembers its module, view and open task
// (`@SceneStorage`, so macOS reopens windows as they were and iOS restores
// the scene) and comes back to them once the data is in. Off when a debug
// route says where to open.

import OpenTodoDomain
import SwiftUI

struct WindowRestoration: ViewModifier {
    @Environment(AppModel.self) private var model
    var enabled: Bool

    @SceneStorage("ot.module") private var savedModule = ""
    @SceneStorage("ot.view") private var savedView = ""
    @SceneStorage("ot.task") private var savedTask = ""
    @State private var restored = false

    func body(content: Content) -> some View {
        content
            .onChange(of: model.loaded, initial: true) { _, loaded in
                guard loaded, !restored else { return }
                restored = true
                guard enabled else { return }
                restore()
            }
            .onChange(of: model.module) { _, m in if restored { savedModule = m.rawValue } }
            .onChange(of: model.view) { _, v in if restored { savedView = v.description } }
            .onChange(of: model.selectedTaskId) { _, id in if restored { savedTask = id ?? "" } }
    }

    private func restore() {
        if let route = DebugRoute(savedView) {
            switch route {
            case .smart, .list, .tag, .filter: model.apply(route)
            default: break
            }
        }
        if !savedTask.isEmpty, let task = model.task(savedTask), viewMatcher(model.view, model.now, model.filterRules)(task) {
            model.open(taskId: task.id)
        }
        if let module = AppModule(rawValue: savedModule) { model.switchTo(module) }
    }
}
