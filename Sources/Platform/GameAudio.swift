import AVFoundation

/// Original synthesized effects. No external audio or game files are needed.
final class GameAudio {
    var enabled = true
    private var voices: [String:[AVAudioPlayer]] = [:]
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient,mode: .default)
        for (name,hz,duration,noise) in [("shot",90.0,0.10,0.8),("hit",700.0,0.045,0.2),("hurt",65.0,0.22,0.4),
                                         ("buy",660.0,0.16,0.0),("repair",180.0,0.08,0.6),("reload",260.0,0.08,0.5),("round",220.0,0.5,0.05)] {
            let data = Self.wave(hz: hz,duration: duration,noise: noise)
            voices[name] = (0..<3).compactMap { _ in
                guard let p = try? AVAudioPlayer(data: data) else { return nil }
                p.volume = name == "shot" ? 0.3 : 0.2; p.prepareToPlay(); return p
            }
        }
    }
    func play(_ events: [GameEvent]) {
        guard enabled else { return }
        var played = Set<String>()
        for event in events {
            let key: String
            switch event {
            case .shot: key = "shot"
            case .hit, .kill: key = "hit"
            case .hurt: key = "hurt"
            case .purchase: key = "buy"
            case .repair: key = "repair"
            case .reload: key = "reload"
            case .round: key = "round"
            }
            if !played.insert(key).inserted { continue }
            guard let pool = voices[key], let player = pool.first(where: { !$0.isPlaying }) ?? pool.first else { continue }
            player.currentTime = 0; player.play()
        }
    }
    private static func wave(hz: Double,duration: Double,noise: Double) -> Data {
        let rate = 22050, count = Int(Double(rate)*duration)
        var result = Data()
        func ascii(_ s: String) { result.append(contentsOf: s.utf8) }
        func u16(_ n: UInt16) { var n = n.littleEndian; withUnsafeBytes(of: &n) { result.append(contentsOf: $0) } }
        func u32(_ n: UInt32) { var n = n.littleEndian; withUnsafeBytes(of: &n) { result.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36+count*2)); ascii("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate*2)); u16(2); u16(16); ascii("data"); u32(UInt32(count*2))
        var seed: UInt32 = 42
        for i in 0..<count {
            seed = seed &* 1664525 &+ 1013904223
            let t = Double(i)/Double(rate), envelope = pow(1-Double(i)/Double(count),2)
            let n = Double(seed & 65535)/32767.5-1
            let tone = sin(2 * Double.pi * hz * t * (1-0.25*t/duration))
            let value = Int16(max(-32767,min(32767,(tone*(1-noise)+n*noise)*envelope*20000)))
            u16(UInt16(bitPattern: value))
        }
        return result
    }
}
