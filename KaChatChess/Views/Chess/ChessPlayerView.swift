import SwiftUI

/// A player's card, opened by tapping a player on a leaderboard or a result: who they are
/// (avatar, .kachat or KNS name, address) and their record here, this month and all time.
/// KaChat opened its chat contact screen (`ChatInfoView`) for this; there are no chats here.
struct ChessPlayerView: View {
    let address: String

    @ObservedObject private var service = ChessTournamentService.shared
    @ObservedObject private var knsService = KNSService.shared
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var name: String { ContactsManager.shared.displayName(for: address) }

    private func row(_ period: ChessLeaderboardPeriod) -> ChessLeaderboardRow? {
        service.board(for: period).first { $0.address.lowercased() == address.lowercased() }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    KNSAvatarView(
                        avatarURLString: knsService.profileCache[address]?.avatarURL,
                        fallbackText: name,
                        size: 88,
                        contactAddress: address
                    )
                    Text(name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Address") {
                Button {
                    UIPasteboard.general.string = address
                    Haptics.success()
                    copied = true
                } label: {
                    HStack {
                        Text(address)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundColor(.accentColor)
                    }
                }
                if let url = settingsViewModel.settings.kaspaExplorer.addressURL(for: address) {
                    Link(destination: url) {
                        Label("View in Explorer", systemImage: "safari")
                    }
                }
            }

            ForEach([ChessLeaderboardPeriod.month, .allTime]) { period in
                Section(period == .month ? "This month" : "All time") {
                    let record = row(period)
                    recordLine("1v1 games", wins: record?.wins ?? 0, losses: record?.losses ?? 0)
                    recordLine("Tournaments", wins: record?.tournamentsWon ?? 0, losses: record?.tournamentsLost ?? 0)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task { _ = await knsService.fetchProfile(for: address) }
    }

    private func recordLine(_ title: LocalizedStringKey, wins: Int, losses: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(wins) W").foregroundColor(.green)
            Text("\(losses) L").foregroundColor(.red)
        }
        .font(.subheadline.monospacedDigit().weight(.semibold))
    }
}
