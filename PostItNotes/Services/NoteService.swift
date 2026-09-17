import Foundation

class NoteService {
    /// What the last load found. Anything but .ok means the notes on disk were
    /// not read, so saving stays off until the app decides what to do -
    /// otherwise the first save would overwrite the user's real notes.
    enum StoreStatus: Equatable {
        case ok
        /// The data folder is gone: moved, renamed, or a cloud drive not ready yet.
        case directoryMissing
        /// The folder exists but holds no notes.json.
        case fileMissing
        /// notes.json exists but could not be read or decoded.
        case unreadable(String)
    }

    private var notes: [PostItNote] = []
    private var dataDirectory: String
    private(set) var status: StoreStatus = .ok

    init(dataDirectory: String) {
        self.dataDirectory = dataDirectory
        load()
    }

    var filePath: String {
        return (dataDirectory as NSString).appendingPathComponent("notes.json")
    }

    /// Every note in storage, including closed ones.
    func getAllNotes() -> [PostItNote] {
        return notes
    }

    /// Notes that should currently be on screen.
    func getOpenNotes() -> [PostItNote] {
        return notes.filter { !$0.isClosed }
    }

    /// Notes the user closed - kept in storage, reopenable from the menu.
    func getClosedNotes() -> [PostItNote] {
        return notes.filter { $0.isClosed }
    }

    func setClosed(id: UUID, closed: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].closed = closed
        notes[index].modifiedAt = Date()
        save()
    }

    @discardableResult
    func createNote(x: Double = 100, y: Double = 100, width: Double = 250, height: Double = 250) -> PostItNote {
        let note = PostItNote(x: x, y: y, width: width, height: height)
        notes.append(note)
        save()
        return note
    }

    func updateNote(_ note: PostItNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updated = note
            updated.modifiedAt = Date()
            notes[index] = updated
            save()
        }
    }

    /// Writes many geometry changes at once - used when notes are rearranged,
    /// so a layout pass costs a single save instead of one per note.
    func updateGeometries(_ geometries: [UUID: CGRect]) {
        var changed = false
        for (id, rect) in geometries {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            notes[index].x = Double(rect.origin.x)
            notes[index].y = Double(rect.origin.y)
            notes[index].width = Double(rect.size.width)
            notes[index].height = Double(rect.size.height)
            notes[index].modifiedAt = Date()
            changed = true
        }
        if changed { save() }
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func getDataDirectory() -> String {
        return dataDirectory
    }

    func changeDataDirectory(_ newPath: String) {
        dataDirectory = newPath
        load()
    }

    func reload() {
        load()
    }

    /// Starts this folder with no notes, creating it if needed. An unreadable
    /// notes.json is moved aside first rather than overwritten.
    func startEmpty() {
        if case .unreadable = status {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let name = "notes.unreadable-\(formatter.string(from: Date())).json"
            let aside = (dataDirectory as NSString).appendingPathComponent(name)
            try? FileManager.default.moveItem(atPath: filePath, toPath: aside)
        }
        notes = []
        status = .ok
    }

    /// Local copy of the last good save. It lives outside the data folder so it
    /// survives that folder being moved, renamed or emptied by a sync client.
    static var backupFilePath: String {
        return (ConfigService.defaultDataDirectory as NSString).appendingPathComponent("backup/notes.json")
    }

    func backupNotes() -> [PostItNote]? {
        return try? NoteService.decodeNotes(atPath: NoteService.backupFilePath)
    }

    func restoreFromBackup() {
        guard let backup = backupNotes() else { return }
        startEmpty()
        notes = backup
        save()
    }

    private func load() {
        notes = []
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dataDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            status = .directoryMissing
            return
        }
        guard FileManager.default.fileExists(atPath: filePath) else {
            status = .fileMissing
            return
        }
        do {
            notes = try NoteService.decodeNotes(atPath: filePath)
            status = .ok
        } catch {
            NSLog("[PostItNotes] Failed to load notes: %@", "\(error)")
            status = .unreadable(error.localizedDescription)
        }
    }

    private static func decodeNotes(atPath path: String) throws -> [PostItNote] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PostItNote].self, from: data)
    }

    private func save() {
        guard status == .ok else {
            NSLog("[PostItNotes] Not saving: notes on disk were not loaded")
            return
        }
        let dir = dataDirectory
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)

            let backupPath = NoteService.backupFilePath
            try? FileManager.default.createDirectory(
                atPath: (backupPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: backupPath), options: .atomic)
        } catch {
            print("Failed to save notes: \(error)")
        }
    }
}
