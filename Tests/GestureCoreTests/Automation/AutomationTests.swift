#if DEBUG
import Foundation
@_spi(GestureAutomation) import GestureCore
import Testing

@Suite("Automation's JSON")
struct AutomationJSONTests {
    @Test("A value is written with its keys sorted and read back the same")
    func roundTrip() throws {
        let value: AutomationJSON = ["ok": true, "outcome": "spawned", "count": 3, "at": [0.25, 1.5, -0.75], "none": nil]
        let text = value.text()
        #expect(text == #"{"at":[0.25,1.5,-0.75],"count":3,"none":null,"ok":true,"outcome":"spawned"}"#)
        #expect(try AutomationJSON.decoded(from: Data(text.utf8)) == value)
    }

    @Test("A place is rounded to the tenth of a millimeter")
    func vectors() {
        let place = AutomationJSON.vector(SIMD3<Float>(0.123456, 1.2, -0.9))
        #expect(place == [0.1235, 1.2, -0.9])
        #expect(AutomationJSON.number(.infinity, decimals: 2) == .null)
    }
}

@Suite("Automation's arguments")
struct AutomationArgumentsTests {
    @Test("A shell's strings are read as numbers, switches, and vectors")
    func lenient() throws {
        let arguments = try AutomationArguments([
            "command": "pluck", "item": "item 7", "hold": "0.4", "pull": "0, 0, 0.06", "release": "yes", "carry": [0.1, 0, 0],
        ])
        #expect(arguments.command == "pluck")
        #expect(try arguments.requiredString("item", example: "item 1") == "item 7")
        #expect(try arguments.number("hold") == 0.4)
        #expect(try arguments.vector("pull") == SIMD3(0, 0, 0.06))
        #expect(try arguments.vector("carry") == SIMD3(0.1, 0, 0))
        #expect(try arguments.bool("release") == true)
        #expect(try arguments.number("missing") == nil)
    }

    @Test("What can't be read is refused in a sentence")
    func refusals() throws {
        let arguments = try AutomationArguments(["command": "carry", "by": "0,1", "time": "soon", "handel": "panel-a"])
        #expect(throws: AutomationError.self) { try arguments.vector("by") }
        #expect(throws: AutomationError.self) { try arguments.number("time") }
        #expect(throws: AutomationError("carry doesn't take handel, time; it takes handle, by.")) {
            try arguments.refuseOthers(than: ["handle", "by"])
        }
        #expect(throws: AutomationError.self) { try AutomationArguments(["item": "item 7"]) }
        #expect(throws: AutomationError.self) { try AutomationArguments("pluck") }
    }
}

@Suite("Automation's HTTP")
struct AutomationHTTPTests {
    private let request = Data("POST /command?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 19\r\n\r\n{\"command\":\"state\"}".utf8)

    @Test("A request is read whole however its bytes arrive")
    func pieces() throws {
        for split in 0..<request.count {
            if case .complete = AutomationHTTPRequest.read(request.prefix(split)) {
                Issue.record("A request read whole from \(split) of its \(request.count) bytes")
            }
        }
        guard case .complete(let read) = AutomationHTTPRequest.read(request) else {
            Issue.record("The whole request wasn't read")
            return
        }
        #expect(read.method == "POST")
        #expect(read.path == "/command")
        #expect(read.headers["host"] == "127.0.0.1")
        #expect(try AutomationJSON.decoded(from: read.body) == ["command": "state"])
    }

    @Test("A request with no body, or a body too long, is told apart")
    func bodies() {
        #expect(AutomationHTTPRequest.read(Data("GET /state HTTP/1.1\r\n\r\n".utf8)) == .complete(AutomationHTTPRequest(method: "GET", path: "/state")))
        let tooLong = Data("POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)
        guard case .malformed = AutomationHTTPRequest.read(tooLong) else {
            Issue.record("A body longer than a command was taken")
            return
        }
    }

    @Test("An answer says its length and closes")
    func answer() {
        let response = AutomationHTTPResponse(json: ["ok": true])
        let text = String(decoding: response.bytes, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"))
        #expect(text.hasSuffix("\"ok\" : true\n}\n"))
    }
}

@Suite("Automation's paths")
struct AutomationPathTests {
    @Test("A move steps 90 times a second, easing, and ends where it's going")
    func move() throws {
        let steps = AutomationPath.steps(from: .zero, to: SIMD3(0, 0, 0.05), over: 0.4)
        #expect(steps.count == 36)
        #expect(steps.last == AutomationPath.Step(time: 0.4, point: SIMD3(0, 0, 0.05)))
        let first = try #require(steps.first)
        #expect(first.point.z < 0.05 / 36)
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.time < $1.time && $0.point.z <= $1.point.z })
        #expect(AutomationPath.steps(from: .zero, to: SIMD3(1, 0, 0), over: 0) == [AutomationPath.Step(time: 0, point: SIMD3(1, 0, 0))])
    }

    @Test("A still hand wavers within its amplitude")
    func held() {
        let steps = AutomationPath.held(at: .zero, for: 1, wavering: 2)
        #expect(steps.count == 90)
        #expect(steps.allSatisfy { ($0.point * $0.point).sum().squareRoot() <= 2.3 })
    }

    @Test("Meters and points: y flips, 1,360 to the meter")
    func units() {
        #expect(AutomationPath.points(ofMeters: SIMD3(0.1, 0.05, 0.05)) == SIMD3(136, -68, 68))
        #expect(AutomationPath.meters(ofPoints: SIMD3(136, -68, 68)) == SIMD3(0.1, 0.05, 0.05))
    }

    @Test("A drag speaks once it has gone its minimum distance, then at every move")
    func dragStart() {
        #expect(!AutomationPath.dragSpeaks(at: SIMD3(30, 40, 0), minimumDistance: 60, hasSpoken: false))
        #expect(AutomationPath.dragSpeaks(at: SIMD3(36, 48, 0), minimumDistance: 60, hasSpoken: false))
        #expect(AutomationPath.dragSpeaks(at: .zero, minimumDistance: 60, hasSpoken: true))
    }
}

@Suite("Automation's event log")
struct AutomationEventLogTests {
    @Test("A run of one thing on one target folds into a line")
    func folds() {
        var log = AutomationEventLog()
        log.record(AutomationEvent(time: 0, source: "pluck", target: "item 7", name: "lifted"))
        for step in 1...30 {
            log.record(AutomationEvent(time: Double(step) / 90, source: "pluck", target: "item 7", name: "carried", detail: .number(Double(step))))
        }
        log.record(AutomationEvent(time: 0.5, source: "pluck", target: "item 8", name: "carried"))
        #expect(log.lines.count == 3)
        #expect(log.lines[1].count == 30)
        #expect(log.lines[1].lastDetail == 30)
        #expect(log.names(from: "pluck", on: "item 7") == ["lifted", "carried"])
        #expect(log.contains("carried", from: "pluck", on: "item 8"))
        #expect(!log.contains("spawned", from: "pluck"))
    }

    @Test("Each gesture's outcome is told from what its adapter reported")
    func outcomes() {
        #expect(AutomationOutcome.pluck(["lifted", "spawned", "carried", "released", "settled"]) == "spawned")
        #expect(AutomationOutcome.pluck(["lifted", "settled"]) == "lifted")
        #expect(AutomationOutcome.pluck(["tapped"]) == "tapped")
        #expect(AutomationOutcome.pluck([]) == "stayed down")
        #expect(AutomationOutcome.surface(["pickUp", "beginCarry", "moveCarry", "endCarry"]) == "carry")
        #expect(AutomationOutcome.surface(["pickUp", "fireHold", "endHold"]) == "hold")
        #expect(AutomationOutcome.surface(["beginScroll", "moveScroll", "endScroll"]) == "scroll")
        #expect(AutomationOutcome.holdWatch(["touch", "held", "release"]) == "hold")
        #expect(AutomationOutcome.holdWatch(["touch", "release"]) == "let go before its hold")
        #expect(AutomationOutcome.carry(["touch", "begin", "carry", "end"]) == "carried")
        #expect(AutomationOutcome.carry(["touch", "end"]) == "nothing")
    }
}
#endif
