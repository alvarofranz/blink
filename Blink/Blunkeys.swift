////////////////////////////////////////////////////////////////////////////////
//
// B L U N K E Y S
//
// Floating round buttons on the main terminal view. Each fires keys LIVE to the
// agent/TUI on tap — no composer, no select.
//
//   bottom-left:  ⌃ (special)  123 (numbers)  abc (letters)  ↕ (arrows)
//   bottom-right: ⏎ (direct Enter, on its own)
//
// ⌃/123/abc pop a clean pad and auto-close after one key. ↕ stays open for repeated
// arrows; close it by tapping ↕ again or tapping outside. A tap outside an open pad
// only dismisses it — it never opens the composer (see SpaceController.openBlunkitor).
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

    // Standalone Enter — bottom-right, on its own.
    let enter = blunkeyRoundButton()
    enter.setTitle("⏎", for: .normal)
    enter.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    enter.translatesAutoresizingMaskIntoConstraints = false
    enter.addAction(UIAction { [weak sc] _ in sc?.currentDevice?.write("\r") }, for: .touchUpInside)
    sc.view.addSubview(enter)

    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
      bar.bottomAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
      enter.trailingAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
      enter.bottomAnchor.constraint(equalTo: sc.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
    ])
    sc.view.bringSubviewToFront(bar)
    sc.view.bringSubviewToFront(enter)
  }
}

// Shared style for the floating round buttons.
private func blunkeyRoundButton() -> UIButton {
  let b = UIButton(type: .system)
  b.tintColor = UIColor(white: 0.12, alpha: 1)
  b.setTitleColor(UIColor(white: 0.12, alpha: 1), for: .normal)
  b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
  b.backgroundColor = UIColor(white: 0.97, alpha: 0.92)
  b.layer.cornerRadius = 21
  b.layer.shadowColor = UIColor.black.cgColor
  b.layer.shadowOpacity = 0.18
  b.layer.shadowRadius = 4
  b.layer.shadowOffset = CGSize(width: 0, height: 1)
  b.translatesAutoresizingMaskIntoConstraints = false
  b.widthAnchor.constraint(equalToConstant: 42).isActive = true
  b.heightAnchor.constraint(equalToConstant: 42).isActive = true
  return b
}

final class BlunkeysBar: UIStackView {

  enum Kind { case special, numbers, letters, arrows }

  private weak var spaceController: SpaceController?
  private let pad = BlunkeysPad()
  private var shownKind: Kind? = nil

  init(spaceController: SpaceController) {
    self.spaceController = spaceController
    super.init(frame: .zero)
    axis = .vertical
    spacing = 10
    alignment = .leading

    pad.isHidden = true
    pad.onKey = { [weak self] bytes in
      guard let self else { return }
      self._send(bytes)
      if self.shownKind != .arrows { self._closePad() }   // arrows stays open
    }
    addArrangedSubview(pad)

    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = 10
    row.addArrangedSubview(_padButton(.special, title: "⌃", systemImage: nil))
    row.addArrangedSubview(_padButton(.numbers, title: "123", systemImage: nil))
    row.addArrangedSubview(_padButton(.letters, title: "abc", systemImage: nil))
    row.addArrangedSubview(_padButton(.arrows, title: "↕", systemImage: "dpad"))
    addArrangedSubview(row)
  }

  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // Called from openBlunkitor: if a pad is open, a terminal tap should only close it.
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

  private func _toggle(_ kind: Kind) {
    if shownKind == kind { _closePad() } else { _showPad(kind) }
  }

  private func _showPad(_ kind: Kind) {
    shownKind = kind
    pad.configure(rows: Self._rows(for: kind))
    pad.isHidden = false
  }

  private func _closePad() {
    shownKind = nil
    pad.isHidden = true
  }

  private func _send(_ bytes: String) {
    spaceController?.currentDevice?.write(bytes)
  }

  private static func _rows(for kind: Kind) -> [[(String, String)]] {
    switch kind {
    case .special:
      return [
        [("Esc", "\u{1B}"), ("Tab", "\t")],
        [("⌃C", "\u{03}"), ("⌃D", "\u{04}")],
      ]
    case .numbers:
      return [
        [("1", "1"), ("2", "2"), ("3", "3")],
        [("4", "4"), ("5", "5"), ("6", "6")],
        [("7", "7"), ("8", "8"), ("9", "9")],
        [("0", "0")],
      ]
    case .letters:
      return [
        [("y", "y"), ("n", "n"), ("a", "a")],
        [("c", "c"), ("q", "q"), ("d", "d")],
        [("e", "e"), ("s", "s"), ("p", "p")],
      ]
    case .arrows:
      return [
        [("←", "\u{1B}[D"), ("↑", "\u{1B}[A"), ("↓", "\u{1B}[B"), ("→", "\u{1B}[C")],
      ]
    }
  }
}

// A clean elegant box holding a grid of real key buttons. Each fires onKey live.
final class BlunkeysPad: UIView {

  var onKey: ((String) -> Void)?

  private let rowsStack = UIStackView()

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
    rowsStack.alignment = .leading
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

  func configure(rows: [[(String, String)]]) {
    rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for row in rows {
      let rowStack = UIStackView()
      rowStack.axis = .horizontal
      rowStack.spacing = 8
      for (label, bytes) in row {
        rowStack.addArrangedSubview(_key(label, bytes))
      }
      rowsStack.addArrangedSubview(rowStack)
    }
  }

  private func _key(_ label: String, _ bytes: String) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(label, for: .normal)
    b.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
    b.setTitleColor(UIColor(white: 0.1, alpha: 1), for: .normal)
    b.backgroundColor = .white
    b.layer.cornerRadius = 10
    b.layer.borderWidth = 0.5
    b.layer.borderColor = UIColor(white: 0.82, alpha: 1).cgColor
    b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    b.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
    b.heightAnchor.constraint(equalToConstant: 46).isActive = true
    b.addAction(UIAction { [weak self] _ in self?.onKey?(bytes) }, for: .touchUpInside)
    return b
  }
}
