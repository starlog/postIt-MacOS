import Cocoa

protocol FontSettingsDelegate: AnyObject {
    func fontSettingsDidSave(fontConfig: FontConfig)
}

class FontSettingsWindowController: NSWindowController {
    weak var fontSettingsDelegate: FontSettingsDelegate?

    private var fontPopup: NSPopUpButton!
    private var sizeField: NSTextField!
    private var sizeStepper: NSStepper!
    private var previewLabel: NSTextField!

    private let fontOptions: [(display: String, name: String)] = [
        ("시스템 기본", "System"),
        ("Apple SD 고딕 Neo", "AppleSDGothicNeo-Regular"),
        ("나눔고딕", "NanumGothic"),
        ("나눔명조", "NanumMyeongjo"),
        ("나눔바른고딕", "NanumBarunGothic"),
        ("D2 코딩", "D2Coding"),
        ("Apple 명조", "AppleMyungjo"),
        ("나눔손글씨 펜", "NanumPen")
    ]

    init(currentFont: FontConfig) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Default Font"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI(currentFont: currentFont)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(currentFont: FontConfig) {
        guard let contentView = window?.contentView else { return }

        // Font label
        let fontLabel = NSTextField(labelWithString: "Font:")
        fontLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fontLabel)

        // Font popup
        fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fontPopup.translatesAutoresizingMaskIntoConstraints = false
        for font in fontOptions {
            fontPopup.addItem(withTitle: font.display)
        }
        // Select current
        if let idx = fontOptions.firstIndex(where: { $0.name == currentFont.fontName }) {
            fontPopup.selectItem(at: idx)
        }
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged(_:))
        contentView.addSubview(fontPopup)

        // Size label
        let sizeLabel = NSTextField(labelWithString: "Size:")
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sizeLabel)

        // Size field
        sizeField = NSTextField()
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.stringValue = "\(Int(currentFont.fontSize))"
        sizeField.alignment = .center
        sizeField.delegate = self
        contentView.addSubview(sizeField)

        // Size stepper
        sizeStepper = NSStepper()
        sizeStepper.translatesAutoresizingMaskIntoConstraints = false
        sizeStepper.minValue = 8
        sizeStepper.maxValue = 72
        sizeStepper.integerValue = Int(currentFont.fontSize)
        sizeStepper.target = self
        sizeStepper.action = #selector(stepperChanged(_:))
        contentView.addSubview(sizeStepper)

        // Preview
        previewLabel = NSTextField(labelWithString: "가나다 ABC 123 Preview")
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.alignment = .center
        previewLabel.wantsLayer = true
        previewLabel.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        previewLabel.layer?.cornerRadius = 4
        contentView.addSubview(previewLabel)
        updatePreview()

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
            fontLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            fontLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            fontLabel.widthAnchor.constraint(equalToConstant: 40),

            fontPopup.centerYAnchor.constraint(equalTo: fontLabel.centerYAnchor),
            fontPopup.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 8),
            fontPopup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            sizeLabel.topAnchor.constraint(equalTo: fontLabel.bottomAnchor, constant: 16),
            sizeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            sizeLabel.widthAnchor.constraint(equalToConstant: 40),

            sizeField.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            sizeField.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 8),
            sizeField.widthAnchor.constraint(equalToConstant: 50),
            sizeField.heightAnchor.constraint(equalToConstant: 24),

            sizeStepper.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            sizeStepper.leadingAnchor.constraint(equalTo: sizeField.trailingAnchor, constant: 4),

            previewLabel.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 16),
            previewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            previewLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            previewLabel.heightAnchor.constraint(equalToConstant: 40),

            saveBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            saveBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            saveBtn.widthAnchor.constraint(equalToConstant: 80),

            cancelBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80)
        ])
    }

    private func updatePreview() {
        let idx = fontPopup.indexOfSelectedItem
        let fontName = fontOptions[idx].name
        let size = CGFloat(sizeStepper.integerValue)
        let font: NSFont
        if fontName == "System" {
            font = NSFont.systemFont(ofSize: size)
        } else {
            font = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        }
        previewLabel.font = font
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        updatePreview()
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        sizeField.stringValue = "\(sender.integerValue)"
        updatePreview()
    }

    @objc private func saveClicked(_ sender: NSButton) {
        let idx = fontPopup.indexOfSelectedItem
        let fontName = fontOptions[idx].name
        let size = Double(sizeStepper.integerValue)
        let config = FontConfig(fontName: fontName, fontSize: size)
        fontSettingsDelegate?.fontSettingsDidSave(fontConfig: config)
        window?.close()
    }

    @objc private func cancelClicked(_ sender: NSButton) {
        window?.close()
    }
}

extension FontSettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let value = Int(sizeField.stringValue), value >= 8, value <= 72 {
            sizeStepper.integerValue = value
            updatePreview()
        }
    }
}
