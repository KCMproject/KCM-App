import SwiftUI
import UIKit

struct SwipeableView: UIViewControllerRepresentable {
    let content: AnyView
    let onSwipeLeft: (() -> Void)?
    let onSwipeRight: (() -> Void)?

    init<Content: View>(content: Content, onSwipeLeft: (() -> Void)?, onSwipeRight: (() -> Void)?) {
        self.content = AnyView(content)
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
    }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear

        let leftSwipe = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipe(_:))
        )
        leftSwipe.direction = .left
        hostingController.view.addGestureRecognizer(leftSwipe)

        let rightSwipe = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipe(_:))
        )
        rightSwipe.direction = .right
        hostingController.view.addGestureRecognizer(rightSwipe)

        return hostingController
    }

    func updateUIViewController(_ uiViewController: UIHostingController<AnyView>, context: Context) {
        uiViewController.rootView = content
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    class Coordinator: NSObject {
        var onSwipeLeft: (() -> Void)?
        var onSwipeRight: (() -> Void)?

        init(onSwipeLeft: (() -> Void)?, onSwipeRight: (() -> Void)?) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            switch gesture.direction {
            case .left:
                onSwipeLeft?()
            case .right:
                onSwipeRight?()
            default:
                break
            }
        }
    }
}