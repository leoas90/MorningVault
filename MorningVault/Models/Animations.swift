import SwiftUI

// MARK: - Animation Constants

enum AppAnimation {
    static let cardEntranceDuration: Double = 0.4
    static let cardStaggerDelay: Double = 0.06
    static let springResponse: Double = 0.4
    static let springDamping: Double = 0.8
    static let tickAnimationDuration: Double = 0.15
    static let sparklineDrawDuration: Double = 0.6
    static let tabCrossfadeDuration: Double = 0.2
}

// MARK: - Reduce Motion Check

private var shouldReduceMotion: Bool {
    UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
}

// MARK: - Spring Animation

private var springAnimation: Animation {
    .spring(response: AppAnimation.springResponse, dampingFraction: AppAnimation.springDamping)
}

private var gentleSpringAnimation: Animation {
    .spring(response: 0.5, dampingFraction: 0.85)
}

// MARK: - Card Entrance Modifier

struct CardEntranceModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(shouldReduceMotion ? 1 : (isVisible ? 1 : 0))
            .offset(y: shouldReduceMotion ? 0 : (isVisible ? 0 : 20))
            .onAppear {
                if !shouldReduceMotion {
                    withAnimation(.easeOut(duration: AppAnimation.cardEntranceDuration).delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

extension View {
    func cardEntrance(delay: Double = 0) -> some View {
        modifier(CardEntranceModifier(delay: delay))
    }
}

// MARK: - Bounce on Appear Modifier

struct BounceOnAppearModifier: ViewModifier {
    let delay: Double
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shouldReduceMotion ? 1 : (hasAppeared ? 1 : 0.8))
            .onAppear {
                if !shouldReduceMotion && !hasAppeared {
                    hasAppeared = true
                    withAnimation(gentleSpringAnimation.delay(delay)) {
                        // animation triggers scale from 0.8 to 1
                    }
                }
            }
    }
}

extension View {
    func bounceOnAppear(delay: Double = 0) -> some View {
        modifier(BounceOnAppearModifier(delay: delay))
    }
}

// MARK: - Pulse on Change Modifier

struct PulseOnChangeModifier: ViewModifier {
    let value: String
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.02 : 1.0)
            .onChange(of: value) { _, _ in
                if !shouldReduceMotion {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPulsing = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isPulsing = false
                        }
                    }
                }
            }
    }
}

extension View {
    func pulseOnChange(value: some Equatable) -> some View {
        modifier(PulseOnChangeModifier(value: String(describing: value)))
    }
}

// MARK: - Highlight on Tap Modifier

struct HighlightOnTapModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func highlightOnTap() -> some View {
        modifier(HighlightOnTapModifier())
    }
}

// MARK: - Staggered Entrance For Each

struct StaggeredForEach<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element, Int) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element, Int) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
            content(item, index)
        }
    }
}