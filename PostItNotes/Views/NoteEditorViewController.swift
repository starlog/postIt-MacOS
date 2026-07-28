import Cocoa
import WebKit

protocol NoteEditorDelegate: AnyObject {
    func noteEditorRequestsNewNote(_ editor: NoteEditorViewController)
    /// Hide the note but keep it in storage (reopenable from Closed Notes).
    func noteEditorRequestsClose(_ editor: NoteEditorViewController)
    /// Remove the note from storage for good.
    func noteEditorRequestsDelete(_ editor: NoteEditorViewController)
    func noteEditorDidChangeTitle(_ editor: NoteEditorViewController)
    func noteEditorDidChangeColor(_ editor: NoteEditorViewController)
}

/// Editing surface for a single note (toolbar + title + rich text / markdown preview).
/// Hosted either by NoteWindowController (floating window mode) or
/// TabWindowController (tab mode). Owns the only mutable copy of its note.
class NoteEditorViewController: NSViewController {

    private(set) var note: PostItNote
    private let noteService: NoteService
    private let claudeService = ClaudeAPIService()
    weak var delegate: NoteEditorDelegate?

    private(set) var titleBarView: NSView!
    private var titleField: NSTextField!
    private var contentTextView: NSTextView!
    private var scrollView: NSScrollView!
    private var markdownWebView: WKWebView!
    private var markdownToggleBtn: NSButton!
    private var wrapToggleBtn: NSButton!
    private var isMarkdownRendered = false
    private var separator: NSBox!
    private var markdownFontName = "System"
    private var markdownFontSize: CGFloat = 13
    private var imageDeleteButton: NSButton?
    private var imageDeleteCharIndex: Int?
    private var imageResizeHandle: NSView?
    private var isResizingImage = false
    private var resizeStartPoint: NSPoint = .zero
    private var resizeStartSize: NSSize = .zero
    private var resizeImageCharIndex: Int?

    /// Every note keeps its own undo stack. In tab mode a single window-level
    /// manager would let Cmd+Z on one note undo an edit made in another.
    private let noteUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 100
        return manager
    }()

    /// Whether the previous edit added or removed text - see the delegate's
    /// shouldChangeTextIn, which uses it to close the typing undo group.
    private enum TypingEdit { case insertion, deletion }
    private var lastTypingEdit: TypingEdit?

    /// Held while the F button's font dialog is open.
    private var fontDialog: FontSettingsWindowController?

    /// Sub-cards of this note. Only the selected one is in the text view; the
    /// rest sit here until their tab is clicked.
    private var pages: [NotePage] = []
    private var currentPageIndex = 0
    private var pageTabBar: NSView!
    private var pageTabStack: NSStackView!

    private let colorOptions: [(name: String, hex: String)] = [
        ("Yellow", "#FFFF88"),
        ("Green", "#88FF88"),
        ("Cyan", "#88FFFF"),
        ("Magenta", "#FF88FF"),
        ("Orange", "#FFBB55")
    ]

    var noteId: UUID { return note.id }
    var noteColor: String { return note.color }

    /// Label used by the tab bar: the note title, falling back to the first
    /// meaningful line of content so untitled notes stay identifiable.
    var displayTitle: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return NoteEditorViewController.contentSummary(note.content)
    }

    static func contentSummary(_ content: String) -> String {
        for rawLine in content.components(separatedBy: .newlines) {
            var line = rawLine
            // Drop image markers so a note starting with an image is not blank
            while let start = line.range(of: "{{IMG:"),
                  let end = line.range(of: "}}", options: [], range: start.upperBound..<line.endIndex) {
                line.removeSubrange(start.lowerBound..<end.upperBound)
            }
            let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*->`~ \t"))
            if !stripped.isEmpty { return String(stripped.prefix(24)) }
        }
        return "Untitled"
    }

    init(note: PostItNote, noteService: NoteService) {
        self.note = note
        self.noteService = noteService
        super.init(nibName: nil, bundle: nil)

        // Undoing an attribute-only change (bold and friends) does not post
        // textDidChange, so without this the formatting would come back the
        // next time the note is loaded.
        for name in [NSNotification.Name.NSUndoManagerDidUndoChange,
                     NSNotification.Name.NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoRedoDidChange),
                                                   name: name, object: noteUndoManager)
        }
    }

    @objc private func undoRedoDidChange() {
        saveContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 375, height: 250))
        view.wantsLayer = true
        pages = note.effectivePages
        currentPageIndex = note.selectedPageIndex
        syncActivePageIntoNote()
        setupUI()
        applyColor(note.color)
        applyWordWrap()
        loadNoteData()
        rebuildPageTabs()
    }

    private func setupUI() {
        let container = view

        // Title bar area
        titleBarView = DraggableTitleBarView()
        titleBarView.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.wantsLayer = true
        container.addSubview(titleBarView)

        // Color buttons
        var lastButton: NSButton?
        for (index, colorOpt) in colorOptions.enumerated() {
            let btn = NSButton(frame: .zero)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.wantsLayer = true
            btn.isBordered = false
            btn.title = ""
            btn.layer?.cornerRadius = 7
            btn.layer?.backgroundColor = NSColor(hex: colorOpt.hex)?.cgColor
            btn.layer?.borderWidth = 1
            btn.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
            btn.tag = index
            btn.target = self
            btn.action = #selector(colorButtonClicked(_:))
            btn.toolTip = colorOpt.name
            titleBarView.addSubview(btn)

            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 14),
                btn.heightAnchor.constraint(equalToConstant: 14),
                btn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor)
            ])
            if let prev = lastButton {
                btn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: 4).isActive = true
            } else {
                btn.leadingAnchor.constraint(equalTo: titleBarView.leadingAnchor, constant: 8).isActive = true
            }
            lastButton = btn
        }

        // Font size decrease button
        let fontMinusBtn = NSButton(frame: .zero)
        fontMinusBtn.translatesAutoresizingMaskIntoConstraints = false
        fontMinusBtn.isBordered = false
        fontMinusBtn.title = "A-"
        fontMinusBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        fontMinusBtn.target = self
        fontMinusBtn.action = #selector(fontSizeDecrease(_:))
        fontMinusBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleBarView.addSubview(fontMinusBtn)

        // Font size increase button
        let fontPlusBtn = NSButton(frame: .zero)
        fontPlusBtn.translatesAutoresizingMaskIntoConstraints = false
        fontPlusBtn.isBordered = false
        fontPlusBtn.title = "A+"
        fontPlusBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        fontPlusBtn.target = self
        fontPlusBtn.action = #selector(fontSizeIncrease(_:))
        fontPlusBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleBarView.addSubview(fontPlusBtn)

        // Font selection button
        let fontBtn = NSButton(frame: .zero)
        fontBtn.translatesAutoresizingMaskIntoConstraints = false
        fontBtn.isBordered = false
        fontBtn.title = "F"
        fontBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        fontBtn.target = self
        fontBtn.action = #selector(fontSelectClicked(_:))
        fontBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleBarView.addSubview(fontBtn)

        // Word wrap toggle
        wrapToggleBtn = NSButton(frame: .zero)
        wrapToggleBtn.translatesAutoresizingMaskIntoConstraints = false
        wrapToggleBtn.isBordered = false
        wrapToggleBtn.title = "\u{21A9}"
        wrapToggleBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        wrapToggleBtn.target = self
        wrapToggleBtn.action = #selector(wrapToggleClicked(_:))
        wrapToggleBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        wrapToggleBtn.setAccessibilityLabel("줄 바꿈 전환")
        titleBarView.addSubview(wrapToggleBtn)

        // Markdown toggle button
        markdownToggleBtn = NSButton(frame: .zero)
        markdownToggleBtn.translatesAutoresizingMaskIntoConstraints = false
        markdownToggleBtn.isBordered = false
        markdownToggleBtn.title = "MD"
        markdownToggleBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        markdownToggleBtn.target = self
        markdownToggleBtn.action = #selector(markdownToggleClicked(_:))
        markdownToggleBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleBarView.addSubview(markdownToggleBtn)

        // AI button
        let aiBtn = NSButton(frame: .zero)
        aiBtn.translatesAutoresizingMaskIntoConstraints = false
        aiBtn.isBordered = false
        aiBtn.title = "AI"
        aiBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        aiBtn.target = self
        aiBtn.action = #selector(aiButtonClicked(_:))
        aiBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleBarView.addSubview(aiBtn)

        // New note button (+)
        let newBtn = NSButton(frame: .zero)
        newBtn.translatesAutoresizingMaskIntoConstraints = false
        newBtn.isBordered = false
        newBtn.title = "+"
        newBtn.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        newBtn.target = self
        newBtn.action = #selector(newNoteClicked(_:))
        newBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleBarView.addSubview(newBtn)

        // Delete button (trash) - removes this note from storage
        let deleteBtn = NSButton(frame: .zero)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.isBordered = false
        if let trash = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete note") {
            deleteBtn.image = trash.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            deleteBtn.imagePosition = .imageOnly
        } else {
            deleteBtn.title = "Del"
            deleteBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        }
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteNoteClicked(_:))
        deleteBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        deleteBtn.toolTip = "Delete this note permanently"
        titleBarView.addSubview(deleteBtn)

        // Close button (X) - hides the note but keeps it in storage
        let closeBtn = NSButton(frame: .zero)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.isBordered = false
        closeBtn.title = "\u{2715}"
        closeBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        closeBtn.target = self
        closeBtn.action = #selector(closeNoteClicked(_:))
        closeBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        closeBtn.toolTip = "Close (reopen from Closed Notes)"
        titleBarView.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            closeBtn.trailingAnchor.constraint(equalTo: titleBarView.trailingAnchor, constant: -6),
            closeBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 22),
            deleteBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -2),
            deleteBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 22),
            newBtn.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -2),
            newBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            newBtn.widthAnchor.constraint(equalToConstant: 22),
            aiBtn.trailingAnchor.constraint(equalTo: newBtn.leadingAnchor, constant: -2),
            aiBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            aiBtn.widthAnchor.constraint(equalToConstant: 22),
            markdownToggleBtn.trailingAnchor.constraint(equalTo: aiBtn.leadingAnchor, constant: -2),
            markdownToggleBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            markdownToggleBtn.widthAnchor.constraint(equalToConstant: 26),
            wrapToggleBtn.trailingAnchor.constraint(equalTo: markdownToggleBtn.leadingAnchor, constant: -2),
            wrapToggleBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            wrapToggleBtn.widthAnchor.constraint(equalToConstant: 20),
            fontBtn.trailingAnchor.constraint(equalTo: wrapToggleBtn.leadingAnchor, constant: -2),
            fontBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            fontBtn.widthAnchor.constraint(equalToConstant: 20),
            fontPlusBtn.trailingAnchor.constraint(equalTo: fontBtn.leadingAnchor, constant: 0),
            fontPlusBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            fontPlusBtn.widthAnchor.constraint(equalToConstant: 22),
            fontMinusBtn.trailingAnchor.constraint(equalTo: fontPlusBtn.leadingAnchor, constant: 0),
            fontMinusBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            fontMinusBtn.widthAnchor.constraint(equalToConstant: 22)
        ])

        // Title text field
        titleField = NSTextField()
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.placeholderString = "Title..."
        titleField.isBordered = false
        titleField.backgroundColor = .clear
        titleField.font = NSFont.boldSystemFont(ofSize: 13)
        titleField.focusRingType = .none
        titleField.delegate = self
        container.addSubview(titleField)

        // Sub-card tab bar, directly under the title
        pageTabBar = NSView()
        pageTabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pageTabBar)

        let pageScroll = TabStripScrollView()
        pageScroll.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.drawsBackground = false
        pageScroll.hasHorizontalScroller = false
        pageScroll.hasVerticalScroller = false
        pageScroll.borderType = .noBorder
        pageTabBar.addSubview(pageScroll)

        pageTabStack = NSStackView()
        pageTabStack.translatesAutoresizingMaskIntoConstraints = false
        pageTabStack.orientation = .horizontal
        pageTabStack.alignment = .centerY
        pageTabStack.spacing = 2
        pageScroll.documentView = pageTabStack

        let addPageBtn = NSButton(frame: .zero)
        addPageBtn.translatesAutoresizingMaskIntoConstraints = false
        addPageBtn.isBordered = false
        addPageBtn.title = "+"
        addPageBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        addPageBtn.target = self
        addPageBtn.action = #selector(addPageClicked(_:))
        addPageBtn.toolTip = "새 서브 카드"
        // Distinct from the toolbar's new-note "+" for VoiceOver.
        addPageBtn.setAccessibilityLabel("새 서브 카드 추가")
        pageTabBar.addSubview(addPageBtn)

        NSLayoutConstraint.activate([
            addPageBtn.trailingAnchor.constraint(equalTo: pageTabBar.trailingAnchor, constant: -4),
            addPageBtn.centerYAnchor.constraint(equalTo: pageTabBar.centerYAnchor),
            addPageBtn.widthAnchor.constraint(equalToConstant: 18),

            pageScroll.leadingAnchor.constraint(equalTo: pageTabBar.leadingAnchor, constant: 4),
            pageScroll.trailingAnchor.constraint(equalTo: addPageBtn.leadingAnchor, constant: -2),
            pageScroll.topAnchor.constraint(equalTo: pageTabBar.topAnchor),
            pageScroll.bottomAnchor.constraint(equalTo: pageTabBar.bottomAnchor),

            pageTabStack.leadingAnchor.constraint(equalTo: pageScroll.contentView.leadingAnchor),
            pageTabStack.centerYAnchor.constraint(equalTo: pageScroll.contentView.centerYAnchor),
            pageTabStack.heightAnchor.constraint(equalToConstant: 18)
        ])

        // Separator
        separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        container.addSubview(separator)

        // Content text view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        contentTextView = NSTextView()
        contentTextView.isRichText = true
        contentTextView.allowsUndo = true
        contentTextView.usesFontPanel = false
        contentTextView.usesRuler = false
        contentTextView.font = NSFont.systemFont(ofSize: 13)
        contentTextView.backgroundColor = .clear
        contentTextView.isEditable = true
        contentTextView.isSelectable = true
        contentTextView.textContainerInset = NSSize(width: 5, height: 5)
        contentTextView.isVerticallyResizable = true
        contentTextView.isHorizontallyResizable = false
        contentTextView.autoresizingMask = [.width]
        contentTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        contentTextView.textContainer?.widthTracksTextView = true
        contentTextView.delegate = self

        scrollView.documentView = contentTextView
        container.addSubview(scrollView)

        // Track mouse for image hover delete button
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentTextView.addTrackingArea(trackingArea)

        // Markdown rendered view. The script handler is held weakly so the
        // editor can be deallocated when its note goes away.
        let webConfig = WKWebViewConfiguration()
        webConfig.userContentController.add(WeakScriptMessageHandler(target: self), name: "deleteImage")
        markdownWebView = WKWebView(frame: .zero, configuration: webConfig)
        markdownWebView.translatesAutoresizingMaskIntoConstraints = false
        markdownWebView.isHidden = true
        markdownWebView.setValue(false, forKey: "drawsBackground")
        container.addSubview(markdownWebView)

        // Layout
        NSLayoutConstraint.activate([
            titleBarView.topAnchor.constraint(equalTo: container.topAnchor),
            titleBarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleBarView.heightAnchor.constraint(equalToConstant: 28),

            titleField.topAnchor.constraint(equalTo: titleBarView.bottomAnchor, constant: 2),
            titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            titleField.heightAnchor.constraint(equalToConstant: 22),

            pageTabBar.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            pageTabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pageTabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pageTabBar.heightAnchor.constraint(equalToConstant: 22),

            separator.topAnchor.constraint(equalTo: pageTabBar.bottomAnchor, constant: 1),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            markdownWebView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 2),
            markdownWebView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            markdownWebView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            markdownWebView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Image drag overlay - sits on top of everything, transparent to mouse events
        let dragOverlay = ImageDragOverlayView()
        dragOverlay.translatesAutoresizingMaskIntoConstraints = false
        dragOverlay.onImageDrop = { [weak self] urls in
            self?.handleImageDrop(urls: urls)
        }
        container.addSubview(dragOverlay)
        NSLayoutConstraint.activate([
            dragOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            dragOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dragOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dragOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    /// Called by the host window once the note geometry changed on screen.
    /// Routed through the editor so the note struct never forks into two copies.
    func updateGeometry(x: Double, y: Double, width: Double, height: Double) {
        setGeometry(x: x, y: y, width: width, height: height)
        noteService.updateNote(note)
    }

    /// Same, but without touching storage - for repositioning done in bulk,
    /// where the caller saves every note in one go.
    func setGeometry(x: Double, y: Double, width: Double, height: Double) {
        note.x = x
        note.y = y
        note.width = width
        note.height = height
    }

    func focusContent() {
        view.window?.makeFirstResponder(contentTextView)
    }

    // MARK: - Sub-cards

    /// Copies the visible sub-card into the note's own content/rtfContent.
    /// Everything downstream - markdown, AI, tab labels, image markers - keeps
    /// reading those, so only the visible page needs to be mirrored.
    private func syncActivePageIntoNote() {
        guard pages.indices.contains(currentPageIndex) else { return }
        note.content = pages[currentPageIndex].content
        note.rtfContent = pages[currentPageIndex].rtfContent
    }

    private func rebuildPageTabs() {
        guard pageTabStack != nil else { return }
        for view in pageTabStack.arrangedSubviews {
            pageTabStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let base = NSColor(hex: note.color) ?? NSColor(red: 1, green: 1, blue: 0.53, alpha: 1)
        for (index, page) in pages.enumerated() {
            let selected = index == currentPageIndex
            let tab = PageTabButton(frame: .zero)
            tab.pageIndex = index
            tab.editor = self
            tab.isBordered = false
            tab.title = " \(page.name) "
            tab.font = NSFont.systemFont(ofSize: 10, weight: selected ? .bold : .regular)
            tab.target = self
            tab.action = #selector(pageTabClicked(_:))
            tab.wantsLayer = true
            tab.layer?.cornerRadius = 4
            tab.layer?.backgroundColor = selected
                ? base.blended(withFraction: 0.22, of: .black)?.cgColor
                : base.blended(withFraction: 0.45, of: .white)?.cgColor
            tab.toolTip = page.name
            tab.setAccessibilityLabel("서브 카드 \(page.name)")
            tab.menu = makePageMenu(for: index)
            pageTabStack.addArrangedSubview(tab)
            tab.heightAnchor.constraint(equalToConstant: 18).isActive = true
        }
        pageTabStack.layoutSubtreeIfNeeded()
    }

    /// Right-click menu of a sub-card tab.
    private func makePageMenu(for index: Int) -> NSMenu {
        let menu = NSMenu()
        // Otherwise AppKit re-enables Delete on the last remaining sub-card.
        menu.autoenablesItems = false

        let rename = NSMenuItem(title: "이름 변경...", action: #selector(renamePageFromMenu(_:)), keyEquivalent: "")
        rename.target = self
        rename.tag = index
        menu.addItem(rename)

        let delete = NSMenuItem(title: "서브 카드 삭제", action: #selector(deletePageFromMenu(_:)), keyEquivalent: "")
        delete.target = self
        delete.tag = index
        delete.isEnabled = pages.count > 1
        menu.addItem(delete)

        menu.addItem(NSMenuItem.separator())

        let add = NSMenuItem(title: "새 서브 카드", action: #selector(addPageFromMenu(_:)), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        return menu
    }

    @objc private func pageTabClicked(_ sender: NSButton) {
        guard let tab = sender as? PageTabButton else { return }
        selectPage(at: tab.pageIndex)
    }

    @objc private func addPageClicked(_ sender: NSButton) {
        addPage()
    }

    func selectPage(at index: Int) {
        guard pages.indices.contains(index), index != currentPageIndex else { return }
        saveContent()
        currentPageIndex = index
        showCurrentPage()
    }

    func addPage() {
        saveContent()
        pages.append(NotePage(name: nextPageName()))
        currentPageIndex = pages.count - 1
        showCurrentPage()
        focusContent()
    }

    /// Moves a sub-card to wherever it was dropped on the tab strip. The point
    /// is in window coordinates, as it comes off the drag event.
    func movePage(from index: Int, toDropPoint windowPoint: NSPoint) {
        guard pages.indices.contains(index) else { return }

        // Insertion slot: every tab whose middle the drop landed past.
        let point = pageTabStack.convert(windowPoint, from: nil)
        var insertion = 0
        for tab in pageTabStack.arrangedSubviews where point.x > tab.frame.midX {
            insertion += 1
        }
        // Removing the dragged tab first shifts every later slot down one.
        var target = insertion
        if target > index { target -= 1 }
        guard target != index, pages.indices.contains(target) else { return }

        let selectedId = pages[currentPageIndex].id
        let page = pages.remove(at: index)
        pages.insert(page, at: target)
        currentPageIndex = pages.firstIndex { $0.id == selectedId } ?? target

        note.pages = pages
        note.selectedPage = currentPageIndex
        rebuildPageTabs()
        noteService.updateNote(note)
    }

    func renamePage(at index: Int) {
        guard pages.indices.contains(index) else { return }

        let alert = NSAlert()
        alert.messageText = "서브 카드 이름"
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = pages[index].name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        pages[index].name = name
        note.pages = pages
        rebuildPageTabs()
        noteService.updateNote(note)
    }

    func deletePage(at index: Int) {
        // A note always keeps at least one sub-card - deleting the last one
        // would be deleting the note, which the trash button already does.
        guard pages.count > 1, pages.indices.contains(index) else {
            NSSound.beep()
            return
        }

        let page = pages[index]
        if !page.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.messageText = "서브 카드 '\(page.name)'을(를) 삭제할까요?"
            alert.informativeText = "이 서브 카드의 내용은 되돌릴 수 없습니다."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "삭제")
            alert.addButton(withTitle: "취소")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        // Flush the visible page first, unless it is the one being removed.
        if index != currentPageIndex { saveContent() }
        pages.remove(at: index)
        if index < currentPageIndex { currentPageIndex -= 1 }
        currentPageIndex = min(currentPageIndex, pages.count - 1)
        showCurrentPage()
    }

    /// Puts the selected sub-card on screen and writes the new selection out.
    private func showCurrentPage() {
        note.pages = pages
        note.selectedPage = currentPageIndex
        syncActivePageIntoNote()
        loadNoteData()
        // Each sub-card is its own document: keeping the stack would let Cmd+Z
        // pour one sub-card's text into another.
        noteUndoManager.removeAllActions()
        lastTypingEdit = nil
        if isMarkdownRendered { renderMarkdown() }
        rebuildPageTabs()
        noteService.updateNote(note)
        delegate?.noteEditorDidChangeTitle(self)
    }

    private func nextPageName() -> String {
        let used = Set(pages.map { $0.name })
        var number = pages.count + 1
        while used.contains("\(number)") { number += 1 }
        return "\(number)"
    }

    @objc func renamePageFromMenu(_ sender: NSMenuItem) { renamePage(at: sender.tag) }
    @objc func deletePageFromMenu(_ sender: NSMenuItem) { deletePage(at: sender.tag) }
    @objc func addPageFromMenu(_ sender: NSMenuItem) { addPage() }

    private func loadNoteData() {
        titleField.stringValue = note.title
        let content = note.content

        if content.contains("{{IMG:") {
            // Content has image markers - reconstruct with attachments
            loadContentWithImages(content)
        } else if let rtfString = note.rtfContent,
                  let rtfData = Data(base64Encoded: rtfString),
                  let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            contentTextView.textStorage?.setAttributedString(attrString)
        } else {
            contentTextView.string = content
        }
    }

    private func loadContentWithImages(_ content: String) {
        let result = NSMutableAttributedString()
        let defaultFont = contentTextView.font ?? NSFont.systemFont(ofSize: 13)
        var remaining = content

        while let markerStart = remaining.range(of: "{{IMG:") {
            // Add text before marker
            let textBefore = String(remaining[remaining.startIndex..<markerStart.lowerBound])
            if !textBefore.isEmpty {
                result.append(NSAttributedString(string: textBefore, attributes: [.font: defaultFont]))
            }

            // Find end of marker
            let afterMarker = remaining[markerStart.upperBound...]
            if let markerEnd = afterMarker.range(of: "}}") {
                let markerContent = String(afterMarker[afterMarker.startIndex..<markerEnd.lowerBound])
                // Parse path and optional size: "path:WxH" or just "path"
                var path = markerContent
                var savedSize: NSSize? = nil
                if let lastColon = markerContent.range(of: ":", options: .backwards),
                   markerContent[lastColon.upperBound...].contains("x") {
                    path = String(markerContent[markerContent.startIndex..<lastColon.lowerBound])
                    let sizeStr = String(markerContent[lastColon.upperBound...])
                    let parts = sizeStr.split(separator: "x")
                    if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
                        savedSize = NSSize(width: w, height: h)
                    }
                }
                if path != "unknown", let image = NSImage(contentsOfFile: path) {
                    let displaySize = savedSize ?? initialImageSize(image)
                    let attachment = NSTextAttachment()
                    let cell = NSTextAttachmentCell(imageCell: image)
                    cell.image?.size = displaySize
                    attachment.attachmentCell = cell
                    let imgAttr = NSMutableAttributedString(attachment: attachment)
                    imgAttr.addAttribute(Self.imagePathKey, value: path, range: NSRange(location: 0, length: imgAttr.length))
                    imgAttr.addAttribute(Self.imageSizeKey, value: NSValue(size: displaySize), range: NSRange(location: 0, length: imgAttr.length))
                    result.append(imgAttr)
                }
                remaining = String(remaining[markerEnd.upperBound...])
            } else {
                break
            }
        }

        // Append remaining text
        if !remaining.isEmpty {
            result.append(NSAttributedString(string: remaining, attributes: [.font: defaultFont]))
        }

        contentTextView.textStorage?.setAttributedString(result)
    }

    private func saveContent() {
        // Build content with image path markers for persistence
        guard let textStorage = contentTextView.textStorage else { return }
        var plainContent = ""
        var hasImages = false
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttributes(in: fullRange) { attrs, range, _ in
            if let path = attrs[Self.imagePathKey] as? String {
                hasImages = true
                if let sizeVal = attrs[Self.imageSizeKey] as? NSValue {
                    let size = sizeVal.sizeValue
                    plainContent += "{{IMG:\(path):\(Int(size.width))x\(Int(size.height))}}"
                } else {
                    plainContent += "{{IMG:\(path)}}"
                }
            } else if let _ = attrs[.attachment] as? NSTextAttachment {
                // Attachment without path - skip entirely
            } else {
                plainContent += (textStorage.string as NSString).substring(with: range)
            }
        }
        note.content = plainContent

        // Only save RTF when no images (images are saved as markers in content)
        if hasImages {
            note.rtfContent = nil
        } else if let rtfData = textStorage.rtf(from: fullRange, documentAttributes: [:]) {
            note.rtfContent = rtfData.base64EncodedString()
        }

        // What is on screen belongs to the selected sub-card.
        if pages.indices.contains(currentPageIndex) {
            pages[currentPageIndex].content = note.content
            pages[currentPageIndex].rtfContent = note.rtfContent
        }
        note.pages = pages
        note.selectedPage = currentPageIndex

        noteService.updateNote(note)

        // Untitled notes are labelled from their content, so the tab needs a refresh
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            delegate?.noteEditorDidChangeTitle(self)
        }
    }

    /// Selection the formatting commands act on, or nil when there is nothing
    /// to format. Focus is required so a stale body selection is not restyled
    /// while the title field or the markdown preview has the keyboard.
    private var formattableSelection: NSRange? {
        guard contentTextView.window?.firstResponder === contentTextView else { return nil }
        let range = contentTextView.selectedRange()
        return range.length > 0 ? range : nil
    }

    /// True when a formatting command would currently do something - drives
    /// whether the Format menu items are enabled.
    var canFormatSelection: Bool { return formattableSelection != nil }

    /// This note's undo stack, so Cmd+Z reaches it even when the body is not
    /// the first responder.
    var contentUndoManager: UndoManager { return noteUndoManager }

    @objc func toggleBold(_ sender: Any?) {
        guard let textStorage = contentTextView.textStorage,
              let selectedRange = formattableSelection else { return }

        var isBold = false
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, _, _ in
            if let font = value as? NSFont {
                isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            }
        }

        // Route the attribute change through the text view so it lands on
        // the undo stack and is saved the same way typing is.
        guard contentTextView.shouldChangeText(in: selectedRange, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
            if let font = value as? NSFont {
                let newFont: NSFont
                if isBold {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                textStorage.addAttribute(.font, value: newFont, range: range)
            }
        }
        textStorage.endEditing()
        contentTextView.didChangeText()
    }

    @objc func toggleItalic(_ sender: Any?) {
        guard let textStorage = contentTextView.textStorage,
              let selectedRange = formattableSelection else { return }

        var isItalic = false
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, _, _ in
            if let font = value as? NSFont {
                isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
            }
        }

        // Route the attribute change through the text view so it lands on
        // the undo stack and is saved the same way typing is.
        guard contentTextView.shouldChangeText(in: selectedRange, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
            if let font = value as? NSFont {
                let newFont: NSFont
                if isItalic {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                textStorage.addAttribute(.font, value: newFont, range: range)
            }
        }
        textStorage.endEditing()
        contentTextView.didChangeText()
    }

    @objc func toggleUnderline(_ sender: Any?) {
        guard let textStorage = contentTextView.textStorage,
              let selectedRange = formattableSelection else { return }

        var hasUnderline = false
        textStorage.enumerateAttribute(.underlineStyle, in: selectedRange) { value, _, _ in
            if let style = value as? Int, style != 0 {
                hasUnderline = true
            }
        }

        // Route the attribute change through the text view so it lands on
        // the undo stack and is saved the same way typing is.
        guard contentTextView.shouldChangeText(in: selectedRange, replacementString: nil) else { return }
        textStorage.beginEditing()
        if hasUnderline {
            textStorage.removeAttribute(.underlineStyle, range: selectedRange)
        } else {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
        }
        textStorage.endEditing()
        contentTextView.didChangeText()
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        guard let textStorage = contentTextView.textStorage,
              let selectedRange = formattableSelection else { return }

        var hasStrikethrough = false
        textStorage.enumerateAttribute(.strikethroughStyle, in: selectedRange) { value, _, _ in
            if let style = value as? Int, style != 0 {
                hasStrikethrough = true
            }
        }

        // Route the attribute change through the text view so it lands on
        // the undo stack and is saved the same way typing is.
        guard contentTextView.shouldChangeText(in: selectedRange, replacementString: nil) else { return }
        textStorage.beginEditing()
        if hasStrikethrough {
            textStorage.removeAttribute(.strikethroughStyle, range: selectedRange)
        } else {
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
        }
        textStorage.endEditing()
        contentTextView.didChangeText()
    }

    // MARK: - Font

    @objc private func fontSizeIncrease(_ sender: NSButton) {
        changeFontSize(delta: 1)
    }

    @objc private func fontSizeDecrease(_ sender: NSButton) {
        changeFontSize(delta: -1)
    }

    private func changeFontSize(delta: CGFloat) {
        // Stepping from the size the note really uses keeps the markdown
        // preview in step with the editor.
        markdownFontSize = max(8, effectiveFontSize + delta)
        if isMarkdownRendered {
            renderMarkdown()
        } else {
            guard let textStorage = contentTextView.textStorage else { return }
            let range = NSRange(location: 0, length: textStorage.length)
            // Nothing typed yet: set the size the note will start typing at.
            guard range.length > 0 else {
                let base = contentTextView.font ?? NSFont.systemFont(ofSize: markdownFontSize)
                contentTextView.font = NSFontManager.shared.convert(base, toSize: markdownFontSize)
                return
            }
            guard contentTextView.shouldChangeText(in: range, replacementString: nil) else { return }
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newSize = max(8, font.pointSize + delta)
                    let newFont = NSFontManager.shared.convert(font, toSize: newSize)
                    textStorage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            textStorage.endEditing()
            contentTextView.didChangeText()
        }
    }

    /// Font the note is actually using, rather than the last one picked here -
    /// a note loaded from storage keeps whatever it was saved with.
    private var effectiveFont: NSFont? {
        if isMarkdownRendered {
            return NSFont(name: markdownFontName, size: markdownFontSize)
                ?? NSFont.systemFont(ofSize: markdownFontSize)
        }
        if let storage = contentTextView.textStorage, storage.length > 0,
           let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            return font
        }
        return contentTextView.font
    }

    private var effectiveFontSize: CGFloat {
        return effectiveFont?.pointSize ?? markdownFontSize
    }

    /// Name this note's font goes by in the picker, so the dialog opens on the
    /// entry the note is really using.
    private var effectiveFontChoiceName: String {
        guard let font = effectiveFont else { return markdownFontName }
        if font.fontName.hasPrefix(".") { return "System" }
        if FontSettingsWindowController.fontOptions.contains(where: { $0.name == font.fontName }) {
            return font.fontName
        }
        return markdownFontName
    }

    /// The F button opens a font + size dialog for this note.
    @objc private func fontSelectClicked(_ sender: NSButton) {
        let current = FontConfig(fontName: effectiveFontChoiceName, fontSize: Double(effectiveFontSize.rounded()))
        let dialog = FontSettingsWindowController(currentFont: current, title: "Note Font")
        dialog.onSave = { [weak self] config in
            self?.applyFont(name: config.fontName, size: CGFloat(config.fontSize))
            self?.fontDialog = nil
        }
        fontDialog = dialog
        dialog.showWindow(nil)
        dialog.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func font(named name: String, size: CGFloat) -> NSFont {
        if name == "System" { return NSFont.systemFont(ofSize: size) }
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// Applies one family and size to the whole note. Bold and italic set on
    /// individual words are kept - only the family and size are replaced.
    private func applyFont(name: String, size: CGFloat) {
        let newSize = max(8, size)
        markdownFontName = name
        markdownFontSize = newSize

        if isMarkdownRendered {
            renderMarkdown()
            return
        }
        guard let textStorage = contentTextView.textStorage else { return }
        let picked = Self.font(named: name, size: newSize)
        let range = NSRange(location: 0, length: textStorage.length)

        // Nothing typed yet: set what the note will start typing with.
        guard range.length > 0 else {
            contentTextView.font = picked
            return
        }

        guard contentTextView.shouldChangeText(in: range, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            var applied = picked
            if let existing = value as? NSFont {
                let traits = NSFontManager.shared.traits(of: existing)
                var keep: NSFontTraitMask = []
                if traits.contains(.boldFontMask) { keep.insert(.boldFontMask) }
                if traits.contains(.italicFontMask) { keep.insert(.italicFontMask) }
                if !keep.isEmpty {
                    applied = NSFontManager.shared.convert(picked, toHaveTrait: keep)
                }
            }
            textStorage.addAttribute(.font, value: applied, range: attrRange)
        }
        textStorage.endEditing()
        contentTextView.didChangeText()
        contentTextView.font = picked
    }

    // MARK: - Markdown

    // MARK: - Word wrap

    @objc private func wrapToggleClicked(_ sender: NSButton) {
        note.wordWrap = !note.wrapsText
        applyWordWrap()
        noteService.updateNote(note)
    }

    /// Wrapping on: the text container follows the view's width. Off: the
    /// container grows with the longest line and the scroll view gains a
    /// horizontal scroller.
    private func applyWordWrap() {
        guard let container = contentTextView.textContainer else { return }
        let wraps = note.wrapsText
        let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        contentTextView.maxSize = unbounded
        if wraps {
            scrollView.hasHorizontalScroller = false
            contentTextView.isHorizontallyResizable = false
            contentTextView.autoresizingMask = [.width]
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            contentTextView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: contentTextView.frame.height))
        } else {
            scrollView.hasHorizontalScroller = true
            contentTextView.isHorizontallyResizable = true
            contentTextView.autoresizingMask = []
            container.widthTracksTextView = false
            container.containerSize = unbounded
        }

        wrapToggleBtn?.alphaValue = wraps ? 1.0 : 0.4
        wrapToggleBtn?.toolTip = wraps ? "줄 바꿈 켜짐 - 끄려면 클릭" : "줄 바꿈 꺼짐 - 켜려면 클릭"
        contentTextView.needsLayout = true
        contentTextView.needsDisplay = true
    }

    @objc private func markdownToggleClicked(_ sender: NSButton) {
        if isMarkdownRendered {
            switchToEditMode()
        } else {
            switchToMarkdownView()
        }
    }

    private func switchToMarkdownView() {
        isMarkdownRendered = true
        markdownToggleBtn.title = "Edit"
        scrollView.isHidden = true
        markdownWebView.isHidden = false
        renderMarkdown()
    }

    private func switchToEditMode() {
        isMarkdownRendered = false
        markdownToggleBtn.title = "MD"
        markdownWebView.isHidden = true
        scrollView.isHidden = false
    }

    private func renderMarkdown() {
        let markdown = contentTextView.string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let bgColor = note.color
        let cssFontFamily: String
        if markdownFontName == "System" {
            cssFontFamily = "-apple-system, BlinkMacSystemFont, sans-serif"
        } else {
            cssFontFamily = "'\(markdownFontName)', -apple-system, sans-serif"
        }
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: \(cssFontFamily);
                font-size: \(Int(markdownFontSize))px;
                padding: 8px;
                margin: 0;
                background-color: \(bgColor);
                color: #333;
                word-wrap: break-word;
            }
            h1 { font-size: 1.4em; margin: 0.4em 0; }
            h2 { font-size: 1.2em; margin: 0.4em 0; }
            h3 { font-size: 1.1em; margin: 0.3em 0; }
            h4, h5, h6 { font-size: 1em; margin: 0.3em 0; }
            code {
                background: rgba(0,0,0,0.08);
                padding: 1px 4px;
                border-radius: 3px;
                font-size: 12px;
            }
            pre {
                background: rgba(0,0,0,0.08);
                padding: 8px;
                border-radius: 4px;
                overflow-x: auto;
            }
            pre code { background: none; padding: 0; }
            blockquote {
                border-left: 3px solid rgba(0,0,0,0.3);
                margin: 0.4em 0;
                padding: 2px 8px;
                color: #555;
            }
            ul, ol { padding-left: 20px; margin: 0.3em 0; }
            hr { border: none; border-top: 1px solid rgba(0,0,0,0.2); margin: 0.5em 0; }
            a { color: #0366d6; }
            table { border-collapse: collapse; margin: 0.4em 0; }
            th, td { border: 1px solid rgba(0,0,0,0.2); padding: 4px 8px; }
            th { background: rgba(0,0,0,0.05); }
            img { max-width: 100%; }
            .img-wrapper {
                position: relative;
                display: inline-block;
            }
            .img-wrapper .delete-btn {
                display: none;
                position: absolute;
                top: 4px;
                left: 4px;
                width: 22px;
                height: 22px;
                border-radius: 50%;
                background: rgba(220, 50, 50, 0.85);
                color: white;
                border: none;
                font-size: 14px;
                line-height: 20px;
                text-align: center;
                cursor: pointer;
                padding: 0;
                box-shadow: 0 1px 3px rgba(0,0,0,0.3);
            }
            .img-wrapper:hover .delete-btn {
                display: block;
            }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        function renderMarkdown(md) {
            // Code blocks
            md = md.replace(/```(\\w*)\\n([\\s\\S]*?)```/g, '<pre><code>$2</code></pre>');
            // Headings
            md = md.replace(/^######\\s+(.*)$/gm, '<h6>$1</h6>');
            md = md.replace(/^#####\\s+(.*)$/gm, '<h5>$1</h5>');
            md = md.replace(/^####\\s+(.*)$/gm, '<h4>$1</h4>');
            md = md.replace(/^###\\s+(.*)$/gm, '<h3>$1</h3>');
            md = md.replace(/^##\\s+(.*)$/gm, '<h2>$1</h2>');
            md = md.replace(/^#\\s+(.*)$/gm, '<h1>$1</h1>');
            // Horizontal rule
            md = md.replace(/^---+\\s*$/gm, '<hr>');
            // Bold & italic
            md = md.replace(/\\*\\*\\*([^*]+)\\*\\*\\*/g, '<strong><em>$1</em></strong>');
            md = md.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
            md = md.replace(/\\*([^*]+)\\*/g, '<em>$1</em>');
            // Strikethrough
            md = md.replace(/~~([^~]+)~~/g, '<del>$1</del>');
            // Inline code
            md = md.replace(/`([^`]+)`/g, '<code>$1</code>');
            // Images - convert absolute paths to file:// URLs, wrap with delete button
            md = md.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g, function(m, alt, src) {
                var origSrc = src;
                if (src.startsWith('/')) { src = 'file://' + src; }
                return '<span class="img-wrapper"><button class="delete-btn" onclick="deleteImage(\\'' + origSrc.replace(/'/g, "\\\\'") + '\\')">\\u2715</button><img src="' + src + '" alt="' + alt + '"></span>';
            });
            // Links
            md = md.replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g, '<a href="$2">$1</a>');
            // Blockquotes
            md = md.replace(/^>\\s+(.*)$/gm, '<blockquote>$1</blockquote>');
            // Unordered lists
            md = md.replace(/^\\s*[-*+]\\s+(.*)$/gm, '<li>$1</li>');
            md = md.replace(/(<li>.*<\\/li>\\n?)+/g, function(m) { return '<ul>' + m + '</ul>'; });
            // Ordered lists
            md = md.replace(/^\\s*\\d+\\.\\s+(.*)$/gm, '<li>$1</li>');
            // Tables
            md = md.replace(/^(\\|.+\\|\\n)+/gm, function(tableBlock) {
                var rows = tableBlock.trim().split('\\n');
                if (rows.length < 2) return tableBlock;
                var html = '<table>';
                // Header row
                var headerCells = rows[0].split('|').filter(function(c) { return c.trim() !== ''; });
                html += '<thead><tr>';
                headerCells.forEach(function(c) { html += '<th>' + c.trim() + '</th>'; });
                html += '</tr></thead>';
                // Find where separator row is (row with |---|---|)
                var startIdx = 1;
                if (rows.length > 1 && /^[\\s|:-]+$/.test(rows[1])) {
                    startIdx = 2;
                }
                html += '<tbody>';
                for (var i = startIdx; i < rows.length; i++) {
                    var cells = rows[i].split('|').filter(function(c) { return c.trim() !== ''; });
                    html += '<tr>';
                    cells.forEach(function(c) { html += '<td>' + c.trim() + '</td>'; });
                    html += '</tr>';
                }
                html += '</tbody></table>';
                return html;
            });
            // Paragraphs
            md = md.replace(/\\n\\n+/g, '</p><p>');
            md = md.replace(/\\n/g, '<br>');
            md = '<p>' + md + '</p>';
            // Clean up
            md = md.replace(/<p><(h[1-6]|ul|ol|pre|blockquote|hr|table)/g, '<$1');
            md = md.replace(/<\\/(h[1-6]|ul|ol|pre|blockquote|table)><\\/p>/g, '</$1>');
            md = md.replace(/<p><\\/p>/g, '');
            md = md.replace(/<hr><\\/p>/g, '<hr>');
            return md;
        }
        document.getElementById('content').innerHTML = renderMarkdown(`\(markdown)`);
        function deleteImage(src) {
            window.webkit.messageHandlers.deleteImage.postMessage(src);
        }
        </script>
        </body>
        </html>
        """
        // Write HTML to data directory, allow read access to / for images from any path
        let dataDir = URL(fileURLWithPath: noteService.getDataDirectory())
        let tmpFile = dataDir.appendingPathComponent("preview_\(note.id.uuidString).html")
        try? html.write(to: tmpFile, atomically: true, encoding: .utf8)
        markdownWebView.loadFileURL(tmpFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func applyColor(_ hex: String) {
        guard let color = NSColor(hex: hex) else { return }
        view.layer?.backgroundColor = color.cgColor
        titleBarView?.layer?.backgroundColor = color.blended(withFraction: 0.1, of: .black)?.cgColor
        rebuildPageTabs()
        if isMarkdownRendered {
            renderMarkdown()
        }
    }

    // MARK: - Actions

    @objc private func colorButtonClicked(_ sender: NSButton) {
        let hex = colorOptions[sender.tag].hex
        note.color = hex
        applyColor(hex)
        noteService.updateNote(note)
        delegate?.noteEditorDidChangeColor(self)
    }

    @objc private func newNoteClicked(_ sender: NSButton) {
        delegate?.noteEditorRequestsNewNote(self)
    }

    /// Non-destructive: the note stays in notes.json and can be reopened.
    @objc private func closeNoteClicked(_ sender: NSButton) {
        delegate?.noteEditorRequestsClose(self)
    }

    @objc private func deleteNoteClicked(_ sender: NSButton) {
        // An empty note has nothing to lose - delete it without nagging.
        let isEmpty = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && contentTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (contentTextView.textStorage?.length ?? 0) == 0
        if isEmpty {
            delegate?.noteEditorRequestsDelete(self)
            return
        }

        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Note"
        alert.informativeText = "\u{201C}\(displayTitle)\u{201D} will be permanently deleted. This cannot be undone."
        alert.alertStyle = .warning

        let deleteButton = alert.addButton(withTitle: "Delete")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        deleteButton.hasDestructiveAction = true
        // Return must not trigger the destructive action by accident
        deleteButton.keyEquivalent = ""
        cancelButton.keyEquivalent = "\r"

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            self.delegate?.noteEditorRequestsDelete(self)
        }
    }

    /// Removes the note from storage along with its markdown preview scratch file.
    func deleteNoteFromStorage() {
        noteService.deleteNote(id: note.id)
        let previewFile = URL(fileURLWithPath: noteService.getDataDirectory())
            .appendingPathComponent("preview_\(note.id.uuidString).html")
        try? FileManager.default.removeItem(at: previewFile)
    }

    @objc private func aiButtonClicked(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "AI Assistant"
        alert.informativeText = "Enter your prompt:"
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")

        let promptScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        promptScroll.hasVerticalScroller = true
        promptScroll.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 294, height: 100))
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 294, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        promptScroll.documentView = textView
        alert.accessoryView = promptScroll
        alert.window.initialFirstResponder = textView

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let prompt = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return }
            self.sendToAI(prompt: prompt)
        }
    }

    private func buildNoteContentForAI() -> String {
        guard let textStorage = contentTextView.textStorage else { return contentTextView.string }
        var result = ""
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttributes(in: fullRange) { attrs, range, _ in
            if let path = attrs[Self.imagePathKey] as? String {
                result += "[Image: \(path)]"
            } else if let _ = attrs[.attachment] as? NSTextAttachment {
                result += "[Image]"
            } else {
                let text = (textStorage.string as NSString).substring(with: range)
                result += text
            }
        }
        return result
    }

    private func sendToAI(prompt: String) {
        let noteContent = buildNoteContentForAI()

        // Show loading indicator
        let originalTitle = titleField.stringValue
        DispatchQueue.main.async {
            self.titleField.stringValue = "⏳ AI processing..."
            self.titleField.isEditable = false
        }

        claudeService.sendMessage(prompt: prompt, noteContent: noteContent) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.titleField.stringValue = originalTitle
                self.titleField.isEditable = true

                switch result {
                case .success(let response):
                    let sep = "\n\n--- AI Response ---\n"
                    let currentText = self.contentTextView.string
                    self.contentTextView.string = currentText + sep + response
                    self.saveContent()
                    if self.isMarkdownRendered {
                        self.renderMarkdown()
                    }
                case .failure(let error):
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "AI Error"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    if let window = self.view.window {
                        errorAlert.beginSheetModal(for: window, completionHandler: nil)
                    }
                }
            }
        }
    }

    // MARK: - Image Drop

    func handleImageDrop(urls: [URL]) {
        for url in urls {
            let path = url.path
            if isMarkdownRendered {
                let markdownImage = "\n![image](\(path))\n"
                contentTextView.string += markdownImage
                saveContent()
                renderMarkdown()
            } else {
                insertImageAttachment(path: path)
            }
        }
    }

    // MARK: - Image hover delete (edit mode)

    override func mouseMoved(with event: NSEvent) {
        guard !isMarkdownRendered else { return }
        let pointInWindow = event.locationInWindow
        let pointInTextView = contentTextView.convert(pointInWindow, from: nil)

        guard contentTextView.bounds.contains(pointInTextView) else {
            hideImageDeleteButton()
            return
        }

        let pointInContainer = NSPoint(
            x: pointInTextView.x - contentTextView.textContainerInset.width,
            y: pointInTextView.y - contentTextView.textContainerInset.height
        )

        let charIndex = contentTextView.layoutManager?.characterIndex(
            for: pointInContainer,
            in: contentTextView.textContainer!,
            fractionOfDistanceBetweenInsertionPoints: nil
        ) ?? NSNotFound

        guard charIndex != NSNotFound,
              charIndex < (contentTextView.textStorage?.length ?? 0) else {
            hideImageDeleteButton()
            return
        }

        let attrs = contentTextView.textStorage?.attributes(at: charIndex, effectiveRange: nil)
        if let _ = attrs?[.attachment] as? NSTextAttachment {
            showImageDeleteButton(at: charIndex)
            showImageResizeHandle(at: charIndex)
        } else {
            hideImageDeleteButton()
            hideImageResizeHandle()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isResizingImage {
            hideImageDeleteButton()
            hideImageResizeHandle()
        }
    }

    private func showImageDeleteButton(at charIndex: Int) {
        if imageDeleteCharIndex == charIndex, imageDeleteButton != nil { return }

        hideImageDeleteButton()
        imageDeleteCharIndex = charIndex

        guard let layoutManager = contentTextView.layoutManager,
              let textContainer = contentTextView.textContainer else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.x += contentTextView.textContainerInset.width
        lineRect.origin.y += contentTextView.textContainerInset.height

        let btn = NSButton(frame: NSRect(x: lineRect.origin.x + 4, y: lineRect.origin.y + 4, width: 22, height: 22))
        btn.bezelStyle = .circular
        btn.title = "\u{2715}"
        btn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(red: 0.86, green: 0.2, blue: 0.2, alpha: 0.85).cgColor
        btn.layer?.cornerRadius = 11
        btn.contentTintColor = .white
        btn.target = self
        btn.action = #selector(deleteImageAttachment(_:))
        contentTextView.addSubview(btn)
        imageDeleteButton = btn
    }

    private func hideImageDeleteButton() {
        imageDeleteButton?.removeFromSuperview()
        imageDeleteButton = nil
        imageDeleteCharIndex = nil
    }

    @objc private func deleteImageAttachment(_ sender: NSButton) {
        guard let charIndex = imageDeleteCharIndex,
              let textStorage = contentTextView.textStorage,
              charIndex < textStorage.length else { return }
        hideImageDeleteButton()
        textStorage.deleteCharacters(in: NSRange(location: charIndex, length: 1))
        saveContent()
    }

    private func showImageResizeHandle(at charIndex: Int) {
        if resizeImageCharIndex == charIndex, imageResizeHandle != nil { return }

        hideImageResizeHandle()
        resizeImageCharIndex = charIndex

        guard let layoutManager = contentTextView.layoutManager,
              let textContainer = contentTextView.textContainer else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += contentTextView.textContainerInset.width
        rect.origin.y += contentTextView.textContainerInset.height

        let handleSize: CGFloat = 14
        let handle = NSView(frame: NSRect(
            x: rect.origin.x + rect.width - handleSize,
            y: rect.origin.y + rect.height - handleSize,
            width: handleSize,
            height: handleSize
        ))
        handle.wantsLayer = true
        handle.layer?.backgroundColor = NSColor.darkGray.withAlphaComponent(0.7).cgColor
        handle.layer?.cornerRadius = 2

        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleImageResize(_:)))
        handle.addGestureRecognizer(panGesture)

        contentTextView.addSubview(handle)
        imageResizeHandle = handle

        NSCursor.resizeLeftRight.set()
    }

    private func hideImageResizeHandle() {
        imageResizeHandle?.removeFromSuperview()
        imageResizeHandle = nil
        if !isResizingImage {
            resizeImageCharIndex = nil
        }
    }

    private var resizeImageOriginX: CGFloat = 0

    @objc private func handleImageResize(_ gesture: NSPanGestureRecognizer) {
        guard let charIndex = resizeImageCharIndex,
              let textStorage = contentTextView.textStorage,
              charIndex < textStorage.length,
              let attachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
              let cell = attachment.attachmentCell as? NSTextAttachmentCell,
              let image = cell.image else { return }

        if gesture.state == .began {
            isResizingImage = true
            resizeStartSize = image.size
            // Get image origin X
            if let layoutManager = contentTextView.layoutManager,
               let textContainer = contentTextView.textContainer {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                resizeImageOriginX = rect.origin.x + contentTextView.textContainerInset.width
            }
        }

        let currentPoint = gesture.location(in: contentTextView)
        // Width = mouse X position - image left edge
        let ratio = resizeStartSize.height / resizeStartSize.width
        let newWidth = max(30, currentPoint.x - resizeImageOriginX)
        let newHeight = newWidth * ratio
        let newSize = NSSize(width: newWidth, height: newHeight)

        cell.image?.size = newSize
        textStorage.addAttribute(Self.imageSizeKey, value: NSValue(size: newSize), range: NSRange(location: charIndex, length: 1))

        // Force layout update
        contentTextView.needsDisplay = true
        contentTextView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)

        // Update handle position
        if let layoutManager = contentTextView.layoutManager,
           let textContainer = contentTextView.textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += contentTextView.textContainerInset.width
            rect.origin.y += contentTextView.textContainerInset.height
            let handleSize: CGFloat = 14
            imageResizeHandle?.frame = NSRect(
                x: rect.origin.x + rect.width - handleSize,
                y: rect.origin.y + rect.height - handleSize,
                width: handleSize,
                height: handleSize
            )
            // Update delete button position too
            imageDeleteButton?.frame.origin = NSPoint(x: rect.origin.x + 4, y: rect.origin.y + 4)
        }

        if gesture.state == .ended || gesture.state == .cancelled {
            isResizingImage = false
            saveContent()
        }
    }

    private static let imagePathKey = NSAttributedString.Key("imageFilePath")

    private static let imageSizeKey = NSAttributedString.Key("imageSize")

    private func initialImageSize(_ image: NSImage) -> NSSize {
        let maxInitialWidth: CGFloat = 300
        var width = image.size.width
        var height = image.size.height
        if width > maxInitialWidth {
            let ratio = maxInitialWidth / width
            width = maxInitialWidth
            height *= ratio
        }
        return NSSize(width: width, height: height)
    }

    private func insertImageAttachment(path: String, size: NSSize? = nil) {
        guard let image = NSImage(contentsOfFile: path) else { return }
        let displaySize = size ?? initialImageSize(image)
        let attachment = NSTextAttachment()
        let cell = NSTextAttachmentCell(imageCell: image)
        cell.image?.size = displaySize
        attachment.attachmentCell = cell
        let attrStr = NSMutableAttributedString(attachment: attachment)
        attrStr.addAttribute(Self.imagePathKey, value: path, range: NSRange(location: 0, length: attrStr.length))
        attrStr.addAttribute(Self.imageSizeKey, value: NSValue(size: displaySize), range: NSRange(location: 0, length: attrStr.length))
        let insertionPoint = contentTextView.selectedRange().location
        contentTextView.textStorage?.insert(attrStr, at: insertionPoint)
        let pathMarker = NSAttributedString(string: "\n")
        contentTextView.textStorage?.insert(pathMarker, at: insertionPoint + 1)
        saveContent()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        markdownWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "deleteImage")
    }
}

// MARK: - Sub-card tab: right-click to rename or delete, double-click to rename
class PageTabButton: NSButton {
    var pageIndex = 0
    weak var editor: NoteEditorViewController?

    // The right-click menu is assigned in rebuildPageTabs so that both the
    // mouse and assistive tools can reach it.

    /// Tracks the mouse so a tab can be dragged sideways to reorder. A press
    /// that never moves is passed on as a plain click, so selecting a sub-card
    /// still works.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            editor?.renamePage(at: pageIndex)
            return
        }
        guard let window = self.window else {
            super.mouseDown(with: event)
            return
        }

        let start = event.locationInWindow
        var isDragging = false
        var lastPoint = start

        trackingLoop: while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            switch next.type {
            case .leftMouseDragged:
                lastPoint = next.locationInWindow
                if !isDragging && abs(lastPoint.x - start.x) > 3 {
                    isDragging = true
                    alphaValue = 0.5
                }
            case .leftMouseUp:
                lastPoint = next.locationInWindow
                break trackingLoop
            default:
                break trackingLoop
            }
        }

        alphaValue = 1.0
        if isDragging {
            editor?.movePage(from: pageIndex, toDropPoint: lastPoint)
        } else {
            sendAction(self.action, to: self.target)
        }
    }
}

// MARK: - NSTextFieldDelegate
extension NoteEditorViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        note.title = titleField.stringValue
        noteService.updateNote(note)
        delegate?.noteEditorDidChangeTitle(self)
    }
}

// MARK: - NSTextViewDelegate
extension NoteEditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        saveContent()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        return noteUndoManager
    }

    /// AppKit coalesces a burst of typing into one undo group, and deleting
    /// straight after typing keeps extending that same group - so Cmd+Z threw
    /// the typing away instead of bringing the deleted text back. Closing the
    /// group whenever the edit flips between adding and removing text makes
    /// "type, delete, Cmd+Z" restore what was deleted.
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        // nil means only attributes change (bold and friends). That also has to
        // close the group, otherwise Cmd+Z after Cmd+B takes the text with it.
        guard let replacement = replacementString else {
            textView.breakUndoCoalescing()
            lastTypingEdit = nil
            return true
        }

        let kind: TypingEdit = (replacement.isEmpty && affectedCharRange.length > 0) ? .deletion : .insertion
        if let previous = lastTypingEdit, previous != kind {
            textView.breakUndoCoalescing()
        }
        lastTypingEdit = kind
        return true
    }
}

// MARK: - WKScriptMessageHandler
extension NoteEditorViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "deleteImage", let src = message.body as? String {
            deleteMarkdownImage(src: src)
        }
    }

    private func deleteMarkdownImage(src: String) {
        // Remove the markdown image line matching this src
        let lines = contentTextView.string.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let pattern = "![" // quick check
            guard line.contains(pattern) else { return true }
            return !line.contains("(\(src))") && !line.contains("(file://\(src))")
        }
        contentTextView.string = filtered.joined(separator: "\n")
        saveContent()
        renderMarkdown()
    }
}

// MARK: - Breaks the WKWebView -> handler -> WKWebView retain cycle
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Custom title bar view that accepts first mouse click
class DraggableTitleBarView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - Transparent overlay that intercepts image file drags but passes all mouse events through
class ImageDragOverlayView: NSView {
    var onImageDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // hitTest returns nil so all mouse events (click, scroll, select) pass through to views below.
    // Drag destination lookup uses frame containment, not hitTest, so drags still arrive here.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImageFiles(sender) { return .copy }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImageFiles(sender) { return .copy }
        return []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return hasImageFiles(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onImageDrop?(urls)
        return true
    }

    private func hasImageFiles(_ info: NSDraggingInfo) -> Bool {
        return !imageURLs(from: info).isEmpty
    }

    private func imageURLs(from info: NSDraggingInfo) -> [URL] {
        guard let items = info.draggingPasteboard.pasteboardItems else { return [] }
        let imageExts = Set(["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"])
        var urls: [URL] = []
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                let ext = url.pathExtension.lowercased()
                if imageExts.contains(ext) {
                    urls.append(url)
                }
            }
        }
        return urls
    }
}

// MARK: - Widens the grab area for resizing a borderless window
/// Invisible ring pinned to the window edges. Only the outer `thickness` points
/// are clickable - everything further in hit-tests through to the content below,
/// so the app keeps working normally away from the edges.
class ResizeBorderView: NSView {
    struct Edge: OptionSet {
        let rawValue: Int
        static let left = Edge(rawValue: 1 << 0)
        static let right = Edge(rawValue: 1 << 1)
        static let bottom = Edge(rawValue: 1 << 2)
        static let top = Edge(rawValue: 1 << 3)
    }

    var thickness: CGFloat = 10

    private var activeEdge: Edge = []
    private var initialFrame: NSRect = .zero
    private var initialMouse: NSPoint = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    private func edge(at point: NSPoint) -> Edge {
        guard bounds.contains(point) else { return [] }
        var result: Edge = []
        if point.x <= thickness { result.insert(.left) }
        if point.x >= bounds.width - thickness { result.insert(.right) }
        if point.y <= thickness { result.insert(.bottom) }
        if point.y >= bounds.height - thickness { result.insert(.top) }
        return result
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return edge(at: local).isEmpty ? nil : self
    }

    override func resetCursorRects() {
        let t = thickness
        addCursorRect(NSRect(x: 0, y: 0, width: t, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - t, y: 0, width: t, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: t), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: bounds.height - t, width: bounds.width, height: t), cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        activeEdge = edge(at: convert(event.locationInWindow, from: nil))
        initialFrame = window.frame
        initialMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window, !activeEdge.isEmpty else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - initialMouse.x
        let dy = current.y - initialMouse.y
        let minSize = window.minSize
        var frame = initialFrame

        if activeEdge.contains(.left) {
            let width = max(minSize.width, initialFrame.width - dx)
            frame.origin.x = initialFrame.maxX - width
            frame.size.width = width
        }
        if activeEdge.contains(.right) {
            frame.size.width = max(minSize.width, initialFrame.width + dx)
        }
        if activeEdge.contains(.bottom) {
            let height = max(minSize.height, initialFrame.height - dy)
            frame.origin.y = initialFrame.maxY - height
            frame.size.height = height
        }
        if activeEdge.contains(.top) {
            frame.size.height = max(minSize.height, initialFrame.height + dy)
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        activeEdge = []
    }

    /// Pins a resize ring on top of `container`, covering its full bounds.
    @discardableResult
    static func install(in container: NSView, thickness: CGFloat = 10) -> ResizeBorderView {
        let border = ResizeBorderView()
        border.thickness = thickness
        border.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(border, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: container.topAnchor),
            border.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            border.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return border
    }
}

// MARK: - NSColor hex extension
extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        guard hexString.count == 6 else { return nil }
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
