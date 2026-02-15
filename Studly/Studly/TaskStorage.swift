import Foundation

final class TaskStorage {

    private static let tasksURL =
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("tasks.json")

    private static let subjectsURL =
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("subjects.json")

    private static let saveQueue = DispatchQueue(label: "studly.taskstorage.save", qos: .utility)
    private static var pendingSaveWorkItem: DispatchWorkItem?
    private static let saveDebounceDelay: TimeInterval = 0.2

    // MARK: - Save
    static func save(tasks: [Task], subjects: [Subject]) {
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            do {
                let tasksData = try JSONEncoder().encode(tasks)
                let subjectsData = try JSONEncoder().encode(subjects)

                try tasksData.write(to: tasksURL, options: .atomic)
                try subjectsData.write(to: subjectsURL, options: .atomic)
            } catch {
                print("Save error:", error)
            }
        }

        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + saveDebounceDelay, execute: workItem)
    }

    // MARK: - Load
    static func load() -> (tasks: [Task], subjects: [Subject]) {
        do {
            let tasksData = try Data(contentsOf: tasksURL)
            let subjectsData = try Data(contentsOf: subjectsURL)

            let tasks = try JSONDecoder().decode([Task].self, from: tasksData)
            let subjects = try JSONDecoder().decode([Subject].self, from: subjectsData)

            return (tasks, subjects)
        } catch {
            return ([], [])
        }
    }
}
