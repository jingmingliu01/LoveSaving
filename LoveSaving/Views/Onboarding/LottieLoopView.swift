import Lottie
import SwiftUI

struct LottieLoopView: UIViewRepresentable {
    let animationName: String

    func makeUIView(context: Context) -> AnimationContainerView {
        let containerView = AnimationContainerView()
        containerView.backgroundColor = .clear

        let animationView = makeAnimationView()
        containerView.install(animationView)
        context.coordinator.animationName = animationName
        return containerView
    }

    func updateUIView(_ uiView: AnimationContainerView, context: Context) {
        if context.coordinator.animationName != animationName {
            let animationView = makeAnimationView()
            uiView.install(animationView)
            context.coordinator.animationName = animationName
            return
        }

        guard let animationView = uiView.animationView else { return }
        if !animationView.isAnimationPlaying {
            animationView.play()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func makeAnimationView() -> LottieAnimationView {
        let animationView = LottieAnimationView(name: animationName)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .loop
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.shouldRasterizeWhenIdle = true
        animationView.play()
        return animationView
    }

    final class AnimationContainerView: UIView {
        fileprivate var animationView: LottieAnimationView?

        fileprivate func install(_ newAnimationView: LottieAnimationView) {
            animationView?.stop()
            animationView?.removeFromSuperview()
            animationView = newAnimationView

            addSubview(newAnimationView)
            NSLayoutConstraint.activate([
                newAnimationView.leadingAnchor.constraint(equalTo: leadingAnchor),
                newAnimationView.trailingAnchor.constraint(equalTo: trailingAnchor),
                newAnimationView.topAnchor.constraint(equalTo: topAnchor),
                newAnimationView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    final class Coordinator {
        var animationName: String?
    }
}
