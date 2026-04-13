import Foundation

enum LinuxCLIOptionsError: LocalizedError {
    case unsupportedFlag(String)
    case missingValue(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFlag(flag):
            return "Flag '\(flag)' is not supported on Linux in phase 2."
        case let .missingValue(flag):
            return "Flag '\(flag)' requires a value."
        case let .invalidValue(message):
            return message
        }
    }
}

struct LinuxCLIOptions {
    var help = false
    var listOutputs = false
    var shuffle = false
    var repeatAll = false
    var repeatOne = false
    var noArt = false
    var volume: Int?
    var eq: String?
    var output: String?
    var positionalInputs: [String] = []

    static let unsupportedLinuxFlags: Set<String> = [
        "--source",
        "--artist", "--album", "--track", "--genre", "--playlist", "--search",
        "--station", "--radio", "--folder", "--channel", "--region",
        "--cast", "--cast-type", "--sonos-rooms",
        "--list-devices", "--list-sources", "--list-libraries", "--list-artists",
        "--list-albums", "--list-tracks", "--list-genres", "--list-playlists", "--list-stations"
    ]

    static func parse(_ arguments: [String]) throws -> LinuxCLIOptions {
        var options = LinuxCLIOptions()
        var index = 1

        while index < arguments.count {
            let arg = arguments[index]

            if unsupportedLinuxFlags.contains(arg) {
                throw LinuxCLIOptionsError.unsupportedFlag(arg)
            }

            switch arg {
            case "--cli":
                break
            case "--help", "-h":
                options.help = true
            case "--list-outputs":
                options.listOutputs = true
            case "--shuffle":
                options.shuffle = true
            case "--repeat-all":
                options.repeatAll = true
            case "--repeat-one":
                options.repeatOne = true
            case "--no-art":
                options.noArt = true
            case "--volume":
                guard index + 1 < arguments.count else {
                    throw LinuxCLIOptionsError.missingValue(arg)
                }
                let value = arguments[index + 1]
                guard let intValue = Int(value), (0...100).contains(intValue) else {
                    throw LinuxCLIOptionsError.invalidValue("--volume must be an integer from 0 to 100.")
                }
                options.volume = intValue
                index += 1
            case "--eq":
                guard index + 1 < arguments.count else {
                    throw LinuxCLIOptionsError.missingValue(arg)
                }
                options.eq = arguments[index + 1]
                index += 1
            case "--output":
                guard index + 1 < arguments.count else {
                    throw LinuxCLIOptionsError.missingValue(arg)
                }
                options.output = arguments[index + 1]
                index += 1
            default:
                if arg.hasPrefix("--") {
                    throw LinuxCLIOptionsError.unsupportedFlag(arg)
                }
                options.positionalInputs.append(arg)
            }

            index += 1
        }

        if options.repeatAll && options.repeatOne {
            throw LinuxCLIOptionsError.invalidValue("--repeat-all and --repeat-one are mutually exclusive.")
        }

        return options
    }

    static func helpText() -> String {
        """
        NullPlayer Linux CLI (Phase 2)

        Supported:
          nullplayer --cli [options] <file-or-url> [more files/urls]
          --shuffle --repeat-all --repeat-one --volume <0-100>
          --eq <off|flat|comma-separated 10 gains>
          --output <name-or-persistent-id>
          --list-outputs
          --no-art

        Inputs:
          Local file paths
          http:// and https:// URLs
        """
    }
}
