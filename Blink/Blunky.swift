////////////////////////////////////////////////////////////////////////////////
//
// B L U N K I T O R
//
// Blunk's own compose window — a self-contained prose composer presented over the
// terminal. All typing happens here (system keyboard + dictation); sending writes the
// text + Enter straight to the active session. While you type a command, a suggestions
// strip offers Blink command completions (shown only when there is something to suggest).
//
// This file is fully additive. Upstream Blink is touched only by two thin seams:
//   1. SmarterTermInput.becomeFirstResponder returns false in Blunk.scratchOnly mode
//   2. WKWebViewGesturesInteraction._on1fTap routes a terminal tap to openBlunkitor
// (plus SpaceController being first responder in Blunk mode so chain-dispatched
//  commands like `config` keep working — see SpaceController.swift.)
//
// Part of Blunk, a fork of Blink (GPLv3).
//
////////////////////////////////////////////////////////////////////////////////

import UIKit

// Blunk-wide feature flag. Set to false to fall back to stock Blink input
// (on-terminal keyboard + SmartKeys bar).
enum Blunk {
  // The terminal is input-less: a tap opens the Blunkitor composer instead of the keyboard.
  static let scratchOnly = true
}

// MARK: - The Blunkitor composer window

final class BlunkitorComposer: UIViewController, UITextViewDelegate {

  private weak var device: TermDevice?
  private let textView = UITextView()
  private var snippetsVC: SnippetsViewController?

  // Suggestions strip (command completions), shown above the keyboard only when non-empty.
  private let suggestionsScroll = UIScrollView()
  private let suggestionsStack = UIStackView()
  private var suggestionsHeight: NSLayoutConstraint!

  init(device: TermDevice) {
    self.device = device
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    textView.delegate = self
    textView.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
    textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
    textView.autocapitalizationType = .sentences
    textView.autocorrectionType = .yes
    textView.smartQuotesType = .yes
    textView.smartDashesType = .yes
    textView.keyboardDismissMode = .interactive
    textView.alwaysBounceVertical = true
    textView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(textView)

    suggestionsScroll.translatesAutoresizingMaskIntoConstraints = false
    suggestionsScroll.showsHorizontalScrollIndicator = false
    suggestionsScroll.clipsToBounds = true
    suggestionsScroll.backgroundColor = .secondarySystemBackground
    view.addSubview(suggestionsScroll)

    suggestionsStack.axis = .horizontal
    suggestionsStack.spacing = 8
    suggestionsStack.alignment = .center
    suggestionsStack.translatesAutoresizingMaskIntoConstraints = false
    suggestionsScroll.addSubview(suggestionsStack)

    suggestionsHeight = suggestionsScroll.heightAnchor.constraint(equalToConstant: 0)

    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      textView.bottomAnchor.constraint(equalTo: suggestionsScroll.topAnchor),

      suggestionsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      suggestionsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      suggestionsScroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      suggestionsHeight,

      suggestionsStack.leadingAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.leadingAnchor, constant: 10),
      suggestionsStack.trailingAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.trailingAnchor, constant: -10),
      suggestionsStack.topAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.topAnchor),
      suggestionsStack.bottomAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.bottomAnchor),
      suggestionsStack.heightAnchor.constraint(equalTo: suggestionsScroll.frameLayoutGuide.heightAnchor),
    ])

    _updateBars()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    textView.becomeFirstResponder()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Hand the first responder back to SpaceController so chain-dispatched commands
    // (config, etc.) keep working after the composer closes.
    navigationController?.presentingViewController?.becomeFirstResponder()
  }

  override var keyCommands: [UIKeyCommand]? {
    let send = UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(sendAndClose))
    send.wantsPriorityOverSystemBehavior = true
    let esc = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(close))
    return [send, esc]
  }

  private func _updateBars() {
    let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
    let snips = UIBarButtonItem(title: "Snips", style: .plain, target: self, action: #selector(openSnips))

    var left: [UIBarButtonItem] = [cancel, snips]
    if UIPasteboard.general.hasStrings {
      left.append(
        UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"),
                        style: .plain, target: self, action: #selector(pasteClipboard))
      )
    }
    navigationItem.leftBarButtonItems = left

    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(image: UIImage(systemName: "paperplane.fill"),
                      style: .plain, target: self, action: #selector(sendAndClose))
    ]
  }

  // MARK: Actions

  @objc private func close() {
    dismiss(animated: true)
  }

  @objc private func pasteClipboard() {
    guard let s = UIPasteboard.general.string, !s.isEmpty else { return }
    if !textView.isFirstResponder { textView.becomeFirstResponder() }
    textView.insertText(s)
  }

  @objc private func openSnips() {
    let picker = BlunkySnipsPicker(
      onPick: { [weak self] content in
        guard let self else { return }
        if !self.textView.isFirstResponder { self.textView.becomeFirstResponder() }
        self.textView.insertText(content)
      },
      currentText: { [weak self] in self?.textView.text ?? "" }
    )
    present(UINavigationController(rootViewController: picker), animated: true)
  }

  @objc private func sendAndClose() {
    let text = textView.text ?? ""
    let device = self.device
    device?.write(text)
    // Trail the Enter so the agent doesn't read it as part of the same paste burst.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      device?.write("\r")
    }
    dismiss(animated: true)
  }

  // MARK: Suggestions (command completion)

  func textViewDidChange(_ textView: UITextView) {
    _updateSuggestions()
  }

  private func _updateSuggestions() {
    let items = _commandSuggestions()
    suggestionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    if items.isEmpty {
      suggestionsHeight.constant = 0
    } else {
      items.forEach { suggestionsStack.addArrangedSubview(_chip($0)) }
      suggestionsHeight.constant = 44
    }
  }

  private func _chip(_ text: String) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(text, for: .normal)
    b.titleLabel?.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
    b.setTitleColor(UIColor(white: 0.1, alpha: 1), for: .normal)
    b.backgroundColor = UIColor(white: 0.93, alpha: 1)
    b.layer.cornerRadius = 14
    b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
    b.addAction(UIAction { [weak self] _ in self?._applySuggestion(text) }, for: .touchUpInside)
    return b
  }

  // Blink command completions for the word being typed in command position.
  private func _commandSuggestions() -> [String] {
    guard let range = _commandTokenRange(), range.length > 0 else { return [] }
    let word = (textView.text as NSString).substring(with: range)
    let matches = Complete._allCommands().filter { $0.hasPrefix(word) && $0 != word }
    return Array(matches.prefix(12))
  }

  // NSRange of the word at the cursor IF it sits in command position (line-leading),
  // otherwise nil. Used both to compute suggestions and to replace on apply.
  private func _commandTokenRange() -> NSRange? {
    guard textView.selectedRange.length == 0 else { return nil }
    let ns = textView.text as NSString
    let cursor = textView.selectedRange.location
    guard cursor <= ns.length else { return nil }

    func isSpace(_ i: Int) -> Bool {
      let c = ns.substring(with: NSRange(location: i, length: 1))
      return c == " " || c == "\t" || c == "\n"
    }

    var start = cursor
    while start > 0, !isSpace(start - 1) { start -= 1 }

    // Command position: only spaces/tabs between the line start and the token.
    var i = start
    while i > 0 {
      let c = ns.substring(with: NSRange(location: i - 1, length: 1))
      if c == "\n" { break }
      if c != " " && c != "\t" { return nil }
      i -= 1
    }
    return NSRange(location: start, length: cursor - start)
  }

  private func _applySuggestion(_ command: String) {
    guard let range = _commandTokenRange() else { return }
    let ns = textView.text as NSString
    let replacement = command + " "
    textView.text = ns.replacingCharacters(in: range, with: replacement)
    let newCursor = range.location + (replacement as NSString).length
    textView.selectedRange = NSRange(location: newCursor, length: 0)
    _updateSuggestions()
  }
}

// MARK: - Blunkitor's own snippet gallery
//
// Reads local snippets straight from disk (.blink/snippets/<folder>/<name>.sh), inserts
// the chosen one into the composer, and can save the current text as a new snip.

final class BlunkySnipsPicker: UITableViewController {

  private var items: [(name: String, url: URL)] = []
  private let onPick: (String) -> Void
  private let currentText: () -> String

  init(onPick: @escaping (String) -> Void, currentText: @escaping () -> String) {
    self.onPick = onPick
    self.currentText = currentText
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Snips"
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(saveCurrent))
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    _reload()
  }

  private func _reload() {
    items = []
    let fm = FileManager.default
    if let root = BlinkPaths.localSnippetsLocationURL(),
       let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
      for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for f in files where f.pathExtension == "sh" {
          items.append((name: "\(folder.lastPathComponent)/\(f.deletingPathExtension().lastPathComponent)", url: f))
        }
      }
    }
    items.sort { $0.name < $1.name }
    tableView.reloadData()
  }

  @objc private func close() { dismiss(animated: true) }

  @objc private func saveCurrent() {
    let text = currentText()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let alert = UIAlertController(title: "Save snip", message: "Name (folder/name)", preferredStyle: .alert)
    alert.addTextField { $0.placeholder = "blunky/my-snip" }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
      guard let self,
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
            let root = BlinkPaths.localSnippetsLocationURL() else { return }
      let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
      let folder = parts.count == 2 ? parts[0] : "blunky"
      let name = parts.count == 2 ? parts[1] : parts[0]
      let folderURL = root.appendingPathComponent(folder)
      try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
      try? text.write(to: folderURL.appendingPathComponent(name + ".sh"), atomically: true, encoding: .utf8)
      self._reload()
    })
    present(alert, animated: true)
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    items.isEmpty ? 1 : items.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
    var config = cell.defaultContentConfiguration()
    if items.isEmpty {
      config.text = "No snips yet — tap + to save the current text."
      config.textProperties.color = .secondaryLabel
      cell.selectionStyle = .none
    } else {
      config.text = items[indexPath.row].name
      cell.selectionStyle = .default
    }
    cell.contentConfiguration = config
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard !items.isEmpty, let content = try? String(contentsOf: items[indexPath.row].url, encoding: .utf8) else { return }
    onPick(content)
    dismiss(animated: true)
  }
}

// MARK: - Seam target: open Blunkitor from a terminal tap

extension SpaceController {
  @objc func openBlunkitor() {
    // A tap while a Blunkeys pad is open just dismisses the pad — never opens the composer.
    if let bar = view.subviews.compactMap({ $0 as? BlunkeysBar }).first, bar.closeIfOpen() {
      return
    }
    guard presentedViewController == nil, let device = currentDevice else { return }
    let composer = BlunkitorComposer(device: device)
    let nav = UINavigationController(rootViewController: composer)
    nav.modalPresentationStyle = .pageSheet
    if let sheet = nav.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
    }
    present(nav, animated: true)
  }
}
