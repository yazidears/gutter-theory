import Combine
import CoreLocation
import Foundation
import MultipeerConnectivity
import SwiftUI
import UIKit

private func gtLog(_ category: String, _ message: String) {
    print("[GT \(category)] \(message)")
}

private enum MeshMessageType: String {
    case presence
    case shot
    case hit
    case ping
}

enum ConnectivityMode: String, CaseIterable {
    case meshOnly = "Mesh Only"
    case meshAndBackend = "Mesh + Backend"
}

final class BackendDiscovery: NSObject, ObservableObject {
    @Published private(set) var discoveredURL: URL?

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var isRunning = false
    private let serviceType = "_guttertheory._tcp."
    private let domain = "local."
    private let defaultsKey = "gt.backend.url"

    override init() {
        super.init()
        browser.delegate = self
        if let saved = UserDefaults.standard.string(forKey: defaultsKey),
           let url = URL(string: saved) {
            discoveredURL = url
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
#if targetEnvironment(simulator)
        discoveredURL = URL(string: "http://localhost:8000")
        gtLog("BackendDiscovery", "simulator mode using \(discoveredURL?.absoluteString ?? "nil")")
        return
#endif
        gtLog("BackendDiscovery", "searching for \(serviceType) in \(domain)")
        browser.searchForServices(ofType: serviceType, inDomain: domain)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        gtLog("BackendDiscovery", "stopping search")
        browser.stop()
        services.removeAll()
    }

    private func updateURL(host: String, port: Int) {
        let sanitized = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let url = URL(string: "http://\(sanitized):\(port)") else { return }
        if discoveredURL != url {
            discoveredURL = url
            UserDefaults.standard.set(url.absoluteString, forKey: defaultsKey)
            gtLog("BackendDiscovery", "resolved backend at \(url.absoluteString)")
        }
    }
}

extension BackendDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        gtLog("BackendDiscovery", "found service \(service.name)")
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 2.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        if let host = sender.hostName {
            updateURL(host: host, port: sender.port)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        gtLog("BackendDiscovery", "didNotSearch: \(errorDict)")
        gtLog("BackendDiscovery", "local network permission likely missing or denied")
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        gtLog("BackendDiscovery", "didNotResolve: \(sender.name) \(errorDict)")
    }
}

struct PresencePayload: Codable {
    let playerID: UUID
    let name: String
    let lat: Double
    let lon: Double
    let heading: Double
    let zoneKey: String?
    let zoneLabel: String?
    let ts: Date
}

struct ShotPayload: Codable {
    let fromID: UUID
    let heading: Double
    let rangeMeters: Double
    let targetID: UUID?
    let ts: Date
}

struct HitPayload: Codable {
    let fromID: UUID
    let toID: UUID
    let distanceMeters: Double
    let ts: Date
}

struct PingPayload: Codable {
    let ts: Date
}

private struct Envelope<T: Codable>: Codable {
    let type: String
    let payload: T
}

struct RemotePresence: Identifiable, Hashable {
    enum Source: String {
        case mesh
        case backend
    }

    let id: UUID
    var name: String
    var location: CLLocation
    var heading: Double
    var zoneKey: String?
    var zoneLabel: String?
    var lastSeen: Date
    var source: Source
}

private struct ZoneResolver {
    static func zoneKey(for location: CLLocation) -> String {
        let latBucket = (location.coordinate.latitude * 1000).rounded()
        let lonBucket = (location.coordinate.longitude * 1000).rounded()
        return "\(latBucket):\(lonBucket)"
    }

    static func zoneLabel(for location: CLLocation) -> String {
        let latBucket = Int(abs(location.coordinate.latitude) * 1000)
        let lonBucket = Int(abs(location.coordinate.longitude) * 1000)
        let ring = (latBucket + lonBucket) % 9 + 1
        return "GRID-\(ring)"
    }
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: Double = 0
    @Published var isAuthorized = false

    private let manager = CLLocationManager()
    private var didLogLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1.5
        manager.headingFilter = 1
    }

    func start() {
        gtLog("Location", "requesting when-in-use authorization")
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        if !didLogLocation, location != nil {
            didLogLocation = true
            gtLog("Location", "received first location fix")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.trueHeading > 0 {
            heading = newHeading.trueHeading
        } else {
            heading = newHeading.magneticHeading
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            gtLog("Location", "authorized: \(authorizationLabel(manager.authorizationStatus))")
        default:
            isAuthorized = false
            gtLog("Location", "not authorized: \(authorizationLabel(manager.authorizationStatus))")
        }
    }

    private func authorizationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown"
        }
    }
}

final class MeshService: NSObject, ObservableObject {
    @Published private(set) var remotePresence: [UUID: RemotePresence] = [:]
    @Published private(set) var isActive = false
    @Published private(set) var connectedPeers: [MCPeerID] = []

    private let serviceType = "gutterpass"
    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    private var decoder: JSONDecoder

    override init() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        decoder = JSONDecoder.withIso8601
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        gtLog("Mesh", "starting advertiser + browser (serviceType=\(serviceType))")
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        isActive = false
        gtLog("Mesh", "stopping advertiser + browser")
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        remotePresence = [:]
        connectedPeers = []
    }

    func sendPresence(_ payload: PresencePayload) {
        send(messageType: .presence, payload: payload, mode: .unreliable)
    }

    func sendShot(_ payload: ShotPayload) {
        send(messageType: .shot, payload: payload, mode: .reliable)
    }

    private func send<T: Codable>(messageType: MeshMessageType, payload: T, mode: MCSessionSendDataMode) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let envelope = Envelope(type: messageType.rawValue, payload: payload)
            let data = try JSONEncoder.withIso8601.encode(envelope)
            try session.send(data, toPeers: session.connectedPeers, with: mode)
        } catch {
            return
        }
    }

    private func handle(data: Data, from peer: MCPeerID) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String,
            let payload = json["payload"]
        else { return }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        switch type {
        case MeshMessageType.presence.rawValue:
            if let presence = try? decoder.decode(PresencePayload.self, from: payloadData) {
                let presenceLocation = CLLocation(latitude: presence.lat, longitude: presence.lon)
                remotePresence[presence.playerID] = RemotePresence(
                    id: presence.playerID,
                    name: presence.name,
                    location: presenceLocation,
                    heading: presence.heading,
                    zoneKey: presence.zoneKey,
                    zoneLabel: presence.zoneLabel,
                    lastSeen: presence.ts,
                    source: .mesh
                )
            }
        case MeshMessageType.hit.rawValue:
            break
        default:
            break
        }
    }
}

extension MeshService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            let label: String
            switch state {
            case .notConnected:
                label = "notConnected"
            case .connecting:
                label = "connecting"
            case .connected:
                label = "connected"
            @unknown default:
                label = "unknown"
            }
            gtLog("Mesh", "peer \(peerID.displayName) state=\(label) peers=\(session.connectedPeers.count)")
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.handle(data: data, from: peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) { }
}

extension MeshService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        gtLog("Mesh", "received invitation from \(peerID.displayName)")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        gtLog("Mesh", "failed to advertise: \(error.localizedDescription)")
    }
}

extension MeshService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        gtLog("Mesh", "found peer \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        gtLog("Mesh", "lost peer \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        gtLog("Mesh", "failed to browse: \(error.localizedDescription)")
    }
}

struct BackendLobbyResponse: Codable {
    let lobbyID: UUID
    let code: String
    let name: String
    let mode: String
}

struct BackendJoinRequest: Codable {
    let playerID: UUID
    let name: String
}

struct BackendCreateRequest: Codable {
    let name: String
    let mode: String
    let hostID: UUID
    let hostName: String
}

struct BackendPresencePayload: Codable {
    let playerID: UUID
    let name: String
    let lat: Double
    let lon: Double
    let heading: Double
    let zoneKey: String?
    let zoneLabel: String?
    let ts: Date
}

struct BackendShotPayload: Codable {
    let fromID: UUID
    let heading: Double
    let rangeM: Double
    let targetID: UUID?
    let ts: Date
}

final class BackendClient {
    static let shared = BackendClient()

    var baseURL = URL(string: "http://localhost:8000")!

    func createLobby(name: String, mode: GTGameMode, hostID: UUID, hostName: String) async throws -> BackendLobbyResponse {
        let url = baseURL.appendingPathComponent("v1/lobbies")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = BackendCreateRequest(name: name, mode: mode.rawValue, hostID: hostID, hostName: hostName)
        request.httpBody = try JSONEncoder.withIso8601.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder.withIso8601.decode(BackendLobbyResponse.self, from: data)
    }

    func joinLobby(code: String, playerID: UUID, name: String) async throws -> BackendLobbyResponse {
        let url = baseURL.appendingPathComponent("v1/lobbies/\(code)/join")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = BackendJoinRequest(playerID: playerID, name: name)
        request.httpBody = try JSONEncoder.withIso8601.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder.withIso8601.decode(BackendLobbyResponse.self, from: data)
    }

    func leaveLobby(code: String, playerID: UUID) async throws {
        let url = baseURL.appendingPathComponent("v1/lobbies/\(code)/leave")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["player_id": playerID.uuidString]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

final class BackendConnection: ObservableObject {
    enum Status: String {
        case disconnected
        case connecting
        case connected
        case error
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var remotePresence: [UUID: RemotePresence] = [:]
    @Published private(set) var lastEventMessage: String? = nil

    private let session = URLSession(configuration: .default)
    private var webSocket: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTimer: Timer?
    private var lobbyCode: String?
    private var playerID: UUID?
    private var playerName: String?
    var socketBaseURL = "ws://localhost:8000"

    private let encoder = JSONEncoder.withIso8601
    private let decoder = JSONDecoder.withIso8601

    func connect(code: String, playerID: UUID, name: String) {
        disconnect()
        lobbyCode = code
        self.playerID = playerID
        playerName = name
        status = .connecting

        guard let url = URL(string: "\(socketBaseURL)/v1/ws/\(code)?player_id=\(playerID.uuidString)&name=\(name.urlEncoded)") else {
            status = .error
            gtLog("Backend", "invalid websocket URL")
            return
        }

        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()
        status = .connected
        gtLog("Backend", "websocket connecting \(url.absoluteString)")
        listenTask = Task { await listen() }
        startHeartbeat()
    }

    func disconnect() {
        listenTask?.cancel()
        listenTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        status = .disconnected
        remotePresence = [:]
        gtLog("Backend", "disconnected")
    }

    func sendPresence(_ payload: BackendPresencePayload) {
        send(type: "presence", payload: payload)
    }

    func sendShot(_ payload: BackendShotPayload) {
        send(type: "shot", payload: payload)
    }

    private func send<T: Codable>(type: String, payload: T) {
        guard let socket = webSocket else { return }
        let envelope = Envelope(type: type, payload: payload)
        guard let data = try? JSONEncoder.withIso8601.encode(envelope) else { return }
        socket.send(.data(data)) { _ in }
    }

    private func listen() async {
        guard let socket = webSocket else { return }
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                switch message {
                case .data(let data):
                    handle(data: data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        handle(data: data)
                    }
                @unknown default:
                    break
                }
            } catch {
                status = .error
                gtLog("Backend", "websocket error: \(error.localizedDescription)")
                return
            }
        }
    }

    private func handle(data: Data) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String,
            let payload = json["payload"]
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if type == "presence" {
                guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                      let presence = try? self.decoder.decode(PresencePayload.self, from: payloadData) else { return }
                let presenceLocation = CLLocation(latitude: presence.lat, longitude: presence.lon)
                self.remotePresence[presence.playerID] = RemotePresence(
                    id: presence.playerID,
                    name: presence.name,
                    location: presenceLocation,
                    heading: presence.heading,
                    zoneKey: presence.zoneKey,
                    zoneLabel: presence.zoneLabel,
                    lastSeen: presence.ts,
                    source: .backend
                )
            } else if type == "hit" {
                self.lastEventMessage = "Hit confirmed"
            } else if type == "error" {
                self.lastEventMessage = "Server error"
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.send(type: "ping", payload: PingPayload(ts: Date()))
        }
    }
}

final class StreetPassViewModel: ObservableObject {
    @Published var nearbyPlayers: [GTPlayer] = []
    @Published var isScanning = false
    @Published var lobbyCode: String? = nil
    @Published var backendStatus: BackendConnection.Status = .disconnected
    @Published var localZoneLabel: String? = nil
    @Published var localZoneKey: String? = nil
    @Published var localHeading: Double = 0
    @Published var meshPeerCount: Int = 0
    @Published var connectivityMode: ConnectivityMode = .meshOnly

    private let localPlayerID = UUID()
    private let localPlayerName = UIDevice.current.name
    private let locationService = LocationService()
    private let meshService = MeshService()
    private let backendConnection = BackendConnection()
    private let discovery = BackendDiscovery()

    private var cancellables = Set<AnyCancellable>()
    private var presenceTimer: Timer?
    private var didLogLocationMissing = false
    private var didLogPermissions = false

    init() {
        locationService.$location
            .combineLatest(meshService.$remotePresence, backendConnection.$remotePresence)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location, meshPresence, backendPresence in
                guard let self else { return }
                self.refreshPlayers(location: location, meshPresence: meshPresence, backendPresence: backendPresence)
            }
            .store(in: &cancellables)

        locationService.$heading
            .receive(on: DispatchQueue.main)
            .assign(to: &$localHeading)

        meshService.$connectedPeers
            .receive(on: DispatchQueue.main)
            .map { $0.count }
            .assign(to: &$meshPeerCount)

        backendConnection.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$backendStatus)

        discovery.$discoveredURL
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                BackendClient.shared.baseURL = url
                self?.backendConnection.socketBaseURL = url.wsBase
                guard let self, self.backendEnabled, self.isScanning, let code = self.lobbyCode else { return }
                self.backendConnection.connect(code: code, playerID: self.localPlayerID, name: self.localPlayerName)
            }
            .store(in: &cancellables)
    }

    var backendEnabled: Bool {
        connectivityMode == .meshAndBackend
    }

    func setConnectivityMode(_ mode: ConnectivityMode) {
        connectivityMode = mode
        gtLog("StreetPass", "connectivity mode \(mode.rawValue)")
        if backendEnabled {
            discovery.start()
            if isScanning, let code = lobbyCode {
                backendConnection.connect(code: code, playerID: localPlayerID, name: localPlayerName)
            }
        } else {
            backendConnection.disconnect()
            backendStatus = .disconnected
            discovery.stop()
        }
    }

    func start() {
        guard !isScanning else { return }
        isScanning = true
        if !didLogPermissions {
            didLogPermissions = true
            logPermissionSnapshot()
        }
        gtLog("StreetPass", "start scanning")
        locationService.start()
        meshService.start()
        if backendEnabled {
            discovery.start()
        }
        if backendEnabled, let code = lobbyCode {
            backendConnection.connect(code: code, playerID: localPlayerID, name: localPlayerName)
        }
        startPresenceTimer()
    }

    func stop() {
        isScanning = false
        gtLog("StreetPass", "stop scanning")
        locationService.stop()
        meshService.stop()
        backendConnection.disconnect()
        discovery.stop()
        presenceTimer?.invalidate()
        presenceTimer = nil
    }

    @MainActor
    func createLobby(mode: GTGameMode) async {
        guard backendEnabled else {
            lobbyCode = "LOCAL"
            backendStatus = .disconnected
            return
        }
        do {
            let lobby = try await BackendClient.shared.createLobby(
                name: "GutterTheory",
                mode: mode,
                hostID: localPlayerID,
                hostName: localPlayerName
            )
            lobbyCode = lobby.code
            backendConnection.connect(code: lobby.code, playerID: localPlayerID, name: localPlayerName)
        } catch {
            backendStatus = .error
        }
    }

    @MainActor
    func joinLobby(code: String) async {
        guard backendEnabled else {
            lobbyCode = code
            backendStatus = .disconnected
            return
        }
        do {
            let lobby = try await BackendClient.shared.joinLobby(
                code: code,
                playerID: localPlayerID,
                name: localPlayerName
            )
            lobbyCode = lobby.code
            backendConnection.connect(code: lobby.code, playerID: localPlayerID, name: localPlayerName)
        } catch {
            backendStatus = .error
        }
    }

    func fireShot(target: GTPlayer?, heading: Double) {
        let shot = ShotPayload(fromID: localPlayerID, heading: heading, rangeMeters: 40, targetID: target?.id, ts: Date())
        meshService.sendShot(shot)
        if backendEnabled {
            let backendShot = BackendShotPayload(fromID: localPlayerID, heading: heading, rangeM: 40, targetID: target?.id, ts: Date())
            backendConnection.sendShot(backendShot)
        }
    }

    private func startPresenceTimer() {
        presenceTimer?.invalidate()
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.broadcastPresence()
        }
    }

    private func broadcastPresence() {
        guard let location = locationService.location else {
            if !didLogLocationMissing {
                gtLog("Presence", "skipping broadcast: location unavailable")
                didLogLocationMissing = true
            }
            return
        }
        didLogLocationMissing = false
        let zoneKey = ZoneResolver.zoneKey(for: location)
        let zoneLabel = ZoneResolver.zoneLabel(for: location)
        let heading = locationService.heading
        let presence = PresencePayload(
            playerID: localPlayerID,
            name: localPlayerName,
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            heading: heading,
            zoneKey: zoneKey,
            zoneLabel: zoneLabel,
            ts: Date()
        )
        meshService.sendPresence(presence)
        if backendEnabled {
            let backendPresence = BackendPresencePayload(
                playerID: localPlayerID,
                name: localPlayerName,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                heading: heading,
                zoneKey: zoneKey,
                zoneLabel: zoneLabel,
                ts: Date()
            )
            backendConnection.sendPresence(backendPresence)
        }
    }

    private func refreshPlayers(
        location: CLLocation?,
        meshPresence: [UUID: RemotePresence],
        backendPresence: [UUID: RemotePresence]
    ) {
        var merged = backendPresence
        for (key, value) in meshPresence {
            merged[key] = value
        }
        if let location {
            localZoneKey = ZoneResolver.zoneKey(for: location)
            localZoneLabel = ZoneResolver.zoneLabel(for: location)
        } else {
            localZoneKey = nil
            localZoneLabel = nil
        }

        let now = Date()
        nearbyPlayers = merged.values
            .filter { $0.id != localPlayerID }
            .filter { now.timeIntervalSince($0.lastSeen) < 12 }
            .map { presence in
                let distance = location.map { $0.distance(from: presence.location) } ?? 999
                let status = statusForDistance(distance)
                return GTPlayer(
                    id: presence.id,
                    name: presence.name,
                    status: status,
                    distanceMeters: distance,
                    heading: presence.heading,
                    zoneKey: presence.zoneKey,
                    zoneLabel: presence.zoneLabel,
                    lastSeen: presence.lastSeen
                )
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    private func statusForDistance(_ distance: Double) -> GTPlayer.Status {
        if distance < 10 { return .linked }
        if distance < 25 { return .inRange }
        return .outOfRange
    }

    private func logPermissionSnapshot() {
        let info = Bundle.main.infoDictionary
        let localNetwork = info?["NSLocalNetworkUsageDescription"] as? String
        let location = info?["NSLocationWhenInUseUsageDescription"] as? String
        let bluetooth = info?["NSBluetoothAlwaysUsageDescription"] as? String
        let bonjour = info?["NSBonjourServices"] as? [String] ?? []

        gtLog("Permissions", "NSLocalNetworkUsageDescription=\(localNetwork == nil ? "missing" : "set")")
        gtLog("Permissions", "NSLocationWhenInUseUsageDescription=\(location == nil ? "missing" : "set")")
        gtLog("Permissions", "NSBluetoothAlwaysUsageDescription=\(bluetooth == nil ? "missing" : "set")")
        if bonjour.isEmpty {
            gtLog("Permissions", "NSBonjourServices=missing")
        } else {
            gtLog("Permissions", "NSBonjourServices=\(bonjour)")
        }
    }
}

enum AimAssistState: String, Equatable {
    case none
    case tracking
    case locking
    case locked
}

struct AimAssist: Equatable {
    var state: AimAssistState
    var targetID: UUID?
    var targetName: String?
    var distanceMeters: Double?
    var angleDifference: Double?
    var progress: Double

    static let none = AimAssist(
        state: .none,
        targetID: nil,
        targetName: nil,
        distanceMeters: nil,
        angleDifference: nil,
        progress: 0
    )
}

final class LaserTagViewModel: ObservableObject {
    @Published var compassHeading: Double = 0
    @Published var stats = LaserTagStats(shotsFired: 0, hits: 0, streak: 0, lastHitName: nil)
    @Published var statusMessage = "Sensors hot"
    @Published var targets: [GTPlayer] = []
    @Published var aimAssist = AimAssist.none

    private var timer: Timer?
    private let lockAngle: Double = 14
    private let preLockAngle: Double = 24
    private let approachAngle: Double = 38

    func connect(players: [GTPlayer], heading: Double) {
        targets = players.filter { $0.status != .outOfRange }
        updateHeading(heading)
        updateAimAssist()
    }

    func updateHeading(_ heading: Double) {
        if heading > 0 {
            compassHeading = heading
            stopHeadingSimulation()
            updateAimAssist()
        } else {
            startHeadingSimulation()
        }
    }

    func fire() -> GTPlayer? {
        stats.shotsFired += 1
        guard let target = bestTarget() else {
            statusMessage = "No lock. Recenter."
            stats.streak = 0
            return nil
        }

        stats.hits += 1
        stats.streak += 1
        stats.lastHitName = target.name
        statusMessage = "Hit confirmed on \(target.name)"
        return target
    }

    private func bestTarget() -> GTPlayer? {
        let candidates = targets.filter { player in
            angleDifference(compassHeading, player.heading) <= lockAngle
        }
        return candidates.sorted { $0.distanceMeters < $1.distanceMeters }.first
    }

    private func updateAimAssist() {
        guard !targets.isEmpty else {
            aimAssist = .none
            return
        }

        let ranked = targets.map { player in
            (player: player, angle: angleDifference(compassHeading, player.heading))
        }
        guard let best = ranked.sorted(by: {
            if $0.angle != $1.angle { return $0.angle < $1.angle }
            return $0.player.distanceMeters < $1.player.distanceMeters
        }).first else {
            aimAssist = .none
            return
        }

        guard best.angle <= approachAngle else {
            aimAssist = .none
            return
        }

        let state: AimAssistState
        if best.angle <= lockAngle {
            state = .locked
        } else if best.angle <= preLockAngle {
            state = .locking
        } else {
            state = .tracking
        }

        let progress = max(0, 1 - (best.angle / approachAngle))
        aimAssist = AimAssist(
            state: state,
            targetID: best.player.id,
            targetName: best.player.name,
            distanceMeters: best.player.distanceMeters,
            angleDifference: best.angle,
            progress: progress
        )
    }

    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    private func startHeadingSimulation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self else { return }
            let delta = Double.random(in: -6...6)
            compassHeading = (compassHeading + delta).truncatingRemainder(dividingBy: 360)
            if compassHeading < 0 { compassHeading += 360 }
            updateAimAssist()
        }
    }

    private func stopHeadingSimulation() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

private extension JSONEncoder {
    static var withIso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private extension JSONDecoder {
    static var withIso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

private extension URL {
    var wsBase: String {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        if components?.scheme == "https" {
            components?.scheme = "wss"
        } else {
            components?.scheme = "ws"
        }
        components?.path = ""
        components?.query = nil
        return components?.string ?? "ws://localhost:8000"
    }
}
