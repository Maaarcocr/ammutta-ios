import AmmuttaCore
import Foundation
import Observation
import os
import Security

private let logger = Logger(subsystem: "dev.ammutta.app", category: "AgentConnector")

/// This phone's account on the agent connector: a random ID and secret made on the phone.
struct AgentAccount: Codable, Equatable {
    let id: String
    let secret: String

    static func make() -> AgentAccount {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return AgentAccount(id: UUID().uuidString.lowercased(), secret: bytes.map { String(format: "%02x", $0) }.joined())
    }
}

/// A plan an agent wrote, waiting on the server.
struct AgentInboxItem: Codable, Equatable {
    let id: String
    /// Set when the agent updated an existing plan.
    let planId: String?
    let name: String
    let link: String
}

/// Where the account is kept. The Keychain item syncs through iCloud Keychain, so a new phone
/// keeps the same account and connected agents.
@MainActor
protocol AgentAccountStore: AnyObject {
    func load() -> AgentAccount?
    func save(_ account: AgentAccount)
    func delete()
}

@MainActor
final class KeychainAgentAccountStore: AgentAccountStore {
    private let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.ammutta.agents",
        kSecAttrAccount as String: "account",
    ]

    func load() -> AgentAccount? {
        var query = base
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AgentAccount.self, from: data)
    }

    func save(_ account: AgentAccount) {
        delete()
        guard let data = try? JSONEncoder().encode(account) else { return }
        var item = base
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed: \(status, privacy: .public)")
        }
    }

    func delete() {
        var query = base
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class MemoryAgentAccountStore: AgentAccountStore {
    var account: AgentAccount?
    func load() -> AgentAccount? { account }
    func save(_ account: AgentAccount) { self.account = account }
    func delete() { account = nil }
}

/// The connector's API for the app (server/src/app-api.ts).
@MainActor
protocol AgentServer: AnyObject {
    /// The address to add in an agent as a custom connector.
    var connectorURL: URL { get }
    func putSnapshot(_ json: Data, account: AgentAccount) async throws
    func inbox(account: AgentAccount) async throws -> [AgentInboxItem]
    func removeFromInbox(_ id: String, account: AgentAccount) async throws
    func pairingCode(account: AgentAccount) async throws -> String
    func disconnectAgents(account: AgentAccount) async throws
    func deleteAccount(_ account: AgentAccount) async throws
    /// Whether the AI Agents subscription is active, as the server last verified it.
    func subscription(account: AgentAccount) async throws -> Bool
    /// Sends an Apple-signed transaction; the server verifies it and returns whether it's active.
    func uploadTransaction(_ jws: String, account: AgentAccount) async throws -> Bool
}

struct AgentServerError: Error {
    let status: Int
}

private struct SubscriptionStatus: Decodable {
    let active: Bool
}

@MainActor
final class HTTPAgentServer: AgentServer {
    private let base: URL

    init(host: String) {
        base = URL(string: "https://\(host)")!
    }

    var connectorURL: URL { base.appending(path: "mcp") }

    func putSnapshot(_ json: Data, account: AgentAccount) async throws {
        _ = try await send("PUT", "/snapshot", account: account, body: json)
    }

    func inbox(account: AgentAccount) async throws -> [AgentInboxItem] {
        try JSONDecoder().decode([AgentInboxItem].self, from: await send("GET", "/inbox", account: account))
    }

    func removeFromInbox(_ id: String, account: AgentAccount) async throws {
        _ = try await send("DELETE", "/inbox/\(id)", account: account)
    }

    func pairingCode(account: AgentAccount) async throws -> String {
        struct Pairing: Decodable { let code: String }
        return try JSONDecoder().decode(Pairing.self, from: await send("POST", "/pairing", account: account)).code
    }

    func disconnectAgents(account: AgentAccount) async throws {
        _ = try await send("DELETE", "/agents", account: account)
    }

    func deleteAccount(_ account: AgentAccount) async throws {
        _ = try await send("DELETE", "", account: account)
    }

    func subscription(account: AgentAccount) async throws -> Bool {
        try JSONDecoder().decode(SubscriptionStatus.self, from: await send("GET", "/subscription", account: account)).active
    }

    func uploadTransaction(_ jws: String, account: AgentAccount) async throws -> Bool {
        let body = try JSONEncoder().encode(["transaction": jws])
        return try JSONDecoder().decode(SubscriptionStatus.self, from: await send("POST", "/subscription", account: account, body: body)).active
    }

    private func send(_ method: String, _ path: String, account: AgentAccount, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: base.appending(path: "v1/accounts/\(account.id)\(path)"))
        request.httpMethod = method
        request.setValue("Bearer \(account.secret)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AgentServerError(status: status) }
        return data
    }
}

/// A server for tests and UI tests: keeps everything in memory.
@MainActor
final class FakeAgentServer: AgentServer {
    var connectorURL: URL { URL(string: "https://agents.example/mcp")! }
    var failing = false
    private(set) var snapshots: [Data] = []
    /// The server's view of the subscription; on by default so UI tests reach the connected screen.
    var active = true
    private(set) var uploadedTransactions: [String] = []
    var pending: [AgentInboxItem] = []
    private(set) var deletedAccounts: [String] = []
    private(set) var disconnects = 0

    private func check() throws {
        if failing { throw AgentServerError(status: 503) }
    }

    func putSnapshot(_ json: Data, account: AgentAccount) async throws {
        try check()
        snapshots.append(json)
    }

    func inbox(account: AgentAccount) async throws -> [AgentInboxItem] {
        try check()
        return pending
    }

    func removeFromInbox(_ id: String, account: AgentAccount) async throws {
        try check()
        pending.removeAll { $0.id == id }
    }

    func pairingCode(account: AgentAccount) async throws -> String {
        try check()
        return "K7M2QX9P"
    }

    func disconnectAgents(account: AgentAccount) async throws {
        try check()
        disconnects += 1
    }

    func deleteAccount(_ account: AgentAccount) async throws {
        try check()
        deletedAccounts.append(account.id)
    }

    func subscription(account: AgentAccount) async throws -> Bool {
        try check()
        return active
    }

    func uploadTransaction(_ jws: String, account: AgentAccount) async throws -> Bool {
        try check()
        uploadedTransactions.append(jws)
        active = true
        return active
    }
}

/// The "AI Agents" setting. While on, the app sends its data to the connector whenever it
/// changes and imports plans agents wrote whenever the app opens. Network work runs in order,
/// one step at a time.
@Observable
final class AgentConnector {
    @ObservationIgnored let server: (any AgentServer)?
    @ObservationIgnored private let store: any AgentStore
    @ObservationIgnored private let accounts: any AgentAccountStore
    @ObservationIgnored private let defaults: UserDefaults
    /// The data agents see; set by the app model.
    @ObservationIgnored var snapshot: () -> AgentSnapshot? = { nil }
    /// Imports one plan; set by the app model. Returns false to keep it for a later try.
    @ObservationIgnored var importPlan: (AgentInboxItem) -> Bool = { _ in false }
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var pushQueued = false

    /// The latest pairing code, shown until it expires.
    private(set) var pairingCode: String?
    private(set) var pairingExpiry: Date?
    /// True after the last network step failed; cleared by the next success.
    private(set) var isOffline = false
    /// Whether the AI Agents subscription is active, as the server verified it. Nothing is sent
    /// and no agent can connect without it.
    private(set) var isSubscribed = false

    private enum Keys {
        static let enabled = "agentsEnabled"
    }

    init(server: (any AgentServer)?, store: any AgentStore, accounts: any AgentAccountStore, defaults: UserDefaults) {
        self.server = server
        self.store = store
        self.accounts = accounts
        self.defaults = defaults
        isEnabled = server != nil && defaults.bool(forKey: Keys.enabled)
        store.observe { [weak self] jws in self?.transactionArrived(jws) }
    }

    /// Ties App Store purchases to this account, so the server knows whose subscription it is.
    var accountToken: UUID? { accounts.load().flatMap { UUID(uuidString: $0.id) } }

    /// False when this build has no connector address.
    var isAvailable: Bool { server != nil }
    var connectorURL: URL? { server?.connectorURL }

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                if accounts.load() == nil { accounts.save(.make()) }
                refresh()
            } else {
                turnOff()
            }
        }
    }

    /// The app's data changed: send it.
    func dataChanged() {
        guard isEnabled, isSubscribed, !pushQueued else { return }
        pushQueued = true
        enqueue { connector, server, account in
            connector.pushQueued = false
            try await connector.push(server, account)
        }
    }

    /// The app opened or came back: check the subscription, send the latest data and import new plans.
    func refresh() {
        guard isEnabled else { return }
        enqueue { connector, server, account in
            if let jws = await connector.store.currentTransaction() {
                connector.isSubscribed = try await server.uploadTransaction(jws, account: account)
            } else {
                connector.isSubscribed = try await server.subscription(account: account)
            }
            guard connector.isSubscribed else { return }
            try await connector.push(server, account)
            for item in try await server.inbox(account: account) {
                if connector.importPlan(item) {
                    try await server.removeFromInbox(item.id, account: account)
                }
            }
        }
    }

    /// A purchase, renewal or redeemed code: let the server verify it, then sync if it's active.
    func transactionArrived(_ jws: String) {
        enqueue { connector, server, account in
            connector.isSubscribed = try await server.uploadTransaction(jws, account: account)
            if connector.isSubscribed {
                try await connector.push(server, account)
            }
        }
    }

    func requestPairingCode() {
        enqueue { connector, server, account in
            connector.pairingCode = try await server.pairingCode(account: account)
            connector.pairingExpiry = .now.addingTimeInterval(600)
        }
    }

    func disconnectAgents() {
        pairingCode = nil
        enqueue { _, server, account in
            try await server.disconnectAgents(account: account)
        }
    }

    /// Lets tests wait for queued work.
    func settled() async {
        await queue?.value
    }

    private func turnOff() {
        pairingCode = nil
        isSubscribed = false
        guard let server, let account = accounts.load() else { return }
        accounts.delete()
        let previous = queue
        queue = Task {
            await previous?.value
            do {
                try await server.deleteAccount(account)
            } catch {
                logger.error("Deleting the agent account failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func push(_ server: any AgentServer, _ account: AgentAccount) async throws {
        guard let snapshot = snapshot() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try await server.putSnapshot(try encoder.encode(snapshot), account: account)
    }

    private func enqueue(_ step: @escaping @MainActor (AgentConnector, any AgentServer, AgentAccount) async throws -> Void) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self, self.isEnabled, let server = self.server, let account = self.accounts.load() else { return }
            do {
                try await step(self, server, account)
                self.isOffline = false
            } catch {
                self.isOffline = true
                logger.error("Agent connector step failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
