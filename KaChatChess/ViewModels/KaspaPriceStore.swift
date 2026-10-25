import Foundation

/// The KAS price in the currency picked in Settings > Customization, for the Send screen's
/// KAS / your-currency switch. KaChat read this off its Portfolio (`PortfolioViewModel`); the
/// price part is all KaChat Chess needs, so it is all that came along: fetched from CoinGecko,
/// kept across launches, refetched when it is older than five minutes or the currency changes.
@MainActor
final class KaspaPriceStore: ObservableObject {
    static let shared = KaspaPriceStore()

    /// KAS price in `currentCurrency` (the name is KaChat's, kept so the copied call sites read
    /// the same). Nil until the first price arrives.
    @Published private(set) var currentPriceUsd: Double?
    private(set) var currentCurrency: AppCurrency = SettingsViewModel.loadSettings().currency

    private let coinGecko = CoinGeckoService.shared
    private var lastFetchAt: Date?
    private var fetchTask: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?

    private struct PersistedPrice: Codable {
        let price: Double
        let fetchedAt: Date
    }

    private init() {
        restorePersistedPrice()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSettingsChanged() }
        }
        refreshIfStale()
    }

    /// Fetches the price unless one younger than five minutes is already here.
    func refreshIfStale() {
        if let lastFetchAt, Date().timeIntervalSince(lastFetchAt) < 5 * 60, currentPriceUsd != nil { return }
        guard fetchTask == nil else { return }
        let currency = currentCurrency
        fetchTask = Task { [weak self] in
            // CoinGecko's keyless tier throttles bursts, so a miss is asked again on a growing pause.
            for delay in [0.0, 3.0, 8.0, 20.0, 45.0] {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard let self, !Task.isCancelled, self.currentCurrency == currency else { break }
                if let result = await self.coinGecko.getCurrentPrice(currency: currency) {
                    self.apply(result.price, currency: currency)
                    break
                }
            }
            self?.fetchTask = nil
        }
    }

    private func apply(_ price: Double, currency: AppCurrency) {
        currentPriceUsd = price
        lastFetchAt = Date()
        if let data = try? JSONEncoder().encode(PersistedPrice(price: price, fetchedAt: Date())) {
            UserDefaults.standard.set(data, forKey: priceKey(currency))
        }
    }

    private func priceKey(_ currency: AppCurrency) -> String { "kachat_kas_price_\(currency.rawValue)" }

    private func restorePersistedPrice() {
        guard let data = UserDefaults.standard.data(forKey: priceKey(currentCurrency)),
              let saved = try? JSONDecoder().decode(PersistedPrice.self, from: data) else { return }
        currentPriceUsd = saved.price
    }

    private func handleSettingsChanged() {
        let newCurrency = SettingsViewModel.loadSettings().currency
        guard newCurrency != currentCurrency else { return }
        currentCurrency = newCurrency
        fetchTask?.cancel()
        fetchTask = nil
        currentPriceUsd = nil
        lastFetchAt = nil
        restorePersistedPrice()
        refreshIfStale()
    }
}
