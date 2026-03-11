# Waveform Implementation Provenance Audit

- Date: 2026-03-11
- Scope: `Sources/NullPlayer/Waveform/`
- Purpose: document whether waveform implementation appears directly derived from `gen-waveseek`.

## Files Reviewed

- `Sources/NullPlayer/Waveform/BaseWaveformView.swift`
- `Sources/NullPlayer/Waveform/WaveformCacheService.swift`
- `Sources/NullPlayer/Waveform/WaveformDrawing.swift`
- `Sources/NullPlayer/Waveform/WaveformModels.swift`

## Audit Method

1. Symbol and identifier fingerprint scan for `gen-waveseek`-specific names:

```bash
rg -n "embed_guid|DummySAVSAInit|DummyVSAAdd|IPC_GETINIFILEW|IPC_GETINIDIRECTORYW|PLUGIN_VERSION \"2\\.3\\.1\"|gen_waveseek|WAVEFORM_SEEK_MENUID|wavecache" -S Sources Tests scripts README.md CLAUDE.md
```

Result: no matches.

2. Phrase scan for upstream `gen-waveseek` README/plugin wording:

```bash
rg -n "Waveform seek plugin for Winamp|skip to the drop|getwacup|Gargaj/gen-waveseek" -S Sources Tests scripts README.md CLAUDE.md
```

Result: no matches.

3. Structural review of local waveform implementation:
- Local code is Swift/AppKit with `AVAudioFile` decode, 4096-bucket caching, and a streaming accumulator pipeline.
- No copied C/C++ plugin scaffolding, Winamp IPC hooks, or matching upstream symbol structure identified.

## Conclusion

As of 2026-03-11, no direct-copy evidence from `gen-waveseek` was found in `Sources/NullPlayer/Waveform/`. The implementation appears independently developed from the audited repo content.

## Release Rule

If direct derivation from `gen-waveseek` is later discovered, halt external source/binary distribution until one of these is completed:

1. Obtain explicit permission or a clear license grant for the derived code and add required notices.
2. Remove or replace the derived implementation with clean-room code.

This is an engineering provenance record, not legal advice.
