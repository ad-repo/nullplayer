import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

final class WMPPhase5Tests: XCTestCase {
    private var helperURL: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/WMPScriptIsolationHelper")
    }

    func testCompatibilityTableIsClosedAndChecked() {
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "controls", member: "play"))
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "theme", member: "currentViewID"))
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "player", member: "shellExecute"))
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "registry", member: "read"))
    }

    func testVersionedTransactionCapturesDependenciesMutationsCommandsPreferencesAndTimers() async throws {
        let runtime = WMPJScriptRuntime(helperURL: helperURL, timeout: 0.5)
        let batch = WMPJScriptBatch(registrations: [
            .init(id: "view", properties: ["width": .number(100), "height": .number(50)]),
            .init(id: "stub", properties: ["width": .number(20), "left": .number(0)])
        ], scripts: ["stub.left = 4;"],
        expressions: [.init(key: "stub.width", source: "view.width / 2")],
        event: .init(name: "click", targetID: "stub", handlers: [
            "stub.left = stub.width + 1; player.controls.play(); player.settings.setString('accent','blue'); setInterval(function(){ stub.left = 9; }, 1);"
        ]), host: ["playlistCount": .number(1)], preferences: [:])

        let transaction = try success(await runtime.transact(batch))
        XCTAssertEqual(transaction.version, WMPJScriptProtocol.version)
        XCTAssertEqual(transaction.expressions.first?.value, .number(50))
        XCTAssertEqual(transaction.expressions.first?.dependencies, ["view.width"])
        XCTAssertTrue(transaction.mutations.contains { $0.targetID == "stub" && $0.property == "left" && $0.value == .number(51) })
        XCTAssertTrue(transaction.hostCommands.contains { $0.action == "play" })
        XCTAssertEqual(transaction.preferences, [.init(key: "accent", value: "blue")])
        XCTAssertEqual(transaction.timers.first?.periodMilliseconds, 8)
        XCTAssertEqual(transaction.timers.first?.repeats, true)
    }

    func testUnsupportedMemberReturnsDefaultWarningAndDeniedNativeObjectsStayUnavailable() async throws {
        let runtime = WMPJScriptRuntime(helperURL: helperURL, timeout: 0.5)
        let batch = WMPJScriptBatch(registrations: [.init(id: "view", properties: [:])],
            expressions: [.init(key: "view.width", source: "view.shellExecute + (typeof ActiveXObject === 'undefined' ? 1 : 100)")])
        let transaction = try success(await runtime.transact(batch))
        XCTAssertEqual(transaction.expressions.first?.value, .number(1))
        XCTAssertTrue(transaction.diagnostics.contains { $0.code == "unsupported-member" })
    }

    func testHostileLoopTimesOutAndNextFreshRealmSucceeds() async throws {
        let runtime = WMPJScriptRuntime(helperURL: helperURL, timeout: 0.05)
        let hostile = WMPJScriptBatch(scripts: ["while (true) {}"])
        switch await runtime.transact(hostile) {
        case let .failure(error): XCTAssertEqual(error.code, .scriptTimedOut)
        case .success: XCTFail("hostile loop unexpectedly completed")
        }
        let recovered = try success(await runtime.transact(WMPJScriptBatch(
            registrations: [.init(id: "view", properties: [:])],
            expressions: [.init(key: "view.width", source: "6 * 7")])))
        XCTAssertEqual(recovered.expressions.first?.value, .number(42))
    }

    func testProductionBridgeHostileCorpusAndHundredFreshRealmCycles() async throws {
        let runtime = WMPJScriptRuntime(helperURL: helperURL, timeout: 0.1)
        let registration = WMPJScriptRegistration(id: "view", properties: [:])
        for index in 0..<100 {
            let transaction = try success(await runtime.transact(WMPJScriptBatch(
                registrations: [registration], expressions: [.init(key: "view.width", source: "\(index) + 1")])))
            XCTAssertEqual(transaction.expressions.first?.value, .number(Double(index + 1)))
        }
        let syntax = try fixtureScript("syntax-error.js"), recursion = try fixtureScript("recursion.js")
        for source in [syntax, recursion] {
            let transaction = try success(await runtime.transact(WMPJScriptBatch(scripts: [source])))
            XCTAssertTrue(transaction.diagnostics.contains { $0.code == "script-error" })
        }
        let storm = try success(await runtime.transact(WMPJScriptBatch(scripts: [try fixtureScript("timer-storm.js")])))
        XCTAssertEqual(storm.timers.count, WMPPhase0Limits.activeTimers)
        XCTAssertTrue(storm.timers.allSatisfy { $0.periodMilliseconds >= WMPPhase0Limits.minimumTimerPeriodMilliseconds })
        for name in ["allocation-pressure.js", "infinite-loop.js"] {
            switch await runtime.transact(WMPJScriptBatch(scripts: [try fixtureScript(name)])) {
            case let .failure(error): XCTAssertTrue(error.code == .scriptTimedOut || error.code == .scriptCrashed)
            case .success: XCTFail("\(name) unexpectedly completed")
            }
        }
        _ = try success(await runtime.transact(WMPJScriptBatch(
            registrations: [registration], expressions: [.init(key: "view.width", source: "42")])))
    }

    func testSynchronousTeardownKillsAnActiveHostileRealm() async {
        let runtime = WMPJScriptRuntime(helperURL: helperURL, timeout: 5)
        let evaluation = Task { await runtime.transact(WMPJScriptBatch(scripts: ["while (true) {}"])) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let start = Date()
        runtime.cancelAll()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.25)
        switch await evaluation.value {
        case let .failure(error): XCTAssertTrue(error.code == .scriptCrashed || error.code == .scriptProtocolViolation)
        case .success: XCTFail("teardown did not terminate the hostile realm")
        }
    }

    func testSessionDetectsDependencyCycleWithoutCommittingPartialGeometry() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="100" height="50"><SUBVIEW id="a" left="0" top="0"
            width="jscript:b.width" height="10"/><SUBVIEW id="b" left="0" top="10"
            width="jscript:a.width" height="10"/></VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let suite = "WMPPhase5Tests.cycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let session = WMPPhase5Session(runtime: WMPJScriptRuntime(helperURL: helperURL, timeout: 0.5),
            preferences: WMPPreferenceStore(skinData: Data("cycle".utf8), defaults: defaults))
        let output = await session.transact(skin: skin, viewID: "main", size: .init(width: 100, height: 50),
                                            snapshot: WMPHostSnapshot(), event: nil)
        XCTAssertTrue(output.overrides.geometry.isEmpty)
        XCTAssertTrue(output.diagnostics.contains { $0.code == "dependency-cycle" })
    }

    func testPropertyRegistryCoalescesBindingsAndPreventsOriginFeedback() throws {
        let graph = WMPObjectGraph(document: try WMPXMLParser().parse("""
        <VIEW id="main"><TEXT id="time" value="wmpprop:player.controls.currentPositionString"/>
        <BUTTON id="play" enabled="wmpenabled:player.controls.play"/></VIEW>
        """, path: "bindings.wms"))
        var registry = WMPObservablePropertyRegistry(graph: graph)
        var snapshot = WMPHostSnapshot(); snapshot.playlistCount = 1; snapshot.currentTime = 5
        let first = registry.changes(for: snapshot)
        XCTAssertEqual(first.count, 2)
        XCTAssertTrue(first.contains { $0.value == .string("0:05") })
        XCTAssertTrue(first.contains { $0.value == .bool(true) })
        XCTAssertTrue(registry.changes(for: snapshot).isEmpty)
        let origin = WMPPropertyTransactionOrigin(id: UUID())
        _ = registry.changes(for: snapshot, origin: origin)
        XCTAssertTrue(registry.changes(for: snapshot, origin: origin).isEmpty)
    }

    func testPreferencesAreHashNamespacedBoundedAndResettable() throws {
        let suite = "WMPPhase5Tests.preferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let first = WMPPreferenceStore(skinData: Data("one".utf8), defaults: defaults, maximumCount: 1)
        let second = WMPPreferenceStore(skinData: Data("two".utf8), defaults: defaults, maximumCount: 1)
        XCTAssertNotEqual(first.namespace, second.namespace)
        XCTAssertTrue(first.apply([.init(key: "a", value: "1")]).isEmpty)
        XCTAssertEqual(first.values(), ["a": "1"]); XCTAssertTrue(second.values().isEmpty)
        XCTAssertEqual(first.apply([.init(key: "b", value: "2")]).first?.code, "preference-count-limit")
        XCTAssertEqual(first.apply([.init(key: "a", value: String(repeating: "x", count: WMPPhase0Limits.preferenceValueBytes + 1))]).first?.code,
                       "preference-value-too-large")
        first.reset(); XCTAssertTrue(first.values().isEmpty)
    }

    func testSceneOverridesCommitResolvedGeometryAndPropertyAtomically() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="100" height="50"><TEXT id="label" left="jscript:view.width/2"
            top="5" width="40" height="10" value="old"/></VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let label = try XCTUnwrap(skin.graph.nodes(id: "label").first)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: label.stableID, property: "left")] = 50
        overrides.properties[.init(stableID: label.stableID, property: "value")] = .string("new")
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main", overrides: overrides)
        XCTAssertEqual(scene.geometries[label.stableID]?.absoluteFrame.x, 50)
        guard case let .text(text) = scene.commands.first(where: { $0.stableID == label.stableID })?.paint else {
            return XCTFail("missing text command")
        }
        XCTAssertEqual(text.value, "new")
    }

    @MainActor
    func testScriptOnlyButtonDispatchesClickWithoutTransportAction() throws {
        let size = WMPSize(width: 20, height: 20)
        let hit = WMPHitMetadata(stableID: 2, nodeID: "scriptOnly", kind: "button",
            frame: .init(x: 0, y: 0, width: 20, height: 20), clipRect: nil,
            zIndex: 0, documentOrder: 2, action: nil, sticky: false, enabled: true,
            mappingImage: nil, mappingTargets: [])
        let scene = WMPScene(viewID: "main", canvasSize: size,
            resizeLimits: .init(minimum: size, maximum: size), commands: [], hits: [hit],
            geometries: [:], unresolved: [], diagnostics: [], dirtyBounds: hit.frame,
            metrics: .init(resolvedNodeCount: 1, unresolvedNodeCount: 0, visibleBounds: hit.frame),
            wasBuiltOnMainThread: false)
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8,
            bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let view = WMPMainView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView = view; view.present(image, scene: scene)
        var events: [String] = []
        view.onScriptEvent = { name, target in events.append("\(name):\(target ?? "-")") }
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0.01, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseDown(with: down); view.mouseUp(with: up)
        XCTAssertTrue(events.contains("click:scriptOnly"))
    }

    func testOptInNineSeriesScriptsAndGeometryAtThreeSizes() async throws {
        guard let path = ProcessInfo.processInfo.environment["WMP_TEST_WMZ"], !path.isEmpty else {
            throw XCTSkip("Set WMP_TEST_WMZ to a user-supplied WMP skin.")
        }
        let url = URL(fileURLWithPath: path)
        let skin = try await WMPSkinLoader().load(from: url)
        let viewID = skin.views.first { $0.id.caseInsensitiveCompare("vPlayer") == .orderedSame }?.id
            ?? skin.views[0].id
        XCTAssertEqual(skin.scripts.filter { $0.status == .available }.count, skin.scriptSources.count)
        let base = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: viewID)
        let suite = "WMPPhase5Tests.corpus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let session = WMPPhase5Session(runtime: WMPJScriptRuntime(helperURL: helperURL, timeout: 1),
            preferences: WMPPreferenceStore(skinData: try Data(contentsOf: url), defaults: defaults))
        let sizes = [base.resizeLimits.minimum, base.canvasSize,
            base.resizeLimits.clamp(.init(width: base.canvasSize.width + 160, height: base.canvasSize.height + 100))]
        var resolvedCounts: [Int] = []
        for size in sizes {
            let output = await session.transact(skin: skin, viewID: viewID, size: size,
                snapshot: WMPHostSnapshot(), event: .init(name: "load", targetID: viewID,
                    handlers: WMPMainWindowController.handlers(in: skin, event: "load", targetID: nil)))
            XCTAssertFalse(output.diagnostics.contains { $0.code == WMPPhase0DiagnosticCode.scriptTimedOut.rawValue
                || $0.code == WMPPhase0DiagnosticCode.scriptCrashed.rawValue })
            let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: viewID,
                requestedSize: size, overrides: output.overrides)
            resolvedCounts.append(scene.metrics.resolvedNodeCount)
        }
        XCTAssertEqual(resolvedCounts.count, 3)
        XCTAssertTrue(resolvedCounts.allSatisfy { $0 > 0 })
    }

    private func success(_ result: Result<WMPJScriptTransaction, WMPPhase0Diagnostic>,
                         file: StaticString = #filePath, line: UInt = #line) throws -> WMPJScriptTransaction {
        switch result {
        case let .success(value): return value
        case let .failure(error): XCTFail(error.description, file: file, line: line); throw error
        }
    }

    private func fixtureScript(_ name: String) throws -> String {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin")
        return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
