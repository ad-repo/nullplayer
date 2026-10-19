import Foundation

/// The value Sonique uses for each `skin.ini` key a skin does not write, as the skinpack's `misc.txt`
/// lists them. These are every key Sonique reads. Values stay raw: they go through the same resolver
/// as a skin's own, so `NAV_PREV_y = PREV_y` follows the skin's `PREV_y`.
enum SoniqueSkinDefaults {
    /// Section → key → raw value, sections and keys lowercased.
    static let values: [String: [String: String]] = table.mapValues {
        Dictionary(uniqueKeysWithValues: $0.map { ($0.key.lowercased(), $0.value) })
    }

    private static let table: [String: [String: String]] = [
        "skin": [
            "version": "100",
            "TouchNavMode": "1", "TouchMidMode": "1", "TouchSmallMode": "1",
        ],
        "sonique colors": [
            "SystemColor_1": "0xFF00FFFF", "SystemColor_2": "0xFFFFFF00", "SystemColor_3": "0xFF00FF00",
            "BorderColor": "0xFF000001",
            "SystemBkColor_1": "0xFF005500", "SystemBkColor_2": "0xFF002B45",
            "PlayListColor_1": "0xFF00FFFF", "PlayListColor_2": "0xFFFF00FF",
            "ProgressColor_1": "0xFF00FF00", "ProgressColor_2": "0xFFFFFF00", "ProgressColor_3": "0xFFFF0000",
            "StatusBarBgColor": "0xFF000000", "StatusBarFgColor": "0xFF005050", "StatusBarTextColor": "0xFF00FFFF",
            "ProgressBkColor": "0xFF606060", "OpenFileColor": "0xFFFF8000",
            "AmpKnobColor": "0xFF00FF00", "BalKnobColor": "0xFF6060FF", "PitchKnobColor": "0xFFFF3030",
            // `misc.txt` swaps these two: the oracle draws the balls in SystemColor_1 (k2, and the default
            // skin's cyan balls) and the logo in SystemColor_2 (the sonique skin's yellow logo, which sets
            // no colours), decision record Amendments 3 and 6.
            "LogoColor": "SystemColor_2", "LogoRingColor": "SystemColor_3", "BlueBallsColor": "SystemColor_1",
            "InternalVisLeftColor": "0xFF0000FF", "InternalVisRightColor": "0xFFFF0000",
            "InternalVisBlendColor": "0xFF00FF00",
            "LogoStartColor": "0x00FF2200", "LogoRingStartColor": "0x000022FF",
        ],
        "misc locations": [
            "PAUSEON_x": "90", "PAUSEON_y": "40", "PREV_x": "0", "PREV_y": "40", "NEXT_x": "0", "NEXT_y": "0",
            "STOPON_x": "130", "STOPON_y": "0", "STOPOFF_x": "130", "STOPOFF_y": "40",
            "PLAYON_x": "90", "PLAYON_y": "0", "SLIDERON_x": "170", "SLIDERON_y": "0",
            "SLIDEROFF_x": "170", "SLIDEROFF_y": "20", "CYANON_x": "60", "CYANON_y": "20",
            "CYANOFF_x": "60", "CYANOFF_y": "0", "GREENON_x": "30", "GREENON_y": "40",
            "GREENON2_x": "60", "GREENON2_y": "40", "ORANGEON_x": "30", "ORANGEON_y": "20",
            "REDON_x": "30", "REDON_y": "0", "BIGUP_x": "280", "BIGUP_y": "0",
            "BIGON_DOWN_x": "BIGUP_x", "BIGON_DOWN_y": "BIGUP_y + 35",
            "DRAWER_x": "0", "DRAWER_y": "76", "DRAWER_POS_x": "29", "DRAWER_POS_y": "229",
            "NAV_CYANON_x": "CYANON_x", "NAV_CYANON_y": "CYANON_y", "NAV_CYANOFF_x": "CYANOFF_x",
            "NAV_CYANOFF_y": "CYANOFF_y", "NAV_GREENON_x": "GREENON_x", "NAV_GREENON_y": "GREENON_y",
            "NAV_GREENON2_x": "GREENON2_x", "NAV_GREENON2_y": "GREENON2_y", "NAV_ORANGEON_x": "ORANGEON_x",
            "NAV_ORANGEON_y": "ORANGEON_y", "NAV_REDON_x": "REDON_x", "NAV_REDON_y": "REDON_y",
            "NAV_PREV_x": "PREV_x", "NAV_PREV_y": "PREV_y", "NAV_NEXT_x": "NEXT_x", "NAV_NEXT_y": "NEXT_y",
            "NAV_STOPON_x": "STOPON_x", "NAV_STOPON_y": "STOPON_y", "NAV_STOPOFF_x": "STOPOFF_x",
            "NAV_STOPOFF_y": "STOPOFF_y", "NAV_PLAYON_x": "PLAYON_x", "NAV_PLAYON_y": "PLAYON_y",
            "NAV_PAUSEON_x": "PAUSEON_x", "NAV_PAUSEON_y": "PAUSEON_y",
        ],
        "misc values": [
            "MISC_DRAWER_POS_x": "29", "MISC_DRAWER_POS_y": "229",
            "MISC_DRAWER_SLIDER_ARRAY_POS_x": "22", "MISC_DRAWER_SLIDER_ARRAY_POS_y": "20",
            "MISC_DRAWER_SLIDER_SIZE_x": "8", "MISC_DRAWER_SLIDER_SIZE_y": "44",
            "MISC_DRAWER_SLIDER_PITCH": "14", "MISC_DRAWER_DISTANCE_TOSLIDE": "75",
            "MISC_DRAWER_SLIDER_HANDLE_SIZE_width": "8", "MISC_DRAWER_SLIDER_HANDLE_SIZE_height": "14",
            "MISC_VOLUME_KNOB_width": "18", "MISC_VOLUME_KNOB_images": "37",
            "MISC_NAV_VOLUME_KNOB_width": "18", "MISC_NAV_VOLUME_KNOB_images": "37",
            "MISC_SMALL_KNOB_width": "13", "MISC_SMALL_KNOB_images": "37",
            "MISC_SHUTTLE_KNOB_width": "49", "MISC_SHUTTLE_KNOB_images": "13",
            "NC_BB_DIST_FROM_RIGHT": "5", "mid_playlistmode": "1",
        ],
        "msm locations": [
            "MSM_SINGLEUP_x": "44", "MSM_SINGLEUP_y": "1", "MSM_SINGLEDOWN_x": "55", "MSM_SINGLEDOWN_y": "3",
            "MSM_HELP_x": "65", "MSM_HELP_y": "8", "MSM_MINIMIZE_x": "73", "MSM_MINIMIZE_y": "16",
            "MSM_CLOSE_x": "79", "MSM_CLOSE_y": "26",
        ],
    ]
}
