# Contributing to AdAmp

Thanks for your interest in contributing to AdAmp!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/adamp.git`
3. Run `./scripts/bootstrap.sh` to download required frameworks
4. Build with `./scripts/kill_build_run.sh` or open `Package.swift` in Xcode

## Important: Streaming Service Restrictions

**We do not accept PRs for integration with:**

- Spotify
- Apple Music
- YouTube / YouTube Music
- Amazon Music
- Google Play Music

These services have restrictive APIs and licensing terms that are incompatible with this project. PRs adding support for these services will be closed without review.

**Supported integrations:** Plex, local files, Chromecast, Sonos, DLNA, AirPlay.

## How to Contribute

### Reporting Bugs

- Check existing issues first to avoid duplicates
- Include macOS version and AdAmp version
- Provide steps to reproduce
- Include relevant logs from Console.app if applicable

### Suggesting Features

- Open an issue describing the feature
- Explain the use case and why it would be useful
- Be open to discussion about implementation approaches

### Submitting Code

1. Create a branch for your changes: `git checkout -b feature/my-feature`
2. Make your changes following the code style below
3. Test your changes thoroughly
4. Commit with clear, descriptive messages
5. Push and open a Pull Request

## Code Style

- Follow existing patterns in the codebase
- Use Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Keep functions focused and reasonably sized
- Add comments for complex logic

### UI Changes

Before making UI changes:

1. Read [docs/UI_GUIDE.md](docs/UI_GUIDE.md)
2. Check `SkinElements.swift` for sprite coordinates
3. Follow existing patterns in `MainWindowView` or `EQView`
4. Test at different window sizes
5. Test with multiple skins

## Documentation

- Update relevant docs if your change affects user-facing behavior
- Keep [docs/USER_GUIDE.md](docs/USER_GUIDE.md) current for feature changes
- Update [AGENTS.md](AGENTS.md) if adding new key files

## Pull Request Guidelines

- Keep PRs focused on a single change
- Include a clear description of what and why
- Reference any related issues
- Ensure the build passes before submitting
- Be responsive to feedback and questions

## License

By contributing, you agree that your contributions will be licensed under the project's GPL-3.0 license.

## Questions?

Open an issue if you have questions about contributing.
