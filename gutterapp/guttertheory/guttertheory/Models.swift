import Foundation

struct GTPlayer: Identifiable, Hashable, Codable {
    enum Status: String, CaseIterable, Codable {
        case linked
        case inRange
        case outOfRange
    }

    let id: UUID
    var name: String
    var status: Status
    var distanceMeters: Double
    var heading: Double
    var zoneKey: String?
    var zoneLabel: String?
    var lastSeen: Date
}

struct GTLobby: Identifiable {
    let id: UUID
    var name: String
    var host: String
    var mode: GTGameMode
    var players: [GTPlayer]
}

enum GTGameMode: String, CaseIterable {
    case laserTag = "Laser Tag"
    case pulseRush = "Pulse Rush"
    case echoRun = "Echo Run"
}

struct LaserTagStats {
    var shotsFired: Int
    var hits: Int
    var streak: Int
    var lastHitName: String?
}
