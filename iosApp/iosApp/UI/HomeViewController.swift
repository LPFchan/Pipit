import UIKit

final class HomeViewController: UIViewController {

    private let onGearTap: () -> Void
    private let onFobTap: () -> Void
    private let onFobLongPress: () -> Void
    private let showTapHint: Bool
    private let onHintDismissed: () -> Void

    private let stackView = UIStackView()
    private let gearButton = UIButton(type: .system)
    private let fobPlaceholderView: FobPlaceholderView
    private let tapHintLabel = UILabel()

    init(
        onGearTap: @escaping () -> Void,
        onFobTap: @escaping () -> Void,
        onFobLongPress: @escaping () -> Void,
        showTapHint: Bool,
        onHintDismissed: @escaping () -> Void = {}
    ) {
        self.onGearTap = onGearTap
        self.onFobTap = onFobTap
        self.onFobLongPress = onFobLongPress
        self.showTapHint = showTapHint
        self.onHintDismissed = onHintDismissed
        self.fobPlaceholderView = FobPlaceholderView(
            onTap: { [weak self] in
                self?.onHintDismissed()
                self?.tapHintLabel.isHidden = true
                onFobTap()
            },
            onLongPress: { [weak self] in
                self?.onHintDismissed()
                self?.tapHintLabel.isHidden = true
                onFobLongPress()
            }
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        gearButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        gearButton.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gearButton)
        NSLayoutConstraint.activate([
            gearButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            gearButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        ])

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        stackView.addArrangedSubview(fobPlaceholderView)
        fobPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fobPlaceholderView.widthAnchor.constraint(equalToConstant: 200),
            fobPlaceholderView.heightAnchor.constraint(equalToConstant: 140)
        ])

        tapHintLabel.text = "Tap · Hold to lock"
        tapHintLabel.font = .preferredFont(forTextStyle: .caption1)
        tapHintLabel.textColor = .secondaryLabel
        tapHintLabel.isHidden = !showTapHint
        stackView.addArrangedSubview(tapHintLabel)
    }

    @objc private func gearTapped() {
        onGearTap()
    }
}
