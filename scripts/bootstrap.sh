#!/bin/bash
# NullPlayer Bootstrap Script
# Downloads required binary frameworks from GitHub Releases
#
# Usage: ./scripts/bootstrap.sh
#        ./scripts/bootstrap.sh --force  (re-download even if exists)

set -eo pipefail

# Configuration
REPO="ad-repo/nullplayer"
RELEASE_TAG="deps-v2"

# Framework definitions
VLCKIT_FILE="VLCKit-macos.tar.gz"
VLCKIT_SHA256="b36a06d9169fba85101dae8264be24ab3d92c0f2976001524d60f79e8fdece93"
VLCKIT_TARGET="Frameworks/VLCKit.framework"

PROJECTM_FILE="libprojectM-4.1.6-macos.tar.gz"
PROJECTM_SHA256="c85addde0f7afb6132c619a6f081ef14fc806e1afbf3767ec04c9470e9c9a7b1"
PROJECTM_TARGET="Frameworks/libprojectM-4.dylib"

AUBIO_FILE="libaubio-macos.tar.gz"
AUBIO_SHA256="0fbcdfcea459e6f8278bfef134e4eddafad4a7764389bc6147428e59b25933d0"
AUBIO_TARGET="Frameworks/libaubio.5.dylib"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Change to repo root
cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)

# Parse arguments
FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    for cmd in tar shasum; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    # Need either gh or curl
    if ! command -v gh &> /dev/null && ! command -v curl &> /dev/null; then
        missing+=("gh or curl")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_error "Please install them and try again."
        exit 1
    fi
}

# Download file (uses gh for private repos, curl for public)
download_file() {
    local filename="$1"
    local output="$2"
    
    # Try gh first (handles authentication for private repos)
    if command -v gh &> /dev/null; then
        log_info "Downloading via GitHub CLI..."
        if gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$filename" --output "$output" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Fallback to curl for public repos
    if command -v curl &> /dev/null; then
        local url="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${filename}"
        log_info "Downloading via curl..."
        local max_retries=3
        local retry=0
        
        while [[ $retry -lt $max_retries ]]; do
            if curl -fSL --progress-bar -o "$output" "$url" 2>/dev/null; then
                return 0
            fi
            retry=$((retry + 1))
            if [[ $retry -lt $max_retries ]]; then
                log_warning "Download failed, retrying ($retry/$max_retries)..."
                sleep 2
            fi
        done
    fi
    
    return 1
}

# Verify checksum
verify_checksum() {
    local file="$1"
    local expected="$2"
    
    local actual
    actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    
    if [[ "$actual" != "$expected" ]]; then
        log_error "Checksum mismatch for $file"
        log_error "  Expected: $expected"
        log_error "  Got:      $actual"
        return 1
    fi
    
    return 0
}

# Download and install a framework
install_framework() {
    local name="$1"
    local filename="$2"
    local checksum="$3"
    local target="$4"
    
    local tmpfile="/tmp/${filename}"
    
    log_info "Downloading ${name}..."
    if ! download_file "$filename" "$tmpfile"; then
        log_error "Failed to download ${name}"
        log_error "If repo is private, ensure 'gh auth login' is complete"
        rm -f "$tmpfile"
        return 1
    fi
    
    log_info "Verifying checksum..."
    if ! verify_checksum "$tmpfile" "$checksum"; then
        rm -f "$tmpfile"
        return 1
    fi
    
    log_info "Extracting ${name}..."
    
    # Remove existing target if it exists
    if [[ -e "${REPO_ROOT}/${target}" ]]; then
        rm -rf "${REPO_ROOT}/${target}"
    fi
    
    # Extract
    tar -xzf "$tmpfile" -C "${REPO_ROOT}/Frameworks/"
    
    # Verify extraction
    if [[ ! -e "${REPO_ROOT}/${target}" ]]; then
        log_error "Extraction failed - ${target} not found"
        rm -f "$tmpfile"
        return 1
    fi
    
    # Create versioned symlink for libprojectM (dylib expects libprojectM-4.4.dylib)
    if [[ "$target" == *"libprojectM"* ]]; then
        local dylib_dir=$(dirname "${REPO_ROOT}/${target}")
        local dylib_name=$(basename "${REPO_ROOT}/${target}")
        # The dylib's install name is @rpath/libprojectM-4.4.dylib
        ln -sf "$dylib_name" "${dylib_dir}/libprojectM-4.4.dylib"
        log_info "Created symlink: libprojectM-4.4.dylib -> $dylib_name"
    fi
    
    # Create unversioned symlink for libaubio (linker looks for libaubio.dylib)
    if [[ "$target" == *"libaubio"* ]]; then
        local dylib_dir=$(dirname "${REPO_ROOT}/${target}")
        local dylib_name=$(basename "${REPO_ROOT}/${target}")
        ln -sf "$dylib_name" "${dylib_dir}/libaubio.dylib"
        log_info "Created symlink: libaubio.dylib -> $dylib_name"
    fi
    
    rm -f "$tmpfile"
    log_success "${name} installed successfully"
    return 0
}

# Main
main() {
    echo ""
    echo "======================================"
    echo "  NullPlayer Framework Bootstrap"
    echo "======================================"
    echo ""
    
    check_dependencies
    
    # Ensure Frameworks directory exists
    mkdir -p "${REPO_ROOT}/Frameworks"
    
    local failed=0
    
    # VLCKit
    if [[ "$FORCE" == true ]] || [[ ! -e "${REPO_ROOT}/${VLCKIT_TARGET}" ]]; then
        if ! install_framework "VLCKit" "$VLCKIT_FILE" "$VLCKIT_SHA256" "$VLCKIT_TARGET"; then
            failed=1
        fi
        echo ""
    else
        log_success "VLCKit already installed"
    fi
    
    # libprojectM
    if [[ "$FORCE" == true ]] || [[ ! -e "${REPO_ROOT}/${PROJECTM_TARGET}" ]]; then
        if ! install_framework "libprojectM" "$PROJECTM_FILE" "$PROJECTM_SHA256" "$PROJECTM_TARGET"; then
            failed=1
        fi
        echo ""
    else
        log_success "libprojectM already installed"
    fi
    
    # libaubio
    if [[ "$FORCE" == true ]] || [[ ! -e "${REPO_ROOT}/${AUBIO_TARGET}" ]]; then
        if ! install_framework "libaubio" "$AUBIO_FILE" "$AUBIO_SHA256" "$AUBIO_TARGET"; then
            failed=1
        fi
        echo ""
    else
        log_success "libaubio already installed"
    fi
    
    # Summary
    echo "======================================"
    if [[ $failed -eq 0 ]]; then
        log_success "Bootstrap complete! All frameworks installed."
    else
        log_error "Some frameworks failed to install."
        exit 1
    fi
    echo "======================================"
    echo ""
}

main "$@"
