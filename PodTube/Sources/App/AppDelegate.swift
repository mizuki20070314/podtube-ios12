import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = BootViewController()
        win.makeKeyAndVisible()
        window = win
        return true
    }
}

/// Temporary root screen used while the app is being built up.
final class BootViewController: UIViewController {
    private let label = UILabel()

    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.06, alpha: 1)
        label.text = "PodTube"
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 28)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        InnerTube.shared.post("search", body: ["query": "test"]) { result in
            DispatchQueue.main.async {
                switch result {
                case .success: self.label.text = "PodTube\nAPI OK"
                case .failure(let e): self.label.text = "PodTube\n\(e)"
                }
                self.label.numberOfLines = 0
            }
        }
    }
}
