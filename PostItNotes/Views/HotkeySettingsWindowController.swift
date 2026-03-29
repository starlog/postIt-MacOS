import Cocoa
import Carbon

protocol HotkeySettingsDelegate: AnyObject {
    func hotkeySettingsDidSave(modifiers: UInt32, keyCode: UInt32, enabled: Bool)
}

class HotkeySettingsWindowController: NSWindowController {
    weak var settingsDelegate: HotkeySettingsDelegate?

    private var enabledCheckbox: NSButton!
    private var hotkeyLabel: NSTextField!
    private var capturedModifiers: UInt32 = 0
    private var capturedKeyCode: UInt32 = 0
    private var isCapturing = false
    private var hotkeyField: NSTextField!

    init(currentModifiers: UInt32, currentKeyCode: UInt32, currentEnabled: Bool) {
        self.capturedModifiers = currentModifiers
        self.capturedKeyCode = currentKeyCode

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hotkey Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI(enabled: currentEnabled, modifiers: currentModifiers, keyCode: currentKeyCode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(enabled: Bool, modifiers: UInt32, keyCode: UInt32) {
        guard let contentView = window?.contentView else { return }

        // Enable checkbox
        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Toggle Hotkey", target: nil, action: nil)
        enabledCheckbox.translatesAutoresizingMaskIntoConstraints = false
        enabledCheckbox.state = enabled ? .on : .off
        contentView.addSubview(enabledCheckbox)

        // Label
        let label = NSTextField(labelWithString: "Press hotkey combination:")
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        // Hotkey display field
        hotkeyField = NSTextField()
        hotkeyField.translatesAutoresizingMaskIntoConstraints = false
        hotkeyField.isEditable = false
        hotkeyField.isBezeled = true
        hotkeyField.bezelStyle = .roundedBezel
        hotkeyField.alignment = .center
        hotkeyField.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        hotkeyField.stringValue = HotkeyService.hotkeyDisplayString(modifiers: modifiers, keyCode: keyCode)
        contentView.addSubview(hotkeyField)

        // Instructions
        let instructions = NSTextField(wrappingLabelWithString: "Click the field above, then press your desired key combination (e.g., \u{2318}\u{21E7}N)")
        instructions.translatesAutoresizingMaskIntoConstraints = false
        instructions.font = NSFont.systemFont(ofSize: 11)
        instructions.textColor = .secondaryLabelColor
        contentView.addSubview(instructions)

        // Buttons
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked(_:)))
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.keyEquivalent = "\r"
        contentView.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            enabledCheckbox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            enabledCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            label.topAnchor.constraint(equalTo: enabledCheckbox.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            hotkeyField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            hotkeyField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hotkeyField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            hotkeyField.heightAnchor.constraint(equalToConstant: 32),

            instructions.topAnchor.constraint(equalTo: hotkeyField.bottomAnchor, constant: 8),
            instructions.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            instructions.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            saveBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            saveBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            saveBtn.widthAnchor.constraint(equalToConstant: 80),

            cancelBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80)
        ])
    }

    override func keyDown(with event: NSEvent) {
        // Ignore modifier-only keys
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 55 || event.keyCode == 54 || event.keyCode == 56 ||
           event.keyCode == 60 || event.keyCode == 58 || event.keyCode == 61 ||
           event.keyCode == 59 || event.keyCode == 62 {
            return
        }

        var carbonMods: UInt32 = 0
        if modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }

        // Require at least one modifier
        guard carbonMods != 0 else { return }

        capturedModifiers = carbonMods
        capturedKeyCode = UInt32(event.keyCode)
        hotkeyField.stringValue = HotkeyService.hotkeyDisplayString(modifiers: capturedModifiers, keyCode: capturedKeyCode)
    }

    @objc private func saveClicked(_ sender: NSButton) {
        let enabled = enabledCheckbox.state == .on
        settingsDelegate?.hotkeySettingsDidSave(modifiers: capturedModifiers, keyCode: capturedKeyCode, enabled: enabled)
        window?.close()
    }

    @objc private func cancelClicked(_ sender: NSButton) {
        window?.close()
    }
}
