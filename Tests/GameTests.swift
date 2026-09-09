import XCTest
@testable import SurvivalCore

final class GameTests: XCTestCase {
    private func live() -> Game { let g = Game(seed: 123); g.start(); g.rebuildPaths(); return g }
    func testPauseFreezesSimulation() {
        let g = Game(seed: 1), p = g.player
        g.tick(1,input: Input(move: V2(1,1),fire: true))
        XCTAssertEqual(g.player,p); XCTAssertEqual(g.weapon.ammo,12); XCTAssertEqual(g.round,0)
    }
    func testRoundStartsAndSpawnsOnlyReachableGates() {
        let g = live(); g.intermission = 0
        g.tick(0.05,input: Input()); XCTAssertEqual(g.round,1); XCTAssertEqual(g.remaining,8)
        for _ in 0..<100 { g.tick(0.05,input: Input()) }
        XCTAssertFalse(g.zombies.isEmpty)
        XCTAssertTrue(g.zombies.allSatisfy { $0.position.x < 9 })
    }
    func testMovementCannotTunnelThroughWalls() {
        let g = live()
        let p = g.move(V2(8.5,7.5),by: V2(20,0))
        XCTAssertLessThan(p.x,9); XCTAssertTrue(g.canStand(p))
    }
    func testDoorPurchaseChangesCollisionAndPathfinding() {
        let g = live(); g.player = V2(8.1,4.5); g.yaw = .pi/2; g.points = 750
        XCTAssertEqual(g.nearestInteraction(),.door(0)); XCTAssertTrue(g.isWall(9,4))
        g.interact()
        XCTAssertEqual(g.points,0); XCTAssertFalse(g.isWall(9,4)); XCTAssertTrue(g.reachable(V2(17.5,2.5)))
        XCTAssertFalse(g.reachable(V2(17.5,13.5)))
    }
    func testCannotPurchaseThroughWallOrWithoutPoints() {
        let g = live(); g.player = V2(8.1,4.5); g.yaw = .pi/2; g.points = 749
        g.interact(); XCTAssertEqual(g.points,749); XCTAssertFalse(g.doors[0].open)
        XCTAssertFalse(g.clearLine(V2(8.5,5.5),V2(10.5,5.5)))
    }
    func testReloadTransfersOnlyAvailableReserveAndPauseStopsTimer() {
        let g = live(); g.weapons[0].ammo = 3; g.weapons[0].reserve = 4; g.reload()
        g.paused = true; let before = g.reloadTimer; g.tick(0.05,input: Input()); XCTAssertEqual(g.reloadTimer,before)
        g.paused = false
        for _ in 0..<40 { g.tick(0.05,input: Input()) }
        XCTAssertEqual(g.weapon.ammo,7); XCTAssertEqual(g.weapon.reserve,0)
    }
    func testSwitchCancelsReloadWithoutCreatingAmmo() {
        let g = live(); g.equip(1); g.weapons[1].ammo = 2; g.reload(); g.swap()
        for _ in 0..<50 { g.tick(0.05,input: Input()) }
        XCTAssertEqual(g.weapons[1].ammo,2); XCTAssertEqual(g.weapons[0].ammo,12)
    }
    func testHitsAwardPointsAndKillsButWallsBlockShots() {
        let g = live(); g.player = V2(3.5,7.5)
        g.zombies = [Zombie(id: 1,position: V2(3.5,5.5),health: 30,gate: nil)]
        g.fire(); XCTAssertEqual(g.kills,1); XCTAssertGreaterThan(g.points,500); XCTAssertTrue(g.zombies.isEmpty)
        g.fireTimer = 0; g.player = V2(8.5,6.5); g.yaw = .pi/2
        g.zombies = [Zombie(id: 2,position: V2(10.5,6.5),health: 100,gate: nil)]
        g.fire(); XCTAssertEqual(g.zombies[0].health,100)
    }
    func testFireRateLimitsHeldTrigger() {
        let g = live(); g.fire(); g.fire(); XCTAssertEqual(g.weapon.ammo,11)
    }
    func testBoxChargesOnceThenOffersTimedClaim() {
        let g = live(); g.player = V2(12.5,4.5); g.points = 2000
        g.interact(); XCTAssertEqual(g.points,1050); XCTAssertEqual(g.boxTimer,3)
        g.interact(); XCTAssertEqual(g.points,1050)
        for _ in 0..<62 { g.tick(0.05,input: Input()) }
        XCTAssertNotNil(g.boxReward)
        let reward = g.boxReward!; g.interact()
        XCTAssertEqual(g.weapon.id,reward); XCTAssertNil(g.boxReward); XCTAssertEqual(g.points,1050)
    }
    func testBoxRewardExpires() {
        let g = live(); g.boxReward = 3; g.boxClaimTimer = 0.01
        g.tick(0.05,input: Input()); XCTAssertNil(g.boxReward)
    }
    func testPerkCannotBeBoughtTwice() {
        let g = live(); g.player = V2(17.5,6.5); g.points = 6000
        g.interact(); XCTAssertEqual(g.maxHealth,200); XCTAssertEqual(g.points,3500)
        g.interact(); XCTAssertEqual(g.points,3500)
    }
    func testWallWeaponAmmoAndTwoSlotLimit() {
        let g = live(); g.player = V2(2.5,6.5)
        g.interact(); XCTAssertEqual(g.weapon.id,1); XCTAssertEqual(g.points,0)
        g.equip(2); XCTAssertEqual(g.weapons.count,2); XCTAssertEqual(g.weapon.id,2)
    }
    func testBarricadeRepairRewardCap() {
        let g = live(); g.player = V2(1.5,3.5); g.barricades[0].boards = 3; g.barricades[0].rewards = 10
        g.interact(); XCTAssertEqual(g.barricades[0].boards,4); XCTAssertEqual(g.points,500)
    }
    func testZombieBreaksBarricadeBeforeAdvancing() {
        let g = live(); g.remaining = 1; g.spawnTimer = 999
        g.zombies = [Zombie(id: 1,position: g.barricades[0].position,health: 100,gate: 0)]
        let p = g.zombies[0].position
        g.tick(0.05,input: Input())
        XCTAssertEqual(g.barricades[0].boards,4); XCTAssertEqual(g.zombies[0].position,p)
    }
    func testDamageCooldownRegenerationAndDeath() {
        let g = live(); g.zombies = [Zombie(id: 1,position: g.player+V2(0.5,0),health: 100,gate: nil)]
        g.tick(0.05,input: Input()); XCTAssertEqual(g.health,70)
        g.tick(0.05,input: Input()); XCTAssertEqual(g.health,70)
        g.zombies = []; g.hurtTimer = 0; g.tick(0.05,input: Input()); XCTAssertGreaterThan(g.health,70)
        g.health = 20; g.zombies = [Zombie(id: 2,position: g.player+V2(0.5,0),health: 100,gate: nil)]
        g.tick(0.05,input: Input()); XCTAssertTrue(g.dead)
    }
}
