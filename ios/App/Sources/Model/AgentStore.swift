import Foundation
import StoreKit

/// The AI Agents add-on: a monthly App Store subscription that pays for the connector server.
/// The rest of the app never needs it.
enum AgentSubscription {
    static let productID = "com.rudilosso.ammutta.agents.monthly"
}

/// The App Store side of the subscription. StoreKit hands out transactions signed by Apple
/// (JWS); the app forwards them to the connector, which verifies them itself.
@MainActor
protocol AgentStore: AnyObject {
    /// The signed transaction for the active subscription, if there is one.
    func currentTransaction() async -> String?
    /// Calls `onTransaction` with every new signed transaction: renewals, redeemed offer codes,
    /// purchases made on another device.
    func observe(_ onTransaction: @escaping @MainActor (String) -> Void)
}

@MainActor
final class StoreKitAgentStore: AgentStore {
    private var updates: Task<Void, Never>?

    func currentTransaction() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == AgentSubscription.productID {
                return result.jwsRepresentation
            }
        }
        return nil
    }

    func observe(_ onTransaction: @escaping @MainActor (String) -> Void) {
        updates?.cancel()
        updates = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result, transaction.productID == AgentSubscription.productID else { continue }
                onTransaction(result.jwsRepresentation)
                await transaction.finish()
            }
        }
    }
}

/// No App Store: unit tests, UI tests and previews.
@MainActor
final class FakeAgentStore: AgentStore {
    var transaction: String?
    private var onTransaction: (@MainActor (String) -> Void)?

    func currentTransaction() async -> String? { transaction }

    func observe(_ onTransaction: @escaping @MainActor (String) -> Void) {
        self.onTransaction = onTransaction
    }

    /// Simulates a renewal or a redeemed code arriving from the App Store.
    func deliver(_ jws: String) {
        transaction = jws
        onTransaction?(jws)
    }
}
