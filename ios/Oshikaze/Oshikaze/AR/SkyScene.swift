import ARKit
import Combine
import CoreLocation
import RealityKit
import UIKit

/// AR の空に浮かべる風船
struct SkyTarget: Equatable {
    let id: Int
    let trackID: Int
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: SkyTarget, rhs: SkyTarget) -> Bool {
        lhs.id == rhs.id && lhs.trackID == rhs.trackID
    }
}

/// カメラ越しの空に、風船を実際の方角へ浮かべ、パチンコの弾との当たりを調べる。
///
/// ARKit の座標は `gravityAndHeading` で東西南北に合わせる（x が東、y が上、-z が北）。
/// 風船は数km以上離れているので、方角だけを合わせ、見かけ上の距離は20〜35mに縮めて置く。
/// 弾の軌道と当たり判定は、調整しやすいよう物理エンジンを使わずに毎フレーム計算する
@MainActor
final class SkyScene {
    /// 使うときに初めて作る。ARView は GPU の資源を多く確保するので、作り捨てると描画できなくなる
    private(set) lazy var arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

    /// 当たった風船のID
    var onHit: ((Int) -> Void)?
    /// 画面の中心で狙っている風船のID
    var onAim: ((Int?) -> Void)?

    private let root = AnchorEntity(world: .zero)
    private var balloons: [Int: BalloonNode] = [:]
    private var projectiles: [Projectile] = []
    private var fragments: [Fragment] = []
    private var updateSubscription: Cancellable?
    private var elapsed: Double = 0
    private var aimedID: Int?
    /// 今聴いている曲の風船。大きくして光の輪と ♪ を付ける
    private var playingID: Int?
    private lazy var highlight = Self.makeHighlight()

    private struct BalloonNode {
        let entity: Entity
        var basePosition: SIMD3<Float>
        let phase: Double
    }

    private struct Projectile {
        let entity: ModelEntity
        var velocity: SIMD3<Float>
        var age: Double
    }

    /// 割れた風船の花びらや、弾の軌跡のキラキラ。時間とともに小さくなって消える
    private struct Fragment {
        let entity: ModelEntity
        var velocity: SIMD3<Float>
        var age: Double
        var lifetime: Double = SkyScene.fragmentLifetime
    }

    private static let gravity = SIMD3<Float>(0, -9.8, 0)
    private static let balloonRadius: Float = 1.0
    /// 当たりの判定は見た目より少し大きくして、当てやすくする
    private static let hitRadius: Float = 1.5
    private static let projectileLifetime = 4.0
    private nonisolated static let fragmentLifetime = 1.4
    private nonisolated static let sparkleLifetime = 0.35
    private static let ammoColor = UIColor(red: 1.0, green: 0.61, blue: 0.79, alpha: 1)
    private static let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemMint,
                                            .systemTeal, .systemCyan, .systemBlue, .systemIndigo, .systemPurple, .systemPink]

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    func start() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        arView.scene.addAnchor(root)
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.update(deltaTime: event.deltaTime) }
        }
    }

    func stop() {
        updateSubscription?.cancel()
        updateSubscription = nil
        arView.session.pause()
    }

    // MARK: - 風船

    /// 浮かべる風船を入れ替える。近い順に並んでいる前提で、近いほど手前に置く
    func show(_ targets: [SkyTarget], from here: CLLocationCoordinate2D, playingID: Int?) {
        defer { markPlaying(playingID) }
        let ids = Set(targets.map(\.id))
        for (id, node) in balloons where !ids.contains(id) {
            node.entity.removeFromParent()
            balloons[id] = nil
        }
        for (rank, target) in targets.enumerated() {
            let position = Self.skyPosition(of: target.coordinate, from: here, rank: rank, count: targets.count)
            if var node = balloons[target.id] {
                node.basePosition = position
                balloons[target.id] = node
            } else {
                let entity = Self.makeBalloon(color: Self.colors[target.id % Self.colors.count])
                entity.position = position
                root.addChild(entity)
                balloons[target.id] = BalloonNode(entity: entity, basePosition: position, phase: Double(target.id))
            }
        }
    }

    /// 光の輪と ♪ を、今聴いている風船へ付け替える
    private func markPlaying(_ id: Int?) {
        playingID = id
        guard let id, let node = balloons[id] else {
            highlight.removeFromParent()
            return
        }
        if highlight.parent !== node.entity {
            node.entity.addChild(highlight)
        }
    }

    /// 風船を包む淡い光の輪と、上に浮かぶ ♪。♪ は常にこちらを向かせる
    private static func makeHighlight() -> Entity {
        let highlight = Entity()
        var glow = UnlitMaterial(color: .white)
        glow.blending = .transparent(opacity: 0.35)
        let halo = ModelEntity(mesh: .generateSphere(radius: balloonRadius * 1.45), materials: [glow])
        halo.scale = [1, 1.2, 1]
        let note = ModelEntity(mesh: .generateText("♪", extrusionDepth: 0.06, font: .systemFont(ofSize: 1.3, weight: .bold)),
                               materials: [UnlitMaterial(color: .white)])
        // 文字のメッシュは左下が原点なので、中心をそろえる
        let bounds = note.visualBounds(relativeTo: nil)
        note.position = [-bounds.center.x, -bounds.center.y, 0]
        let noteHolder = Entity()
        noteHolder.position = [0, balloonRadius * 2.2, 0]
        noteHolder.components.set(BillboardComponent())
        noteHolder.addChild(note)
        highlight.addChild(halo)
        highlight.addChild(noteHolder)
        return highlight
    }

    /// 今聴いている風船は1.5倍にしてゆっくり脈打たせ、当たりも同じだけ広げる
    private func scale(of id: Int) -> Float {
        guard id == playingID else { return 1 }
        return 1.5 + 0.08 * Float(sin(elapsed * 3))
    }

    /// 方角は実際のとおり、距離と高さは見やすさのために決める
    private static func skyPosition(of coordinate: CLLocationCoordinate2D, from here: CLLocationCoordinate2D,
                                    rank: Int, count: Int) -> SIMD3<Float> {
        let bearing = Geo.bearing(from: here, to: coordinate)
        let ratio = count > 1 ? Double(rank) / Double(count - 1) : 0
        let distance = 20 + 15 * ratio
        // 遠い風船ほど低く見せ、手前の風船と重なりにくくする
        let elevation = (40 - 20 * ratio) * .pi / 180
        let horizontal = distance * cos(elevation)
        return SIMD3<Float>(Float(horizontal * sin(bearing)), Float(distance * sin(elevation)), Float(-horizontal * cos(bearing)))
    }

    private static func makeBalloon(color: UIColor) -> Entity {
        let balloon = Entity()
        let body = ModelEntity(mesh: .generateSphere(radius: balloonRadius),
                               materials: [SimpleMaterial(color: color, roughness: 0.25, isMetallic: false)])
        body.scale = [1, 1.2, 1]
        let knot = ModelEntity(mesh: .generateSphere(radius: 0.12),
                               materials: [SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)])
        knot.position = [0, -balloonRadius * 1.2, 0]
        let string = ModelEntity(mesh: .generateBox(width: 0.02, height: 2.2, depth: 0.02),
                                 materials: [SimpleMaterial(color: .white, roughness: 1, isMetallic: false)])
        string.position = [0, -balloonRadius * 1.2 - 1.1, 0]
        balloon.addChild(body)
        balloon.addChild(knot)
        balloon.addChild(string)
        return balloon
    }

    // MARK: - パチンコ

    /// 引いた量（画面のポイント）から弾を撃つ。下へ引くほど上へ、左へ引くほど右へ、長く引くほど速く飛ぶ
    func fire(pull: CGSize) {
        let camera = arView.cameraTransform.matrix
        let right = SIMD3<Float>(camera.columns.0.x, camera.columns.0.y, camera.columns.0.z)
        let up = SIMD3<Float>(camera.columns.1.x, camera.columns.1.y, camera.columns.1.z)
        let forward = -SIMD3<Float>(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z)
        let origin = SIMD3<Float>(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)

        let length = min(Float(hypot(pull.width, pull.height)), 220)
        guard length > 20 else { return }
        let lift: Float = Float(pull.height) / 220 * 0.5
        let swing: Float = Float(pull.width) / 220 * 0.5
        let aim: SIMD3<Float> = forward + up * lift - right * swing
        let speed: Float = 14 + length / 220 * 22
        let velocity = simd_normalize(aim) * speed

        // 画面のパチンコの弾と同じ、つやのあるパステルピンク
        let stone = ModelEntity(mesh: .generateSphere(radius: 0.09),
                                materials: [SimpleMaterial(color: Self.ammoColor, roughness: 0.15, isMetallic: false)])
        stone.position = origin + forward * 0.4 - up * 0.15
        root.addChild(stone)
        projectiles.append(Projectile(entity: stone, velocity: velocity, age: 0))
    }

    // MARK: - 毎フレーム

    private func update(deltaTime: Double) {
        elapsed += deltaTime
        let dt = Float(deltaTime)

        // 風に揺れているように、ゆっくり上下させる
        for (id, node) in balloons {
            node.entity.position = node.basePosition + [0, Float(sin(elapsed * 0.8 + node.phase)) * 0.4, 0]
            node.entity.scale = SIMD3(repeating: scale(of: id))
        }

        for index in projectiles.indices.reversed() {
            projectiles[index].velocity += Self.gravity * dt
            projectiles[index].age += deltaTime
            let stone = projectiles[index].entity
            stone.position += projectiles[index].velocity * dt
            if let hit = balloons.first(where: { simd_distance($0.value.entity.position, stone.position) < Self.hitRadius * scale(of: $0.key) }) {
                stone.removeFromParent()
                projectiles.remove(at: index)
                burst(hit.key)
                continue
            }
            if projectiles[index].age > Self.projectileLifetime {
                stone.removeFromParent()
                projectiles.remove(at: index)
                continue
            }
            sparkle(at: stone.position)
        }

        for index in fragments.indices.reversed() {
            fragments[index].velocity += Self.gravity * 0.15 * dt
            fragments[index].age += deltaTime
            let fragment = fragments[index].entity
            fragment.position += fragments[index].velocity * dt
            let life = Float(1 - fragments[index].age / fragments[index].lifetime)
            fragment.scale = SIMD3(repeating: max(life, 0))
            if life <= 0 {
                fragment.removeFromParent()
                fragments.remove(at: index)
            }
        }

        updateAim()
    }

    /// 飛んでいる弾の後ろに、白とピンクの小さな光を残す
    private func sparkle(at position: SIMD3<Float>) {
        let color = Bool.random() ? UIColor.white : Self.ammoColor
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: 0.85)
        let dot = ModelEntity(mesh: .generateSphere(radius: Float.random(in: 0.025...0.05)), materials: [material])
        let jitter = SIMD3<Float>(Float.random(in: -0.04...0.04), Float.random(in: -0.04...0.04), Float.random(in: -0.04...0.04))
        dot.position = position + jitter
        root.addChild(dot)
        fragments.append(Fragment(entity: dot, velocity: .zero, age: 0, lifetime: Self.sparkleLifetime))
    }

    /// 割れた風船を、花びらのような小さなかけらにして散らす
    private func burst(_ id: Int) {
        guard let node = balloons.removeValue(forKey: id) else { return }
        let center = node.entity.position
        node.entity.removeFromParent()
        let color = Self.colors[id % Self.colors.count]
        for _ in 0..<28 {
            let petal = ModelEntity(mesh: .generateBox(width: 0.25, height: 0.04, depth: 0.18, cornerRadius: 0.02),
                                    materials: [SimpleMaterial(color: Bool.random() ? color : .white, roughness: 0.5, isMetallic: false)])
            petal.position = center
            let tilt = SIMD3<Float>(Float.random(in: -1...1), 1, Float.random(in: -1...1))
            petal.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: simd_normalize(tilt))
            let direction = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -0.3...1), Float.random(in: -1...1)))
            root.addChild(petal)
            fragments.append(Fragment(entity: petal, velocity: direction * Float.random(in: 3...7), age: 0))
        }
        onHit?(id)
    }

    /// 画面の中心に一番近い風船を「狙っている風船」として知らせる
    private func updateAim() {
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let aimed = balloons
            .compactMap { id, node -> (Int, CGFloat)? in
                guard let point = arView.project(node.entity.position) else { return nil }
                return (id, hypot(point.x - center.x, point.y - center.y))
            }
            .filter { $0.1 < 120 }
            .min { $0.1 < $1.1 }?.0
        guard aimed != aimedID else { return }
        aimedID = aimed
        onAim?(aimed)
    }
}
