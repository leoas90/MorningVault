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

@MainActor
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
