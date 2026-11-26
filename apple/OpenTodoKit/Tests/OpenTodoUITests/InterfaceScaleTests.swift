// 界面大小: the sizes and their order, what's stored, ⌘+ / ⌘- / ⌘0, the
// debug launch option, and the helpers giving exactly the 标准 fonts at 1.

import Foundation
import SwiftUI
import Testing
@testable import OpenTodoUI

@MainActor
@Suite struct InterfaceScaleTests {
    /// A UserDefaults of its own for each test.
    private func scratchDefaults() -> UserDefaults {
        let name = "InterfaceScaleTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func sizesGoFromSmallToExtraLarge() {
        #expect(InterfaceSize.allCases == [.small, .standard, .large, .extraLarge])
        #expect(InterfaceSize.standard.scale == 1)
        let scales = InterfaceSize.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(Set(scales).count == 4)
        #expect(InterfaceSize.small.scale < 1)
        #expect(InterfaceSize.allCases.map(\.title) == ["小", "标准", "大", "特大"])
    }

    @Test func eachSizeKnowsItsNeighbours() {
        #expect(InterfaceSize.small.smaller == nil)
        #expect(InterfaceSize.small.larger == .standard)
        #expect(InterfaceSize.standard.larger == .large)
        #expect(InterfaceSize.large.larger == .extraLarge)
        #expect(InterfaceSize.extraLarge.larger == nil)
        #expect(InterfaceSize.extraLarge.smaller == .large)
        #expect(InterfaceSize.standard.smaller == .small)
    }

    @Test func readsWhatIsStoredAndStandardOtherwise() {
        #expect(InterfaceSize(storage: nil) == .standard)
        #expect(InterfaceSize(storage: "") == .standard)
        #expect(InterfaceSize(storage: "huge") == .standard)
        #expect(InterfaceSize(storage: "large") == .large)
        #expect(InterfaceSize(storage: "extraLarge") == .extraLarge)
    }

    @Test func standardIsKeptAsNothing() {
        let d = scratchDefaults()
        #expect(InterfacePrefs.size(d) == .standard)
        InterfacePrefs.setSize(.large, d)
        #expect(d.string(forKey: InterfacePrefs.sizeKey) == "large")
        #expect(InterfacePrefs.size(d) == .large)
        InterfacePrefs.setSize(.standard, d)
        #expect(d.object(forKey: InterfacePrefs.sizeKey) == nil)
        #expect(InterfacePrefs.size(d) == .standard)
    }

    @Test func zoomingStepsOneSizeAndStopsAtTheEnds() {
        let d = scratchDefaults()
        InterfacePrefs.zoomIn(d)
        #expect(InterfacePrefs.size(d) == .large)
        InterfacePrefs.zoomIn(d)
        InterfacePrefs.zoomIn(d)
        #expect(InterfacePrefs.size(d) == .extraLarge)
        InterfacePrefs.resetSize(d)
        #expect(InterfacePrefs.size(d) == .standard)
        InterfacePrefs.zoomOut(d)
        InterfacePrefs.zoomOut(d)
        #expect(InterfacePrefs.size(d) == .small)
        InterfacePrefs.zoomIn(d)
        #expect(InterfacePrefs.size(d) == .standard)
        #expect(d.object(forKey: InterfacePrefs.sizeKey) == nil)
    }

    @Test func aDebugLaunchOverridesWhatIsStoredForTheRun() {
        let d = scratchDefaults()
        let saved = d.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { d.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        InterfacePrefs.setSize(.small, d)
        InterfacePrefs.overrideForThisRun(.extraLarge, d)
        #expect(InterfacePrefs.size(d) == .extraLarge)
        // What the app stores meanwhile doesn't show while the option is there.
        InterfacePrefs.setSize(.large, d)
        #expect(InterfacePrefs.size(d) == .extraLarge)
    }

    @Test func theLaunchOptionIsRead() {
        let l = DebugLaunch(arguments: ["app", "-OTInterfaceSize", "large", "-OTOpen", "smart:today"])
        #expect(l.interfaceSize == .large)
        #expect(l.problems.isEmpty)
        #expect(DebugLaunch(arguments: ["app"]).interfaceSize == nil)
        let bad = DebugLaunch(arguments: ["app", "-OTInterfaceSize", "huge"])
        #expect(bad.interfaceSize == nil)
        #expect(bad.problems.count == 1)
    }

    @Test func atOneTheFontsAreTheStylesThemselves() {
        #expect(Font.ui(.body, scale: 1) == Font.body)
        #expect(Font.ui(.caption2, scale: 1) == Font.caption2)
        #expect(Font.ui(.headline, scale: 1) == Font.headline)
        #expect(Font.ui(.caption, weight: .semibold, scale: 1) == Font.caption.weight(.semibold))
        #expect(Font.ui(.body, weight: .semibold, design: .default, scale: 1)
            == Font.system(.body, design: .default).weight(.semibold))
        #expect(Font.ui(size: 11, weight: .medium, scale: 1) == Font.system(size: 11, weight: .medium))
        #expect(Font.ui(size: 10, scale: 1) == Font.system(size: 10))
    }

    @Test func otherwiseTheyAreTheMacSizesScaled() {
        #expect(Font.ui(.body, scale: 2) == Font.system(size: 26, weight: .regular, design: .default))
        #expect(Font.ui(.headline, scale: 2) == Font.system(size: 26, weight: .bold, design: .default))
        #expect(Font.ui(.caption, weight: .semibold, scale: 2) == Font.system(size: 20, weight: .semibold, design: .default))
        #expect(Font.ui(size: 10, weight: .bold, scale: 2) == Font.system(size: 20, weight: .bold))
        #expect(Font.macPointSize(.subheadline) == 11)
        #expect(Font.macPointSize(.title3) == 15)
    }

    @Test func calendarAndBoardSizesFollowTheScale() {
        // The month cell: the same lines in a cell scaled with them.
        let room = CalendarMetrics.cellHeader + 4 + (CalendarMetrics.chipHeight + CalendarMetrics.chipGap) * 3
        #expect(CalendarLogic.cellLines(height: room) == 3)
        #expect(CalendarLogic.cellLines(height: room * 1.5, scale: 1.5) == 3)
        #expect(CalendarLogic.cellLines(height: room, scale: 1.5) == 1)
        // A panel beside the calendar needs proportionally more room.
        #expect(CalendarLogic.panelsBeside(width: 920))
        #expect(!CalendarLogic.panelsBeside(width: 920, scale: 1.2))
        #expect(CalendarLogic.panelsBeside(width: 920 * 1.2, scale: 1.2))
        // A wide board's columns grow; a phone's stay a share of the width.
        #expect(BoardLayout.columnWidth(for: 1000, scale: 1.4) == BoardLayout.columnWidth * 1.4)
        #expect(BoardLayout.columnWidth(for: 400, scale: 1.4) == BoardLayout.columnWidth(for: 400))
    }
}
