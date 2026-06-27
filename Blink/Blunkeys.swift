////////////////////////////////////////////////////////////////////////////////
//
// B L U N K E Y S
//
// Floating round buttons on the main terminal view. Tapping one pops a clean centered
// pad of real key buttons; each key fires LIVE to the agent/TUI on tap.
//
//   bottom-left:  ⌃ (special keys + a Blunkopy/Tabs/Settings column)  123  abc  ↕ (arrows)  ⏎ (Enter)
//   bottom-right: ✎ (a larger button that opens Blunkitor)
//
// ⌃/123/abc auto-close after a key; the arrows d-pad stays open for repeated presses.
// While a pad is open, a transparent overlay dismisses it when the terminal is tapped.
// A plain terminal tap is otherwise left to Blink, so select/copy keeps working.
//
// Fully additive: installed with one line in SpaceController.viewDidLoad.
//
// Part of Blunk, a fork of Blink (GPLv3).
//
////////////////////////////////////////////////////////////////////////////////

import UIKit

enum Blunkeys {
  static func install(in sc: SpaceController) {
    // Pad cluster — bottom-left.
    let bar = BlunkeysBar(spaceController: sc)
    bar.translatesAutoresizingMaskIntoConstraints = false
    sc.view.addSubview(bar)

    // Standalone, larger compose button — bottom-right, on its own.
    let compose = blunkeyRoundButton(diameter: 68)
    compose.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
    compose.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 24), forImageIn: .normal)
    compose.translatesAutoresizingMaskIntoConstraints = false
    compose.addAction(UIAction { [weak sc] _ in sc?.openBlunkitor() }, for: .touchUpInside)
    sc.view.addSubview(compose)

    bar.chrome = [compose]   // kept tappable above the dismiss overlay

    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
      bar.bottomAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
      compose.trailingAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
      compose.bottomAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
    ])
    sc.view.bringSubviewToFront(bar)
    sc.view.bringSubviewToFront(compose)
  }
}

// Shared style for the floating round buttons — the Blunk house style, reused by the
// Blunkitor control bar so everything matches.
func blunkeyRoundButton(diameter: CGFloat = 42) -> UIButton {
  let b = UIButton(type: .system)
  b.tintColor = UIColor(white: 0.12, alpha: 1)
  b.setTitleColor(UIColor(white: 0.12, alpha: 1), for: .normal)
  b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
  b.backgroundColor = UIColor(white: 0.97, alpha: 0.92)
  b.layer.cornerRadius = diameter / 2
  b.layer.shadowColor = UIColor.black.cgColor
  b.layer.shadowOpacity = 0.18
  b.layer.shadowRadius = 4
  b.layer.shadowOffset = CGSize(width: 0, height: 1)
  b.translatesAutoresizingMaskIntoConstraints = false
  b.widthAnchor.constraint(equalToConstant: diameter).isActive = true
  b.heightAnchor.constraint(equalToConstant: diameter).isActive = true
  return b
}

final class BlunkeysBar: UIStackView {

  enum Kind { case special, numbers, letters, arrows }

  // Sibling Blunkeys views (e.g. Enter) to keep above the dismiss overlay.
  var chrome: [UIView] = []

  private weak var spaceController: SpaceController?
  private let pad = BlunkeysPad()
  private let padContainer = UIStackView()
  private let overlay = UIView()
  private lazy var sideColumn = _makeSideColumn()
  private var shownKind: Kind?

  init(spaceController: SpaceController) {
    self.spaceController = spaceController
    super.init(frame: .zero)
    axis = .horizontal
    spacing = 10
    alignment = .center

    pad.onKey = { [weak self] bytes in
      guard let self else { return }
      self.spaceController?.currentDevice?.write(bytes)
      if self.shownKind != .arrows { self._closePad() }   // arrows stays open
    }

    addArrangedSubview(_padButton(.special, title: "⌃", systemImage: nil))
    addArrangedSubview(_padButton(.numbers, title: "123", systemImage: nil))
    addArrangedSubview(_padButton(.letters, title: "abc", systemImage: nil))
    addArrangedSubview(_padButton(.arrows, title: "↕", systemImage: "dpad"))
    addArrangedSubview(_enterButton())
  }

  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @discardableResult
  func closeIfOpen() -> Bool {
    guard shownKind != nil else { return false }
    _closePad()
    return true
  }

  private func _padButton(_ kind: Kind, title: String?, systemImage: String?) -> UIButton {
    let b = blunkeyRoundButton()
    if let systemImage, let img = UIImage(systemName: systemImage) {
      b.setImage(img, for: .normal)
    } else if let title {
      b.setTitle(title, for: .normal)
    }
    b.addAction(UIAction { [weak self] _ in self?._toggle(kind) }, for: .touchUpInside)
    return b
  }

  private func _enterButton() -> UIButton {
    let b = blunkeyRoundButton()
    b.setTitle("⏎", for: .normal)
    b.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    b.addAction(UIAction { [weak self] _ in self?.spaceController?.currentDevice?.write("\r") }, for: .touchUpInside)
    return b
  }

  private func _toggle(_ kind: Kind) {
    if shownKind == kind { _closePad() } else { _showPad(kind) }
  }

  // The pad floats centered in the viewport, a comfortable gap above the buttons. A
  // transparent overlay behind it dismisses the pad when the terminal is tapped.
  private func _installPad() {
    guard padContainer.superview == nil, let sv = superview else { return }

    overlay.translatesAutoresizingMaskIntoConstraints = false
    overlay.backgroundColor = .clear
    overlay.isHidden = true
    overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(_overlayTapped)))
    sv.addSubview(overlay)

    padContainer.axis = .horizontal
    padContainer.spacing = 14
    padContainer.alignment = .center
    padContainer.translatesAutoresizingMaskIntoConstraints = false
    sv.addSubview(padContainer)

    NSLayoutConstraint.activate([
      overlay.topAnchor.constraint(equalTo: sv.topAnchor),
      overlay.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
      overlay.bottomAnchor.constraint(equalTo: sv.bottomAnchor),

      padContainer.centerXAnchor.constraint(equalTo: sv.centerXAnchor),
      padContainer.bottomAnchor.constraint(equalTo: topAnchor, constant: -64),
    ])
  }

  private func _showPad(_ kind: Kind) {
    _installPad()
    shownKind = kind

    padContainer.arrangedSubviews.forEach {
      padContainer.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    if kind == .arrows { pad.configureArrows() }
    else { pad.configure(rows: Self._rows(for: kind), round: false) }

    // Special keys come paired with a side column (Blunkopy + Tabs + Settings) on the left.
    if kind == .special { padContainer.addArrangedSubview(sideColumn) }
    padContainer.addArrangedSubview(pad)

    overlay.isHidden = false
    padContainer.isHidden = false
    if let sv = superview {
      sv.bringSubviewToFront(overlay)
      chrome.forEach { sv.bringSubviewToFront($0) }
      sv.bringSubviewToFront(self)
      sv.bringSubviewToFront(padContainer)
    }
  }

  private func _closePad() {
    shownKind = nil
    padContainer.isHidden = true
    overlay.isHidden = true
  }

  @objc private func _overlayTapped() { _closePad() }

  // Left-hand column shown next to the special keys: Blunkopy + Tabs + Settings.
  private func _makeSideColumn() -> UIView {
    let box = UIView()
    box.backgroundColor = UIColor(white: 0.97, alpha: 0.97)
    box.layer.cornerRadius = 18
    box.layer.shadowColor = UIColor.black.cgColor
    box.layer.shadowOpacity = 0.22
    box.layer.shadowRadius = 9
    box.layer.shadowOffset = CGSize(width: 0, height: 3)

    let stack = UIStackView(arrangedSubviews: [
      _actionButton("Blunkopy", "doc.on.doc") { [weak self] in self?.spaceController?.openBlunkopy() },
      _actionButton("Tabs", "rectangle.stack") { [weak self] in self?.spaceController?.openQuickActions() },
      _actionButton("Settings", "gearshape") { [weak self] in self?.spaceController?.openSettings() },
    ])
    stack.axis = .vertical
    stack.spacing = 8
    stack.alignment = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
      stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
      stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
    ])
    return box
  }

  private func _actionButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> UIButton {
    var config = UIButton.Configuration.plain()
    config.image = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
    config.imagePlacement = .top
    config.imagePadding = 5
    config.baseForegroundColor = UIColor(white: 0.12, alpha: 1)
    config.background.backgroundColor = .white
    config.background.cornerRadius = 12
    config.background.strokeColor = UIColor(white: 0.82, alpha: 1)
    config.background.strokeWidth = 0.5
    config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 6, bottom: 9, trailing: 6)
    var titleAttr = AttributeContainer()
    titleAttr.font = .systemFont(ofSize: 11, weight: .medium)
    config.attributedTitle = AttributedString(title, attributes: titleAttr)

    let b = UIButton(configuration: config)
    b.addAction(UIAction { _ in action() }, for: .touchUpInside)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 74).isActive = true
    b.heightAnchor.constraint(equalToConstant: 56).isActive = true
    return b
  }

  private static func _rows(for kind: Kind) -> [[(String, String)?]] {
    switch kind {
    case .numbers:
      return [
        [("0", "0"), ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4")],
        [("5", "5"), ("6", "6"), ("7", "7"), ("8", "8"), ("9", "9")],
      ]
    case .letters:
      return [
        [("y", "y"), ("n", "n"), ("a", "a"), ("c", "c")],
        [("d", "d"), ("e", "e"), ("q", "q"), ("s", "s")],
        [("p", "p"), ("r", "r"), ("o", "o"), ("k", "k")],
        [("l", "l"), ("v", "v"), ("h", "h"), ("m", "m")],
      ]
    case .special:
      return [
        [("Esc", "\u{1B}"), ("Tab", "\t"), ("␣", " "), ("^C", "\u{03}")],
        [("^D", "\u{04}"), ("^R", "\u{12}"), ("^L", "\u{0C}"), ("^Z", "\u{1A}")],
        [("^A", "\u{01}"), ("^E", "\u{05}"), ("^K", "\u{0B}"), ("^U", "\u{15}")],
        [("^W", "\u{17}"), ("^P", "\u{10}"), ("^N", "\u{0E}"), ("^G", "\u{07}")],
      ]
    case .arrows:
      return [
        [nil, ("↑", "\u{1B}[A"), nil],
        [("←", "\u{1B}[D"), nil, ("→", "\u{1B}[C")],
        [nil, ("↓", "\u{1B}[B"), nil],
      ]
    }
  }
}

// A clean box of real key buttons; each fires onKey live. Grids (numbers/letters/special)
// use a rounded-rect box; the arrows use a circular box with a tight d-pad cross.
final class BlunkeysPad: UIView {

  var onKey: ((String) -> Void)?

  private let rowsStack = UIStackView()
  private var extras: [UIView] = []
  private var sizeConstraints: [NSLayoutConstraint] = []
  private var isCircular = false

  init() {
    super.init(frame: .zero)
    backgroundColor = UIColor(white: 0.97, alpha: 0.97)
    layer.cornerRadius = 18
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.22
    layer.shadowRadius = 9
    layer.shadowOffset = CGSize(width: 0, height: 3)

    rowsStack.axis = .vertical
    rowsStack.spacing = 8
    rowsStack.alignment = .center
    rowsStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(rowsStack)
    NSLayoutConstraint.activate([
      rowsStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    if isCircular { layer.cornerRadius = min(bounds.width, bounds.height) / 2 }
  }

  private func _reset() {
    rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    extras.forEach { $0.removeFromSuperview() }
    extras = []
    NSLayoutConstraint.deactivate(sizeConstraints)
    sizeConstraints = []
  }

  // Grid layout (rounded-rect box). `nil` cells are invisible spacers.
  func configure(rows: [[(String, String)?]], round: Bool) {
    _reset()
    isCircular = false
    layer.cornerRadius = 18
    rowsStack.isHidden = false
    for row in rows {
      let rowStack = UIStackView()
      rowStack.axis = .horizontal
      rowStack.spacing = 8
      for cell in row {
        if let cell { rowStack.addArrangedSubview(_key(cell.0, cell.1, round: round)) }
        else { rowStack.addArrangedSubview(_spacer()) }
      }
      rowsStack.addArrangedSubview(rowStack)
    }
    setNeedsLayout()
  }

  // Circular d-pad: four round arrows clustered tightly around the centre.
  func configureArrows() {
    _reset()
    isCircular = true
    rowsStack.isHidden = true

    let r: CGFloat = 40
    let up = _key("↑", "\u{1B}[A", round: true)
    let down = _key("↓", "\u{1B}[B", round: true)
    let left = _key("←", "\u{1B}[D", round: true)
    let right = _key("→", "\u{1B}[C", round: true)
    [up, down, left, right].forEach { addSubview($0); extras.append($0) }

    NSLayoutConstraint.activate([
      up.centerXAnchor.constraint(equalTo: centerXAnchor),
      up.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -r),
      down.centerXAnchor.constraint(equalTo: centerXAnchor),
      down.centerYAnchor.constraint(equalTo: centerYAnchor, constant: r),
      left.centerYAnchor.constraint(equalTo: centerYAnchor),
      left.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -r),
      right.centerYAnchor.constraint(equalTo: centerYAnchor),
      right.centerXAnchor.constraint(equalTo: centerXAnchor, constant: r),
    ])
    sizeConstraints = [
      widthAnchor.constraint(equalToConstant: 140),
      heightAnchor.constraint(equalToConstant: 140),
    ]
    NSLayoutConstraint.activate(sizeConstraints)
    setNeedsLayout()
  }

  private func _key(_ label: String, _ bytes: String, round: Bool) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(label, for: .normal)
    b.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
    b.titleLabel?.adjustsFontSizeToFitWidth = true
    b.titleLabel?.minimumScaleFactor = 0.6
    b.setTitleColor(UIColor(white: 0.1, alpha: 1), for: .normal)
    b.backgroundColor = .white
    b.layer.cornerRadius = round ? 23 : 10
    b.layer.borderWidth = 0.5
    b.layer.borderColor = UIColor(white: 0.82, alpha: 1).cgColor
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 46).isActive = true
    b.heightAnchor.constraint(equalToConstant: 46).isActive = true
    b.addAction(UIAction { [weak self] _ in self?.onKey?(bytes) }, for: .touchUpInside)
    return b
  }

  private func _spacer() -> UIView {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.widthAnchor.constraint(equalToConstant: 46).isActive = true
    v.heightAnchor.constraint(equalToConstant: 46).isActive = true
    return v
  }
}
