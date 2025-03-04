import ArgumentParser
import Foundation
import FrontmatterParsing
import Yams

#if canImport(Glibc)
    @preconcurrency import Glibc
#elseif canImport(Musl)
    @preconcurrency import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

struct UnrecognizedDate: Error {
    let string: String
}

extension UnrecognizedDate: LocalizedError {
    var errorDescription: String? {
        "unrecognized date \"\(self.string)\""
    }
}

let taskmatterShortTimeFormat = "h a"
let taskmatterTimeFormat = "h:mm a"
let taskmatterDateFormat = "MMMM d, yyyy"
let taskmatterDateTimeFormat = taskmatterDateFormat + ", " + taskmatterTimeFormat

let calendar = { () in
    var calendar = Calendar.current
    calendar.firstWeekday = 1
    return calendar
}()

extension Date {
    init(fromTaskmatterString from: String) throws(UnrecognizedDate) {
        let formatter = DateFormatter()
        formatter.dateFormat = taskmatterDateTimeFormat
        if let date = formatter.date(from: from) {
            self = date
        } else {
            formatter.dateFormat = taskmatterDateFormat
            if let date = formatter.date(from: from) {
                self = date
            } else {
                throw UnrecognizedDate(string: from)
            }
        }
    }
}

extension Date {
    var taskmatterString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = taskmatterDateFormat

        let components = calendar.dateComponents(in: TimeZone.gmt, from: self)
        if components.hour == 0 && components.minute == 0 {
            return formatter.string(from: self)
        } else if components.hour == 12 && components.minute == 0 {
            return formatter.string(from: self) + ", Noon"
        }

        formatter.dateFormat = taskmatterDateTimeFormat
        return formatter.string(from: self)
    }

    var taskmatterTimeString: String? {
        let formatter = DateFormatter()

        let components = calendar.dateComponents(in: TimeZone.gmt, from: self)
        if components.hour == 0 && components.minute == 0 {
            return nil
        } else if components.hour == 12 && components.minute == 0 {
            return "Noon"
        }

        if components.minute == 0 {
            formatter.dateFormat = taskmatterShortTimeFormat
            return formatter.string(from: self)
        }

        formatter.dateFormat = taskmatterTimeFormat
        return formatter.string(from: self)
    }
}

struct Properties {
    var due: Date? = nil
    var planned: Date? = nil
    var done: Bool? = nil

    var date: Date? { planned ?? due }

    enum CodingKeys: String, CodingKey {
        case due = "due"
        case planned = "planned"
        case done = "done"
    }
}

extension Properties: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let due = self.due {
            try container.encode(due.taskmatterString, forKey: .due)
        }
        if let planned = self.planned {
            try container.encode(planned.taskmatterString, forKey: .planned)
        }
        if let done = self.done {
            try container.encode(done, forKey: .done)
        }
    }
}

extension Properties: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.due = try container.decodeIfPresent(String.self, forKey: .due).map(
            Date.init(fromTaskmatterString:))
        self.planned = try container.decodeIfPresent(String.self, forKey: .planned).map(
            Date.init(fromTaskmatterString:))
        self.done = try container.decodeIfPresent(Bool.self, forKey: .done)
    }
}

enum FrontmatterCodingKeys {
    case properties
    case other(String)
}

extension FrontmatterCodingKeys: CodingKey {
    var stringValue: String {
        switch self {
        case .properties:
            "_tm"
        case .other(let s):
            s
        }
    }

    init?(stringValue: String) {
        if stringValue == "_tm" {
            self = .properties
        } else {
            self = .other(stringValue)
        }
    }

    var intValue: Int? { nil }

    init?(intValue: Int) { return nil }
}

struct FrontMatter {
    var properties: Properties = Properties()
    var other: [String: JSONValue] = [:]
}

extension FrontMatter: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: FrontmatterCodingKeys.self)
        try container.encode(properties, forKey: .properties)
        for (key, value) in other {
            try container.encode(value, forKey: .other(key))
        }
    }
}

extension FrontMatter: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: FrontmatterCodingKeys.self)
        self.properties =
            try container.decodeIfPresent(Properties.self, forKey: .properties) ?? Properties()
        for key in container.allKeys {
            switch key {
            case .properties:
                continue
            case .other(let key):
                self.other[key] = try container.decode(JSONValue.self, forKey: .other(key))
            }
        }
    }
}

struct CommonOptions: ParsableArguments {
    @Flag(name: [.customShort("R")], help: "Don't search for tasks recursively.")
    var nonRecursive: Bool = false
}

struct ListCommonOptions: ParsableArguments {
    @Flag(name: [.short], help: "Also show completed tasks.")
    var all: Bool = false

    @OptionGroup
    var common: CommonOptions

    @Argument
    var paths: [String] = ["."]
}

struct Task {
    let id: String
    let title: String
    let properties: Properties

    var date: Date? { properties.date }
}

extension Task: CustomStringConvertible {
    var description: String {
        if let timeString = self.date?.taskmatterTimeString {
            return "[\(self.id)] \(self.title) - \(timeString)"
        } else {
            return "[\(self.id)] \(self.title)"
        }
    }
}

func findTasks(listCommon: ListCommonOptions) throws -> [Task] {
    var urlToIDAndTitle = [URL: (String, String)]()

    let taskPathRegex = #/\| ([a-z]{3}).md$/#
    for path in listCommon.paths {
        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: [])
        while let url = enumerator?.nextObject() as? URL {
            if listCommon.common.nonRecursive {
                enumerator?.skipDescendants()
            }

            if url.lastPathComponent.starts(with: ".") {
                enumerator?.skipDescendants()
            }

            if let match = url.lastPathComponent.firstMatch(of: taskPathRegex) {
                let title = String(url.lastPathComponent.dropLast(8)).trimmingCharacters(
                    in: .whitespaces)
                urlToIDAndTitle[url] = (String(match.1), title)
            }
        }
    }

    var res = [Task]()
    let conversion = MarkdownWithFrontMatterConversion<FrontMatter>()
    for (url, (id, title)) in urlToIDAndTitle {
        let parsed = try conversion.apply(
            try String(contentsOfFile: url.path, encoding: .utf8))
        let properties = parsed.frontMatter?.properties ?? Properties()
        if listCommon.all || !(properties.done ?? false) {
            res.append(Task(id: id, title: title, properties: properties))
        }
    }
    return res
}

struct CalendarMathError: Error {}

extension CalendarMathError: LocalizedError {
    var errorDescription: String? {
        "failed to calculate date"
    }
}

struct Week: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show tasks planned this week.", aliases: ["w"])

    @Option(name: [.customShort("n")], help: "Offset this many weeks from today.")
    var offset: Int = 0

    @OptionGroup
    var listCommon: ListCommonOptions

    @Flag(name: [.customShort("T")], help: "Don't cut off empty days.")
    var noTrim: Bool = false

    mutating func run() throws {
        guard let offsetNow = calendar.date(byAdding: .weekOfYear, value: self.offset, to: Date())
        else {
            throw CalendarMathError()
        }
        guard let week = calendar.dateInterval(of: .weekOfYear, for: offsetNow) else {
            throw CalendarMathError()
        }

        var tasks = try findTasks(listCommon: self.listCommon).filter {
            $0.date.map(week.contains) ?? false
        }
        tasks.sort { $0.date! <= $1.date! }

        var days = [(String, [String])]()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        var day = week.start
        while day < week.end {
            var dayTasks = [String]()
            while let task = tasks.first {
                if calendar.dateComponents(in: TimeZone.gmt, from: task.date!).day
                    != calendar.dateComponents(in: TimeZone.gmt, from: day).day
                {
                    break
                }

                tasks.removeFirst()
                dayTasks.append(String(describing: task))
            }

            days.append((formatter.string(from: day), dayTasks))

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                throw CalendarMathError()
            }
            day = nextDay
        }
        if !self.noTrim {
            while let (_, tasks) = days.first {
                if !tasks.isEmpty {
                    break
                }

                days.removeFirst()
            }

            while let (_, tasks) = days.last {
                if !tasks.isEmpty {
                    break
                }

                days.removeLast()
            }

            if days.isEmpty {
                return
            }
        }

        let maxHeight = days.map { (_, tasks) in tasks.count }.max() ?? 0
        let maxWidths =
            days.map { (day, tasks) in
                max(day.count, tasks.map { $0.count }.max() ?? 0)
            }
        for dayIdx in 0..<days.count {
            days[dayIdx].0 = days[dayIdx].0.padding(
                toLength: maxWidths[dayIdx], withPad: " ", startingAt: 0)
            for taskIdx in 0..<days[dayIdx].1.count {
                days[dayIdx].1[taskIdx] = days[dayIdx].1[taskIdx]
                    .padding(toLength: maxWidths[dayIdx], withPad: " ", startingAt: 0)
            }
            while days[dayIdx].1.count < maxHeight {
                days[dayIdx].1.append(
                    String(repeating: " ", count: maxWidths[dayIdx]))
            }
        }

        let topBorder =
            "┌" + maxWidths.map { String(repeating: "─", count: $0) }.joined(separator: "┬") + "┐\n"
        try FileHandle.standardOutput.write(contentsOf: Data(topBorder.utf8))

        let titles = "│" + days.map { $0.0 }.joined(separator: "│") + "│\n"
        try FileHandle.standardOutput.write(contentsOf: Data(titles.utf8))

        let middleBorder =
            "├" + maxWidths.map { String(repeating: "─", count: $0) }.joined(separator: "┼") + "┤\n"
        try FileHandle.standardOutput.write(contentsOf: Data(middleBorder.utf8))

        for taskIdx in 0..<days[0].1.count {
            let tasks = "│" + days.map { $0.1[taskIdx] }.joined(separator: "│") + "│\n"
            try FileHandle.standardOutput.write(contentsOf: Data(tasks.utf8))
        }

        let bottomBorder =
            "└" + maxWidths.map { String(repeating: "─", count: $0) }.joined(separator: "┴") + "┘\n"
        try FileHandle.standardOutput.write(contentsOf: Data(bottomBorder.utf8))
    }
}

struct Month: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show tasks planned this month.", aliases: ["m"])

    @Option(name: [.customShort("n")], help: "Offset this many months from today.")
    var offset: Int = 0

    @OptionGroup
    var listCommon: ListCommonOptions

    @Flag(name: [.customShort("T")], help: "Don't cut off empty days/weeks.")
    var noTrim: Bool = false

    mutating func run() throws {
        guard let offsetNow = calendar.date(byAdding: .month, value: self.offset, to: Date())
        else {
            throw CalendarMathError()
        }
        guard let strictMonth = calendar.dateInterval(of: .month, for: offsetNow) else {
            throw CalendarMathError()
        }
        guard
            let monthStartWeekStart = calendar.dateInterval(
                of: .weekOfYear, for: strictMonth.start)?.start
        else {
            throw CalendarMathError()
        }
        guard
            let monthEndWeekEnd = calendar.dateInterval(of: .weekOfYear, for: strictMonth.end)?.end
        else {
            throw CalendarMathError()
        }
        let month = DateInterval(start: monthStartWeekStart, end: monthEndWeekEnd)

        var tasks = try findTasks(listCommon: self.listCommon).filter {
            $0.date.map(month.contains) ?? false
        }
        tasks.sort { $0.date! <= $1.date! }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        var day = month.start

        var days = [String]()
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else {
            throw CalendarMathError()
        }
        while day < week.end {
            days.append(formatter.string(from: day))

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                throw CalendarMathError()
            }
            day = nextDay
        }

        formatter.dateFormat = "d"
        day = month.start

        var weeks = [[(String, [String])]]()
        while day < month.end {
            guard let weekEnd = calendar.dateInterval(of: .weekOfYear, for: day)?.end else {
                throw CalendarMathError()
            }

            var week = [(String, [String])]()
            while day < weekEnd {
                var dayTasks = [String]()
                while let task = tasks.first {
                    if calendar.dateComponents(in: TimeZone.gmt, from: task.date!).day
                        != calendar.dateComponents(in: TimeZone.gmt, from: day).day
                    {
                        break
                    }

                    tasks.removeFirst()
                    dayTasks.append(String(describing: task))
                }

                week.append((formatter.string(from: day), dayTasks))

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                    throw CalendarMathError()
                }
                day = nextDay
            }

            weeks.append(week)
        }
        if !self.noTrim {
            while let days = weeks.first {
                if !days.allSatisfy({ $0.1.isEmpty }) {
                    break
                }

                weeks.removeFirst()
            }

            while let days = weeks.last {
                if !days.allSatisfy({ $0.1.isEmpty }) {
                    break
                }

                weeks.removeLast()
            }

            while !days.isEmpty {
                if !weeks.allSatisfy({ $0.first!.1.isEmpty }) {
                    break
                }

                days.removeFirst()
                for weekIdx in 0..<weeks.count {
                    weeks[weekIdx].removeFirst()
                }
            }

            while !days.isEmpty {
                if !weeks.allSatisfy({ $0.last!.1.isEmpty }) {
                    break
                }

                days.removeLast()
                for weekIdx in 0..<weeks.count {
                    weeks[weekIdx].removeLast()
                }
            }

            if days.isEmpty || weeks.isEmpty {
                return
            }
        }

        var maxWidths = [Int]()
        for dayIdx in 0..<days.count {
            let maxWidth =
                max(
                    days[dayIdx].count,
                    weeks.map { week in
                        max(week[dayIdx].0.count, week[dayIdx].1.map { $0.count }.max() ?? 0)
                    }.max() ?? 0)

            days[dayIdx] = days[dayIdx].padding(toLength: maxWidth, withPad: " ", startingAt: 0)

            maxWidths.append(maxWidth)
        }
        for weekIdx in 0..<weeks.count {
            let maxHeight = weeks[weekIdx].map { $0.1.count }.max() ?? 0
            for dayIdx in 0..<days.count {
                weeks[weekIdx][dayIdx].0 =
                    String(
                        repeating: " ", count: maxWidths[dayIdx] - weeks[weekIdx][dayIdx].0.count)
                    + "\u{1B}[1m" + weeks[weekIdx][dayIdx].0 + "\u{1B}[0m"
                for taskIdx in 0..<weeks[weekIdx][dayIdx].1.count {
                    weeks[weekIdx][dayIdx].1[taskIdx] = weeks[weekIdx][dayIdx].1[taskIdx].padding(
                        toLength: maxWidths[dayIdx], withPad: " ", startingAt: 0)
                }
                while weeks[weekIdx][dayIdx].1.count < maxHeight {
                    weeks[weekIdx][dayIdx].1.append(
                        String(repeating: " ", count: maxWidths[dayIdx])
                    )
                }
            }
        }

        let topBorder =
            "┌" + maxWidths.map { String(repeating: "─", count: $0) }.joined(separator: "─") + "┐\n"
        try FileHandle.standardOutput.write(contentsOf: Data(topBorder.utf8))

        formatter.dateFormat = "MMMM"
        let monthTitle =
            "│"
            + formatter.string(from: offsetNow).padding(
                toLength: maxWidths.reduce(maxWidths.count - 1, +), withPad: " ",
                startingAt: 0) + "│\n"
        try FileHandle.standardOutput.write(contentsOf: Data(monthTitle.utf8))

        let upperMiddleBorder =
            "├" + maxWidths.map { String(repeating: "─", count: $0) }.joined(separator: "┬") + "┤\n"
        try FileHandle.standardOutput.write(contentsOf: Data(upperMiddleBorder.utf8))

        let dayOfWeekTitles = "│" + days.joined(separator: "│") + "│\n"
        try FileHandle.standardOutput.write(contentsOf: Data(dayOfWeekTitles.utf8))

        let lowerMiddleBorder =
            "├" + maxWidths.map { String(repeating: "─", count: $0) }.joined(separator: "┼") + "┤\n"
        for week in weeks {
            try FileHandle.standardOutput.write(contentsOf: Data(lowerMiddleBorder.utf8))

            let dayTitles = "│" + week.map { $0.0 }.joined(separator: "│") + "│\n"
            try FileHandle.standardOutput.write(contentsOf: Data(dayTitles.utf8))

            for taskIdx in 0..<week[0].1.count {
                let tasks = "│" + week.map { $0.1[taskIdx] }.joined(separator: "│") + "│\n"
                try FileHandle.standardOutput.write(contentsOf: Data(tasks.utf8))
            }
        }

        let bottomBorder =
            "└" + maxWidths.map { String(repeating: "─", count: $0) }.joined(separator: "┴") + "┘\n"
        try FileHandle.standardOutput.write(contentsOf: Data(bottomBorder.utf8))
    }
}

struct Someday: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show tasks without planned or due dates.", aliases: ["s"])

    @OptionGroup
    var listCommon: ListCommonOptions

    mutating func run() throws {
        for task in try findTasks(listCommon: self.listCommon) {
            if task.properties.due == nil && task.properties.planned == nil {
                print(String(describing: task))
            }
        }
    }
}

enum PropError: Error {
    case noSeparator
    case unknownProp(String)
    case invalidBool(String)
}

extension PropError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noSeparator:
            "prop didn't contain separator"
        case .unknownProp(let name):
            "unknown prop \"\(name)\""
        case .invalidBool(let value):
            "invalid boolean value for done prop \"\(value)\""
        }
    }
}

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a new task in the current directory.", aliases: ["a"])

    @Argument(help: "The title of the new task.")
    var title: String

    @Argument(help: "Colon-separated key-value taskmatter property pairs.")
    var props: [String] = []

    mutating func run() throws {
        var frontMatter = FrontMatter()
        for prop in props {
            let propParts = prop.split(separator: ":", maxSplits: 1)
            guard propParts.count == 2 else {
                throw PropError.noSeparator
            }

            // TODO: Use a more permissve date parser
            let value = String(propParts[1]).trimmingCharacters(in: .whitespaces)
            switch propParts[0].lowercased() {
            case "due":
                frontMatter.properties.due = try Date(fromTaskmatterString: value)

            case "planned":
                frontMatter.properties.planned = try Date(fromTaskmatterString: value)

            case "done":
                guard let b = Bool(value) else {
                    throw PropError.invalidBool(value)
                }
                frontMatter.properties.done = b

            default:
                throw PropError.unknownProp(String(propParts[0]))
            }
        }

        let conversion = MarkdownWithFrontMatterConversion<FrontMatter>()
        let data = try conversion.unapply(
            MarkdownWithFrontMatter(frontMatter: frontMatter, body: "\n# \(title)\n"))

        let id = String((0..<3).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        try data.write(toFile: "\(title) | \(id).md", atomically: false, encoding: .utf8)
    }
}

enum FindTargetsError: Error {
    case duplicateID(String)
    case notIDOrPath(String)
    case idNotFound(String)
}

extension FindTargetsError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .duplicateID(let id):
            "ID \"\(id)\" was specified more than once"
        case .notIDOrPath(let s):
            "target \"\(s)\" does not look like an ID or a path"
        case .idNotFound(let id):
            "no file found for ID \"\(id)\""
        }
    }
}

func findTargets(targets: [String], common: CommonOptions) throws(FindTargetsError) -> [URL] {
    var idToIdx = [String: Int]()
    var res = [URL?](repeating: nil, count: targets.count)
    for (idx, target) in targets.enumerated() {
        if target.wholeMatch(of: #/[a-z]{3}/#) != nil {
            if idToIdx.keys.contains(target) {
                throw .duplicateID(target)
            }

            idToIdx[target] = idx
        } else if FileManager.default.fileExists(atPath: target) {
            res[idx] = URL(filePath: target)
        } else {
            throw .notIDOrPath(target)
        }
    }

    let enumerator = FileManager.default.enumerator(
        at: URL.currentDirectory(), includingPropertiesForKeys: [])
    let taskPathRegex = #/\| ([a-z]{3}).md$/#
    while let url = enumerator?.nextObject() as? URL {
        if common.nonRecursive {
            enumerator?.skipDescendants()
        }

        if url.lastPathComponent.starts(with: ".") {
            enumerator?.skipDescendants()
        }

        if let match = url.lastPathComponent.firstMatch(of: taskPathRegex) {
            if let idx = idToIdx.removeValue(forKey: String(match.1)) {
                res[idx] = url
            }
        }
    }

    for (id, _) in idToIdx {
        throw .idNotFound(id)
    }

    return res.map { $0! }
}

enum EditorError: Error {
    case editorUnset
    case strdupFailed
    case execvpFailed(Int32)
}

extension EditorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .editorUnset:
            "$EDITOR was unset"
        case .strdupFailed:
            "strdup failed, possible out of memory error"
        case .execvpFailed(let errno):
            if let error = strerror(errno) {
                "execvp failed with error: \(String(cString: error))"
            } else {
                "execvp failed with unknown errno \(errno)"
            }
        }
    }
}

struct Edit: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Edit the specified tasks.", aliases: ["e"])

    @Argument(help: "Task IDs or paths to edit.")
    var targets: [String] = []

    @OptionGroup
    var common: CommonOptions

    mutating func run() throws {
        let urls = try findTargets(targets: self.targets, common: self.common)
        guard let editor = ProcessInfo.processInfo.environment["EDITOR"] else {
            throw EditorError.editorUnset
        }
        guard let editorCString = strdup(editor) else {
            throw EditorError.strdupFailed
        }
        execvp(editorCString, [editorCString] + urls.map { strdup($0.path) } + [nil])
        throw EditorError.execvpFailed(errno)
    }
}

struct Rename: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Rename the specified task.", aliases: ["r"])

    @Argument(help: "Task ID or path to rename.")
    var target: String

    @Argument(help: "Updated title to assign.")
    var title: String

    @OptionGroup
    var common: CommonOptions

    mutating func run() throws {
        let urls = try findTargets(targets: [self.target], common: self.common)
        assert(urls.count == 1)

        let oldURL = urls[0]
        let id = oldURL.lastPathComponent.firstMatch(of: #/\| ([a-z]{3}).md$/#)!.1
        let url = oldURL.deletingLastPathComponent().appendingPathComponent(
            "\(self.title) | \(id).md")

        let conversion = MarkdownWithFrontMatterConversion<FrontMatter>()
        var parsed = try conversion.apply(
            try String(contentsOfFile: oldURL.path, encoding: .utf8))

        parsed.body?.replace(
            #/^# .*$/#.anchorsMatchLineEndings(true), with: "# \(self.title)", maxReplacements: 1)

        let data = try conversion.unapply(parsed)
        try data.write(toFile: url.path, atomically: false, encoding: .utf8)
        try FileManager.default.removeItem(at: oldURL)
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete the specified tasks.", aliases: ["x"])

    @Argument(help: "Task IDs or paths to delete.")
    var targets: [String] = []

    @OptionGroup
    var common: CommonOptions

    mutating func run() throws {
        let urls = try findTargets(targets: self.targets, common: self.common)
        try urls.forEach(FileManager.default.removeItem)
    }
}

struct Done: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mark the specified tasks as done.", aliases: ["d"])

    @Argument(help: "Task IDs or paths to mark as done.")
    var targets: [String] = []

    @OptionGroup
    var common: CommonOptions

    mutating func run() throws {
        let urls = try findTargets(targets: self.targets, common: self.common)

        let conversion = MarkdownWithFrontMatterConversion<FrontMatter>()
        for url in urls {
            var parsed = try conversion.apply(
                try String(contentsOfFile: url.path, encoding: .utf8))
            var frontMatter = parsed.frontMatter ?? FrontMatter()
            frontMatter.properties.done = true
            parsed.frontMatter = frontMatter
            let data = try conversion.unapply(parsed)
            try data.write(toFile: url.path, atomically: false, encoding: .utf8)
        }
    }
}

@main
struct Taskmatter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "taskmatter",
        abstract: "Process tasks in Markdown YAML frontmatter.",
        subcommands: [
            Week.self, Month.self, Someday.self, Add.self, Edit.self, Rename.self, Delete.self,
            Done.self,
        ],
        defaultSubcommand: Month.self)
}
