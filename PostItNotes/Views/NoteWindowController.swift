import Cocoa
import WebKit

protocol NoteWindowControllerDelegate: AnyObject {
    func noteWindowDidClose(_ controller: NoteWindowController)
    func noteWindowRequestNewNote(_ controller: NoteWindowController)
}

class NoteWindowController: NSWindowController {
    private var note: PostItNote
    private let noteService: NoteService
    private let claudeService = ClaudeAPIService()
    weak var delegate: NoteWindowControllerDelegate?

    private var titleField: NSTextField!
    private var contentView: NSTextView!
    private var scrollView: NSScrollView!
    private var titleBarView: NSView!
    private var markdownWebView: WKWebView!
    private var markdownToggleBtn: NSButton!
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
        titleBarView = DraggableTitleBarView()
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
            newBtn.widthAnchor.constraint(equalToConstant: 22),
            aiBtn.trailingAnchor.constraint(equalTo: newBtn.leadingAnchor, constant: -2),
            aiBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            aiBtn.widthAnchor.constraint(equalToConstant: 22),
            markdownToggleBtn.trailingAnchor.constraint(equalTo: aiBtn.leadingAnchor, constant: -2),
            markdownToggleBtn.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            markdownToggleBtn.widthAnchor.constraint(equalToConstant: 26),
            fontBtn.trailingAnchor.constraint(equalTo: markdownToggleBtn.leadingAnchor, constant: -2),
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

        // Track mouse for image hover delete button
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(trackingArea)

        // Markdown rendered view
        let webConfig = WKWebViewConfiguration()
        webConfig.userContentController.add(self, name: "deleteImage")
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

            separator.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
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

    private func loadNoteData() {
        titleField.stringValue = note.title
        let content = note.content

        if content.contains("{{IMG:") {
            // Content has image markers - reconstruct with attachments
            loadContentWithImages(content)
        } else if let rtfString = note.rtfContent,
                  let rtfData = Data(base64Encoded: rtfString),
                  let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            contentView.textStorage?.setAttributedString(attrString)
        } else {
            contentView.string = content
        }
    }

    private func loadContentWithImages(_ content: String) {
        let result = NSMutableAttributedString()
        let defaultFont = contentView.font ?? NSFont.systemFont(ofSize: 13)
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

        contentView.textStorage?.setAttributedString(result)
    }

    private func saveContent() {
        // Build content with image path markers for persistence
        guard let textStorage = contentView.textStorage else { return }
        var plainContent = ""
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttributes(in: fullRange) { attrs, range, _ in
            if let path = attrs[Self.imagePathKey] as? String {
                if let sizeVal = attrs[Self.imageSizeKey] as? NSValue {
                    let size = sizeVal.sizeValue
                    plainContent += "{{IMG:\(path):\(Int(size.width))x\(Int(size.height))}}"
                } else {
                    plainContent += "{{IMG:\(path)}}"
                }
            } else if let _ = attrs[.attachment] as? NSTextAttachment {
                // Attachment without path - skip
                plainContent += "{{IMG:unknown}}"
            } else {
                plainContent += (textStorage.string as NSString).substring(with: range)
            }
        }
        note.content = plainContent

        // Also save RTF for styled text (without images)
        if let rtfData = textStorage.rtf(from: fullRange, documentAttributes: [:]) {
            note.rtfContent = rtfData.base64EncodedString()
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

    // MARK: - Font

    @objc private func fontSizeIncrease(_ sender: NSButton) {
        changeFontSize(delta: 1)
    }

    @objc private func fontSizeDecrease(_ sender: NSButton) {
        changeFontSize(delta: -1)
    }

    private func changeFontSize(delta: CGFloat) {
        markdownFontSize = max(8, markdownFontSize + delta)
        if isMarkdownRendered {
            renderMarkdown()
        } else {
            guard let textStorage = contentView.textStorage else { return }
            let range = NSRange(location: 0, length: textStorage.length)
            guard range.length > 0 else { return }
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newSize = max(8, font.pointSize + delta)
                    let newFont = NSFontManager.shared.convert(font, toSize: newSize)
                    textStorage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            textStorage.endEditing()
            saveContent()
        }
    }

    @objc private func fontSelectClicked(_ sender: NSButton) {
        let fonts: [(display: String, name: String)] = [
            ("시스템 기본", "System"),
            ("Apple SD 고딕 Neo", "AppleSDGothicNeo-Regular"),
            ("나눔고딕", "NanumGothic"),
            ("나눔명조", "NanumMyeongjo"),
            ("나눔바른고딕", "NanumBarunGothic"),
            ("D2 코딩", "D2Coding"),
            ("Apple 명조", "AppleMyungjo"),
            ("나눔손글씨 펜", "NanumPen")
        ]
        let menu = NSMenu()
        for font in fonts {
            let item = NSMenuItem(title: font.display, action: #selector(fontSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = font.name
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY), in: sender)
    }

    @objc private func fontSelected(_ sender: NSMenuItem) {
        guard let fontName = sender.representedObject as? String else { return }
        markdownFontName = fontName
        if isMarkdownRendered {
            renderMarkdown()
        } else {
            guard let textStorage = contentView.textStorage else { return }
            let range = NSRange(location: 0, length: textStorage.length)
            guard range.length > 0 else { return }
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                let currentFont = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
                let size = currentFont.pointSize
                let newFont: NSFont
                if fontName == "System" {
                    newFont = NSFont.systemFont(ofSize: size)
                } else {
                    newFont = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
                }
                textStorage.addAttribute(.font, value: newFont, range: attrRange)
            }
            textStorage.endEditing()
            saveContent()
        }
    }

    // MARK: - Markdown

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
        let markdown = contentView.string
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
        window?.contentView?.layer?.backgroundColor = color.cgColor
        titleBarView?.layer?.backgroundColor = color.blended(withFraction: 0.1, of: .black)?.cgColor
        if isMarkdownRendered {
            renderMarkdown()
        }
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

    @objc private func aiButtonClicked(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "AI Assistant"
        alert.informativeText = "Enter your prompt:"
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 294, height: 100))
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 294, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.window.initialFirstResponder = textView

        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let prompt = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return }
            self.sendToAI(prompt: prompt)
        }
    }

    private func buildNoteContentForAI() -> String {
        guard let textStorage = contentView.textStorage else { return contentView.string }
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
                    let currentText = self.contentView.string
                    self.contentView.string = currentText + sep + response
                    self.saveContent()
                    if self.isMarkdownRendered {
                        self.renderMarkdown()
                    }
                case .failure(let error):
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "AI Error"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    if let window = self.window {
                        errorAlert.beginSheetModal(for: window, completionHandler: nil)
                    }
                }
            }
        }
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

    // MARK: - Image Drop

    func handleImageDrop(urls: [URL]) {
        for url in urls {
            let path = url.path
            if isMarkdownRendered {
                let markdownImage = "\n![image](\(path))\n"
                contentView.string += markdownImage
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
        let pointInTextView = contentView.convert(pointInWindow, from: nil)

        guard contentView.bounds.contains(pointInTextView) else {
            hideImageDeleteButton()
            return
        }

        let pointInContainer = NSPoint(
            x: pointInTextView.x - contentView.textContainerInset.width,
            y: pointInTextView.y - contentView.textContainerInset.height
        )

        let charIndex = contentView.layoutManager?.characterIndex(
            for: pointInContainer,
            in: contentView.textContainer!,
            fractionOfDistanceBetweenInsertionPoints: nil
        ) ?? NSNotFound

        guard charIndex != NSNotFound,
              charIndex < (contentView.textStorage?.length ?? 0) else {
            hideImageDeleteButton()
            return
        }

        let attrs = contentView.textStorage?.attributes(at: charIndex, effectiveRange: nil)
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

        guard let layoutManager = contentView.layoutManager,
              let textContainer = contentView.textContainer else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.x += contentView.textContainerInset.width
        lineRect.origin.y += contentView.textContainerInset.height

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
        contentView.addSubview(btn)
        imageDeleteButton = btn
    }

    private func hideImageDeleteButton() {
        imageDeleteButton?.removeFromSuperview()
        imageDeleteButton = nil
        imageDeleteCharIndex = nil
    }

    @objc private func deleteImageAttachment(_ sender: NSButton) {
        guard let charIndex = imageDeleteCharIndex,
              let textStorage = contentView.textStorage,
              charIndex < textStorage.length else { return }
        hideImageDeleteButton()
        textStorage.deleteCharacters(in: NSRange(location: charIndex, length: 1))
        saveContent()
    }

    private func showImageResizeHandle(at charIndex: Int) {
        if resizeImageCharIndex == charIndex, imageResizeHandle != nil { return }

        hideImageResizeHandle()
        resizeImageCharIndex = charIndex

        guard let layoutManager = contentView.layoutManager,
              let textContainer = contentView.textContainer else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += contentView.textContainerInset.width
        rect.origin.y += contentView.textContainerInset.height

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

        contentView.addSubview(handle)
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
              let textStorage = contentView.textStorage,
              charIndex < textStorage.length,
              let attachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
              let cell = attachment.attachmentCell as? NSTextAttachmentCell,
              let image = cell.image else { return }

        if gesture.state == .began {
            isResizingImage = true
            resizeStartSize = image.size
            // Get image origin X
            if let layoutManager = contentView.layoutManager,
               let textContainer = contentView.textContainer {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                resizeImageOriginX = rect.origin.x + contentView.textContainerInset.width
            }
        }

        let currentPoint = gesture.location(in: contentView)
        // Width = mouse X position - image left edge
        let ratio = resizeStartSize.height / resizeStartSize.width
        let newWidth = max(30, currentPoint.x - resizeImageOriginX)
        let newHeight = newWidth * ratio
        let newSize = NSSize(width: newWidth, height: newHeight)

        cell.image?.size = newSize
        textStorage.addAttribute(Self.imageSizeKey, value: NSValue(size: newSize), range: NSRange(location: charIndex, length: 1))

        // Force layout update
        contentView.needsDisplay = true
        contentView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)

        // Update handle position
        if let layoutManager = contentView.layoutManager,
           let textContainer = contentView.textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += contentView.textContainerInset.width
            rect.origin.y += contentView.textContainerInset.height
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
        let insertionPoint = contentView.selectedRange().location
        contentView.textStorage?.insert(attrStr, at: insertionPoint)
        let pathMarker = NSAttributedString(string: "\n")
        contentView.textStorage?.insert(pathMarker, at: insertionPoint + 1)
        saveContent()
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

// MARK: - WKScriptMessageHandler
extension NoteWindowController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "deleteImage", let src = message.body as? String {
            deleteMarkdownImage(src: src)
        }
    }

    private func deleteMarkdownImage(src: String) {
        // Remove the markdown image line matching this src
        let lines = contentView.string.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            // Match ![...](<src>) or ![...](file://<src>)
            if line.contains("![\(line)") { return true } // keep non-image lines
            let pattern = "![" // quick check
            guard line.contains(pattern) else { return true }
            return !line.contains("(\(src))") && !line.contains("(file://\(src))")
        }
        contentView.string = filtered.joined(separator: "\n")
        saveContent()
        renderMarkdown()
    }
}

// MARK: - Custom title bar view that accepts first mouse click
class DraggableTitleBarView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - Custom borderless window that accepts key events
class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    func setupImageDrop() {
        contentView?.registerForDraggedTypes([.fileURL])
    }

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
