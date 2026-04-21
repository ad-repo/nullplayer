# Contributing to NullPlayer

Thanks for your interest in contributing to NullPlayer!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/nullplayer.git`
3. Run `./scripts/bootstrap.sh` to download required frameworks
4. Build with `./scripts/kill_build_run.sh` or open `Package.swift` in Xcode
5. Run `swift test` for relevant automated coverage before opening a PR

## Important: Streaming Service Restrictions

**We do not accept PRs for integration with:**

- Spotify
- Apple Music
- YouTube / YouTube Music
- Amazon Music
- Google Play Music

These services have restrictive APIs and licensing terms that are incompatible with this project. PRs adding support for these services will be closed without review.

**Supported backends and integrations:** local files, Plex, Jellyfin, Emby, Subsonic / Navidrome, internet radio, Chromecast, Sonos, DLNA, AirPlay.

## How to Contribute

### Reporting Bugs

- Check existing issues first to avoid duplicates
- Include macOS version and NullPlayer version
- Provide steps to reproduce
- Include relevant logs from Console.app if applicable

### Suggesting Features

- Open an issue describing the feature
- Explain the use case and why it would be useful
- Be open to discussion about implementation approaches
- Do not open a feature PR without an issue

### Submitting Code

1. Create a branch for your changes: `git checkout -b feature/my-feature`
2. Confirm there is a GitHub issue for the bug, feature, or refactor before writing the PR
3. Make your changes following the code style below
4. Test your changes thoroughly
5. Collect proof of the issue and proof of testing for the PR description
6. Add a PR comment with reviewer-facing step-by-step "How to test" instructions
7. Commit with clear, descriptive messages
8. Push and open a Pull Request

## Code Style

- Follow existing patterns in the codebase
- Use Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Keep functions focused and reasonably sized
- Add comments for complex logic
- Avoid speculative fixes that are not backed by a real issue or demonstrated user impact

### UI Changes

Before making UI changes:

1. Read [skills/ui-guide/SKILL.md](skills/ui-guide/SKILL.md)
2. Check `SkinElements.swift` for sprite coordinates
3. Follow existing patterns in `MainWindowView` or `EQView`
4. Test at different window sizes
5. Test with multiple skins

## Documentation

- Update relevant docs if your change affects user-facing behavior
- Keep [skills/user-guide/SKILL.md](skills/user-guide/SKILL.md) current for feature changes
- Update [AGENTS.md](AGENTS.md) if adding new key files

## Pull Request Requirements

We keep PRs small, testable, and tied to real user problems.

### PR Size

- Keep each PR narrowly scoped to one issue, bug, feature, or refactor
- Large mixed PRs are difficult to review and verify and may be closed or asked to be split
- Mechanical cleanup, refactors, logging changes, and behavior changes should usually be separate PRs
- If a change touches multiple systems, the PR description must explain exactly why that scope is necessary

### Real Problems Only

We do not want speculative fixes.

- Do not submit fixes for problems found by AI tools unless there is evidence that the problem is real
- "AI suggested this might be wrong" is not sufficient
- Every fix must be tied to one of the following:
  - a confirmed user-facing bug
  - a reproducible failure
  - a crash with evidence
  - a regression
  - a warning or deprecation that has a clear product or maintenance impact
- PRs based only on hypothetical issues, style-only cleanup, or unproven possible bugs may be closed without merge

### AI-Assisted Changes

AI-assisted work is allowed, but the author is fully responsible for correctness.

- Review all AI-generated code before opening the PR
- Do not submit code you do not understand
- Do not use AI to generate broad cleanup or "fix everything" changes without verifying each change individually
- If AI was used to help create the PR, say so clearly in the PR description
- The PR author must still provide proof of the issue, proof of testing, and clear manual test steps

### Required PR Description

Every PR must include all of the following:

- **Issue reference:** link to the GitHub issue the PR addresses
- **Problem evidence:** reproduction steps, logs, screenshots, crash details, or a clear explanation of the real user impact
- **What changed:** short summary of the implementation
- **Proof of testing:** build results, test results, and manual verification notes
- **How to test:** a comment on the PR with step-by-step instructions another reviewer can follow

PRs without an issue, without proof of testing, or without a reviewer-facing how to test comment may be closed.

### Testing Expectations

All changes must be fully tested before the PR is opened.

- Run all relevant automated tests
- Verify the app builds cleanly
- Manually test every affected code path
- Test regressions, not just the happy path
- If the change touches playback, UI state, streaming, casting, skins, or integrations, those paths must be exercised directly

Include the exact testing performed in the PR description and add a PR comment that explains how a reviewer should test the change.

### Backend and Integration Checklist

Include a checklist in the PR description and mark every backend or integration you tested. If a backend was affected but not tested, explain why.

#### Tested Backends

- [ ] Local files
- [ ] Plex
- [ ] Jellyfin
- [ ] Emby
- [ ] Subsonic / Navidrome
- [ ] Internet radio

#### Tested Integrations

- [ ] Sonos
- [ ] Chromecast
- [ ] DLNA / UPnP
- [ ] AirPlay

#### Additional Verification

- [ ] App builds successfully
- [ ] Relevant automated tests pass
- [ ] Manual testing completed
- [ ] Regression testing completed for affected areas
- [ ] PR links to an issue
- [ ] PR includes proof of the issue
- [ ] PR includes proof of testing
- [ ] PR includes a reviewer-facing comment with "How to test"

### Comment Resolution

All PR comments must be resolved before a PR can be merged.

- This includes comments from human reviewers
- This includes automated review comments, including CodeRabbit comments
- Authors are responsible for either fixing the issue or responding clearly with evidence for why no code change is needed
- A PR is not ready to merge while review comments remain unresolved

### Reviewer Notes

Reviewers may close PRs that:

- are too large or unfocused
- do not link to an issue
- do not show proof that the problem is real
- do not include adequate testing
- rely on AI-generated fixes without demonstrating real user impact

## License

By contributing, you agree that your contributions will be licensed under the project's GPL-3.0 license.

## Questions?

Open an issue if you have questions about contributing.
