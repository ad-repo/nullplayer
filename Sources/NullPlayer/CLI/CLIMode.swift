import AppKit
import NullPlayerPlayback

struct CLIOptions {
    // Mode
    var json = false
    var help = false
    var version = false

    // Source
    var source: String?

    // Content filters
    var artist: String?
    var album: String?
    var track: String?
    var genre: String?
    var decade: Int?
    var playlist: String?
    var search: String?
    var radio: String?
    var station: String?

    // Query commands
    var listSources = false
    var listLibraries = false
    var listArtists = false
    var listAlbums = false
    var listTracks = false
    var listGenres = false
    var listPlaylists = false
    var listStations = false
    var listDevices = false
    var listOutputs = false
    var listEQ = false

    // Library selection
    var library: String?

    // Radio folder
    var folder: String?
    var channel: String?
    var region: String?

    // Playback
    var shuffle = false
    var repeatAll = false
    var repeatOne = false
    var art = true
    var volume: Int?

    // Casting
    var cast: String?
    var castType: String?
    var sonosRooms: String?

    // Audio
    var eq: String?
    var output: String?

    var isQueryMode: Bool {
        listSources || listLibraries || listArtists || listAlbums || listTracks ||
        listGenres || listPlaylists || listStations || listDevices ||
        listOutputs || listEQ || isSearchQuery
    }

    /// --search without playback flags (--artist/--album/--playlist/--radio/--station)
    /// is treated as a query: print results and exit.
    var isSearchQuery: Bool {
        search != nil && artist == nil && album == nil && playlist == nil && radio == nil && station == nil
    }

    static func parse(_ args: [String]) -> CLIOptions {
        var opts = CLIOptions()
        var i = 1 // skip executable path
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--json": opts.json = true
            case "--help": opts.help = true
            case "--version": opts.version = true
            case "--shuffle": opts.shuffle = true
            case "--repeat-all": opts.repeatAll = true
            case "--repeat-one": opts.repeatOne = true
            case "--no-art": opts.art = false
            case "--list-sources": opts.listSources = true
            case "--list-libraries": opts.listLibraries = true
            case "--list-artists": opts.listArtists = true
            case "--list-albums": opts.listAlbums = true
            case "--list-tracks": opts.listTracks = true
            case "--list-genres": opts.listGenres = true
            case "--list-playlists": opts.listPlaylists = true
            case "--list-stations": opts.listStations = true
            case "--list-devices": opts.listDevices = true
            case "--list-outputs": opts.listOutputs = true
            case "--list-eq": opts.listEQ = true
            case "--cli": break // already handled in main.swift
            default:
                if arg.hasPrefix("--"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                    let value = args[i + 1]
                    switch arg {
                    case "--source": opts.source = value
                    case "--library": opts.library = value
                    case "--artist": opts.artist = value
                    case "--album": opts.album = value
                    case "--track": opts.track = value
                    case "--genre": opts.genre = value
                    case "--decade":
                        guard let intVal = Int(value) else {
                            fputs("Error: --decade requires an integer value (e.g. 1970)\n", stderr)
                            exit(1)
                        }
                        opts.decade = intVal
                    case "--playlist": opts.playlist = value
                    case "--search": opts.search = value
                    case "--radio": opts.radio = value
                    case "--station": opts.station = value
                    case "--folder": opts.folder = value
                    case "--channel": opts.channel = value
                    case "--region": opts.region = value
                    case "--volume":
                        guard let intVal = Int(value) else {
                            fputs("Error: --volume requires an integer value (0-100)\n", stderr)
                            exit(1)
                        }
                        opts.volume = intVal
                    case "--cast": opts.cast = value
                    case "--cast-type": opts.castType = value
                    case "--sonos-rooms": opts.sonosRooms = value
                    case "--eq": opts.eq = value
                    case "--output": opts.output = value
                    default:
                        fputs("Error: Unknown flag '\(arg)'\n", stderr)
                        exit(1)
                    }
                    i += 1 // skip value
                } else if arg.hasPrefix("--") {
                    fputs("Error: Flag '\(arg)' requires a value\n", stderr)
                    exit(1)
                }
            }
            i += 1
        }
        return opts
    }
}

class CLIMode: NSObject, NSApplicationDelegate {
    private var player: CLIPlayer?
    private var keyboard: CLIKeyboard?
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioEngine.isHeadless = true

        let opts = CLIOptions.parse(CommandLine.arguments)

        // Signal handlers (must use DispatchSourceSignal — signal() requires C function pointers)
        signal(SIGINT, SIG_IGN)
        sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource?.setEventHandler {
            CLIKeyboard.restoreTerminal()
            exit(130)
        }
        sigintSource?.resume()

        signal(SIGTERM, SIG_IGN)
        sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource?.setEventHandler {
            CLIKeyboard.restoreTerminal()
            exit(0)
        }
        sigtermSource?.resume()

        // Help
        if opts.help {
            CLIDisplay.printHelp()
            exit(0)
        }

        // Version
        if opts.version {
            CLIDisplay.printVersion()
            exit(0)
        }

        // Validate mutually exclusive flags
        if opts.repeatAll && opts.repeatOne {
            fputs("Error: --repeat-all and --repeat-one are mutually exclusive\n", stderr)
            exit(1)
        }

        // Query mode
        if opts.isQueryMode {
            Task { @MainActor in
                do {
                    let outputRouting: (any AudioOutputRouting)? = opts.listOutputs
                        ? AudioOutputRoutingProvider.shared
                        : nil
                    try await CLIQueryHandler.handle(opts, outputRouting: outputRouting)
                    exit(0)
                } catch {
                    fputs("Error: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            return
        }

        // Playback mode
        Task { @MainActor in
            do {
                let cliPlayer = CLIPlayer(options: opts)
                self.player = cliPlayer

                let result = try await CLISourceResolver.resolve(opts)

                // Radio stations are handled directly by RadioManager (returns .radioStation)
                switch result {
                case .tracks(let tracks):
                    if tracks.isEmpty {
                        fputs("Error: No tracks found for the given criteria.\n", stderr)
                        exit(1)
                    }
                    cliPlayer.play(tracks: tracks)
                case .radioStation:
                    // RadioManager is already playing; CLIPlayer just monitors
                    cliPlayer.monitorRadio()
                }

                let kb = CLIKeyboard(player: cliPlayer)
                self.keyboard = kb
                kb.start()
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }
}
