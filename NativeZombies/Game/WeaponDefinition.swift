import Foundation

struct WeaponDefinition: Codable, Hashable {
    let id: String
    let displayName: String
    let magazineSize: Int
    let reserveAmmo: Int
    let damage: Int

    static let prototypeRifle = WeaponDefinition(
        id: "prototype_rifle",
        displayName: "Prototype Rifle",
        magazineSize: 30,
        reserveAmmo: 180,
        damage: 40
    )
}
