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
    var cloudColor: Color
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
        var cloudColor: Color = dark ? Color(hex: "4E586C") : Color.white
        var cloudOpacity: Double = dark ? 0.9 : 0.96
        switch weather {
        case .clear:
            break
        case .partlyCloudy:
            gradient = blend(gradient, toward: dark ? Color(hex: "1A1E2A") : Color(hex: "D9DEE3"), 0.15)
        case .cloudy:
            gradient = blend(gradient, toward: dark ? Color(hex: "1E222B") : Color(hex: "C9CFD6"), 0.45)
            cloudColor = dark ? Color(hex: "525B6D") : Color(hex: "F2F3F5")
        case .rain, .storm:
            gradient = blend(gradient, toward: dark ? Color(hex: "161A22") : Color(hex: "A3AEBB"), weather == .storm ? 0.75 : 0.6)
            cloudColor = dark ? Color(hex: "3D4556") : Color(hex: "7E8A99")
            cloudOpacity = dark ? 0.95 : 0.8
        case .snow:
            gradient = blend(gradient, toward: dark ? Color(hex: "1C2028") : Color(hex: "DADEE3"), 0.5)
            cloudColor = dark ? Color(hex: "4A5364") : Color(hex: "F4F5F7")
        case .fog:
            gradient = blend(gradient, toward: dark ? Color(hex: "1A1C22") : Color(hex: "D4D5D6"), 0.7)
        }

        let showsSun = weather.hasSun && (phase != .night) && !(dark && phase == .day)
        let showsMoon = weather.hasSun && phase == .night
        return SkyStyle(
            phase: phase, weather: weather, gradient: gradient, usesLightText: light,
            tint: gradient[1], sunColor: sun, glowColor: halo, sunPosition: sunPos,
            showsSun: showsSun, showsMoon: showsMoon,
            cloudColor: cloudColor, cloudOpacity: cloudOpacity, sunGlowOpacity: glow
        )
    }
}

/// The scene itself. Pass a fixed `hour` from previews so the render is deterministic.
struct SkyScene: View {
    var hour: Int
    var condition: String?
    @Environment(\.colorScheme) private var colorScheme

    /// Fixed star field in unit coordinates (x, y, radius).
    private static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.08, 0.18, 1.2), (0.21, 0.09, 0.8), (0.33, 0.24, 1.0), (0.46, 0.11, 0.7), (0.57, 0.30, 1.1),
        (0.66, 0.08, 0.8), (0.14, 0.42, 0.7), (0.39, 0.40, 0.8), (0.91, 0.12, 0.9), (0.73, 0.44, 0.7),
        (0.27, 0.56, 0.6), (0.52, 0.52, 0.7), (0.86, 0.50, 0.6), (0.05, 0.63, 0.8)
    ]

    var style: SkyStyle { SkyStyle.resolve(hour: hour, condition: condition, colorScheme: colorScheme) }

    var body: some View {
        let s = style
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: s.gradient, startPoint: .top, endPoint: .bottom)

                if s.showsMoon {
                    stars(in: size, dark: colorScheme == .dark)
                    moon(in: size, style: s)
                }
                if s.showsSun {
                    sun(in: size, style: s)
                }
                if s.weather == .fog {
                    fogBands(in: size, style: s)
                }
                if s.weather.cloudCount > 0 {
                    clouds(in: size, style: s)
                }
                if s.weather == .rain || s.weather == .storm {
                    rain(in: size, style: s)
                }
                if s.weather == .snow {
                    snow(in: size, style: s)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    // MARK: Elements

    private func sun(in size: CGSize, style s: SkyStyle) -> some View {
        let center = CGPoint(x: size.width * s.sunPosition.x, y: size.height * s.sunPosition.y)
        let disc: CGFloat = s.phase == .day ? 52 : 64
        return ZStack {
            // Wide warm halo, a tighter bloom, then the bright disc.
            Circle()
                .fill(RadialGradient(colors: [s.glowColor.opacity(s.sunGlowOpacity), s.glowColor.opacity(0.25), s.glowColor.opacity(0)],
                                     center: .center, startRadius: disc * 0.5, endRadius: disc * 3.0))
                .frame(width: disc * 6, height: disc * 6)
            Circle()
                .fill(s.sunColor.opacity(0.6))
                .frame(width: disc * 1.4, height: disc * 1.4)
                .blur(radius: 8)
            Circle()
                .fill(s.sunColor)
                .frame(width: disc, height: disc)
                .blur(radius: 1)
                .opacity(s.weather == .partlyCloudy ? 0.95 : 1)
        }
        .position(center)
    }

    private func moon(in size: CGSize, style s: SkyStyle) -> some View {
        let center = CGPoint(x: size.width * s.sunPosition.x, y: size.height * s.sunPosition.y)
        let r: CGFloat = 22
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [s.sunColor.opacity(0.25), s.sunColor.opacity(0)],
                                     center: .center, startRadius: r, endRadius: r * 4.5))
                .frame(width: r * 9, height: r * 9)
            // Thin crescent: a disc with a second, offset disc cut out of it.
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
                .opacity(0.95)
        }
        .position(center)
    }

    private func stars(in size: CGSize, dark: Bool) -> some View {
        Canvas { context, _ in
            for star in Self.stars {
                let rect = CGRect(x: size.width * star.x, y: size.height * star.y, width: star.r * 2, height: star.r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(dark ? 0.75 : 0.6)))
            }
        }
        .allowsHitTesting(false)
    }

    /// One or two large soft volumes built from overlapping blurred circles and capsules.
    private func clouds(in size: CGSize, style s: SkyStyle) -> some View {
        let w = size.width
        let h = size.height
        return ZStack {
            // One cloud (partly cloudy) sits left of the sun; the second volume covers the right.
            cloudVolume(width: w * 0.62, height: h * 0.20)
                .position(x: s.weather.cloudCount > 1 ? w * 0.62 : w * 0.40, y: h * 0.34)
            if s.weather.cloudCount > 1 {
                cloudVolume(width: w * 0.5, height: h * 0.16)
                    .position(x: w * 0.22, y: h * 0.22)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(s.cloudColor)
        .opacity(s.cloudOpacity)
        .allowsHitTesting(false)
    }

    private func cloudVolume(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Soft underside shadow gives the volume depth, then the lit body.
            cloudLobes(width: width, height: height)
                .foregroundStyle(Color.black.opacity(0.10))
                .offset(y: height * 0.22)
                .blur(radius: 14)
            cloudLobes(width: width, height: height)
                .blur(radius: 6)
        }
        .frame(width: width * 1.4, height: height * 2.6)
    }

    private func cloudLobes(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Capsule()
                .frame(width: width, height: height * 0.9)
                .offset(y: height * 0.15)
            Circle()
                .frame(width: height * 1.5, height: height * 1.5)
                .offset(x: -width * 0.18, y: -height * 0.15)
            Circle()
                .frame(width: height * 1.9, height: height * 1.9)
                .offset(x: width * 0.08, y: -height * 0.35)
            Circle()
                .frame(width: height * 1.2, height: height * 1.2)
                .offset(x: width * 0.32, y: -height * 0.05)
        }
    }

    /// Fine diagonal streaks at fixed pseudo-random positions.
    private func rain(in size: CGSize, style s: SkyStyle) -> some View {
        Canvas { context, _ in
            var x: CGFloat = 6
            var seed: UInt32 = 7
            let color = s.usesLightText ? Color.white.opacity(0.28) : Color(hex: "2F3A48").opacity(0.35)
            while x < size.width {
                seed = seed &* 1_103_515_245 &+ 12_345
                // Streaks live in the sky's upper 60 %; the temperature block sits below.
                let y = CGFloat((seed >> 8) % 1000) / 1000 * size.height * 0.5 + size.height * 0.08
                let length: CGFloat = 14 + CGFloat((seed >> 4) % 12)
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - 3, y: y + length))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                x += 9 + CGFloat(seed % 7)
            }
        }
        .allowsHitTesting(false)
    }

    private func snow(in size: CGSize, style s: SkyStyle) -> some View {
        Canvas { context, _ in
            var seed: UInt32 = 11
            for _ in 0..<46 {
                seed = seed &* 1_103_515_245 &+ 12_345
                let x = CGFloat((seed >> 8) % 1000) / 1000 * size.width
                seed = seed &* 1_103_515_245 &+ 12_345
                let y = CGFloat((seed >> 8) % 1000) / 1000 * size.height
                let r: CGFloat = 1 + CGFloat(seed % 3) * 0.6
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                             with: .color(Color.white.opacity(0.7)))
            }
        }
        .allowsHitTesting(false)
    }

    private func fogBands(in size: CGSize, style s: SkyStyle) -> some View {
        VStack(spacing: size.height * 0.07) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill((s.usesLightText ? Color.white : Color(hex: "6F7781")).opacity(i % 2 == 0 ? 0.22 : 0.34))
                    .frame(height: size.height * 0.08)
                    .padding(.leading, i % 2 == 0 ? -size.width * 0.2 : size.width * 0.05)
                    .padding(.trailing, i % 2 == 0 ? size.width * 0.1 : -size.width * 0.25)
                    .blur(radius: 6)
            }
        }
        .padding(.top, size.height * 0.2)
        .allowsHitTesting(false)
    }
}

// MARK: - Breathing status dot

/// Tiny dot next to "Updated 6:21 PM"; 2 s opacity cycle 0.45 → 1.0, still under Reduce Motion.
struct BreathingDot: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(reduceMotion ? 0.9 : (bright ? 1.0 : 0.45))
            .onAppear {
                guard !reduceMotion else { return }
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
