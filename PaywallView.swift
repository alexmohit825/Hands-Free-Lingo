import SwiftUI
import StoreKit

/// High-converting, driver-safe paywall modal for Hands-Free Lingo.
/// Highlights the 4 languages, 204 units, CarPlay integration, and one-time $4.99 lifetime ownership.
public struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storeManager = StoreKitManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background dark gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.08, blue: 0.14),
                        Color(red: 0.02, green: 0.03, blue: 0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header Badge
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                                .font(.system(size: 12))
                            Text("ONE-TIME PURCHASE • ZERO SUBSCRIPTIONS")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.yellow.opacity(0.12))
                        .cornerRadius(20)
                        .padding(.top, 10)

                        // Title & Subtitle
                        VStack(spacing: 8) {
                            Text("Unlock Lifetime Access")
                                .font(.system(.title, design: .rounded))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text("Master 4 languages hands-free on your daily commute with Apple CarPlay.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }

                        // Feature Highlights Card
                        VStack(spacing: 16) {
                            featureRow(
                                icon: "globe.americas.fill",
                                color: .blue,
                                title: "4 Full World Languages",
                                subtitle: "Complete native curricula for Spanish, French, German & Japanese."
                            )

                            featureRow(
                                icon: "book.pages.fill",
                                color: .purple,
                                title: "204 Curated Units & 1,855 Phrases",
                                subtitle: "Travel essentials, street ordering, dining, emergencies, and executive meetings."
                            )

                            featureRow(
                                icon: "car.fill",
                                color: .green,
                                title: "Apple CarPlay Hands-Free Audio",
                                subtitle: "Seamless voice repetition loops designed for driver safety."
                            )

                            featureRow(
                                icon: "sparkles",
                                color: .orange,
                                title: "Unlimited AI Textbook Generator",
                                subtitle: "Generate custom conversational lessons on any topic instantly."
                            )

                            featureRow(
                                icon: "infinity.circle.fill",
                                color: .cyan,
                                title: "Lifetime Ownership",
                                subtitle: "Pay once, keep forever. No recurring fees, no surprise renewals."
                            )
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                        // Error Banner
                        if let error = storeManager.errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                                .multilineTextAlignment(.center)
                        }

                        // Pricing CTA Button
                        VStack(spacing: 12) {
                            Button(action: {
                                Task {
                                    let success = await storeManager.purchase()
                                    if success {
                                        dismiss()
                                    }
                                }
                            }) {
                                HStack {
                                    if storeManager.isPurchasing {
                                        ProgressView()
                                            .tint(.black)
                                            .padding(.trailing, 8)
                                    }
                                    
                                    Text(purchaseButtonTitle)
                                        .font(.system(.headline, design: .rounded))
                                        .fontWeight(.heavy)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.black)
                                .cornerRadius(18)
                                .shadow(color: Color.blue.opacity(0.4), radius: 12, x: 0, y: 6)
                            }
                            .disabled(storeManager.isPurchasing)

                            // Restore Purchases Button
                            Button(action: {
                                Task {
                                    await storeManager.restorePurchases()
                                    if storeManager.isUnlocked {
                                        dismiss()
                                    }
                                }
                            }) {
                                Text("Restore Previous Purchases")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.gray)
                            }
                            .disabled(storeManager.isPurchasing)
                        }
                        .padding(.horizontal, 20)

                        // Terms & Privacy Policy Footnote (Apple Requirement)
                        HStack(spacing: 16) {
                            Link("Privacy Policy", destination: URL(string: "https://alexmohit825.github.io/Hands-Free-Lingo/privacy.html") ?? URL(string: "https://apple.com")!)
                                .font(.system(size: 11))
                                .foregroundColor(.gray.opacity(0.8))

                            Text("•")
                                .foregroundColor(.gray.opacity(0.5))

                            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                                .font(.system(size: 11))
                                .foregroundColor(.gray.opacity(0.8))
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let product = storeManager.lifetimeProduct {
            return "Unlock Lifetime Access — \(product.displayPrice)"
        } else {
            return "Unlock Lifetime Access — $4.99"
        }
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
