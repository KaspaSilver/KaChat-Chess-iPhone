import SwiftUI

/// KaChat Chess's dock: Play, Leaderboard, Wallet, Settings. Fixed - unlike KaChat's dock there
/// is nothing to rearrange, so none of KaChat's dock machinery (Kaspa Hub, Customize Dock) comes
/// along.
struct ChessMainTabView: View {
    enum Tab: Hashable { case play, leaderboard, wallet, settings }

    @EnvironmentObject private var walletManager: WalletManager
    @State private var selection: Tab = .play

    var body: some View {
        TabView(selection: $selection) {
            ChessHomeView()
                .tabItem { Label("Play", systemImage: "checkerboard.rectangle") }
                .tag(Tab.play)
            ChessLeaderboardTabView()
                .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }
                .tag(Tab.leaderboard)
            ChessWalletView()
                .tabItem { Label("Wallet", systemImage: "wallet.pass.fill") }
                .tag(Tab.wallet)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
    }
}

/// The Leaderboard tab: both boards, 1v1 and Tournaments, each for this month or all time.
/// The rows are Chess Online's own (`ChessLeaderboardRows`).
struct ChessLeaderboardTabView: View {
    @ObservedObject private var service = ChessTournamentService.shared
    @State private var mode: ChessTournamentsView.Mode = .duel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                UnderlineTabBar(
                    tabs: ChessTournamentsView.Mode.allCases.map { (tab: $0, title: $0.rawValue) },
                    selection: $mode
                )
                List {
                    ChessLeaderboardRows(mode: mode)
                }
                .listStyle(.insetGrouped)
                .refreshable { service.refreshIndexerLeaderboards() }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { ConnectionStatusIndicator() }
                ToolbarItem(placement: .principal) { BalanceToolbarLabel() }
            }
            // Reads the arena while the board is up, the same as the Play screens do.
            .onAppear { service.acquire() }
            .onDisappear { service.release() }
        }
    }
}

/// The Wallet tab: the one address every move is signed by - its balance, history, Receive
/// and Send.
struct ChessWalletView: View {
    @EnvironmentObject private var walletManager: WalletManager

    var body: some View {
        NavigationStack {
            if let address = walletManager.currentWallet?.publicAddress {
                ChattingAddressManageView(address: address)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { ConnectionStatusIndicator() }
                    }
            }
        }
    }
}
