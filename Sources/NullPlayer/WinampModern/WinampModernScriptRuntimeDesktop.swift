import AppKit
import CoreGraphics
import Foundation

/// The parts of MAKI's `System` that answer about the desk rather than the player: the clock and
/// date fields, the screen (viewport, monitor, the player's own frame, the pointer) and the
/// windows a script can look up or show by name. Split out of
/// `WinampModernScriptRuntimeSystem.swift`, whose `invokeSystem` asks these after its own table;
/// see `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    /// A MAKI date argument: seconds since 1970, with 0 (or less) meaning now.
    static func makiDate(_ value: MakiValue) -> Date {
        value.integerValue > 0 ? Date(timeIntervalSince1970: TimeInterval(value.integerValue)) : Date()
    }

    /// A screen's work area in Winamp's space: top-left origin on the primary display, the menu bar
    /// and the Dock taken out. What MAKI's `getViewport*` answer.
    static func workArea(of screen: NSScreen?) -> CGRect {
        guard let screen else { return .zero }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: primaryHeight - visible.maxY,
                      width: visible.width, height: visible.height)
    }

    /// The clock and date fields.
    static let systemClockMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        table.add("getdate", 0) { runtime, call in
            .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970)))
        }
        // The clock fields beside `getDateYear`, from the same `getDate()` stamp (0 = now). Skin
        // clocks read them in their timer, and the miss aborted the timer and froze the clock.
        // The day fields are C's `tm` fields: a 0-based month and a 0-based weekday (Sunday 0).
        let clockFields: [String: (Date) -> Int] = [
            "getdatehour": { Calendar.current.component(.hour, from: $0) },
            "getdatemin": { Calendar.current.component(.minute, from: $0) },
            "getdatesec": { Calendar.current.component(.second, from: $0) },
            "getdateday": { Calendar.current.component(.day, from: $0) },
            "getdatemonth": { Calendar.current.component(.month, from: $0) - 1 },
            "getdatedow": { Calendar.current.component(.weekday, from: $0) - 1 },
            // 0-based like `tm_yday` ("0-365", `std.mi`). Clock V2.76 numbers its calendar's weeks
            // from it, one stamp per row; read from now, every row printed this week's number.
            "getdatedoy": { (Calendar.current.ordinality(of: .day, in: .year, for: $0) ?? 1) - 1 },
        ]
        for (name, field) in clockFields {
            table.add(name, 1) { runtime, call in
                .integer(Int32(field(WinampModernScriptRuntime.makiDate(call.arguments[0]))))
            }
        }
        table.add("getdatedst", 1) { runtime, call in
            let date = WinampModernScriptRuntime.makiDate(call.arguments[0])
            return .integer(TimeZone.current.isDaylightSavingTime(for: date) ? 1 : 0)
        }
        // The locale's short and long date, as Winamp's `formatDate`/`formatLongDate` print them.
        table.add(["formatdate", "formatlongdate"], 1) { runtime, call in
            let formatter = DateFormatter()
            formatter.dateStyle = call.method == "formatdate" ? .short : .long
            formatter.timeStyle = .none
            return .string(formatter.string(from: WinampModernScriptRuntime.makiDate(call.arguments[0])))
        }
        // The time of day, `h:mm:ss`, the shape `integerToLongTime` prints.
        table.add("datetolongtime", 1) { runtime, call in
            let parts = Calendar.current.dateComponents([.hour, .minute, .second],
                                                        from: WinampModernScriptRuntime.makiDate(call.arguments[0]))
            return .string(String(format: "%d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0))
        }
        // Milliseconds since local midnight: cPro2 shows it as its stopped clock through
        // `integerToLongTime`, and the epoch count read as 415 hours.
        table.add("gettimeofday", 0) { runtime, call in
            let now = Date()
            return .integer(Int32(now.timeIntervalSince(Calendar.current.startOfDay(for: now)) * 1000))
        }
        table.add("getdateyear", 1) { runtime, call in
            // Years since 1900, as C's `tm_year`. Pinned by the engine's own use of it: `cproabout.m`
            // computes an age as `1899 + getDateYear(...) - birthYear` (+1 once the birthday has
            // passed) and leap-year-tests it with `% 4`, both of which are only correct on that scale.
            let date = WinampModernScriptRuntime.makiDate(call.arguments[0])
            return .integer(Int32(Calendar.current.component(.year, from: date) - 1900))
        }
        return table
    }()

    /// The screen, the player's frame on it and the pointer.
    static let systemScreenMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        // The viewport is Winamp's *work area* — the screen minus its taskbars — so here the visible
        // frame, below the menu bar and clear of the Dock. 1010_Fullscreen sizes its window to it:
        // answered with the whole display, it asked for a 1169-tall window at y=0 on a 1130-tall
        // work area, and the (0, 0) it wrote read as a round trip (B61), so it never moved either.
        let getviewportwidthBody: MakiMethodDefinition<Void>.Body = { runtime, call in
            return .integer(Int32(WinampModernScriptRuntime.workArea(of: NSScreen.main).width))
        }
        table.add("getviewportwidth", 0, getviewportwidthBody)
        table.add("getviewportwidthfromguiobject", 1, getviewportwidthBody)
        let getviewportheightBody: MakiMethodDefinition<Void>.Body = { runtime, call in
            return .integer(Int32(WinampModernScriptRuntime.workArea(of: NSScreen.main).height))
        }
        table.add("getviewportheight", 0, getviewportheightBody)
        table.add("getviewportheightfromguiobject", 1, getviewportheightBody)
        let getviewportleftBody: MakiMethodDefinition<Void>.Body = { runtime, call in
            return .integer(Int32(WinampModernScriptRuntime.workArea(of: NSScreen.main).minX))
        }
        table.add("getviewportleft", 0, getviewportleftBody)
        table.add("getviewportleftfromguiobject", 1, getviewportleftBody)
        let getviewporttopBody: MakiMethodDefinition<Void>.Body = { runtime, call in
            return .integer(Int32(WinampModernScriptRuntime.workArea(of: NSScreen.main).minY))
        }
        table.add("getviewporttop", 0, getviewporttopBody)
        table.add("getviewporttopfromguiobject", 1, getviewporttopBody)
        // The display holding the point, in Winamp's top-left screen space. The stock `tooltips.m`
        // keeps its tip on that display (B195); a point on no display answers the main one.
        let pointAreaEdges: [String: KeyPath<CGRect, CGFloat>] = [
            "getviewportleftfrompoint": \.minX, "getviewporttopfrompoint": \.minY,
            "getviewportwidthfrompoint": \.width, "getviewportheightfrompoint": \.height,
        ]
        for (name, edge) in pointAreaEdges {
            table.add(name, 2) { runtime, call in
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                let point = CGPoint(x: Int(call.arguments[0].integerValue),
                                    y: Int(primaryHeight) - Int(call.arguments[1].integerValue))
                let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
                return .integer(Int32(WinampModernScriptRuntime.workArea(of: screen)[keyPath: edge]))
            }
        }
        // The **monitor** family, which is the viewport's whole-screen twin: Winamp's viewport is
        // the work area, the monitor is the display it sits on. Big Bento's notifier asks for both
        // one after the other, and its `pledit.maki` sizes the side playlist from
        // `getMonitorWidth()` — so with this unimplemented the `onAction("load_comp")` that moves
        // the playlist beside the player aborted, and with it every option that governs that
        // playlist ("Enlarge Playlist" had nothing left to enlarge). Arity 0, pinned by the four
        // call sites in that skin.
        // The monitor is the whole display containing the skin's player window. Do not derive this
        // from `NSScreen.main`: that is the primary display, not necessarily the one the skin is on.
        // The controller answers in logical screen points so Retina backing pixels never enter MAKI
        // geometry. The direct AppKit lookup is only the headless/unwired fallback.
        table.add("getmonitorwidth", 0) { runtime, call in
            return .integer(WinampModernScriptRuntime.screenDimension(runtime.hooks.monitorSizeRequested?()?.width
                                                  ?? NSScreen.main?.frame.width))
        }
        table.add("getmonitorheight", 0) { runtime, call in
            return .integer(WinampModernScriptRuntime.screenDimension(runtime.hooks.monitorSizeRequested?()?.height
                                                  ?? NSScreen.main?.frame.height))
        }
        table.add(["getmonitorleft", "getmonitortop"], 0) { runtime, call in .integer(0) }
        // The player window's own box. `getCurAppWidth`/`getCurAppHeight` were missing while
        // their two siblings were present, and `two/scripts/presetpos.m` calls all four in one
        // expression — `saveFramePos()` died on the third call, so the F9–F12 preset positions
        // stored nothing and `gotoFramePos` could only ever restore its fallback.
        table.add("getcurappleft", 0) { runtime, call in
            .integer(WinampModernScriptRuntime.appFrameDimension(runtime.playerWindowFrame?.minX))
        }
        table.add("getcurapptop", 0) { runtime, call in
            .integer(WinampModernScriptRuntime.appFrameDimension(runtime.playerWindowFrame?.minY))
        }
        table.add("getcurappwidth", 0) { runtime, call in
            .integer(WinampModernScriptRuntime.appFrameDimension(runtime.playerWindowFrame?.width))
        }
        table.add("getcurappheight", 0) { runtime, call in
            .integer(WinampModernScriptRuntime.appFrameDimension(runtime.playerWindowFrame?.height))
        }
        // Screen-space cursor position, in the same skin-pixel units as the x/y a mouse event
        // hands the script — the knob scripts mix the two in one expression.
        table.add("getmouseposx", 0) { runtime, call in
            .integer(Int32(clamping: Int((runtime.hooks.mousePositionRequested?().x ?? 0).rounded())))
        }
        table.add("getmouseposy", 0) { runtime, call in
            .integer(Int32(clamping: Int((runtime.hooks.mousePositionRequested?().y ?? 0).rounded())))
        }
        // The monitor holding the object, answered the way `getMonitorWidth` is for the player.
        table.add("getmonitorwidthfromguiobject", 1) { runtime, call in
            .integer(WinampModernScriptRuntime.screenDimension(runtime.hooks.monitorSizeRequested?()?.width
                                                                    ?? NSScreen.main?.frame.width))
        }
        table.add("getmonitorheightfromguiobject", 1) { runtime, call in
            .integer(WinampModernScriptRuntime.screenDimension(runtime.hooks.monitorSizeRequested?()?.height
                                                                    ?? NSScreen.main?.frame.height))
        }
        table.add(["getmonitorleftfromguiobject", "getmonitortopfromguiobject"], 1) { runtime, call in
            .integer(0)
        }
        return table
    }()

    /// The windows and components a script looks up or shows by name.
    static let systemWindowMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        // A Winamp component by GUID. Winamp's `Wac` lets a script send the component private
        // commands; none of NullPlayer's components takes one, so the object exists and
        // `sendCommand` answers 0, "not handled" (Zygote's `sysfunc.m` fetches the main and playlist
        // components at load and the miss aborted it).
        table.add("getwac", 1) { runtime, call in
            runtime.dynamicValue(role: .wac(guid: call.arguments[0].stringValue))
        }
        // The skin's own `<browser>`, the one `navigateUrlBrowser` lands in.
        table.add("getmainbrowser", 0) { runtime, call in
            let graph = runtime.loadedSkin.runtime.graph
            return runtime.objectValue(graph.allObjectsUnordered.first(where: WasabiSceneRenderer.isBrowserElement))
        }
        table.add("popmainbrowser", 0) { runtime, call in
            let graph = runtime.loadedSkin.runtime.graph
            guard let browser = graph.allObjectsUnordered.first(where: WasabiSceneRenderer.isBrowserElement),
                  let container = runtime.ancestor(of: browser, type: .container) else { return .null }
            return try runtime.setVisible(container, true)
        }
        // `showWindow(guid or group id, preferred container, transient)`: a component GUID opens that
        // component's window (Big Bento's "show playing track" opens the playlist with `guid:pl`); a
        // group id shows the container that holds it. Answers the object it showed.
        table.add("showwindow", 3) { runtime, call in
            let name = call.arguments[0].stringValue
            let graph = runtime.loadedSkin.runtime.graph
            if let kind = WinampModernComponentRegistry.kind(for: name) {
                runtime.hooks.componentShowRequested?(kind)
                return runtime.objectValue(graph.allObjectsUnordered.first {
                    WasabiSceneRenderer.componentKind(of: $0) == kind
                })
            }
            guard let object = graph.allObjectsUnordered.first(where: {
                      $0.xmlID?.caseInsensitiveCompare(name) == .orderedSame
                  }),
                  let container = object.tag.is(.container)
                    ? object : runtime.ancestor(of: object, type: .container) else { return .null }
            _ = try runtime.setVisible(container, true)
            return runtime.objectValue(object)
        }
        return table
    }()
}
