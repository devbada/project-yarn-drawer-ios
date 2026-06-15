import SwiftUI

struct BrandMarkView: View {
    var size: CGFloat = 42

    var body: some View {
        Image("PatternCabinetAppIcon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
            .shadow(color: YDColor.wood3.opacity(0.14), radius: 11, y: 5)
            .accessibilityHidden(true)
    }
}

