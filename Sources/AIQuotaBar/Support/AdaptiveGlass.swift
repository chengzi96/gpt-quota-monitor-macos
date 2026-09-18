import SwiftUI

/// Keeps the current macOS 26 Liquid Glass treatment while allowing the same
/// layout to run on macOS 13–15 with a native material fallback.
struct AdaptivePanelGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                        .fill(Color.black.opacity(0.74))
                }
                .glassEffect(
                    .regular.tint(Color.black.opacity(0.62)),
                    in: RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                )
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                        .fill(Color.black.opacity(0.56))
                }
        }
    }
}

extension View {
    func adaptivePanelGlass() -> some View {
        modifier(AdaptivePanelGlassModifier())
    }

    @ViewBuilder
    func adaptiveCompactGlass<S: Shape>(
        tint: Color,
        in shape: S
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear.tint(tint), in: shape)
        } else {
            self
                .background(shape.fill(tint.opacity(0.72)))
                .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.6))
        }
    }
}
