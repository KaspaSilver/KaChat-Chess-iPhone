import Foundation

/// The bots' move search (Play > Bots). `ChessEngine` is the rules - it decides what is legal,
/// and every move a bot plays is checked against its list - but it copies the whole board for
/// every move it tries, far too slow to look several moves ahead on a phone. So the search runs
/// on its own compact board (`BotPosition`: 64 ints, make/unmake in place) with a plain
/// alpha-beta: iterative deepening under a time limit, captures searched to quiet positions,
/// piece-square tables for the evaluation. The levels differ in how deep they look and how much
/// noise they add to their choice (see `ChessBot.all`).
enum ChessBotEngine {
    struct Settings: Hashable {
        /// Plies searched at most (iterative deepening stops early on the time limit).
        let depth: Int
        /// Follow captures past the depth so a piece is never counted mid-exchange.
        let quiescence: Bool
        /// Centipawns of random noise on each root move's score: how loosely the bot plays.
        let noise: Int
        /// Chance of an outright random legal move - the beginner's blunders.
        let randomChance: Double
        /// Seconds of thinking at most, past depth 1.
        let timeLimit: TimeInterval
    }

    /// The bot's move in `board`, or nil when there is none (the game is over).
    /// `avoiding`: moves that repeat a position already seen in this game - scored as a draw,
    /// so a bot that is winning does not shuffle into threefold repetition (and one that is
    /// losing takes the draw when it can).
    static func bestMove(for board: ChessBoard, settings: Settings, avoiding: [ChessMove] = []) -> ChessMove? {
        let legal = ChessEngine.legalMoves(for: board)
        guard !legal.isEmpty else { return nil }
        if legal.count == 1 { return legal[0] }
        if Double.random(in: 0..<1) < settings.randomChance { return legal.randomElement() }
        let search = BotSearch(position: BotPosition(board), settings: settings, drawish: avoiding)
        guard let move = search.run()?.chessMove else { return legal.randomElement() }
        // The rules engine has the last word: a search move it does not know (it never should
        // happen) becomes a random legal one rather than an illegal move on chain.
        return legal.contains(move) ? move : legal.randomElement()
    }
}

// MARK: - Board

/// A move on `BotPosition`'s board: squares 0...63 (rank * 8 + file, a1 = 0).
struct BotMove {
    enum Flag { case normal, doublePush, enPassant, castle }

    let from: Int
    let to: Int
    /// Promotion piece code (2 knight, 3 bishop, 4 rook, 5 queen), 0 for none.
    var promo: Int = 0
    var flag: Flag = .normal
    /// Move-ordering score: captures by most valuable victim, then least valuable attacker.
    var order: Int = 0

    var chessMove: ChessMove {
        let promotion: ChessPieceType?
        switch promo {
        case 2: promotion = .knight
        case 3: promotion = .bishop
        case 4: promotion = .rook
        case 5: promotion = .queen
        default: promotion = nil
        }
        return ChessMove(
            from: ChessSquare(file: from % 8, rank: from / 8),
            to: ChessSquare(file: to % 8, rank: to / 8),
            promotion: promotion
        )
    }
}

/// Precomputed targets per square, so move generation never checks the board's edges.
private enum BotTables {
    static func targets(_ offsets: [(Int, Int)]) -> [[Int]] {
        (0..<64).map { square in
            let file = square % 8, rank = square / 8
            return offsets.compactMap { df, dr in
                let f = file + df, r = rank + dr
                return (0..<8).contains(f) && (0..<8).contains(r) ? r * 8 + f : nil
            }
        }
    }

    static let knight = targets([(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)])
    static let king = targets([(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)])

    /// Rays from each square: directions 0...3 straight, 4...7 diagonal.
    static let rays: [[[Int]]] = (0..<64).map { square in
        let file = square % 8, rank = square / 8
        return [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)].map { df, dr in
            var ray: [Int] = []
            var f = file + df, r = rank + dr
            while (0..<8).contains(f) && (0..<8).contains(r) {
                ray.append(r * 8 + f)
                f += df
                r += dr
            }
            return ray
        }
    }

    /// Castling bits a move from or to this square clears (1 white king side, 2 white queen
    /// side, 4 black king side, 8 black queen side).
    static let castleMask: [Int] = (0..<64).map { square in
        switch square {
        case 0: return 2
        case 4: return 3
        case 7: return 1
        case 56: return 8
        case 60: return 12
        case 63: return 4
        default: return 0
        }
    }
}

/// The search's board. Pieces are codes 1 pawn ... 6 king, positive for white, negative for
/// black; `side` is 1 for white to move, -1 for black.
final class BotPosition {
    private(set) var squares: [Int]
    private(set) var side: Int
    private var castling: Int
    private var enPassant: Int
    /// King squares: [white, black].
    private var kings: [Int]
    private var history: [(move: BotMove, captured: Int, castling: Int, enPassant: Int)] = []

    static let values = [0, 100, 320, 330, 500, 900, 0]

    init(_ board: ChessBoard) {
        squares = Array(repeating: 0, count: 64)
        kings = [4, 60]
        for rank in 0..<8 {
            for file in 0..<8 {
                guard let piece = board.squares[rank][file] else { continue }
                let code: Int
                switch piece.type {
                case .pawn: code = 1
                case .knight: code = 2
                case .bishop: code = 3
                case .rook: code = 4
                case .queen: code = 5
                case .king: code = 6
                }
                squares[rank * 8 + file] = piece.color == .white ? code : -code
                if piece.type == .king { kings[piece.color == .white ? 0 : 1] = rank * 8 + file }
            }
        }
        side = board.sideToMove == .white ? 1 : -1
        castling = (board.whiteCanCastleKingside ? 1 : 0) | (board.whiteCanCastleQueenside ? 2 : 0)
            | (board.blackCanCastleKingside ? 4 : 0) | (board.blackCanCastleQueenside ? 8 : 0)
        enPassant = board.enPassantTarget.map { $0.rank * 8 + $0.file } ?? -1
    }

    // MARK: Attacks

    func isAttacked(_ square: Int, by color: Int) -> Bool {
        let file = square % 8, rank = square / 8
        // A white pawn attacks from the rank below, a black one from the rank above.
        let pawnRank = rank - color
        if pawnRank >= 0 && pawnRank < 8 {
            if file > 0 && squares[pawnRank * 8 + file - 1] == color { return true }
            if file < 7 && squares[pawnRank * 8 + file + 1] == color { return true }
        }
        for target in BotTables.knight[square] where squares[target] == 2 * color { return true }
        for target in BotTables.king[square] where squares[target] == 6 * color { return true }
        let rays = BotTables.rays[square]
        for direction in 0..<8 {
            for target in rays[direction] {
                let piece = squares[target]
                if piece == 0 { continue }
                if piece * color > 0 {
                    let type = abs(piece)
                    if type == 5 || type == (direction < 4 ? 4 : 3) { return true }
                }
                break
            }
        }
        return false
    }

    /// The side to move is in check.
    var inCheck: Bool { isAttacked(kings[side == 1 ? 0 : 1], by: -side) }

    /// The side that just moved left its own king attacked: the move was not legal.
    var moverInCheck: Bool { isAttacked(kings[side == 1 ? 1 : 0], by: side) }

    // MARK: Move generation (pseudo-legal; `make` then `moverInCheck` filters)

    func moves(capturesOnly: Bool) -> [BotMove] {
        var moves: [BotMove] = []
        moves.reserveCapacity(capturesOnly ? 12 : 48)
        let us = side
        for square in 0..<64 {
            let piece = squares[square]
            guard piece * us > 0 else { continue }
            switch abs(piece) {
            case 1:
                pawnMoves(square, capturesOnly: capturesOnly, into: &moves)
            case 2:
                for target in BotTables.knight[square] {
                    add(square, target, capturesOnly: capturesOnly, into: &moves)
                }
            case 3:
                slide(square, directions: 4..<8, capturesOnly: capturesOnly, into: &moves)
            case 4:
                slide(square, directions: 0..<4, capturesOnly: capturesOnly, into: &moves)
            case 5:
                slide(square, directions: 0..<8, capturesOnly: capturesOnly, into: &moves)
            default:
                for target in BotTables.king[square] {
                    add(square, target, capturesOnly: capturesOnly, into: &moves)
                }
                if !capturesOnly { castlingMoves(square, into: &moves) }
            }
        }
        return moves.sorted { $0.order > $1.order }
    }

    /// The legal moves, best-looking first.
    func legalMoves() -> [BotMove] {
        moves(capturesOnly: false).filter { move in
            make(move)
            defer { unmake() }
            return !moverInCheck
        }
    }

    private func add(_ from: Int, _ to: Int, capturesOnly: Bool, into moves: inout [BotMove]) {
        let victim = squares[to]
        if victim * side > 0 { return }
        if victim == 0 {
            if !capturesOnly { moves.append(BotMove(from: from, to: to)) }
            return
        }
        moves.append(BotMove(from: from, to: to, order: captureOrder(victim: abs(victim), attacker: abs(squares[from]))))
    }

    private func captureOrder(victim: Int, attacker: Int) -> Int {
        10_000 + BotPosition.values[victim] * 10 - attacker
    }

    private func slide(_ from: Int, directions: Range<Int>, capturesOnly: Bool, into moves: inout [BotMove]) {
        let rays = BotTables.rays[from]
        for direction in directions {
            for target in rays[direction] {
                let piece = squares[target]
                if piece == 0 {
                    if !capturesOnly { moves.append(BotMove(from: from, to: target)) }
                    continue
                }
                if piece * side < 0 {
                    moves.append(BotMove(from: from, to: target, order: captureOrder(victim: abs(piece), attacker: abs(squares[from]))))
                }
                break
            }
        }
    }

    private func pawnMoves(_ from: Int, capturesOnly: Bool, into moves: inout [BotMove]) {
        let step = side * 8
        let rank = from / 8, file = from % 8
        let promotes = rank == (side == 1 ? 6 : 1)
        let startRank = side == 1 ? 1 : 6

        func promotions(to target: Int, order: Int) {
            // Queen and knight only: a rook or bishop promotion is never better than a queen
            // except to dodge stalemate, which is not worth the search time here.
            moves.append(BotMove(from: from, to: target, promo: 5, order: order + 9_000))
            moves.append(BotMove(from: from, to: target, promo: 2, order: order + 1_000))
        }

        let one = from + step
        if squares[one] == 0 {
            if promotes {
                promotions(to: one, order: 0)
            } else if !capturesOnly {
                moves.append(BotMove(from: from, to: one))
                if rank == startRank && squares[one + step] == 0 {
                    moves.append(BotMove(from: from, to: one + step, flag: .doublePush))
                }
            }
        }
        for df in [-1, 1] {
            let targetFile = file + df
            guard targetFile >= 0 && targetFile < 8 else { continue }
            let target = one + df
            let victim = squares[target]
            if victim * side < 0 {
                let order = captureOrder(victim: abs(victim), attacker: 1)
                if promotes { promotions(to: target, order: order) } else { moves.append(BotMove(from: from, to: target, order: order)) }
            } else if target == enPassant {
                moves.append(BotMove(from: from, to: target, flag: .enPassant, order: captureOrder(victim: 1, attacker: 1)))
            }
        }
    }

    private func castlingMoves(_ from: Int, into moves: inout [BotMove]) {
        let base = side == 1 ? 0 : 56
        let kingSide = side == 1 ? 1 : 4
        let queenSide = side == 1 ? 2 : 8
        guard from == base + 4 else { return }
        if castling & kingSide != 0, squares[base + 5] == 0, squares[base + 6] == 0, squares[base + 7] == 4 * side,
           !isAttacked(base + 4, by: -side), !isAttacked(base + 5, by: -side), !isAttacked(base + 6, by: -side) {
            moves.append(BotMove(from: from, to: base + 6, flag: .castle))
        }
        if castling & queenSide != 0, squares[base + 3] == 0, squares[base + 2] == 0, squares[base + 1] == 0, squares[base] == 4 * side,
           !isAttacked(base + 4, by: -side), !isAttacked(base + 3, by: -side), !isAttacked(base + 2, by: -side) {
            moves.append(BotMove(from: from, to: base + 2, flag: .castle))
        }
    }

    // MARK: Make / unmake

    func make(_ move: BotMove) {
        let piece = squares[move.from]
        history.append((move, squares[move.to], castling, enPassant))
        squares[move.to] = move.promo != 0 ? move.promo * side : piece
        squares[move.from] = 0
        switch move.flag {
        case .enPassant:
            squares[move.to - 8 * side] = 0
        case .castle:
            if move.to > move.from {
                squares[move.from + 1] = squares[move.from + 3]
                squares[move.from + 3] = 0
            } else {
                squares[move.from - 1] = squares[move.from - 4]
                squares[move.from - 4] = 0
            }
        case .normal, .doublePush:
            break
        }
        if abs(piece) == 6 { kings[side == 1 ? 0 : 1] = move.to }
        castling &= ~(BotTables.castleMask[move.from] | BotTables.castleMask[move.to])
        enPassant = move.flag == .doublePush ? move.from + 8 * side : -1
        side = -side
    }

    func unmake() {
        let last = history.removeLast()
        let move = last.move
        side = -side
        let moved = squares[move.to]
        squares[move.from] = move.promo != 0 ? side : moved
        squares[move.to] = last.captured
        switch move.flag {
        case .enPassant:
            squares[move.to - 8 * side] = -side
        case .castle:
            if move.to > move.from {
                squares[move.from + 3] = squares[move.from + 1]
                squares[move.from + 1] = 0
            } else {
                squares[move.from - 4] = squares[move.from - 1]
                squares[move.from - 1] = 0
            }
        case .normal, .doublePush:
            break
        }
        if abs(moved) == 6 { kings[side == 1 ? 0 : 1] = move.from }
        castling = last.castling
        enPassant = last.enPassant
    }

    // MARK: Evaluation

    /// Centipawns for the side to move: material, piece-square tables, and in a won endgame a
    /// push of the losing king to the edge so the bot can actually finish the game.
    func evaluate() -> Int {
        var nonPawnMaterial = 0
        var balance = 0
        for square in 0..<64 {
            let piece = squares[square]
            guard piece != 0 else { continue }
            let type = abs(piece)
            if type != 1 && type != 6 { nonPawnMaterial += BotPosition.values[type] }
            balance += piece > 0 ? BotPosition.values[type] : -BotPosition.values[type]
        }
        let endgame = nonPawnMaterial <= 1_300

        var score = balance
        for square in 0..<64 {
            let piece = squares[square]
            guard piece != 0 else { continue }
            let type = abs(piece)
            // Tables are drawn from white's side with rank 8 first; black reads them mirrored.
            let index = piece > 0 ? (7 - square / 8) * 8 + square % 8 : square
            let table = type == 6 && endgame ? BotPosition.kingEndgame : BotPosition.tables[type]
            score += piece > 0 ? table[index] : -table[index]
        }

        if endgame && abs(balance) >= 300 {
            let winner = balance > 0 ? 1 : -1
            let loserKing = kings[winner == 1 ? 1 : 0]
            let winnerKing = kings[winner == 1 ? 0 : 1]
            let edge = max(3 - loserKing % 8, loserKing % 8 - 4) + max(3 - loserKing / 8, loserKing / 8 - 4)
            let distance = abs(loserKing % 8 - winnerKing % 8) + abs(loserKing / 8 - winnerKing / 8)
            score += winner * (edge * 10 + (14 - distance) * 4)
        }
        return score * side
    }

    private static let pawn = [
        0, 0, 0, 0, 0, 0, 0, 0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5, 5, 10, 25, 25, 10, 5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, -5, -10, 0, 0, -10, -5, 5,
        5, 10, 10, -20, -20, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0
    ]
    private static let knight = [
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50
    ]
    private static let bishop = [
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20
    ]
    private static let rook = [
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, 10, 10, 10, 10, 5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        0, 0, 0, 5, 5, 0, 0, 0
    ]
    private static let queen = [
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -5, 0, 5, 5, 5, 5, 0, -5,
        0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20
    ]
    private static let kingMiddlegame = [
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        20, 20, 0, 0, 0, 0, 20, 20,
        20, 30, 10, 0, 0, 10, 30, 20
    ]
    private static let kingEndgame = [
        -50, -40, -30, -20, -20, -30, -40, -50,
        -30, -20, -10, 0, 0, -10, -20, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -30, 0, 0, 0, 0, -30, -30,
        -50, -30, -30, -30, -30, -30, -30, -50
    ]
    private static let tables: [[Int]] = [[], pawn, knight, bishop, rook, queen, kingMiddlegame]
}

// MARK: - Search

private final class BotSearch {
    private let position: BotPosition
    private let settings: ChessBotEngine.Settings
    private let drawish: [ChessMove]
    private var deadline = Date.distantFuture
    private var nodes = 0
    private var aborted = false
    /// Depth 1 always finishes; only deeper iterations may be cut by the clock.
    private var canAbort = false

    private static let mate = 100_000
    private static let infinity = 1_000_000

    init(position: BotPosition, settings: ChessBotEngine.Settings, drawish: [ChessMove]) {
        self.position = position
        self.settings = settings
        self.drawish = drawish
    }

    func run() -> BotMove? {
        var rootMoves = position.legalMoves()
        guard !rootMoves.isEmpty else { return nil }
        deadline = Date().addingTimeInterval(settings.timeLimit)
        // With noise every root move needs its true score (a full window), not just a bound.
        let exact = settings.noise > 0
        var lastScored: [(move: BotMove, score: Int)] = []

        for depth in 1...max(1, settings.depth) {
            canAbort = depth > 1
            var scored: [(move: BotMove, score: Int)] = []
            var alpha = -Self.infinity
            for move in rootMoves {
                let score: Int
                if isDrawish(move) {
                    score = 0
                } else {
                    position.make(move)
                    score = -search(depth: depth - 1, alpha: -Self.infinity, beta: exact ? Self.infinity : -alpha, ply: 1)
                    position.unmake()
                }
                if aborted { break }
                scored.append((move, score))
                alpha = max(alpha, score)
            }
            if aborted { break }
            scored.sort { $0.score > $1.score }
            lastScored = scored
            // Searched best first next time round, which is what makes deepening cheap.
            rootMoves = scored.map { $0.move }
            if let best = scored.first, abs(best.score) >= Self.mate - 100 { break }
            if Date() > deadline { break }
        }

        guard !lastScored.isEmpty else { return nil }
        guard settings.noise > 0 else { return lastScored[0].move }
        return lastScored
            .map { (move: $0.move, score: $0.score + Int.random(in: -settings.noise...settings.noise)) }
            .max { $0.score < $1.score }?
            .move
    }

    private func isDrawish(_ move: BotMove) -> Bool {
        guard !drawish.isEmpty else { return false }
        let chess = move.chessMove
        return drawish.contains(chess)
    }

    private func tick() {
        nodes += 1
        if canAbort && nodes & 1023 == 0 && Date() > deadline { aborted = true }
    }

    private func search(depth: Int, alpha alphaIn: Int, beta: Int, ply: Int) -> Int {
        tick()
        if aborted { return 0 }
        let inCheck = position.inCheck
        // Checks are searched one ply deeper, so a mate just past the horizon is still seen.
        let depth = inCheck && ply < 12 ? depth + 1 : depth
        if depth <= 0 {
            return settings.quiescence ? quiesce(alpha: alphaIn, beta: beta, ply: 0) : position.evaluate()
        }
        var alpha = alphaIn
        var legal = 0
        for move in position.moves(capturesOnly: false) {
            position.make(move)
            if position.moverInCheck {
                position.unmake()
                continue
            }
            legal += 1
            let score = -search(depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            position.unmake()
            if aborted { return 0 }
            if score >= beta { return score }
            if score > alpha { alpha = score }
        }
        if legal == 0 { return inCheck ? -Self.mate + ply : 0 }
        return alpha
    }

    private func quiesce(alpha alphaIn: Int, beta: Int, ply: Int) -> Int {
        tick()
        if aborted { return 0 }
        let standPat = position.evaluate()
        if standPat >= beta { return standPat }
        var alpha = max(alphaIn, standPat)
        if ply >= 6 { return alpha }
        for move in position.moves(capturesOnly: true) {
            position.make(move)
            if position.moverInCheck {
                position.unmake()
                continue
            }
            let score = -quiesce(alpha: -beta, beta: -alpha, ply: ply + 1)
            position.unmake()
            if aborted { return 0 }
            if score >= beta { return score }
            if score > alpha { alpha = score }
        }
        return alpha
    }
}
