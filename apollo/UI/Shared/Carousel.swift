
import SwiftUI

struct CarouselTranslationEffect: GeometryEffect {
    var offsetX: CGFloat

    var animatableData: CGFloat {
        get { offsetX }
        set { offsetX = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: offsetX, y: 0))
    }
}

struct CarouselContainer<Content: View>: View {
    @ObservedObject var swipeState = SwipeState.shared
    let isSlimBoxInstance: Bool
    let currentPage: Int
    let panelWidth: CGFloat
    let content: Content

    init(isSlimBoxInstance: Bool, currentPage: Int, panelWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.isSlimBoxInstance = isSlimBoxInstance
        self.currentPage = currentPage
        self.panelWidth = panelWidth
        self.content = content()
    }

    var body: some View {
        content
            .modifier(CarouselTranslationEffect(offsetX: -CGFloat(isSlimBoxInstance ? 0 : currentPage) * panelWidth + swipeState.carouselDragOffset))
    }
}
