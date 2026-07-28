import Cocoa

protocol TabWindowControllerDelegate: AnyObject {
    /// Asks the app to create a note (placement/config lives in AppDelegate).
    func tabWindowCreateNote(_ controller: TabWindowController) -> PostItNote
    func tabWindowRequestsHide(_ controller: TabWindowController)
}

/// Single window that gathers every note into a tab bar, each tab labelled
/// with the note title. Notes themselves are untouched - the same NoteService
/// backs both this and the floating-window mode.
class TabWindowController: NSWindowController {

    private let noteService: NoteService
    private let configService: ConfigService
    weak var tabDelegate: TabWindowControllerDelegate?

    private var tabBarView: DraggableTitleBarView!
    private var tabScrollView: NSScrollView!
    private var tabsContainer: NSView!
    private var editorContainer: NSView!

    private var tabButtons: [TabButton] = []
    private var editors: [UUID: NoteEditorViewController] = [:]
    private(set) var activeEditor: NoteEditorViewController?
    private var selectedNoteId: UUID?

    private let tabBarHeight: CGFloat = 60
    private let tabHeight: CGFloat = 38
    private let tabSpacing: CGFloat = 4

    private var emptyStateLabel: NSTextField!

    /// Only open notes get tabs; closed ones live in the Closed Notes menu.
    private var notes: [PostItNote] { return noteService.getOpenNotes() }

    static let defaultSize = NSSize(width: 720, height: 480)

    init(noteService: NoteService, configService: ConfigService) {
        self.noteService = noteService
        self.configService = configService

        let frame = TabWindowController.initialFrame(configService: configService)
        let window = TabHostWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.minSize = NSSize(width: 380, height: 260)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear

        super.init(window: window)
        window.delegate = self

        setupUI()
        reloadTabs()

        NotificationCenter.default.addObserver(self, selector: #selector(windowGeometryChanged(_:)), name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowGeometryChanged(_:)), name: NSWindow.didResizeNotification, object: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func initialFrame(configService: ConfigService) -> NSRect {
        if let saved = configService.getTabWindowFrame() {
            let rect = NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
            // Only reuse it if it is still on a connected display
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                return rect
            }
        }
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.midX - defaultSize.width / 2,
            y: visible.midY - defaultSize.height / 2,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }

    // MARK: - UI

    private func setupUI() {
        guard let window = self.window else { return }

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(hex: "#FFFF88")?.cgColor
        window.contentView = container

        // Tab bar (also the window's drag handle)
        tabBarView = DraggableTitleBarView()
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        tabBarView.wantsLayer = true
        container.addSubview(tabBarView)
        tabBarView.addGestureRecognizer(makeWindowDragGesture())

        // Hide-window button
        let hideBtn = NSButton(frame: .zero)
        hideBtn.translatesAutoresizingMaskIntoConstraints = false
        hideBtn.isBordered = false
        hideBtn.title = "\u{2013}"
        hideBtn.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        hideBtn.target = self
        hideBtn.action = #selector(hideWindowClicked(_:))
        hideBtn.toolTip = "Hide window"
        tabBarView.addSubview(hideBtn)

        // New note button
        let newBtn = NSButton(frame: .zero)
        newBtn.translatesAutoresizingMaskIntoConstraints = false
        newBtn.isBordered = false
        newBtn.title = "+"
        newBtn.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        newBtn.target = self
        newBtn.action = #selector(newNoteClicked(_:))
        newBtn.toolTip = "New note"
        tabBarView.addSubview(newBtn)

        // Scrollable strip of tabs
        tabsContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: tabBarHeight))
        tabsContainer.addGestureRecognizer(makeWindowDragGesture())

        // Legacy (always-visible) scroller so overflowing tabs are discoverable.
        // It occupies the bottom strip of the tab bar, which is why the bar is
        // tall enough to keep the tabs themselves fully readable above it.
        tabScrollView = TabStripScrollView()
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.drawsBackground = false
        tabScrollView.borderType = .noBorder
        tabScrollView.hasVerticalScroller = false
        tabScrollView.hasHorizontalScroller = true
        tabScrollView.autohidesScrollers = true
        tabScrollView.scrollerStyle = .legacy
        tabScrollView.verticalScrollElasticity = .none
        tabScrollView.horizontalScrollElasticity = .allowed
        tabScrollView.documentView = tabsContainer
        tabBarView.addSubview(tabScrollView)

        // Editor host
        editorContainer = NSView()
        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.wantsLayer = true
        container.addSubview(editorContainer)

        // Shown when every note has been closed
        emptyStateLabel = NSTextField(labelWithString: "No open notes.\nUse + for a new note, or reopen one from Closed Notes.")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = NSFont.systemFont(ofSize: 12)
        emptyStateLabel.textColor = NSColor.black.withAlphaComponent(0.45)
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.isHidden = true
        editorContainer.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            tabBarView.topAnchor.constraint(equalTo: container.topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: tabBarHeight),

            hideBtn.trailingAnchor.constraint(equalTo: tabBarView.trailingAnchor, constant: -6),
            hideBtn.centerYAnchor.constraint(equalTo: tabBarView.centerYAnchor),
            hideBtn.widthAnchor.constraint(equalToConstant: 22),

            newBtn.trailingAnchor.constraint(equalTo: hideBtn.leadingAnchor, constant: -2),
            newBtn.centerYAnchor.constraint(equalTo: tabBarView.centerYAnchor),
            newBtn.widthAnchor.constraint(equalToConstant: 22),

            tabScrollView.leadingAnchor.constraint(equalTo: tabBarView.leadingAnchor, constant: 6),
            tabScrollView.trailingAnchor.constraint(equalTo: newBtn.leadingAnchor, constant: -4),
            tabScrollView.topAnchor.constraint(equalTo: tabBarView.topAnchor),
            tabScrollView.bottomAnchor.constraint(equalTo: tabBarView.bottomAnchor),

            editorContainer.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            editorContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: editorContainer.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: editorContainer.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: editorContainer.leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: editorContainer.trailingAnchor, constant: -12)
        ])

        // Added last so it stays on top: widens the resize grab area at the edges
        ResizeBorderView.install(in: container)
    }

    // MARK: - Tabs

    /// Rebuilds the whole tab strip and keeps (or repairs) the selection.
    func reloadTabs() {
        let current = notes
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons = []

        for note in current {
            let btn = makeTabButton(for: note)
            tabsContainer.addSubview(btn)
            tabButtons.append(btn)
        }
        layoutTabs()

        emptyStateLabel?.isHidden = !current.isEmpty

        if let selected = selectedNoteId, current.contains(where: { $0.id == selected }) {
            selectNote(id: selected)
        } else if let first = current.first {
            selectNote(id: first.id)
        } else {
            selectedNoteId = nil
            activeEditor?.view.removeFromSuperview()
            activeEditor = nil
        }
    }

    private func makeTabButton(for note: PostItNote) -> TabButton {
        let btn = TabButton(frame: .zero)
        btn.noteId = note.id
        btn.tabController = self
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.borderWidth = 1
        btn.target = self
        btn.action = #selector(tabClicked(_:))
        applyTabAppearance(btn, note: note, selected: note.id == selectedNoteId)
        return btn
    }

    private func label(for note: PostItNote) -> String {
        if let editor = editors[note.id] { return editor.displayTitle }
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return NoteEditorViewController.contentSummary(note.content)
    }

    private func applyTabAppearance(_ btn: TabButton, note: PostItNote, selected: Bool) {
        let text = label(for: note)
        btn.toolTip = text

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: 12, weight: selected ? .bold : .regular)
        btn.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: selected ? NSColor.black : NSColor.black.withAlphaComponent(0.55)
        ])

        let base = NSColor(hex: note.color) ?? NSColor(hex: "#FFFF88")!
        btn.layer?.backgroundColor = selected ? base.cgColor : base.withAlphaComponent(0.45).cgColor
        btn.layer?.borderColor = selected
            ? NSColor.black.withAlphaComponent(0.35).cgColor
            : NSColor.black.withAlphaComponent(0.12).cgColor

        btn.preferredWidth = TabWindowController.tabWidth(for: text, font: font)
    }

    private static func tabWidth(for title: String, font: NSFont) -> CGFloat {
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return min(170, max(70, ceil(textWidth) + 22))
    }

    private func layoutTabs() {
        guard let scrollView = tabScrollView else { return }

        let totalWidth = tabButtons.reduce(CGFloat(0)) { $0 + $1.preferredWidth + tabSpacing }

        // Size the document view first: whether the tabs overflow decides if the
        // scroller is shown, which in turn decides the clip view's height.
        tabsContainer.frame = NSRect(x: 0, y: 0,
                                     width: max(totalWidth, scrollView.frame.width),
                                     height: scrollView.contentView.bounds.height)
        scrollView.tile()

        let clipHeight = scrollView.contentView.bounds.height
        tabsContainer.setFrameSize(NSSize(width: tabsContainer.frame.width, height: clipHeight))

        var x: CGFloat = 0
        let y = max(0, (clipHeight - tabHeight) / 2)
        for btn in tabButtons {
            btn.frame = NSRect(x: x, y: y, width: btn.preferredWidth, height: tabHeight)
            x += btn.preferredWidth + tabSpacing
        }
    }

    private func refreshTab(for noteId: UUID) {
        guard let btn = tabButtons.first(where: { $0.noteId == noteId }),
              let note = notes.first(where: { $0.id == noteId }) else { return }
        applyTabAppearance(btn, note: note, selected: noteId == selectedNoteId)
        layoutTabs()
    }

    // MARK: - Selection

    func selectNote(id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        selectedNoteId = id

        let editor: NoteEditorViewController
        if let cached = editors[id] {
            editor = cached
        } else {
            editor = NoteEditorViewController(note: note, noteService: noteService)
            editor.delegate = self
            editors[id] = editor
        }

        if activeEditor !== editor {
            activeEditor?.view.removeFromSuperview()
            editor.view.translatesAutoresizingMaskIntoConstraints = false
            editorContainer.addSubview(editor.view)
            NSLayoutConstraint.activate([
                editor.view.topAnchor.constraint(equalTo: editorContainer.topAnchor),
                editor.view.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
                editor.view.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
                editor.view.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor)
            ])
            activeEditor = editor
        }

        // Repaint every tab so the selected one stands out
        for btn in tabButtons {
            if let n = notes.first(where: { $0.id == btn.noteId }) {
                applyTabAppearance(btn, note: n, selected: btn.noteId == id)
            }
        }
        layoutTabs()
        applyWindowColor(editor.noteColor)

        if let btn = tabButtons.first(where: { $0.noteId == id }) {
            btn.scrollToVisible(btn.bounds)
        }
    }

    func selectTab(at index: Int) {
        let current = notes
        guard index >= 0, index < current.count else { return }
        selectNote(id: current[index].id)
    }

    func selectNextTab() {
        let current = notes
        guard let selected = selectedNoteId,
              let idx = current.firstIndex(where: { $0.id == selected }),
              !current.isEmpty else { return }
        selectNote(id: current[(idx + 1) % current.count].id)
    }

    func selectPreviousTab() {
        let current = notes
        guard let selected = selectedNoteId,
              let idx = current.firstIndex(where: { $0.id == selected }),
              !current.isEmpty else { return }
        selectNote(id: current[(idx - 1 + current.count) % current.count].id)
    }

    private func applyWindowColor(_ hex: String) {
        guard let color = NSColor(hex: hex) else { return }
        window?.contentView?.layer?.backgroundColor = color.cgColor
        tabBarView?.layer?.backgroundColor = color.blended(withFraction: 0.22, of: .black)?.cgColor
    }

    // MARK: - Actions

    @objc private func tabClicked(_ sender: TabButton) {
        guard let id = sender.noteId else { return }
        selectNote(id: id)
        activeEditor?.focusContent()
    }

    @objc private func newNoteClicked(_ sender: NSButton) {
        addNewNote()
    }

    @objc func addNewNote() {
        guard let delegate = tabDelegate else { return }
        let note = delegate.tabWindowCreateNote(self)
        selectedNoteId = note.id
        reloadTabs()
        activeEditor?.focusContent()
    }

    @objc private func hideWindowClicked(_ sender: NSButton) {
        tabDelegate?.tabWindowRequestsHide(self)
    }

    @objc func closeNoteFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        closeNote(id: id)
    }

    @objc func deleteNoteFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let note = notes.first(where: { $0.id == id }) else { return }

        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Note"
        alert.informativeText = "\u{201C}\(label(for: note))\u{201D} will be permanently deleted. This cannot be undone."
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "Delete")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        deleteButton.hasDestructiveAction = true
        deleteButton.keyEquivalent = ""
        cancelButton.keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.deleteNote(id: id)
        }
    }

    private func closeNote(id: UUID) {
        detachTab(id: id, deleting: false)
    }

    private func deleteNote(id: UUID) {
        detachTab(id: id, deleting: true)
    }

    /// Removes a tab either by closing (note kept, marked closed) or deleting.
    private func detachTab(id: UUID, deleting: Bool) {
        let removedIndex = notes.firstIndex(where: { $0.id == id })
        // Acting on a background tab must not yank the user off the tab they are on
        let stayOn = (activeEditor?.noteId != id) ? activeEditor?.noteId : nil

        if let editor = editors[id] {
            if activeEditor === editor {
                editor.view.removeFromSuperview()
                activeEditor = nil
            }
            if deleting { editor.deleteNoteFromStorage() }
            editors.removeValue(forKey: id)
        } else if deleting {
            noteService.deleteNote(id: id)
        }
        if !deleting { noteService.setClosed(id: id, closed: true) }

        let remaining = notes
        if remaining.isEmpty {
            selectedNoteId = nil
        } else if let keep = stayOn, remaining.contains(where: { $0.id == keep }) {
            selectedNoteId = keep
        } else {
            selectedNoteId = remaining[min(removedIndex ?? 0, remaining.count - 1)].id
        }
        reloadTabs()
    }

    /// Brings a closed note back as a tab and selects it.
    func reopenNote(id: UUID) {
        noteService.setClosed(id: id, closed: false)
        selectedNoteId = id
        reloadTabs()
        activeEditor?.focusContent()
    }

    // MARK: - Window

    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero

    private func makeWindowDragGesture() -> NSPanGestureRecognizer {
        let gesture = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        gesture.delegate = self
        return gesture
    }

    @objc private func handleDrag(_ gesture: NSPanGestureRecognizer) {
        guard let window = self.window else { return }
        if gesture.state == .began {
            initialMouseLocation = NSEvent.mouseLocation
            initialWindowOrigin = window.frame.origin
        }
        let currentMouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: initialWindowOrigin.x + (currentMouse.x - initialMouseLocation.x),
            y: initialWindowOrigin.y + (currentMouse.y - initialMouseLocation.y)
        ))
    }

    @objc private func windowGeometryChanged(_ notification: Notification) {
        guard let frame = window?.frame else { return }
        configService.setTabWindowFrame(WindowFrame(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.size.width),
            height: Double(frame.size.height)
        ))
        layoutTabs()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - NSGestureRecognizerDelegate
extension TabWindowController: NSWindowDelegate {
    /// The window is shared by every tab, so the undo stack follows whichever
    /// note is currently selected.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        return activeEditor?.contentUndoManager
    }
}

// MARK: - NSGestureRecognizerDelegate
extension TabWindowController: NSGestureRecognizerDelegate {
    /// The window-drag pan sits on an ancestor of the tab scroll view, so without
    /// this it would recognize mid-drag and steal tracking from the scrollbar -
    /// dragging the scroller would move the window instead of scrolling.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard let root = window?.contentView else { return true }
        var hit = root.hitTest(root.convert(event.locationInWindow, from: nil))
        while let view = hit {
            if view is NSScroller { return false }
            hit = view.superview
        }
        return true
    }
}

// MARK: - NoteEditorDelegate
extension TabWindowController: NoteEditorDelegate {
    func noteEditorRequestsNewNote(_ editor: NoteEditorViewController) {
        addNewNote()
    }

    func noteEditorRequestsClose(_ editor: NoteEditorViewController) {
        closeNote(id: editor.noteId)
    }

    func noteEditorRequestsDelete(_ editor: NoteEditorViewController) {
        deleteNote(id: editor.noteId)
    }

    func noteEditorDidChangeTitle(_ editor: NoteEditorViewController) {
        refreshTab(for: editor.noteId)
    }

    func noteEditorDidChangeColor(_ editor: NoteEditorViewController) {
        refreshTab(for: editor.noteId)
        if editor === activeEditor {
            applyWindowColor(editor.noteColor)
        }
    }
}

// MARK: - Tab strip: scrolls horizontally from a plain vertical wheel too
class TabStripScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
            super.scrollWheel(with: event)
            return
        }
        let maxX = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
        let newX = min(max(0, contentView.bounds.origin.x - event.scrollingDeltaY), maxX)
        contentView.scroll(to: NSPoint(x: newX, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
    }
}

// MARK: - Tab button with a right-click menu
class TabButton: NSButton {
    var noteId: UUID!
    weak var tabController: TabWindowController?
    var preferredWidth: CGFloat = 100

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(TabWindowController.closeNoteFromMenu(_:)), keyEquivalent: "")
        closeItem.target = tabController
        closeItem.representedObject = noteId
        menu.addItem(closeItem)

        let deleteItem = NSMenuItem(title: "Delete Note", action: #selector(TabWindowController.deleteNoteFromMenu(_:)), keyEquivalent: "")
        deleteItem.target = tabController
        deleteItem.representedObject = noteId
        menu.addItem(deleteItem)
        menu.addItem(NSMenuItem.separator())
        let newItem = NSMenuItem(title: "New Note", action: #selector(TabWindowController.addNewNote), keyEquivalent: "")
        newItem.target = tabController
        menu.addItem(newItem)
        return menu
    }
}

// MARK: - Borderless window hosting the tab interface
class TabHostWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              let controller = windowController as? TabWindowController,
              let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }

        // Cmd+Shift+[ / ] cycles tabs
        if flags.contains(.shift) {
            switch chars {
            case "[", "{": controller.selectPreviousTab(); return true
            case "]", "}": controller.selectNextTab(); return true
            default: break
            }
        }
        // Cmd+1..9 jumps to a tab
        if !flags.contains(.shift), let index = Int(chars), index >= 1, index <= 9 {
            controller.selectTab(at: index - 1)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // Text formatting is handled by the Format menu - see NoteWindow.
}
