# Agent Instructions

See [CLAUDE.md](CLAUDE.md) for documentation, key source files, and development guidelines.

Technical documentation is in the `skills/` directory.

For agent development and verification, use debug builds (`./scripts/kill_build_run.sh --debug`
or `swift build -c debug`). Do not build a DMG unless the user explicitly requests one.
