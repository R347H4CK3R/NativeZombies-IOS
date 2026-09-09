import Foundation

struct V2: Equatable {
    var x: Float
    var z: Float
    init(_ x: Float = 0, _ z: Float = 0) { self.x = x; self.z = z }
    static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.z + b.z) }
    static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.z - b.z) }
    static func * (a: V2, b: Float) -> V2 { V2(a.x * b, a.z * b) }
    var length: Float { sqrt(x*x + z*z) }
    var unit: V2 { length > 0.0001 ? self * (1 / length) : V2() }
    func dot(_ b: V2) -> Float { x*b.x + z*b.z }
}

struct WeaponSpec {
    let name: String
    let damage: Float
    let magazine: Int
    let reserve: Int
    let interval: Float
    let reload: Float
    let pellets: Int
    let spread: Float
    static let all: [WeaponSpec] = [
        .init(name: "SERVICE 9", damage: 38, magazine: 12, reserve: 96, interval: 0.24, reload: 1.5, pellets: 1, spread: 0.012),
        .init(name: "KITE SMG", damage: 32, magazine: 32, reserve: 256, interval: 0.085, reload: 2.0, pellets: 1, spread: 0.025),
        .init(name: "BREACH 12", damage: 28, magazine: 8, reserve: 64, interval: 0.8, reload: 2.5, pellets: 8, spread: 0.12),
        .init(name: "WARDEN AR", damage: 60, magazine: 30, reserve: 240, interval: 0.13, reload: 2.2, pellets: 1, spread: 0.017),
        .init(name: "ARC LANCE", damage: 220, magazine: 16, reserve: 128, interval: 0.32, reload: 2.8, pellets: 1, spread: 0.004)
    ]
}
struct Weapon {
    let id: Int
    var ammo: Int
    var reserve: Int
    init(_ id: Int) { self.id = id; ammo = WeaponSpec.all[id].magazine; reserve = WeaponSpec.all[id].reserve }
    var spec: WeaponSpec { WeaponSpec.all[id] }
}
enum Perk: Int, CaseIterable {
    case ironHeart, quickHands, fleetFoot
    var name: String { ["IRON HEART", "QUICK HANDS", "FLEET FOOT"][rawValue] }
    var cost: Int { [2500, 2000, 1500][rawValue] }
}
enum StationKind: Equatable { case wall(Int), box, perk(Perk) }
struct Station { let position: V2; let kind: StationKind }
struct Door { let x: Int; let z: Int; let cost: Int; var open = false; var position: V2 { V2(Float(x)+0.5, Float(z)+0.5) } }
struct Barricade { let position: V2; var boards = 5; var rewards = 0 }
struct Zombie {
    let id: Int
    var position: V2
    var health: Float
    var gate: Int?
    var attack: Float = 0
    var flash: Float = 0
}
enum Interaction: Equatable { case door(Int), station(Int), barricade(Int) }
struct Input {
    var move = V2()
    var fire = false
    var aim = false
    var sprint = false
}
enum GameEvent { case shot, hit, kill, hurt, purchase, repair, reload, round }

/// Platform-independent simulation. All mutations happen on the presentation thread.
final class Game {
    static let width = 20, height = 16
    var player = V2(4.5, 7.5)
    var yaw: Float = 0
    var pitch: Float = 0
    var health: Float = 100
    var points = 500
    var round = 0
    var kills = 0
    var weapons = [Weapon(0)]
    var slot = 0
    var perks = Set<Perk>()
    var doors = [Door(x: 9, z: 4, cost: 750), Door(x: 9, z: 11, cost: 1000), Door(x: 14, z: 8, cost: 1250)]
    let stations: [Station] = [
        .init(position: V2(2.5, 5.5), kind: .wall(1)),
        .init(position: V2(7.5, 10.5), kind: .wall(2)),
        .init(position: V2(12.5, 3.5), kind: .box),
        .init(position: V2(17.5, 5.5), kind: .perk(.ironHeart)),
        .init(position: V2(12.5, 12.5), kind: .perk(.quickHands)),
        .init(position: V2(17.5, 11.5), kind: .perk(.fleetFoot)),
        .init(position: V2(16.5, 13.5), kind: .wall(3))
    ]
    var barricades = [Barricade(position: V2(1.5, 2.5)), Barricade(position: V2(7.5, 13.5)), Barricade(position: V2(17.5, 2.5)), Barricade(position: V2(11.5, 13.5))]
    var zombies: [Zombie] = []
    var paused = true
    var started = false
    var dead = false
    var intermission: Float = 4
    var remaining = 0
    var spawnTimer: Float = 0
    var reloadTimer: Float = 0
    var fireTimer: Float = 0
    var hurtTimer: Float = 0
    var hitMarker: Float = 0
    var muzzle: Float = 0
    var elapsed: Float = 0
    var boxTimer: Float = 0
    var boxReward: Int?
    var boxClaimTimer: Float = 0
    var crouched = false
    var jumpHeight: Float = 0
    var jumpVelocity: Float = 0
    var message = "RESTORE NOTHING. SURVIVE EVERYTHING."
    var messageTimer: Float = 4
    var events: [GameEvent] = []
    private var nextID = 0
    private var repairTimer: Float = 0
    private var pathTimer: Float = 0
    private var distances = [Int](repeating: -1, count: Game.width * Game.height)
    private var randomState: UInt64
    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { randomState = seed }
    var weapon: Weapon { weapons[slot] }
    var maxHealth: Float { perks.contains(.ironHeart) ? 200 : 100 }
    var eyeHeight: Float { (crouched ? 1.05 : 1.6) + jumpHeight }
    var forward: V2 { V2(sin(yaw), -cos(yaw)) }
    var aliveCount: Int { zombies.count + remaining }
    func random() -> Float {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Float(randomState >> 40) / Float(1 << 24)
    }
    func notify(_ text: String) { message = text; messageTimer = 2.5 }
    func start() { started = true; paused = false }
    func turn(dx: Float, dy: Float) {
        guard !paused && !dead else { return }
        yaw += dx; pitch = min(1.1, max(-1.1, pitch + dy))
    }
    func isWall(_ x: Int, _ z: Int) -> Bool {
        if x <= 0 || z <= 0 || x >= Self.width-1 || z >= Self.height-1 { return true }
        if let door = doors.first(where: { $0.x == x && $0.z == z }) { return !door.open }
        if x == 9 || (z == 8 && x > 9) { return true }
        return [(4, 4), (5, 4), (4, 11), (13, 5), (16, 10)].contains { $0.0 == x && $0.1 == z }
    }
    func canStand(_ p: V2, radius: Float = 0.23) -> Bool {
        for x in [p.x-radius, p.x+radius] {
            for z in [p.z-radius, p.z+radius] { if isWall(Int(floor(x)), Int(floor(z))) { return false } }
        }
        return true
    }
    func move(_ p: V2, by d: V2, radius: Float = 0.23) -> V2 {
        var result = p
        let steps = max(1, Int(ceil(d.length / 0.15)))
        let step = d * (1 / Float(steps))
        for _ in 0..<steps {
            let x = V2(result.x+step.x, result.z)
            if canStand(x, radius: radius) { result = x }
            let z = V2(result.x, result.z+step.z)
            if canStand(z, radius: radius) { result = z }
        }
        return result
    }
    func clearLine(_ a: V2, _ b: V2) -> Bool {
        let d = b-a, steps = max(1, Int(ceil(d.length / 0.08)))
        for i in 1...steps {
            let p = a + d * (Float(i)/Float(steps))
            if isWall(Int(floor(p.x)), Int(floor(p.z))) { return false }
        }
        return true
    }
    func rebuildPaths() {
        distances = [Int](repeating: -1, count: Self.width * Self.height)
        let start = Int(player.z)*Self.width + Int(player.x)
        distances[start] = 0
        var queue = [start], cursor = 0
        while cursor < queue.count {
            let cell = queue[cursor]; cursor += 1
            let x = cell % Self.width, z = cell / Self.width
            for (nx, nz) in [(x+1,z),(x-1,z),(x,z+1),(x,z-1)] {
                if isWall(nx,nz) { continue }
                let index = nz*Self.width+nx
                if distances[index] == -1 { distances[index] = distances[cell]+1; queue.append(index) }
            }
        }
    }
    func reachable(_ p: V2) -> Bool { distances[Int(p.z)*Self.width+Int(p.x)] >= 0 }
    func nextTarget(_ p: V2) -> V2 {
        if clearLine(p, player) { return player }
        let x = Int(p.x), z = Int(p.z)
        var best = distances[z*Self.width+x], target = p
        for (nx,nz) in [(x+1,z),(x-1,z),(x,z+1),(x,z-1)] {
            if isWall(nx,nz) { continue }
            let d = distances[nz*Self.width+nx]
            if d >= 0 && (best < 0 || d < best) { best = d; target = V2(Float(nx)+0.5, Float(nz)+0.5) }
        }
        return target
    }
    func beginRound() {
        round += 1; remaining = 5 + round * 3; spawnTimer = 0
        for i in barricades.indices { barricades[i].rewards = 0 }
        notify("ROUND \(round)"); events.append(.round)
    }
    func tick(_ dt: Float, input: Input) {
        guard !paused && !dead else { return }
        let dt = min(max(dt, 0), 0.05)
        elapsed += dt
        messageTimer = max(0, messageTimer-dt); fireTimer = max(0, fireTimer-dt)
        hitMarker = max(0, hitMarker-dt); muzzle = max(0, muzzle-dt)
        hurtTimer = max(0, hurtTimer-dt); repairTimer = max(0, repairTimer-dt)
        if hurtTimer == 0 { health = min(maxHealth, health + dt*18) }
        if reloadTimer > 0 {
            reloadTimer = max(0, reloadTimer-dt)
            if reloadTimer == 0 {
                let count = min(weapon.spec.magazine-weapon.ammo, weapon.reserve)
                weapons[slot].ammo += count; weapons[slot].reserve -= count
            }
        }
        if jumpHeight > 0 || jumpVelocity > 0 {
            jumpVelocity -= dt*12; jumpHeight = max(0, jumpHeight+jumpVelocity*dt)
            if jumpHeight == 0 { jumpVelocity = 0 }
        }
        let movement = input.move.length > 1 ? input.move.unit : input.move
        var speed: Float = crouched ? 1.6 : (input.sprint && !input.fire && !input.aim ? 4.2 : 2.8)
        if perks.contains(.fleetFoot) { speed *= 1.25 }
        if input.aim { speed *= 0.65 }
        let right = V2(cos(yaw), sin(yaw))
        player = move(player, by: (right*movement.x + forward*movement.z) * (dt*speed))
        pathTimer -= dt
        if pathTimer <= 0 { rebuildPaths(); pathTimer = 0.35 }
        if boxTimer > 0 {
            boxTimer = max(0, boxTimer-dt)
            if boxTimer == 0 { boxReward = 1 + Int(random()*4); boxClaimTimer = 12; notify("CACHE READY — RETURN TO CLAIM") }
        } else if boxClaimTimer > 0 {
            boxClaimTimer = max(0, boxClaimTimer-dt)
            if boxClaimTimer == 0 { boxReward = nil }
        }
        if remaining == 0 && zombies.isEmpty {
            intermission -= dt
            if intermission <= 0 { beginRound() }
        } else {
            spawnTimer -= dt
            if remaining > 0 && zombies.count < 24 && spawnTimer <= 0 {
                let gates = barricades.indices.filter { reachable(barricades[$0].position) }
                if !gates.isEmpty {
                    let gate = gates[min(gates.count-1, Int(random()*Float(gates.count)))]
                    nextID += 1
                    zombies.append(Zombie(id: nextID, position: barricades[gate].position, health: 80 * pow(1.13, Float(round-1)), gate: gate))
                    remaining -= 1; spawnTimer = max(0.45, 2.2-Float(round)*0.1)
                }
            }
        }
        for i in zombies.indices {
            zombies[i].attack = max(0, zombies[i].attack-dt)
            zombies[i].flash = max(0, zombies[i].flash-dt)
            if let gate = zombies[i].gate {
                if barricades[gate].boards > 0 {
                    if zombies[i].attack == 0 { barricades[gate].boards -= 1; zombies[i].attack = 1.2 }
                    continue
                }
                zombies[i].gate = nil
            }
            let delta = player-zombies[i].position
            if delta.length < 0.78 && clearLine(zombies[i].position, player) {
                if zombies[i].attack == 0 {
                    health = max(0, health-30); hurtTimer = 4; zombies[i].attack = 1
                    events.append(.hurt)
                    if health <= 0 { dead = true; notify("OUTPOST OVERRUN"); break }
                }
            } else {
                let direction = (nextTarget(zombies[i].position)-zombies[i].position).unit
                let speed = min(2.45, 0.7 + Float(round)*0.105)
                zombies[i].position = move(zombies[i].position, by: direction*(dt*speed), radius: 0.18)
            }
        }
        if input.fire && !dead { fire(aimed: input.aim) }
    }
    func reload() {
        guard !paused && !dead && reloadTimer == 0 && weapon.ammo < weapon.spec.magazine && weapon.reserve > 0 else { return }
        reloadTimer = weapon.spec.reload * (perks.contains(.quickHands) ? 0.55 : 1)
        events.append(.reload)
    }
    func swap() { guard !paused && !dead else { return }; reloadTimer = 0; slot = (slot+1)%weapons.count }
    func jump() { if !paused && !dead && jumpHeight == 0 { jumpVelocity = 4.2; crouched = false } }
    func fire(aimed: Bool = false) {
        guard !paused && !dead && fireTimer == 0 && reloadTimer == 0 else { return }
        guard weapon.ammo > 0 else { reload(); return }
        let spec = weapon.spec
        weapons[slot].ammo -= 1; fireTimer = spec.interval; muzzle = 0.07; events.append(.shot)
        for _ in 0..<spec.pellets {
            let spread = spec.spread * (aimed ? 0.35 : 1)
            let angle = yaw + (random()-0.5)*spread
            let vertical = pitch + (random()-0.5)*spread
            let ray = V2(sin(angle), -cos(angle))
            var target: Int?, nearest: Float = 40, headshot = false
            for i in zombies.indices where zombies[i].health > 0 {
                let d = zombies[i].position-player, along = d.dot(ray)
                if along <= 0 || along >= nearest { continue }
                let side = abs(d.x*ray.z-d.z*ray.x)
                let height = eyeHeight + tan(vertical)*along
                if side < 0.33 && height > 0.12 && height < 1.85 && clearLine(player, zombies[i].position) {
                    nearest = along; target = i; headshot = height > 1.4
                }
            }
            if let i = target {
                zombies[i].health -= spec.damage * (headshot ? 2.2 : 1)
                zombies[i].flash = 0.1; hitMarker = 0.13; points += 10; events.append(.hit)
                if zombies[i].health <= 0 { points += headshot ? 100 : 60; kills += 1; events.append(.kill) }
            }
        }
        zombies.removeAll { $0.health <= 0 }
        if remaining == 0 && zombies.isEmpty { intermission = 8 }
    }
    func equip(_ id: Int) {
        reloadTimer = 0
        if let existing = weapons.firstIndex(where: { $0.id == id }) { weapons[existing] = Weapon(id); slot = existing }
        else if weapons.count < 2 { weapons.append(Weapon(id)); slot = weapons.count-1 }
        else { weapons[slot] = Weapon(id) }
    }
    func nearestInteraction() -> Interaction? {
        var best: Float = 1.85, result: Interaction?
        func consider(_ p: V2, _ item: Interaction, door: Bool = false) {
            let delta = p-player, d = delta.length
            // Closed door centers are solid, so test visibility up to the near face.
            let endpoint = door && d > 0.6 ? p-delta.unit*0.6 : p
            if d < best && (d < 0.65 || delta.unit.dot(forward) > 0.35) && clearLine(player, endpoint) { best = d; result = item }
        }
        for i in doors.indices where !doors[i].open { consider(doors[i].position, .door(i), door: true) }
        for i in stations.indices { consider(stations[i].position, .station(i)) }
        for i in barricades.indices where barricades[i].boards < 5 { consider(barricades[i].position, .barricade(i)) }
        return result
    }
    func prompt(_ item: Interaction) -> String {
        switch item {
        case .door(let i): return "OPEN DOOR · \(doors[i].cost)"
        case .barricade(let i): return "REPAIR · \(barricades[i].boards)/5 BOARDS"
        case .station(let i):
            switch stations[i].kind {
            case .wall(let id):
                let owned = weapons.contains { $0.id == id }
                return "\(WeaponSpec.all[id].name) \(owned ? "AMMO" : "") · \(owned ? 350 : wallCost(id))"
            case .box:
                if boxTimer > 0 { return "SUPPLY CACHE · ROLLING…" }
                if let reward = boxReward { return "CLAIM \(WeaponSpec.all[reward].name) · \(Int(ceil(boxClaimTimer)))s" }
                return "RANDOM SUPPLY CACHE · 950"
            case .perk(let perk): return perks.contains(perk) ? "\(perk.name) · ACTIVE" : "\(perk.name) · \(perk.cost)"
            }
        }
    }
    func wallCost(_ id: Int) -> Int { [0, 500, 750, 1500, 0][id] }
    func spend(_ cost: Int) -> Bool {
        guard points >= cost else { notify("NEED \(cost-points) MORE POINTS"); return false }
        points -= cost; events.append(.purchase); return true
    }
    func interact() {
        guard !paused && !dead, let item = nearestInteraction() else { return }
        switch item {
        case .door(let i):
            if spend(doors[i].cost) { doors[i].open = true; rebuildPaths(); notify("AREA UNLOCKED") }
        case .barricade(let i):
            if repairTimer == 0 && barricades[i].boards < 5 {
                barricades[i].boards += 1; repairTimer = 0.5; events.append(.repair)
                if barricades[i].rewards < 10 { points += 10; barricades[i].rewards += 1 }
            }
        case .station(let i):
            switch stations[i].kind {
            case .wall(let id):
                if let owned = weapons.firstIndex(where: { $0.id == id }) {
                    if weapons[owned].reserve == weapons[owned].spec.reserve { notify("AMMO FULL"); return }
                    if spend(350) { weapons[owned].reserve = weapons[owned].spec.reserve; notify("AMMO REPLENISHED") }
                } else if spend(wallCost(id)) { equip(id); notify("\(weapon.spec.name) EQUIPPED") }
            case .box:
                if boxTimer > 0 { return }
                if let reward = boxReward { equip(reward); boxReward = nil; boxClaimTimer = 0; notify("\(weapon.spec.name) EQUIPPED") }
                else if spend(950) { boxTimer = 3; notify("SUPPLY CACHE ROLLING…") }
            case .perk(let perk):
                if !perks.contains(perk) && spend(perk.cost) { perks.insert(perk); if perk == .ironHeart { health = maxHealth }; notify("\(perk.name) ACTIVE") }
            }
        }
    }
}

