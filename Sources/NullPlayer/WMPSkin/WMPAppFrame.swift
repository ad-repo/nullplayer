import Foundation

/// The pieces of WMP's own full-mode frame that only belong under a Windows title bar.
///
/// Only the two Redux archives — copies of WMP 8's and 9's own full mode — declare `<APP>`. WMP 8's
/// markup draws a grey `*_border` twin beside every corner and edge of its blue frame
/// (`apptopleft_border.bmp`, `appfillbottom_border.bmp` …), always visible, which squares the
/// shaped frame off into a rectangle. Nothing in the skin hides them, yet the WMP 9 Redux by the
/// same author ships the same bitmaps and places none of the grey ones. They are the fill WMP
/// draws with its title bar on; `app.titleBarVisible` answers false here (`readApp`) and NullPlayer
/// draws no title bar, so they are not drawn. A script that shows one still wins.
///
/// `isKeyedShape` tells them from the blue `appfillleft_border.bmp` strip, which both Redux skins
/// place in the same way: the grey pieces fill the key-coloured corners round the frame, so their
/// own `transparencyColor` cuts pixels away, and the strip has no key pixel at all.
enum WMPAppFrame {
    static func titleBarFill(in view: WMPNode, isKeyedShape: (WMPNode) -> Bool) -> Set<Int> {
        guard view.children.contains(where: declaresApp) else { return [] }
        var found = Set<Int>()
        func walk(_ node: WMPNode) {
            if node.attribute(named: "passthrough")?.rawValue.lowercased() == "true",
               let image = node.attribute(named: "image")?.rawValue.lowercased(),
               image.contains("_border"), isKeyedShape(node) {
                found.insert(node.stableID)
            }
            node.children.forEach(walk)
        }
        walk(view)
        return found
    }

    /// `<APP>` sits inside `svEntireApp` in WMP 8's markup and directly under the view in WMP 9's.
    private static func declaresApp(_ node: WMPNode) -> Bool {
        node.authoredTagName.caseInsensitiveCompare("app") == .orderedSame
            || node.children.contains(where: declaresApp)
    }
}
