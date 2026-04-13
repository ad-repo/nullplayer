#if os(Linux)
import Foundation
import Dispatch
import Glibc
import NullPlayerCore
import NullPlayerPlayback

private var signalSources: [DispatchSourceSignal] = []

private func installSignalHandlers(_ onTerminate: @escaping (Int32) -> Void) {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler {
        onTerminate(130)
    }
    sigintSource.resume()

    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigtermSource.setEventHandler {
        onTerminate(0)
    }
    sigtermSource.resume()

    signalSources = [sigintSource, sigtermSource]
}

do {
    let options = try LinuxCLIOptions.parse(CommandLine.arguments)

    if options.help {
        print(LinuxCLIOptions.helpText())
        exit(0)
    }

    let display = LinuxCLIDisplay()
    let backend = LinuxGStreamerAudioBackend()
    let facade = AudioEngineFacade(backend: backend)

    let player = LinuxCLIPlayer(
        engine: facade,
        outputRouting: backend,
        display: display,
        options: options,
        quitHandler: { code in
            backend.shutdown()
            exit(code)
        }
    )

    installSignalHandlers { code in
        player.requestQuit(exitCode: code)
    }

    if options.listOutputs {
        player.listOutputs()
        player.requestQuit(exitCode: 0)
    }

    let tracks = try LinuxSourceResolver.resolveTracks(from: options.positionalInputs)
    player.startPlayback(with: tracks)

    RunLoop.main.run()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    fputs("\(LinuxCLIOptions.helpText())\n", stderr)
    exit(1)
}
#else
import Foundation

print("NullPlayerCLI Linux mode is only available when built on Linux.")
#endif
