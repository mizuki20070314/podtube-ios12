import UIKit
import CoreImage

/// QR code of a short text, drawn crisp (no interpolation) on white.
enum QRCode {
    static func image(_ text: String, side: CGFloat) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(text.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        UIGraphicsBeginImageContextWithOptions(CGSize(width: side, height: side), true, 0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.interpolationQuality = .none
        UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

/// Google sign-in with the "limited input device" flow (the one YouTube on TV uses): the app shows a short code,
/// the user approves it on google.com/device (in Safari on this device or on any other device) and the app polls
/// until Google hands out the tokens. The Google password is never typed into this app.
final class SignInViewController: UIViewController {
    private let scroll = UIScrollView()
    private let introLabel = UILabel()
    private let step1Label = UILabel()
    private let urlButton = UIButton(type: .system)
    private let qrView = UIImageView()
    private let step2Label = UILabel()
    private let codeLabel = UILabel()
    private let copyButton = PillButton(icon: "content_copy", title: L10n.t("signin.copy"))
    private let openButton = PillButton(icon: "open_in_new", title: L10n.t("signin.open"))
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .gray)
    private let retryButton = PillButton(icon: "refresh", title: L10n.t("signin.newCode"))
    private let noteLabel = UILabel()

    private var code: DeviceCode?
    private var interval: TimeInterval = 5
    private var generation = 0
    private var finished = false
    private var qrText = "https://www.google.com/device"
    private var qrSide: CGFloat = 0
    /// CI screenshots: a fixed code and no network.
    private let demoCode: DeviceCode?

    init(demoCode: DeviceCode? = nil) {
        self.demoCode = demoCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("signin.title")
        introLabel.text = L10n.t("signin.intro")
        step1Label.text = L10n.t("signin.step1")
        step2Label.text = L10n.t("signin.step2")
        noteLabel.text = L10n.t("signin.note")
        for l in [introLabel, step1Label, step2Label, statusLabel, noteLabel] { l.numberOfLines = 0 }
        introLabel.font = Theme.font(15)
        step1Label.font = Theme.font(14, .semibold)
        step2Label.font = Theme.font(14, .semibold)
        statusLabel.font = Theme.font(14)
        statusLabel.textAlignment = .center
        noteLabel.font = Theme.font(12)
        codeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        codeLabel.textAlignment = .center
        codeLabel.adjustsFontSizeToFitWidth = true
        codeLabel.minimumScaleFactor = 0.6
        codeLabel.layer.cornerRadius = 12
        codeLabel.clipsToBounds = true
        urlButton.titleLabel?.font = Theme.font(17, .semibold)
        urlButton.setTitle("google.com/device", for: .normal)
        urlButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        qrView.contentMode = .scaleAspectFit
        qrView.layer.cornerRadius = 8
        qrView.clipsToBounds = true
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.isHidden = true
        spinner.hidesWhenStopped = true
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        view.addSubview(scroll)
        scroll.addSubviews([introLabel, step1Label, urlButton, qrView, step2Label, codeLabel, copyButton, openButton,
                            statusLabel, spinner, retryButton, noteLabel])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(miniPlayerChanged), name: .miniPlayerChanged, object: nil)
        miniPlayerChanged()
        start()
    }

    @objc private func miniPlayerChanged() {
        let inset = Router.shared.root?.miniPlayerInset ?? 0
        scroll.contentInset.bottom = inset
        scroll.scrollIndicatorInsets.bottom = inset
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed { generation += 1 }
    }

    @objc private func applyTheme() {
        view.backgroundColor = Theme.background
        introLabel.textColor = Theme.text
        step1Label.textColor = Theme.text
        step2Label.textColor = Theme.text
        statusLabel.textColor = Theme.secondaryText
        noteLabel.textColor = Theme.secondaryText
        codeLabel.textColor = Theme.text
        codeLabel.backgroundColor = Theme.surface
        urlButton.setTitleColor(Theme.link, for: .normal)
        spinner.style = Theme.isDark ? .white : .gray
    }

    // MARK: Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        let w = min(view.bounds.width, 480)
        let x0 = (view.bounds.width - w) / 2
        let pad: CGFloat = 20
        let tw = w - pad * 2
        // a 320x568 iPod touch leaves ~450 pt for this page: tighten it so the code is on the first screen
        let compact = tw < 320 || view.bounds.height < 600
        let side: CGFloat = compact ? 112 : 150
        var y: CGFloat = compact ? 8 : 16

        func place(_ label: UILabel) {
            let h = TextMetrics.height(label.text ?? "", font: label.font, width: tw, maxLines: 0)
            label.frame = CGRect(x: x0 + pad, y: y, width: tw, height: h)
            y += h
        }

        place(introLabel)
        y += compact ? 10 : 18
        place(step1Label)
        y += compact ? 0 : 4
        urlButton.frame = CGRect(x: x0 + pad, y: y, width: tw, height: compact ? 36 : 40)
        urlButton.contentHorizontalAlignment = .left
        y += compact ? 36 : 44
        if qrSide != side {
            qrSide = side
            qrView.image = QRCode.image(qrText, side: side)
        }
        qrView.frame = CGRect(x: x0 + pad, y: y, width: side, height: side)
        let ow = min(openButton.sizeThatFits(.zero).width, tw - side - 14)
        copyButton.isHidden = false
        openButton.frame = CGRect(x: x0 + pad + side + 14, y: y + (compact ? 10 : 20), width: ow, height: 36)
        y += side + (compact ? 10 : 20)
        place(step2Label)
        y += compact ? 6 : 8
        let codeH: CGFloat = compact ? 60 : 72
        codeLabel.frame = CGRect(x: x0 + pad, y: y, width: tw, height: codeH)
        y += codeH + (compact ? 8 : 10)
        let cw = copyButton.sizeThatFits(.zero).width
        copyButton.frame = CGRect(x: x0 + pad, y: y, width: cw, height: 36)
        y += 36 + (compact ? 12 : 18)
        place(statusLabel)
        spinner.frame = CGRect(x: x0 + w / 2 - 10, y: y + 4, width: 20, height: 20)
        y += 32
        let rw = retryButton.sizeThatFits(.zero).width
        retryButton.frame = CGRect(x: x0 + (w - rw) / 2, y: y, width: rw, height: 36)
        y += 36 + 18
        place(noteLabel)
        y += 24
        scroll.contentSize = CGSize(width: view.bounds.width, height: y)
    }

    // MARK: Flow

    private func setStatus(_ text: String, busy: Bool, retry: Bool = false) {
        statusLabel.text = text
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
        retryButton.isHidden = !retry
        view.setNeedsLayout()
    }

    private func showCode(_ c: DeviceCode) {
        code = c
        interval = max(c.interval, 3)
        codeLabel.text = c.userCode
        urlButton.setTitle(c.verificationURL.replacingOccurrences(of: "https://", with: ""), for: .normal)
        qrText = c.verificationURL
        qrSide = 0 // redrawn by the next layout pass
        setStatus(L10n.t("signin.waiting"), busy: true)
    }

    private func start() {
        generation += 1
        let gen = generation
        code = nil
        codeLabel.text = "···-···-····"
        if let demo = demoCode {
            showCode(demo)
            return
        }
        setStatus(L10n.t("signin.getting"), busy: true)
        AuthSession.shared.requestDeviceCode { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                switch result {
                case .success(let c):
                    self.showCode(c)
                    self.schedulePoll(gen)
                case .failure(let e):
                    self.setStatus(L10n.t("signin.failed") + "\n" + e.localizedDescription, busy: false, retry: true)
                }
            }
        }
    }

    private func schedulePoll(_ gen: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in self?.poll(gen) }
    }

    @objc private func appBecameActive() {
        // coming back from Safari: do not wait for the next timer tick
        if code != nil, !finished { poll(generation, reschedule: false) }
    }

    private func poll(_ gen: Int, reschedule: Bool = true) {
        guard gen == generation, !finished, let c = code, demoCode == nil else { return }
        if Date() > c.expiresAt {
            start()
            return
        }
        AuthSession.shared.pollToken(c) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation, !self.finished else { return }
                switch result {
                case .success:
                    self.finish()
                case .failure(let e):
                    switch e as? AuthError {
                    case .some(.pending):
                        if reschedule { self.schedulePoll(gen) }
                    case .some(.slowDown):
                        self.interval += 5
                        if reschedule { self.schedulePoll(gen) }
                    case .some(.denied):
                        self.generation += 1
                        self.setStatus(L10n.t("signin.denied"), busy: false, retry: true)
                    case .some(.expired):
                        self.start()
                    default:
                        // transient problem (offline, 5xx): keep trying until the code expires
                        self.setStatus(L10n.t("signin.waiting") + "\n" + e.localizedDescription, busy: true)
                        if reschedule { self.schedulePoll(gen) }
                    }
                }
            }
        }
    }

    private func finish() {
        finished = true
        generation += 1
        setStatus(L10n.t("signin.finishing"), busy: true)
        Account.shared.didSignIn()
        Toast.show(L10n.t("signin.done"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            if let nav = self.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self.dismiss(animated: true, completion: nil)
            }
        }
    }

    // MARK: Actions

    @objc private func copyTapped() {
        guard let c = code else { return }
        UIPasteboard.general.string = c.userCode
        Toast.show(L10n.t("signin.copied"))
    }

    @objc private func openTapped() {
        let urlString = code?.verificationURL ?? "https://www.google.com/device"
        if let u = URL(string: urlString) { UIApplication.shared.open(u, options: [:], completionHandler: nil) }
    }

    @objc private func retryTapped() {
        finished = false
        start()
    }
}
