import SwiftUI

/// Brand mark from Simple Icons, tinted with the provider's color.
struct ProviderLogo: View {
    let provider: Provider
    var size: CGFloat = 16

    var body: some View {
        Image(provider.logo)
            .resizable()
            .scaledToFit()
            .foregroundStyle(provider.tint)
            .frame(width: size, height: size)
            .accessibilityLabel(provider.name)
    }
}

/// Selectable tile for the Add Account picker.
struct ProviderCard: View {
    let provider: Provider
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ProviderLogo(provider: provider, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(.headline)
                    Text(provider.pitch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.fill.quaternary.opacity(hovering || selected ? 1 : 0.6), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : .secondary.opacity(0.2), lineWidth: selected ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
