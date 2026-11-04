#include "VisClassicCore.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "upstream/BarColour.h"
#include "upstream/LevelCalc.h"
#include "upstream/LogBarTable.h"
#include "upstream/PeakColour.h"
#include "upstream/fft.h"
#include "VisClassicEffects.h"
#include "VisClassicPeaks.h"

thread_local int draw_height = 0;  // Used by upstream bar color helpers.

namespace {

constexpr int kWaveCount = 576;
constexpr int kMaxBars = 576;
constexpr int kColorCount = 256;
constexpr int kDefaultFFTFrequencies = 512;

using visclassic::Palette;
using visclassic::RGB;

static inline int clampInt(int v, int lo, int hi) {
    return std::max(lo, std::min(hi, v));
}

static inline std::string trim(const std::string &s) {
    size_t start = 0;
    while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start]))) {
        ++start;
    }
    size_t end = s.size();
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
        --end;
    }
    return s.substr(start, end - start);
}

static inline std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

static inline bool parseInt(const std::string &s, int &out) {
    try {
        size_t pos = 0;
        int v = std::stoi(trim(s), &pos, 10);
        if (pos == 0) return false;
        out = v;
        return true;
    } catch (...) {
        return false;
    }
}

// Profile colours are `R G B` as they appear on screen. The original plugin's source reads them
// into variables named `r g b` and stores `RGB(b, g, r)` into a COLORREF, but that COLORREF goes
// straight into a 32-bit DIB whose byte order undoes the swap — its built-in default,
// `bmpRGB(204 + i/5, i, 0)`, is the red→yellow of "Default Red & Yellow". Reading them as B G R
// drew every bundled profile with red and blue exchanged.
static inline bool parseRGB(const std::string &s, RGB &out) {
    std::istringstream iss(s);
    int r = 0, g = 0, b = 0;
    if (!(iss >> r >> g >> b)) {
        return false;
    }
    out.b = static_cast<uint8_t>(clampInt(b, 0, 255));
    out.g = static_cast<uint8_t>(clampInt(g, 0, 255));
    out.r = static_cast<uint8_t>(clampInt(r, 0, 255));
    return true;
}

static inline std::string stemFromPath(const std::string &path) {
    const size_t slash = path.find_last_of("/\\");
    const std::string file = (slash == std::string::npos) ? path : path.substr(slash + 1);
    const size_t dot = file.find_last_of('.');
    if (dot == std::string::npos) return file;
    return file.substr(0, dot);
}

struct IniProfile {
    std::map<std::string, std::string> analyzer;
    Palette barColors{};
    Palette peakColors{};
    Palette volumeColors{};
    std::array<int, kColorCount> volumeFunc{};
    bool hasBarColors = false;
    bool hasPeakColors = false;
    bool hasVolumeColors = false;
    bool hasVolumeFunc = false;
};

class Core {
public:
    explicit Core(int width, int height) : width_(std::max(1, width)), height_(std::max(1, height)) {
        setDefaultColors();
        resetLevelTables();
        setupFFT();
        recalcGeometry();
    }

    void setWaveform(const uint8_t *left, const uint8_t *right, size_t count, double sampleRate) {
        if (!left || !right || count == 0) {
            return;
        }

        sampleRate_ = static_cast<unsigned int>(std::max(8000.0, std::min(192000.0, sampleRate)));
        if (sampleRate_ != lastBarTableSampleRate_) {
            rebuildBarTable_ = true;
        }

        const size_t n = std::min(count, static_cast<size_t>(kWaveCount));
        std::copy(left, left + n, waveLeft_.begin());
        std::copy(right, right + n, waveRight_.begin());
        if (n < static_cast<size_t>(kWaveCount)) {
            std::fill(waveLeft_.begin() + static_cast<long>(n), waveLeft_.end(), static_cast<uint8_t>(128));
            std::fill(waveRight_.begin() + static_cast<long>(n), waveRight_.end(), static_cast<uint8_t>(128));
        }
        hasWaveform_ = true;
    }

    int setOption(const std::string &keyRaw, int value) {
        const std::string key = lower(trim(keyRaw));

        if (key == "falloff") {
            falloffRate_ = clampInt(value, 0, 75);
            return 1;
        }
        if (key == "peakchange") {
            peakChangeRate_ = clampInt(value, 0, 255);
            rebuildPeakTables_ = true;
            return 1;
        }
        if (key == "peakfalloffmode") {
            peakLogFalloff_ = value != 0;
            rebuildPeakTables_ = true;
            return 1;
        }
        if (key == "bar width" || key == "bar_width") {
            requestedBarWidth_ = clampInt(value, 1, 64);
            recalcGeometry();
            return 1;
        }
        if (key == "x-spacing" || key == "x_spacing") {
            xSpacing_ = clampInt(value, 0, 32);
            recalcGeometry();
            return 1;
        }
        if (key == "y-spacing" || key == "y_spacing") {
            ySpacing_ = clampInt(value, 1, 7);
            return 1;
        }
        if (key == "backgrounddraw") {
            backgroundDraw_ = clampInt(value, 0, 4);
            return 1;
        }
        if (key == "barcolourstyle") {
            barColourStyle_ = clampInt(value, 0, 4);
            return 1;
        }
        if (key == "peakcolourstyle") {
            peakColourStyle_ = clampInt(value, 0, 2);
            rebuildPeakTables_ = true;
            return 1;
        }
        if (key == "effect") {
            effect_ = clampInt(value, 0, 7);
            ghosts_.reset(bands_, bandWidth_);
            return 1;
        }
        if (key == "peak effect" || key == "peak_effect") {
            peakEffect_ = clampInt(value, 0, 5);
            rebuildPeakTables_ = true;
            return 1;
        }
        if (key == "reverseleft") {
            reverseLeft_ = value != 0;
            return 1;
        }
        if (key == "reverseright") {
            reverseRight_ = value != 0;
            return 1;
        }
        if (key == "mono") {
            mono_ = value != 0;
            recalcGeometry();
            return 1;
        }
        if (key == "bar level" || key == "bar_level") {
            levelBase_ = clampInt(value, 0, 1);
            return 1;
        }
        if (key == "fftequalize") {
            fftEqualize_ = value != 0;
            setupFFT();
            return 1;
        }
        if (key == "fftenvelope") {
            fftEnvelope_ = std::max(0.01f, static_cast<float>(value) / 100.0f);
            setupFFT();
            return 1;
        }
        if (key == "fftscale") {
            fftScale_ = std::max(0.01f, static_cast<float>(value) / 100.0f);
            return 1;
        }
        if (key == "fittowidth" || key == "fit_to_width" || key == "fit to width") {
            fitToWidth_ = value != 0;
            return 1;
        }
        if (key == "transparentbg" || key == "transparent_bg" || key == "transparent bg") {
            transparentBg_ = value != 0;
            return 1;
        }
        if (key == "referencewidth") {
            referenceWidth_ = std::max(0, value);
            recalcGeometry();
            return 1;
        }
        return 0;
    }

    int getOption(const std::string &keyRaw, int *valueOut) const {
        if (!valueOut) return 0;
        const std::string key = lower(trim(keyRaw));

        if (key == "falloff") {
            *valueOut = falloffRate_;
            return 1;
        }
        if (key == "peakchange") {
            *valueOut = peakChangeRate_;
            return 1;
        }
        if (key == "peakfalloffmode") {
            *valueOut = peakLogFalloff_ ? 1 : 0;
            return 1;
        }
        if (key == "bar width" || key == "bar_width") {
            *valueOut = requestedBarWidth_;
            return 1;
        }
        if (key == "x-spacing" || key == "x_spacing") {
            *valueOut = xSpacing_;
            return 1;
        }
        if (key == "y-spacing" || key == "y_spacing") {
            *valueOut = ySpacing_;
            return 1;
        }
        if (key == "backgrounddraw") {
            *valueOut = backgroundDraw_;
            return 1;
        }
        if (key == "barcolourstyle") {
            *valueOut = barColourStyle_;
            return 1;
        }
        if (key == "peakcolourstyle") {
            *valueOut = peakColourStyle_;
            return 1;
        }
        if (key == "effect") {
            *valueOut = effect_;
            return 1;
        }
        if (key == "peak effect" || key == "peak_effect") {
            *valueOut = peakEffect_;
            return 1;
        }
        if (key == "reverseleft") {
            *valueOut = reverseLeft_ ? 1 : 0;
            return 1;
        }
        if (key == "reverseright") {
            *valueOut = reverseRight_ ? 1 : 0;
            return 1;
        }
        if (key == "mono") {
            *valueOut = mono_ ? 1 : 0;
            return 1;
        }
        if (key == "bar level" || key == "bar_level") {
            *valueOut = levelBase_;
            return 1;
        }
        if (key == "fftequalize") {
            *valueOut = fftEqualize_ ? 1 : 0;
            return 1;
        }
        if (key == "fftenvelope") {
            *valueOut = static_cast<int>(fftEnvelope_ * 100.0f + 0.5f);
            return 1;
        }
        if (key == "fftscale") {
            *valueOut = static_cast<int>(fftScale_ * 100.0f + 0.5f);
            return 1;
        }
        if (key == "fittowidth" || key == "fit_to_width" || key == "fit to width") {
            *valueOut = fitToWidth_ ? 1 : 0;
            return 1;
        }
        if (key == "transparentbg" || key == "transparent_bg" || key == "transparent bg") {
            *valueOut = transparentBg_ ? 1 : 0;
            return 1;
        }
        if (key == "referencewidth") {
            *valueOut = referenceWidth_;
            return 1;
        }
        return 0;
    }

    int loadProfile(const std::string &path) {
        IniProfile profile;
        if (!readProfile(path, profile)) {
            setError("Failed to parse profile");
            return 0;
        }

        auto readAnalyzerInt = [&](const char *key, int fallback, int lo, int hi) {
            auto it = profile.analyzer.find(key);
            if (it == profile.analyzer.end()) return fallback;
            int v = fallback;
            if (!parseInt(it->second, v)) return fallback;
            return clampInt(v, lo, hi);
        };

        falloffRate_ = readAnalyzerInt("Falloff", falloffRate_, 0, 75);
        peakChangeRate_ = readAnalyzerInt("PeakChange", peakChangeRate_, 0, 255);
        requestedBarWidth_ = readAnalyzerInt("Bar Width", requestedBarWidth_, 1, 64);
        xSpacing_ = readAnalyzerInt("X-Spacing", xSpacing_, 0, 32);
        ySpacing_ = readAnalyzerInt("Y-Spacing", ySpacing_, 1, 7);
        backgroundDraw_ = readAnalyzerInt("BackgroundDraw", backgroundDraw_, 0, 4);
        barColourStyle_ = readAnalyzerInt("BarColourStyle", barColourStyle_, 0, 4);
        peakColourStyle_ = readAnalyzerInt("PeakColourStyle", peakColourStyle_, 0, 2);
        effect_ = readAnalyzerInt("Effect", effect_, 0, 7);
        peakEffect_ = readAnalyzerInt("Peak Effect", peakEffect_, 0, 5);
        peakLogFalloff_ = readAnalyzerInt("PeakFallOffMode", peakLogFalloff_ ? 1 : 0, 0, 1) != 0;
        rebuildPeakTables_ = true;
        reverseLeft_ = readAnalyzerInt("ReverseLeft", reverseLeft_ ? 1 : 0, 0, 1) != 0;
        reverseRight_ = readAnalyzerInt("ReverseRight", reverseRight_ ? 1 : 0, 0, 1) != 0;
        mono_ = readAnalyzerInt("Mono", mono_ ? 1 : 0, 0, 1) != 0;
        levelBase_ = readAnalyzerInt("Bar Level", levelBase_, 0, 1);
        fftEqualize_ = readAnalyzerInt("FFTEqualize", fftEqualize_ ? 1 : 0, 0, 1) != 0;
        fftEnvelope_ = std::max(0.01f, static_cast<float>(readAnalyzerInt("FFTEnvelope", static_cast<int>(fftEnvelope_ * 100.0f), 1, 1000)) / 100.0f);
        fftScale_ = std::max(0.01f, static_cast<float>(readAnalyzerInt("FFTScale", static_cast<int>(fftScale_ * 100.0f), 1, 2000)) / 100.0f);
        fitToWidth_ = readAnalyzerInt("FitToWidth", fitToWidth_ ? 1 : 0, 0, 1) != 0;

        auto msgIt = profile.analyzer.find("Message");
        if (msgIt != profile.analyzer.end()) {
            profileMessage_ = msgIt->second;
        }

        if (profile.hasBarColors) {
            barColors_ = profile.barColors;
        }
        if (profile.hasPeakColors) {
            peakColors_ = profile.peakColors;
        }
        if (profile.hasVolumeColors) {
            volumeColors_ = profile.volumeColors;
        }
        if (profile.hasVolumeFunc) {
            volumeFunc_ = profile.volumeFunc;
        }

        setupFFT();
        recalcGeometry();
        currentProfilePath_ = path;
        currentProfileName_ = stemFromPath(path);
        return 1;
    }

    int saveProfile(const std::string &path) {
        std::ofstream out(path, std::ios::out | std::ios::trunc);
        if (!out) {
            setError("Unable to open profile for writing");
            return 0;
        }

        out << "[Classic Analyzer]\n";
        out << "Falloff=" << falloffRate_ << "\n";
        out << "PeakChange=" << peakChangeRate_ << "\n";
        out << "Bar Width=" << requestedBarWidth_ << "\n";
        out << "X-Spacing=" << xSpacing_ << "\n";
        out << "Y-Spacing=" << ySpacing_ << "\n";
        out << "BackgroundDraw=" << backgroundDraw_ << "\n";
        out << "BarColourStyle=" << barColourStyle_ << "\n";
        out << "PeakColourStyle=" << peakColourStyle_ << "\n";
        out << "Effect=" << effect_ << "\n";
        out << "Peak Effect=" << peakEffect_ << "\n";
        out << "PeakFallOffMode=" << (peakLogFalloff_ ? 1 : 0) << "\n";
        out << "ReverseLeft=" << (reverseLeft_ ? 1 : 0) << "\n";
        out << "ReverseRight=" << (reverseRight_ ? 1 : 0) << "\n";
        out << "Mono=" << (mono_ ? 1 : 0) << "\n";
        out << "Bar Level=" << levelBase_ << "\n";
        out << "FFTEqualize=" << (fftEqualize_ ? 1 : 0) << "\n";
        out << "FFTEnvelope=" << static_cast<int>(fftEnvelope_ * 100.0f + 0.5f) << "\n";
        out << "FFTScale=" << static_cast<int>(fftScale_ * 100.0f + 0.5f) << "\n";
        out << "FitToWidth=" << (fitToWidth_ ? 1 : 0) << "\n";
        out << "Message=" << profileMessage_ << "\n";

        out << "[BarColours]\n";
        for (int i = 0; i < kColorCount; ++i) {
            out << i << "=" << static_cast<int>(barColors_[i].r) << " "
                << static_cast<int>(barColors_[i].g) << " "
                << static_cast<int>(barColors_[i].b) << "\n";
        }

        out << "[PeakColours]\n";
        for (int i = 0; i < kColorCount; ++i) {
            out << i << "=" << static_cast<int>(peakColors_[i].r) << " "
                << static_cast<int>(peakColors_[i].g) << " "
                << static_cast<int>(peakColors_[i].b) << "\n";
        }

        out << "[VolumeColours]\n";
        for (int i = 0; i < kColorCount; ++i) {
            out << i << "=" << static_cast<int>(volumeColors_[i].r) << " "
                << static_cast<int>(volumeColors_[i].g) << " "
                << static_cast<int>(volumeColors_[i].b) << "\n";
        }

        out << "[VolumeFunction]\n";
        for (int i = 0; i < kColorCount; ++i) {
            out << i << "=" << volumeFunc_[i] << "\n";
        }

        currentProfilePath_ = path;
        currentProfileName_ = stemFromPath(path);
        return 1;
    }

    const std::string &lastError() const { return lastError_; }

private:
    int width_ = 1;
    int height_ = 1;
    int drawWidth_ = 1;
    int bands_ = 1;
    int bandWidth_ = 3;
    int referenceWidth_ = 0;  // if > 0, use for band computation instead of drawWidth_

    int falloffRate_ = 12;
    int peakChangeRate_ = 80;
    int requestedBarWidth_ = 3;
    int xSpacing_ = 1;
    int ySpacing_ = 2;
    int backgroundDraw_ = 0;
    int barColourStyle_ = 1;
    int peakColourStyle_ = 0;
    int effect_ = 0;
    int peakEffect_ = 1;
    bool peakLogFalloff_ = false;  // PeakFallOffMode
    bool reverseLeft_ = true;
    bool reverseRight_ = false;
    bool mono_ = true;
    int levelBase_ = 1;

    bool fftEqualize_ = true;
    float fftEnvelope_ = 0.2f;
    float fftScale_ = 2.0f;
    bool fitToWidth_ = true;
    bool transparentBg_ = false;

    unsigned int sampleRate_ = 44100;
    unsigned int lastBarTableSampleRate_ = 0;
    bool rebuildBarTable_ = true;

    FFT fft_;
    int fftFrequencies_ = kDefaultFFTFrequencies;

    std::array<uint8_t, kWaveCount> waveLeft_{};
    std::array<uint8_t, kWaveCount> waveRight_{};
    bool hasWaveform_ = false;

    std::array<float, kWaveCount> floatWave_{};
    std::vector<float> fftSpectrum_ = std::vector<float>(kDefaultFFTFrequencies);
    std::vector<uint8_t> spectrumLeft_ = std::vector<uint8_t>(kDefaultFFTFrequencies);
    std::vector<uint8_t> spectrumRight_ = std::vector<uint8_t>(kDefaultFFTFrequencies);

    std::array<unsigned int, kMaxBars> barTable_{};

    std::vector<int> level_;
    std::vector<int> peakLevel_;
    std::vector<int> peakChange_;  // frames left in the peak's life (the plugin's `peakchange`)
    std::vector<int> peakRef_;     // level the peak was set at (`peakreferencelevel`)
    visclassic::PeakTables peakTables_;
    visclassic::Rng rng_;
    bool rebuildPeakTables_ = true;
    visclassic::GhostState ghosts_;
    double tickAccum_ = 0;  // fraction of a 33 ms plugin frame not yet run

    // Time-based decay: scale decay by elapsed time so different frame rates produce identical visuals.
    using Clock = std::chrono::steady_clock;
    static constexpr double kRefIntervalMs = 33.333;  // 30fps baseline
    Clock::time_point lastFrameTime_{};
    bool hasLastFrameTime_ = false;
    double fixedDtMs_ = 0;  // vc_set_fixed_dt_ms: > 0 pins the frame interval for tests

public:
    void setFixedDtMs(int ms) { fixedDtMs_ = std::max(0, ms); }

private:
    std::vector<float> levelDecayAccum_;

    std::array<int, kColorCount> volumeFunc_{};
    Palette barColors_{};
    Palette peakColors_{};
    Palette volumeColors_{};
    int volume_ = 0;  // this frame's average VolumeFunction over the bars; drives the Flash background

    std::string profileMessage_;
    std::string currentProfilePath_;
    std::string currentProfileName_;
    std::string lastError_;

    void setError(const std::string &msg) { lastError_ = msg; }

    void setDefaultColors() {
        for (int i = 0; i < kColorCount; ++i) {
            barColors_[i] = RGB{static_cast<uint8_t>(clampInt(204 + i / 5, 0, 255)), static_cast<uint8_t>(i), 0};
            peakColors_[i] = RGB{static_cast<uint8_t>(clampInt(92 + (163 * i) / 255, 0, 255)),
                                 static_cast<uint8_t>((255 * i) / 255),
                                 static_cast<uint8_t>((255 * i) / 255)};
            volumeColors_[i] = RGB{static_cast<uint8_t>(i / 1.8), static_cast<uint8_t>(i / 1.6), static_cast<uint8_t>(i / 1.45)};
        }
    }

    void resetLevelTables() {
        // The plugin's DefaultSettings: a 1/x curve.
        for (int i = 0; i < kColorCount; ++i) {
            volumeFunc_[i] = 256 - 256 / (i + 1);
        }
    }

    void setupFFT() {
        fft_.Init(kWaveCount, fftFrequencies_, fftEqualize_ ? 1 : 0, fftEnvelope_, true);
    }

    void recalcGeometry() {
        drawWidth_ = std::max(1, width_);
        bandWidth_ = std::max(1, requestedBarWidth_);
        const int refW = (referenceWidth_ > 0) ? referenceWidth_ : drawWidth_;
        int newBands = std::max(1, (refW + xSpacing_) / std::max(1, bandWidth_ + xSpacing_));
        newBands = std::min(kMaxBars, newBands);
        if (!mono_) {
            newBands = std::max(2, (newBands / 2) * 2);
        }
        if (newBands != bands_) {
            bands_ = newBands;
            level_.assign(static_cast<size_t>(bands_), 0);
            peakLevel_.assign(static_cast<size_t>(bands_), 0);
            peakChange_.assign(static_cast<size_t>(bands_), 0);
            peakRef_.assign(static_cast<size_t>(bands_), 0);
            levelDecayAccum_.assign(static_cast<size_t>(bands_), 0.0f);
        }

        // The plugin's CalculateFFTVariables: start at 512 bins and double until every bar of one
        // channel gets at least two. A fixed 512 left the last bars of a 576-bar analyzer empty (#682).
        const int barUsage = mono_ ? bands_ : (bands_ + 1) / 2;
        int newFft = kDefaultFFTFrequencies;
        while (barUsage > newFft / 2) {
            newFft <<= 1;
        }
        if (newFft != fftFrequencies_) {
            fftFrequencies_ = newFft;
            fftSpectrum_.assign(static_cast<size_t>(newFft), 0.0f);
            spectrumLeft_.assign(static_cast<size_t>(newFft), 0);
            spectrumRight_.assign(static_cast<size_t>(newFft), 0);
            setupFFT();
        }
        // Mono and stereo split the table differently even at the same band count.
        rebuildBarTable_ = true;
        // The plugin clears the effects' ghosts whenever its geometry or settings are recalculated.
        ghosts_.reset(bands_, bandWidth_);
    }

    int leftBands() const { return mono_ ? bands_ : bands_ / 2; }

    // Mono: one table over every bar. Stereo: each channel's bars cover the whole spectrum, left
    // at [0, half) and right at [half, bands_), as the plugin builds them.
    void rebuildBarTableIfNeeded() {
        if (!rebuildBarTable_) {
            return;
        }
        lastBarTableSampleRate_ = sampleRate_;
        const unsigned int fft = static_cast<unsigned int>(fftFrequencies_);
        const int half = leftBands();
        LogBarValueTable(fft, sampleRate_, 16000, static_cast<unsigned int>(half), barTable_.data());
        if (!mono_) {
            LogBarValueTable(fft, sampleRate_, 16000, static_cast<unsigned int>(bands_ - half), barTable_.data() + half);
        }
        rebuildBarTable_ = false;
    }

    int monoLevel(int low, int high) const {
        if (levelBase_ == 0) {
            return UnionLevelCalcMono(low, high, spectrumLeft_.data(), spectrumRight_.data());
        }
        return AverageLevelCalcMono(low, high, spectrumLeft_.data(), spectrumRight_.data());
    }

    int stereoLevel(const std::vector<uint8_t> &src, int low, int high) const {
        if (levelBase_ == 0) {
            return UnionLevelCalcStereo(low, high, src.data());
        }
        return AverageLevelCalcStereo(low, high, src.data());
    }

    void updatePeaks(size_t idx, int barLevel, double dtScale, int ticks) {
        float scaledFalloff = static_cast<float>(falloffRate_) * static_cast<float>(dtScale)
                              + levelDecayAccum_[idx];
        int intFalloff = static_cast<int>(scaledFalloff);
        levelDecayAccum_[idx] = scaledFalloff - static_cast<float>(intFalloff);

        if (barLevel > (level_[idx] - intFalloff)) {
            level_[idx] = barLevel;
            levelDecayAccum_[idx] = 0.0f;
        } else {
            level_[idx] = std::max(0, level_[idx] - intFalloff);
        }
        stepPeak(idx, ticks);
    }

    void decayWhenIdle(double dtScale, int ticks) {
        for (size_t i = 0; i < level_.size(); ++i) {
            float scaledFalloff = static_cast<float>(falloffRate_) * static_cast<float>(dtScale)
                                  + levelDecayAccum_[i];
            int intFalloff = static_cast<int>(scaledFalloff);
            levelDecayAccum_[i] = scaledFalloff - static_cast<float>(intFalloff);
            level_[i] = std::max(0, level_[i] - intFalloff);
            stepPeak(i, ticks);
        }
    }

    // The plugin's per-frame peak step, run once per elapsed 33 ms tick. A peak restarts its life
    // from the bar when its life runs out or the bar reaches it; otherwise it follows its table.
    // With no tick this frame, only the bar-reached restart applies, so a peak never lags under its bar.
    void stepPeak(size_t i, int ticks) {
        const auto restart = [&] {
            const int level = clampInt(level_[i], 0, 255);
            peakChange_[i] = peakTables_.length[static_cast<size_t>(level)];
            peakRef_[i] = peakChangeRate_ > 0 ? level : 0;
            peakLevel_[i] = peakTables_.level[static_cast<size_t>(peakRef_[i])][static_cast<size_t>(peakChange_[i])];
        };
        if (ticks == 0) {
            if (peakLevel_[i] <= level_[i]) restart();
            return;
        }
        for (int t = 0; t < ticks; ++t) {
            if (peakChange_[i]-- == 0 || peakLevel_[i] <= level_[i]) {
                restart();
            } else {
                peakLevel_[i] = peakTables_.level[static_cast<size_t>(peakRef_[i])][static_cast<size_t>(peakChange_[i])];
            }
        }
    }

    visclassic::PeakColourFn peakColourScheme() const {
        switch (peakColourStyle_) {
        case 1: return PeakColourLevel;
        case 2: return PeakColourLevelFade;
        default: return PeakColourFade;
        }
    }

    void rebuildPeakTablesIfNeeded() {
        if (!rebuildPeakTables_) return;
        peakTables_ = visclassic::PeakTables{};
        visclassic::buildPeakTables(peakTables_, peakEffect_, peakChangeRate_, peakLogFalloff_, peakColourScheme(), rng_);
        std::fill(peakLevel_.begin(), peakLevel_.end(), 0);
        std::fill(peakChange_.begin(), peakChange_.end(), 0);
        std::fill(peakRef_.begin(), peakRef_.end(), 0);
        rebuildPeakTables_ = false;
    }

public:
    void processFrameOnly() {
        rebuildBarTableIfNeeded();
        rebuildPeakTablesIfNeeded();

        // Scale decay by elapsed time so different frame rates produce identical visuals.
        double dtScale = 1.0;
        auto now = Clock::now();
        if (fixedDtMs_ > 0) {
            dtScale = fixedDtMs_ / kRefIntervalMs;
        } else if (hasLastFrameTime_) {
            double dtMs = std::chrono::duration<double, std::milli>(now - lastFrameTime_).count();
            dtMs = std::min(dtMs, 200.0);  // clamp after window-hidden gaps
            dtScale = dtMs / kRefIntervalMs;
        }
        lastFrameTime_ = now;
        hasLastFrameTime_ = true;

        // Plugin-frame steps (peaks, and the effects' ghosts) run in whole 33 ms ticks.
        const double ticksExact = dtScale + tickAccum_;
        const int ticks = static_cast<int>(ticksExact);
        tickAccum_ = ticksExact - ticks;

        if (!hasWaveform_) {
            decayWhenIdle(dtScale, ticks);
            stepGhosts(ticks);
            return;
        }

        // Left
        for (int i = 0; i < kWaveCount; ++i) {
            floatWave_[i] = static_cast<float>(static_cast<int>(waveLeft_[i]) - 128);
        }
        fft_.time_to_frequency_domain(floatWave_.data(), fftSpectrum_.data());
        for (int i = 0; i < fftFrequencies_; ++i) {
            unsigned int h = static_cast<unsigned int>(fftSpectrum_[static_cast<size_t>(i)] / fftScale_);
            spectrumLeft_[static_cast<size_t>(i)] = static_cast<uint8_t>((h > 255) ? 255 : h);
        }

        // Right
        for (int i = 0; i < kWaveCount; ++i) {
            floatWave_[i] = static_cast<float>(static_cast<int>(waveRight_[i]) - 128);
        }
        fft_.time_to_frequency_domain(floatWave_.data(), fftSpectrum_.data());
        for (int i = 0; i < fftFrequencies_; ++i) {
            unsigned int h = static_cast<unsigned int>(fftSpectrum_[static_cast<size_t>(i)] / fftScale_);
            spectrumRight_[static_cast<size_t>(i)] = static_cast<uint8_t>((h > 255) ? 255 : h);
        }

        int volumeSum = 0;
        if (mono_) {
            int low = 0;
            int x = reverseRight_ ? bands_ - 1 : 0;
            int dir = reverseRight_ ? -1 : 1;
            for (int i = 0; i < bands_; ++i, x += dir) {
                int high = low + static_cast<int>(barTable_[static_cast<size_t>(i)]);
                high = std::min(high, fftFrequencies_);
                int newLevel = monoLevel(low, high);
                low = high;
                volumeSum += volumeFunc_[static_cast<size_t>(clampInt(newLevel, 0, 255))];
                updatePeaks(static_cast<size_t>(x), newLevel, dtScale, ticks);
            }
        } else {
            const int half = leftBands();

            int low = 0;
            int x = reverseLeft_ ? half - 1 : 0;
            int dir = reverseLeft_ ? -1 : 1;
            for (int i = 0; i < half; ++i, x += dir) {
                int high = low + static_cast<int>(barTable_[static_cast<size_t>(i)]);
                high = std::min(high, fftFrequencies_);
                int newLevel = stereoLevel(spectrumLeft_, low, high);
                low = high;
                volumeSum += volumeFunc_[static_cast<size_t>(clampInt(newLevel, 0, 255))];
                updatePeaks(static_cast<size_t>(x), newLevel, dtScale, ticks);
            }

            low = 0;
            x = reverseRight_ ? bands_ - 1 : half;
            dir = reverseRight_ ? -1 : 1;
            for (int i = half; i < bands_; ++i, x += dir) {
                int high = low + static_cast<int>(barTable_[static_cast<size_t>(i)]);
                high = std::min(high, fftFrequencies_);
                int newLevel = stereoLevel(spectrumRight_, low, high);
                low = high;
                volumeSum += volumeFunc_[static_cast<size_t>(clampInt(newLevel, 0, 255))];
                updatePeaks(static_cast<size_t>(x), newLevel, dtScale, ticks);
            }
        }

        volume_ = clampInt(volumeSum / bands_, 0, 255);
        stepGhosts(ticks);
        hasWaveform_ = false;
    }

    visclassic::BarColourFn barColourScheme() const {
        switch (barColourStyle_) {
        case 1: return BarColourFire;
        case 2: return BarColourLines;
        case 3: return BarColourWinampFire;
        case 4: return BarColourElevator;
        default: return BarColourClassic;
        }
    }

    void stepGhosts(int ticks) {
        for (int t = 0; t < ticks; ++t) {
            visclassic::advanceGhosts(ghosts_, effect_, level_, bandWidth_, xSpacing_, rng_);
        }
    }

    // Each bar's [start, end) columns at this canvas width.
    void barColumns(int width, std::vector<int> &starts, std::vector<int> &ends) const {
        starts.clear();
        ends.clear();
        for (int bar = 0; bar < bands_; ++bar) {
            int xStart = 0;
            int xEnd = 0;
            if (fitToWidth_) {
                xStart = (bar * width) / bands_;
                xEnd = ((bar + 1) * width) / bands_;
                if (xStart >= width) break;
                if (xEnd <= xStart) {
                    xEnd = xStart + 1;
                }
                if (xSpacing_ > 0 && (xEnd - xStart) > 1) {
                    xEnd -= std::min(xSpacing_, (xEnd - xStart) - 1);
                }
            } else {
                xStart = bar * (bandWidth_ + xSpacing_);
                if (xStart >= width) break;
                xEnd = std::min(width, xStart + bandWidth_);
            }
            starts.push_back(xStart);
            ends.push_back(xEnd);
        }
    }

    void drawFrame(uint8_t *dst, int width, int height, size_t stride) {
        if (!dst || width <= 0 || height <= 0 || stride < static_cast<size_t>(width * 4)) {
            return;
        }
        draw_height = height;

        visclassic::DrawContext ctx;
        ctx.dst = dst;
        ctx.w = width;
        ctx.h = height;
        ctx.stride = stride;
        ctx.ySpacing = ySpacing_;
        ctx.barWidth = bandWidth_;
        ctx.xSpacing = xSpacing_;
        barColumns(width, ctx.barStart, ctx.barEnd);
        ctx.level = level_.data();
        ctx.peak = peakLevel_.data();
        ctx.peakColour.resize(ctx.barStart.size());
        for (size_t bar = 0; bar < ctx.barStart.size(); ++bar) {
            ctx.peakColour[bar] = peakTables_.colour[static_cast<size_t>(peakRef_[bar])][static_cast<size_t>(peakChange_[bar])];
        }
        ctx.barScheme = barColourScheme();
        ctx.bars = &barColors_;
        ctx.peaks = &peakColors_;
        ctx.volumes = &volumeColors_;

        // Rows the passes below leave alone stay black, or clear when the skin shows through;
        // a transparent canvas draws no BackgroundDraw at all.
        for (int y = 0; y < height; ++y) {
            uint8_t *line = dst + static_cast<size_t>(y) * stride;
            for (int x = 0; x < width; ++x) {
                line[x * 4 + 0] = 0;
                line[x * 4 + 1] = 0;
                line[x * 4 + 2] = 0;
                line[x * 4 + 3] = transparentBg_ ? 0 : 255;
            }
        }
        if (!transparentBg_) {
            visclassic::drawBackground(ctx, backgroundDraw_, effect_, volume_);
        }
        visclassic::drawBars(ctx, effect_, ghosts_);
    }

public:
    void drawAtSize(unsigned char *outRGBA, int w, int h, int stride) {
        drawFrame(outRGBA, w, h, static_cast<size_t>(stride));
    }

    static bool readProfile(const std::string &path, IniProfile &out) {
        std::ifstream in(path);
        if (!in) {
            return false;
        }

        std::string section;
        std::string line;
        while (std::getline(in, line)) {
            line = trim(line);
            if (line.empty()) continue;
            if (line[0] == ';' || line[0] == '#') continue;
            if (line.front() == '[' && line.back() == ']') {
                section = line.substr(1, line.size() - 2);
                continue;
            }

            const size_t eq = line.find('=');
            if (eq == std::string::npos) continue;
            std::string key = trim(line.substr(0, eq));
            std::string value = trim(line.substr(eq + 1));

            if (section == "Classic Analyzer") {
                out.analyzer[key] = value;
                continue;
            }

            int idx = -1;
            if (!parseInt(key, idx) || idx < 0 || idx >= kColorCount) {
                continue;
            }

            RGB c;
            if (!parseRGB(value, c)) {
                continue;
            }

            if (section == "BarColours") {
                out.barColors[static_cast<size_t>(idx)] = c;
                out.hasBarColors = true;
            } else if (section == "PeakColours") {
                out.peakColors[static_cast<size_t>(idx)] = c;
                out.hasPeakColors = true;
            } else if (section == "VolumeColours") {
                out.volumeColors[static_cast<size_t>(idx)] = c;
                out.hasVolumeColors = true;
            }
        }

        // Second pass: parse VolumeFunction (integer values, not RGB)
        {
            std::ifstream in2(path);
            std::string section2;
            std::string line2;
            while (std::getline(in2, line2)) {
                line2 = trim(line2);
                if (line2.empty() || line2[0] == ';' || line2[0] == '#') continue;
                if (line2.front() == '[' && line2.back() == ']') {
                    section2 = line2.substr(1, line2.size() - 2);
                    continue;
                }
                if (section2 != "VolumeFunction") continue;
                const size_t eq = line2.find('=');
                if (eq == std::string::npos) continue;
                int idx2 = -1;
                if (!parseInt(trim(line2.substr(0, eq)), idx2) || idx2 < 0 || idx2 >= kColorCount) continue;
                int val = 0;
                if (!parseInt(trim(line2.substr(eq + 1)), val)) continue;
                out.volumeFunc[static_cast<size_t>(idx2)] = val;
                out.hasVolumeFunc = true;
            }
        }

        return true;
    }
};

}  // namespace

struct VisClassicCore {
    Core impl;
    std::string lastError;

    explicit VisClassicCore(int width, int height) : impl(width, height) {}
};

extern "C" {

VisClassicCore *vc_create(int width, int height) {
    try {
        return new VisClassicCore(width, height);
    } catch (...) {
        return nullptr;
    }
}

void vc_destroy(VisClassicCore *core) {
    delete core;
}

void vc_set_waveform_u8(VisClassicCore *core,
                        const uint8_t *left,
                        const uint8_t *right,
                        size_t count,
                        double sample_rate) {
    if (!core) return;
    core->impl.setWaveform(left, right, count, sample_rate);
}

int vc_set_option(VisClassicCore *core, const char *key, int value) {
    if (!core || !key) return 0;
    return core->impl.setOption(key, value);
}

int vc_get_option(VisClassicCore *core, const char *key, int *value_out) {
    if (!core || !key || !value_out) return 0;
    return core->impl.getOption(key, value_out);
}

int vc_load_profile_ini(VisClassicCore *core, const char *path_utf8) {
    if (!core || !path_utf8) return 0;
    const int ok = core->impl.loadProfile(path_utf8);
    if (!ok) {
        core->lastError = core->impl.lastError();
    }
    return ok;
}

int vc_save_profile_ini(VisClassicCore *core, const char *path_utf8) {
    if (!core || !path_utf8) return 0;
    const int ok = core->impl.saveProfile(path_utf8);
    if (!ok) {
        core->lastError = core->impl.lastError();
    }
    return ok;
}

const char *vc_get_last_error(VisClassicCore *core) {
    if (!core) return "";
    return core->lastError.c_str();
}

void vc_process_frame_only(VisClassicCore *core) {
    if (!core) return;
    core->impl.processFrameOnly();
}

int vc_draw_at_size(VisClassicCore *core, unsigned char *outRGBA, int width, int height, int stride) {
    if (!core) return 0;
    core->impl.drawAtSize(outRGBA, width, height, stride);
    return 1;
}

void vc_set_fixed_dt_ms(VisClassicCore *core, int ms) {
    if (!core) return;
    core->impl.setFixedDtMs(ms);
}

}  // extern "C"
