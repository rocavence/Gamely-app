import Foundation
import os
import Testing
@testable import Gamely

/// Runs against throwaway preference domains with a fake Dock restart.
@Suite(.serialized)
final class HotCornerControllerTests {
    private let dockDomain = "com.gamely.tests.dock"
    private let stateDomain = "com.gamely.tests.state"
    private let restarts = OSAllocatedUnfairLock(initialState: 0)
    private var dock: UserDefaults { UserDefaults(suiteName: dockDomain)! }
    private var hc: HotCornerController!

    init() {
        clean()
        let restarts = restarts
        hc = HotCornerController(dockDomain: dockDomain, stateDomain: stateDomain) {
            restarts.withLock { $0 += 1 }
        }
    }

    deinit { clean() }

    private func clean() {
        UserDefaults.standard.removePersistentDomain(forName: dockDomain)
        UserDefaults.standard.removePersistentDomain(forName: stateDomain)
    }

    @Test func pauseSavesOriginalsAndZeroesEveryKey() async {
        dock.set(2, forKey: "wvous-tl-corner")
        dock.set(131_072, forKey: "wvous-tl-modifier")
        dock.set(13, forKey: "wvous-br-corner")

        await hc.pause()

        #expect(hc.savedCorners == ["wvous-tl-corner": 2, "wvous-tl-modifier": 131_072, "wvous-br-corner": 13])
        for key in HotCornerController.keys {
            #expect(dock.object(forKey: key) as? Int == 0, "\(key)")
        }
        #expect(restarts.withLock { $0 } == 1)
    }

    @Test func restoreWritesBackAndRemovesKeysThatWereAbsent() async {
        dock.set(4, forKey: "wvous-tr-corner")
        await hc.pause()

        await hc.restore()

        #expect(dock.integer(forKey: "wvous-tr-corner") == 4)
        for key in HotCornerController.keys where key != "wvous-tr-corner" {
            #expect(dock.object(forKey: key) == nil, "\(key)")
        }
        #expect(!hc.isPaused)
        #expect(restarts.withLock { $0 } == 2)
    }

    @Test func repeatedPauseKeepsTheRealSettingsAndSkipsTheDock() async {
        dock.set(2, forKey: "wvous-bl-corner")
        await hc.pause()
        await hc.pause()

        #expect(hc.savedCorners == ["wvous-bl-corner": 2])
        #expect(restarts.withLock { $0 } == 1)
    }

    @Test func restoreWithoutPauseIsANoOp() async {
        dock.set(3, forKey: "wvous-tl-corner")
        await hc.restore()

        #expect(dock.integer(forKey: "wvous-tl-corner") == 3)
        #expect(restarts.withLock { $0 } == 0)
    }
}
