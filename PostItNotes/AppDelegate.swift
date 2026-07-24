import Cocoa
import Carbon

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var configService: ConfigService!
    private var noteService: NoteService!
    private var hotkeyService: HotkeyService!
    private var noteWindows: [UUID: NoteWindowController] = [:]
    private var tabWindowController: TabWindowController?
    private var viewMode: ViewMode = .windows
    private var notesVisible = true
    private var hotkeySettingsController: HotkeySettingsWindowController?
    private var fontSettingsController: FontSettingsWindowController?
    private weak var tabModeMenuItem: NSMenuItem?
    private weak var showHideMenuItem: NSMenuItem?

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
        viewMode = configService.getViewMode()
        NSLog("[PostItNotes] View mode: %@", viewMode.rawValue)

        // Setup main menu with Edit menu for standard shortcuts
        setupMainMenu()

        // Setup status bar item (menu bar icon)
        setupStatusItem()
        NSLog("[PostItNotes] Status item setup done")

        // Setup global hotkey
        setupHotkey()

        // Restore the last used presentation
        if viewMode == .tabs {
            openTabWindow()
        } else {
            loadAllNotes()
            NSLog("[PostItNotes] Loaded %d notes", noteWindows.count)

            // Start with one note on a fresh install. If notes exist but are all
            // closed, respect that and leave the screen empty.
            if noteWindows.isEmpty && noteService.getAllNotes().isEmpty {
                NSLog("[PostItNotes] No notes, creating new one")
                createNewNote()
            }
        }
        NSLog("[PostItNotes] Startup complete, %d windows", noteWindows.count)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleNotesVisibility()
        if viewMode == .tabs {
            if tabWindowController == nil {
                openTabWindow()
            }
        } else if noteWindows.isEmpty {
            createNewNote()
        }
        return false
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About PostItNotes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit PostItNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.delegate = self

        // Title flips between Hide/Show - kept current in menuNeedsUpdate
        let showHideItem = NSMenuItem(title: "Hide Notes", action: #selector(toggleShowHideNotes), keyEquivalent: "h")
        showHideItem.keyEquivalentModifierMask = [.command, .shift]
        showHideItem.target = self
        viewMenu.addItem(showHideItem)
        showHideMenuItem = showHideItem

        viewMenu.addItem(NSMenuItem.separator())

        let tabModeItem = NSMenuItem(title: "Tab Mode", action: #selector(toggleTabMode), keyEquivalent: "t")
        tabModeItem.keyEquivalentModifierMask = [.command, .shift]
        tabModeItem.target = self
        tabModeItem.state = viewMode == .tabs ? .on : .off
        viewMenu.addItem(tabModeItem)
        tabModeMenuItem = tabModeItem

        viewMenu.addItem(NSMenuItem.separator())

        let closedItem = NSMenuItem(title: "Closed Notes", action: nil, keyEquivalent: "")
        closedItem.submenu = makeClosedNotesMenu()
        viewMenu.addItem(closedItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Settings menu
        let settingsMenuItem = NSMenuItem()
        let settingsMenu = NSMenu(title: "Settings")

        let hotkeyItem = NSMenuItem(title: "Set Hotkey...", action: #selector(openHotkeySettings), keyEquivalent: "")
        hotkeyItem.target = self
        settingsMenu.addItem(hotkeyItem)

        let fontItem = NSMenuItem(title: "Set Default Font...", action: #selector(openFontSettings), keyEquivalent: "")
        fontItem.target = self
        settingsMenu.addItem(fontItem)

        settingsMenu.addItem(NSMenuItem.separator())

        let dataFolderItem = NSMenuItem(title: "Data Folder...", action: #selector(changeDataFolder), keyEquivalent: "")
        dataFolderItem.target = self
        settingsMenu.addItem(dataFolderItem)

        settingsMenuItem.submenu = settingsMenu
        mainMenu.addItem(settingsMenuItem)

        NSApp.mainMenu = mainMenu
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

        let tabModeItem = NSMenuItem(title: "Tab Mode", action: #selector(toggleTabMode), keyEquivalent: "")
        tabModeItem.target = self
        tabModeItem.state = viewMode == .tabs ? .on : .off
        menu.addItem(tabModeItem)

        let closedItem = NSMenuItem(title: "Closed Notes", action: nil, keyEquivalent: "")
        closedItem.submenu = makeClosedNotesMenu()
        menu.addItem(closedItem)

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

    @objc private func toggleShowHideNotes() {
        toggleNotesVisibility()
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
        for note in noteService.getOpenNotes() {
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

    /// Creates the note record itself (no window), so both modes place new notes identically.
    @discardableResult
    private func createNoteRecord() -> PostItNote {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let offset = Double(noteService.getAllNotes().count % 10) * 30
        let noteWidth = 375.0
        let noteHeight = 250.0
        let x = Double(screenFrame.midX) - noteWidth / 2 + offset
        let y = Double(screenFrame.midY) - noteHeight / 2 + offset
        return noteService.createNote(x: x, y: y, width: noteWidth, height: noteHeight)
    }

    @objc func createNewNote() {
        if viewMode == .tabs {
            if tabWindowController == nil {
                openTabWindow()
            } else if !notesVisible {
                showAllNotes()
            }
            tabWindowController?.addNewNote()
            return
        }
        openNoteWindow(createNoteRecord())
    }

    // MARK: - Tab Mode

    private func openTabWindow() {
        if noteService.getAllNotes().isEmpty {
            createNoteRecord()
        }
        // All notes closed: the tab window opens on its empty state instead
        let controller = TabWindowController(noteService: noteService, configService: configService)
        controller.tabDelegate = self
        tabWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        notesVisible = true
    }

    // MARK: - Closed Notes

    /// Menu of closed notes; rebuilt on open via NSMenuDelegate so it is never stale.
    private func makeClosedNotesMenu() -> NSMenu {
        let menu = NSMenu(title: "Closed Notes")
        menu.delegate = self
        return menu
    }

    private func rebuildClosedNotesMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let closed = noteService.getClosedNotes()

        guard !closed.isEmpty else {
            let empty = NSMenuItem(title: "No closed notes", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for note in closed {
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = title.isEmpty ? NoteEditorViewController.contentSummary(note.content) : title
            let item = NSMenuItem(title: label, action: #selector(reopenClosedNote(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = note.id
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let reopenAll = NSMenuItem(title: "Reopen All", action: #selector(reopenAllClosedNotes), keyEquivalent: "")
        reopenAll.target = self
        menu.addItem(reopenAll)
    }

    @objc private func reopenClosedNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        reopenNote(id: id)
    }

    @objc private func reopenAllClosedNotes() {
        for note in noteService.getClosedNotes() {
            reopenNote(id: note.id)
        }
    }

    private func reopenNote(id: UUID) {
        if viewMode == .tabs {
            if tabWindowController == nil {
                openTabWindow()
            } else if !notesVisible {
                showAllNotes()
            }
            tabWindowController?.reopenNote(id: id)
            return
        }

        noteService.setClosed(id: id, closed: false)
        guard let note = noteService.getOpenNotes().first(where: { $0.id == id }) else { return }
        if let existing = noteWindows[id] {
            existing.window?.makeKeyAndOrderFront(nil)
            existing.window?.orderFrontRegardless()
        } else {
            openNoteWindow(note)
        }
        notesVisible = true
    }

    /// Switches between one-window-per-note and the single tabbed window.
    /// Notes are only re-presented here - nothing is written to notes.json.
    @objc func toggleTabMode() {
        if viewMode == .tabs {
            tabWindowController?.window?.close()
            tabWindowController = nil
            viewMode = .windows
            configService.setViewMode(.windows)
            loadAllNotes()
            if noteWindows.isEmpty {
                createNewNote()
            }
            notesVisible = true
        } else {
            for (_, controller) in noteWindows {
                controller.window?.close()
            }
            noteWindows.removeAll()
            viewMode = .tabs
            configService.setViewMode(.tabs)
            openTabWindow()
        }
        tabModeMenuItem?.state = viewMode == .tabs ? .on : .off
        NSLog("[PostItNotes] Switched to %@ mode", viewMode.rawValue)
    }

    @objc func showAllNotes() {
        if viewMode == .tabs {
            if tabWindowController == nil {
                openTabWindow()
            } else {
                tabWindowController?.showWindow(nil)
                tabWindowController?.window?.makeKeyAndOrderFront(nil)
                tabWindowController?.window?.orderFrontRegardless()
            }
        } else {
            for (_, controller) in noteWindows {
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                controller.window?.orderFrontRegardless()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        notesVisible = true
    }

    @objc func hideAllNotes() {
        if viewMode == .tabs {
            tabWindowController?.window?.orderOut(nil)
        } else {
            for (_, controller) in noteWindows {
                controller.window?.orderOut(nil)
            }
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
            // Tear down whatever is on screen (windows or the tab window)
            for (_, controller) in noteWindows {
                controller.window?.close()
            }
            noteWindows.removeAll()
            tabWindowController?.window?.close()
            tabWindowController = nil

            // Update config and reload
            configService.setDataDirectory(url.path)
            noteService.changeDataDirectory(url.path)

            // Load notes from new location
            if viewMode == .tabs {
                openTabWindow()
            } else {
                loadAllNotes()
                if noteWindows.isEmpty {
                    createNewNote()
                }
            }
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

    @objc func openFontSettings() {
        let fontConfig = configService.getDefaultFont()
        let controller = FontSettingsWindowController(currentFont: fontConfig)
        controller.fontSettingsDelegate = self
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fontSettingsController = controller
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NoteWindowControllerDelegate
extension AppDelegate: NoteWindowControllerDelegate {
    func noteWindowDidClose(_ controller: NoteWindowController) {
        let id = controller.getNoteId()
        noteWindows.removeValue(forKey: id)
        noteService.setClosed(id: id, closed: true)
    }

    func noteWindowDidDelete(_ controller: NoteWindowController) {
        noteWindows.removeValue(forKey: controller.getNoteId())
    }

    func noteWindowRequestNewNote(_ controller: NoteWindowController) {
        createNewNote()
    }
}

// MARK: - NSMenuDelegate (keeps the Closed Notes list current)
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.title {
        case "Closed Notes":
            rebuildClosedNotesMenu(menu)
        case "View":
            showHideMenuItem?.title = notesVisible ? "Hide Notes" : "Show Notes"
            tabModeMenuItem?.state = viewMode == .tabs ? .on : .off
        default:
            break
        }
    }
}

// MARK: - TabWindowControllerDelegate
extension AppDelegate: TabWindowControllerDelegate {
    func tabWindowCreateNote(_ controller: TabWindowController) -> PostItNote {
        return createNoteRecord()
    }

    func tabWindowRequestsHide(_ controller: TabWindowController) {
        hideAllNotes()
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

// MARK: - FontSettingsDelegate
extension AppDelegate: FontSettingsDelegate {
    func fontSettingsDidSave(fontConfig: FontConfig) {
        configService.setDefaultFont(fontConfig)
    }
}
