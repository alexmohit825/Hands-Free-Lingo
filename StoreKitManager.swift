import SwiftUI
import StoreKit

/// Native StoreKit 2 manager for Hands-Free Lingo.
/// Handles the one-time Lifetime Unlock product, transaction updates,
/// and grandfathering of legacy users who purchased version 1.0.2 or earlier.
@MainActor
public final class StoreKitManager: ObservableObject {
    public static let shared = StoreKitManager()

    /// Product ID registered in App Store Connect
    public static let lifetimeProductID = "com.Alex.VocalLingo.lifetime_unlock"

    @Published public private(set) var isUnlocked: Bool = false
    @Published public private(set) var lifetimeProduct: Product? = nil
    @Published public private(set) var isPurchasing: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private var updateListenerTask: Task<Void, Never>? = nil

    private init() {
        // Check cached local unlock status immediately to prevent UI flash
        self.isUnlocked = UserDefaults.standard.bool(forKey: "vocal_lingo_is_unlocked")

        // Start listening for transaction updates (purchases outside app, restores, ask-to-buy)
        updateListenerTask = listenForTransactions()

        // Fetch products and verify actual App Store entitlements asynchronously
        Task {
            await loadProducts()
            await updatePurchasedStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    await self.handle(transaction: transaction)
                    await transaction.finish()
                } catch {
                    print("[StoreKit] Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Load Products

    public func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.lifetimeProductID])
            self.lifetimeProduct = products.first { $0.id == Self.lifetimeProductID }
            print("[StoreKit] Loaded product: \(String(describing: self.lifetimeProduct?.displayName)) - \(self.lifetimeProduct?.displayPrice ?? "N/A")")
        } catch {
            print("[StoreKit] Failed to fetch products: \(error)")
            self.errorMessage = "Unable to load App Store products."
        }
    }

    // MARK: - Entitlement & Grandfathering Verification

    public func updatePurchasedStatus() async {
        // 1. Check App Store In-App Purchase Entitlements
        var hasActiveEntitlement = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.lifetimeProductID && transaction.revocationDate == nil {
                    hasActiveEntitlement = true
                    break
                }
            }
        }

        if hasActiveEntitlement {
            setUnlocked(true)
            return
        }

        // 2. Grandfather Legacy Paid Users (Guideline 3.1.2)
        // If the user purchased the original paid app (v1.0.2 or earlier), unlock permanently.
        do {
            if case .verified(let appTransaction) = try await AppTransaction.shared {
                let originalVersion = appTransaction.originalAppVersion
                print("[StoreKit] AppTransaction verified. originalAppVersion: \(originalVersion)")
                if isLegacyPaidVersion(originalVersion) {
                    print("[StoreKit] Grandfathering legacy user from version \(originalVersion)")
                    setUnlocked(true)
                    return
                }
            }
        } catch {
            print("[StoreKit] AppTransaction check failed or in simulator: \(error)")
        }

        // Retain cache if already unlocked, otherwise lock
        if !UserDefaults.standard.bool(forKey: "vocal_lingo_is_unlocked") {
            setUnlocked(false)
        }
    }

    /// Determines whether the original purchase version qualifies as a legacy upfront purchase
    private func isLegacyPaidVersion(_ version: String) -> Bool {
        // Version format could be "1.0", "1.0.1", "1.0.2", or numeric build "1", "2", "3"
        let legacyVersions: Set<String> = ["1.0", "1.0.0", "1.0.1", "1.0.2", "1", "2", "3"]
        if legacyVersions.contains(version) {
            return true
        }
        // Semantic version compare: if version < "1.1.0"
        return version.compare("1.1.0", options: .numeric) == .orderedAscending
    }

    private func setUnlocked(_ unlocked: Bool) {
        self.isUnlocked = unlocked
        UserDefaults.standard.set(unlocked, forKey: "vocal_lingo_is_unlocked")
    }

    // MARK: - Purchase Flow

    public func purchase() async -> Bool {
        guard let product = lifetimeProduct else {
            errorMessage = "Product not available. Please check your internet connection."
            return false
        }

        isPurchasing = true
        errorMessage = nil

        do {
            let result = try await product.purchase()
            isPurchasing = false

            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await handle(transaction: transaction)
                await transaction.finish()
                return true

            case .userCancelled:
                print("[StoreKit] User cancelled purchase.")
                return false

            case .pending:
                print("[StoreKit] Purchase pending (Ask to Buy enabled).")
                return false

            @unknown default:
                return false
            }
        } catch {
            isPurchasing = false
            errorMessage = error.localizedDescription
            print("[StoreKit] Purchase failed: \(error)")
            return false
        }
    }

    // MARK: - Restore Purchases Flow

    public func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await updatePurchasedStatus()
            isPurchasing = false
        } catch {
            isPurchasing = false
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func handle(transaction: StoreKit.Transaction) async {
        if transaction.productID == Self.lifetimeProductID {
            if transaction.revocationDate == nil {
                setUnlocked(true)
            } else {
                setUnlocked(false)
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
