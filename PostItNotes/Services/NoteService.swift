import Foundation

class NoteService {
    private var notes: [PostItNote] = []
    private var dataDirectory: String

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

    private func load() {
        let path = filePath
        guard FileManager.default.fileExists(atPath: path) else {
            notes = []
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = try decoder.decode([PostItNote].self, from: data)
        } catch {
            print("Failed to load notes: \(error)")
            notes = []
        }
    }

    private func save() {
        let dir = dataDirectory
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: URL(fileURLWithPath: filePath))
        } catch {
            print("Failed to save notes: \(error)")
        }
    }
}
