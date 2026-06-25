////////////////////////////////////////////////////////////////////////////////
//
// B L U N K I T O R
//
// Blunk's own compose window — a self-contained prose composer presented over the
// terminal. All typing happens here (system keyboard + dictation); sending writes the
// text + Enter straight to the active session. A control bar sits just above the keyboard
// (Cancel / Snips / Paste / Send), with a command-completion suggestions strip above it.
//
// This file is fully additive. Upstream Blink is touched only by small, flag-gated seams
// (see SmarterTermInput, WKWebView and SpaceController, all under Blunk.scratchOnly).
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
  private let controls = UIView()

  // The unsent draft survives closing the composer; it's cleared once the text is sent.
  private static var draft = ""
  private var didSend = false

  // Optional text to seed the composer with (used by the hardware-keyboard hand-off).
  private let seed: String

  // Suggestions strip (command completions), shown above the control bar only when non-empty.
  private let suggestionsScroll = UIScrollView()
  private let suggestionsStack = UIStackView()
  private var suggestionsHeight: NSLayoutConstraint!

  init(device: TermDevice, seed: String = "") {
    self.device = device
    self.seed = seed
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

    controls.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(controls)

    suggestionsHeight = suggestionsScroll.heightAnchor.constraint(equalToConstant: 0)

    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      textView.bottomAnchor.constraint(equalTo: suggestionsScroll.topAnchor),

      suggestionsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      suggestionsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      suggestionsScroll.bottomAnchor.constraint(equalTo: controls.topAnchor),
      suggestionsHeight,

      suggestionsStack.leadingAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.leadingAnchor, constant: 10),
      suggestionsStack.trailingAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.trailingAnchor, constant: -10),
      suggestionsStack.topAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.topAnchor),
      suggestionsStack.bottomAnchor.constraint(equalTo: suggestionsScroll.contentLayoutGuide.bottomAnchor),
      suggestionsStack.heightAnchor.constraint(equalTo: suggestionsScroll.frameLayoutGuide.heightAnchor),

      // A little breathing room above the keyboard.
      controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      controls.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
      controls.heightAnchor.constraint(equalToConstant: 50),
    ])

    _buildControls()

    let initial = Self.draft + seed
    textView.text = initial
    textView.selectedRange = NSRange(location: (initial as NSString).length, length: 0)
    _updateSuggestions()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: false)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    textView.becomeFirstResponder()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Keep the unsent draft so it's still there next time; clear it once sent.
    Self.draft = didSend ? "" : (textView.text ?? "")
    // Hand the first responder back to SpaceController so chain-dispatched commands
    // (config, etc.) keep working after the composer closes.
    navigationController?.presentingViewController?.becomeFirstResponder()
  }

  override var keyCommands: [UIKeyCommand]? {
    let sendCtrl = UIKeyCommand(input: "\r", modifierFlags: .control, action: #selector(sendAndClose))
    sendCtrl.wantsPriorityOverSystemBehavior = true
    let sendCmd = UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(sendAndClose))
    sendCmd.wantsPriorityOverSystemBehavior = true
    let esc = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(close))
    return [sendCtrl, sendCmd, esc]
  }

  // A tight control bar sitting just above the keyboard (back on the left, the rest right),
  // styled with the same round Blunkeys buttons so the whole app matches.
  private func _buildControls() {
    let back = _barButton(systemImage: "chevron.left", action: #selector(close))

    var rightItems: [UIView] = [_barButton(systemImage: "chevron.left.forwardslash.chevron.right", action: #selector(openSnips))]
    if UIPasteboard.general.hasStrings {
      rightItems.append(_barButton(systemImage: "doc.on.clipboard", action: #selector(pasteClipboard)))
    }
    rightItems.append(_barButton(systemImage: "paperplane.fill", action: #selector(sendAndClose)))

    let rightStack = UIStackView(arrangedSubviews: rightItems)
    rightStack.axis = .horizontal
    rightStack.spacing = 20
    rightStack.alignment = .center

    let spacer = UIView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let bar = UIStackView(arrangedSubviews: [back, spacer, rightStack])
    bar.axis = .horizontal
    bar.alignment = .center
    bar.translatesAutoresizingMaskIntoConstraints = false
    controls.addSubview(bar)
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 10),
      bar.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -10),
      bar.topAnchor.constraint(equalTo: controls.topAnchor),
      bar.bottomAnchor.constraint(equalTo: controls.bottomAnchor),
    ])
  }

  private func _barButton(systemImage: String, action: Selector) -> UIButton {
    let b = blunkeyRoundButton()
    b.setImage(UIImage(systemName: systemImage), for: .normal)
    b.setContentHuggingPriority(.required, for: .horizontal)
    b.addTarget(self, action: action, for: .touchUpInside)
    return b
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
    let picker = BlunkySnipsPicker(onPick: { [weak self] content in
      guard let self else { return }
      if !self.textView.isFirstResponder { self.textView.becomeFirstResponder() }
      self.textView.insertText(content)
    })
    present(UINavigationController(rootViewController: picker), animated: true)
  }

  @objc private func sendAndClose() {
    didSend = true
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

  private func _commandSuggestions() -> [String] {
    guard let range = _commandTokenRange(), range.length > 0 else { return [] }
    let word = (textView.text as NSString).substring(with: range)
    let matches = Complete._allCommands().filter { $0.hasPrefix(word) && $0 != word }
    return Array(matches.prefix(12))
  }

  // NSRange of the word at the cursor IF it sits in command position (line-leading), else nil.
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

// MARK: - Blunkitor's snippet gallery (accordion)
//
// Reads local snippets straight from disk: root-level `.blink/snippets/*.sh` first, then
// every nested folder that holds snips (shown by its full relative path, one open at a
// time, no indent). Tap inserts; swipe edits/deletes; `+` creates a brand-new snip in a
// dedicated editor (independent of the composer text).

final class BlunkySnipsPicker: UITableViewController {

  private enum Row {
    case folder(name: String, expanded: Bool)
    case snip(name: String, url: URL)
  }

  private struct Folder { let name: String; let snips: [(name: String, url: URL)] }

  private var rootSnips: [(name: String, url: URL)] = []
  private var folders: [Folder] = []
  private var expandedFolder: String?
  private var rows: [Row] = []

  private let onPick: (String) -> Void

  init(onPick: @escaping (String) -> Void) {
    self.onPick = onPick
    super.init(style: .plain)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Snips"
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newSnip))
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    _reloadFromDisk()
  }

  // One level only, matching upstream Blink: root-level `.sh` files, plus one tier of
  // folders each holding their own `.sh` snips.
  private func _reloadFromDisk() {
    rootSnips = []
    folders = []
    let fm = FileManager.default
    if let root = BlinkPaths.localSnippetsLocationURL(),
       let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
      for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
          let snips = ((try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension == "sh" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { (name: $0.deletingPathExtension().lastPathComponent, url: $0) }
          if !snips.isEmpty { folders.append(Folder(name: entry.lastPathComponent, snips: snips)) }
        } else if entry.pathExtension == "sh" {
          rootSnips.append((name: entry.deletingPathExtension().lastPathComponent, url: entry))
        }
      }
    }
    _rebuildRows()
  }

  private func _rebuildRows() {
    rows = rootSnips.map { .snip(name: $0.name, url: $0.url) }
    for folder in folders {
      let expanded = folder.name == expandedFolder
      rows.append(.folder(name: folder.name, expanded: expanded))
      if expanded { rows.append(contentsOf: folder.snips.map { .snip(name: $0.name, url: $0.url) }) }
    }
    tableView.reloadData()
  }

  @objc private func close() { dismiss(animated: true) }

  @objc private func newSnip() {
    let editor = BlunkySnipEditor(existingURL: nil, name: "", content: "") { [weak self] in self?._reloadFromDisk() }
    navigationController?.pushViewController(editor, animated: true)
  }

  private func _editSnip(_ url: URL) {
    let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let editor = BlunkySnipEditor(existingURL: url, name: BlunkySnipEditor.displayName(for: url), content: content) { [weak self] in
      self?._reloadFromDisk()
    }
    navigationController?.pushViewController(editor, animated: true)
  }

  // MARK: Table

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
    var config = cell.defaultContentConfiguration()
    switch rows[indexPath.row] {
    case .folder(let name, let expanded):
      config.text = name
      config.image = UIImage(systemName: "folder")
      config.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
      cell.contentConfiguration = config
      let chevron = UIImageView(image: UIImage(systemName: expanded ? "chevron.down" : "chevron.right"))
      chevron.tintColor = .tertiaryLabel
      cell.accessoryView = chevron
    case .snip(let name, _):
      config.text = name
      cell.contentConfiguration = config
      cell.accessoryView = nil
    }
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch rows[indexPath.row] {
    case .folder(let name, _):
      expandedFolder = (expandedFolder == name) ? nil : name   // accordion: only one open
      _rebuildRows()
    case .snip(_, let url):
      if let content = try? String(contentsOf: url, encoding: .utf8) {
        onPick(content)
        dismiss(animated: true)
      }
    }
  }

  override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    guard case .snip(_, let url) = rows[indexPath.row] else { return nil }

    let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, done in
      self?._editSnip(url); done(true)
    }
    edit.backgroundColor = .systemBlue

    let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
      let alert = UIAlertController(title: "Delete snip?", message: url.deletingPathExtension().lastPathComponent, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
      alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
        try? FileManager.default.removeItem(at: url)
        self?._reloadFromDisk()
        done(true)
      })
      self?.present(alert, animated: true)
    }

    return UISwipeActionsConfiguration(actions: [delete, edit])
  }
}

// MARK: - Snip editor (create + edit, independent of the composer)

final class BlunkySnipEditor: UIViewController {

  private let nameField = UITextField()
  private let contentView = UITextView()
  private let existingURL: URL?
  private let onSaved: () -> Void

  init(existingURL: URL?, name: String, content: String, onSaved: @escaping () -> Void) {
    self.existingURL = existingURL
    self.onSaved = onSaved
    super.init(nibName: nil, bundle: nil)
    nameField.text = name
    contentView.text = content
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // "folder/name" for a snip in a folder, or just "name" at the root (one level).
  static func displayName(for url: URL) -> String {
    let name = url.deletingPathExtension().lastPathComponent
    guard let root = BlinkPaths.localSnippetsLocationURL() else { return name }
    let parent = url.deletingLastPathComponent().standardizedFileURL
    if parent == root.standardizedFileURL { return name }
    return "\(parent.lastPathComponent)/\(name)"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = existingURL == nil ? "New snip" : "Edit snip"
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))

    nameField.placeholder = "name  or  folder/name"
    nameField.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
    nameField.autocapitalizationType = .none
    nameField.autocorrectionType = .no
    nameField.clearButtonMode = .whileEditing
    nameField.borderStyle = .roundedRect
    nameField.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(nameField)

    contentView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
    contentView.autocapitalizationType = .none
    contentView.autocorrectionType = .no
    contentView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
    contentView.layer.borderColor = UIColor.separator.cgColor
    contentView.layer.borderWidth = 1
    contentView.layer.cornerRadius = 8
    contentView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(contentView)

    NSLayoutConstraint.activate([
      nameField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      nameField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      nameField.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),

      contentView.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 12),
      contentView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      contentView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      contentView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if (nameField.text ?? "").isEmpty { nameField.becomeFirstResponder() } else { contentView.becomeFirstResponder() }
  }

  @objc private func save() {
    guard let raw = nameField.text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
          let root = BlinkPaths.localSnippetsLocationURL() else {
      _alert(title: "Name required"); return
    }
    // One level only: "folder/name" or "name".
    let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
    let folder = parts.count == 2 ? parts[0] : nil
    let name = parts.count == 2 ? parts[1] : parts[0]
    guard !name.isEmpty, !name.contains("/") else {
      _alert(title: "Use one level", message: "Name it \"name\" or \"folder/name\"."); return
    }
    let dir = folder.map { root.appendingPathComponent($0) } ?? root
    let newURL = dir.appendingPathComponent(name + ".sh")

    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try (contentView.text ?? "").write(to: newURL, atomically: true, encoding: .utf8)
    } catch {
      _alert(title: "Couldn't save", message: error.localizedDescription); return
    }
    // Renamed/moved: drop the old file.
    if let old = existingURL, old.standardizedFileURL != newURL.standardizedFileURL {
      try? FileManager.default.removeItem(at: old)
    }
    onSaved()
    navigationController?.popViewController(animated: true)
  }

  private func _alert(title: String, message: String? = nil) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
}

// MARK: - Opening Blunkitor

extension SpaceController {
  // Opened by the Blunkeys compose button, or by the hardware keyboard once typing exceeds
  // a single probe keystroke. A plain terminal tap is left untouched (select/copy works).
  func openBlunkitor(seed: String = "") {
    view.subviews.compactMap({ $0 as? BlunkeysBar }).first?.closeIfOpen()
    guard presentedViewController == nil, let device = currentDevice else { return }
    let composer = BlunkitorComposer(device: device, seed: seed)
    let nav = UINavigationController(rootViewController: composer)
    nav.modalPresentationStyle = .pageSheet
    if let sheet = nav.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
    }
    present(nav, animated: true)
  }
}

// MARK: - Hardware keyboard routing (Bluetooth)
//
// In keyboard-less terminal mode SpaceController is the first responder, so it receives
// hardware key presses. We route them so single-key TUI reactions keep working while
// real typing flows into Blunkitor:
//
//   • control combos / Return / Tab / Esc / arrows / Backspace  → straight to the agent
//   • the first printable keystroke                              → live to the agent (a probe)
//   • a second printable keystroke in quick succession          → open Blunkitor seeded with
//                                                                  both chars (the probe is erased)
//
// Send from Blunkitor with Ctrl+Enter (Enter inserts a newline).

enum BlunkKeyboard {
  private static var pendingChar: String?
  private static var resetItem: DispatchWorkItem?

  @discardableResult
  static func handle(_ presses: Set<UIPress>, device: TermDevice?, openComposer: (String) -> Void) -> Bool {
    guard let key = presses.first(where: { $0.key != nil })?.key else { return false }
    let mods = key.modifierFlags

    // Leave ⌘ shortcuts (new tab, etc.) to Blink.
    if mods.contains(.command) { return false }

    // Ctrl-combos pass through as their control byte.
    if mods.contains(.control) {
      guard let bytes = _controlBytes(for: key) else { return false }
      device?.write(bytes)
      _clearPending()
      return true
    }

    // Non-text keys go live to the agent/TUI.
    if let bytes = _specialBytes(for: key) {
      device?.write(bytes)
      _clearPending()
      return true
    }

    // Printable text.
    let text = key.characters
    guard !text.isEmpty, !(text.first?.isNewline ?? true) else { return false }

    if let first = pendingChar {
      // Second keystroke: hand off to Blunkitor, erasing the probe char already sent.
      _clearPending()
      device?.write("\u{7F}")
      openComposer(first + text)
    } else {
      // First keystroke: live to the agent, remembered briefly.
      device?.write(text)
      _setPending(text)
    }
    return true
  }

  private static func _setPending(_ s: String) {
    pendingChar = s
    resetItem?.cancel()
    let item = DispatchWorkItem { pendingChar = nil }
    resetItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
  }

  private static func _clearPending() {
    resetItem?.cancel()
    resetItem = nil
    pendingChar = nil
  }

  private static func _specialBytes(for key: UIKey) -> String? {
    switch key.keyCode {
    case .keyboardReturnOrEnter, .keypadEnter: return "\r"
    case .keyboardTab: return "\t"
    case .keyboardEscape: return "\u{1B}"
    case .keyboardDeleteOrBackspace: return "\u{7F}"
    case .keyboardUpArrow: return "\u{1B}[A"
    case .keyboardDownArrow: return "\u{1B}[B"
    case .keyboardRightArrow: return "\u{1B}[C"
    case .keyboardLeftArrow: return "\u{1B}[D"
    default: return nil
    }
  }

  private static func _controlBytes(for key: UIKey) -> String? {
    guard let scalar = key.charactersIgnoringModifiers.uppercased().unicodeScalars.first else { return nil }
    let v = scalar.value
    guard v >= 0x41, v <= 0x5A else { return nil }   // Ctrl+A ... Ctrl+Z
    return String(UnicodeScalar(v & 0x1F)!)
  }
}
