import MetalKit
import UIKit
import simd

struct WorldVertex {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
    var materialUV: SIMD4<Float>
}
struct CameraUniform {
    var eye: SIMD4<Float>
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var forward: SIMD4<Float>
    var params: SIMD4<Float>
}

/// A tiny native Metal renderer: flat-shaded geometry, depth testing, and distance fog.
final class WorldRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let materials: MTLTexture
    private var staticBuffer: MTLBuffer?
    private var staticCount = 0
    private var doorState = ""
    private var vertices: [WorldVertex] = []
    private let indices = [0,1,2, 0,2,3]

    init(view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else {
            throw NSError(domain: "Afterlight", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal is unavailable on this device."])
        }
        self.device = device; self.queue = queue
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "worldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "worldFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = .less; d.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: d) else {
            throw NSError(domain: "Afterlight", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create depth state."])
        }
        self.depth = depth
        materials = try Self.loadMaterials(device: device, queue: queue)
        vertices.reserveCapacity(20000)
    }
    private static func loadMaterials(device: MTLDevice, queue: MTLCommandQueue) throws -> MTLTexture {
        let names = ["floor", "wall", "wood", "health-front"]
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 512, height: 512, mipmapped: true)
        desc.textureType = .type2DArray; desc.arrayLength = names.count+1
        desc.storageMode = .shared; desc.usage = .shaderRead
        guard let atlas = device.makeTexture(descriptor: desc) else {
            throw NSError(domain: "Afterlight", code: 3)
        }
        let white = [UInt8](repeating: 255, count: 512*512*4)
        white.withUnsafeBytes { atlas.replace(region: MTLRegionMake2D(0,0,512,512), mipmapLevel: 0, slice: 0, withBytes: $0.baseAddress!, bytesPerRow: 512*4, bytesPerImage: 512*512*4) }
        for (index,name) in names.enumerated() {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Imported"),
                  let image = UIImage(contentsOfFile: url.path)?.cgImage else {
                throw NSError(domain: "Afterlight", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing material: \(name)"])
            }
            guard image.width == 512 && image.height == 512 else { throw NSError(domain: "Afterlight", code: 5) }
            var pixels = [UInt8](repeating: 255,count: 512*512*4)
            let decoded = pixels.withUnsafeMutableBytes { bytes -> Bool in
                let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                guard let context = CGContext(data: bytes.baseAddress, width: 512, height: 512, bitsPerComponent: 8,
                                              bytesPerRow: 512*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags) else { return false }
                context.draw(image,in: CGRect(x: 0,y: 0,width: 512,height: 512))
                return true
            }
            guard decoded else { throw NSError(domain: "Afterlight", code: 6) }
            pixels.withUnsafeBytes { atlas.replace(region: MTLRegionMake2D(0,0,512,512), mipmapLevel: 0, slice: index+1, withBytes: $0.baseAddress!, bytesPerRow: 512*4, bytesPerImage: 512*512*4) }
        }
        // All fallible decoding is finished before opening an encoder.
        guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else { throw NSError(domain: "Afterlight", code: 7) }
        blit.generateMipmaps(for: atlas); blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        return atlas
    }
    private func box(_ center: SIMD3<Float>, _ size: SIMD3<Float>, _ color: SIMD3<Float>, material: Float = 0, frontOnly: Bool = false) {
        let lo = center-size/2, hi = center+size/2
        let p = [SIMD3(lo.x,lo.y,lo.z), SIMD3(hi.x,lo.y,lo.z), SIMD3(hi.x,hi.y,lo.z), SIMD3(lo.x,hi.y,lo.z),
                 SIMD3(lo.x,lo.y,hi.z), SIMD3(hi.x,lo.y,hi.z), SIMD3(hi.x,hi.y,hi.z), SIMD3(lo.x,hi.y,hi.z)]
        let faces = [[0,1,2,3],[5,4,7,6],[4,0,3,7],[1,5,6,2],[3,2,6,7],[4,5,1,0]]
        let shades: [Float] = [0.72,0.8,0.62,0.86,1,0.45]
        let uv: [SIMD2<Float>] = [SIMD2(0,1),SIMD2(1,1),SIMD2(1,0),SIMD2(0,0)]
        for f in 0..<6 {
            let c = color*shades[f]
            let layer = frontOnly && f > 1 ? 0 : material
            for i in indices { vertices.append(WorldVertex(position: SIMD4(p[faces[f][i]],1), color: SIMD4(c,1), materialUV: SIMD4(uv[i].x,uv[i].y,layer,0))) }
        }
    }
    private func rebuildWorld(_ game: Game) {
        vertices.removeAll(keepingCapacity: true)
        for z in 0..<Game.height {
            for x in 0..<Game.width {
                let px = Float(x)+0.5, pz = Float(z)+0.5
                let alternate: Float = (x+z)%2 == 0 ? 1 : 0.84
                let floor: SIMD3<Float> = x < 9 ? SIMD3(0.65,0.72,0.74) : (z < 8 ? SIMD3(0.74,0.73,0.64) : SIMD3(0.67,0.69,0.8))
                box(SIMD3(px,-0.08,pz), SIMD3(1,0.12,1), floor*alternate, material: 1)
                if game.isWall(x,z) {
                    let isDoor = game.doors.contains { $0.x == x && $0.z == z }
                    let color: SIMD3<Float> = isDoor ? SIMD3(0.8,0.64,0.42) : SIMD3(0.7,0.77,0.8)
                    box(SIMD3(px,1.5,pz), SIMD3(1,3,1), color, material: isDoor ? 3 : 2)
                    box(SIMD3(px,0.16,pz), SIMD3(1.015,0.12,1.015), SIMD3(0.11,0.14,0.15))
                    if isDoor {
                        for h in [Float(0.55),1.4,2.25] { box(SIMD3(px,h,pz), SIMD3(1.03,0.12,1.03), SIMD3(0.85,0.63,0.14)) }
                    }
                }
            }
        }
        for station in game.stations {
            let p = station.position
            switch station.kind {
            case .wall:
                box(SIMD3(p.x,0.55,p.z), SIMD3(0.75,1.1,0.3), SIMD3(0.08,0.25,0.28))
                box(SIMD3(p.x,1.16,p.z), SIMD3(0.9,0.07,0.45), SIMD3(0.2,0.95,0.88))
                box(SIMD3(p.x,0.84,p.z-0.2), SIMD3(0.6,0.12,0.12), SIMD3(0.72,0.93,0.89))
            case .box:
                box(SIMD3(p.x,0.35,p.z), SIMD3(1.2,0.7,0.7), SIMD3(0.7,0.55,0.35), material: 3)
                box(SIMD3(p.x,0.75,p.z), SIMD3(1.24,0.12,0.74), SIMD3(0.92,0.68,0.18))
            case .perk(let perk):
                let colors: [SIMD3<Float>] = [SIMD3(0.85,0.2,0.25),SIMD3(0.22,0.82,0.4),SIMD3(0.35,0.5,1)]
                if perk == .ironHeart {
                    box(SIMD3(p.x,0.8,p.z), SIMD3(0.65,1.6,0.65), SIMD3(0.9,0.9,0.9), material: 4, frontOnly: true)
                } else {
                    box(SIMD3(p.x,0.8,p.z), SIMD3(0.65,1.6,0.65), colors[perk.rawValue]*0.65)
                    box(SIMD3(p.x,1.35,p.z), SIMD3(0.69,0.3,0.69), colors[perk.rawValue])
                }
            }
        }
        for gate in game.barricades {
            let p = gate.position
            for dx in [Float(-0.55),0.55] { box(SIMD3(p.x+dx,1,p.z), SIMD3(0.12,2,0.15), SIMD3(0.18,0.15,0.13)) }
        }
        staticCount = vertices.count
        staticBuffer = vertices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
    func render(_ view: MTKView, game: Game, aiming: Bool) {
        let key = game.doors.map { $0.open ? "1" : "0" }.joined()
        if key != doorState || staticBuffer == nil { doorState = key; rebuildWorld(game) }
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let right = SIMD3<Float>(cos(game.yaw),0,sin(game.yaw))
        let forward = SIMD3<Float>(sin(game.yaw)*cos(game.pitch),sin(game.pitch),-cos(game.yaw)*cos(game.pitch))
        let up = simd_cross(right,forward)
        let eye = SIMD3<Float>(game.player.x,game.eyeHeight,game.player.z)
        var camera = CameraUniform(eye: SIMD4(eye,1),right: SIMD4(right,0),up: SIMD4(up,0),forward: SIMD4(forward,0),
                                   params: SIMD4(Float(view.drawableSize.width/max(1,view.drawableSize.height)), aiming ? 1.95 : 1.15,game.elapsed,0))
        encoder.setRenderPipelineState(pipeline); encoder.setDepthStencilState(depth); encoder.setCullMode(.none)
        encoder.setVertexBytes(&camera,length: MemoryLayout<CameraUniform>.stride,index: 1)
        encoder.setFragmentTexture(materials,index: 0)
        encoder.setVertexBuffer(staticBuffer,offset: 0,index: 0)
        encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: staticCount)
        vertices.removeAll(keepingCapacity: true)
        for gate in game.barricades {
            for n in 0..<gate.boards { box(SIMD3(gate.position.x,0.3+Float(n)*0.33,gate.position.z),SIMD3(1.15,0.18,0.12),SIMD3(0.8,0.65,0.45),material: 3) }
        }
        for zombie in game.zombies {
            let p = zombie.position
            let phase = game.elapsed*6+Float(zombie.id)
            let sway = sin(phase)*0.055
            let skin: SIMD3<Float> = zombie.flash > 0 ? SIMD3(1,0.7,0.3) : SIMD3(0.42,0.55,0.32)
            box(SIMD3(p.x,1.04,p.z),SIMD3(0.5,0.72,0.3),SIMD3(0.22,0.28,0.24))
            box(SIMD3(p.x+sway,1.58,p.z),SIMD3(0.36,0.4,0.35),skin)
            for side in [Float(-1),1] {
                box(SIMD3(p.x+side*0.15,0.37,p.z+side*sway),SIMD3(0.19,0.72,0.23),SIMD3(0.14,0.19,0.19))
                box(SIMD3(p.x+side*0.35,1.02+sway,p.z),SIMD3(0.16,0.62,0.2),skin)
                box(SIMD3(p.x+side*0.085,1.64,p.z-0.18),SIMD3(0.055,0.045,0.035),SIMD3(1,0.55,0.12))
            }
        }
        if game.boxTimer > 0 || game.boxReward != nil {
            let p = game.stations.first { $0.kind == .box }!.position
            box(SIMD3(p.x,1.25+sin(game.elapsed*4)*0.12,p.z),SIMD3(0.55,0.18,0.2),SIMD3(0.95,0.8,0.25))
        }
        // View model in camera space; the same Metal pipeline renders it without external assets.
        let begin = vertices.count
        let offset: Float = aiming ? 0 : 0.23
        let recoil = game.muzzle > 0 ? Float(0.05) : 0
        let drop = game.reloadTimer > 0 ? Float(0.2) : 0
        box(SIMD3(offset,-0.25-drop,0.48-recoil),SIMD3(0.12,0.14,0.35),SIMD3(0.25,0.28,0.3))
        box(SIMD3(offset,-0.34-drop,0.36-recoil),SIMD3(0.09,0.2,0.12),SIMD3(0.12,0.14,0.15))
        box(SIMD3(offset,-0.2-drop,0.72-recoil),SIMD3(0.065,0.065,0.2),SIMD3(0.12,0.15,0.17))
        if game.muzzle > 0 { box(SIMD3(offset,-0.2,0.86),SIMD3(0.16,0.16,0.12),SIMD3(1,0.8,0.2)) }
        for i in begin..<vertices.count {
            let p = vertices[i].position
            vertices[i].position = SIMD4(eye+right*p.x+up*p.y+forward*p.z,1)
        }
        if !vertices.isEmpty, let buffer = vertices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!,length: $0.count,options: .storageModeShared) }) {
            encoder.setVertexBuffer(buffer,offset: 0,index: 0)
            encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: vertices.count)
        }
        encoder.endEncoding(); command.present(drawable); command.commit()
    }
}
