import Foundation

/// Resolves an `AppCurrency` to its display symbol (e.g. "$", "€") - Bitcoin isn't ISO 4217, so
/// it's spelled out rather than trusted to `NumberFormatter`'s fallback behavior for an
/// unrecognized code. Mirrors `PortfolioView.currencySymbol(for:)`, kept separate since that one
/// stays `private` to its file - shared here for callers outside Portfolio (see
/// `KaspaFiatAmountState`).
func currencySymbol(for currency: AppCurrency) -> String {
    if currency == .bitcoin { return "₿" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency.code
    return formatter.currencySymbol ?? currency.code
}

/// Generic fiat total - symbol + 2 decimals, for a read-only display label (e.g. a live
/// KAS-to-fiat conversion next to a Max button). Not meant to be parsed back - see
/// `KaspaFiatAmountState`, which keeps its own plain (no symbol) edit buffer for that.
func formatFiatAmount(_ value: Double, currency: AppCurrency) -> String {
    let sign = value < 0 ? "-" : ""
    return "\(sign)\(currencySymbol(for: currency))\(String(format: "%.2f", abs(value)))"
}

/// Trimmed 8-decimal KAS amount (e.g. "12.5" rather than "12.50000000").
func formatKasAmountPlain(_ value: Double) -> String {
    var text = String(format: "%.8f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
}

extension KaspaUnit {
    /// "35 KAS", "0.2 KAS", "1.99831 KAS": exact, trailing zeros dropped.
    static func amount(_ sompi: UInt64) -> String {
        "\(plain(sompi)) \(symbol)"
    }

    /// "35", "0.2", "1.99831": the KAS amount, exact, trailing zeros dropped.
    static func plain(_ sompi: UInt64) -> String {
        let whole = sompi / 100_000_000
        let frac = sompi % 100_000_000
        guard frac > 0 else { return "\(whole)" }
        var f = String(format: "%08llu", frac)
        while f.hasSuffix("0") { f.removeLast() }
        return "\(whole).\(f)"
    }
}
