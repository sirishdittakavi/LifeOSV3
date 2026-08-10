import Foundation

/// A small protocol shared by every event that can leave the iOS persistence layer.
/// The JSON contract, rather than this Swift protocol, is the cross-platform API.
protocol PortableTrackableMetric: Codable, Identifiable {
    var schemaVersion: Int { get }
    var profileID: UUID { get }
    var occurredAt: Date { get }
    var kind: PortableMetricKind { get }
    var fields: [String: PortableValue] { get }
}

enum PortableMetricKind: String, Codable, CaseIterable, Sendable {
    case actionSession = "action_session"
    case goalResult = "goal_result"
    case nutrition
    case weight
    case sport
}

/// JSON-native values keep extensions flexible without collapsing everything into strings.
/// Dates inside `fields` use ISO-8601 strings; the canonical event date is `occurredAt`.
indirect enum PortableValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case array([PortableValue])
    case object([String: PortableValue])
    case null

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum ValueType: String, Codable {
        case string, number, integer, boolean, array, object, null
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ValueType.self, forKey: .type) {
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
        case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .value))
        case .array: self = .array(try container.decode([PortableValue].self, forKey: .value))
        case .object:
            self = .object(try container.decode([String: PortableValue].self, forKey: .value))
        case .null: self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case .boolean(let value):
            try container.encode(ValueType.boolean, forKey: .type)
            try container.encode(value, forKey: .value)
        case .array(let value):
            try container.encode(ValueType.array, forKey: .type)
            try container.encode(value, forKey: .value)
        case .object(let value):
            try container.encode(ValueType.object, forKey: .type)
            try container.encode(value, forKey: .value)
        case .null:
            try container.encode(ValueType.null, forKey: .type)
        }
    }

    fileprivate var containsNonFiniteNumber: Bool {
        switch self {
        case .number(let value): return !value.isFinite
        case .array(let values): return values.contains(where: \.containsNonFiniteNumber)
        case .object(let values): return values.values.contains(where: \.containsNonFiniteNumber)
        default: return false
        }
    }
}

/// One dated fact for analytics, interoperability and a future Android client.
/// Deliberately excludes stored progress: each client derives progress from raw evidence.
struct PortableMetric: PortableTrackableMetric, Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let profileID: UUID
    let categoryID: UUID?
    let goalID: UUID?
    let definitionID: UUID?
    let occurredAt: Date
    let kind: PortableMetricKind
    let title: String
    let note: String
    let fields: [String: PortableValue]

    init(
        schemaVersion: Int = PortableMetric.currentSchemaVersion,
        id: UUID,
        profileID: UUID,
        categoryID: UUID? = nil,
        goalID: UUID? = nil,
        definitionID: UUID? = nil,
        occurredAt: Date,
        kind: PortableMetricKind,
        title: String,
        note: String = "",
        fields: [String: PortableValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.profileID = profileID
        self.categoryID = categoryID
        self.goalID = goalID
        self.definitionID = definitionID
        self.occurredAt = occurredAt
        self.kind = kind
        self.title = title
        self.note = note
        self.fields = fields
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableMetricError.unsupportedVersion(schemaVersion)
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PortableMetricError.emptyTitle(id)
        }
        guard fields.keys.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PortableMetricError.emptyFieldName(id)
        }
        guard !fields.values.contains(where: \.containsNonFiniteNumber) else {
            throw PortableMetricError.nonFiniteNumber(id)
        }
    }
}

struct PortableMetricEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let metrics: [PortableMetric]

    init(
        schemaVersion: Int = PortableMetricEnvelope.currentSchemaVersion,
        exportedAt: Date = .now,
        metrics: [PortableMetric]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.metrics = metrics
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableMetricError.unsupportedVersion(schemaVersion)
        }
        var identifiers = Set<UUID>()
        for metric in metrics {
            try metric.validate()
            guard identifiers.insert(metric.id).inserted else {
                throw PortableMetricError.duplicateIdentifier(metric.id)
            }
        }
    }
}

enum PortableMetricError: Error, Equatable {
    case unsupportedVersion(Int)
    case missingProfile(recordID: UUID, kind: PortableMetricKind)
    case emptyTitle(UUID)
    case emptyFieldName(UUID)
    case nonFiniteNumber(UUID)
    case duplicateIdentifier(UUID)
}

enum PortableMetricCodec {
    static func encode(_ envelope: PortableMetricEnvelope) throws -> Data {
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> PortableMetricEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(PortableMetricEnvelope.self, from: data)
        try envelope.validate()
        return envelope
    }
}

enum PortableMetricService {
    static func makeEnvelope(
        sessions: [ActivitySession],
        resultEntries: [ResultEntry],
        foodEntries: [FoodEntry],
        weightEntries: [WeightEntry],
        sportEntries: [SportEntry],
        exportedAt: Date = .now
    ) throws -> PortableMetricEnvelope {
        var metrics = try sessions.map(metric(from:))
        metrics += try resultEntries.map(metric(from:))
        metrics += try foodEntries.filter { !$0.isMealPlanItem }.map(metric(from:))
        metrics += try weightEntries.map(metric(from:))
        metrics += try sportEntries.map(metric(from:))
        metrics.sort {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let envelope = PortableMetricEnvelope(exportedAt: exportedAt, metrics: metrics)
        try envelope.validate()
        return envelope
    }

    static func metric(from session: ActivitySession) throws -> PortableMetric {
        let activity = session.activity
        guard let profileID = activity?.profile?.id ?? session.calendarItem?.profile?.id else {
            throw PortableMetricError.missingProfile(recordID: session.id, kind: .actionSession)
        }
        var fields: [String: PortableValue] = [
            "recorded_value": .number(session.recordedValue),
            "active_seconds": .integer(session.actualActiveSeconds)
        ]
        add(activity?.targetValue, key: "target_value", to: &fields)
        add(activity?.targetUnit, key: "unit", to: &fields)
        add(session.startedAt, key: "started_at", to: &fields)
        add(session.endedAt, key: "ended_at", to: &fields)
        return PortableMetric(
            id: session.id, profileID: profileID, categoryID: activity?.category?.id,
            definitionID: activity?.id, occurredAt: session.date, kind: .actionSession,
            title: activity?.name ?? "Activity session", note: session.note, fields: fields
        )
    }

    static func metric(from entry: ResultEntry) throws -> PortableMetric {
        guard let profileID = entry.profile?.id else {
            throw PortableMetricError.missingProfile(recordID: entry.id, kind: .goalResult)
        }
        let measure = entry.measure
        var fields: [String: PortableValue] = [
            "value_type": .string(measure?.valueTypeRaw ?? ResultValueType.text.rawValue),
            "source": .string(entry.sourceLabel)
        ]
        add(entry.numericValue, key: "numeric_value", to: &fields)
        add(nonEmpty: entry.textValue, key: "text_value", to: &fields)
        add(nonEmpty: measure?.unit, key: "unit", to: &fields)
        add(nonEmpty: measure?.roleRaw, key: "role", to: &fields)
        add(nonEmpty: measure?.directionRaw, key: "direction", to: &fields)
        add(measure?.baselineValue, key: "baseline_value", to: &fields)
        add(measure?.targetValue, key: "target_value", to: &fields)
        add(measure?.targetMinimum, key: "target_minimum", to: &fields)
        add(measure?.targetMaximum, key: "target_maximum", to: &fields)
        return PortableMetric(
            id: entry.id, profileID: profileID, goalID: measure?.goal?.id,
            definitionID: measure?.id, occurredAt: entry.date, kind: .goalResult,
            title: measure?.name ?? "Goal result", note: entry.note, fields: fields
        )
    }

    static func metric(from entry: FoodEntry) throws -> PortableMetric {
        guard let profileID = entry.profile?.id else {
            throw PortableMetricError.missingProfile(recordID: entry.id, kind: .nutrition)
        }
        var fields: [String: PortableValue] = [
            "meal_type": .string(entry.mealTypeRaw),
            "calories": .number(entry.calories),
            "protein_grams": .number(entry.proteinGrams),
            "carbohydrate_grams": .number(entry.carbohydrateGrams),
            "fat_grams": .number(entry.fatGrams),
            "water_milliliters": .number(entry.waterMilliliters),
            "servings": .number(entry.servings),
            "source": .string(entry.nutritionSource),
            "has_photo": .boolean(entry.photoData != nil)
        ]
        add(nonEmpty: entry.barcode, key: "barcode", to: &fields)
        return PortableMetric(
            id: entry.id, profileID: profileID, occurredAt: entry.date,
            kind: .nutrition, title: entry.name, note: entry.note, fields: fields
        )
    }

    static func metric(from entry: WeightEntry) throws -> PortableMetric {
        guard let profileID = entry.profile?.id else {
            throw PortableMetricError.missingProfile(recordID: entry.id, kind: .weight)
        }
        return PortableMetric(
            id: entry.id, profileID: profileID, occurredAt: entry.date,
            kind: .weight, title: "Body weight", note: entry.note,
            fields: ["kilograms": .number(entry.kilograms), "unit": .string("kg")]
        )
    }

    static func metric(from entry: SportEntry) throws -> PortableMetric {
        guard let profileID = entry.profile?.id else {
            throw PortableMetricError.missingProfile(recordID: entry.id, kind: .sport)
        }
        return PortableMetric(
            id: entry.id, profileID: profileID, categoryID: entry.category?.id,
            occurredAt: entry.date, kind: .sport, title: entry.sessionName, note: entry.note,
            fields: [
                "repetitions": .integer(entry.repetitions),
                "duration_minutes": .integer(entry.durationMinutes),
                "perceived_effort": .integer(entry.perceivedEffort),
                "soreness": .integer(entry.soreness)
            ]
        )
    }

    private static func add(_ value: Double?, key: String, to fields: inout [String: PortableValue]) {
        if let value { fields[key] = .number(value) }
    }

    private static func add(_ value: String?, key: String, to fields: inout [String: PortableValue]) {
        if let value { fields[key] = .string(value) }
    }

    private static func add(nonEmpty value: String?, key: String, to fields: inout [String: PortableValue]) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fields[key] = .string(value)
    }

    private static func add(_ value: Date?, key: String, to fields: inout [String: PortableValue]) {
        if let value { fields[key] = .string(iso8601.string(from: value)) }
    }

    private static let iso8601 = ISO8601DateFormatter()
}
