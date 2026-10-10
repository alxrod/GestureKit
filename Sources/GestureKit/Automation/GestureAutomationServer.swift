#if os(visionOS) && DEBUG
import GestureCore
import Foundation
import Network

/// The automation's server, in a debug build: HTTP on 127.0.0.1 only, so
/// nothing off the machine reaches it, which a visionOS simulator shares
/// with its Mac, so `curl http://127.0.0.1:<port>/state` there reaches the
/// app. One request a connection, its answer from `answer`, then the
/// connection closes. It works on a queue of its own and hands each request
/// to `answer`, which hops to the main actor.
final class GestureAutomationServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "net.alexbrodriguez.gesturekit.automation-server")
    private let answer: @Sendable (AutomationHTTPRequest) async -> AutomationHTTPResponse
    private var listener: NWListener?

    init(answer: @escaping @Sendable (AutomationHTTPRequest) async -> AutomationHTTPResponse) {
        self.answer = answer
    }

    /// Listens on 127.0.0.1 at `port`.
    func start(port: UInt16) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw AutomationError("\(port) isn't a port.")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                gestureAutomationLogger.info("The automation's server listens on 127.0.0.1:\(port, privacy: .public)")
            case .failed(let error):
                gestureAutomationLogger.error("The automation's server failed: \(String(describing: error), privacy: .public)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, received: Data())
    }

    /// Reads from `connection` until a whole request has come, then answers.
    private func read(_ connection: NWConnection, received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var received = received
            if let data { received.append(data) }
            switch AutomationHTTPRequest.read(received) {
            case .complete(let request):
                let answer = self.answer
                Task {
                    let response = await answer(request)
                    self.send(response, on: connection)
                }
            case .malformed(let reason):
                self.send(AutomationHTTPResponse(status: 400, json: ["ok": false, "error": .string(reason)]), on: connection)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.read(connection, received: received)
                }
            }
        }
    }

    private func send(_ response: AutomationHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
#endif
