#!/bin/bash
# NullPlayer App Bundle Assembly Helper
# Shared by build_dmg.sh and build_mas.sh
# Expects: REPO_ROOT, BUILD_DIR, SKIP_BUILD set by caller
# Expects: log_info, log_success, log_warning, log_error functions defined by caller

assemble_app() {
    local APP_BUNDLE="$1"

    # Derive subdirectories from the bundle path
    local CONTENTS_DIR="$APP_BUNDLE/Contents"
    local MACOS_DIR="$CONTENTS_DIR/MacOS"
    local FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
    local RESOURCES_DIR="$CONTENTS_DIR/Resources"
    local HOMEBREW_REF_PATTERN='^(/opt/homebrew|/usr/local)/'

    # Step 1: Check frameworks exist
    log_info "Checking required frameworks..."
    if [[ ! -d "$REPO_ROOT/Frameworks/VLCKit.framework" ]] || [[ ! -f "$REPO_ROOT/Frameworks/libprojectM-4.dylib" ]] || [[ ! -f "$REPO_ROOT/Frameworks/libaubio.5.dylib" ]]; then
        log_error "Required frameworks not found. Run ./scripts/bootstrap.sh first."
        exit 1
    fi
    log_success "Frameworks found"

    # Step 2: Build release binary
    if [[ "$SKIP_BUILD" == false ]]; then
        log_info "Building release binary..."
        swift build -c release
        log_success "Build complete"
    else
        log_info "Skipping build (--skip-build)"
        if [[ ! -f "$BUILD_DIR/NullPlayer" ]]; then
            log_error "No release build found at $BUILD_DIR/NullPlayer"
            exit 1
        fi
    fi

    # Step 3: Clean and create app bundle structure
    log_info "Creating app bundle structure..."
    rm -rf "$APP_BUNDLE"
    mkdir -p "$MACOS_DIR"
    mkdir -p "$FRAMEWORKS_DIR"
    mkdir -p "$RESOURCES_DIR"

    # Step 4: Copy executable and write PkgInfo
    log_info "Copying executable..."
    cp "$BUILD_DIR/NullPlayer" "$MACOS_DIR/"
    printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

    # Step 5: Copy frameworks
    log_info "Copying frameworks..."
    cp -R "$REPO_ROOT/Frameworks/VLCKit.framework" "$FRAMEWORKS_DIR/"
    cp "$REPO_ROOT/Frameworks/libprojectM-4.dylib" "$FRAMEWORKS_DIR/"
    ln -sf "libprojectM-4.dylib" "$FRAMEWORKS_DIR/libprojectM-4.4.dylib"

    # Step 5b: Copy optional YouTube→Sonos helper binaries (DMG only; MAS does not include)
    # These are DMG-only and self-disable when absent via runtime binary-presence check.
    if [[ -f "$REPO_ROOT/Frameworks/yt-dlp" ]]; then
        cp "$REPO_ROOT/Frameworks/yt-dlp" "$MACOS_DIR/yt-dlp"
        chmod +x "$MACOS_DIR/yt-dlp"
        log_success "yt-dlp bundled"
    fi
    if [[ -f "$REPO_ROOT/Frameworks/ffmpeg" ]]; then
        cp "$REPO_ROOT/Frameworks/ffmpeg" "$MACOS_DIR/ffmpeg"
        chmod +x "$MACOS_DIR/ffmpeg"
        log_success "ffmpeg CLI bundled"
    fi

    # Copy libaubio (BPM detection) and all its transitive Homebrew dependencies
    if [[ -f "$REPO_ROOT/Frameworks/libaubio.5.dylib" ]]; then
        cp "$REPO_ROOT/Frameworks/libaubio.5.dylib" "$FRAMEWORKS_DIR/"
        ln -sf "libaubio.5.dylib" "$FRAMEWORKS_DIR/libaubio.dylib"
        log_success "libaubio copied"

        # Recursively bundle all Homebrew dylib dependencies
        # libaubio depends on libsndfile which depends on libogg, libvorbis, libFLAC, etc.
        bundle_homebrew_deps() {
            local binary="$1"
            local deps
            deps=$(otool -L "$binary" 2>/dev/null | awk '{print $1}' | grep -E "$HOMEBREW_REF_PATTERN" || true)
            for dep in $deps; do
                local dep_name
                dep_name=$(basename "$dep")
                if [[ ! -f "$FRAMEWORKS_DIR/$dep_name" ]]; then
                    if [[ -f "$dep" ]]; then
                        cp "$dep" "$FRAMEWORKS_DIR/"
                        chmod 755 "$FRAMEWORKS_DIR/$dep_name"
                        log_info "  Bundled transitive dep: $dep_name"
                        # Recurse into this dependency's own deps
                        bundle_homebrew_deps "$FRAMEWORKS_DIR/$dep_name"
                    else
                        log_warning "  Homebrew dep not found: $dep"
                    fi
                fi
            done
        }

        log_info "Bundling libaubio transitive dependencies..."
        bundle_homebrew_deps "$FRAMEWORKS_DIR/libaubio.5.dylib"
    else
        log_warning "libaubio.5.dylib not found - BPM detection will not work"
    fi

    # Copy ogg and vorbis frameworks from xcframework artifacts
    OGG_FRAMEWORK="$REPO_ROOT/.build/artifacts/ogg-binary-xcframework/ogg/ogg.xcframework/macos-arm64_x86_64/ogg.framework"
    VORBIS_FRAMEWORK="$REPO_ROOT/.build/artifacts/vorbis-binary-xcframework/vorbis/vorbis.xcframework/macos-arm64_x86_64/vorbis.framework"

    if [[ -d "$OGG_FRAMEWORK" ]]; then
        cp -R "$OGG_FRAMEWORK" "$FRAMEWORKS_DIR/"
    else
        log_warning "ogg.framework not found - app may not run"
    fi

    if [[ -d "$VORBIS_FRAMEWORK" ]]; then
        cp -R "$VORBIS_FRAMEWORK" "$FRAMEWORKS_DIR/"
    else
        log_warning "vorbis.framework not found - app may not run"
    fi

    # Step 6: Copy resources from the build output
    log_info "Copying resources..."
    # The swift build puts resources in NullPlayer_NullPlayer.bundle/Resources
    BUNDLE_RESOURCES="$BUILD_DIR/NullPlayer_NullPlayer.bundle/Resources"
    if [[ -d "$BUNDLE_RESOURCES" ]]; then
        cp -R "$BUNDLE_RESOURCES/"* "$RESOURCES_DIR/" 2>/dev/null || true
        log_success "Resources copied (Presets, Textures, etc.)"
    else
        log_warning "No resources found at $BUNDLE_RESOURCES"
    fi

    # Copy ALL Metal shader files from bundle root (SPM places .copy() files there)
    # Includes: SpectrumShaders, FlameShaders, CosmicShaders, ElectricityShaders, MatrixShaders, BloomShader
    for metal_file in "$BUILD_DIR/NullPlayer_NullPlayer.bundle/"*.metal; do
        if [[ -f "$metal_file" ]]; then
            cp "$metal_file" "$RESOURCES_DIR/"
        fi
    done
    log_success "Metal shaders copied"

    # Also copy Info.plist from source
    cp "$REPO_ROOT/Sources/NullPlayer/Resources/Info.plist" "$CONTENTS_DIR/"

    # Step 6b: Validate third-party notices for every bundled dependency.
    # Forward: every component in scripts/third_party_components.tsv ships its
    # license text. Reverse: every framework/dylib in Contents/Frameworks is
    # covered by a manifest entry. Also validates helper executables in MacOS dir.
    # Fails the build on any gap.
    log_info "Validating bundled third-party notices..."
    "$REPO_ROOT/scripts/validate_notices.sh" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$MACOS_DIR"

    # Step 7: Create app icon from AppIcon.png
    APP_ICON_PNG="$REPO_ROOT/Sources/NullPlayer/Resources/AppIcon.png"
    if [[ -f "$APP_ICON_PNG" ]]; then
        log_info "Creating app icon..."
        ICONSET_DIR="$REPO_ROOT/dist/AppIcon.iconset"
        rm -rf "$ICONSET_DIR"
        mkdir -p "$ICONSET_DIR"

        # Use magick to produce a full-bleed square icon (no transparent corners).
        # macOS Big Sur+ applies its own squircle mask; pre-rounded icons with transparent
        # corners show the Dock background as a grey border. We fix this by:
        #   1. Trimming the transparent canvas padding
        #   2. Blurring a copy to spread the gradient colors into the rounded corners
        #   3. Compositing the original over that filled background (DstOver)
        # Result: solid square with the gradient naturally filling the corners.
        resize_icon() {
            local size=$1
            local out=$2
            magick "$APP_ICON_PNG" -trim +repage \
                \( +clone -blur 0x200 -alpha off \) \
                -compose DstOver -composite \
                -resize "${size}x${size}" "$out"
        }

        # Generate all required icon sizes
        resize_icon 16   "$ICONSET_DIR/icon_16x16.png"
        resize_icon 32   "$ICONSET_DIR/icon_16x16@2x.png"
        resize_icon 32   "$ICONSET_DIR/icon_32x32.png"
        resize_icon 64   "$ICONSET_DIR/icon_32x32@2x.png"
        resize_icon 128  "$ICONSET_DIR/icon_128x128.png"
        resize_icon 256  "$ICONSET_DIR/icon_128x128@2x.png"
        resize_icon 256  "$ICONSET_DIR/icon_256x256.png"
        resize_icon 512  "$ICONSET_DIR/icon_256x256@2x.png"
        resize_icon 512  "$ICONSET_DIR/icon_512x512.png"
        resize_icon 1024 "$ICONSET_DIR/icon_512x512@2x.png"

        # Create .icns file
        iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
        rm -rf "$ICONSET_DIR"
        log_success "App icon created"
    else
        log_warning "AppIcon.png not found, skipping icon creation"
    fi

    # Step 9: Fix library rpaths
    log_info "Fixing library paths..."

    # Add rpath to executable if not already present
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/NullPlayer" 2>/dev/null || true

    # Fix libprojectM reference in executable
    install_name_tool -change "@rpath/libprojectM-4.4.dylib" "@executable_path/../Frameworks/libprojectM-4.4.dylib" "$MACOS_DIR/NullPlayer" 2>/dev/null || true

    # Update libprojectM's own install name
    install_name_tool -id "@executable_path/../Frameworks/libprojectM-4.dylib" "$FRAMEWORKS_DIR/libprojectM-4.dylib" 2>/dev/null || true

    # Fix libaubio reference in executable
    if [[ -f "$FRAMEWORKS_DIR/libaubio.5.dylib" ]]; then
        for aubio_ref in \
            "/opt/homebrew/opt/aubio/lib/libaubio.5.dylib" \
            "/opt/homebrew/lib/libaubio.5.dylib" \
            "/usr/local/opt/aubio/lib/libaubio.5.dylib" \
            "/usr/local/lib/libaubio.5.dylib"; do
            install_name_tool -change "$aubio_ref" "@executable_path/../Frameworks/libaubio.5.dylib" "$MACOS_DIR/NullPlayer" 2>/dev/null || true
        done
        install_name_tool -id "@executable_path/../Frameworks/libaubio.5.dylib" "$FRAMEWORKS_DIR/libaubio.5.dylib" 2>/dev/null || true
    fi

    # Fix ALL Homebrew references in ALL bundled dylibs (transitive dependency chain)
    # This rewrites Homebrew paths to @executable_path/../Frameworks/... in every dylib.
    log_info "Fixing Homebrew references in bundled dylibs..."
    for dylib in "$FRAMEWORKS_DIR/"*.dylib; do
        if [[ -f "$dylib" && ! -L "$dylib" ]]; then
            local_name=$(basename "$dylib")
            # Update the dylib's own install name
            install_name_tool -id "@executable_path/../Frameworks/$local_name" "$dylib" 2>/dev/null || true
            # Find and rewrite all Homebrew references
            homebrew_refs=$(otool -L "$dylib" 2>/dev/null | awk '{print $1}' | grep -E "$HOMEBREW_REF_PATTERN" || true)
            for ref in $homebrew_refs; do
                ref_name=$(basename "$ref")
                install_name_tool -change "$ref" "@executable_path/../Frameworks/$ref_name" "$dylib" 2>/dev/null || true
            done
        fi
    done
    # Also fix Homebrew references in the main executable
    homebrew_refs=$(otool -L "$MACOS_DIR/NullPlayer" 2>/dev/null | awk '{print $1}' | grep -E "$HOMEBREW_REF_PATTERN" || true)
    for ref in $homebrew_refs; do
        ref_name=$(basename "$ref")
        install_name_tool -change "$ref" "@executable_path/../Frameworks/$ref_name" "$MACOS_DIR/NullPlayer" 2>/dev/null || true
    done
}
