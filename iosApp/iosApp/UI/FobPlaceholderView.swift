import UIKit

/// Placeholder fob area shown when no USDZ/GLB model is available.
/// Tap = unlock, 700 ms long press = lock.
final class FobPlaceholderView: UIView {

    private let onTap: () -> Void
    private let onLongPress: () -> Void
    private let cardView = UIView()
    private let iconView = UIImageView()

    init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        cardView.backgroundColor = UIColor.secondarySystemFill
        cardView.layer.cornerRadius = 20
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.10
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .light)
        iconView.image = UIImage(systemName: "lock.rectangle.on.rectangle", withConfiguration: config)
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.7
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(tap)
        addGestureRecognizer(long)
        tap.require(toFail: long)
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap()
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            onLongPress()
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            setPressed(true)
        case .ended, .cancelled:
            setPressed(false)
        default:
            break
        }
    }

    private func setPressed(_ pressed: Bool) {
        UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            self.cardView.layer.shadowRadius = pressed ? 3 : 12
            self.cardView.transform = CGAffineTransform(scaleX: pressed ? 0.97 : 1.0, y: pressed ? 0.97 : 1.0)
        }
    }
}
