#if os(Linux)
import Dispatch
import Glibc

private var signalSources: [DispatchSourceSignal] = []

enum LinuxSignalHandlers {
    static func install(_ onTerminate: @escaping (Int32) -> Void) {
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
}
#endif
