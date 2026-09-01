import Foundation

/// A minimal HTTP server on the loopback interface, one connection at a time.
///
/// Exists because a `URLProtocol` stub cannot show what `URLSession` really does with a refused redirection:
/// a redirection a `URLProtocol` signals through `wasRedirectedTo` leaves no response behind once the
/// delegate refuses it, whereas a real exchange ends the task on the 3xx itself — which is where
/// `DataRequest.redirect()` reads the callback. Only a real exchange pins that.
final class LoopbackHTTPServer {
    /// The port the server ended up on, since it binds to whatever is free.
    let port: UInt16

    private let listeningSocket: Int32
    private let respond: (_ requestLine: String) -> String

    /// - Parameter respond: the raw HTTP response to write back, given the request line (`GET /path HTTP/1.1`).
    init(respond: @escaping (_ requestLine: String) -> String) throws {
        self.respond = respond

        // Everything below works on a local descriptor: `self` is not fully initialised until `port` is set,
        // so the pointer closures may not capture a member.
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw Failure.socket(errno) }

        var reuse: Int32 = 1
        setsockopt(fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0 // whatever port is free
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fileDescriptor, 4) == 0 else {
            close(fileDescriptor)
            throw Failure.bind(errno)
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fileDescriptor, $0, &length) }
        }
        guard named == 0 else {
            close(fileDescriptor)
            throw Failure.bind(errno)
        }

        listeningSocket = fileDescriptor
        port = UInt16(bigEndian: boundAddress.sin_port)

        Thread.detachNewThread { [respond] in
            while true {
                let connection = accept(fileDescriptor, nil, nil)
                guard connection >= 0 else { return } // the listening socket was closed: stop() was called
                defer { close(connection) }

                var request = ""
                var buffer = [UInt8](repeating: 0, count: 1024)
                while !request.contains("\r\n\r\n") {
                    let read = recv(connection, &buffer, buffer.count, 0)
                    guard read > 0 else { break }
                    request += String(decoding: buffer[0 ..< read], as: UTF8.self)
                }

                let requestLine = request.components(separatedBy: "\r\n").first ?? ""
                Array(respond(requestLine).utf8).withUnsafeBufferPointer { _ = send(connection, $0.baseAddress, $0.count, 0) }
            }
        }
    }

    func stop() {
        close(listeningSocket) // unblocks the accept the thread is sitting on, which then returns
    }

    enum Failure: Error {
        case socket(Int32)
        case bind(Int32)
    }
}
