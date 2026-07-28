import Cocoa

/// Lays notes out on a screen so they overlap as little as possible.
///
/// Notes are shelf-packed left to right and top to bottom: a row is as tall as
/// its tallest note, and a note that no longer fits horizontally starts the next
/// row. Tall notes go first so rows stay tightly packed. Note sizes are kept as
/// the user set them - only a note larger than the screen is clamped.
///
/// When the rows do not fit vertically the gaps between them are shrunk
/// proportionally, so whatever overlap is unavoidable is spread evenly over all
/// rows instead of piling up on the last one.
enum NoteArranger {
    /// Distance kept from the edges of the screen.
    static let margin: CGFloat = 12
    /// Distance kept between two notes.
    static let gap: CGFloat = 12

    /// - Returns: the new frame for each note, keyed by note id.
    static func arrange(_ notes: [PostItNote], in visibleFrame: NSRect) -> [UUID: NSRect] {
        guard !notes.isEmpty else { return [:] }

        let availableWidth = max(visibleFrame.width - margin * 2, 1)
        let availableHeight = max(visibleFrame.height - margin * 2, 1)

        // Tallest first packs the shelves tighter; createdAt keeps the result
        // stable for the common case of equally sized notes.
        let ordered = notes.sorted {
            if $0.height != $1.height { return $0.height > $1.height }
            return $0.createdAt < $1.createdAt
        }

        // Split into rows, never letting a note exceed the screen itself.
        var rows: [[(id: UUID, size: NSSize)]] = []
        var row: [(id: UUID, size: NSSize)] = []
        var rowWidth: CGFloat = 0

        for note in ordered {
            let size = NSSize(width: min(CGFloat(note.width), availableWidth),
                              height: min(CGFloat(note.height), availableHeight))
            if !row.isEmpty && rowWidth + gap + size.width > availableWidth {
                rows.append(row)
                row = []
                rowWidth = 0
            }
            rowWidth = row.isEmpty ? size.width : rowWidth + gap + size.width
            row.append((note.id, size))
        }
        if !row.isEmpty { rows.append(row) }

        let rowHeights = rows.map { $0.map { $0.size.height }.max() ?? 0 }

        // Distance of every row from the top edge, squeezed if the rows overflow.
        var offsets: [CGFloat] = []
        var offset: CGFloat = 0
        for height in rowHeights {
            offsets.append(offset)
            offset += height + gap
        }
        let contentHeight = (offsets.last ?? 0) + (rowHeights.last ?? 0)
        if contentHeight > availableHeight, let lastOffset = offsets.last, lastOffset > 0 {
            // Scale so the bottom row ends exactly on the bottom margin.
            let scale = max((availableHeight - (rowHeights.last ?? 0)) / lastOffset, 0)
            offsets = offsets.map { $0 * scale }
        }

        var frames: [UUID: NSRect] = [:]
        for (index, row) in rows.enumerated() {
            let contentWidth = row.reduce(0) { $0 + $1.size.width } + gap * CGFloat(row.count - 1)
            // Centre each row so a half-filled last row does not look ragged.
            var x = visibleFrame.minX + margin + max((availableWidth - contentWidth) / 2, 0)
            let rowTop = visibleFrame.maxY - margin - offsets[index]

            for item in row {
                // AppKit origins are bottom-left, so subtract the height.
                frames[item.id] = NSRect(x: x,
                                         y: rowTop - item.size.height,
                                         width: item.size.width,
                                         height: item.size.height)
                x += item.size.width + gap
            }
        }
        return frames
    }
}

// MARK: - Screens

extension NSScreen {
    /// Stable identifier of the display, so a menu selection still refers to the
    /// right screen if the screen list changes between building and clicking.
    var displayID: CGDirectDisplayID? {
        return (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        return screens.first { $0.displayID == id }
    }

    /// "Built-in Display (1920 × 1080)" - used as the menu title.
    var menuDescription: String {
        let size = frame.size
        return "\(localizedName) (\(Int(size.width)) × \(Int(size.height)))"
    }
}
