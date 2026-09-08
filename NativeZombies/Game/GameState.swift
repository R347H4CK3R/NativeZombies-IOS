import Foundation

@MainActor
final class GameState: ObservableObject {
    @Published private(set) var round = 0
    @Published private(set) var points = 500
    @Published private(set) var zombiesRemaining = 0
    @Published private(set) var currentWeapon = WeaponDefinition.prototypeRifle
    @Published private(set) var currentAmmo = WeaponDefinition.prototypeRifle.magazineSize
    @Published private(set) var reserveAmmo = WeaponDefinition.prototypeRifle.reserveAmmo

    func startNextRound() {
        guard zombiesRemaining == 0 else { return }
        round += 1
        zombiesRemaining = RoundRules.zombieCount(for: round)
    }

    func fire() {
        guard zombiesRemaining > 0, currentAmmo > 0 else { return }
        currentAmmo -= 1

        // Prototype combat loop. Asset-driven health/damage replaces this later.
        zombiesRemaining -= 1
        points += 100
    }

    func reload() {
        let needed = currentWeapon.magazineSize - currentAmmo
        guard needed > 0, reserveAmmo > 0 else { return }

        let moved = min(needed, reserveAmmo)
        currentAmmo += moved
        reserveAmmo -= moved
    }
}

enum RoundRules {
    static func zombieCount(for round: Int) -> Int {
        max(6, 4 + round * 2)
    }
}
