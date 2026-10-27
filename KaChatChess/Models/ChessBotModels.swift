import SwiftUI

/// A bot to play in Play > Bots: five characters, one per level. Level 1 is open from the
/// start; each one after opens when the one before it is beaten.
struct ChessBot: Identifiable, Hashable {
    let level: Int
    let name: String
    let title: String
    let bio: String
    let initials: String
    /// The avatar's gradient, top to bottom.
    let colors: [Color]
    let settings: ChessBotEngine.Settings

    var id: Int { level }

    static func == (lhs: ChessBot, rhs: ChessBot) -> Bool { lhs.level == rhs.level }
    func hash(into hasher: inout Hasher) { hasher.combine(level) }

    /// The search for the move at `ply` (0 = the game's first). The master varies its opening
    /// a little so no two games start the same; past the opening it plays its best.
    func searchSettings(atPly ply: Int) -> ChessBotEngine.Settings {
        guard settings.noise == 0, ply < 8 else { return settings }
        return ChessBotEngine.Settings(
            depth: settings.depth, quiescence: settings.quiescence, noise: 12,
            randomChance: settings.randomChance, timeLimit: settings.timeLimit
        )
    }

    static let all: [ChessBot] = [
        ChessBot(
            level: 1, name: "Kaspa Silver", title: "Beginner",
            bio: "Here for the fun of it. Moves fast and sometimes leaves a piece hanging.",
            initials: "KS",
            colors: [Color(red: 0.78, green: 0.80, blue: 0.84), Color(red: 0.50, green: 0.53, blue: 0.58)],
            settings: .init(depth: 1, quiescence: false, noise: 250, randomChance: 0.35, timeLimit: 1)
        ),
        ChessBot(
            level: 2, name: "Izio Dev", title: "Novice",
            bio: "Knows how every piece moves and loves grabbing free material. Watch your loose pawns.",
            initials: "ID",
            colors: [Color(red: 0.36, green: 0.80, blue: 0.86), Color(red: 0.12, green: 0.52, blue: 0.66)],
            settings: .init(depth: 1, quiescence: true, noise: 100, randomChance: 0.12, timeLimit: 1)
        ),
        ChessBot(
            level: 3, name: "Coderofstuff", title: "Intermediate",
            bio: "Looks a couple of moves ahead before committing. Steady and hard to trick.",
            initials: "CS",
            colors: [Color(red: 0.44, green: 0.78, blue: 0.73), Color(red: 0.16, green: 0.55, blue: 0.47)],
            settings: .init(depth: 2, quiescence: true, noise: 40, randomChance: 0.04, timeLimit: 2)
        ),
        ChessBot(
            level: 4, name: "Michael Sutton", title: "Advanced",
            bio: "Calculates carefully and punishes mistakes. Come with a plan.",
            initials: "MS",
            colors: [Color(red: 0.55, green: 0.55, blue: 0.95), Color(red: 0.32, green: 0.25, blue: 0.72)],
            settings: .init(depth: 3, quiescence: true, noise: 12, randomChance: 0, timeLimit: 3)
        ),
        ChessBot(
            level: 5, name: "Yonatan Sompolinsky", title: "Master",
            bio: "Thinks deep and sees far. Beat this one and you have climbed the whole ladder.",
            initials: "YS",
            colors: [Color(red: 0.98, green: 0.80, blue: 0.36), Color(red: 0.85, green: 0.52, blue: 0.10)],
            settings: .init(depth: 6, quiescence: true, noise: 0, randomChance: 0, timeLimit: 4)
        )
    ]
}

/// The player's colour choice before a bot game.
enum ChessBotSidePreference: String, CaseIterable, Identifiable {
    case white = "White"
    case random = "Random"
    case black = "Black"

    var id: String { rawValue }

    func resolve() -> ChessColor {
        switch self {
        case .white: return .white
        case .black: return .black
        case .random: return Bool.random() ? .white : .black
        }
    }
}

// MARK: - On chain (ONLINE_CHESS.md §7)

/// A bot game message: plaintext broadcast JSON in `#chess-bots`, signed by the player's
/// address - for the player's moves and the bot's replies alike, so the whole game is on chain.
struct ChessBotMessage: Codable, Equatable {
    var type: String = "chess_bot"
    var v: Int = 1
    /// Game id: a lowercase UUID chosen by the player's phone.
    let g: String
    /// Action: start, move, resign.
    let a: String
    /// `start` only: the bot's level, 1...5.
    var bot: Int? = nil
    /// `start` only: the player's colour, "w" or "b".
    var c: String? = nil
    /// Ply number of a move (1 = white's first move).
    var n: Int? = nil
    var from: String? = nil
    var to: String? = nil
    /// Promotion piece letter: q r b n.
    var promo: String? = nil
}

enum ChessBotCodec {
    static let channel = "chess-bots"

    static func start(id: String, bot: ChessBot, playerColor: ChessColor) -> ChessBotMessage {
        ChessBotMessage(g: id, a: "start", bot: bot.level, c: playerColor == .white ? "w" : "b")
    }

    static func move(id: String, ply: Int, move: ChessMove) -> ChessBotMessage {
        ChessBotMessage(
            g: id, a: "move", n: ply, from: move.from.algebraic, to: move.to.algebraic,
            promo: move.promotion?.promotionLetter
        )
    }

    static func resign(id: String) -> ChessBotMessage {
        ChessBotMessage(g: id, a: "resign")
    }

    static func encode(_ message: ChessBotMessage) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(message), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// One move's fee, for the "about 0.0017 KAS a move" line: the same estimate the arena's
    /// Join button shows (one input, a fixed-size payload).
    @MainActor
    static func moveFeeText() -> String? {
        guard let wallet = WalletManager.shared.currentWallet,
              let senderScriptPubKey = KaspaAddress.scriptPublicKey(from: wallet.publicAddress) else { return nil }
        let sample = move(id: UUID().uuidString.lowercased(), ply: 40, move: ChessMove(
            from: ChessSquare(file: 4, rank: 1), to: ChessSquare(file: 4, rank: 3), promotion: nil
        ))
        let payload = KasiaTransactionBuilder.buildPublicChatPayload(channel: channel, content: encode(sample))
        let sompi = KasiaTransactionBuilder.estimatePublicChatFee(payload: payload, inputCount: 1, senderScriptPubKey: senderScriptPubKey)
        return String(format: "%.4f %@", Double(sompi) / 100_000_000, KaspaUnit.symbol)
    }
}

// MARK: - Record

/// The player's record against each bot, kept on this phone per address. A win against a bot
/// opens the next level.
@MainActor
final class ChessBotProgress: ObservableObject {
    static let shared = ChessBotProgress()

    struct Record: Codable, Equatable {
        var wins = 0
        var losses = 0
        var draws = 0
    }

    enum Result: Equatable {
        case won(String)
        case lost(String)
        case drawn(String)
    }

    /// Address -> level -> record.
    @Published private var records: [String: [Int: Record]]

    private static let defaultsKey = "chessBotRecords"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: [Int: Record]].self, from: data) {
            records = saved
        } else {
            records = [:]
        }
    }

    private var address: String { WalletManager.shared.currentWallet?.publicAddress ?? "" }

    func record(for bot: ChessBot) -> Record {
        records[address]?[bot.level] ?? Record()
    }

    func isUnlocked(_ bot: ChessBot) -> Bool {
        guard bot.level > 1, let previous = ChessBot.all.first(where: { $0.level == bot.level - 1 }) else { return true }
        return record(for: previous).wins > 0
    }

    func add(_ result: Result, against bot: ChessBot) {
        var record = record(for: bot)
        switch result {
        case .won: record.wins += 1
        case .lost: record.losses += 1
        case .drawn: record.draws += 1
        }
        records[address, default: [:]][bot.level] = record
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
