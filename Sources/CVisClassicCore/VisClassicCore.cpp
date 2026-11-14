#include "VisClassicCore.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstring>
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
#include "VisClassicProfile.h"

thread_local int draw_height = 0;  // Used by upstream bar color helpers.

namespace {

constexpr int kWaveCount = 576;
constexpr int kMaxBars = 576;
constexpr int kColorCount = 256;
constexpr int kDefaultFFTFrequencies = 512;

using visclassic::Palette;
using visclassic::RGB;
using visclassic::trim;

static inline int clampInt(int v, int lo, int hi) {
    return std::max(lo, std::min(hi, v));
}

static inline std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

class Core {
public:
    // `referenceWidth` sets the band count (as `referencewidth` does later); each draw fits the bands
    // to its own canvas.
    explicit Core(int referenceWidth) : referenceWidth_(std::max(1, referenceWidth)) {
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
            referenceWidth_ = std::max(1, value);
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
        visclassic::IniProfile profile;
        if (!visclassic::readProfile(path, profile)) {
            setError("Failed to parse profile");
            return 0;
        }

        falloffRate_ = profile.analyzerInt("Falloff", falloffRate_, 0, 75);
        peakChangeRate_ = profile.analyzerInt("PeakChange", peakChangeRate_, 0, 255);
        requestedBarWidth_ = profile.analyzerInt("Bar Width", requestedBarWidth_, 1, 64);
        xSpacing_ = profile.analyzerInt("X-Spacing", xSpacing_, 0, 32);
        ySpacing_ = profile.analyzerInt("Y-Spacing", ySpacing_, 1, 7);
        backgroundDraw_ = profile.analyzerInt("BackgroundDraw", backgroundDraw_, 0, 4);
        barColourStyle_ = profile.analyzerInt("BarColourStyle", barColourStyle_, 0, 4);
        peakColourStyle_ = profile.analyzerInt("PeakColourStyle", peakColourStyle_, 0, 2);
        effect_ = profile.analyzerInt("Effect", effect_, 0, 7);
        peakEffect_ = profile.analyzerInt("Peak Effect", peakEffect_, 0, 5);
        peakLogFalloff_ = profile.analyzerInt("PeakFallOffMode", peakLogFalloff_ ? 1 : 0, 0, 1) != 0;
        rebuildPeakTables_ = true;
        reverseLeft_ = profile.analyzerInt("ReverseLeft", reverseLeft_ ? 1 : 0, 0, 1) != 0;
        reverseRight_ = profile.analyzerInt("ReverseRight", reverseRight_ ? 1 : 0, 0, 1) != 0;
        mono_ = profile.analyzerInt("Mono", mono_ ? 1 : 0, 0, 1) != 0;
        levelBase_ = profile.analyzerInt("Bar Level", levelBase_, 0, 1);
        fftEqualize_ = profile.analyzerInt("FFTEqualize", fftEqualize_ ? 1 : 0, 0, 1) != 0;
        fftEnvelope_ = std::max(0.01f, static_cast<float>(profile.analyzerInt("FFTEnvelope", static_cast<int>(fftEnvelope_ * 100.0f), 1, 1000)) / 100.0f);
        fftScale_ = std::max(0.01f, static_cast<float>(profile.analyzerInt("FFTScale", static_cast<int>(fftScale_ * 100.0f), 1, 2000)) / 100.0f);
        fitToWidth_ = profile.analyzerInt("FitToWidth", fitToWidth_ ? 1 : 0, 0, 1) != 0;

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
        currentProfileName_ = visclassic::stemFromPath(path);
        return 1;
    }

    int saveProfile(const std::string &path) {
        auto n = [](int v) { return std::to_string(v); };
        const std::vector<std::pair<std::string, std::string>> analyzer = {
            {"Falloff", n(falloffRate_)},
            {"PeakChange", n(peakChangeRate_)},
            {"Bar Width", n(requestedBarWidth_)},
            {"X-Spacing", n(xSpacing_)},
            {"Y-Spacing", n(ySpacing_)},
            {"BackgroundDraw", n(backgroundDraw_)},
            {"BarColourStyle", n(barColourStyle_)},
            {"PeakColourStyle", n(peakColourStyle_)},
            {"Effect", n(effect_)},
            {"Peak Effect", n(peakEffect_)},
            {"PeakFallOffMode", n(peakLogFalloff_ ? 1 : 0)},
            {"ReverseLeft", n(reverseLeft_ ? 1 : 0)},
            {"ReverseRight", n(reverseRight_ ? 1 : 0)},
            {"Mono", n(mono_ ? 1 : 0)},
            {"Bar Level", n(levelBase_)},
            {"FFTEqualize", n(fftEqualize_ ? 1 : 0)},
            {"FFTEnvelope", n(static_cast<int>(fftEnvelope_ * 100.0f + 0.5f))},
            {"FFTScale", n(static_cast<int>(fftScale_ * 100.0f + 0.5f))},
            {"FitToWidth", n(fitToWidth_ ? 1 : 0)},
            {"Message", profileMessage_},
        };
        if (!visclassic::writeProfile(path, analyzer, barColors_, peakColors_, volumeColors_, volumeFunc_)) {
            setError("Unable to open profile for writing");
            return 0;
        }

        currentProfilePath_ = path;
        currentProfileName_ = visclassic::stemFromPath(path);
        return 1;
    }

    const std::string &lastError() const { return lastError_; }

    void setFixedDtMs(int ms) { fixedDtMs_ = std::max(0, ms); }

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

        spectrumOf(waveLeft_, spectrumLeft_);
        spectrumOf(waveRight_, spectrumRight_);

        int volumeSum = 0;
        if (mono_) {
            volumeSum += runBars(0, bands_, reverseRight_, dtScale, ticks, [&](int low, int high) { return monoLevel(low, high); });
        } else {
            const int half = leftBands();
            volumeSum += runBars(0, half, reverseLeft_, dtScale, ticks,
                                 [&](int low, int high) { return stereoLevel(spectrumLeft_, low, high); });
            volumeSum += runBars(half, bands_ - half, reverseRight_, dtScale, ticks,
                                 [&](int low, int high) { return stereoLevel(spectrumRight_, low, high); });
        }

        volume_ = clampInt(volumeSum / bands_, 0, 255);
        stepGhosts(ticks);
        hasWaveform_ = false;
    }

    void drawAtSize(unsigned char *outRGBA, int w, int h, int stride) {
        drawFrame(outRGBA, w, h, static_cast<size_t>(stride));
    }


private:
    int bands_ = 1;
    int bandWidth_ = 3;
    int referenceWidth_ = 1;  // the width the band count is computed for

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
    visclassic::DrawContext drawScratch_;  // drawFrame's buffers, kept to avoid per-frame allocation
    double tickAccum_ = 0;  // fraction of a 33 ms plugin frame not yet run

    // Time-based decay: scale decay by elapsed time so different frame rates produce identical visuals.
    using Clock = std::chrono::steady_clock;
    static constexpr double kRefIntervalMs = 33.333;  // 30fps baseline
    Clock::time_point lastFrameTime_{};
    bool hasLastFrameTime_ = false;
    double fixedDtMs_ = 0;  // vc_set_fixed_dt_ms: > 0 pins the frame interval for tests

    std::vector<float> levelDecayAccum_;

    visclassic::VolumeFunction volumeFunc_{};
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
        bandWidth_ = std::max(1, requestedBarWidth_);
        int newBands = std::max(1, (referenceWidth_ + xSpacing_) / std::max(1, bandWidth_ + xSpacing_));
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

    // One channel's FFT, scaled to 0..255 per bin.
    void spectrumOf(const std::array<uint8_t, kWaveCount> &wave, std::vector<uint8_t> &out) {
        for (int i = 0; i < kWaveCount; ++i) {
            floatWave_[i] = static_cast<float>(static_cast<int>(wave[i]) - 128);
        }
        fft_.time_to_frequency_domain(floatWave_.data(), fftSpectrum_.data());
        for (int i = 0; i < fftFrequencies_; ++i) {
            const unsigned int h = static_cast<unsigned int>(fftSpectrum_[static_cast<size_t>(i)] / fftScale_);
            out[static_cast<size_t>(i)] = static_cast<uint8_t>((h > 255) ? 255 : h);
        }
    }

    // Bars [first, first + count) read consecutive bins from `barTable_`'s entries for them, low to
    // high frequency, and are laid out left to right or, `reverse`, right to left. Returns the bars'
    // VolumeFunction sum.
    template <typename LevelAt>
    int runBars(int first, int count, bool reverse, double dtScale, int ticks, LevelAt levelAt) {
        int volumeSum = 0;
        int low = 0;
        int x = reverse ? first + count - 1 : first;
        const int dir = reverse ? -1 : 1;
        for (int i = first; i < first + count; ++i, x += dir) {
            const int high = std::min(low + static_cast<int>(barTable_[static_cast<size_t>(i)]), fftFrequencies_);
            const int newLevel = levelAt(low, high);
            low = high;
            volumeSum += volumeFunc_[static_cast<size_t>(clampInt(newLevel, 0, 255))];
            updatePeaks(static_cast<size_t>(x), newLevel, dtScale, ticks);
        }
        return volumeSum;
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

        visclassic::DrawContext &ctx = drawScratch_;  // reused: no allocation per frame
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
};

}  // namespace

struct VisClassicCore {
    Core impl;
    std::string lastError;

    explicit VisClassicCore(int width) : impl(width) {}
};

extern "C" {

VisClassicCore *vc_create(int width, int height) {
    try {
        (void)height;  // the band count comes from the width; each draw passes its own size
        return new VisClassicCore(width);
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
