import XCTest
import CAvsCore
@testable import NullPlayer

/// The AVS effects whose upstream render path is 32-bit x86 only (inline MMX or a JIT) and that
/// NullPlayer ports to C: each is built into a preset through the editor API and its output
/// checked against a hand-computed result.
final class AvsEffectPortTests: XCTestCase {

    private let width = 64
    private let height = 48

    /// A 3×3 box kernel with scale 9 (not a power of two, so the 16.16 reciprocal path runs)
    /// over a SuperScope dot gives the dot's 3×3 neighbourhood mean on R, G and B.
    func testConvolutionFilterBoxBlursASuperScopeDot() throws {
        let core = try XCTUnwrap(AvsCore())
        let preset = AvsPresetBuilder(core)
        preset.set(preset.root, "Clear", bool: true)
        preset.addDot(x: 0, y: 0)
        let convolution = try preset.add("Convolution Filter")
        for index in 0..<49 {
            let (row, column) = (index / 7, index % 7)
            let inBox = (2...4).contains(row) && (2...4).contains(column)
            preset.set(convolution, "Kernel", "Value", index: index, int: inBox ? 1 : 0)
        }
        preset.set(convolution, "Scale", int: 9)

        preset.setEnabled(convolution, false)
        let source = render(core)
        XCTAssertTrue(source.contains { $0 & 0xFF_FFFF != 0 }, "the SuperScope dot did not draw")
        preset.setEnabled(convolution, true)
        let filtered = render(core)

        var mismatches = 0
        for y in 3..<(height - 3) {
            for x in 3..<(width - 3) {
                var expected: UInt32 = 0
                for channel in 0..<3 {
                    var sum: UInt32 = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            sum += (source[(y + dy) * width + x + dx] >> (8 * channel)) & 0xFF
                        }
                    }
                    expected |= min((sum * (65536 / 9)) >> 16, 255) << (8 * channel)
                }
                if filtered[y * width + x] & 0xFF_FFFF != expected { mismatches += 1 }
            }
        }
        XCTAssertEqual(mismatches, 0)
        XCTAssertNotEqual(filtered.map { $0 & 0xFF_FFFF }, source.map { $0 & 0xFF_FFFF })
    }

    /// One Texer II particle (the built-in 21×21 image) over a grey fill, in every blend mode,
    /// through the scaling renderer and both non-scaling ones (plain and colourised): the
    /// particle changes the frame, and only inside its own box.
    func testTexerIIDrawsItsParticleInEveryBlendMode() throws {
        let variants: [(name: String, resize: Bool, colorize: Bool, halfBox: Int)] = [
            ("unscaled", false, false, 11), ("unscaled colourised", false, true, 11),
            ("scaled", true, true, 22),
        ]
        for variant in variants {
            for mode in Int64(0)...9 {
                let core = try XCTUnwrap(AvsCore())
                let preset = AvsPresetBuilder(core)
                preset.set(preset.root, "Clear", bool: true)
                let fill = try preset.add("Clear Screen")
                preset.set(fill, "Color", color: 0x60_6060)
                preset.set(fill, "Blend Mode", int: 0)  // Replace, not the line blend mode
                let renderMode = try preset.add("Set Render Mode")
                preset.set(renderMode, "Blend", int: mode)
                preset.set(renderMode, "Adjustable Blend", int: 128)
                let texer = try preset.add("Texer II")
                preset.set(texer, "Resize", bool: variant.resize)
                preset.set(texer, "Colorize", bool: variant.colorize)
                preset.set(texer, "Init", string: "n=1;")
                preset.set(texer, "Frame", string: "")
                preset.set(texer, "Beat", string: "")
                preset.set(texer, "Point", string: "x=0;y=0;sizex=2;sizey=2;red=1;green=0.5;blue=0.25;")

                preset.setEnabled(texer, false)
                _ = render(core)  // the line blend mode is global and carries into the next frame
                let background = render(core)
                preset.setEnabled(texer, true)
                let frame = render(core)

                let label = "\(variant.name), blend \(mode)"
                let changed = (0..<(width * height)).filter { frame[$0] & 0xFF_FFFF != background[$0] & 0xFF_FFFF }
                XCTAssertFalse(changed.isEmpty, "\(label): the particle drew nothing")
                let outside = changed.filter {
                    abs($0 % width - width / 2) > variant.halfBox || abs($0 / width - height / 2) > variant.halfBox
                }
                XCTAssertTrue(outside.isEmpty, "\(label): \(outside.count) pixels changed outside the particle")
            }
        }
    }

    /// Text draws its words centred, one at a time, cycling every `Speed` frames.
    func testTextDrawsAndCyclesItsWords() throws {
        let core = try XCTUnwrap(AvsCore())
        let preset = AvsPresetBuilder(core)
        preset.set(preset.root, "Clear", bool: true)
        let text = try preset.add("Text")
        preset.set(text, "Text", string: "I;WWWWW")
        preset.set(text, "Font Size", int: 20)
        preset.set(text, "Speed", int: 2)

        let lit = (0..<6).map { _ in render(core).filter { $0 & 0xFF_FFFF != 0 }.count }
        XCTAssertTrue(lit.allSatisfy { $0 > 0 }, "a frame drew no text: \(lit)")
        XCTAssertEqual(lit[0], lit[1], "a word changed before Speed frames: \(lit)")
        XCTAssertNotEqual(lit[1], lit[2], "'I' and 'WWWWW' lit the same pixels: \(lit)")
        XCTAssertEqual(lit[0], lit[4], "the words do not cycle: \(lit)")
    }

    /// A Text record in Winamp's layout (11 dwords, CHOOSEFONTA, LOGFONTA, the text, 7 dwords)
    /// loads with its font and saves back byte for byte. The root's Clear byte is in the
    /// comparison too: libavs used to drop it on load (`E_Root::swap`).
    func testTextLegacyRecordRoundTripsUnchanged() throws {
        var record = Data()
        func dword(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { record.append(contentsOf: $0) } }
        for v: Int32 in [1, 0x00FF_8000, 0, 1, 0, 0, 0, 8, 2, 12, 30] { dword(v) }  // …50/50, bottom, right
        var chooseFont = [UInt8](repeating: 0, count: 60)
        chooseFont[0] = 60
        chooseFont[20] = 0x41  // Flags: some dialog flags, kept as saved
        record.append(contentsOf: chooseFont)
        var logFont = [UInt8](repeating: 0, count: 60)
        withUnsafeBytes(of: Int32(-24).littleEndian) { logFont.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: Int32(700).littleEndian) { logFont.replaceSubrange(16..<20, with: $0) }
        logFont[20] = 1  // italic
        logFont[26] = 3  // NONANTIALIASED_QUALITY
        logFont.replaceSubrange(28..<35, with: Array("Courier".utf8))
        record.append(contentsOf: logFont)
        let words = Array("one;two;$(reg07:3.1)\0".utf8)
        dword(Int32(words.count))
        record.append(contentsOf: words)
        for v: Int32 in [1, 0x0000_00FF, 5, -10, 2, 1, 0] { dword(v) }

        var preset = Data("Nullsoft AVS Preset 0.2\u{1A}".utf8)
        preset.append(1)  // root: clear every frame
        withUnsafeBytes(of: Int32(28).littleEndian) { preset.append(contentsOf: $0) }  // Text
        withUnsafeBytes(of: Int32(record.count).littleEndian) { preset.append(contentsOf: $0) }
        preset.append(record)

        let core = try XCTUnwrap(AvsCore())
        let saved: [UInt8]? = core.withHandle { handle in
            let bytes = [UInt8](preset)
            guard avs_preset_set_legacy(handle, bytes, bytes.count) else { return nil }
            var length = 0
            guard let out = avs_preset_get_legacy(handle, &length) else { return nil }
            return Array(UnsafeBufferPointer(start: out, count: length))
        }
        XCTAssertEqual(saved, [UInt8](preset))
        XCTAssertTrue(render(core).contains { $0 & 0xFF_FFFF != 0 }, "the loaded Text drew nothing")
    }

    private func render(_ core: AvsCore) -> [UInt32] {
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBufferPointer {
            XCTAssertTrue(core.renderFrame(into: $0.baseAddress!, width: width, height: height),
                          core.lastError)
        }
        return pixels
    }
}

/// Builds a preset in an `AvsCore` through the editor API, addressing effects and parameters by
/// their names in libavs's metadata.
struct AvsPresetBuilder {
    let core: AvsCore

    init(_ core: AvsCore) { self.core = core }

    var root: AVS_Component_Handle { core.withHandle { avs_component_root($0) } }

    /// Appends a component of the named effect to the root.
    @discardableResult
    func add(_ effectName: String) throws -> AVS_Component_Handle {
        let component = core.withHandle { handle -> AVS_Component_Handle in
            var count: UInt32 = 0
            guard let library = avs_effect_library(handle, &count) else { return 0 }
            for effect in UnsafeBufferPointer(start: library, count: Int(count)) {
                var info = AVS_Effect_Info()
                if avs_effect_info(handle, effect, &info), String(cString: info.name) == effectName {
                    return avs_component_create(handle, effect, 0, AVS_COMPONENT_POSITION_DONTCARE)
                }
            }
            return 0
        }
        guard component != 0 else { throw XCTSkip("no effect named \(effectName)") }
        return component
    }

    /// A white single-point SuperScope at (x, y) in AVS's -1…1 space.
    func addDot(x: Double, y: Double) {
        guard let scope = try? add("SuperScope") else { return XCTFail("no SuperScope") }
        set(scope, "Init", string: "n=1;")
        set(scope, "Frame", string: "")
        set(scope, "Beat", string: "")
        set(scope, "Point", string: "x=\(x);y=\(y);")
        set(scope, "Draw Mode", int: 0)
        set(scope, "Colors", "Color", index: 0, color: 0xFF_FFFF)
    }

    func setEnabled(_ component: AVS_Component_Handle, _ enabled: Bool) {
        core.withHandle { handle in
            var properties = AVS_Component_Properties()
            _ = avs_component_properties_get(handle, component, &properties)
            properties.enabled = enabled
            XCTAssertTrue(avs_component_properties_set(handle, component, properties))
        }
    }

    func set(_ component: AVS_Component_Handle, _ name: String, bool value: Bool) {
        write(component, name) { avs_parameter_set_bool($0, component, $1, value, $2, $3) }
    }

    func set(_ component: AVS_Component_Handle, _ name: String, int value: Int64) {
        write(component, name) { avs_parameter_set_int($0, component, $1, value, $2, $3) }
    }

    func set(_ component: AVS_Component_Handle, _ name: String, color value: UInt64) {
        write(component, name) { avs_parameter_set_color($0, component, $1, value, $2, $3) }
    }

    func set(_ component: AVS_Component_Handle, _ name: String, string value: String) {
        write(component, name) { avs_parameter_set_string($0, component, $1, value, $2, $3) }
    }

    func set(_ component: AVS_Component_Handle, _ list: String, _ name: String, index: Int,
             int value: Int64) {
        write(component, list, name, index: index) {
            avs_parameter_set_int($0, component, $1, value, $2, $3)
        }
    }

    func set(_ component: AVS_Component_Handle, _ list: String, _ name: String, index: Int,
             color value: UInt64) {
        write(component, list, name, index: index) {
            avs_parameter_set_color($0, component, $1, value, $2, $3)
        }
    }

    // MARK: - Lookup

    private typealias Setter = (AVS_Handle, AVS_Parameter_Handle, UInt32,
                                UnsafeMutablePointer<Int64>?) -> Bool

    private func write(_ component: AVS_Component_Handle, _ name: String, _ setter: Setter) {
        core.withHandle { handle in
            let effect = avs_component_effect(handle, component)
            guard let parameter = Self.parameter(handle, effect, named: name, in: Self.topLevel(handle, effect))
            else { return XCTFail("no parameter \(name)") }
            XCTAssertTrue(setter(handle, parameter, 0, nil), "\(name): \(String(cString: avs_error_str(handle)))")
        }
    }

    private func write(_ component: AVS_Component_Handle, _ list: String, _ name: String, index: Int,
                       _ setter: Setter) {
        core.withHandle { handle in
            let effect = avs_component_effect(handle, component)
            guard let listParameter = Self.parameter(handle, effect, named: list, in: Self.topLevel(handle, effect))
            else { return XCTFail("no list \(list)") }
            var listInfo = AVS_Parameter_Info()
            _ = avs_parameter_info(handle, effect, listParameter, &listInfo)
            let children = Array(UnsafeBufferPointer(start: listInfo.children, count: Int(listInfo.children_length)))
            guard let parameter = Self.parameter(handle, effect, named: name, in: children)
            else { return XCTFail("no parameter \(list)/\(name)") }
            while avs_parameter_list_length(handle, component, listParameter, 0, nil) <= index {
                guard avs_parameter_list_element_add(handle, component, listParameter, -1, 0, nil, 0, nil) else {
                    return XCTFail("\(list): cannot add element \(index)")
                }
            }
            var indices = [Int64(index)]
            XCTAssertTrue(setter(handle, parameter, 1, &indices),
                          "\(list)[\(index)]/\(name): \(String(cString: avs_error_str(handle)))")
        }
    }

    private static func topLevel(_ handle: AVS_Handle, _ effect: AVS_Effect_Handle) -> [AVS_Parameter_Handle] {
        var info = AVS_Effect_Info()
        guard avs_effect_info(handle, effect, &info), let parameters = info.parameters else { return [] }
        return Array(UnsafeBufferPointer(start: parameters, count: Int(info.parameters_length)))
    }

    private static func parameter(_ handle: AVS_Handle, _ effect: AVS_Effect_Handle, named name: String,
                                  in parameters: [AVS_Parameter_Handle]) -> AVS_Parameter_Handle? {
        parameters.first { parameter in
            var info = AVS_Parameter_Info()
            return avs_parameter_info(handle, effect, parameter, &info) && String(cString: info.name) == name
        }
    }
}
