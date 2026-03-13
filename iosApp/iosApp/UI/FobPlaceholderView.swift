import UIKit

/// Placeholder 3D fob area: tap = unlock, 700ms long press = lock. Button depression and haptics.
final class FobPlaceholderView: UIView {

    private let onTap: () -> Void
    private let onLongPress: () -> Void
    private let cardView = UIView()
    private let label = UILabel()
    private var pressedOffset: NSLayoutConstraint?

    init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        cardView.backgroundColor = .secondarySystemFill
        cardView.layer.cornerRadius = 16
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.15
        cardView.layer.shadowRadius = 8
        cardView.layer.shadowOffset = CGSize(width: 0, height: 4)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        label.text = "Uguisu\n(placeholder)"
        label.numberOfLines = 2
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
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
        UIView.animate(withDuration: 0.08) {
            self.cardView.layer.shadowRadius = pressed ? 2 : 8
            self.cardView.transform = CGAffineTransform(translationX: 0, y: pressed ? 4 : 0)
        }
    }
}
