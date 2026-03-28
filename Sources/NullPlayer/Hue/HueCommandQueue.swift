import Foundation

actor HueCommandQueue {
    struct Command {
        let dedupeKey: String
        let targetID: String?
        let isSliderLike: Bool
        let execute: () async throws -> Void
    }

    private var pending: [String: Command] = [:]
    private var order: [String] = []
    private var worker: Task<Void, Never>?
    private var lastGlobalDispatch: Date = .distantPast
    private var lastTargetDispatch: [String: Date] = [:]

    private let globalInterval: TimeInterval = 0.1 // 10 req/s cap
    private let sliderInterval: TimeInterval = 0.2 // 5 req/s per target

    func enqueue(_ command: Command) {
        if pending[command.dedupeKey] == nil {
            order.append(command.dedupeKey)
        }
        pending[command.dedupeKey] = command

        if worker == nil {
            worker = Task { [weak self] in
                await self?.drain()
            }
        }
    }

    func cancelAll() {
        pending.removeAll()
        order.removeAll()
        worker?.cancel()
        worker = nil
    }

    private func drain() async {
        while !Task.isCancelled {
            guard let key = order.first else { break }
            order.removeFirst()
            guard let command = pending.removeValue(forKey: key) else {
                continue
            }

            await enforceRateLimits(for: command)
            do {
                try await command.execute()
            } catch {
                NSLog("HueCommandQueue: command failed for key %@: %@", command.dedupeKey, error.localizedDescription)
            }

            lastGlobalDispatch = Date()
            if let target = command.targetID {
                lastTargetDispatch[target] = lastGlobalDispatch
            }
        }

        worker = nil
    }

    private func enforceRateLimits(for command: Command) async {
        let now = Date()
        let sinceGlobal = now.timeIntervalSince(lastGlobalDispatch)
        let globalDelay = max(0, globalInterval - sinceGlobal)

        var perTargetDelay: TimeInterval = 0
        if command.isSliderLike,
           let targetID = command.targetID,
           let lastTarget = lastTargetDispatch[targetID] {
            let sinceTarget = now.timeIntervalSince(lastTarget)
            perTargetDelay = max(0, sliderInterval - sinceTarget)
        }

        let totalDelay = max(globalDelay, perTargetDelay)
        if totalDelay > 0 {
            let ns = UInt64(totalDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
    }
}
