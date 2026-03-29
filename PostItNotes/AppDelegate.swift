import Cocoa
import Carbon

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var configService: ConfigService!
    private var noteService: NoteService!
    private var hotkeyService: HotkeyService!
    private var noteWindows: [UUID: NoteWindowController] = [:]
    private var notesVisible = true
    private var hotkeySettingsController: HotkeySettingsWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[PostItNotes] App launched")

        // Initialize services
        configService = ConfigService()
        let dataDir = configService.getDataDirectory()
        NSLog("[PostItNotes] Data directory: %@", dataDir)
        noteService = NoteService(dataDirectory: dataDir)
        hotkeyService = HotkeyService()

        // Setup status bar item (menu bar icon)
        setupStatusItem()
        NSLog("[PostItNotes] Status item setup done")

        // Setup global hotkey
        setupHotkey()

        // Load existing notes
        loadAllNotes()
        NSLog("[PostItNotes] Loaded %d notes", noteWindows.count)

        // If no notes exist, create one
        if noteWindows.isEmpty {
            NSLog("[PostItNotes] No notes, creating new one")
            createNewNote()
        }
        NSLog("[PostItNotes] Startup complete, %d windows", noteWindows.count)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showAllNotes()
            if noteWindows.isEmpty {
                createNewNote()
            }
        }
        return true
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "PostItNotes") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
            } else {
                button.title = "📝"
            }
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func createStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            NSGraphicsContext.saveGraphicsState()

            // Yellow background
            let bgColor = NSColor(red: 1.0, green: 1.0, blue: 0.53, alpha: 1.0)
            bgColor.setFill()
            let bgRect = NSRect(x: 1, y: 1, width: 16, height: 16)
            let path = NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2)
            path.fill()

            // Border
            NSColor.darkGray.setStroke()
            path.lineWidth = 1.0
            path.stroke()

            // Lines on the note
            NSColor.darkGray.withAlphaComponent(0.6).setStroke()
            let line1 = NSBezierPath()
            line1.move(to: NSPoint(x: 4, y: 6))
            line1.line(to: NSPoint(x: 14, y: 6))
            line1.lineWidth = 1.0
            line1.stroke()

            let line2 = NSBezierPath()
            line2.move(to: NSPoint(x: 4, y: 9))
            line2.line(to: NSPoint(x: 14, y: 9))
            line2.lineWidth = 1.0
            line2.stroke()

            let line3 = NSBezierPath()
            line3.move(to: NSPoint(x: 4, y: 12))
            line3.line(to: NSPoint(x: 10, y: 12))
            line3.lineWidth = 1.0
            line3.stroke()

            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            // Left click - toggle notes or show menu
            showMenu()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let newNoteItem = NSMenuItem(title: "New Note", action: #selector(createNewNote), keyEquivalent: "n")
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        menu.addItem(NSMenuItem.separator())

        if notesVisible {
            let hideItem = NSMenuItem(title: "Hide Notes", action: #selector(hideAllNotes), keyEquivalent: "")
            hideItem.target = self
            menu.addItem(hideItem)
        } else {
            let showItem = NSMenuItem(title: "Show Notes", action: #selector(showAllNotes), keyEquivalent: "")
            showItem.target = self
            menu.addItem(showItem)
        }

        menu.addItem(NSMenuItem.separator())

        let dataFolderItem = NSMenuItem(title: "Data Folder...", action: #selector(changeDataFolder), keyEquivalent: "")
        dataFolderItem.target = self
        menu.addItem(dataFolderItem)

        let hotkeyItem = NSMenuItem(title: "Hotkey Settings...", action: #selector(openHotkeySettings), keyEquivalent: "")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let config = configService.getHotkeyConfig()
        guard config.enabled else { return }

        hotkeyService.hotkeyPressed = { [weak self] in
            self?.toggleNotesVisibility()
        }
        hotkeyService.register(modifiers: config.modifiers, keyCode: config.keyCode)
    }

    private func toggleNotesVisibility() {
        if notesVisible {
            hideAllNotes()
        } else {
            showAllNotes()
        }
    }

    // MARK: - Note Management

    private func loadAllNotes() {
        let notes = noteService.getAllNotes()
        for note in notes {
            openNoteWindow(note)
        }
    }

    private func openNoteWindow(_ note: PostItNote) {
        // Ensure note is within visible screen area
        var fixedNote = note
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            let noteRect = NSRect(x: fixedNote.x, y: fixedNote.y, width: fixedNote.width, height: fixedNote.height)
            if !visibleFrame.intersects(noteRect) {
                fixedNote.x = Double(visibleFrame.midX) - fixedNote.width / 2
                fixedNote.y = Double(visibleFrame.midY) - fixedNote.height / 2
                noteService.updateNote(fixedNote)
            }
        }

        let controller = NoteWindowController(note: fixedNote, noteService: noteService)
        controller.delegate = self
        noteWindows[note.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func createNewNote() {
        // Place note in center of main screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let offset = Double(noteWindows.count % 10) * 30
        let noteWidth = 375.0
        let noteHeight = 250.0
        let x = Double(screenFrame.midX) - noteWidth / 2 + offset
        let y = Double(screenFrame.midY) - noteHeight / 2 + offset
        let note = noteService.createNote(x: x, y: y, width: noteWidth, height: noteHeight)
        openNoteWindow(note)
    }

    @objc func showAllNotes() {
        for (_, controller) in noteWindows {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            controller.window?.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        notesVisible = true
    }

    @objc func hideAllNotes() {
        for (_, controller) in noteWindows {
            controller.window?.orderOut(nil)
        }
        notesVisible = false
    }

    @objc func changeDataFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose data storage folder"

        if panel.runModal() == .OK, let url = panel.url {
            // Close all current note windows
            for (_, controller) in noteWindows {
                controller.window?.close()
            }
            noteWindows.removeAll()

            // Update config and reload
            configService.setDataDirectory(url.path)
            noteService.changeDataDirectory(url.path)

            // Load notes from new location
            loadAllNotes()
        }
    }

    @objc func openHotkeySettings() {
        let config = configService.getHotkeyConfig()
        let controller = HotkeySettingsWindowController(
            currentModifiers: config.modifiers,
            currentKeyCode: config.keyCode,
            currentEnabled: config.enabled
        )
        controller.settingsDelegate = self
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hotkeySettingsController = controller
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NoteWindowControllerDelegate
extension AppDelegate: NoteWindowControllerDelegate {
    func noteWindowDidClose(_ controller: NoteWindowController) {
        noteWindows.removeValue(forKey: controller.getNoteId())
    }

    func noteWindowRequestNewNote(_ controller: NoteWindowController) {
        createNewNote()
    }
}

// MARK: - HotkeySettingsDelegate
extension AppDelegate: HotkeySettingsDelegate {
    func hotkeySettingsDidSave(modifiers: UInt32, keyCode: UInt32, enabled: Bool) {
        let config = HotkeyConfig(modifiers: modifiers, keyCode: keyCode, enabled: enabled)
        configService.setHotkeyConfig(config)

        hotkeyService.unregister()
        if enabled {
            hotkeyService.hotkeyPressed = { [weak self] in
                self?.toggleNotesVisibility()
            }
            hotkeyService.register(modifiers: modifiers, keyCode: keyCode)
        }
    }
}
