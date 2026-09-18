import Foundation
import MultipeerConnectivity
import NearbyInteraction

/// Which side of a meeting this phone is on.
public enum PairingRole: String, Sendable, Codable {
    /// Has a team and lets someone in.
    case inviter
    /// Wants to join.
    case joiner
}

/// What the two phones say to each other once they are linked.
public enum PairingMessage: Codable, Sendable, Equatable {
    /// The joiner's Apple ID as CloudKit names it, so the inviter can let exactly that person in.
    case identity(userRecordName: String)
    /// The way in, sent only after the inviter said yes.
    case invite(url: URL, team: String)
    /// The inviter said no.
    case declined
    /// The joiner is in: the invite was accepted. Only now does the inviter's phone celebrate.
    case joined
}

/// What happens while two phones find each other, as the screen needs to hear it.
public enum PairingEvent: Sendable, Equatable {
    case linked(peer: String)
    /// Metres between the phones; nil on a phone that cannot measure it.
    case distance(Double?)
    /// Close enough to count as the tops of two phones touching.
    case touched
    case received(PairingMessage)
    case lost
}

/// Two phones in the same room, linked to each other and knowing how far apart they are.
///
/// Multipeer Connectivity carries the few messages a meeting needs, over a session that is
/// encrypted end to end; Nearby Interaction measures the distance so the light fires when the
/// phones actually touch, not when they are merely in the same building. Nothing here reaches the
/// internet, and nothing but the invite — which only lets in the one Apple ID it was made for —
/// ever crosses between the phones.
///
/// `@unchecked Sendable` because the framework objects it holds are not annotated; every piece of
/// state they touch is behind `lock`.
public final class NearbyLink: NSObject, @unchecked Sendable {
    public static let serviceType = "cuetake-team"
    /// Tops of two phones held together read as a few centimetres; a little slack keeps it from
    /// needing a second try.
    public static let touchDistance = 0.15

    public let role: PairingRole
    public let events: AsyncStream<PairingEvent>

    private let continuation: AsyncStream<PairingEvent>.Continuation
    private let lock = NSLock()
    private let me: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var nearby: NISession?
    private var peer: MCPeerID?
    private var hasTouched = false
    /// The other phone's token when it arrives before this phone's measuring has started — both
    /// start the moment they link, and either can be first.
    private var waitingToken: NIDiscoveryToken?

    private enum Kind: UInt8 {
        case token = 0
        case message = 1
    }

    public init(role: PairingRole, displayName: String) {
        self.role = role
        // The framework refuses names over 63 bytes; a phone's name can be longer.
        var name = displayName
        while name.utf8.count > 60 { name.removeLast() }
        me = MCPeerID(displayName: name.isEmpty ? "CueTake" : name)
        let (stream, continuation) = AsyncStream.makeStream(of: PairingEvent.self)
        self.events = stream
        self.continuation = continuation
        super.init()
    }

    /// Whether this phone can measure distance to another. Older phones link and pair all the
    /// same; they are told to tap instead of touch.
    public static var canMeasureDistance: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    public func start() {
        lock.withLock {
            let session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            self.session = session
            switch role {
            case .inviter:
                let browser = MCNearbyServiceBrowser(peer: me, serviceType: Self.serviceType)
                browser.delegate = self
                browser.startBrowsingForPeers()
                self.browser = browser
            case .joiner:
                let advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: Self.serviceType)
                advertiser.delegate = self
                advertiser.startAdvertisingPeer()
                self.advertiser = advertiser
            }
        }
    }

    public func stop() {
        lock.withLock {
            browser?.stopBrowsingForPeers()
            advertiser?.stopAdvertisingPeer()
            session?.disconnect()
            nearby?.invalidate()
            browser = nil
            advertiser = nil
            session = nil
            nearby = nil
            peer = nil
        }
        continuation.finish()
    }

    public func send(_ message: PairingMessage) {
        guard let body = try? JSONEncoder().encode(message) else { return }
        send(.message, body)
    }

    private func send(_ kind: Kind, _ body: Data) {
        lock.withLock {
            guard let session, let peer else { return }
            try? session.send(Data([kind.rawValue]) + body, toPeers: [peer], with: .reliable)
        }
    }

    /// Once linked, each phone hands the other its distance token and starts measuring.
    private func beginMeasuring() {
        guard Self.canMeasureDistance else {
            continuation.yield(.distance(nil))
            return
        }
        let session = NISession()
        session.delegate = self
        let early = lock.withLock { () -> NIDiscoveryToken? in
            nearby = session
            defer { waitingToken = nil }
            return waitingToken
        }
        if let early { session.run(NINearbyPeerConfiguration(peerToken: early)) }
        guard let token = session.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return }
        send(.token, data)
    }

    private func received(_ data: Data) {
        guard let first = data.first, let kind = Kind(rawValue: first) else { return }
        let body = data.dropFirst()
        switch kind {
        case .token:
            guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: Data(body)) else { return }
            let session = lock.withLock { () -> NISession? in
                if nearby == nil { waitingToken = token }
                return nearby
            }
            session?.run(NINearbyPeerConfiguration(peerToken: token))
        case .message:
            guard let message = try? JSONDecoder().decode(PairingMessage.self, from: Data(body)) else { return }
            continuation.yield(.received(message))
        }
    }
}

extension NearbyLink: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            // One meeting at a time: a third phone arriving is not let into this one.
            let isFirst = lock.withLock { () -> Bool in
                guard peer == nil else { return false }
                peer = peerID
                browser?.stopBrowsingForPeers()
                advertiser?.stopAdvertisingPeer()
                return true
            }
            guard isFirst else { return }
            continuation.yield(.linked(peer: peerID.displayName))
            beginMeasuring()
        case .notConnected:
            let wasOurs = lock.withLock { () -> Bool in
                guard peer == peerID else { return false }
                peer = nil
                return true
            }
            if wasOurs { continuation.yield(.lost) }
        default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard lock.withLock({ peer == peerID }) else { return }
        received(data)
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}

extension NearbyLink: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session = lock.withLock({ peer == nil ? self.session : nil }) else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension NearbyLink: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let session = lock.withLock { peer == nil ? self.session : nil }
        invitationHandler(session != nil, session)
    }
}

extension NearbyLink: NISessionDelegate {
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let reading = nearbyObjects.first?.distance else { return }
        let metres = Double(reading)
        continuation.yield(.distance(metres))
        let firstTouch = lock.withLock { () -> Bool in
            guard metres <= Self.touchDistance, !hasTouched else { return false }
            hasTouched = true
            return true
        }
        if firstTouch { continuation.yield(.touched) }
    }

    public func session(_ session: NISession, didInvalidateWith error: any Error) {
        continuation.yield(.distance(nil))
    }
}
