import Foundation
import XCTest
@testable import NullPlayer

/// **W176 — a `.wmz` opens on the nag panel it declares ahead of its player.**
///
/// `upgradeView` and `versionView` are views the *host* opens, never the user: the "your Windows
/// Media Player is too old to run this skin" notice a 2002 skin shows a player it does not like.
/// WMP shows one only when it has decided to, and nothing in any of these skins has a control that
/// reaches it.
///
/// They are otherwise ordinary views — they lay out, they have a canvas — so the candidate walk
/// presented one wherever its fallback reached it first. Five corpus archives declare one and
/// **every one of them declares it ahead of the view it means by the player**: `Dreamcatcher`,
/// `xsn_sports` and `T3-Skynet_Media_Player` first of all, `Halo 2` second, `WALL-E` third. A skin
/// whose dispatcher posts no `openView` at load falls through to document order and lands there.
///
/// Reported on `WALL-E`, whose `controlView` opens its player from its **timer** rather than its
/// `onLoad` — `checkRemoteViewStatus()` calls `theme.openView('mainView')` on the first tick where
/// `delayPop` is true — so at the moment the walk runs the dispatcher has posted nothing at all.
/// Measured before the fix: the window list was player 382x298 (`upgradeView`) *plus* `mainView`
/// 392x298, with `wmpSkinViewID` persisting as `upgradeView`.
@MainActor
final class WMPNoticeViewTests: XCTestCase {

    /// `WALL-E`'s declaration order. The preview thumbnail, the windowless dispatcher, the notice,
    /// and the player last.
    private let walle = ["previewView", "controlView", "upgradeView", "mainView"]

    /// `xsn_sports`, `Dreamcatcher` and `T3-Skynet_Media_Player` all declare the notice **first**,
    /// which is the worst case for a document-order fallback.
    private let xsn = ["versionView", "upgradeView", "mainView", "plView", "eqView", "visView",
                       "videoView", "msgView"]

    // MARK: - The report

    /// The walk reaches `mainView` rather than `upgradeView`, which is the whole of the fix.
    func testTheNoticeViewSortsBehindTheRealPlayerInDocumentOrder() {
        let candidates = WMPMainWindowController.startupCandidates(
            persisted: nil, declared: nil, declarationOrder: walle)
        let notice = try? XCTUnwrap(candidates.firstIndex(of: "upgradeView"))
        let player = try? XCTUnwrap(candidates.firstIndex(of: "mainView"))
        XCTAssertNotNil(notice)
        XCTAssertNotNil(player)
        XCTAssertLessThan(player!, notice!,
                          "WALL-E declares upgradeView third and mainView fourth, so document "
                          + "order alone opens the nag panel and leaves the player beside it")
    }

    /// Both spellings, and from the front of the list as well as the middle.
    func testBothNoticeSpellingsSortBehindEveryOrdinaryView() {
        let candidates = WMPMainWindowController.startupCandidates(
            persisted: nil, declared: nil, declarationOrder: xsn)
        let ordinary = xsn.filter { !["versionView", "upgradeView"].contains($0) }
        for name in ordinary {
            for notice in ["versionView", "upgradeView"] {
                XCTAssertLessThan(candidates.firstIndex(of: name)!,
                                  candidates.firstIndex(of: notice)!,
                                  "\(name) must outrank \(notice)")
            }
        }
    }

    /// **The persisted slot is refused too.** Landing on the notice is how it came to be persisted,
    /// so honouring `wmpSkinViewID` there would make the defect survive its own fix on every launch
    /// after the first — which is exactly what the live measurement found on disk.
    func testAPersistedNoticeViewIsNotHonouredAsTheStartupView() {
        let candidates = WMPMainWindowController.startupCandidates(
            persisted: "upgradeView", declared: nil, declarationOrder: walle)
        XCTAssertEqual(candidates.first, "vPlayer",
                       "a persisted notice view must not seed the walk at all")
        XCTAssertLessThan(candidates.firstIndex(of: "mainView")!,
                          candidates.firstIndex(of: "upgradeView")!)
    }

    /// The ranks this change must not disturb: the user's own view first, then the skin's declared
    /// one, then `vPlayer`, then document order (W153).
    func testAnOrdinaryPersistedViewStillOutranksEverythingElse() {
        let candidates = WMPMainWindowController.startupCandidates(
            persisted: "eqView", declared: "mainView", declarationOrder: xsn)
        XCTAssertEqual(Array(candidates.prefix(3)), ["eqView", "mainView", "vPlayer"],
                       "persisted, then <THEME currentViewID>, then vPlayer — unchanged by W176")
    }

    /// **A skin stating the notice on purpose is still honoured.** `<THEME currentViewID>` is the
    /// skin saying which view it opens in; the refusal is of the walk *choosing* one on its behalf.
    func testASkinThatDeclaresItsNoticeViewOutrightStillGetsIt() {
        let candidates = WMPMainWindowController.startupCandidates(
            persisted: nil, declared: "upgradeView", declarationOrder: walle)
        XCTAssertEqual(candidates.first, "upgradeView")
    }

    /// Sorted last, never dropped: a skin whose only view is a notice must still open a window.
    func testASkinWhoseOnlyViewIsANoticeStillHasACandidate() {
        let candidates = WMPMainWindowController.startupCandidates(
            persisted: nil, declared: nil, declarationOrder: ["upgradeView"])
        XCTAssertTrue(candidates.contains("upgradeView"),
                      "the notice is ranked last, not excluded — one is better than no window")
    }

    /// A skin with no notice view at all — 180 of the 185 installed archives — must produce exactly
    /// the list it produced before this change.
    func testASkinWithNoNoticeViewIsUnchanged() {
        let corona = ["vPlayer", "plView", "eqView", "vTiny"]
        XCTAssertEqual(
            WMPMainWindowController.startupCandidates(persisted: "vPlayer", declared: nil,
                                                      declarationOrder: corona),
            ["vPlayer", "vPlayer"] + corona,
            "the persisted seed and vPlayer both stay; the walk folds the duplicates itself")
    }

    // MARK: - The predicate

    func testTheNoticePredicateMatchesBothSpellingsCaseInsensitively() {
        for name in ["upgradeView", "UPGRADEVIEW", "versionView", "VersionView"] {
            XCTAssertTrue(WMPDeclaredHostState.isHostOpenedNotice(viewID: name), name)
        }
    }

    /// The names it must not reach. `previewView` and `mediaSwitcherView` are host-opened too, but
    /// they blank themselves in their own `onLoad` and the collapse rule already handles them — and
    /// `infoView` is the skin's own about panel, which the user *does* open.
    func testTheNoticePredicateMatchesNothingElseTheCorpusDeclares() {
        for name in ["mainView", "vPlayer", "previewView", "controlView", "mediaSwitcherView",
                     "infoView", "plView", "eqView", "videoView", "msgView", "upgrade", "version"] {
            XCTAssertFalse(WMPDeclaredHostState.isHostOpenedNotice(viewID: name), name)
        }
    }
}
