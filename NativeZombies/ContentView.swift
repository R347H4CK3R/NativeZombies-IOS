import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text("NATIVE ZOMBIES")
                    .font(.system(size: 36, weight: .black, design: .rounded))

                Text("PS3 asset-import ready prototype")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    StatRow(label: "Round", value: "\(game.round)")
                    StatRow(label: "Points", value: "\(game.points)")
                    StatRow(label: "Zombies", value: "\(game.zombiesRemaining)")
                    StatRow(label: "Weapon", value: game.currentWeapon.displayName)
                    StatRow(label: "Ammo", value: "\(game.currentAmmo)/\(game.reserveAmmo)")
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                HStack {
                    Button("Start Round") {
                        game.startNextRound()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Shoot") {
                        game.fire()
                    }
                    .buttonStyle(.bordered)
                    .disabled(game.zombiesRemaining == 0)
                }

                Button("Reload") {
                    game.reload()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("Original game assets are not bundled. Import user-owned PS3 assets separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
