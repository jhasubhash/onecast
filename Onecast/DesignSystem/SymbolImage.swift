import SwiftUI

/// A symbol falling back to a bundled asset of the same name, since not all are system.
struct SymbolImage: View {
    let name: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: SystemSymbolName.resolve(name, isDark: colorScheme == .dark))
                .font(.system(size: size, weight: .regular))
                .symbolRenderingMode(.hierarchical)
        }
    }
}
