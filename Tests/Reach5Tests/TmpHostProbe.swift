import XCTest
@testable import Reach5

final class TmpHostProbe: XCTestCase {
    func testProbe() {
        for s in ["https://:8443", "https://[]", "https://"] {
            let u = URL(string: s)!
            let host = u.host
            print("PROBE \(s) -> host=\(host == nil ? "nil" : "\"\(host!)\"") normalizedHost=\(u.normalizedHost ?? "nil") isEmpty=\(host?.isEmpty ?? true)")
        }
    }
}
