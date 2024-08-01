import Foundation

func mkString(start: String, fields: (field: Any?, name: String)...) -> String {
    mkString(start: "\(start)(", sep: ", ", end: ")", fields: fields)
}

func mkString(start: String, sep: String, end: String, fields: [(field: Any?, name: String)]) -> String {
    let nonNilFields = fields.compactMap { field, name in
        if let field {
            switch field {
            case is String: return "\(name): \"\(field)\""
            default: return "\(name): \(field)"
            }
        } else {
            return nil
        }
    }
    return mkString(start: start, sep: sep, end: end, fields: nonNilFields)
}

func mkString(start: String, sep: String, end: String, fields: [String]) -> String {
    var iter = fields.makeIterator()
    var s = start
    var first = true
    while let next = iter.next() {
        if first {
            first = false
        } else {
            s += sep
        }
        s += next
    }
    s += end
    return s
}