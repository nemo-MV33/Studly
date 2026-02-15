import SwiftUI
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import QuickLook
import Combine

private enum UIFormatters {
    static let weekRange: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    static let shortWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d"
        return formatter
    }()

    static let fullDayHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - Models

enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case homework
    case reminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homework: return "ДЗ"
        case .reminder: return "Напоминание"
        }
    }
}

struct SubjectColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    static let defaultBlue = SubjectColor(red: 0.25, green: 0.56, blue: 0.95, opacity: 1)
}

struct Subject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: SubjectColor
}

struct Task: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var kind: TaskKind = .homework
    var dueDate: Date
    var subjectID: UUID? = nil
    var isDone: Bool = false
    var isPinned: Bool = false
    var attachments: [TaskAttachment] = []

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case dueDate
        case subjectID
        case isDone
        case isPinned
        case attachments
    }

    init(id: UUID = UUID(),
         title: String,
         kind: TaskKind = .homework,
         dueDate: Date,
         subjectID: UUID? = nil,
         isDone: Bool = false,
         isPinned: Bool = false,
         attachments: [TaskAttachment] = []) {
        self.id = id
        self.title = title
        self.kind = kind
        self.dueDate = dueDate
        self.subjectID = subjectID
        self.isDone = isDone
        self.isPinned = isPinned
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(TaskKind.self, forKey: .kind) ?? .homework
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        subjectID = try container.decodeIfPresent(UUID.self, forKey: .subjectID)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        attachments = try container.decodeIfPresent([TaskAttachment].self, forKey: .attachments) ?? []
    }
}

enum TaskAttachmentKind: String, Codable {
    case photo
    case audio
    case file
}

struct TaskAttachment: Identifiable, Codable, Equatable {
    var id = UUID()
    var originalName: String
    var storedFileName: String
    var kind: TaskAttachmentKind
}

enum AttachmentStorage {
    private static let folderName = "attachments"

    private static var folderURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func ensureFolderExists() throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    static func savePhotoData(_ data: Data, preferredFileName: String?) throws -> TaskAttachment {
        try ensureFolderExists()
        let providedName = preferredFileName ?? ""
        let providedExt = URL(fileURLWithPath: providedName).pathExtension
        let ext = providedExt.isEmpty ? "jpg" : providedExt
        let stored = "\(UUID().uuidString).\(ext)"
        let destination = folderURL.appendingPathComponent(stored)
        try data.write(to: destination, options: .atomic)

        let name = preferredFileName?.isEmpty == false ? preferredFileName! : "Фото.\(ext)"
        return TaskAttachment(originalName: name, storedFileName: stored, kind: .photo)
    }

    static func importFile(from sourceURL: URL) throws -> TaskAttachment {
        try ensureFolderExists()
        let ext = sourceURL.pathExtension
        let stored = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let destination = folderURL.appendingPathComponent(stored)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        let kind: TaskAttachmentKind
        if let type = UTType(filenameExtension: sourceURL.pathExtension.lowercased()),
           type.conforms(to: .audio) {
            kind = .audio
        } else {
            kind = .file
        }
        return TaskAttachment(originalName: sourceURL.lastPathComponent, storedFileName: stored, kind: kind)
    }

    static func delete(_ attachment: TaskAttachment) {
        let url = folderURL.appendingPathComponent(attachment.storedFileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func fileURL(for attachment: TaskAttachment) -> URL {
        folderURL.appendingPathComponent(attachment.storedFileName)
    }
}

// MARK: - Notification manager

final class NotificationManager {
    static let shared = NotificationManager()

    private init() {
        requestAuthorization()
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleNotification(for task: Task) {
        let content = UNMutableNotificationContent()
        content.title = task.kind == .homework ? "Напоминание о ДЗ" : "Напоминание"
        content.body = task.title
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                          from: task.dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(identifier: task.id.uuidString,
                                            content: content,
                                            trigger: trigger)

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func removeNotification(for taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskID.uuidString])
    }
}

// MARK: - Onboarding

struct HelloView: View {
    @AppStorage("hasSeenHello") var hasSeenHello: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255)
                    .ignoresSafeArea()

                VStack {
                    CircleImageView().offset(y: 110)

                    VStack(alignment: .center, spacing: 8) {
                        Text("Добро пожаловать!")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)
                            .offset(y: 105)

                        Text("Studly — планер для школьников и студентов")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .offset(y: 95)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    Button {
                        hasSeenHello = true
                    } label: {
                        Text("Начать")
                            .font(.title3.bold())
                            .padding(.horizontal, 70)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.18, green: 0.29, blue: 0.24))
                            )
                            .foregroundColor(.white)
                    }
                    .offset(y: -30)
                }
            }
        }
    }
}

// MARK: - Root screen with system Tab Bar

struct MainView: View {
    enum Section: String, CaseIterable, Identifiable {
        case planner
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .planner: return "Планер"
            case .settings: return "Настройки"
            }
        }

        var icon: String {
            switch self {
            case .planner: return "calendar"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var tasks: [Task] = []
    @State private var subjects: [Subject] = []
    @State private var selectedSection: Section = .planner

    @State private var showCreateTaskSheet = false
    @State private var showSubjectSetup = false
    @State private var createTaskInitialDate = Date()

    var body: some View {
        TabView(selection: $selectedSection) {
            PlannerView(
                tasks: $tasks,
                subjects: subjects,
                onCreateTask: { selectedDate in
                    createTaskInitialDate = dateWithCurrentTime(for: selectedDate)
                    showCreateTaskSheet = true
                }
            )
            .tabItem {
                Label("Планер", systemImage: "calendar")
            }
            .tag(Section.planner)

            SettingsView(subjects: $subjects)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(Section.settings)
        }
        .tint(.blue)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onAppear {
            let loaded = TaskStorage.load()
            tasks = loaded.tasks
            subjects = loaded.subjects
            showSubjectSetup = subjects.isEmpty
        }
        .onChange(of: tasks) { _ in
            TaskStorage.save(tasks: tasks, subjects: subjects)
        }
        .onChange(of: subjects) { _ in
            TaskStorage.save(tasks: tasks, subjects: subjects)
            if !subjects.isEmpty {
                showSubjectSetup = false
            }
        }
        .sheet(isPresented: $showCreateTaskSheet) {
            CreateTaskView(tasks: $tasks, subjects: subjects, initialDate: createTaskInitialDate)
        }
        .sheet(isPresented: $showSubjectSetup) {
            SubjectSetupView(subjects: $subjects)
                .interactiveDismissDisabled(subjects.isEmpty)
        }
    }

    private func dateWithCurrentTime(for day: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }
}

// MARK: - Planner

struct PlannerView: View {
    @Binding var tasks: [Task]
    let subjects: [Subject]
    let onCreateTask: (Date) -> Void

    @State private var weekStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDayIndex: Int = 0
    @State private var showDateJumpSheet = false
    @State private var jumpDate = Date()
    @State private var editingTask: Task?
    @State private var selectedTaskForDetails: Task?
    @State private var searchText = ""

    private static let appCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }()

    private let calendar = PlannerView.appCalendar

    private var weekDates: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStartDate)
        }
    }

    private var weekTitle: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        return "\(UIFormatters.weekRange.string(from: first)) - \(UIFormatters.weekRange.string(from: last))"
    }

    private var selectedDate: Date {
        guard weekDates.indices.contains(selectedDayIndex) else { return weekStartDate }
        return weekDates[selectedDayIndex]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("Учебный планер")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        onCreateTask(selectedDate)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .glassEffect()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                searchBar

                if normalizedSearchText.isEmpty {
                    DayTasksList(
                        date: selectedDate,
                        tasks: tasksFor(selectedDate),
                        subjects: subjects,
                        onToggleDone: { task in toggleTask(task) },
                        onDelete: { task in deleteTask(task) },
                        onToggleImportant: { task in toggleImportant(task) },
                        onEdit: { task in editingTask = task },
                        onOpen: { task in selectedTaskForDetails = task }
                    )
                } else {
                    SearchResultsList(
                        query: normalizedSearchText,
                        tasks: searchResults,
                        subjects: subjects,
                        onToggleDone: { task in toggleTask(task) },
                        onDelete: { task in deleteTask(task) },
                        onToggleImportant: { task in toggleImportant(task) },
                        onEdit: { task in editingTask = task },
                        onOpen: { task in selectedTaskForDetails = task }
                    )
                }

                VStack(spacing: 10) {
                    HStack {
                        Button {
                            shiftWeek(by: -7)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .glassEffect()
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            jumpDate = selectedDate
                            showDateJumpSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(weekTitle)
                                Image(systemName: "calendar")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect()
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 8)

                        Button {
                            goToToday()
                        } label: {
                            Image(systemName: "1.calendar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .glassEffect()
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 8)

                        Button {
                            shiftWeek(by: 7)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .glassEffect()
                        }
                        .buttonStyle(.plain)
                    }

                    dayPicker
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            .background(Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255))
        }
        .onAppear {
            weekStartDate = startOfWeek(for: Date())
            selectedDayIndex = max(0, min(6, dayIndex(for: Date())))
        }
        .sheet(isPresented: $showDateJumpSheet) {
            DateJumpSheet(date: $jumpDate) {
                weekStartDate = startOfWeek(for: jumpDate)
                selectedDayIndex = max(0, min(6, dayIndex(for: jumpDate)))
            }
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(tasks: $tasks, subjects: subjects, task: task)
        }
        .sheet(item: $selectedTaskForDetails) { task in
            TaskDetailsView(task: task, subjects: subjects)
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 8) {
            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, day in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedDayIndex = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(shortWeekday(for: day))
                            .font(.caption)
                        Text(dayNumber(for: day))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(selectedDayIndex == index ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedDayIndex == index ? Color.white : Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.75))
            TextField("Поиск: название, дата, предмет", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var subjectNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0.name.lowercased()) })
    }

    private var searchResults: [Task] {
        tasks
            .filter { matchesSearch($0, query: normalizedSearchText) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private func matchesSearch(_ task: Task, query: String) -> Bool {
        guard !query.isEmpty else { return true }

        let title = task.title.lowercased()
        if title.contains(query) { return true }

        let dateString = TaskDetailsView.dateTimeFormatter.string(from: task.dueDate).lowercased()
        if dateString.contains(query) { return true }

        let dayString = UIFormatters.fullDayHeader.string(from: task.dueDate).lowercased()
        if dayString.contains(query) { return true }

        let timeString = UIFormatters.time.string(from: task.dueDate).lowercased()
        if timeString.contains(query) { return true }

        if let id = task.subjectID, let subjectName = subjectNameByID[id], subjectName.contains(query) {
            return true
        }

        return false
    }

    private func tasksFor(_ day: Date) -> [Task] {
        tasks
            .filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private func toggleTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
    }

    private func deleteTask(_ task: Task) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            task.attachments.forEach { AttachmentStorage.delete($0) }
            tasks.removeAll { $0.id == task.id }
            NotificationManager.shared.removeNotification(for: task.id)
        }
    }

    private func toggleImportant(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tasks[index].isPinned.toggle()
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        var start: Date = date
        var interval: TimeInterval = 0
        _ = calendar.dateInterval(of: .weekOfYear, start: &start, interval: &interval, for: date)
        return calendar.startOfDay(for: start)
    }

    private func dayIndex(for date: Date) -> Int {
        let start = startOfWeek(for: date)
        let startDay = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: start, to: startDay).day ?? 0
        return diff
    }

    private func shiftWeek(by days: Int) {
        if let date = calendar.date(byAdding: .day, value: days, to: weekStartDate) {
            weekStartDate = date
            selectedDayIndex = 0
        }
    }

    private func goToToday() {
        let today = Date()
        weekStartDate = startOfWeek(for: today)
        selectedDayIndex = max(0, min(6, dayIndex(for: today)))
    }

    private func shortWeekday(for date: Date) -> String {
        UIFormatters.shortWeekday.string(from: date).capitalized
    }

    private func dayNumber(for date: Date) -> String {
        UIFormatters.dayNumber.string(from: date)
    }
}

struct DateJumpSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var date: Date
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 16)

                Spacer()
            }
            .navigationTitle("Перейти к дате")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Перейти") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DayTasksList: View {
    let date: Date
    let tasks: [Task]
    let subjects: [Subject]
    let onToggleDone: (Task) -> Void
    let onDelete: (Task) -> Void
    let onToggleImportant: (Task) -> Void
    let onEdit: (Task) -> Void
    let onOpen: (Task) -> Void

    var body: some View {
        List {
            Section {
                if tasks.isEmpty {
                    Text("На этот день заданий нет")
                        .foregroundColor(.white.opacity(0.75))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(tasks) { task in
                        TaskCard(
                            task: task,
                            subject: subject(for: task),
                            onToggleDone: { onToggleDone(task) }
                        )
                        .onTapGesture {
                            onOpen(task)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                DispatchQueue.main.async {
                                    onDelete(task)
                                }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                DispatchQueue.main.async {
                                    onToggleImportant(task)
                                }
                            } label: {
                                Label(task.isPinned ? "Убрать важное" : "Важное",
                                      systemImage: task.isPinned ? "star.slash" : "star.fill")
                            }
                            .tint(.yellow)

                            Button {
                                onEdit(task)
                            } label: {
                                Label("Редактировать", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text(formattedDay(date))
                    .foregroundColor(.white)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func subject(for task: Task) -> Subject? {
        guard let id = task.subjectID else { return nil }
        return subjects.first(where: { $0.id == id })
    }

    private func formattedDay(_ date: Date) -> String {
        UIFormatters.fullDayHeader.string(from: date).capitalized
    }
}

struct SearchResultsList: View {
    let query: String
    let tasks: [Task]
    let subjects: [Subject]
    let onToggleDone: (Task) -> Void
    let onDelete: (Task) -> Void
    let onToggleImportant: (Task) -> Void
    let onEdit: (Task) -> Void
    let onOpen: (Task) -> Void

    var body: some View {
        List {
            Section {
                if tasks.isEmpty {
                    Text("Ничего не найдено")
                        .foregroundColor(.white.opacity(0.75))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(tasks) { task in
                        TaskCard(
                            task: task,
                            subject: subject(for: task),
                            onToggleDone: { onToggleDone(task) }
                        )
                        .onTapGesture {
                            onOpen(task)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                DispatchQueue.main.async {
                                    onDelete(task)
                                }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                DispatchQueue.main.async {
                                    onToggleImportant(task)
                                }
                            } label: {
                                Label(task.isPinned ? "Убрать важное" : "Важное",
                                      systemImage: task.isPinned ? "star.slash" : "star.fill")
                            }
                            .tint(.yellow)

                            Button {
                                onEdit(task)
                            } label: {
                                Label("Редактировать", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text("Результаты поиска: \(query)")
                    .foregroundColor(.white)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func subject(for task: Task) -> Subject? {
        guard let id = task.subjectID else { return nil }
        return subjects.first(where: { $0.id == id })
    }
}

struct TaskCard: View {
    let task: Task
    let subject: Subject?
    let onToggleDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggleDone) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(task.isDone ? .green : .white.opacity(0.75))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .foregroundColor(.white)
                        .strikethrough(task.isDone)
                        .opacity(task.isDone ? 0.55 : 1)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(task.kind.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.2)))

                        Text("Важное")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.yellow))
                            .opacity(task.isPinned ? 1 : 0)
                            .accessibilityHidden(!task.isPinned)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 8) {
                    Text(timeString(task.dueDate))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))

                    if !task.attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(task.attachments.count)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    if let subject {
                        Circle()
                            .fill(subject.color.swiftUIColor)
                            .frame(width: 9, height: 9)
                        Text(subject.name)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(minHeight: 86)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(task.isPinned ? Color.yellow.opacity(0.9) : Color.white.opacity(0.14),
                                lineWidth: task.isPinned ? 1.6 : 1)
                )
        )
    }

    private func timeString(_ date: Date) -> String {
        UIFormatters.time.string(from: date)
    }
}

// MARK: - Settings and subjects

struct SettingsView: View {
    @Binding var subjects: [Subject]

    @State private var newSubjectName = ""
    @State private var selectedColor: Color = .blue

    var body: some View {
        NavigationStack {
            Form {
                Section("Добавить дисциплину") {
                    TextField("Например: Математика", text: $newSubjectName)
                    ColorPicker("Цвет индикатора", selection: $selectedColor)

                    Button("Добавить") {
                        addSubject()
                    }
                    .disabled(newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Мои дисциплины") {
                    if subjects.isEmpty {
                        Text("Пока нет дисциплин")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(subjects) { subject in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(subject.color.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                Text(subject.name)
                            }
                        }
                        .onDelete(perform: deleteSubject)
                    }
                }
            }
            .navigationTitle("Настройки")
        }
    }

    private func addSubject() {
        let trimmed = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let rgba = selectedColor.rgba
        let subject = Subject(
            name: trimmed,
            color: SubjectColor(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.opacity)
        )
        subjects.append(subject)

        newSubjectName = ""
        selectedColor = .blue
    }

    private func deleteSubject(at offsets: IndexSet) {
        subjects.remove(atOffsets: offsets)
    }
}

struct SubjectSetupView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var subjects: [Subject]

    @State private var newSubjectName = ""
    @State private var selectedColor: Color = .blue

    var body: some View {
        NavigationStack {
            Form {
                Section("Добавьте дисциплины") {
                    Text("Выберите предмет и цвет индикатора. Это нужно, чтобы задания на планере было легко различать.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Название предмета", text: $newSubjectName)
                    ColorPicker("Цвет", selection: $selectedColor)

                    Button("Добавить предмет") {
                        addSubject()
                    }
                    .disabled(newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Текущий список") {
                    if subjects.isEmpty {
                        Text("Добавьте минимум один предмет")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(subjects) { subject in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(subject.color.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                Text(subject.name)
                            }
                        }
                        .onDelete(perform: deleteSubject)
                    }
                }
            }
            .navigationTitle("Первичная настройка")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .disabled(subjects.isEmpty)
                }
            }
        }
    }

    private func addSubject() {
        let trimmed = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let rgba = selectedColor.rgba
        let subject = Subject(
            name: trimmed,
            color: SubjectColor(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.opacity)
        )
        subjects.append(subject)

        newSubjectName = ""
        selectedColor = .blue
    }

    private func deleteSubject(at offsets: IndexSet) {
        subjects.remove(atOffsets: offsets)
    }
}

// MARK: - Create task

struct CreateTaskView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tasks: [Task]
    let subjects: [Subject]

    @State private var title = ""
    @State private var selectedKind: TaskKind = .homework
    @State private var selectedSubjectID: UUID? = nil
    @State private var dueDate: Date
    @State private var addNotification = true
    @State private var attachments: [TaskAttachment] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    init(tasks: Binding<[Task]>, subjects: [Subject], initialDate: Date) {
        _tasks = tasks
        self.subjects = subjects
        _dueDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Введите задание", text: $title)
                }

                Section("Тип") {
                    Picker("Тип", selection: $selectedKind) {
                        ForEach(TaskKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Дисциплина") {
                    Picker("Предмет", selection: $selectedSubjectID) {
                        Text("Без предмета").tag(Optional<UUID>.none)
                        ForEach(subjects) { subject in
                            Text(subject.name).tag(Optional.some(subject.id))
                        }
                    }
                }

                Section("Дата и время") {
                    DatePicker("Когда", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    Toggle("Локальное уведомление", isOn: $addNotification)
                }

                Section("Вложения") {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label("Добавить фото", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Добавить файл", systemImage: "doc")
                    }

                    if attachments.isEmpty {
                        Text("Нет вложений")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(attachments) { attachment in
                            AttachmentRow(attachment: attachment)
                        }
                        .onDelete(perform: removeAttachments)
                    }
                }
            }
            .navigationTitle("Новое задание")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        saveTask()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedPhotoItems) { items in
                handleSelectedPhotos(items)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.item],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
        }
    }

    private func saveTask() {
        let newTask = Task(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: selectedKind,
            dueDate: dueDate,
            subjectID: selectedSubjectID,
            attachments: attachments
        )

        tasks.append(newTask)

        if addNotification {
            NotificationManager.shared.scheduleNotification(for: newTask)
        }

        dismiss()
    }

    private func handleSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        _Concurrency.Task {
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let attachment = try AttachmentStorage.savePhotoData(data, preferredFileName: item.itemIdentifier)
                    await MainActor.run { attachments.append(attachment) }
                } catch {
                    continue
                }
            }
            await MainActor.run { selectedPhotoItems = [] }
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let attachment = try AttachmentStorage.importFile(from: url)
                attachments.append(attachment)
            } catch {
                continue
            }
        }
    }

    private func removeAttachments(at offsets: IndexSet) {
        for index in offsets {
            let attachment = attachments[index]
            AttachmentStorage.delete(attachment)
        }
        attachments.remove(atOffsets: offsets)
    }
}

struct EditTaskView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tasks: [Task]
    let subjects: [Subject]
    let task: Task

    @State private var title: String
    @State private var selectedKind: TaskKind
    @State private var selectedSubjectID: UUID?
    @State private var dueDate: Date
    @State private var addNotification = true
    @State private var attachments: [TaskAttachment]
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    init(tasks: Binding<[Task]>, subjects: [Subject], task: Task) {
        _tasks = tasks
        self.subjects = subjects
        self.task = task
        _title = State(initialValue: task.title)
        _selectedKind = State(initialValue: task.kind)
        _selectedSubjectID = State(initialValue: task.subjectID)
        _dueDate = State(initialValue: task.dueDate)
        _attachments = State(initialValue: task.attachments)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Введите задание", text: $title)
                }

                Section("Тип") {
                    Picker("Тип", selection: $selectedKind) {
                        ForEach(TaskKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Дисциплина") {
                    Picker("Предмет", selection: $selectedSubjectID) {
                        Text("Без предмета").tag(Optional<UUID>.none)
                        ForEach(subjects) { subject in
                            Text(subject.name).tag(Optional.some(subject.id))
                        }
                    }
                }

                Section("Дата и время") {
                    DatePicker("Когда", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    Toggle("Локальное уведомление", isOn: $addNotification)
                }

                Section("Вложения") {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label("Добавить фото", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Добавить файл", systemImage: "doc")
                    }

                    if attachments.isEmpty {
                        Text("Нет вложений")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(attachments) { attachment in
                            AttachmentRow(attachment: attachment)
                        }
                        .onDelete(perform: removeAttachments)
                    }
                }
            }
            .navigationTitle("Редактировать")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        saveChanges()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedPhotoItems) { items in
                handleSelectedPhotos(items)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.item],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
        }
    }

    private func saveChanges() {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            dismiss()
            return
        }

        tasks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks[index].kind = selectedKind
        tasks[index].dueDate = dueDate
        tasks[index].subjectID = selectedSubjectID
        let oldAttachments = tasks[index].attachments
        tasks[index].attachments = attachments

        let keptFileNames = Set(attachments.map(\.storedFileName))
        for attachment in oldAttachments where !keptFileNames.contains(attachment.storedFileName) {
            AttachmentStorage.delete(attachment)
        }

        NotificationManager.shared.removeNotification(for: task.id)
        if addNotification {
            NotificationManager.shared.scheduleNotification(for: tasks[index])
        }

        dismiss()
    }

    private func handleSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        _Concurrency.Task {
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let attachment = try AttachmentStorage.savePhotoData(data, preferredFileName: item.itemIdentifier)
                    await MainActor.run { attachments.append(attachment) }
                } catch {
                    continue
                }
            }
            await MainActor.run { selectedPhotoItems = [] }
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let attachment = try AttachmentStorage.importFile(from: url)
                attachments.append(attachment)
            } catch {
                continue
            }
        }
    }

    private func removeAttachments(at offsets: IndexSet) {
        for index in offsets {
            let attachment = attachments[index]
            AttachmentStorage.delete(attachment)
        }
        attachments.remove(atOffsets: offsets)
    }
}

struct AttachmentRow: View {
    let attachment: TaskAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(.secondary)
            Text(attachment.originalName)
                .lineLimit(1)
        }
    }

    private var iconName: String {
        switch attachment.kind {
        case .photo:
            return "photo"
        case .audio:
            return "waveform"
        case .file:
            return "doc"
        }
    }
}

struct TaskDetailsView: View {
    @Environment(\.dismiss) var dismiss
    let task: Task
    let subjects: [Subject]
    @State private var selectedPhotoIndex: Int?
    @State private var selectedFileForPreview: TaskAttachment?

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("Краткая информация") {
                    Text(task.title)
                        .font(.headline)
                    HStack {
                        Text(task.kind.title)
                        Spacer()
                        Text(Self.dateTimeFormatter.string(from: task.dueDate))
                            .foregroundColor(.secondary)
                    }

                    if let subject = subjectForTask {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(subject.color.swiftUIColor)
                                .frame(width: 10, height: 10)
                            Text(subject.name)
                        }
                    }

                    HStack {
                        Text("Статус")
                        Spacer()
                        Text(task.isDone ? "Выполнено" : "В процессе")
                            .foregroundColor(task.isDone ? .green : .secondary)
                    }
                }

                Section("Вложения") {
                    if photoAttachments.isEmpty && audioAttachments.isEmpty && documentAttachments.isEmpty {
                        Text("Нет вложений")
                            .foregroundColor(.secondary)
                    } else {
                        if !photoAttachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(Array(photoAttachments.enumerated()), id: \.element.id) { index, attachment in
                                        TaskAttachmentImagePreview(attachment: attachment)
                                            .frame(width: 120, height: 120)
                                            .onTapGesture {
                                                selectedPhotoIndex = index
                                            }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if !audioAttachments.isEmpty {
                            ForEach(audioAttachments) { attachment in
                                AudioAttachmentPlayerRow(attachment: attachment)
                            }
                        }

                        if !documentAttachments.isEmpty {
                            ForEach(documentAttachments) { attachment in
                                Button {
                                    selectedFileForPreview = attachment
                                } label: {
                                    AttachmentRow(attachment: attachment)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Задача")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedPhotoIndex != nil },
                set: { if !$0 { selectedPhotoIndex = nil } }
            )) {
                if let index = selectedPhotoIndex {
                    AttachmentPhotoPagerView(
                        attachments: photoAttachments,
                        initialIndex: index
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                }
            }
            .sheet(item: $selectedFileForPreview) { attachment in
                AttachmentQuickLookPreview(
                    url: AttachmentStorage.fileURL(for: attachment),
                    title: attachment.originalName
                )
                .ignoresSafeArea()
            }
        }
    }

    private var subjectForTask: Subject? {
        guard let id = task.subjectID else { return nil }
        return subjects.first(where: { $0.id == id })
    }

    private var photoAttachments: [TaskAttachment] {
        task.attachments.filter { $0.kind == .photo }
    }

    private var audioAttachments: [TaskAttachment] {
        task.attachments.filter { $0.kind == .audio }
    }

    private var documentAttachments: [TaskAttachment] {
        task.attachments.filter { $0.kind == .file }
    }
}

struct TaskAttachmentImagePreview: View {
    let attachment: TaskAttachment

    var body: some View {
        if let image = UIImage(contentsOfFile: AttachmentStorage.fileURL(for: attachment).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Text("Не удалось загрузить изображение")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct AudioAttachmentPlayerRow: View {
    let attachment: TaskAttachment
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isSeeking = false
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text(attachment.originalName)
                    .lineLimit(1)
                Spacer()
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                }
            }

            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { newValue in
                        currentTime = newValue
                    }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        player?.currentTime = currentTime
                    }
                }
            )

            HStack {
                Text(timeString(currentTime))
                Spacer()
                Text(timeString(duration))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .onAppear {
            preparePlayerIfNeeded()
        }
        .onReceive(timer) { _ in
            guard !isSeeking else { return }
            guard let player else { return }
            currentTime = player.currentTime
            if !player.isPlaying && isPlaying {
                isPlaying = false
            }
        }
        .onDisappear {
            player?.stop()
            isPlaying = false
        }
    }

    private func preparePlayerIfNeeded() {
        guard player == nil else { return }
        let url = AttachmentStorage.fileURL(for: attachment)
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = newPlayer.currentTime
        } catch {
            player = nil
            duration = 0
            currentTime = 0
        }
    }

    private func togglePlayback() {
        preparePlayerIfNeeded()
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "00:00" }
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AttachmentQuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, title: title)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let previewController = QLPreviewController()
        previewController.dataSource = context.coordinator
        previewController.navigationItem.title = title
        return UINavigationController(rootViewController: previewController)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        guard let previewController = uiViewController.viewControllers.first as? QLPreviewController else { return }
        context.coordinator.url = url
        context.coordinator.title = title
        previewController.navigationItem.title = title
        previewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        var title: String

        init(url: URL, title: String) {
            self.url = url
            self.title = title
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            PreviewItem(url: url, title: title)
        }
    }

    final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL, title: String) {
            previewItemURL = url
            previewItemTitle = title
        }
    }
}

struct AttachmentPhotoPagerView: View {
    let attachments: [TaskAttachment]
    let initialIndex: Int
    @State private var selectedIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    Group {
                        if let image = UIImage(contentsOfFile: AttachmentStorage.fileURL(for: attachment).path) {
                            ZoomableImageView(image: image)
                                .ignoresSafeArea()
                        } else {
                            Text("Не удалось открыть изображение")
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .onAppear {
            selectedIndex = max(0, min(initialIndex, attachments.count - 1))
        }
    }

    private var title: String {
        guard attachments.indices.contains(selectedIndex) else { return "Фото" }
        return attachments[selectedIndex].originalName
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.delaysContentTouches = false
        context.coordinator.scrollView = scrollView

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(doubleTap)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        uiView.setZoomScale(1.0, animated: false)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            let minScale = scrollView.minimumZoomScale
            let maxScale = min(scrollView.maximumZoomScale, 3.0)
            let targetScale: CGFloat = scrollView.zoomScale > minScale + 0.05 ? minScale : maxScale

            if targetScale == minScale {
                scrollView.setZoomScale(minScale, animated: true)
                return
            }

            let point = gesture.location(in: imageView)
            let width = scrollView.bounds.size.width / targetScale
            let height = scrollView.bounds.size.height / targetScale
            let zoomRect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }
}

// MARK: - Color helpers

private extension Color {
    var rgba: (red: Double, green: Double, blue: Double, opacity: Double) {
        #if os(iOS)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0.25, 0.56, 0.95, 1)
        #endif
    }
}

// MARK: - Previews

#Preview {
    HelloView()
}

#Preview {
    MainView()
}
