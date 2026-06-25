import SwiftUI
import UIKit

struct SwipeableView: UIViewControllerRepresentable {
    let selectedTab: Int
    let tabCount: Int
    let contentProvider: (Int) -> AnyView
    let onSwipeToTab: ((Int) -> Void)?
    var isSwipeEnabled: Bool = true

    init(
        selectedTab: Int,
        tabCount: Int,
        contentProvider: @escaping (Int) -> AnyView,
        onSwipeToTab: ((Int) -> Void)?,
        isSwipeEnabled: Bool = true
    ) {
        self.selectedTab = selectedTab
        self.tabCount = tabCount
        self.contentProvider = contentProvider
        self.onSwipeToTab = onSwipeToTab
        self.isSwipeEnabled = isSwipeEnabled
    }

    func makeUIViewController(context: Context) -> SwipeableContainerController {
        let controller = SwipeableContainerController()
        controller.tabCount = tabCount
        controller.contentProvider = contentProvider
        controller.onSwipeToTab = onSwipeToTab
        controller.pendingInitialTab = selectedTab
        controller.isSwipeEnabled = isSwipeEnabled
        return controller
    }

    func updateUIViewController(_ uiViewController: SwipeableContainerController, context: Context) {
        uiViewController.tabCount = tabCount
        uiViewController.contentProvider = contentProvider
        uiViewController.onSwipeToTab = onSwipeToTab
        uiViewController.isSwipeEnabled = isSwipeEnabled

        if uiViewController.isDragging {
            uiViewController.currentTabIndex = selectedTab
            return
        }

        // 同じタブの場合はコンテンツを作り直さない
        guard uiViewController.currentTabIndex != selectedTab else { return }

        let animated = selectedTab != uiViewController.currentTabIndex
        uiViewController.setContent(contentProvider(selectedTab), selectedIndex: selectedTab, animated: animated)
    }
}

class SwipeableContainerController: UIViewController {
    var onSwipeToTab: ((Int) -> Void)?
    var tabCount: Int = 0
    var currentTabIndex: Int = 0
    var contentProvider: (Int) -> AnyView = { _ in AnyView(EmptyView()) }
    var isDragging = false
    var isSwipeEnabled = true
    var pendingInitialTab: Int?

    private var currentHC: UIHostingController<AnyView>?
    private var adjacentHC: UIHostingController<AnyView>?
    private var adjacentTabIndex: Int?

    private var panGesture: UIPanGestureRecognizer!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)

        if let tab = pendingInitialTab {
            setContent(contentProvider(tab), selectedIndex: tab, animated: false)
            pendingInitialTab = nil
        }
    }

    func setContent(_ content: AnyView, selectedIndex: Int, animated: Bool) {
        removeCurrent()

        let hc = UIHostingController(rootView: content)
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hc)
        view.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hc.didMove(toParent: self)
        currentHC = hc
        currentTabIndex = selectedIndex

        if animated {
            hc.view.alpha = 0
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                hc.view.alpha = 1
            }
        }
    }

    private func ensureAdjacent(at index: Int) {
        guard index >= 0, index < tabCount else { return }
        if let current = adjacentTabIndex, current == index, adjacentHC != nil { return }

        removeAdjacent()

        let hc = UIHostingController(rootView: contentProvider(index))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hc)
        if let currentView = currentHC?.view {
            view.insertSubview(hc.view, belowSubview: currentView)
        } else {
            view.addSubview(hc.view)
        }
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hc.didMove(toParent: self)
        hc.view.layoutIfNeeded()
        adjacentHC = hc
        adjacentTabIndex = index
    }

    private func removeAdjacent() {
        guard let hc = adjacentHC else { return }
        hc.willMove(toParent: nil)
        hc.view.removeFromSuperview()
        hc.removeFromParent()
        adjacentHC = nil
        adjacentTabIndex = nil
    }

    private func removeCurrent() {
        guard let hc = currentHC else { return }
        hc.willMove(toParent: nil)
        hc.view.removeFromSuperview()
        hc.removeFromParent()
        currentHC = nil
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let currentView = currentHC?.view else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let screenWidth = view.bounds.width

        switch gesture.state {
        case .began:
            isDragging = true

        case .changed:
            let atLeftEdge = currentTabIndex == 0
            let atRightEdge = currentTabIndex >= tabCount - 1

            var offset = translation.x
            if atLeftEdge && offset > 0 {
                offset *= 0.3
            } else if atRightEdge && offset < 0 {
                offset *= 0.3
            }

            currentView.transform = CGAffineTransform(translationX: offset, y: 0)

            let desiredAdjacent: Int?
            if translation.x > 0 && !atLeftEdge {
                desiredAdjacent = currentTabIndex - 1
            } else if translation.x < 0 && !atRightEdge {
                desiredAdjacent = currentTabIndex + 1
            } else {
                desiredAdjacent = nil
            }

            if let desired = desiredAdjacent {
                ensureAdjacent(at: desired)
                if let adjView = adjacentHC?.view {
                    let sideMultiplier: CGFloat = (desired < currentTabIndex) ? -1 : 1
                    let adjOffset = sideMultiplier * screenWidth + offset
                    adjView.transform = CGAffineTransform(translationX: adjOffset, y: 0)
                }
            } else {
                removeAdjacent()
            }

        case .ended, .cancelled:
            let atLeftEdge = currentTabIndex == 0
            let atRightEdge = currentTabIndex >= tabCount - 1
            let atEdge = (atLeftEdge && translation.x > 0) || (atRightEdge && translation.x < 0)

            if atEdge {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.85,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut,
                    animations: {
                        currentView.transform = .identity
                    },
                    completion: { _ in
                        self.removeAdjacent()
                        self.isDragging = false
                    }
                )
                return
            }

            let shouldComplete: Bool
            if abs(velocity.x) > 300 {
                shouldComplete = true
            } else if abs(translation.x) > screenWidth * 0.2 {
                shouldComplete = true
            } else {
                shouldComplete = false
            }

            let targetTab: Int
            if translation.x < 0 && !atRightEdge {
                targetTab = currentTabIndex + 1
            } else if translation.x > 0 && !atLeftEdge {
                targetTab = currentTabIndex - 1
            } else {
                targetTab = currentTabIndex
            }

            if shouldComplete && targetTab != currentTabIndex {
                let completionIndex = targetTab
                let targetX: CGFloat = translation.x < 0 ? -screenWidth : screenWidth

                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    options: .curveEaseOut,
                    animations: {
                        currentView.transform = CGAffineTransform(translationX: targetX, y: 0)
                        self.adjacentHC?.view.transform = .identity
                    },
                    completion: { _ in
                        self.setContent(self.contentProvider(completionIndex), selectedIndex: completionIndex, animated: false)
                        self.isDragging = false
                        self.onSwipeToTab?(completionIndex)
                    }
                )
            } else {
                let offscreenX: CGFloat
                if let adjIndex = adjacentTabIndex {
                    offscreenX = adjIndex < currentTabIndex ? -screenWidth : screenWidth
                } else {
                    offscreenX = translation.x < 0 ? screenWidth : -screenWidth
                }

                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.85,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut,
                    animations: {
                        currentView.transform = .identity
                        self.adjacentHC?.view.transform = CGAffineTransform(translationX: offscreenX, y: 0)
                    },
                    completion: { _ in
                        self.removeAdjacent()
                        self.isDragging = false
                    }
                )
            }

        default:
            break
        }
    }
}

extension SwipeableContainerController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isSwipeEnabled else { return false }
        let velocity = panGesture.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) * 1.5
    }
}
