import UIKit
import MetalKit
import GameController

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible(); self.window = window
        return true
    }
}

final class GameViewController: UIViewController, MTKViewDelegate {
    private var game = Game()
    private var metalView: MTKView!
    private var renderer: WorldRenderer?
    private let hud = HUDView()
    private let menu = UIView()
    private let heading = UILabel()
    private let subtitle = UILabel()
    private let startButton = UIButton(type: .system)
    private let sound = GameAudio()
    private var previousTime: CFTimeInterval = 0
    private var controllerButtons = Set<String>()
    private var sensitivity: Float = 0.004
    private var aiming = false
    private var recordedDeath = false
    private var highScore = UserDefaults.standard.integer(forKey: "bestRound")
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metalView = MTKView(frame: view.bounds,device: MTLCreateSystemDefaultDevice())
        metalView.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.clearColor = MTLClearColor(red: 0.026,green: 0.038,blue: 0.053,alpha: 1)
        metalView.preferredFramesPerSecond = 60
        view.addSubview(metalView)
        do { renderer = try WorldRenderer(view: metalView) }
        catch {
            let label = UILabel(frame: view.bounds); label.text = error.localizedDescription
            label.textColor = .white; label.textAlignment = .center; view.addSubview(label); return
        }
        hud.frame = view.bounds; hud.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        hud.backgroundColor = .clear; hud.isMultipleTouchEnabled = true
        hud.onLook = { [weak self] dx,dy in
            guard let self else { return }
            self.game.turn(dx: Float(dx)*self.sensitivity*(self.aiming ? 0.6 : 1),dy: -Float(dy)*self.sensitivity*(self.aiming ? 0.6 : 1))
        }
        hud.onAction = { [weak self] in self?.action($0) }
        view.addSubview(hud)
        configureMenu()
        metalView.delegate = self
        NotificationCenter.default.addObserver(self,selector: #selector(background),name: UIApplication.willResignActiveNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(controllerLost),name: .GCControllerDidDisconnect,object: nil)
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        showMenu()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Cap internal resolution for sustained thermal performance on iPhone.
        let scale = min(UIScreen.main.scale,1.5)
        metalView.drawableSize = CGSize(width: view.bounds.width*scale,height: view.bounds.height*scale)
        menu.frame = view.bounds
    }
    private func configureMenu() {
        menu.backgroundColor = UIColor(red: 0.025,green: 0.04,blue: 0.055,alpha: 0.94)
        view.addSubview(menu)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false; menu.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: menu.safeAreaLayoutGuide.centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: menu.safeAreaLayoutGuide.centerYAnchor),
                                     stack.widthAnchor.constraint(lessThanOrEqualTo: menu.safeAreaLayoutGuide.widthAnchor,multiplier: 0.9)])
        let eyebrow = UILabel(); eyebrow.text = "A F T E R L I G H T   /   O U T P O S T"; eyebrow.textColor = .systemMint
        eyebrow.font = .systemFont(ofSize: 12,weight: .bold); stack.addArrangedSubview(eyebrow)
        heading.font = .systemFont(ofSize: 38,weight: .black); heading.textColor = .white; stack.addArrangedSubview(heading)
        subtitle.font = .monospacedSystemFont(ofSize: 12,weight: .medium); subtitle.textColor = .lightGray
        subtitle.numberOfLines = 0; subtitle.textAlignment = .center; stack.addArrangedSubview(subtitle)
        startButton.setTitle("ENTER OUTPOST",for: .normal); style(startButton)
        startButton.addTarget(self,action: #selector(resume),for: .touchUpInside); stack.addArrangedSubview(startButton)
        let options = UIStackView(); options.axis = .horizontal; options.spacing = 20
        for (title,selector) in [("NEW RUN",#selector(restart)),("LOOK: NORMAL",#selector(changeSensitivity)),("SOUND: ON",#selector(toggleSound))] {
            let b = UIButton(type: .system); b.setTitle(title,for: .normal); b.tintColor = .lightGray
            b.titleLabel?.font = .systemFont(ofSize: 11,weight: .bold); b.addTarget(self,action: selector,for: .touchUpInside); options.addArrangedSubview(b)
        }
        stack.addArrangedSubview(options)
        let help = UILabel(); help.numberOfLines = 0; help.textAlignment = .center
        help.font = .systemFont(ofSize: 11); help.textColor = .gray
        help.text = "TOUCH: left stick moves · drag right to look · hold FIRE / AIM\nCONTROLLER: sticks · RT fire · LT aim · X reload · A use · Y swap\nLB sprint · B crouch · RB jump · Menu pause"
        stack.addArrangedSubview(help)
    }
    private func style(_ button: UIButton) {
        button.backgroundColor = .systemMint; button.tintColor = UIColor(white: 0.06,alpha: 1)
        button.titleLabel?.font = .systemFont(ofSize: 15,weight: .heavy); button.layer.cornerRadius = 8
        button.widthAnchor.constraint(equalToConstant: 260).isActive = true
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
    private func showMenu() {
        sound.pause()
        hud.clearInput(); game.paused = true; menu.isHidden = false
        heading.text = game.dead ? "OUTPOST OVERRUN" : (game.started ? "HOLD YOUR GROUND" : "THE LAST SHIFT")
        subtitle.text = game.dead ? "ROUND \(game.round)  /  \(game.kills) ELIMINATED  /  BEST \(highScore)" : "Survive the rounds. Buy your way deeper.\nTeal: weapons · Gold: doors & supply cache · Color: perks"
        startButton.setTitle(game.dead ? "TRY AGAIN" : (game.started ? "RESUME" : "ENTER OUTPOST"),for: .normal)
    }
    @objc private func resume() {
        if game.dead { sound.stop(); game = Game(); recordedDeath = false }
        game.start(); hud.clearInput(); menu.isHidden = true; previousTime = CACurrentMediaTime()
        sound.resume()
    }
    @objc private func restart() { sound.stop(); game = Game(); recordedDeath = false; resume() }
    @objc private func background() { if renderer != nil { showMenu() } }
    @objc private func controllerLost() { controllerButtons.removeAll(); showMenu() }
    @objc private func changeSensitivity(_ sender: UIButton) {
        sensitivity = sensitivity == 0.004 ? 0.006 : (sensitivity == 0.006 ? 0.0025 : 0.004)
        sender.setTitle(sensitivity == 0.004 ? "LOOK: NORMAL" : (sensitivity == 0.006 ? "LOOK: FAST" : "LOOK: SLOW"),for: .normal)
    }
    @objc private func toggleSound(_ sender: UIButton) { sound.enabled.toggle(); sender.setTitle(sound.enabled ? "SOUND: ON" : "SOUND: OFF",for: .normal) }
    private func action(_ name: String) {
        switch name {
        case "PAUSE": showMenu()
        case "RELOAD": game.reload()
        case "USE": game.interact()
        case "SWAP": game.swap()
        case "CROUCH": if !game.paused && !game.dead { game.crouched.toggle() }
        case "JUMP": game.jump()
        default: break
        }
    }
    private func controllerInput(dt: Float) -> Input? {
        guard let pad = GCController.controllers().first?.extendedGamepad else { controllerButtons.removeAll(); return nil }
        var pressed = Set<String>()
        for (name,button) in [("RELOAD",pad.buttonX),("USE",pad.buttonA),("SWAP",pad.buttonY),("CROUCH",pad.buttonB),("JUMP",pad.rightShoulder),("PAUSE",pad.buttonMenu)] {
            if button.isPressed { pressed.insert(name) }
        }
        for name in pressed.subtracting(controllerButtons) {
            if game.paused && (name == "PAUSE" || name == "USE") { resume() }
            else { action(name) }
        }
        controllerButtons = pressed
        func axis(_ value: Float) -> Float { abs(value) < 0.14 ? 0 : (value > 0 ? 1 : -1)*(abs(value)-0.14)/0.86 }
        let aim = pad.leftTrigger.value > 0.2
        game.turn(dx: axis(pad.rightThumbstick.xAxis.value)*dt*(aim ? 1.4 : 2.6),dy: axis(pad.rightThumbstick.yAxis.value)*dt*(aim ? 1.1 : 2))
        return Input(move: V2(axis(pad.leftThumbstick.xAxis.value),axis(pad.leftThumbstick.yAxis.value)),fire: pad.rightTrigger.value > 0.2,aim: aim,sprint: pad.leftShoulder.isPressed)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime(), dt = Float(previousTime == 0 ? 1/60.0 : min(now-previousTime,0.05)); previousTime = now
        var input = hud.input
        if let controller = controllerInput(dt: dt) {
            if controller.move.length > 0 { input.move = controller.move }
            input.fire = input.fire || controller.fire; input.aim = input.aim || controller.aim; input.sprint = input.sprint || controller.sprint
        }
        aiming = input.aim
        hud.advance(dt: dt)
        game.tick(dt,input: input)
        if !game.paused && !game.dead { sound.play(game.events) }
        game.events.removeAll(keepingCapacity: true)
        if game.dead && !recordedDeath {
            recordedDeath = true; highScore = max(highScore,game.round)
            UserDefaults.standard.set(highScore,forKey: "bestRound"); showMenu()
        }
        hud.game = game; hud.controllerConnected = !GCController.controllers().isEmpty; hud.setNeedsDisplay()
        renderer?.render(view,game: game,aiming: aiming)
    }
}
