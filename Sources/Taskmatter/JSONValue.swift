struct JSONKey {
    let stringValue: String
}

extension JSONKey: CodingKey {
    var intValue: Int? { nil }
    init?(intValue: Int) {
        return nil
    }
}

enum JSONNumber {
    case float(Float64)
    case int(Int64)
}

extension JSONNumber: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .float(let f):
            try container.encode(f)
        case .int(let i):
            try container.encode(i)
        }
    }
}

extension JSONNumber: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else {
            self = .float(try container.decode(Float64.self))
        }
    }
}

enum JSONValue {
    case null
    case bool(Bool)
    case number(JSONNumber)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])
}

extension JSONValue: Encodable {
    func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()

        case .bool(let b):
            var container = encoder.singleValueContainer()
            try container.encode(b)

        case .number(let n):
            var container = encoder.singleValueContainer()
            try container.encode(n)

        case .string(let s):
            var container = encoder.singleValueContainer()
            try container.encode(s)

        case .array(let values):
            var container = encoder.unkeyedContainer()
            for v in values {
                try container.encode(v)
            }

        case .object(let KeyValuePairs):
            var container = encoder.container(keyedBy: JSONKey.self)
            for (k, v) in KeyValuePairs {
                try container.encode(v, forKey: JSONKey(stringValue: k))
            }
        }
    }
}

enum JSONDecodeError: Error {
    case unknownSingleValue
    case unknownContainer
}

extension JSONValue: Decodable {
    init(from decoder: any Decoder) throws {
        if let keyedContainer = try? decoder.container(keyedBy: JSONKey.self) {
            var keyValuePairs: [(String, JSONValue)] = []
            for k in keyedContainer.allKeys {
                do {
                    keyValuePairs.append(
                        (
                            k.stringValue,
                            try keyedContainer.decode(
                                JSONValue.self, forKey: k)
                        ))
                } catch DecodingError.valueNotFound(_, _) {
                    keyValuePairs.append((k.stringValue, .null))
                }
            }
            self = .object(keyValuePairs)
        } else if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !unkeyedContainer.isAtEnd {
                do {
                    values.append(try unkeyedContainer.decode(JSONValue.self))
                } catch DecodingError.valueNotFound(_, _) {
                    values.append(.null)
                }
            }
            self = .array(values)
        } else if let singleValueContainer = try? decoder.singleValueContainer() {
            if singleValueContainer.decodeNil() {
                self = .null
            } else if let b = try? singleValueContainer.decode(Bool.self) {
                self = .bool(b)
            } else if let n = try? singleValueContainer.decode(JSONNumber.self) {
                self = .number(n)
            } else if let s = try? singleValueContainer.decode(String.self) {
                self = .string(s)
            } else {
                throw JSONDecodeError.unknownSingleValue
            }
        } else {
            throw JSONDecodeError.unknownContainer
        }
    }
}
