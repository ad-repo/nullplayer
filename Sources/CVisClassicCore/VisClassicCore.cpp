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
#include "upstream/LevelFunc.h"
#include "upstream/LogBarTable.h"
#include "upstream/PeakColour.h"
#include "upstream/fft.h"

thread_local int draw_height = 0;  // Used by upstream bar color helpers.

namespace {

constexpr int kWaveCount = 576;
constexpr int kMaxBars = 576;
constexpr int kColorCount = 256;
constexpr int kDefaultFFTFrequencies = 512;

struct RGB {
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
};

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

static inline bool parseBGR(const std::string &s, RGB &out) {
    std::istringstream iss(s);
    int b = 0, g = 0, r = 0;
    if (!(iss >> b >> g >> r)) {
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
    std::array<RGB, kColorCount> barColors{};
    std::array<RGB, kColorCount> peakColors{};
    std::array<int, kColorCount> volumeFunc{};
    bool hasBarColors = false;
    bool hasPeakColors = false;
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

    void render(uint8_t *outRGBA, int width, int height, size_t stride) {
        if (!outRGBA || width <= 0 || height <= 0 || stride < static_cast<size_t>(width * 4)) {
            return;
        }

        if (width != width_ || height != height_) {
            width_ = width;
            height_ = height;
            recalcGeometry();
        }

        processFrame();
        drawFrame(outRGBA, width, height, stride);
    }

    int setOption(const std::string &keyRaw, int value) {
        const std::string key = lower(trim(keyRaw));

        if (key == "falloff") {
            falloffRate_ = clampInt(value, 0, 255);
            return 1;
        }
        if (key == "peakchange") {
            peakChangeRate_ = clampInt(value, 0, 255);
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
            ySpacing_ = clampInt(value, 0, 32);
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
            return 1;
        }
        if (key == "effect") {
            effect_ = clampInt(value, 0, 7);
            return 1;
        }
        if (key == "peak effect" || key == "peak_effect") {
            peakEffect_ = clampInt(value, 0, 5);
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

        falloffRate_ = readAnalyzerInt("Falloff", falloffRate_, 0, 255);
        peakChangeRate_ = readAnalyzerInt("PeakChange", peakChangeRate_, 0, 255);
        requestedBarWidth_ = readAnalyzerInt("Bar Width", requestedBarWidth_, 1, 64);
        xSpacing_ = readAnalyzerInt("X-Spacing", xSpacing_, 0, 32);
        ySpacing_ = readAnalyzerInt("Y-Spacing", ySpacing_, 0, 32);
        backgroundDraw_ = readAnalyzerInt("BackgroundDraw", backgroundDraw_, 0, 4);
        barColourStyle_ = readAnalyzerInt("BarColourStyle", barColourStyle_, 0, 4);
        peakColourStyle_ = readAnalyzerInt("PeakColourStyle", peakColourStyle_, 0, 2);
        effect_ = readAnalyzerInt("Effect", effect_, 0, 7);
        peakEffect_ = readAnalyzerInt("Peak Effect", peakEffect_, 0, 5);
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
            out << i << "=" << static_cast<int>(barColors_[i].b) << " "
                << static_cast<int>(barColors_[i].g) << " "
                << static_cast<int>(barColors_[i].r) << "\n";
        }

        out << "[PeakColours]\n";
        for (int i = 0; i < kColorCount; ++i) {
            out << i << "=" << static_cast<int>(peakColors_[i].b) << " "
                << static_cast<int>(peakColors_[i].g) << " "
                << static_cast<int>(peakColors_[i].r) << "\n";
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
    std::vector<int> peakTimer_;

    // Time-based decay: scale decay by elapsed time so different frame rates produce identical visuals.
    using Clock = std::chrono::steady_clock;
    static constexpr double kRefIntervalMs = 33.333;  // 30fps baseline
    Clock::time_point lastFrameTime_{};
    bool hasLastFrameTime_ = false;
    std::vector<float> levelDecayAccum_;
    std::vector<float> peakTimerAccum_;
    std::vector<float> peakDecayAccum_;

    std::array<int, kColorCount> volumeFunc_{};
    std::array<RGB, kColorCount> barColors_{};
    std::array<RGB, kColorCount> peakColors_{};

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
        }
    }

    void resetLevelTables() {
        for (int i = 0; i < kColorCount; ++i) {
            volumeFunc_[i] = i;
        }
        // Match upstream defaults: gentle log shape for analyzer response.
        LogBase10Table(volumeFunc_.data());
    }

    void setupFFT() {
        fft_.Init(kWaveCount, fftFrequencies_, fftEqualize_ ? 1 : 0, fftEnvelope_, true);
    }

    void recalcGeometry() {
        drawWidth_ = std::max(1, width_);
        draw_height = std::max(1, height_);

        bandWidth_ = std::max(1, requestedBarWidth_);
        bands_ = std::max(1, (drawWidth_ + xSpacing_) / std::max(1, bandWidth_ + xSpacing_));
        bands_ = std::min(kMaxBars, bands_);

        if (!mono_) {
            bands_ = std::max(2, (bands_ / 2) * 2);
        }

        level_.assign(static_cast<size_t>(bands_), 0);
        peakLevel_.assign(static_cast<size_t>(bands_), 0);
        peakTimer_.assign(static_cast<size_t>(bands_), 0);
        levelDecayAccum_.assign(static_cast<size_t>(bands_), 0.0f);
        peakTimerAccum_.assign(static_cast<size_t>(bands_), 0.0f);
        peakDecayAccum_.assign(static_cast<size_t>(bands_), 0.0f);

        rebuildBarTable_ = true;
    }

    void rebuildBarTableIfNeeded() {
        if (!rebuildBarTable_) {
            return;
        }
        lastBarTableSampleRate_ = sampleRate_;
        LogBarValueTable(static_cast<unsigned int>(fftFrequencies_), sampleRate_, 16000, static_cast<unsigned int>(bands_), barTable_.data());
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

    void updatePeaks(size_t idx, int barLevel, double dtScale) {
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

        if (peakChangeRate_ <= 0) {
            peakLevel_[idx] = 0;
            peakTimer_[idx] = 0;
            return;
        }

        if (level_[idx] >= peakLevel_[idx]) {
            peakLevel_[idx] = level_[idx];
            peakTimer_[idx] = peakChangeRate_;
            peakTimerAccum_[idx] = 0.0f;
            peakDecayAccum_[idx] = 0.0f;
            return;
        }

        if (peakTimer_[idx] > 0) {
            float scaledTick = static_cast<float>(dtScale) + peakTimerAccum_[idx];
            int intTick = static_cast<int>(scaledTick);
            peakTimerAccum_[idx] = scaledTick - static_cast<float>(intTick);
            peakTimer_[idx] = std::max(0, peakTimer_[idx] - intTick);
        } else {
            float scaledDescent = static_cast<float>(dtScale) + peakDecayAccum_[idx];
            int intDescent = static_cast<int>(scaledDescent);
            peakDecayAccum_[idx] = scaledDescent - static_cast<float>(intDescent);
            peakLevel_[idx] = std::max(level_[idx], peakLevel_[idx] - intDescent);
        }
    }

    void decayWhenIdle(double dtScale) {
        for (size_t i = 0; i < level_.size(); ++i) {
            float scaledFalloff = static_cast<float>(falloffRate_) * static_cast<float>(dtScale)
                                  + levelDecayAccum_[i];
            int intFalloff = static_cast<int>(scaledFalloff);
            levelDecayAccum_[i] = scaledFalloff - static_cast<float>(intFalloff);
            level_[i] = std::max(0, level_[i] - intFalloff);

            if (peakTimer_[i] > 0) {
                float scaledTick = static_cast<float>(dtScale) + peakTimerAccum_[i];
                int intTick = static_cast<int>(scaledTick);
                peakTimerAccum_[i] = scaledTick - static_cast<float>(intTick);
                peakTimer_[i] = std::max(0, peakTimer_[i] - intTick);
            } else {
                float scaledDescent = static_cast<float>(dtScale) + peakDecayAccum_[i];
                int intDescent = static_cast<int>(scaledDescent);
                peakDecayAccum_[i] = scaledDescent - static_cast<float>(intDescent);
                peakLevel_[i] = std::max(level_[i], peakLevel_[i] - intDescent);
            }
        }
    }

    void processFrame() {
        // Upstream color helpers use a global draw_height; restore per-frame for this instance.
        draw_height = std::max(1, height_);
        rebuildBarTableIfNeeded();

        // Scale decay by elapsed time so different frame rates produce identical visuals.
        double dtScale = 1.0;
        auto now = Clock::now();
        if (hasLastFrameTime_) {
            double dtMs = std::chrono::duration<double, std::milli>(now - lastFrameTime_).count();
            dtMs = std::min(dtMs, 200.0);  // clamp after window-hidden gaps
            dtScale = dtMs / kRefIntervalMs;
        }
        lastFrameTime_ = now;
        hasLastFrameTime_ = true;

        if (!hasWaveform_) {
            decayWhenIdle(dtScale);
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

        if (mono_) {
            int low = 0;
            int x = reverseRight_ ? bands_ - 1 : 0;
            int dir = reverseRight_ ? -1 : 1;
            for (int i = 0; i < bands_; ++i, x += dir) {
                int high = low + static_cast<int>(barTable_[static_cast<size_t>(i)]);
                high = std::min(high, fftFrequencies_);
                int newLevel = monoLevel(low, high);
                low = high;
                updatePeaks(static_cast<size_t>(x), newLevel, dtScale);
            }
        } else {
            const int half = bands_ / 2;

            int low = 0;
            int x = reverseLeft_ ? half - 1 : 0;
            int dir = reverseLeft_ ? -1 : 1;
            for (int i = 0; i < half; ++i, x += dir) {
                int high = low + static_cast<int>(barTable_[static_cast<size_t>(i)]);
                high = std::min(high, fftFrequencies_);
                int newLevel = stereoLevel(spectrumLeft_, low, high);
                low = high;
                updatePeaks(static_cast<size_t>(x), newLevel, dtScale);
            }

            low = 0;
            x = reverseRight_ ? bands_ - 1 : half;
            dir = reverseRight_ ? -1 : 1;
            for (int i = 0; i < half; ++i, x += dir) {
                int high = low + static_cast<int>(barTable_[static_cast<size_t>(i)]);
                high = std::min(high, fftFrequencies_);
                int newLevel = stereoLevel(spectrumRight_, low, high);
                low = high;
                updatePeaks(static_cast<size_t>(x), newLevel, dtScale);
            }
        }

        hasWaveform_ = false;
    }

    RGB barColorForLevel(int level, int yScaled) const {
        unsigned char idx = 0;
        switch (barColourStyle_) {
        case 1:
            idx = BarColourFire(level, yScaled);
            break;
        case 2:
            idx = BarColourLines(level, yScaled);
            break;
        case 3:
            idx = BarColourWinampFire(level, yScaled);
            break;
        case 4:
            idx = BarColourElevator(level, yScaled);
            break;
        case 0:
        default:
            idx = BarColourClassic(level, yScaled);
            break;
        }
        return barColors_[idx];
    }

    RGB peakColorForLevel(int level, int yScaled) const {
        unsigned char idx = 0;
        switch (peakColourStyle_) {
        case 1:
            idx = PeakColourLevel(level, yScaled);
            break;
        case 2:
            idx = PeakColourLevelFade(level, yScaled);
            break;
        case 0:
        default:
            idx = PeakColourFade(level, yScaled);
            break;
        }
        return peakColors_[idx];
    }

    void setPixel(uint8_t *dst, int x, int y, size_t stride, const RGB &c) const {
        if (x < 0 || x >= width_ || y < 0 || y >= height_) return;
        const size_t o = static_cast<size_t>(y) * stride + static_cast<size_t>(x) * 4;
        dst[o + 0] = c.b;
        dst[o + 1] = c.g;
        dst[o + 2] = c.r;
        dst[o + 3] = 255;
    }

    void fillBackground(uint8_t *dst, size_t stride) const {
        uint8_t base = 0;
        switch (backgroundDraw_) {
        case 1: base = 18; break;   // flash-ish
        case 2: base = 10; break;   // solid dark
        case 3: base = 6; break;    // grid
        case 4: base = 8; break;    // flash grid
        default: base = 0; break;
        }

        for (int y = 0; y < height_; ++y) {
            uint8_t *row = dst + static_cast<size_t>(y) * stride;
            for (int x = 0; x < width_; ++x) {
                uint8_t v = base;
                if ((backgroundDraw_ == 3 || backgroundDraw_ == 4) && ((x % 8 == 0) || (y % 8 == 0))) {
                    v = static_cast<uint8_t>(std::min(255, base + 20));
                }
                row[x * 4 + 0] = transparentBg_ ? 0 : v;
                row[x * 4 + 1] = transparentBg_ ? 0 : v;
                row[x * 4 + 2] = transparentBg_ ? 0 : v;
                row[x * 4 + 3] = transparentBg_ ? 0 : 255;
            }
        }
    }

    void drawFrame(uint8_t *dst, int width, int height, size_t stride) const {
        (void)width;
        (void)height;
        fillBackground(dst, stride);

        const int effectiveHeight = std::max(1, draw_height);
        for (int bar = 0; bar < bands_; ++bar) {
            int xStart = 0;
            int xEnd = 0;
            if (fitToWidth_) {
                xStart = (bar * width_) / bands_;
                xEnd = ((bar + 1) * width_) / bands_;
                if (xStart >= width_) break;
                if (xEnd <= xStart) {
                    xEnd = xStart + 1;
                }
                if (xSpacing_ > 0 && (xEnd - xStart) > 1) {
                    xEnd -= std::min(xSpacing_, (xEnd - xStart) - 1);
                }
                if (xEnd <= xStart) {
                    xEnd = xStart + 1;
                }
            } else {
                xStart = bar * (bandWidth_ + xSpacing_);
                if (xStart >= width_) break;
                xEnd = std::min(width_, xStart + bandWidth_);
            }

            const int level = clampInt(level_[static_cast<size_t>(bar)], 0, 255);
            const int peak = clampInt(peakLevel_[static_cast<size_t>(bar)], 0, 255);

            int barPx = (level * effectiveHeight) / 255;
            int peakY = height_ - 1 - ((peak * effectiveHeight) / 255);

            barPx = std::max(0, std::min(height_, barPx));
            peakY = clampInt(peakY, 0, height_ - 1);

            for (int row = 0; row < barPx; ++row) {
                const int y = height_ - 1 - row;
                int yScaled = (row * 255) / effectiveHeight;
                RGB c = barColorForLevel(level, yScaled);

                for (int x = xStart; x < xEnd; ++x) {
                    setPixel(dst, x, y, stride, c);
                }

                // Approximate fade shadow effect when profile requests it.
                if (effect_ == 7) {
                    RGB shadow = c;
                    shadow.r = static_cast<uint8_t>(shadow.r / 4);
                    shadow.g = static_cast<uint8_t>(shadow.g / 4);
                    shadow.b = static_cast<uint8_t>(shadow.b / 4);
                    if (fitToWidth_) {
                        setPixel(dst, xEnd, y, stride, shadow);
                    } else {
                        setPixel(dst, xStart + bandWidth_, y, stride, shadow);
                    }
                }
            }

            if (peakChangeRate_ > 0) {
                const int yScaled = ((height_ - 1 - peakY) * 255) / effectiveHeight;
                RGB pc = peakColorForLevel(level, yScaled);
                for (int x = xStart; x < xEnd; ++x) {
                    setPixel(dst, x, peakY, stride, pc);
                }
            }
        }
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
            if (!parseBGR(value, c)) {
                continue;
            }

            if (section == "BarColours") {
                out.barColors[static_cast<size_t>(idx)] = c;
                out.hasBarColors = true;
            } else if (section == "PeakColours") {
                out.peakColors[static_cast<size_t>(idx)] = c;
                out.hasPeakColors = true;
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

void vc_render_rgba(VisClassicCore *core,
                    uint8_t *out_rgba,
                    int width,
                    int height,
                    size_t stride) {
    if (!core) return;
    core->impl.render(out_rgba, width, height, stride);
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

}  // extern "C"
