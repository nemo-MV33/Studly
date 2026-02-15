import SwiftUI
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import QuickLook
import Combine
import Charts

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

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Не повторять"
        case .daily: return "Каждый день"
        case .weekly: return "Каждую неделю"
        case .monthly: return "Каждый месяц"
        case .yearly: return "Каждый год"
        }
    }

    var occurrenceLimit: Int {
        switch self {
        case .none: return 1
        case .daily: return 120
        case .weekly: return 104
        case .monthly: return 36
        case .yearly: return 8
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
    var createdAt: Date = Date()
    var subjectID: UUID? = nil
    var isDone: Bool = false
    var completedAt: Date? = nil
    var isPinned: Bool = false
    var recurrence: TaskRecurrence = .none
    var seriesID: UUID? = nil
    var attachments: [TaskAttachment] = []

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case dueDate
        case createdAt
        case subjectID
        case isDone
        case completedAt
        case isPinned
        case recurrence
        case seriesID
        case attachments
    }

    init(id: UUID = UUID(),
         title: String,
         kind: TaskKind = .homework,
         dueDate: Date,
         createdAt: Date = Date(),
         subjectID: UUID? = nil,
         isDone: Bool = false,
         completedAt: Date? = nil,
         isPinned: Bool = false,
         recurrence: TaskRecurrence = .none,
         seriesID: UUID? = nil,
         attachments: [TaskAttachment] = []) {
        self.id = id
        self.title = title
        self.kind = kind
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.subjectID = subjectID
        self.isDone = isDone
        self.completedAt = completedAt
        self.isPinned = isPinned
        self.recurrence = recurrence
        self.seriesID = seriesID
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(TaskKind.self, forKey: .kind) ?? .homework
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? dueDate
        subjectID = try container.decodeIfPresent(UUID.self, forKey: .subjectID)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        recurrence = try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? .none
        seriesID = try container.decodeIfPresent(UUID.self, forKey: .seriesID)
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
    private struct CreateTaskSheetPayload: Identifiable {
        let id = UUID()
        let initialDate: Date
    }

    enum Section: String, CaseIterable, Identifiable {
        case planner
        case stats
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .planner: return "Планер"
            case .stats: return "Статистика"
            case .settings: return "Настройки"
            }
        }

        var icon: String {
            switch self {
            case .planner: return "calendar"
            case .stats: return "chart.xyaxis.line"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var tasks: [Task] = []
    @State private var subjects: [Subject] = []
    @State private var selectedSection: Section = .planner

    @State private var createTaskSheetPayload: CreateTaskSheetPayload?
    @State private var showSubjectSetup = false
    @AppStorage("statsResetAt") private var statsResetAt: Double = 0

    var body: some View {
        TabView(selection: $selectedSection) {
            PlannerView(
                tasks: $tasks,
                subjects: subjects,
                onCreateTask: { selectedDate in
                    createTaskSheetPayload = CreateTaskSheetPayload(
                        initialDate: dateWithCurrentTime(for: selectedDate)
                    )
                }
            )
            .tabItem {
                Label("Планер", systemImage: "calendar")
            }
            .tag(Section.planner)

            StatisticsView(
                tasks: tasks,
                subjects: subjects,
                statsResetAt: statsResetAt,
                onRebuildStatistics: {
                    statsResetAt = 0
                },
                onResetStatistics: {
                    statsResetAt = Date().timeIntervalSince1970
                }
            )
                .tabItem {
                    Label("Статистика", systemImage: "chart.xyaxis.line")
                }
                .tag(Section.stats)

            SettingsView(
                subjects: $subjects,
                onDeleteAllTasks: {
                    let allAttachments = Set(tasks.flatMap { $0.attachments.map(\.storedFileName) })
                    for fileName in allAttachments {
                        AttachmentStorage.delete(
                            TaskAttachment(originalName: fileName, storedFileName: fileName, kind: .file)
                        )
                    }
                    for task in tasks {
                        NotificationManager.shared.removeNotification(for: task.id)
                    }
                    tasks.removeAll()
                }
            )
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
        .sheet(item: $createTaskSheetPayload) { payload in
            CreateTaskView(tasks: $tasks, subjects: subjects, initialDate: payload.initialDate)
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

// MARK: - Monthly planner

struct MonthlyPlannerView: View {
    @Binding var tasks: [Task]
    let subjects: [Subject]
    let onCreateTask: (Date) -> Void

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var editingTask: Task?
    @State private var selectedTaskForDetails: Task?
    @State private var pendingDeleteTask: Task?
    @State private var pendingDeleteDate: Date?

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("На месяц")
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

                HStack(spacing: 10) {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .glassEffect()
                    }
                    .buttonStyle(.plain)

                    Text(monthTitle(displayedMonth))
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect()
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .glassEffect()
                    }
                    .buttonStyle(.plain)

                    Spacer()

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
                }
                .padding(.horizontal, 16)

                monthGrid

                DayTasksList(
                    date: selectedDate,
                    tasks: tasksFor(selectedDate),
                    subjects: subjects,
                    onToggleDone: { task in toggleTask(task) },
                    onDelete: { task in requestDelete(task, occurrenceDate: selectedDate) },
                    onToggleImportant: { task in toggleImportant(task) },
                    onEdit: { task in editingTask = task },
                    onOpen: { task in selectedTaskForDetails = task }
                )
            }
            .background(Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255))
        }
        .onAppear {
            displayedMonth = startOfMonth(for: selectedDate)
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(tasks: $tasks, subjects: subjects, task: task)
        }
        .sheet(item: $selectedTaskForDetails) { task in
            TaskDetailsView(task: task, subjects: subjects)
        }
        .confirmationDialog(
            "Удаление повторяющейся задачи",
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { shown in
                    if !shown {
                        pendingDeleteTask = nil
                        pendingDeleteDate = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let task = pendingDeleteTask, task.recurrence != .none {
                Button("Удалить только это событие", role: .destructive) {
                    deleteSingleOccurrence(task: task, on: pendingDeleteDate)
                }
                Button("Удалить всю серию", role: .destructive) {
                    deleteEntireSeries(task: task)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выберите, что удалить")
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbolsMondayFirst(), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(monthCells(), id: \.self) { day in
                    let isCurrentMonthDay = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
                    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                    let indicators = indicatorsForDay(day)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = day
                            if !isCurrentMonthDay {
                                displayedMonth = startOfMonth(for: day)
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(UIFormatters.dayNumber.string(from: day))
                                .font(.subheadline.weight(isSelected ? .bold : .semibold))
                                .foregroundColor(textColor(isSelected: isSelected, isCurrentMonthDay: isCurrentMonthDay))

                            HStack(spacing: 3) {
                                ForEach(Array(indicators.enumerated()), id: \.offset) { _, color in
                                    Circle()
                                        .fill(color)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .gesture(monthSwipeGesture)
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 44 else { return }
                if horizontal < 0 {
                    shiftMonth(by: 1)
                } else {
                    shiftMonth(by: -1)
                }
            }
    }

    private func textColor(isSelected: Bool, isCurrentMonthDay: Bool) -> Color {
        if isSelected { return .white }
        return isCurrentMonthDay ? .white : .white.opacity(0.38)
    }

    private func weekdaySymbolsMondayFirst() -> [String] {
        ["П", "В", "С", "Ч", "П", "С", "В"]
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func monthCells() -> [Date] {
        let first = startOfMonth(for: displayedMonth)
        let startWeekday = calendar.component(.weekday, from: first)
        let offset = (startWeekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: first) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func indicatorsForDay(_ day: Date) -> [Color] {
        let dayTasks = tasksFor(day)
        var unique: [Color] = []
        var seenKeys = Set<String>()
        for task in dayTasks {
            let key: String
            let color: Color
            if let id = task.subjectID, let subject = subjects.first(where: { $0.id == id }) {
                color = subject.color.swiftUIColor
                key = id.uuidString
            } else {
                color = .white.opacity(0.85)
                key = "no-subject"
            }
            if unique.count >= 3 { break }
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                unique.append(color)
            }
        }
        return unique
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

    private func requestDelete(_ task: Task, occurrenceDate: Date?) {
        guard task.recurrence != .none, task.seriesID != nil else {
            deleteTask(task)
            return
        }

        pendingDeleteTask = task
        pendingDeleteDate = occurrenceDate
    }

    private func deleteTask(_ task: Task) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            deleteUnsharedAttachments(of: task)
            tasks.removeAll { $0.id == task.id }
            NotificationManager.shared.removeNotification(for: task.id)
        }
    }

    private func deleteSingleOccurrence(task: Task, on _: Date?) {
        deleteTask(task)
        pendingDeleteTask = nil
        pendingDeleteDate = nil
    }

    private func deleteEntireSeries(task: Task) {
        guard let seriesID = task.seriesID else {
            deleteTask(task)
            pendingDeleteTask = nil
            pendingDeleteDate = nil
            return
        }

        let seriesTasks = tasks.filter { $0.seriesID == seriesID }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for item in seriesTasks {
                deleteUnsharedAttachments(of: item, excludingSeriesID: seriesID)
                NotificationManager.shared.removeNotification(for: item.id)
            }
            tasks.removeAll { $0.seriesID == seriesID }
        }

        pendingDeleteTask = nil
        pendingDeleteDate = nil
    }

    private func deleteUnsharedAttachments(of task: Task, excludingSeriesID: UUID? = nil) {
        for attachment in task.attachments {
            let usedElsewhere = tasks.contains { candidate in
                guard candidate.id != task.id else { return false }
                if let seriesID = excludingSeriesID, candidate.seriesID == seriesID { return false }
                return candidate.attachments.contains(where: { $0.storedFileName == attachment.storedFileName })
            }
            if !usedElsewhere {
                AttachmentStorage.delete(attachment)
            }
        }
    }

    private func toggleImportant(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tasks[index].isPinned.toggle()
        }
        NotificationManager.shared.removeNotification(for: tasks[index].id)
        NotificationManager.shared.scheduleNotification(for: tasks[index])
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = startOfMonth(for: next)
            if !calendar.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) {
                selectedDate = displayedMonth
            }
        }
    }

    private func goToToday() {
        let today = Date()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = today
            displayedMonth = startOfMonth(for: today)
        }
    }
}

// MARK: - Planner

struct PlannerView: View {
    @Binding var tasks: [Task]
    let subjects: [Subject]
    let onCreateTask: (Date) -> Void

    enum DisplayMode: String, CaseIterable, Identifiable {
        case week
        case month
        case year

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .year: return "Год"
            }
        }
    }

    @State private var displayMode: DisplayMode = .week
    @State private var weekStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDayIndex: Int = 0
    @State private var selectedCalendarDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var displayedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showDateJumpSheet = false
    @State private var jumpDate = Date()
    @State private var editingTask: Task?
    @State private var selectedTaskForDetails: Task?
    @State private var showSearchSheet = false
    @State private var pendingDeleteTask: Task?
    @State private var pendingDeleteDate: Date?
    @State private var yearCalendarRefreshID = UUID()

    private static let appCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }()

    private let calendar = PlannerView.appCalendar
    private let controlButtonSize: CGFloat = 42

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

    private var activeDate: Date {
        switch displayMode {
        case .week: return selectedDate
        case .month, .year: return selectedCalendarDate
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("Учебный планер")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Spacer()

                    modeMenuButton
                    quickActionsCluster
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                switch displayMode {
                case .week:
                    DayTasksList(
                        date: selectedDate,
                        tasks: tasksFor(selectedDate),
                        subjects: subjects,
                        onToggleDone: { task in toggleTask(task) },
                        onDelete: { task in requestDelete(task, occurrenceDate: selectedDate) },
                        onToggleImportant: { task in toggleImportant(task) },
                        onEdit: { task in editingTask = task },
                        onOpen: { task in selectedTaskForDetails = task }
                    )

                    weekControls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                case .month:
                    monthControls
                    monthGrid
                    DayTasksList(
                        date: selectedCalendarDate,
                        tasks: tasksFor(selectedCalendarDate),
                        subjects: subjects,
                        onToggleDone: { task in toggleTask(task) },
                        onDelete: { task in requestDelete(task, occurrenceDate: selectedCalendarDate) },
                        onToggleImportant: { task in toggleImportant(task) },
                        onEdit: { task in editingTask = task },
                        onOpen: { task in selectedTaskForDetails = task }
                    )
                case .year:
                    yearControls
                    yearCalendar
                }
            }
            .background(Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255))
        }
        .onAppear {
            weekStartDate = startOfWeek(for: Date())
            selectedDayIndex = max(0, min(6, dayIndex(for: Date())))
            selectedCalendarDate = Date()
            displayedMonth = startOfMonth(for: Date())
            displayedYear = calendar.component(.year, from: Date())
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
        .sheet(isPresented: $showSearchSheet) {
            PlannerSearchSheet(
                tasks: $tasks,
                subjects: subjects,
                onDelete: { task in requestDelete(task, occurrenceDate: nil) }
            )
        }
        .confirmationDialog(
            "Удаление повторяющейся задачи",
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { shown in
                    if !shown {
                        pendingDeleteTask = nil
                        pendingDeleteDate = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let task = pendingDeleteTask, task.recurrence != .none {
                Button("Удалить только это событие", role: .destructive) {
                    deleteSingleOccurrence(task: task, on: pendingDeleteDate)
                }
                Button("Удалить всю серию", role: .destructive) {
                    deleteEntireSeries(task: task)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выберите, что удалить")
        }
    }

    private var modeMenuButton: some View {
        Menu {
            ForEach(DisplayMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        displayMode = mode
                        syncModeState(mode)
                    }
                } label: {
                    Label(mode.title, systemImage: displayMode == mode ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "ellipsis.calendar")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: controlButtonSize, height: controlButtonSize)
                .glassEffect()
        }
    }

    private var quickActionsCluster: some View {
        HStack(spacing: 0) {
            Button {
                showSearchSheet = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: controlButtonSize, height: controlButtonSize)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 22)

            Button {
                onCreateTask(activeDate)
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: controlButtonSize, height: controlButtonSize)
            }
            .buttonStyle(.plain)
        }
        .glassEffect()
        .clipShape(Capsule())
    }

    private var weekControls: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    shiftWeek(by: -7)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: controlButtonSize, height: controlButtonSize)
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
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: controlButtonSize, height: controlButtonSize)
                        .glassEffect()
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    shiftWeek(by: 7)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: controlButtonSize, height: controlButtonSize)
                        .glassEffect()
                }
                .buttonStyle(.plain)
            }

            dayPicker
        }
    }

    private var monthControls: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: controlButtonSize, height: controlButtonSize)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: controlButtonSize, height: controlButtonSize)
                        .glassEffect()
                }
                .buttonStyle(.plain)

                Text(monthTitle(displayedMonth))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect()
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: controlButtonSize, height: controlButtonSize)
                        .glassEffect()
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                goToTodayFromYear()
            } label: {
                Image(systemName: "1.calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: controlButtonSize, height: controlButtonSize)
                    .glassEffect()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private var yearControls: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: controlButtonSize, height: controlButtonSize)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    displayedYear -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: controlButtonSize, height: controlButtonSize)
                        .glassEffect()
                }
                .buttonStyle(.plain)

                Text("Год \(displayedYear.formatted(.number.grouping(.never)))")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect()
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    displayedYear += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: controlButtonSize, height: controlButtonSize)
                        .glassEffect()
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                goToTodayFromYear()
            } label: {
                Image(systemName: "1.calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: controlButtonSize, height: controlButtonSize)
                    .glassEffect()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbolsMondayFirst(), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            let rows = monthRows(for: displayedMonth)
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        if let day {
                            monthDayButton(for: day, monthAnchor: displayedMonth)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.horizontal, 8)

                if rowIndex < rows.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .padding(.horizontal, 16)
        .gesture(monthSwipeGesture)
    }

    private var yearCalendar: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(monthsInDisplayedYear(), id: \.self) { monthDate in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(monthTitle(monthDate))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)

                        HStack(spacing: 0) {
                            ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { symbol in
                                Text(symbol)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                            ForEach(Array(monthCells(for: monthDate).enumerated()), id: \.offset) { _, day in
                                if let day {
                                    yearDayButton(for: day, monthAnchor: monthDate)
                                } else {
                                    Color.clear
                                        .frame(maxWidth: .infinity, minHeight: 24)
                                }
                            }
                        }
                        .padding(.horizontal, 12)

                        Rectangle()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .frame(maxHeight: 530)
        .id(yearCalendarRefreshID)
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

    private func tasksFor(_ day: Date) -> [Task] {
        tasks
            .filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private func toggleTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
        tasks[index].completedAt = tasks[index].isDone ? Date() : nil
    }

    private func requestDelete(_ task: Task, occurrenceDate: Date?) {
        guard task.recurrence != .none, task.seriesID != nil else {
            deleteTask(task)
            return
        }

        pendingDeleteTask = task
        pendingDeleteDate = occurrenceDate
    }

    private func deleteTask(_ task: Task) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            deleteUnsharedAttachments(of: task)
            tasks.removeAll { $0.id == task.id }
            NotificationManager.shared.removeNotification(for: task.id)
        }
    }

    private func deleteSingleOccurrence(task: Task, on _: Date?) {
        deleteTask(task)
        pendingDeleteTask = nil
        pendingDeleteDate = nil
    }

    private func deleteEntireSeries(task: Task) {
        guard let seriesID = task.seriesID else {
            deleteTask(task)
            pendingDeleteTask = nil
            pendingDeleteDate = nil
            return
        }

        let seriesTasks = tasks.filter { $0.seriesID == seriesID }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for item in seriesTasks {
                deleteUnsharedAttachments(of: item, excludingSeriesID: seriesID)
                NotificationManager.shared.removeNotification(for: item.id)
            }
            tasks.removeAll { $0.seriesID == seriesID }
        }

        pendingDeleteTask = nil
        pendingDeleteDate = nil
    }

    private func deleteUnsharedAttachments(of task: Task, excludingSeriesID: UUID? = nil) {
        for attachment in task.attachments {
            let usedElsewhere = tasks.contains { candidate in
                guard candidate.id != task.id else { return false }
                if let seriesID = excludingSeriesID, candidate.seriesID == seriesID { return false }
                return candidate.attachments.contains(where: { $0.storedFileName == attachment.storedFileName })
            }
            if !usedElsewhere {
                AttachmentStorage.delete(attachment)
            }
        }
    }

    private func toggleImportant(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tasks[index].isPinned.toggle()
        }
        NotificationManager.shared.removeNotification(for: tasks[index].id)
        NotificationManager.shared.scheduleNotification(for: tasks[index])
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
        selectedCalendarDate = today
        displayedMonth = startOfMonth(for: today)
        displayedYear = calendar.component(.year, from: today)
    }

    private func goToTodayFromYear() {
        withAnimation(.easeInOut(duration: 0.2)) {
            goToToday()
        }
        yearCalendarRefreshID = UUID()
    }

    private func shortWeekday(for date: Date) -> String {
        UIFormatters.shortWeekday.string(from: date).capitalized
    }

    private func dayNumber(for date: Date) -> String {
        UIFormatters.dayNumber.string(from: date)
    }

    private func syncModeState(_ mode: DisplayMode) {
        switch mode {
        case .week:
            weekStartDate = startOfWeek(for: selectedCalendarDate)
            selectedDayIndex = max(0, min(6, dayIndex(for: selectedCalendarDate)))
        case .month:
            displayedMonth = startOfMonth(for: selectedCalendarDate)
        case .year:
            displayedYear = calendar.component(.year, from: selectedCalendarDate)
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 24 else { return }
                if horizontal < 0 {
                    shiftMonth(by: 1)
                } else {
                    shiftMonth(by: -1)
                }
            }
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = startOfMonth(for: next)
            if !calendar.isDate(selectedCalendarDate, equalTo: displayedMonth, toGranularity: .month) {
                selectedCalendarDate = displayedMonth
            }
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func weekdaySymbolsMondayFirst() -> [String] {
        ["П", "В", "С", "Ч", "П", "С", "В"]
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func monthCells(for month: Date) -> [Date?] {
        let first = startOfMonth(for: month)
        let startWeekday = calendar.component(.weekday, from: first)
        let offset = (startWeekday - calendar.firstWeekday + 7) % 7
        let range = calendar.range(of: .day, in: .month, for: first) ?? (1..<31)
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            var components = calendar.dateComponents([.year, .month], from: first)
            components.day = day
            cells.append(calendar.date(from: components))
        }
        let tail = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array(repeating: nil, count: tail))
        return cells
    }

    private func monthRows(for month: Date) -> [[Date?]] {
        let cells = monthCells(for: month)
        return stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start ..< min(start + 7, cells.count)])
        }
    }

    private func monthDayButton(for day: Date, monthAnchor: Date) -> some View {
        let isCurrentMonthDay = calendar.isDate(day, equalTo: monthAnchor, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedCalendarDate)
        let indicators = indicatorsForDay(day)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCalendarDate = day
                if !isCurrentMonthDay {
                    displayedMonth = startOfMonth(for: day)
                }
            }
        } label: {
            VStack(spacing: 4) {
                Text(UIFormatters.dayNumber.string(from: day))
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                    .foregroundColor(isSelected ? .white : (isCurrentMonthDay ? .white : .white.opacity(0.38)))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.red : Color.clear)
                    )

                HStack(spacing: 3) {
                    ForEach(Array(indicators.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func yearDayButton(for day: Date, monthAnchor: Date) -> some View {
        let isCurrentMonthDay = calendar.isDate(day, equalTo: monthAnchor, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedCalendarDate)
        let indicators = indicatorsForDay(day)

        return Button {
            selectedCalendarDate = day
            displayedMonth = startOfMonth(for: day)
        } label: {
            VStack(spacing: 2) {
                Text(UIFormatters.dayNumber.string(from: day))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isSelected ? .white : (isCurrentMonthDay ? .white.opacity(0.95) : .white.opacity(0.25)))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.red : Color.clear)
                    )
                HStack(spacing: 2) {
                    ForEach(Array(indicators.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.plain)
    }

    private func monthsInDisplayedYear() -> [Date] {
        (1...12).compactMap { month in
            var components = DateComponents()
            components.year = displayedYear
            components.month = month
            components.day = 1
            return calendar.date(from: components)
        }
    }

    private func indicatorsForDay(_ day: Date) -> [Color] {
        let dayTasks = tasksFor(day)
        var unique: [Color] = []
        var seenKeys = Set<String>()
        for task in dayTasks {
            let key: String
            let color: Color
            if let id = task.subjectID, let subject = subjects.first(where: { $0.id == id }) {
                color = subject.color.swiftUIColor
                key = id.uuidString
            } else {
                color = .white.opacity(0.85)
                key = "no-subject"
            }
            if unique.count >= 3 { break }
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                unique.append(color)
            }
        }
        return unique
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
                            .tint(.orange)

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
                            .tint(.orange)

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

struct PlannerSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var tasks: [Task]
    let subjects: [Subject]
    let onDelete: (Task) -> Void

    @State private var query = ""
    @State private var editingTask: Task?
    @State private var selectedTask: Task?

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var subjectNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0.name.lowercased()) })
    }

    private var results: [Task] {
        guard !normalizedQuery.isEmpty else { return [] }
        return tasks
            .filter { matchesSearch($0, query: normalizedQuery) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.75))
                    TextField("Поиск: название, дата, предмет", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                    if !query.isEmpty {
                        Button {
                            query = ""
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

                SearchResultsList(
                    query: normalizedQuery,
                    tasks: results,
                    subjects: subjects,
                    onToggleDone: toggleTask,
                    onDelete: onDelete,
                    onToggleImportant: toggleImportant,
                    onEdit: { editingTask = $0 },
                    onOpen: { selectedTask = $0 }
                )
            }
            .background(Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255))
            .navigationTitle("Поиск")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(tasks: $tasks, subjects: subjects, task: task)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailsView(task: task, subjects: subjects)
        }
    }

    private func matchesSearch(_ task: Task, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if task.title.lowercased().contains(query) { return true }
        if TaskDetailsView.dateTimeFormatter.string(from: task.dueDate).lowercased().contains(query) { return true }
        if UIFormatters.fullDayHeader.string(from: task.dueDate).lowercased().contains(query) { return true }
        if UIFormatters.time.string(from: task.dueDate).lowercased().contains(query) { return true }
        if let id = task.subjectID, let subjectName = subjectNameByID[id], subjectName.contains(query) { return true }
        return false
    }

    private func toggleTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
        tasks[index].completedAt = tasks[index].isDone ? Date() : nil
    }

    private func toggleImportant(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tasks[index].isPinned.toggle()
        }
        NotificationManager.shared.removeNotification(for: tasks[index].id)
        NotificationManager.shared.scheduleNotification(for: tasks[index])
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
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange))
                            .opacity(task.isPinned ? 1 : 0)
                            .accessibilityHidden(!task.isPinned)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 8) {
                    Text(timeString(task.dueDate))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))

                    if task.recurrence != .none {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }

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
                        .stroke(task.isPinned ? Color.orange.opacity(0.9) : Color.white.opacity(0.14),
                                lineWidth: task.isPinned ? 1.6 : 1)
                )
        )
    }

    private func timeString(_ date: Date) -> String {
        UIFormatters.time.string(from: date)
    }
}

// MARK: - Statistics

struct StatisticsView: View {
    let tasks: [Task]
    let subjects: [Subject]
    let statsResetAt: Double
    let onRebuildStatistics: () -> Void
    let onResetStatistics: () -> Void
    @State private var mainChartMode: ChartMode = .month
    @State private var showResetAlert = false
    @State private var statisticsRefreshID = UUID()

    private enum ChartMode: String, CaseIterable, Identifiable {
        case month
        case week

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month: return "По месяцам"
            case .week: return "По неделям"
            }
        }
    }

    private struct MonthStat: Identifiable {
        let id = UUID()
        let label: String
        let score: Double
    }

    private struct TrendSegment: Identifiable {
        let id = UUID()
        let startLabel: String
        let endLabel: String
        let startScore: Double
        let endScore: Double
    }

    private struct SubjectStat: Identifiable {
        let id: UUID
        let title: String
        let tint: Color
        let missed: Int
        let completed: Int
        let percent: Int
        let total: Int
        let onTime: Int
        let monthStats: [MonthStat]
        let rankingScore: Double
    }

    private var resetDate: Date? {
        statsResetAt > 0 ? Date(timeIntervalSince1970: statsResetAt) : nil
    }

    private var scopedTasks: [Task] {
        guard let resetDate else { return tasks }
        return tasks.filter { $0.createdAt >= resetDate }
    }

    private func metricValues(for sourceTasks: [Task]) -> (missed: Int, completed: Int, onTime: Int, percent: Int) {
        let done = sourceTasks.filter(\.isDone)
        let onTime = done.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return Calendar.current.isDate(completedAt, inSameDayAs: task.createdAt)
        }.count
        let missed = sourceTasks.filter { !$0.isDone && $0.dueDate < Date() }.count
        let completed = done.count
        let percent: Int
        if sourceTasks.isEmpty {
            percent = 0
        } else {
            let base = (Double(completed) / Double(sourceTasks.count)) * 100
            let bonusShare = completed == 0 ? 0 : (Double(onTime) / Double(completed))
            let bonus = bonusShare * 12
            percent = Int(min(100, (base + bonus).rounded()))
        }
        return (missed, completed, onTime, percent)
    }

    private var overallMetrics: (missed: Int, completed: Int, onTime: Int, percent: Int) {
        metricValues(for: scopedTasks)
    }

    private var missedCount: Int { overallMetrics.missed }

    private var completedCount: Int { overallMetrics.completed }

    private var boostedCompletionPercent: Int { overallMetrics.percent }

    private func monthlyStats(for sourceTasks: [Task]) -> [MonthStat] {
        let calendar = Calendar.current
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let filtered = sourceTasks.filter { $0.dueDate >= currentMonthStart }
        let groupedFiltered = Dictionary(grouping: filtered) { task in
            calendar.date(from: calendar.dateComponents([.year, .month], from: task.dueDate)) ?? task.dueDate
        }
        let sortedKeys = groupedFiltered.keys.sorted()
        return sortedKeys.suffix(6).map { key in
            let monthTasks = groupedFiltered[key] ?? []
            let metrics = metricValues(for: monthTasks)
            return MonthStat(label: monthFormatter.string(from: key).capitalized, score: Double(metrics.percent))
        }
    }

    private var summaryMessage: String {
        if scopedTasks.isEmpty { return "После сброса пока нет данных. Добавляй задачи и смотри динамику." }
        if boostedCompletionPercent >= 85 { return "Круто, молодец. Ты держишь очень сильный темп." }
        if boostedCompletionPercent >= 65 { return "Нормальный темп. Чуть меньше пропусков и будет отлично." }
        return "Пока много пропусков. Сконцентрируйся на 2-3 задачах в день."
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLL"
        return formatter
    }

    private var monthlyStats: [MonthStat] {
        monthlyStats(for: scopedTasks)
    }

    private func weekDayStats(for sourceTasks: [Task]) -> [MonthStat] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "ru_RU")
        weekdayFormatter.dateFormat = "EE"

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let dayTasks = sourceTasks.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
            let metrics = metricValues(for: dayTasks)
            let raw = weekdayFormatter.string(from: day).replacingOccurrences(of: ".", with: "")
            let label = raw.prefix(1).uppercased() + raw.dropFirst()
            return MonthStat(label: label, score: Double(metrics.percent))
        }
    }

    private var subjectStats: [SubjectStat] {
        let grouped = Dictionary(grouping: scopedTasks) { $0.subjectID }
        var items: [SubjectStat] = []

        for subject in subjects {
            let tasksForSubject = grouped[subject.id] ?? []
            guard !tasksForSubject.isEmpty else { continue }
            let metrics = metricValues(for: tasksForSubject)
            let completionRate = Double(metrics.completed) / Double(max(tasksForSubject.count, 1))
            let onTimeRate = Double(metrics.onTime) / Double(max(metrics.completed, 1))
            let ranking = (completionRate * 0.72) + (onTimeRate * 0.28)

            items.append(
                SubjectStat(
                    id: subject.id,
                    title: subject.name,
                    tint: subject.color.swiftUIColor,
                    missed: metrics.missed,
                    completed: metrics.completed,
                    percent: metrics.percent,
                    total: tasksForSubject.count,
                    onTime: metrics.onTime,
                    monthStats: monthlyStats(for: tasksForSubject),
                    rankingScore: ranking
                )
            )
        }

        return items.sorted {
            if $0.rankingScore == $1.rankingScore {
                return $0.completed > $1.completed
            }
            return $0.rankingScore > $1.rankingScore
        }
    }

    private func points(for mode: ChartMode) -> [MonthStat] {
        switch mode {
        case .month:
            return monthlyStats
        case .week:
            return weekDayStats(for: scopedTasks)
        }
    }

    private func trendSegments(for points: [MonthStat]) -> [TrendSegment] {
        guard points.count > 1 else { return [] }
        return (0..<(points.count - 1)).map { index in
            let start = points[index]
            let end = points[index + 1]
            return TrendSegment(
                startLabel: start.label,
                endLabel: end.label,
                startScore: start.score,
                endScore: end.score
            )
        }
    }

    private func trendColor(for segment: TrendSegment) -> Color {
        if segment.endScore > segment.startScore { return .green }
        if segment.endScore < segment.startScore { return .red }
        return .gray
    }

    private func trendChart(points: [MonthStat], height: CGFloat, lineWidth: CGFloat, symbolSize: CGFloat, xAxisLabel: String) -> some View {
        let segments = trendSegments(for: points)
        return Chart {
            ForEach(segments) { segment in
                LineMark(
                    x: .value("Период", segment.startLabel),
                    y: .value("Процент", segment.startScore),
                    series: .value("Сегмент", segment.id.uuidString)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(trendColor(for: segment))
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                LineMark(
                    x: .value("Период", segment.endLabel),
                    y: .value("Процент", segment.endScore),
                    series: .value("Сегмент", segment.id.uuidString)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(trendColor(for: segment))
                .lineStyle(StrokeStyle(lineWidth: lineWidth))
            }

            ForEach(points) { point in
                PointMark(
                    x: .value("Период", point.label),
                    y: .value("Процент", point.score)
                )
                .symbolSize(symbolSize)
                .foregroundStyle(.white)
            }
        }
        .frame(height: height)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel(xAxisLabel)
        .chartYAxisLabel("Процент, %")
    }

    private var subjectSummary: String {
        guard let best = subjectStats.first else { return "Добавь задачи с предметами, и здесь появится аналитика по каждому предмету." }
        guard let worst = subjectStats.last, subjectStats.count > 1 else {
            return "Самый стабильный предмет сейчас: \(best.title). Выполнено \(best.completed) из \(best.total), в срок \(best.onTime)."
        }
        return "Лучший предмет: \(best.title) (\(best.percent)%). Зона роста: \(worst.title) (\(worst.percent)%)."
    }

    var body: some View {
        let mainPoints = points(for: mainChartMode)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Статистика")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Spacer()

                        HStack(spacing: 0) {
                            Button {
                                onRebuildStatistics()
                                statisticsRefreshID = UUID()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 1, height: 22)

                            Button {
                                showResetAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                        }
                        .glassEffect()
                        .clipShape(Capsule())
                    }

                    Text(summaryMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.1))
                        )

                    trendChart(
                        points: mainPoints,
                        height: 230,
                        lineWidth: 2.5,
                        symbolSize: 48,
                        xAxisLabel: mainChartMode == .month ? "Последние месяцы" : "Текущая неделя"
                    )
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )

                    Picker("Период основного графика", selection: $mainChartMode) {
                        ForEach(ChartMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        StatBadge(title: "Пропущено", value: "\(missedCount)", tint: .orange)
                        StatBadge(title: "Выполнено", value: "\(completedCount)", tint: .green)
                        StatBadge(title: "Процент", value: "\(boostedCompletionPercent)%", tint: .blue)
                    }

                    Text(subjectSummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.1))
                        )

                    ForEach(subjectStats) { subject in
                        let subjectPoints = subject.monthStats

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(subject.tint)
                                    .frame(width: 10, height: 10)
                                Text(subject.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(.white)
                            }

                            trendChart(
                                points: subjectPoints,
                                height: 150,
                                lineWidth: 2.2,
                                symbolSize: 36,
                                xAxisLabel: "Месяцы"
                            )

                            HStack(spacing: 8) {
                                StatBadge(title: "Пропущено", value: "\(subject.missed)", tint: .orange)
                                StatBadge(title: "Выполнено", value: "\(subject.completed)", tint: .green)
                                StatBadge(title: "Процент", value: "\(subject.percent)%", tint: .blue)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(16)
                .id(statisticsRefreshID)
            }
            .background(Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255))
            .alert("Сбросить статистику?", isPresented: $showResetAlert) {
                Button("Сбросить", role: .destructive) {
                    onResetStatistics()
                    statisticsRefreshID = UUID()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это очистит данные статистики. Задачи останутся.")
            }
        }
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(value)
                .font(.headline.bold())
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Settings and subjects

struct SettingsView: View {
    @Binding var subjects: [Subject]
    let onDeleteAllTasks: () -> Void

    @State private var newSubjectName = ""
    @State private var selectedColor: Color = .blue
    @State private var showDeleteAllAlert = false

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

                Section("Напоминания") {
                    Button("Удалить все напоминания", role: .destructive) {
                        showDeleteAllAlert = true
                    }
                }
            }
            .navigationTitle("Настройки")
            .alert("Удалить все напоминания?", isPresented: $showDeleteAllAlert) {
                Button("Удалить", role: .destructive) {
                    onDeleteAllTasks()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это действие удалит все задачи и уведомления.")
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
        @State private var selectedRecurrence: TaskRecurrence = .none
    @State private var isImportant = false
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
                    Picker("Повтор", selection: $selectedRecurrence) {
                        ForEach(TaskRecurrence.allCases) { recurrence in
                            Text(recurrence.title).tag(recurrence)
                        }
                    }
                    Toggle("Важное", isOn: $isImportant)
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
        let prepared = buildTasksFromForm()
        tasks.append(contentsOf: prepared)

        prepared.forEach { NotificationManager.shared.scheduleNotification(for: $0) }

        dismiss()
    }

    private func buildTasksFromForm() -> [Task] {
        let baseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let seriesID: UUID? = selectedRecurrence == .none ? nil : UUID()

        var generated: [Task] = []
        var currentDate = dueDate
        for _ in 0..<selectedRecurrence.occurrenceLimit {
            generated.append(
                Task(
                    title: baseTitle,
                    kind: selectedKind,
                    dueDate: currentDate,
                    subjectID: selectedSubjectID,
                    isPinned: isImportant,
                    recurrence: selectedRecurrence,
                    seriesID: seriesID,
                    attachments: attachments
                )
            )

            guard let nextDate = nextOccurrence(from: currentDate, recurrence: selectedRecurrence) else {
                break
            }
            currentDate = nextDate
        }

        return generated
    }

    private func nextOccurrence(from date: Date, recurrence: TaskRecurrence) -> Date? {
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return Calendar.current.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return Calendar.current.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return Calendar.current.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return Calendar.current.date(byAdding: .year, value: 1, to: date)
        }
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
        @State private var selectedRecurrence: TaskRecurrence
    @State private var isImportant: Bool
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
        _selectedRecurrence = State(initialValue: task.recurrence)
        _isImportant = State(initialValue: task.isPinned)
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
                    Picker("Повтор", selection: $selectedRecurrence) {
                        ForEach(TaskRecurrence.allCases) { recurrence in
                            Text(recurrence.title).tag(recurrence)
                        }
                    }
                    Toggle("Важное", isOn: $isImportant)
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
        tasks[index].isPinned = isImportant
        tasks[index].recurrence = selectedRecurrence
        if selectedRecurrence == .none {
            tasks[index].seriesID = nil
        } else if tasks[index].seriesID == nil {
            tasks[index].seriesID = UUID()
        }
        let oldAttachments = tasks[index].attachments
        tasks[index].attachments = attachments

        let keptFileNames = Set(attachments.map(\.storedFileName))
        for attachment in oldAttachments where !keptFileNames.contains(attachment.storedFileName) {
            let usedElsewhere = tasks.contains { candidate in
                guard candidate.id != task.id else { return false }
                return candidate.attachments.contains(where: { $0.storedFileName == attachment.storedFileName })
            }
            if !usedElsewhere {
                AttachmentStorage.delete(attachment)
            }
        }

        NotificationManager.shared.removeNotification(for: task.id)
        NotificationManager.shared.scheduleNotification(for: tasks[index])

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

                    HStack {
                        Text("Повтор")
                        Spacer()
                        Text(task.recurrence.title)
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
