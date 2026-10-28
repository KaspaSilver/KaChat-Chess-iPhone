import SwiftUI

/// KaChat Chess's dock: Play, Leaderboard, Wallet, Settings. Fixed - unlike KaChat's dock there
/// is nothing to rearrange, so none of KaChat's dock machinery (Kaspa Hub, Customize Dock) comes
/// along.
struct ChessMainTabView: View {
    enum Tab: Hashable { case play, leaderboard, wallet, settings }

    @EnvironmentObject private var chatService: ChatService
    @State private var selection: Tab = .play

    /// KaPay's (and KaPosts') wallet symbol; it only exists from iOS 17, so iOS 16 gets the
    /// pass-style wallet.
    private static var walletIcon: String {
        if #available(iOS 17, *) { return "wallet.bifold" }
        return "wallet.pass"
    }

    var body: some View {
        TabView(selection: $selection) {
            ChessHomeView()
                .tabItem { Label("Play", systemImage: "checkerboard.rectangle") }
                .tag(Tab.play)
            ChessLeaderboardTabView()
                .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }
                .tag(Tab.leaderboard)
            ChessWalletView()
                .tabItem { Label("Wallet", systemImage: Self.walletIcon) }
                .tag(Tab.wallet)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .onAppear {
            // What KaChat's dock did on appearing: connect to the node pool and subscribe to
            // this address's coins (`ChatService.startPolling`; its chat phases are off, see
            // `syncsChats`). A hold left from onboarding is lifted first, or nothing would start.
            if chatService.onboardingSyncHeld {
                chatService.releaseSyncForOnboarding()
            }
            chatService.startPolling()
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
