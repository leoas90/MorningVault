import SwiftUI

// MARK: - Sky scene
//
// The Brief's signature object: a full-bleed sky drawn in SwiftUI (no assets), keyed to the
// local hour and the weather condition. Static by design — no TimelineView; the only motion
// is the one-shot entrance in the Brief and the breathing status dot.

/// Coarse weather bucket derived from the condition text.
enum SkyWeather: Equatable {
    case clear, partlyCloudy, cloudy, rain, storm, snow, fog

    static func from(condition: String?) -> SkyWeather {
        guard let c = condition?.lowercased() else { return .clear }
        if c.contains("thunder") || c.contains("storm") { return .storm }
        if c.contains("snow") || c.contains("sleet") || c.contains("flurr") || c.contains("blizzard") { return .snow }
        if c.contains("rain") || c.contains("drizzle") || c.contains("shower") { return .rain }
        if c.contains("fog") || c.contains("mist") || c.contains("haze") || c.contains("smoke") { return .fog }
        if c.contains("partly") || c.contains("mostly clear") || c.contains("few clouds") || c.contains("mostly sunny") { return .partlyCloudy }
        if c.contains("cloud") || c.contains("overcast") { return .cloudy }
        return .clear
    }

    var hasSun: Bool { self == .clear || self == .partlyCloudy }
    var cloudCount: Int {
        switch self {
        case .clear: return 0
        case .partlyCloudy: return 1
        case .cloudy, .rain, .storm, .snow: return 2
        case .fog: return 0
        }
    }
}

/// Time-of-day bucket.
enum SkyPhase: Equatable {
    case night, dawn, day, dusk

    init(hour: Int) {
        switch hour {
        case 5..<8: self = .dawn
        case 8..<17: self = .day
        case 17..<20: self = .dusk
        default: self = .night
        }
    }
}

/// Everything the scene needs, resolved once per (hour, condition, scheme).
struct SkyStyle: Equatable {
    var phase: SkyPhase
    var weather: SkyWeather
    var gradient: [Color]
    /// White text on dark skies; ink on the luminous light-mode skies.
    var usesLightText: Bool
    /// Colour the rest of the page can borrow (4 % tint on dark surfaces).
    var tint: Color
    var sunColor: Color
    /// Halo colour around the disc (warmer / more saturated than the disc itself).
    var glowColor: Color
    /// Unit coordinates (0…1) inside the scene.
    var sunPosition: CGPoint
    var showsSun: Bool
    var showsMoon: Bool
    var cloudLit: Color
    var cloudBase: Color
    var cloudShadow: Color
    var cloudOpacity: Double
    var sunGlowOpacity: Double

    static func resolve(hour: Int, condition: String?, colorScheme: ColorScheme) -> SkyStyle {
        let phase = SkyPhase(hour: hour)
        let weather = SkyWeather.from(condition: condition)
        let dark = colorScheme == .dark

        // Art-directed base skies. Light = luminous paper / apricot / pale blue;
        // dark = deep indigo to near-black with one warm source only at dawn/dusk.
        var gradient: [Color]
        var light: Bool
        var sun: Color
        var halo: Color
        var sunPos: CGPoint
        var glow: Double
        switch (phase, dark) {
        case (.dawn, false):
            gradient = [Color(hex: "C7C2DA"), Color(hex: "F1C2A0"), Color(hex: "F7E0C2")]
            light = false; sun = Color(hex: "FFF4DC"); halo = Color(hex: "FFA74A"); sunPos = CGPoint(x: 0.78, y: 0.56); glow = 0.75
        case (.day, false):
            gradient = [Color(hex: "A9CBEA"), Color(hex: "CFE2F1"), Color(hex: "EEEDE6")]
            light = false; sun = Color(hex: "FFFBEA"); halo = Color(hex: "FFD56A"); sunPos = CGPoint(x: 0.80, y: 0.30); glow = 0.7
        case (.dusk, false):
            gradient = [Color(hex: "E9A878"), Color(hex: "D393A2"), Color(hex: "8C7FB0")]
            light = false; sun = Color(hex: "FFE7C2"); halo = Color(hex: "FF8F3D"); sunPos = CGPoint(x: 0.76, y: 0.58); glow = 0.8
        case (.night, false):
            gradient = [Color(hex: "2B2749"), Color(hex: "4A416F"), Color(hex: "6F6694")]
            light = true; sun = Color(hex: "F4EEDC"); halo = Color(hex: "F4EEDC"); sunPos = CGPoint(x: 0.80, y: 0.30); glow = 0.25
        case (.dawn, true):
            gradient = [Color(hex: "0D0F1F"), Color(hex: "2A2238"), Color(hex: "5A3A36")]
            light = true; sun = Color(hex: "FFD9B0"); halo = Color(hex: "FF8E4A"); sunPos = CGPoint(x: 0.78, y: 0.60); glow = 0.6
        case (.day, true):
            gradient = [Color(hex: "121829"), Color(hex: "1B2238"), Color(hex: "11141D")]
            light = true; sun = Color(hex: "C9D4EA"); halo = Color(hex: "C9D4EA"); sunPos = CGPoint(x: 0.80, y: 0.28); glow = 0.12
        case (.dusk, true):
            gradient = [Color(hex: "14122A"), Color(hex: "3A2338"), Color(hex: "6A3A33")]
            light = true; sun = Color(hex: "FFD2A8"); halo = Color(hex: "FF7A3A"); sunPos = CGPoint(x: 0.76, y: 0.58); glow = 0.65
        case (.night, true):
            gradient = [Color(hex: "070912"), Color(hex: "11142A"), Color(hex: "0E1018")]
            light = true; sun = Color(hex: "E9E4D2"); halo = Color(hex: "E9E4D2"); sunPos = CGPoint(x: 0.80, y: 0.30); glow = 0.2
        }

        // Weather modifies the sky: greys for cloud, darker greys for rain, flat for fog.
        func blend(_ colors: [Color], toward target: Color, _ amount: Double) -> [Color] {
            colors.map { $0.mix(with: target, by: amount, in: .perceptual) }
        }
        // Cloud palette: lit top / base / shadow, per scheme and weather.
        var cloudLit: Color = dark ? Color(hex: "7D869C") : Color.white
        var cloudBase: Color = dark ? Color(hex: "3F475C") : Color(hex: "E3E8EF")
        var cloudShadow: Color = dark ? Color(hex: "0B0E18") : Color(hex: "6E7A8C")
        var cloudOpacity: Double = 1
        switch weather {
        case .clear:
            break
        case .partlyCloudy:
            gradient = blend(gradient, toward: dark ? Color(hex: "1A1E2A") : Color(hex: "D9DEE3"), 0.15)
            // A fair-weather cloud, not a storm cell: paler in dark mode.
            if dark { cloudLit = Color(hex: "9AA3B8"); cloudBase = Color(hex: "545E78"); cloudShadow = Color(hex: "141826") }
        case .cloudy:
            gradient = blend(gradient, toward: dark ? Color(hex: "1E222B") : Color(hex: "C9CFD6"), 0.6)
            cloudLit = dark ? Color(hex: "6F7A91") : Color(hex: "F7F8FA")
            cloudBase = dark ? Color(hex: "394154") : Color(hex: "CBD2DC")
        case .rain, .storm:
            gradient = dark ? [Color(hex: "161A24"), Color(hex: "1F2630"), Color(hex: "262D38")]
                            : [Color(hex: "AEB9C6"), Color(hex: "C4CDD7"), Color(hex: "D6DCE3")]
            if weather == .storm { gradient = blend(gradient, toward: dark ? Color(hex: "0E1016") : Color(hex: "8E99A8"), 0.3) }
            cloudLit = dark ? Color(hex: "5E687E") : Color(hex: "C4CCD6")
            cloudBase = dark ? Color(hex: "2C3344") : Color(hex: "7E8A99")
            cloudShadow = dark ? Color(hex: "05070D") : Color(hex: "46505E")
        case .snow:
            gradient = blend(gradient, toward: dark ? Color(hex: "1C2028") : Color(hex: "DADEE3"), 0.5)
            cloudLit = dark ? Color(hex: "76819A") : Color.white
            cloudBase = dark ? Color(hex: "3B4357") : Color(hex: "D7DDE5")
        case .fog:
            gradient = blend(gradient, toward: dark ? Color(hex: "1A1C22") : Color(hex: "D4D5D6"), 0.7)
        }

        // Dusk keeps the sun until 18:00; after that the sky is still warm but the moon is up.
        let afterSunset = phase == .dusk && hour >= 18
        let showsSun = weather.hasSun && (phase != .night) && !afterSunset && !(dark && phase == .day)
        let showsMoon = weather.hasSun && (phase == .night || afterSunset)
        return SkyStyle(
            phase: phase, weather: weather, gradient: gradient, usesLightText: light,
            tint: gradient[1], sunColor: sun, glowColor: halo, sunPosition: sunPos,
            showsSun: showsSun, showsMoon: showsMoon,
            cloudLit: cloudLit, cloudBase: cloudBase, cloudShadow: cloudShadow, cloudOpacity: cloudOpacity, sunGlowOpacity: glow
        )
    }
}

/// The sky inside the hero card: the time-of-day gradient plus one 150×90 pt art region in
/// the top-right (`WeatherArt`). The same geometry is used for every condition, so the
/// temperature, date and stats never collide with the art and the three weather states read
/// as one product under different conditions. Pass a fixed `hour` from previews.
struct SkyScene: View {
    var hour: Int
    var condition: String?
    /// Distance from the top-right corner of the scene to the art region.
    var artInset: CGSize = CGSize(width: 20, height: 44)
    @Environment(\.colorScheme) private var colorScheme

    var style: SkyStyle { SkyStyle.resolve(hour: hour, condition: condition, colorScheme: colorScheme) }

    var body: some View {
        let s = style
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: s.gradient, startPoint: .top, endPoint: .bottom)
            WeatherArt(style: s)
                .frame(width: WeatherArt.size.width, height: WeatherArt.size.height)
                .padding(.top, artInset.height)
                .padding(.trailing, artInset.width)
        }
        .clipped()
    }
}

/// Crisp vector weather art in a fixed 150×90 pt box. Element positions are constant across
/// conditions: sun / moon disc centred at (112, 34); near cloud 100 pt wide at (10, 16);
/// far cloud 72 pt wide top-right; rain and snow fall from the near cloud's base.
struct WeatherArt: View {
    let style: SkyStyle
    static let size = CGSize(width: 150, height: 90)

    private static let sunCenter = CGPoint(x: 112, y: 34)
    private static let nearCloud = CGRect(x: 10, y: 16, width: 100, height: 100 * CloudShape.aspect)
    private static let farCloud = CGRect(x: 76, y: 6, width: 72, height: 72 * CloudShape.farAspect)

    /// Fixed star field (x, y, radius) inside the box.
    private static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (8, 14, 1.1), (26, 6, 0.8), (40, 24, 1.0), (58, 10, 0.7), (72, 30, 1.0), (20, 44, 0.7),
        (48, 46, 0.8), (142, 10, 0.9), (84, 50, 0.7), (34, 66, 0.6), (64, 70, 0.7), (136, 62, 0.6), (6, 80, 0.8)
    ]

    var body: some View {
        let s = style
        ZStack(alignment: .topLeading) {
            if s.showsMoon {
                if s.phase == .night { stars }
                moon
            }
            if s.showsSun {
                sun
            }
            if s.weather == .fog {
                fog
            }
            if s.weather == .rain || s.weather == .storm {
                rain   // behind the cloud: it falls from it
            }
            if s.weather == .snow {
                snow
            }
            if s.weather.cloudCount > 1 {
                cloud(in: Self.farCloud, lobes: CloudShape.farLobes, far: true)
            }
            if s.weather.cloudCount > 0 {
                cloud(in: Self.nearCloud, lobes: CloudShape.nearLobes, far: false)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Sun / moon

    /// 44 pt disc (#FFF9DF → #F3B364) with a 92 pt halo blurred 22 pt at ≤ 28 %. Dawn and dusk
    /// widen the halo to ~130 pt around the disc only; the page never gets an orange wash.
    private var sun: some View {
        let s = style
        let warm = s.phase == .dawn || s.phase == .dusk
        let haloSize: CGFloat = warm ? 130 : 92
        return ZStack {
            Circle()
                .fill(s.glowColor)
                .frame(width: haloSize, height: haloSize)
                .blur(radius: warm ? 28 : 22)
                .opacity(min(s.sunGlowOpacity, 0.24))
            Circle()
                .fill(RadialGradient(colors: s.phase == .dusk ? [Color(hex: "FFE6C2"), Color(hex: "F08A4B")] : [Color(hex: "FFF9DF"), Color(hex: "F3B364")],
                                     center: UnitPoint(x: 0.40, y: 0.36), startRadius: 4, endRadius: 24))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                .frame(width: 44, height: 44)
                .opacity(s.weather == .partlyCloudy ? 0.96 : 1)
        }
        .position(Self.sunCenter)
    }

    private var moon: some View {
        let s = style
        let r: CGFloat = 20
        return ZStack {
            Circle()
                .fill(s.sunColor)
                .frame(width: 92, height: 92)
                .blur(radius: 22)
                .opacity(0.16)
            Circle()
                .fill(s.sunColor)
                .frame(width: r * 2, height: r * 2)
                .mask {
                    ZStack {
                        Circle()
                        Circle()
                            .frame(width: r * 2, height: r * 2)
                            .offset(x: -r * 0.55, y: -r * 0.2)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
        .position(Self.sunCenter)
    }

    private var stars: some View {
        Canvas { context, _ in
            for star in Self.stars {
                let rect = CGRect(x: star.x - star.r, y: star.y - star.r, width: star.r * 2, height: star.r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.7)))
            }
        }
    }

    // MARK: Cloud

    /// Authored silhouette (union of circles over a flat base): crisp edge softened ≤ 0.8 pt, lit
    /// top to shaded base, and a separate drop shadow (black 18 %, blur 16, y 8).
    private func cloud(in rect: CGRect, lobes: [CloudShape.Lobe], far: Bool) -> some View {
        let s = style
        let shape = CloudShape(lobes: lobes)
        let warmTop = s.phase == .dawn || s.phase == .dusk
        let lit = warmTop ? s.cloudLit.mix(with: s.glowColor, by: 0.2, in: .perceptual) : s.cloudLit
        return ZStack {
            shape
                .fill(Color.black.opacity(far ? 0.10 : 0.18))
                .blur(radius: 12)
                .offset(y: 8)
            shape
                .fill(LinearGradient(stops: [
                    .init(color: lit, location: 0),
                    .init(color: s.cloudBase, location: 0.64),
                    .init(color: s.cloudBase.mix(with: s.cloudShadow, by: 0.3, in: .perceptual), location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .overlay {
                    shape.fill(RadialGradient(colors: [lit.opacity(0.6), lit.opacity(0)],
                                              center: UnitPoint(x: 0.42, y: 0.18), startRadius: 0, endRadius: rect.width * 0.45))
                }
                .blur(radius: far ? 0.5 : 0)
        }
        .frame(width: rect.width, height: rect.height)
        .opacity(far ? 0.9 : s.cloudOpacity)
        .offset(x: rect.minX, y: rect.minY)
    }

    // MARK: Precipitation

    /// 14 deterministic 1.25 pt strokes, 28 pt long, at 30 % — falling from the near cloud's base.
    private var rain: some View {
        let s = style
        let color = (s.usesLightText ? Color.white : Color(hex: "2E3A4A")).opacity(s.usesLightText ? 0.34 : 0.42)
        let base = Self.nearCloud.minY + Self.nearCloud.height * 0.72
        return Canvas { context, _ in
            let count = s.weather == .storm ? 16 : 14
            for i in 0..<count {
                let t = CGFloat(i)
                let x = Self.nearCloud.minX + 10 + t * (Self.nearCloud.width - 16) / CGFloat(count - 1)
                let near = i % 2 == 0                               // two depths: near / far
                let yOffset = CGFloat((i * 7) % 11)                 // deterministic 0…10 pt stagger
                let length: CGFloat = near ? 28 : 18
                let start = CGPoint(x: x, y: base + yOffset)
                var path = Path()
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x - length * 0.14, y: start.y + length))
                context.stroke(path, with: .color(color.opacity(near ? 1 : 0.6)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
            }
        }
    }

    private var snow: some View {
        let base = Self.nearCloud.minY + Self.nearCloud.height * 0.8
        return Canvas { context, _ in
            for i in 0..<18 {
                let t = CGFloat(i)
                let x = Self.nearCloud.minX + 8 + t * (Self.nearCloud.width - 12) / 17
                let y = base + CGFloat((i * 9) % 23)
                let r: CGFloat = i % 3 == 0 ? 1.8 : 1.2
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(Color.white.opacity(0.85)))
            }
        }
    }

    private var fog: some View {
        let s = style
        let color = s.usesLightText ? Color.white : Color(hex: "6F7781")
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(i == 1 ? 0.34 : 0.22))
                    .frame(width: i == 1 ? 118 : 96, height: 10)
                    .padding(.leading, i == 2 ? 22 : (i == 0 ? 30 : 0))
            }
        }
        .padding(.top, 24)
        .padding(.leading, 8)
    }
}

// MARK: - Cloud silhouette

/// A cloud as a union of circles in unit coordinates (x, y, r relative to width), plus a flat
/// base, so the overlaps merge into one silhouette. The bounding box is exactly the frame.
struct CloudShape: Shape {
    struct Lobe { let x: CGFloat; let y: CGFloat; let r: CGFloat }
    var lobes: [Lobe]
    static let aspect: CGFloat = 0.537
    static let farAspect: CGFloat = 0.481

    /// Big cumulus: tall centre mound, shoulders either side, flat base.
    static let nearLobes: [Lobe] = [
        Lobe(x: 0.500, y: 0.220, r: 0.220), Lobe(x: 0.317, y: 0.280, r: 0.183), Lobe(x: 0.671, y: 0.268, r: 0.171),
        Lobe(x: 0.402, y: 0.171, r: 0.134), Lobe(x: 0.585, y: 0.159, r: 0.122), Lobe(x: 0.232, y: 0.244, r: 0.110),
        Lobe(x: 0.780, y: 0.256, r: 0.110), Lobe(x: 0.134, y: 0.341, r: 0.134), Lobe(x: 0.878, y: 0.341, r: 0.122),
        Lobe(x: 0.500, y: 0.341, r: 0.195), Lobe(x: 0.293, y: 0.354, r: 0.171), Lobe(x: 0.720, y: 0.354, r: 0.159)
    ]
    /// Smaller, flatter bank for the far layer.
    static let farLobes: [Lobe] = [
        Lobe(x: 0.468, y: 0.203, r: 0.203), Lobe(x: 0.278, y: 0.253, r: 0.152), Lobe(x: 0.684, y: 0.241, r: 0.165),
        Lobe(x: 0.380, y: 0.152, r: 0.101), Lobe(x: 0.582, y: 0.139, r: 0.101), Lobe(x: 0.886, y: 0.304, r: 0.114),
        Lobe(x: 0.101, y: 0.316, r: 0.101), Lobe(x: 0.481, y: 0.304, r: 0.177)
    ]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        var bottom: CGFloat = 0
        for l in lobes {
            let r = l.r * w
            p.addEllipse(in: CGRect(x: rect.minX + l.x * w - r, y: rect.minY + l.y * w - r, width: r * 2, height: r * 2))
            bottom = max(bottom, (l.y + l.r) * w)
        }
        // Flat base: a capsule across the lower lobes so the underside reads as one edge.
        let baseHeight = w * 0.11
        p.addRoundedRect(in: CGRect(x: rect.minX + w * 0.06, y: rect.minY + bottom - baseHeight, width: w * 0.88, height: baseHeight),
                         cornerSize: CGSize(width: baseHeight / 2, height: baseHeight / 2))
        return p
    }
}

// MARK: - Breathing status dot

/// Tiny dot next to "Updated 6:21 PM"; 2 s opacity cycle 0.45 → 1.0, still under Reduce Motion.
struct BreathingDot: View {
    var color: Color
    /// False for offscreen renders (share card).
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(reduceMotion || !animated ? 0.9 : (bright ? 1.0 : 0.45))
            .onAppear {
                guard !reduceMotion, animated else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}

private struct SceneSample: Identifiable {
    let hour: Int
    let condition: String
    var id: String { "\(hour)-\(condition)" }
}

private let sceneSamples: [SceneSample] = [
    SceneSample(hour: 7, condition: "Clear"), SceneSample(hour: 12, condition: "Partly Cloudy"),
    SceneSample(hour: 15, condition: "Cloudy"), SceneSample(hour: 9, condition: "Rain"),
    SceneSample(hour: 18, condition: "Clear"), SceneSample(hour: 22, condition: "Clear"),
    SceneSample(hour: 8, condition: "Fog"), SceneSample(hour: 10, condition: "Snow")
]

private struct SceneSheet: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(sceneSamples) { sample in
                    SkyScene(hour: sample.hour, condition: sample.condition)
                        .frame(height: 170)
                        .overlay(alignment: .bottomLeading) {
                            Text("\(sample.hour):00 · \(sample.condition)")
                                .font(.caption)
                                .padding(8)
                        }
                }
            }
        }
    }
}

#Preview("Scenes · light") {
    SceneSheet().preferredColorScheme(.light)
}

#Preview("Scenes · dark") {
    SceneSheet().preferredColorScheme(.dark)
}
