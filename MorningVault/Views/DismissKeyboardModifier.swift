import SwiftUI

// MARK: - Dismiss Keyboard on Tap

/// Removes focus from any active text field when the user taps outside the keyboard.
/// Apply to the root view of screens with TextFields/SecureFields.
struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
            )
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}