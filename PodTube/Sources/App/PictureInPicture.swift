import UIKit
import AVKit
import AVFoundation

extension Notification.Name {
    static let pipChanged = Notification.Name("PodTubePipChanged")
}

/// Picture in Picture of the video layer, through the system's own `AVPictureInPictureController` (iOS 9 and later).
/// Whether a device may use it is the OS's decision, not the app's: iPads since iOS 9, iPhones and iPod touches since iOS 14.
/// Where the OS says no, `isSupported` is false and the player shows no PiP button.
final class PictureInPicture: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PictureInPicture()

    static var isSupported: Bool { return AVPictureInPictureController.isPictureInPictureSupported() }

    private var controller: AVPictureInPictureController?
    private var possibleObserver: NSKeyValueObservation?
    private var starting = false

    /// The PiP window is up: the watch screen steps aside so the app underneath can be used.
    var onStarted: (() -> Void)?
    /// The user tapped "back to app" in the PiP window.
    var onRestore: (() -> Void)?

    /// From the moment PiP is about to start until its window is gone.
    var isActive: Bool { return starting || (controller?.isPictureInPictureActive ?? false) }
    var isPossible: Bool { return controller?.isPictureInPicturePossible ?? false }

    /// Ties PiP to the video layer. Does nothing on a device the OS does not allow PiP on.
    func bind(to layer: AVPlayerLayer) {
        guard controller == nil, PictureInPicture.isSupported,
              let c = AVPictureInPictureController(playerLayer: layer) else { return }
        c.delegate = self
        possibleObserver = c.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
        controller = c
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard let c = controller, !c.isPictureInPictureActive, c.isPictureInPicturePossible else { return }
        c.startPictureInPicture()
    }

    func stop() {
        guard let c = controller, c.isPictureInPictureActive else { return }
        c.stopPictureInPicture()
    }

    private func changed() {
        NotificationCenter.default.post(name: .pipChanged, object: nil)
    }

    // MARK: AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        starting = true
        changed()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        starting = false
        changed()
        onStarted?()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        starting = false
        changed()
        Toast.show(L10n.t("pip.failed"))
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        starting = false
        changed()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        onRestore?()
        completionHandler(true)
    }
}
