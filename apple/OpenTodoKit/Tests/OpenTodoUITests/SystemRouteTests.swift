import Testing
@testable import OpenTodoUI

@Test(arguments: SystemDebugState.allCases)
func systemRoutes(_ state: SystemDebugState) {
    #expect(DebugRoute("system:\(state.rawValue)") == .system(state.rawValue))
    #expect(DebugRoute("system:\(state.rawValue)")?.text == "system:\(state.rawValue)")
}
