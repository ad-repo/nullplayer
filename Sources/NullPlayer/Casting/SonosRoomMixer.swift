import Foundation

/// Window state is independent of skin recreation. Room writes are serialized per room;
/// polling cannot replace a newer slider value with an older network response.
@MainActor
final class SonosRoomMixer {
    static let shared = SonosRoomMixer()
    private(set) var volumes: [String: Int] = [:]
    private(set) var errors: [String: String] = [:]
    private var pending: [String: Int] = [:]
    private var writing: Set<String> = []
    private var revisions: [String: UInt] = [:]
    private var reading = false
    private(set) var changingRooms = false
    private let roomIDs: @MainActor () -> [String]
    private let readVolume: @MainActor (String) async throws -> Int
    private let writeVolume: @MainActor (Int, String) async throws -> Void

    init(roomIDs: @escaping @MainActor () -> [String] = { CastManager.shared.sonosRooms.map(\.id) },
         readVolume: @escaping @MainActor (String) async throws -> Int = {
             try await UPnPManager.shared.getSonosRoomVolume(roomUDN: $0)
         },
         writeVolume: @escaping @MainActor (Int, String) async throws -> Void = {
             try await UPnPManager.shared.setSonosRoomVolume($0, roomUDN: $1)
         }) {
        self.roomIDs = roomIDs
        self.readVolume = readVolume
        self.writeVolume = writeVolume
    }

    func setVolume(_ value: Int, room: String) {
        let value = max(0, min(100, value))
        revisions[room, default: 0] &+= 1
        volumes[room] = value
        errors[room] = nil
        pending[room] = value
        guard writing.insert(room).inserted else { return }
        Task {
            defer { writing.remove(room) }
            while let next = pending.removeValue(forKey: room) {
                do {
                    try await writeVolume(next, room)
                    errors[room] = nil
                } catch {
                    errors[room] = error.localizedDescription
                    if pending[room] == nil { volumes[room] = nil }
                }
            }
        }
    }

    func refreshVolumes() async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        let candidates = roomIDs().filter { !writing.contains($0) }.map { ($0, revisions[$0, default: 0]) }
        var remaining = candidates.makeIterator()
        let read = readVolume
        await withTaskGroup(of: (String, UInt, Result<Int, Error>).self) { group in
            func enqueue(_ candidate: (String, UInt)) {
                let (id, revision) = candidate
                group.addTask { @MainActor in
                    do { return (id, revision, .success(try await read(id))) }
                    catch { return (id, revision, .failure(error)) }
                }
            }
            for _ in 0..<4 { if let id = remaining.next() { enqueue(id) } }
            for await (id, revision, result) in group {
                if !Task.isCancelled, revision == revisions[id, default: 0], !writing.contains(id) {
                    switch result {
                    case .success(let value): volumes[id] = value; errors[id] = nil
                    case .failure(let error): volumes[id] = nil; errors[id] = error.localizedDescription
                    }
                }
                if Task.isCancelled { group.cancelAll() }
                else if let id = remaining.next() { enqueue(id) }
            }
        }
    }

    func selectRoom(_ id: String, selected: Bool) async throws {
        guard !changingRooms else { throw CastError.operationInProgress }
        let manager = CastManager.shared
        guard manager.activeSession?.device.type == .sonos else {
            if selected { manager.selectedSonosRooms.insert(id) }
            else { manager.selectedSonosRooms.remove(id) }
            return
        }
        changingRooms = true
        defer { changingRooms = false }
        if selected, let coordinator = manager.activeSession?.device.id {
            try await manager.joinSonosToGroup(zoneUDN: id, coordinatorUDN: coordinator)
        } else if id == manager.activeSession?.device.id {
            let others = manager.getRoomsInActiveCastGroup().filter { $0 != id }.sorted()
            if let next = others.first {
                try await manager.transferSonosCast(fromCoordinator: id, toRoom: next,
                                                    otherRooms: Array(others.dropFirst()))
            } else {
                await manager.stopCasting()
            }
        } else {
            try await manager.unjoinSonos(zoneUDN: id)
        }
        await manager.refreshSonosGroups()
    }

    func startCasting() async throws {
        guard !changingRooms else { throw CastError.operationInProgress }
        let manager = CastManager.shared
        guard WindowManager.shared.audioEngine.currentTrack != nil else { throw CastError.noTrackPlaying }
        let ids = manager.sonosRooms.map(\.id).filter { manager.selectedSonosRooms.contains($0) }
        guard let first = ids.first,
              let device = UPnPManager.shared.sonosCastDevice(forZoneUDN: first) else { throw CastError.deviceNotFound }
        changingRooms = true
        defer { changingRooms = false }
        do {
            // A selected member of an existing household group must become its own
            // coordinator first, so unselected rooms are not accidentally included.
            try await manager.unjoinSonos(zoneUDN: first)
            try await manager.castCurrentTrack(to: device)
            guard let coordinator = manager.activeSession?.device.id else { throw CastError.sessionNotActive }
            for id in ids where id != coordinator {
                try await manager.joinSonosToGroup(zoneUDN: id, coordinatorUDN: coordinator)
            }
            await manager.refreshSonosGroups()
        } catch {
            await manager.stopCasting()
            throw error
        }
    }
}
