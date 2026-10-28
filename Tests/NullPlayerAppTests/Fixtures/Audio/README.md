# Synthetic audio fixture

`opus-in-m4a.m4a` is 0.537 seconds of two generated tones (440 Hz left at 0.2,
660 Hz right at 0.1), 48 kHz stereo, encoded with FFmpeg/libopus. It contains no
third-party recording. The duration is deliberately not a multiple of a 20 ms
Opus packet, exercising pre-skip and final-packet trimming.

Regenerate from the repository root (FFmpeg is needed only to regenerate, not to run tests):

```sh
ffmpeg -v error -f lavfi \
  -i 'aevalsrc=0.2*sin(2*PI*440*t)|0.1*sin(2*PI*660*t):s=48000:d=0.537' \
  -c:a libopus -b:a 96k -map_metadata -1 -f mp4 -y \
  Tests/NullPlayerAppTests/Fixtures/Audio/opus-in-m4a.m4a
```

The `.m4a` suffix reproduces valid MPEG-4 Opus downloads. FFmpeg's default M4A
muxer rejects Opus, hence the explicit `-f mp4`.

`aac-in-m4a.m4a` is the same source encoded with `-c:a aac -b:a 96k` (without
`-f mp4`), a control for the existing native M4A path.
