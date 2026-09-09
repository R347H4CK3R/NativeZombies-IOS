import UIKit

final class HUDView: UIView {
    weak var game: Game?
    var controllerConnected = false
    var onLook: ((CGFloat,CGFloat) -> Void)?
    var onAction: ((String) -> Void)?
    private enum Role { case move, look, button(String) }
    private struct Finger { var role: Role; var point: CGPoint }
    private var fingers: [ObjectIdentifier: Finger] = [:]
    private var stick = CGPoint.zero
    private var repeatUse: Float = 0
    var input: Input {
        Input(move: V2(Float(stick.x),-Float(stick.y)),fire: held("FIRE"),aim: held("AIM"),sprint: held("RUN"))
    }
    private var left: CGFloat { max(safeAreaInsets.left,22) }
    private var right: CGFloat { bounds.width-max(safeAreaInsets.right,22) }
    private var bottom: CGFloat { bounds.height-max(safeAreaInsets.bottom,15) }
    private var stickCenter: CGPoint { CGPoint(x: left+76,y: bottom-78) }
    private var controls: [(String,CGRect)] {
        [("FIRE",CGRect(x: right-96,y: bottom-163,width: 76,height: 76)),
         ("AIM",CGRect(x: right-182,y: bottom-115,width: 62,height: 62)),
         ("USE",CGRect(x: right-253,y: bottom-174,width: 58,height: 58)),
         ("RELOAD",CGRect(x: right-106,y: bottom-67,width: 76,height: 42)),
         ("SWAP",CGRect(x: right-187,y: bottom-47,width: 65,height: 35)),
         ("CROUCH",CGRect(x: right-263,y: bottom-47,width: 67,height: 35)),
         ("JUMP",CGRect(x: right-22,y: bottom-116,width: 42,height: 55)),
         ("RUN",CGRect(x: left+48,y: bottom-169,width: 58,height: 36)),
         ("PAUSE",CGRect(x: right-42,y: 64,width: 42,height: 30))]
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        isAccessibilityElement = false
        accessibilityElements = controls.map { name,frame in
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = name
            element.accessibilityTraits = .button
            element.accessibilityFrameInContainerSpace = frame
            return element
        }
    }
    private func held(_ name: String) -> Bool {
        fingers.values.contains { if case .button(let n) = $0.role { return n == name }; return false }
    }
    func clearInput() { fingers.removeAll(); stick = .zero; repeatUse = 0 }
    func advance(dt: Float) {
        if held("USE") { repeatUse -= dt; if repeatUse <= 0 { onAction?("USE"); repeatUse = 0.55 } }
    }
    override func touchesBegan(_ touches: Set<UITouch>,with event: UIEvent?) {
        guard game?.paused == false else { return }
        for touch in touches {
            let p = touch.location(in: self), id = ObjectIdentifier(touch)
            if let (name,_) = controls.first(where: { $0.1.insetBy(dx: -5,dy: -5).contains(p) }) {
                fingers[id] = Finger(role: .button(name),point: p)
                onAction?(name)
                if name == "USE" { repeatUse = 0.55 }
            } else if p.x < bounds.width*0.4 && p.y > bounds.height*0.4 && !fingers.values.contains(where: { if case .move = $0.role { return true }; return false }) {
                fingers[id] = Finger(role: .move,point: p); updateStick(p)
            } else { fingers[id] = Finger(role: .look,point: p) }
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>,with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch), p = touch.location(in: self)
            guard var finger = fingers[id] else { continue }
            switch finger.role {
            case .move: updateStick(p)
            case .look: onLook?(p.x-finger.point.x,p.y-finger.point.y)
            case .button(let name): if name == "FIRE" { onLook?(p.x-finger.point.x,p.y-finger.point.y) }
            }
            finger.point = p; fingers[id] = finger
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>,with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>,with event: UIEvent?) { end(touches) }
    private func end(_ touches: Set<UITouch>) {
        for touch in touches {
            if let finger = fingers.removeValue(forKey: ObjectIdentifier(touch)), case .move = finger.role { stick = .zero }
        }
    }
    private func updateStick(_ p: CGPoint) {
        let dx = (p.x-stickCenter.x)/48, dy = (p.y-stickCenter.y)/48, length = max(1,sqrt(dx*dx+dy*dy))
        stick = CGPoint(x: dx/length,y: dy/length)
    }
    private func text(_ value: String,_ rect: CGRect,size: CGFloat = 12,color: UIColor = .white,align: NSTextAlignment = .left,weight: UIFont.Weight = .bold) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align
        (value as NSString).draw(in: rect,withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: size,weight: weight),.foregroundColor: color,.paragraphStyle: paragraph])
    }
    override func draw(_ rect: CGRect) {
        guard let game, let ctx = UIGraphicsGetCurrentContext(), !game.paused else { return }
        let w = bounds.width, h = bounds.height
        UIColor(white: 0,alpha: 0.32).setFill(); UIBezierPath(roundedRect: CGRect(x: left,y: 16,width: 180,height: 63),cornerRadius: 8).fill()
        text("ROUND",CGRect(x: left+12,y: 24,width: 65,height: 16),size: 10,color: .systemMint)
        text(String(format: "%02d",game.round),CGRect(x: left+12,y: 39,width: 58,height: 35),size: 28)
        text("\(game.points) PTS",CGRect(x: left+76,y: 28,width: 110,height: 20),size: 16,color: .systemYellow)
        text("\(game.aliveCount) HOSTILES",CGRect(x: left+76,y: 52,width: 104,height: 18),size: 10,color: .lightGray)
        text("OUTPOST / NIGHT SHIFT",CGRect(x: w/2-140,y: 20,width: 280,height: 20),size: 10,color: UIColor(white: 0.7,alpha: 1),align: .center)
        text(game.weapon.spec.name,CGRect(x: right-220,y: 19,width: 220,height: 20),size: 12,color: .systemMint,align: .right)
        text(game.reloadTimer > 0 ? "RELOADING…" : "\(game.weapon.ammo) / \(game.weapon.reserve)",CGRect(x: right-220,y: 38,width: 220,height: 30),size: 22,align: .right)
        let hp = CGFloat(game.health/game.maxHealth)
        UIColor(white: 0.1,alpha: 0.7).setFill(); ctx.fill(CGRect(x: left,y: 86,width: 180,height: 5))
        (hp < 0.35 ? UIColor.systemRed : UIColor.systemMint).setFill(); ctx.fill(CGRect(x: left,y: 86,width: 180*hp,height: 5))
        text("\(Int(game.health)) HP",CGRect(x: left,y: 97,width: 80,height: 16),size: 10,color: .lightGray)
        let names = Perk.allCases.filter { game.perks.contains($0) }.map { $0.name }.joined(separator: " · ")
        text(names,CGRect(x: left,y: 117,width: 360,height: 18),size: 9,color: .systemMint)
        if game.messageTimer > 0 {
            text(game.message,CGRect(x: w/2-220,y: 67,width: 440,height: 30),size: 16,color: .systemYellow,align: .center)
        } else if game.remaining == 0 && game.zombies.isEmpty {
            text("NEXT ROUND IN \(max(0,Int(ceil(game.intermission))))",CGRect(x: w/2-170,y: 67,width: 340,height: 20),size: 13,color: .systemMint,align: .center)
        }
        if let item = game.nearestInteraction() {
            let panel = CGRect(x: w/2-185,y: h-73,width: 370,height: 35)
            UIColor(white: 0.02,alpha: 0.8).setFill(); UIBezierPath(roundedRect: panel,cornerRadius: 6).fill()
            text("USE / A  ·  \(game.prompt(item))",panel.insetBy(dx: 5,dy: 10),size: 10,color: .systemYellow,align: .center)
        }
        let center = CGPoint(x: w/2,y: h/2)
        ctx.setStrokeColor((game.hitMarker > 0 ? UIColor.systemRed : UIColor.white).cgColor); ctx.setLineWidth(1.5)
        if game.hitMarker > 0 {
            for side in [CGFloat(-1),1] { ctx.move(to: CGPoint(x: center.x-7,y: center.y+7*side)); ctx.addLine(to: CGPoint(x: center.x+7,y: center.y-7*side)) }
        } else {
            for side in [CGFloat(-1),1] {
                ctx.move(to: CGPoint(x: center.x+5*side,y: center.y)); ctx.addLine(to: CGPoint(x: center.x+11*side,y: center.y))
                ctx.move(to: CGPoint(x: center.x,y: center.y+5*side)); ctx.addLine(to: CGPoint(x: center.x,y: center.y+11*side))
            }
        }
        ctx.strokePath()
        if game.hurtTimer > 3.65 { UIColor(red: 0.8,green: 0.05,blue: 0.03,alpha: 0.18).setFill(); ctx.fill(bounds) }
        // Touch controls stay available even with a controller connected.
        for (name,frame) in controls {
            let active = held(name)
            (active ? UIColor.systemMint.withAlphaComponent(0.4) : UIColor(white: 0.04,alpha: 0.38)).setFill()
            let path = UIBezierPath(roundedRect: frame,cornerRadius: name == "FIRE" || name == "AIM" ? frame.width/2 : 9)
            path.fill(); UIColor(white: 0.9,alpha: 0.35).setStroke(); path.lineWidth = 1; path.stroke()
            text(name == "PAUSE" ? "II" : name,CGRect(x: frame.minX,y: frame.midY-6,width: frame.width,height: 16),size: name == "FIRE" ? 13 : 9,align: .center)
        }
        let base = CGRect(x: stickCenter.x-52,y: stickCenter.y-52,width: 104,height: 104)
        UIColor(white: 0.03,alpha: 0.3).setFill(); UIBezierPath(ovalIn: base).fill()
        UIColor(white: 1,alpha: 0.25).setStroke(); UIBezierPath(ovalIn: base).stroke()
        UIColor(white: 0.9,alpha: 0.32).setFill()
        UIBezierPath(ovalIn: CGRect(x: stickCenter.x+stick.x*40-20,y: stickCenter.y+stick.y*40-20,width: 40,height: 40)).fill()
        text(controllerConnected ? "CONTROLLER + TOUCH" : "DRAG RIGHT TO LOOK",CGRect(x: w/2-160,y: h-25,width: 320,height: 14),size: 8,color: .gray,align: .center)
    }
}
