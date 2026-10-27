import Foundation

/// One game against a bot (Play > Bots). The board lives on this phone, and every step of the
/// game goes on chain as it happens (ONLINE_CHESS.md §7): the start, each move - the player's
/// and the bot's, both signed by the player's address - and a resignation. Sends go out one at
/// a time, in order; the bot replies only once the player's move is on chain, and the player
/// moves only once the bot's is, so the chain always holds the game up to the board. A send
/// that fails holds the game until Retry.
@MainActor
final class ChessBotGame: ObservableObject {
    struct PlayedMove {
        let move: ChessMove
        let color: ChessColor
        let piece: ChessPieceType
        let captured: ChessPieceType?
    }

    let bot: ChessBot
    let playerColor: ChessColor
    let id = UUID().uuidString.lowercased()

    @Published private(set) var board = ChessEngine.initialBoard()
    @Published private(set) var moves: [PlayedMove] = []
    @Published private(set) var result: ChessBotProgress.Result?
    @Published private(set) var isThinking = false
    /// Messages still to go on chain, the first one sending.
    @Published private(set) var outbox: [ChessBotMessage] = []
    /// Moves on chain so far (the start message not counted).
    @Published private(set) var movesOnChain = 0
    @Published private(set) var sendError: String?

    private var isSending = false
    private var started = false
    private var positionCounts: [String: Int] = [:]
    private var halfmoveClock = 0

    init(bot: ChessBot, playerColor: ChessColor) {
        self.bot = bot
        self.playerColor = playerColor
    }

    var botColor: ChessColor { playerColor.opposite }
    var isOver: Bool { result != nil }

    /// The player may move: their turn, the bot not thinking, everything before on chain.
    var canPlayerMove: Bool {
        !isOver && board.sideToMove == playerColor && !isThinking && outbox.isEmpty && sendError == nil
    }

    /// The board opened: the start goes on chain; if the bot has white it moves once that lands.
    func start() {
        guard !started else { return }
        started = true
        positionCounts[ChessTournamentEngine.positionKey(board)] = 1
        enqueue(ChessBotCodec.start(id: id, bot: bot, playerColor: playerColor))
    }

    func play(_ move: ChessMove) {
        guard canPlayerMove, ChessEngine.isLegal(move, in: board) else { return }
        apply(ChessEngine.normalizingPromotion(move, in: board))
    }

    func resign() {
        guard started, !isOver else { return }
        finish(.lost("resignation"))
        enqueue(ChessBotCodec.resign(id: id))
    }

    func retry() {
        sendError = nil
        pump()
    }

    // MARK: - The board

    private func apply(_ move: ChessMove) {
        guard let piece = board.piece(at: move.from) else { return }
        let isEnPassant = piece.type == .pawn && move.to == board.enPassantTarget && board.piece(at: move.to) == nil
        let captured = board.piece(at: move.to)?.type ?? (isEnPassant ? .pawn : nil)
        let mover = board.sideToMove
        board = ChessEngine.apply(move, to: board)
        moves.append(PlayedMove(move: move, color: mover, piece: piece.type, captured: captured))
        enqueue(ChessBotCodec.move(id: id, ply: moves.count, move: move))

        halfmoveClock = (piece.type == .pawn || captured != nil) ? 0 : halfmoveClock + 1
        let key = ChessTournamentEngine.positionKey(board)
        positionCounts[key, default: 0] += 1

        if ChessEngine.isCheckmate(board) {
            finish(mover == playerColor ? .won("checkmate") : .lost("checkmate"))
        } else if ChessEngine.isStalemate(board) {
            finish(.drawn("stalemate"))
        } else if ChessEngine.isInsufficientMaterial(board) {
            finish(.drawn("insufficient material"))
        } else if halfmoveClock >= 100 {
            finish(.drawn("the fifty-move rule"))
        } else if positionCounts[key, default: 0] >= 3 {
            finish(.drawn("threefold repetition"))
        }
    }

    private func finish(_ result: ChessBotProgress.Result) {
        guard self.result == nil else { return }
        self.result = result
        ChessBotProgress.shared.add(result, against: bot)
    }

    /// The bot's turn and the chain caught up: think off the main thread (never quicker than
    /// a beat, so a reply does not land in the same instant as the player's move), then play.
    private func botMoveIfDue() {
        guard !isOver, board.sideToMove == botColor, !isThinking, outbox.isEmpty, sendError == nil else { return }
        isThinking = true
        let position = board
        let settings = bot.searchSettings(atPly: moves.count)
        let avoiding = repeatingMoves()
        let began = Date()
        Task {
            let move = await Task.detached(priority: .userInitiated) {
                ChessBotEngine.bestMove(for: position, settings: settings, avoiding: avoiding)
            }.value
            let elapsed = Date().timeIntervalSince(began)
            if elapsed < 0.8 {
                try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000))
            }
            isThinking = false
            guard !isOver, let move, board == position else { return }
            apply(move)
        }
    }

    /// The bot's moves that bring back a position already seen this game.
    private func repeatingMoves() -> [ChessMove] {
        ChessEngine.legalMoves(for: board).filter { move in
            positionCounts[ChessTournamentEngine.positionKey(ChessEngine.apply(move, to: board))] != nil
        }
    }

    // MARK: - On chain

    private func enqueue(_ message: ChessBotMessage) {
        outbox.append(message)
        pump()
    }

    private func pump() {
        guard !isSending, sendError == nil, let next = outbox.first else { return }
        isSending = true
        Task {
            let error = await send(next)
            isSending = false
            if let error {
                sendError = error
                return
            }
            outbox.removeFirst()
            if next.a == "move" { movesOnChain += 1 }
            pump()
            botMoveIfDue()
        }
    }

    /// One broadcast transaction, with the retries back-to-back sends need: the change of the
    /// last transaction is not spendable until it is mined (the arena's sends do the same).
    /// Returns the error to show, or nil once it is sent.
    private func send(_ message: ChessBotMessage) async -> String? {
        let content = ChessBotCodec.encode(message)
        var attempt = 0
        while true {
            do {
                try await PublicChatService.shared.sendPublicChat(channel: ChessBotCodec.channel, content: content)
                return nil
            } catch {
                attempt += 1
                if attempt > 5 {
                    AppLog.log("[Chess] Bot game send failed after retries: %@", error.localizedDescription)
                    return error.localizedDescription
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }
}
