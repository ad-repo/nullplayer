import XCTest
@testable import NullPlayer

/// Phase 87 — the waveform seeker a WACUP-era skin reserves and the host fills (BB18).
///
/// The item was filed as blocked by the skin: `Use integrated Waveform Seeker` is created by
/// `wacup_checker.maki` only when the koopa.ini probe succeeds, that probe must keep failing (B37),
/// and so the setting is never registered. Re-measured 2026-08-30, that is true and irrelevant.
/// Reading Big Bento's own bytecode (`RENDER_DISASM=@player-normal-group`) shows the layout's
/// `onTimer` gating the strip on
///
/// ```
/// System.isNamedWindowVisible("{E124F4D6-…}")
///   && wdh.waveseeker.getXmlParam("hold") == "{E124F4D6-…}"
/// ```
///
/// — the **component-discovery handshake**, not the setting. Nothing in the skin ever writes `hold`;
/// the holder ships `hold="none" autoavailable="1"`, which is Wasabi for "the host may claim this".
/// So the capability needs no dialect concept and no impersonation: we supply a component, which is
/// what the protocol is for.
///
/// Three things had to be true, and each of them independently kept the strip invisible:
///
/// 1. **The claim** — stamping the GUID into `hold` (`WinampModernAvailableComponents`).
/// 2. **`isNamedWindowVisible`** — it answered a blanket `false`, so the gate failed whatever `hold`
///    said.
/// 3. **The z-order** — the skin backs the strip with its *own* layer, declared after the holder and
///    shown by its timer **because** the component was accepted. Drawn inline at the holder's
///    position, our waveform went under a full-width dark panel and measured a uniform
///    `rgb(40,42,48)` — indistinguishable from a strip that never drew.
final class WinampModernPhase87Tests: XCTestCase {

    private let graph = WasabiObjectGraph()

    private func holder(_ id: String, typeName: String = "windowholder",
                        attributes extra: [String: String] = [:]) -> WasabiObject {
        var attributes = ["id": id]
        attributes.merge(extra) { _, new in new }
        return graph.makeObject(typeName: typeName, attributes: attributes,
                                source: WalSourceLocation(path: "/player-normal-group.xml"))
    }

    /// Big Bento's own declaration, verbatim in the parts that matter.
    private func waveseekerHolder() -> WasabiObject {
        holder("wdh.waveseeker", attributes: ["autoavailable": "1", "hold": "none"])
    }

    // MARK: - The claim

    func testClaimsAnAvailableHolderThatNamesAComponentWeSupply() {
        let object = waveseekerHolder()

        let claimed = WinampModernAvailableComponents.claim(in: graph)

        XCTAssertEqual(claimed[object.stableID], .waveformSeeker)
        XCTAssertEqual(object.attributes["hold"], "{E124F4D6-AA3E-4F3D-A813-C2A8CD6501E5}")
    }

    /// The stamped value is what the skin's own comparison reads, so it has to survive the round
    /// trip through the registry the renderer resolves it with.
    func testTheStampedGUIDResolvesBackToTheSeeker() {
        let object = waveseekerHolder()
        WinampModernAvailableComponents.claim(in: graph)

        XCTAssertEqual(WinampModernComponentRegistry.kind(for: object.attributes["hold"]),
                       .waveformSeeker)
    }

    /// **`autoavailable` is the skin's opt-in, and absent is not available.** A holder that says
    /// `hold="none"` and nothing else is a skin reserving space for itself — claiming it would put a
    /// surface in a box the skin never offered.
    func testDoesNotClaimAHolderThatIsNotAvailable() {
        let object = holder("wdh.waveseeker", attributes: ["hold": "none"])

        XCTAssertTrue(WinampModernAvailableComponents.claim(in: graph).isEmpty)
        XCTAssertEqual(object.attributes["hold"], "none")
    }

    /// A holder that already named its component is the skin's decision and outranks ours. This is
    /// the rule that keeps the claim off the other `autoavailable="1"` holders in the corpus — every
    /// one of them (Big Bento's `ghost.playlist` and `wdh.playlist`, BLAKK's playlist and video,
    /// Defix's playlist) already carries a `hold="guid:…"`.
    func testDoesNotClaimAHolderThatAlreadyHoldsSomething() {
        let object = holder("wdh.playlist", attributes: [
            "autoavailable": "1", "hold": "guid:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}",
        ])

        XCTAssertTrue(WinampModernAvailableComponents.claim(in: graph).isEmpty)
        XCTAssertEqual(object.attributes["hold"], "guid:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}")
    }

    /// An available holder we have nothing to put in is left alone, rather than being handed the
    /// one component we do supply. `offered` is deliberately a set of one.
    func testDoesNotClaimAnAvailableHolderNamingSomethingElse() {
        let object = holder("wdh.someplugin", attributes: ["autoavailable": "1", "hold": "none"])

        XCTAssertTrue(WinampModernAvailableComponents.claim(in: graph).isEmpty)
        XCTAssertEqual(object.attributes["hold"], "none")
    }

    /// Only holder *elements*. Big Bento's `<PlaylistPro id="centro.windowholder.playlist1"
    /// autoavailable="1">` carries no `hold` at all and would otherwise satisfy every other test
    /// here; it is a group the skin's own engine fills.
    func testDoesNotClaimANonHolderElement() {
        let object = holder("centro.windowholder.waveseeker", typeName: "PlaylistPro",
                            attributes: ["autoavailable": "1"])

        XCTAssertTrue(WinampModernAvailableComponents.claim(in: graph).isEmpty)
        XCTAssertNil(object.attributes["hold"])
    }

    // MARK: - The GUID

    /// Not a Winamp component GUID — read off Big Bento's bytecode. Both spellings a skin can write
    /// have to resolve, because the comparison in the skin is against the braced upper-case form
    /// while `componentReference` may hand us either.
    func testTheSeekerGUIDResolvesInBothSpellings() {
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "{E124F4D6-AA3E-4F3D-A813-C2A8CD6501E5}"),
                       .waveformSeeker)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "guid:{e124f4d6-aa3e-4f3d-a813-c2a8cd6501e5}"),
                       .waveformSeeker)
        XCTAssertEqual(WinampModernComponentRegistry.canonicalGUID(for: .waveformSeeker),
                       "{E124F4D6-AA3E-4F3D-A813-C2A8CD6501E5}")
    }

    /// The seeker must not be reachable through the fuzzy id rule that serves ClassicPro's engine
    /// holders unless the id actually names it — the rule is applied to every holder in every skin.
    func testHolderIdentifierRuleMatchesOnlyTheSeekersOwnName() {
        XCTAssertEqual(WinampModernComponentRegistry.kindFromHolderIdentifier("wdh.waveseeker"),
                       .waveformSeeker)
        XCTAssertNil(WinampModernComponentRegistry.kindFromHolderIdentifier("wdh.seek"))
        XCTAssertNil(WinampModernComponentRegistry.kindFromHolderIdentifier("seeker.ghost"))
    }

    /// A kind with no standalone window and no bucket icon: the seeker exists only as a strip inside
    /// a skin's own layout, so the routes that open a component window must not offer it.
    func testTheSeekerIsNotARoutedSurface() {
        // `canonicalGUID` answering non-nil is what makes it a *component*; staying out of both
        // catalogs is what keeps it from ever being given a window. `managedKinds` feeds
        // `synthesizableKinds`, so a seeker in it would build an empty window for every skin that
        // does not declare the holder.
        XCTAssertFalse(WinampModernSurfaceInventory.managedKinds.contains(.waveformSeeker))
        XCTAssertFalse(WinampModernSurfaceInventory.routedKinds.contains(.waveformSeeker))
    }
}
