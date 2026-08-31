import Darwin
import Foundation
import JavaScriptCore

private let maximumMessageBytes = 1 * 1_024 * 1_024
private let maximumCallbacks = 256
private let memoryLimitBytes: rlim_t = 256 * 1_024 * 1_024

struct Request: Codable {
    let id: String
    let script: String
    let globalsJSON: String
    let callbackLimit: Int
}

struct Response: Codable {
    let id: String
    let value: String?
    let globalsJSON: String?
    let callbacksJSON: String?
    let error: String?
}

private func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        let chunk = FileHandle.standardInput.readData(ofLength: count - data.count)
        if chunk.isEmpty { return nil }
        data.append(chunk)
    }
    return data
}

private func writeFrame(_ payload: Data) {
    var length = UInt32(payload.count).bigEndian
    var frame = Data(bytes: &length, count: 4)
    frame.append(payload)
    FileHandle.standardOutput.write(frame)
}

private func applyResourceLimits() {
    var addressSpace = rlimit(rlim_cur: memoryLimitBytes, rlim_max: memoryLimitBytes)
    _ = setrlimit(RLIMIT_AS, &addressSpace)
    var files = rlimit(rlim_cur: 16, rlim_max: 16)
    _ = setrlimit(RLIMIT_NOFILE, &files)
}

applyResourceLimits()

guard let header = readExactly(4) else { exit(2) }
let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
guard length <= maximumMessageBytes, let payload = readExactly(Int(length)),
      let request = try? JSONDecoder().decode(Request.self, from: payload) else { exit(3) }

guard let context = JSContext() else { exit(4) }
var capturedException: String?
context.exceptionHandler = { _, exception in
    if let exception {
        capturedException = exception.toString()
        fputs("JavaScript exception: \(exception)\n", stderr)
    }
}

guard let globalsLiteralData = try? JSONEncoder().encode(request.globalsJSON),
      let globalsLiteral = String(data: globalsLiteralData, encoding: .utf8) else { exit(3) }
let bootstrap = """
var __wmpGlobals = JSON.parse(\(globalsLiteral));
Object.keys(__wmpGlobals).forEach(function(key) { globalThis[key] = __wmpGlobals[key]; });
var __wmpCallbacks = [];
var __wmpTimers = [];
function callback(value) { if (__wmpCallbacks.length < \(maximumCallbacks)) __wmpCallbacks.push(value); }
function setTimeout(fn, period) {
  if (__wmpTimers.length >= \(maximumCallbacks)) return 0;
  __wmpTimers.push(fn); return __wmpTimers.length;
}
function setInterval(fn, period) { return setTimeout(fn, Math.max(8, period || 0)); }
function clearTimeout(token) { if (token > 0 && token <= __wmpTimers.length) __wmpTimers[token - 1] = null; }
function clearInterval(token) { clearTimeout(token); }
"""
_ = context.evaluateScript(bootstrap)
capturedException = nil
let value = context.evaluateScript(request.script)
var error = capturedException ?? context.exception?.toString()

if error == nil {
    capturedException = nil
    let callbackCount = min(max(request.callbackLimit, 0), maximumCallbacks)
    _ = context.evaluateScript(
        "for (var __i=0; __i<Math.min(__wmpTimers.length, \(callbackCount)); __i++) { if (__wmpTimers[__i]) __wmpTimers[__i](); }"
    )
    error = capturedException ?? context.exception?.toString()
}

let globals = context.evaluateScript("JSON.stringify(__wmpGlobals)")?.toString()
let callbacks = context.evaluateScript("JSON.stringify(__wmpCallbacks)")?.toString()
let response = Response(id: request.id,
                        value: value?.isUndefined == true ? nil : value?.toString(),
                        globalsJSON: globals,
                        callbacksJSON: callbacks,
                        error: error)
guard let responsePayload = try? JSONEncoder().encode(response),
      responsePayload.count <= maximumMessageBytes else { exit(5) }
writeFrame(responsePayload)
