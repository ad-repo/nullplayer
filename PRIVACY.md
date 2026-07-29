# Privacy Policy

**Effective date: July 29, 2026**

NullPlayer does not collect, transmit, sell, rent, or share your personal data
with the NullPlayer developer. NullPlayer has no developer-operated analytics,
telemetry, crash-reporting, advertising, or tracking service.

## Data stored on your device

NullPlayer stores data locally to provide its features. This may include:

- Your media library and related metadata.
- Playback and usage history, such as the media played, playback time, duration
  listened, source, content type, skip status, and output device.
- App preferences, saved state, artwork, and other caches.
- Connection details, credentials, and access tokens for media servers you
  choose to connect.

The media library and playback history are stored in a local SQLite database,
normally at:

`~/Library/Application Support/NullPlayer/library.db`

This locally stored data is not sent to the NullPlayer developer or to an
analytics or advertising service.

## Credentials and account information

When you connect a Plex, Jellyfin, Emby, or Subsonic/Navidrome server,
NullPlayer may store the server name and address, username, password, access
token, user or account identifier, and other account details returned by that
service. NullPlayer also generates a persistent client identifier used when
communicating with supported media servers.

In a packaged macOS app, this information is stored in the macOS Keychain as
device-only data that is accessible while your Mac is unlocked. It is not
synchronized through iCloud Keychain. A raw development build run outside an
app bundle falls back to macOS preferences (`UserDefaults`) and therefore does
not receive the same Keychain protection. If a packaged app finds credentials
left by such a build, it moves them to the Keychain and removes the preference
copy.

Credentials are sent only to the service or server you chose, as required to
authenticate and perform requested operations. They are never sent to the
NullPlayer developer. The security of credentials in transit depends on the
server address you configure; use HTTPS when connecting to a server over an
untrusted network.

Some media servers authorize playback through a token included in a media URL.
When you cast that media, NullPlayer may provide the authorized URL to the
casting device you selected so that device can retrieve the media.

## Network features and third-party services

NullPlayer makes network connections only when needed for features you use,
including streaming media, internet radio, downloading media or artwork,
retrieving metadata, connecting to Plex, Jellyfin, Emby, or
Subsonic/Navidrome servers, and communicating with casting devices.

Some connected media servers support playback-progress reporting or
scrobbling. When you use those integrations, NullPlayer may send playback
status directly to the server you configured. This is separate from
NullPlayer's local playback-history database, which is not uploaded.

The macOS Now Playing integration may also make current playback information
available to compatible software on your Mac, such as optional Discord Music
Presence software.

Third-party services and devices receive only the information required for the
feature you requested and handle that information under their own privacy
practices. NullPlayer does not control those services.

## Data sharing and tracking

NullPlayer does not:

- Sell or rent personal data.
- Share personal data with advertisers or data brokers.
- Track you across apps or websites.
- Use your data for advertising or marketing.

## Data retention and deletion

Local data remains on your Mac until you remove it. You can remove NullPlayer's
local database, backups, preferences, and caches by deleting its data under
`~/Library/Application Support/NullPlayer` and the related macOS preferences
and caches. Credentials stored in the macOS Keychain must be removed separately
by disconnecting or removing the applicable account or server in NullPlayer, or
by deleting the Keychain entries for the `com.nullplayer.app` service. Removing
the app or its Application Support folder alone may not remove Keychain entries.

Data sent to a media server or other third-party service at your direction is
subject to that service's retention and deletion controls.

## Changes to this policy

This policy may be updated if NullPlayer's features or data practices change.
Material changes will be reflected in this file and its effective date.

## Contact

For privacy questions, open an issue in the
[NullPlayer GitHub repository](https://github.com/ad-repo/nullplayer/issues).
