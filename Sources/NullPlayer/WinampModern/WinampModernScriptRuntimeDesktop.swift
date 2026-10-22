import AppKit
import CoreGraphics
import Foundation

/// The parts of MAKI's `System` that answer about the desk rather than the player: the clock and
/// date fields, the screen (viewport, monitor, the player's own frame, the pointer), and the
/// windows a script can look up or show by name. Split out of
/// `WinampModernScriptRuntimeSystem.swift`, whose `invokeSystem` asks these after its own switch;
/// see `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    /// A MAKI date argument: seconds since 1970, with 0 (or less) meaning now.
    static func makiDate(_ value: MakiValue) -> Date {
        value.integerValue > 0 ? Date(timeIntervalSince1970: TimeInterval(value.integerValue)) : Date()
    }

    /// The clock and date fields, or nil for any other method.
    func systemClockValue(_ method: String, arguments: [MakiValue]) -> MakiValue? {
        switch method {
        case "getdate": return .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970)))
        // The clock fields beside `getDateYear`, from the same `getDate()` stamp (0 = now). Skin
        // clocks read them in their timer, and the miss aborted the timer and froze the clock.
        // The day fields are C's `tm` fields: a 0-based month and a 0-based weekday (Sunday 0).
        case "getdatehour", "getdatemin", "getdatesec", "getdateday", "getdatemonth", "getdatedow":
            let date = Self.makiDate(arguments[0])
            switch method {
            case "getdatehour": return .integer(Int32(Calendar.current.component(.hour, from: date)))
            case "getdatemin": return .integer(Int32(Calendar.current.component(.minute, from: date)))
            case "getdatesec": return .integer(Int32(Calendar.current.component(.second, from: date)))
            case "getdateday": return .integer(Int32(Calendar.current.component(.day, from: date)))
            case "getdatemonth": return .integer(Int32(Calendar.current.component(.month, from: date) - 1))
            default: return .integer(Int32(Calendar.current.component(.weekday, from: date) - 1))
            }
        case "getdatedst":
            return .integer(TimeZone.current.isDaylightSavingTime(for: Self.makiDate(arguments[0])) ? 1 : 0)
        // The locale's short and long date, as Winamp's `formatDate`/`formatLongDate` print them.
        case "formatdate", "formatlongdate":
            let formatter = DateFormatter()
            formatter.dateStyle = method == "formatdate" ? .short : .long
            formatter.timeStyle = .none
            return .string(formatter.string(from: Self.makiDate(arguments[0])))
        // The time of day, `h:mm:ss`, the shape `integerToLongTime` prints.
        case "datetolongtime":
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: Self.makiDate(arguments[0]))
            return .string(String(format: "%d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0))
        // Milliseconds since local midnight: cPro2 shows it as its stopped clock through
        // `integerToLongTime`, and the epoch count read as 415 hours.
        case "gettimeofday":
            let now = Date()
            return .integer(Int32(now.timeIntervalSince(Calendar.current.startOfDay(for: now)) * 1000))
        case "getdatedoy":
            return .integer(Int32(Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0))
        case "getdateyear":
            // Years since 1900, as C's `tm_year`. Pinned by the engine's own use of it: `cproabout.m`
            // computes an age as `1899 + getDateYear(...) - birthYear` (+1 once the birthday has
            // passed) and leap-year-tests it with `% 4`, both of which are only correct on that scale.
            return .integer(Int32(Calendar.current.component(.year, from: Self.makiDate(arguments[0])) - 1900))
        default: return nil
        }
    }

    /// The screen, the player's frame on it and the pointer, or nil for any other method.
    func systemScreenValue(_ method: String, arguments: [MakiValue]) -> MakiValue? {
        switch method {
        // The viewport is Winamp's *work area* — the screen minus its taskbars — so here the visible
        // frame, below the menu bar and clear of the Dock. 1010_Fullscreen sizes its window to it:
        // answered with the whole display, it asked for a 1169-tall window at y=0 on a 1130-tall
        // work area, and the (0, 0) it wrote read as a round trip (B61), so it never moved either.
        case "getviewportwidth", "getviewportwidthfromguiobject":
            return .integer(Int32(Self.workArea(of: NSScreen.main).width))
        case "getviewportheight", "getviewportheightfromguiobject":
            return .integer(Int32(Self.workArea(of: NSScreen.main).height))
        case "getviewportleft", "getviewportleftfromguiobject":
            return .integer(Int32(Self.workArea(of: NSScreen.main).minX))
        case "getviewporttop", "getviewporttopfromguiobject":
            return .integer(Int32(Self.workArea(of: NSScreen.main).minY))
        // The display holding the point, in Winamp's top-left screen space. The stock `tooltips.m`
        // keeps its tip on that display (B195); a point on no display answers the main one.
        case "getviewportleftfrompoint", "getviewporttopfrompoint",
             "getviewportwidthfrompoint", "getviewportheightfrompoint":
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let point = CGPoint(x: Int(arguments[0].integerValue),
                                y: Int(primaryHeight) - Int(arguments[1].integerValue))
            let area = Self.workArea(of: NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)
            let value: CGFloat
            switch method {
            case "getviewportleftfrompoint": value = area.minX
            case "getviewporttopfrompoint": value = area.minY
            case "getviewportwidthfrompoint": value = area.width
            default: value = area.height
            }
            return .integer(Int32(value))
        // The monitor is the whole display containing the skin's player window. Do not derive this
        // from `NSScreen.main`: that is the primary display, not necessarily the one the skin is on.
        // The controller answers in logical screen points so Retina backing pixels never enter MAKI
        // geometry. The direct AppKit lookup is only the headless/unwired fallback.
        case "getmonitorwidth":
            return .integer(Self.screenDimension(hooks.monitorSizeRequested?()?.width
                                                  ?? NSScreen.main?.frame.width))
        case "getmonitorheight":
            return .integer(Self.screenDimension(hooks.monitorSizeRequested?()?.height
                                                  ?? NSScreen.main?.frame.height))
        case "getmonitorleft", "getmonitortop": return .integer(0)
        case "getcurappleft": return .integer(Self.appFrameDimension(playerWindowFrame?.minX))
        case "getcurapptop": return .integer(Self.appFrameDimension(playerWindowFrame?.minY))
        case "getcurappwidth": return .integer(Self.appFrameDimension(playerWindowFrame?.width))
        case "getcurappheight": return .integer(Self.appFrameDimension(playerWindowFrame?.height))
        case "getmouseposx": return .integer(Int32(clamping: Int((hooks.mousePositionRequested?().x ?? 0).rounded())))
        case "getmouseposy": return .integer(Int32(clamping: Int((hooks.mousePositionRequested?().y ?? 0).rounded())))
        // The monitor holding the object, answered the way `getMonitorWidth` is for the player.
        case "getmonitorwidthfromguiobject":
            return .integer(Self.screenDimension(hooks.monitorSizeRequested?()?.width ?? NSScreen.main?.frame.width))
        case "getmonitorheightfromguiobject":
            return .integer(Self.screenDimension(hooks.monitorSizeRequested?()?.height ?? NSScreen.main?.frame.height))
        case "getmonitorleftfromguiobject", "getmonitortopfromguiobject": return .integer(0)
        default: return nil
        }
    }

    /// The windows and components a script looks up or shows by name, or nil for any other method.
    func systemWindowValue(_ method: String, arguments: [MakiValue]) throws -> MakiValue? {
        switch method {
        // A Winamp component by GUID. Winamp's `Wac` lets a script send the component private
        // commands; none of NullPlayer's components takes one, so the object exists and
        // `sendCommand` answers 0, "not handled" (Zygote's `sysfunc.m` fetches the main and playlist
        // components at load and the miss aborted it).
        case "getwac": return dynamicValue(role: .wac(guid: arguments[0].stringValue))
        // The skin's own `<browser>`, the one `navigateUrlBrowser` lands in.
        case "getmainbrowser":
            return objectValue(loadedSkin.runtime.graph.allObjectsUnordered.first(where: WasabiSceneRenderer.isBrowserElement))
        case "popmainbrowser":
            guard let browser = loadedSkin.runtime.graph.allObjectsUnordered.first(where: WasabiSceneRenderer.isBrowserElement),
                  let container = ancestor(of: browser, type: .container) else { return .null }
            return try setVisible(container, true)
        // `showWindow(guid or group id, preferred container, transient)`: a component GUID opens that
        // component's window (Big Bento's "show playing track" opens the playlist with `guid:pl`); a
        // group id shows the container that holds it. Answers the object it showed.
        case "showwindow":
            let name = arguments[0].stringValue
            let graph = loadedSkin.runtime.graph
            if let kind = WinampModernComponentRegistry.kind(for: name) {
                hooks.componentShowRequested?(kind)
                return objectValue(graph.allObjectsUnordered.first { WasabiSceneRenderer.componentKind(of: $0) == kind })
            }
            guard let object = graph.allObjectsUnordered.first(where: { $0.xmlID?.caseInsensitiveCompare(name) == .orderedSame }),
                  let container = object.tag.is(.container)
                    ? object : ancestor(of: object, type: .container) else { return .null }
            _ = try setVisible(container, true)
            return objectValue(object)
        default: return nil
        }
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
}
