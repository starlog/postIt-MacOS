import Cocoa

protocol NoteWindowControllerDelegate: AnyObject {
    func noteWindowDidClose(_ controller: NoteWindowController)
    func noteWindowRequestNewNote(_ controller: NoteWindowController)
}

class NoteWindowController: NSWindowController {
    private var note: PostItNote
    private let noteService: NoteService
    weak var delegate: NoteWindowControllerDelegate?

    private var titleField: NSTextField!
    private var contentView: NSTextView!
    private var scrollView: NSScrollView!
    private var titleBarView: NSView!

    private let colorOptions: [(name: String, hex: String)] = [
        ("Yellow", "#FFFF88"),
        ("Green", "#88FF88"),
        ("Cyan", "#88FFFF"),
        ("Magenta", "#FF88FF"),
        ("Orange", "#FFBB55")
    ]

    init(note: PostItNote, noteService: NoteService) {
        self.note = note
        self.noteService = noteService

        let window = NoteWindow(
            contentRect: NSRect(x: note.x, y: note.y, width: note.width, height: note.height),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.minSize = NSSize(width: 150, height: 120)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear

        super.init(window: window)
        NSLog("[PostItNotes] Creating note window at (%f, %f) size (%fx%f)", note.x, note.y, note.width, note.height)
        setupUI()
        applyColor(note.color)
        loadNoteData()
        NSLog("[PostItNotes] Window frame: %@, isVisible: %d", NSStringFromRect(window.frame), window.isVisible)

        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove(_:)), name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let container = NSView(frame: window.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        window.contentView = container

        // Title bar area
        titleBarView = NSView()
        titleBarView.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.wantsLayer = true
        container.addSubview(titleBarView)

        // Make title bar draggable
        let dragGesture = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        titleBarView.addGestureRecognizer(dragGesture)

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

        // Close button (X)
        let closeBtn = NSButton(frame: .zero)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.isBordered = false
        closeBtn.title = "\u{2715}"
        closeBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        closeBtn.target = self
        closeBtn.action = #selector(closeNoteClicked(_:))
        closeBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleBarView.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            closeBtn.trailingAnchor.constraint(equalTo: titleBarView.trailingAnchor, constant: -6),
            closeBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 22),
            newBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -2),
            newBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            newBtn.widthAnchor.constraint(equalToConstant: 22)
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

        // Separator
        let separator = NSBox()
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

        contentView = NSTextView()
        contentView.isRichText = true
        contentView.usesFontPanel = false
        contentView.usesRuler = false
        contentView.font = NSFont.systemFont(ofSize: 13)
        contentView.backgroundColor = .clear
        contentView.isEditable = true
        contentView.isSelectable = true
        contentView.textContainerInset = NSSize(width: 5, height: 5)
        contentView.isVerticallyResizable = true
        contentView.isHorizontallyResizable = false
        contentView.autoresizingMask = [.width]
        contentView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        contentView.textContainer?.widthTracksTextView = true
        contentView.delegate = self

        scrollView.documentView = contentView
        container.addSubview(scrollView)

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

            separator.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func loadNoteData() {
        titleField.stringValue = note.title
        if let rtfString = note.rtfContent,
           let rtfData = Data(base64Encoded: rtfString),
           let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            contentView.textStorage?.setAttributedString(attrString)
        } else {
            contentView.string = note.content
        }
    }

    private func saveContent() {
        note.content = contentView.string
        if let textStorage = contentView.textStorage {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            if let rtfData = textStorage.rtf(from: fullRange, documentAttributes: [:]) {
                note.rtfContent = rtfData.base64EncodedString()
            }
        }
        noteService.updateNote(note)
    }

    @objc func toggleBold(_ sender: Any?) {
        guard let textStorage = contentView.textStorage else { return }
        let selectedRange = contentView.selectedRange()
        guard selectedRange.length > 0 else { return }

        var isBold = false
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, _, _ in
            if let font = value as? NSFont {
                isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            }
        }

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
        saveContent()
    }

    @objc func toggleItalic(_ sender: Any?) {
        guard let textStorage = contentView.textStorage else { return }
        let selectedRange = contentView.selectedRange()
        guard selectedRange.length > 0 else { return }

        var isItalic = false
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, _, _ in
            if let font = value as? NSFont {
                isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
            }
        }

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
        saveContent()
    }

    @objc func toggleUnderline(_ sender: Any?) {
        guard let textStorage = contentView.textStorage else { return }
        let selectedRange = contentView.selectedRange()
        guard selectedRange.length > 0 else { return }

        var hasUnderline = false
        textStorage.enumerateAttribute(.underlineStyle, in: selectedRange) { value, _, _ in
            if let style = value as? Int, style != 0 {
                hasUnderline = true
            }
        }

        textStorage.beginEditing()
        if hasUnderline {
            textStorage.removeAttribute(.underlineStyle, range: selectedRange)
        } else {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
        }
        textStorage.endEditing()
        saveContent()
    }

    func applyColor(_ hex: String) {
        guard let color = NSColor(hex: hex) else { return }
        window?.contentView?.layer?.backgroundColor = color.cgColor
        titleBarView?.layer?.backgroundColor = color.blended(withFraction: 0.1, of: .black)?.cgColor
    }

    func getNoteId() -> UUID {
        return note.id
    }

    // MARK: - Actions

    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero

    @objc private func handleDrag(_ gesture: NSPanGestureRecognizer) {
        guard let window = self.window else { return }
        if gesture.state == .began {
            initialMouseLocation = NSEvent.mouseLocation
            initialWindowOrigin = window.frame.origin
        }
        let currentMouse = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: initialWindowOrigin.x + (currentMouse.x - initialMouseLocation.x),
            y: initialWindowOrigin.y + (currentMouse.y - initialMouseLocation.y)
        )
        window.setFrameOrigin(newOrigin)
    }

    @objc private func colorButtonClicked(_ sender: NSButton) {
        let hex = colorOptions[sender.tag].hex
        note.color = hex
        applyColor(hex)
        noteService.updateNote(note)
    }

    @objc private func newNoteClicked(_ sender: NSButton) {
        delegate?.noteWindowRequestNewNote(self)
    }

    @objc private func closeNoteClicked(_ sender: NSButton) {
        noteService.deleteNote(id: note.id)
        window?.close()
        delegate?.noteWindowDidClose(self)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let frame = window?.frame else { return }
        note.x = Double(frame.origin.x)
        note.y = Double(frame.origin.y)
        noteService.updateNote(note)
    }

    @objc private func windowDidResize(_ notification: Notification) {
        guard let frame = window?.frame else { return }
        note.width = Double(frame.size.width)
        note.height = Double(frame.size.height)
        noteService.updateNote(note)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - NSTextFieldDelegate
extension NoteWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        note.title = titleField.stringValue
        noteService.updateNote(note)
    }
}

// MARK: - NSTextViewDelegate
extension NoteWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        saveContent()
    }
}

// MARK: - Custom borderless window that accepts key events
class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if let controller = windowController as? NoteWindowController {
                switch event.charactersIgnoringModifiers {
                case "b": controller.toggleBold(nil); return
                case "i": controller.toggleItalic(nil); return
                case "u": controller.toggleUnderline(nil); return
                default: break
                }
            }
        }
        super.keyDown(with: event)
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
