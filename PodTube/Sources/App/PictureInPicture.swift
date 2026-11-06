import UIKit
import AVKit
import AVFoundation
import MachO

extension Notification.Name {
    static let pipChanged = Notification.Name("PodTubePipChanged")
}

/// Picture in Picture of the video layer, through the system's own `AVPictureInPictureController` (iOS 9 and later).
/// Whether a device may use it is the OS's decision, not the app's: iPads since iOS 9, iPhones and iPod touches since iOS 14.
/// Where the OS says no, `isSupported` is false and the player shows no PiP button.
final class PictureInPicture: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PictureInPicture()

    /// Jailbroken devices where ForceInPicture is loaded into the app but its MobileGestalt hook did not take
    /// (seen on an iPod touch 6 / iOS 12.5.7: the Objective-C hook applied, the function hook did not). There
    /// the app answers AVKit's "is PiP supported" itself, with the Objective-C runtime; this is only tried when
    /// the OS says no and a ForceInPicture library is inside the process.
    private(set) static var overrideApplied = false

    private static let installOverride: Void = {
        var tweak = false
        for i in 0..<_dyld_image_count() {
            if let p = _dyld_get_image_name(i), String(cString: p).lowercased().contains("forceinpicture") { tweak = true }
        }
        guard tweak, !AVPictureInPictureController.isPictureInPictureSupported(),
              let m = class_getClassMethod(AVPictureInPictureController.self, NSSelectorFromString("isPictureInPictureSupported")) else { return }
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        method_setImplementation(m, imp_implementationWithBlock(yes))
        overrideApplied = true
    }()

    /// With the override, the button is only offered if AVKit then really hands out a controller.
    private static let overrideWorks: Bool = AVPictureInPictureController(playerLayer: AVPlayerLayer()) != nil

    static var isSupported: Bool {
        _ = installOverride
        return overrideApplied ? overrideWorks : AVPictureInPictureController.isPictureInPictureSupported()
    }

    private static func imageName(of p: UnsafeRawPointer) -> String {
        var info = Dl_info()
        guard dladdr(p, &info) != 0, let f = info.dli_fname else { return "?" }
        return (String(cString: f) as NSString).lastPathComponent
    }

    /// Lines for the connection diagnostics: why the OS says no. Shows whether a tweak loader and ForceInPicture
    /// are inside this process at all, and what MobileGestalt answers for the key ForceInPicture rewrites.
    static func diagnosis() -> [String] {
        var lines: [String] = []
        _ = installOverride
        lines.append("PodTube's own override of AVKit's PiP check: " + (overrideApplied ? "applied" : "not applied")
                     + (overrideApplied ? (overrideWorks ? " (AVKit then creates the controller)" : " (AVKit still refuses to create the controller)") : ""))
        var u = utsname()
        _ = uname(&u)
        let model = withUnsafePointer(to: &u.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        lines.append("device \(model), iOS \(UIDevice.current.systemVersion)")
        let keys = ["forceinpicture", "pipenabler", "substitute", "substrate", "libhooker", "tweakinject", "ellekit"]
        var found: [String] = []
        for i in 0..<_dyld_image_count() {
            guard let p = _dyld_get_image_name(i) else { continue }
            let path = String(cString: p)
            if keys.contains(where: { path.lowercased().contains($0) }) { found.append((path as NSString).lastPathComponent) }
        }
        lines.append("tweak libraries in this app: " + (found.isEmpty ? "none (no tweak loader or tweak is injected into PodTube)" : found.joined(separator: ", ")))
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "MGGetBoolAnswer") {
            typealias MG = @convention(c) (CFString) -> Bool
            let mg = unsafeBitCast(sym, to: MG.self)
            lines.append("MobileGestalt PiP key: " + (mg("nVh/gwNpy7Jv1NOk00CMrw" as CFString) ? "YES" : "NO"))
            // a function patched by a tweak loader starts with a jump (typically ldr x16 = 58...., br x16 = d61f0200)
            let code = sym.assumingMemoryBound(to: UInt32.self)
            lines.append("MGGetBoolAnswer starts: " + (0..<4).map { String(format: "%08x", code[$0]) }.joined(separator: " ")
                         + " in " + imageName(of: sym))
        } else {
            lines.append("MobileGestalt PiP key: MGGetBoolAnswer not found")
        }
        for (cls, sel, meta) in [("AVPlayerController", "isPictureInPictureSupported", false),
                                 ("AVPictureInPictureController", "isPictureInPictureSupported", true)] {
            guard let c = NSClassFromString(cls) else { lines.append("\(cls): class not loaded"); continue }
            guard let m = meta ? class_getClassMethod(c, Selector(sel)) : class_getInstanceMethod(c, Selector(sel)) else {
                lines.append("\(cls) \(sel): no such method"); continue
            }
            lines.append("\(cls) \(sel) is implemented in " + imageName(of: unsafeBitCast(method_getImplementation(m), to: UnsafeRawPointer.self)))
        }
        lines.append("AVPictureInPictureController(playerLayer:) → " + (AVPictureInPictureController(playerLayer: AVPlayerLayer()) == nil ? "nil" : "created"))
        return lines
    }

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
