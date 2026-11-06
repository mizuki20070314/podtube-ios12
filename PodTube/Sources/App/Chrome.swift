import UIKit
import AVKit

/// Android-style top app bar: logo on the left, AirPlay ("cast") + search on the right.
final class AppBarView: UIView {
    static let contentHeight: CGFloat = 56

    private let logo = UIImageView(image: Icons.logoMark(height: 20))
    private let titleLabel = UILabel()
    let searchButton = IconButton(icon: "search")
    private let routePicker = AVRoutePickerView()
    private let divider = UIView()
    var onSearch: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.text = "PodTube"
        titleLabel.font = Theme.font(20, .bold)
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        routePicker.activeTintColor = Theme.red
        addSubviews([logo, titleLabel, routePicker, searchButton, divider])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        backgroundColor = Theme.background
        titleLabel.textColor = Theme.text
        routePicker.tintColor = Theme.text
        divider.backgroundColor = Theme.divider
    }

    @objc private func searchTapped() { onSearch?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        var top: CGFloat = 0
        if #available(iOS 11.0, *) { top = safeAreaInsets.top }
        let h = AppBarView.contentHeight
        let cy = top + h / 2
        logo.frame = CGRect(x: 12, y: cy - 10, width: 28, height: 20)
        titleLabel.sizeToFit()
        titleLabel.frame = CGRect(x: 46, y: cy - titleLabel.frame.height / 2, width: titleLabel.frame.width, height: titleLabel.frame.height)
        searchButton.frame = CGRect(x: bounds.width - 48, y: cy - 22, width: 44, height: 44)
        routePicker.frame = CGRect(x: bounds.width - 48 - 44, y: cy - 22, width: 44, height: 44)
        divider.frame = CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
    }
}

/// Bottom navigation bar: Home / Shorts / Subscriptions / You.
final class TabBarView: UIView {
    struct Item {
        let title: String
        let icon: String
        let iconSelected: String
    }

    static let contentHeight: CGFloat = 49

    private var items: [Item] = []
    private var controls: [UIControl] = []
    private var icons: [UIImageView] = []
    private var labels: [UILabel] = []
    private let divider = UIView()
    private(set) var selectedIndex = 0
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(divider)
        NotificationCenter.default.addObserver(self, selector: #selector(restyle), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    func setItems(_ items: [Item]) {
        controls.forEach { $0.removeFromSuperview() }
        controls = []
        icons = []
        labels = []
        self.items = items
        for (i, it) in items.enumerated() {
            let c = UIControl()
            c.tag = i
            c.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            let iv = UIImageView(image: Icons.image(it.icon, size: 24))
            iv.isUserInteractionEnabled = false
            let l = UILabel()
            l.text = it.title
            l.font = Theme.font(10)
            l.textAlignment = .center
            l.isUserInteractionEnabled = false
            c.addSubview(iv)
            c.addSubview(l)
            addSubview(c)
            controls.append(c)
            icons.append(iv)
            labels.append(l)
        }
        restyle()
        setNeedsLayout()
    }

    func select(_ index: Int) {
        selectedIndex = index
        restyle()
    }

    @objc private func tapped(_ c: UIControl) {
        onSelect?(c.tag)
    }

    @objc private func restyle() {
        backgroundColor = Theme.background
        divider.backgroundColor = Theme.divider
        for (i, it) in items.enumerated() {
            let sel = i == selectedIndex
            icons[i].image = Icons.image(sel ? it.iconSelected : it.icon, size: 24)
            icons[i].tintColor = sel ? Theme.text : Theme.secondaryText
            labels[i].textColor = sel ? Theme.text : Theme.secondaryText
            labels[i].font = Theme.font(10, sel ? .medium : .regular)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        divider.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 0.5)
        guard !controls.isEmpty else { return }
        let n = CGFloat(controls.count)
        var w = bounds.width / n
        var x0: CGFloat = 0
        if GridLayout.isRegular(width: bounds.width) {
            // an iPad: the items stay a hand apart in the middle of the bar instead of spreading over the whole width
            w = min(w, 100)
            x0 = ((bounds.width - w * n) / 2).rounded()
        }
        for (i, c) in controls.enumerated() {
            c.frame = CGRect(x: x0 + CGFloat(i) * w, y: 0, width: w, height: TabBarView.contentHeight)
            icons[i].frame = CGRect(x: (w - 24) / 2, y: 7, width: 24, height: 24)
            labels[i].frame = CGRect(x: 0, y: 32, width: w, height: 13)
        }
    }
}
