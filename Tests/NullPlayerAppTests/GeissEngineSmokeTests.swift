import XCTest
import CGeissCore

/// Phase-4 closeout smoke test for the Geiss C ABI. Verifies that the full
/// engine lifecycle (create → addPCM → setSpectrum → render → palette →
/// destroy) runs end-to-end without crashing, that the rendered indexed
/// framebuffer accumulates non-zero pixels (i.e. the upstream effect engine
/// actually fired), and that the palette is populated with non-black entries.
final class GeissEngineSmokeTests: XCTestCase {

    func testGeissCoreLifecycleProducesNonEmptyFrame() {
        let width: Int32 = 256
        let height: Int32 = 192
        let pixels = Int(width) * Int(height)

        guard let core = GeissCore_create(width, height) else {
            XCTFail("GeissCore_create returned nil — engine init failed")
            return
        }
        defer { GeissCore_destroy(core) }

        // Push a few frames of synthetic audio so the audio-driven branches
        // (RenderDots / RenderWave) have something to react to.
        var pcm = [Float](repeating: 0, count: 576)
        var spectrum = [Float](repeating: 0, count: 576)
        for i in 0..<pcm.count {
            pcm[i] = sinf(Float(i) * 0.05) * 0.6
            spectrum[i] = abs(pcm[i])
        }

        var indexBuf = [UInt8](repeating: 0, count: pixels)
        var rgba = [UInt8](repeating: 0, count: 256 * 4)

        // Geiss randomizes the active mode at startup. Some modes
        // (e.g. mode 10 with min_effects=0) can legitimately render zero
        // pixels for many frames at a time. To keep the smoke test robust,
        // cycle through several modes until effects activate, then render.
        var sawNonZero = false
        outer: for _ in 0..<25 {
            // Render a small batch of frames at the current mode.
            for _ in 0..<10 {
                pcm.withUnsafeBufferPointer { buf in
                    GeissCore_addPCM(core, buf.baseAddress, Int32(buf.count))
                }
                spectrum.withUnsafeBufferPointer { buf in
                    GeissCore_setSpectrum(core, buf.baseAddress, Int32(buf.count))
                }
                indexBuf.withUnsafeMutableBufferPointer { buf in
                    GeissCore_render(core, buf.baseAddress)
                }
                if indexBuf.contains(where: { $0 != 0 }) {
                    sawNonZero = true
                    break outer
                }
            }
            // No pixels yet — advance to the next mode and try again. Each
            // call to GeissCore_nextEffect kicks off a rush-map regen that
            // takes a few frames to apply.
            GeissCore_nextEffect(core)
        }

        rgba.withUnsafeMutableBufferPointer { buf in
            GeissCore_palette(core, buf.baseAddress)
        }

        if !sawNonZero {
            var diag = GeissCoreDiag()
            GeissCore_diag(core, &diag)
            print("DIAG: mode=\(diag.active_mode) new_mode=\(diag.new_mode) y_map_pos=\(diag.y_map_pos) frames_this_mode=\(diag.frames_this_mode)")
            print("DIAG: effects=\(diag.effects) gXC=\(diag.gXC) gYC=\(diag.gYC) iDispBits=\(diag.iDispBits) FXW=\(diag.FXW) FXH=\(diag.FXH)")
        }
        XCTAssertTrue(
            sawNonZero,
            "GeissCore_render produced an all-black framebuffer for 250 frames across 25 mode changes — the effect engine never fired."
        )

        // Palette must contain at least one non-black RGB triplet.
        var hasColour = false
        for i in 0..<256 {
            let r = rgba[i * 4 + 0]
            let g = rgba[i * 4 + 1]
            let b = rgba[i * 4 + 2]
            if r != 0 || g != 0 || b != 0 {
                hasColour = true
                break
            }
        }
        XCTAssertTrue(
            hasColour,
            "GeissCore_palette returned an all-black palette — FX_Random_Palette / PutPalette pump did not run."
        )

        // Effect-name accessor should return a non-empty C string.
        if let cstr = GeissCore_currentEffectName(core) {
            let name = String(cString: cstr)
            XCTAssertFalse(name.isEmpty, "GeissCore_currentEffectName returned an empty string.")
        } else {
            XCTFail("GeissCore_currentEffectName returned nil.")
        }
    }

    func testGeissCoreNextEffectAdvancesMode() {
        guard let core = GeissCore_create(128, 96) else {
            XCTFail("GeissCore_create failed")
            return
        }
        defer { GeissCore_destroy(core) }

        let firstName: String = {
            guard let cstr = GeissCore_currentEffectName(core) else { return "" }
            return String(cString: cstr)
        }()

        GeissCore_nextEffect(core)

        // GeissCore_nextEffect updates `new_mode`; the active `mode` only
        // updates after GenerateChunkOfNewMap completes a full chunk inside
        // the next render. Run several frames so the rush-map regen lands.
        var indexBuf = [UInt8](repeating: 0, count: 128 * 96)
        for _ in 0..<60 {
            indexBuf.withUnsafeMutableBufferPointer { buf in
                GeissCore_render(core, buf.baseAddress)
            }
        }

        let afterName: String = {
            guard let cstr = GeissCore_currentEffectName(core) else { return "" }
            return String(cString: cstr)
        }()

        XCTAssertNotEqual(firstName, afterName,
                          "GeissCore_nextEffect did not advance the active mode within 60 frames.")
    }

    func testGeissCoreMarksSilenceIdleAndAudioActive() {
        guard let core = GeissCore_create(128, 96) else {
            XCTFail("GeissCore_create failed")
            return
        }
        defer { GeissCore_destroy(core) }

        let silence = [Float](repeating: 0, count: 576)
        var audio = [Float](repeating: 0, count: 576)
        for i in 0..<audio.count {
            audio[i] = sinf(Float(i) * 0.08) * 0.8
        }
        var indexBuf = [UInt8](repeating: 0, count: 128 * 96)

        silence.withUnsafeBufferPointer { pcm in
            GeissCore_addPCM(core, pcm.baseAddress, Int32(pcm.count))
        }
        indexBuf.withUnsafeMutableBufferPointer { buf in
            GeissCore_render(core, buf.baseAddress)
        }

        var idleDiag = GeissCoreDiag()
        GeissCore_diag(core, &idleDiag)
        XCTAssertNotEqual(idleDiag.sound_ready, 0)
        XCTAssertNotEqual(idleDiag.sound_active, 0)
        XCTAssertNotEqual(idleDiag.sound_empty, 0)

        for _ in 0..<5 {
            audio.withUnsafeBufferPointer { pcm in
                GeissCore_addPCM(core, pcm.baseAddress, Int32(pcm.count))
            }
            indexBuf.withUnsafeMutableBufferPointer { buf in
                GeissCore_render(core, buf.baseAddress)
            }
        }

        var activeDiag = GeissCoreDiag()
        GeissCore_diag(core, &activeDiag)
        XCTAssertNotEqual(activeDiag.sound_ready, 0)
        XCTAssertNotEqual(activeDiag.sound_active, 0)
        XCTAssertEqual(activeDiag.sound_empty, 0)
        XCTAssertGreaterThan(activeDiag.current_vol, 0)
    }

    func testGeissConfigRoundTripAllFields() {
        guard let core = GeissCore_create(128, 96) else {
            XCTFail("GeissCore_create failed")
            return
        }
        defer { GeissCore_destroy(core) }

        var cfg = GeissCoreConfig()
        cfg.sensitivity = 2.0
        cfg.gamma = 150
        cfg.beatDetection = 0
        cfg.syncColorToSound = 1
        cfg.slideShift = 0
        cfg.modeLocked = 1
        cfg.paletteLocked = 1
        cfg.autoSwitchSeconds = 15
        cfg.visMode = 1

        GeissCore_setConfig(core, &cfg)

        var readback = GeissCoreConfig()
        GeissCore_getConfig(core, &readback)

        XCTAssertEqual(readback.sensitivity, 2.0, accuracy: 0.001, "sensitivity mismatch")
        XCTAssertEqual(readback.gamma, 150, "gamma mismatch")
        XCTAssertEqual(readback.beatDetection, 0, "beatDetection mismatch")
        XCTAssertEqual(readback.syncColorToSound, 1, "syncColorToSound mismatch")
        XCTAssertEqual(readback.slideShift, 0, "slideShift mismatch")
        XCTAssertEqual(readback.modeLocked, 1, "modeLocked mismatch")
        XCTAssertEqual(readback.paletteLocked, 1, "paletteLocked mismatch")
        XCTAssertEqual(readback.autoSwitchSeconds, 15, "autoSwitchSeconds mismatch")
        XCTAssertEqual(readback.visMode, 1, "visMode mismatch")
    }

    func testGeissModeLockPreventsActiveModeChange() {
        guard let core = GeissCore_create(128, 96) else {
            XCTFail("GeissCore_create failed")
            return
        }
        defer { GeissCore_destroy(core) }

        var cfg = GeissCoreConfig()
        GeissCore_getConfig(core, &cfg)
        cfg.modeLocked = 1
        GeissCore_setConfig(core, &cfg)

        var diag = GeissCoreDiag()
        GeissCore_diag(core, &diag)
        let initialMode = diag.active_mode

        let silence = [Float](repeating: 0, count: 576)
        var indexBuf = [UInt8](repeating: 0, count: 128 * 96)

        for _ in 0..<300 {
            silence.withUnsafeBufferPointer { pcm in
                GeissCore_addPCM(core, pcm.baseAddress, Int32(pcm.count))
            }
            indexBuf.withUnsafeMutableBufferPointer { buf in
                GeissCore_render(core, buf.baseAddress)
            }
        }

        GeissCore_diag(core, &diag)
        XCTAssertEqual(diag.active_mode, initialMode, "Mode Lock should prevent mode changes across 300 frames")
    }

    func testGeissModeLockOffAllowsAutoSwitch() {
        guard let core = GeissCore_create(128, 96) else {
            XCTFail("GeissCore_create failed")
            return
        }
        defer { GeissCore_destroy(core) }

        var cfg = GeissCoreConfig()
        GeissCore_getConfig(core, &cfg)
        cfg.modeLocked = 0
        cfg.autoSwitchSeconds = 5
        GeissCore_setConfig(core, &cfg)

        var diag = GeissCoreDiag()
        GeissCore_diag(core, &diag)
        let initialMode = diag.active_mode

        let silence = [Float](repeating: 0, count: 576)
        var indexBuf = [UInt8](repeating: 0, count: 128 * 96)
        var modeDidChange = false

        for frameNum in 0..<500 {
            silence.withUnsafeBufferPointer { pcm in
                GeissCore_addPCM(core, pcm.baseAddress, Int32(pcm.count))
            }
            indexBuf.withUnsafeMutableBufferPointer { buf in
                GeissCore_render(core, buf.baseAddress)
            }

            if frameNum % 50 == 0 {
                GeissCore_diag(core, &diag)
                if diag.active_mode != initialMode {
                    modeDidChange = true
                    break
                }
            }
        }

        if modeDidChange {
            XCTAssertTrue(modeDidChange, "Mode Lock off allows auto-switch to occur")
        } else {
            XCTFail("Mode did not auto-switch within 500 frames; auto-switch feature may require upstream port edits. Current mode: \(diag.active_mode)")
        }
    }
}
