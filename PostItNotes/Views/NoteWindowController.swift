import Cocoa

protocol NoteWindowControllerDelegate: AnyObject {
    /// Window closed by the user - the note is kept and marked closed.
    func noteWindowDidClose(_ controller: NoteWindowController)
    /// The note was permanently deleted from storage.
    func noteWindowDidDelete(_ controller: NoteWindowController)
    func noteWindowRequestNewNote(_ controller: NoteWindowController)
}

/// Floating single-note window. All editing behaviour lives in
/// NoteEditorViewController; this only owns the window chrome and geometry.
class NoteWindowController: NSWindowController {
    /// The Format menu reaches the note body through this.
    let editor: NoteEditorViewController
    weak var delegate: NoteWindowControllerDelegate?

    init(note: PostItNote, noteService: NoteService) {
        editor = NoteEditorViewController(note: note, noteService: noteService)

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
        window.delegate = self
        NSLog("[PostItNotes] Creating note window at (%f, %f) size (%fx%f)", note.x, note.y, note.width, note.height)

        editor.delegate = self
        editor.view.wantsLayer = true
        editor.view.layer?.cornerRadius = 6
        editor.view.layer?.masksToBounds = true
        window.contentView = editor.view

        // Dragging the toolbar moves the borderless window
        let dragGesture = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        editor.titleBarView.addGestureRecognizer(dragGesture)

        // Borderless windows only expose a couple of points of resize edge - widen it.
        // Kept a little thinner than the tab window so it overlaps the 28pt toolbar less.
        ResizeBorderView.install(in: editor.view, thickness: 8)

        NSLog("[PostItNotes] Window frame: %@, isVisible: %d", NSStringFromRect(window.frame), window.isVisible)

        // Geometry is persisted from the NSWindowDelegate callbacks below.
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func getNoteId() -> UUID {
        return editor.noteId
    }

    /// Repositions the window during a layout pass. The move/resize
    /// notifications are ignored while it runs so the rearrangement is written
    /// to notes.json once by the caller rather than twice per window here.
    func applyFrame(_ frame: NSRect) {
        guard let window = self.window else { return }
        isApplyingLayout = true
        window.setFrame(frame, display: true)
        isApplyingLayout = false
        editor.setGeometry(x: Double(frame.origin.x), y: Double(frame.origin.y),
                           width: Double(frame.size.width), height: Double(frame.size.height))
    }

    // MARK: - Window dragging

    private var isApplyingLayout = false
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

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingLayout, let frame = window?.frame else { return }
        editor.updateGeometry(x: Double(frame.origin.x), y: Double(frame.origin.y),
                              width: Double(frame.size.width), height: Double(frame.size.height))
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingLayout, let frame = window?.frame else { return }
        editor.updateGeometry(x: Double(frame.origin.x), y: Double(frame.origin.y),
                              width: Double(frame.size.width), height: Double(frame.size.height))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - NSWindowDelegate
extension NoteWindowController: NSWindowDelegate {
    /// Hands the note's own stack to the title field's editor too, so one note
    /// means one undo history no matter which field the edit happened in.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        return editor.contentUndoManager
    }
}

// MARK: - NoteEditorDelegate
extension NoteWindowController: NoteEditorDelegate {
    func noteEditorRequestsNewNote(_ editor: NoteEditorViewController) {
        delegate?.noteWindowRequestNewNote(self)
    }

    func noteEditorRequestsClose(_ editor: NoteEditorViewController) {
        window?.close()
        delegate?.noteWindowDidClose(self)
    }

    func noteEditorRequestsDelete(_ editor: NoteEditorViewController) {
        editor.deleteNoteFromStorage()
        window?.close()
        delegate?.noteWindowDidDelete(self)
    }

    func noteEditorDidChangeTitle(_ editor: NoteEditorViewController) {
        // Window mode shows the title inline; nothing extra to refresh.
    }

    func noteEditorDidChangeColor(_ editor: NoteEditorViewController) {
        // The editor repaints its own background.
    }
}

// MARK: - Custom borderless window that accepts key events
class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    func setupImageDrop() {
        contentView?.registerForDraggedTypes([.fileURL])
    }

    // Bold/italic/underline/strikethrough live in the Format menu: while the
    // text view is first responder it swallows the key event, so keyDown here
    // would never see it. Menu key equivalents are checked before that.
}
