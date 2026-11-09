import SwiftUI

// MARK: - Shared controls for the Trackers screens

/// Capsule choice chip: hairline at rest, filled accent when selected.
struct ChoiceChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .medium))
                }
                Text(title).font(.system(size: 15, weight: .medium))
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(isSelected ? Color.onAccent : Color.inkPrimary)
            .background(isSelected ? Color.appAccentColor : Color.surfaceColor, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 12 pt member initial in a hairline circle (the row tag in the Brief and the editor).
struct MemberInitialChip: View {
    let initial: String
    var size: CGFloat = 22

    var body: some View {
        Text(initial)
            .font(.system(size: size > 20 ? 12 : 11, weight: .semibold))
            .foregroundStyle(Color.inkSecondary)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Eyebrow + content block with the section spacing used across the editor.
struct EditorBlock<Content: View>: View {
    let label: String
    var trailing: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Grid4.label) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: label)
                Spacer()
                if let trailing {
                    Text(trailing).font(.metaText).foregroundStyle(Color.inkSecondary)
                }
            }
            content()
        }
    }
}

/// "Pro" caption with a lock, shown next to gated controls when Pro is off.
struct ProLockCaption: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock").font(.system(size: 11, weight: .semibold))
            Text("Pro").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.inkSecondary)
        .accessibilityLabel("Pro feature")
    }
}

#Preview("Chips") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return VStack(alignment: .leading, spacing: 20) {
        FlowLayout(spacing: 8, alignment: .leading) {
            ChoiceChip(title: "Household", systemImage: "house", isSelected: true) {}
            ChoiceChip(title: "Sam", isSelected: false) {}
            ChoiceChip(title: "Riley", isSelected: false) {}
        }
        HStack { MemberInitialChip(initial: "S"); MemberInitialChip(initial: "R"); ProLockCaption() }
        EditorBlock(label: "Repeats", trailing: "Daily") { Hairline() }
    }
    .padding(20)
    .background(Color.backgroundColor)
}
