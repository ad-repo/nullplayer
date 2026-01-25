#!/usr/bin/env swift
//
// test_chromecast.swift
// Standalone Chromecast protocol test for debugging
//
// Usage: swift scripts/test_chromecast.swift
//
// This script tests the Google Cast Protocol v2 implementation in isolation
// from the main app. Use it to debug connection, message encoding/decoding,
// and session establishment issues.
//
// Update chromecastIP below with your device's IP address (discovered via mDNS).
//

import Foundation
import Network

print("🔍 Chromecast Protocol Test")
print("============================")

// Chromecast IP - discovered earlier
let chromecastIP = "192.168.0.199"
let chromecastPort = 8009

var receiveBuffer = Data()
var transportId: String?

// MARK: - Protobuf Encoding

func encodeVarint(_ value: UInt64) -> [UInt8] {
    var result: [UInt8] = []
    var v = value
    while v > 127 {
        result.append(UInt8(v & 0x7F) | 0x80)
        v >>= 7
    }
    result.append(UInt8(v))
    return result
}

func encodeString(_ str: String) -> Data {
    let utf8 = Data(str.utf8)
    var result = Data(encodeVarint(UInt64(utf8.count)))
    result.append(utf8)
    return result
}

func encodeCastMessage(namespace: String, payload: String, destination: String = "receiver-0") -> Data {
    var result = Data()
    
    // Field 1: protocol_version = 0
    result.append(0x08)
    result.append(contentsOf: encodeVarint(0))
    
    // Field 2: source_id = "sender-0"
    result.append(0x12)
    result.append(encodeString("sender-0"))
    
    // Field 3: destination_id
    result.append(0x1a)
    result.append(encodeString(destination))
    
    // Field 4: namespace
    result.append(0x22)
    result.append(encodeString(namespace))
    
    // Field 5: payload_type = 0 (string)
    result.append(0x28)
    result.append(contentsOf: encodeVarint(0))
    
    // Field 6: payload_utf8
    result.append(0x32)
    result.append(encodeString(payload))
    
    return result
}

func frameMessage(_ data: Data) -> Data {
    var framed = Data()
    var len = UInt32(data.count).bigEndian
    framed.append(Data(bytes: &len, count: 4))
    framed.append(data)
    return framed
}

// MARK: - Protobuf Decoding

func decodeVarint(_ data: Data, at offset: Int) -> (UInt64, Int)? {
    var value: UInt64 = 0
    var shift = 0
    var pos = offset
    while pos < data.count {
        let byte = data[pos]
        pos += 1
        value |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 { return (value, pos) }
        shift += 7
        if shift > 63 { return nil }
    }
    return nil
}

func decodeString(_ data: Data, at offset: Int) -> (String, Int)? {
    guard let (length, dataOffset) = decodeVarint(data, at: offset) else { return nil }
    let end = dataOffset + Int(length)
    guard end <= data.count else { return nil }
    guard let str = String(data: data[dataOffset..<end], encoding: .utf8) else { return nil }
    return (str, end)
}

func skipField(_ data: Data, at offset: Int, wireType: Int) -> Int? {
    switch wireType {
    case 0: return decodeVarint(data, at: offset)?.1
    case 1: return offset + 8
    case 2:
        guard let (len, o) = decodeVarint(data, at: offset) else { return nil }
        return o + Int(len)
    case 5: return offset + 4
    default: return nil
    }
}

struct CastMessage {
    var namespace: String = ""
    var sourceId: String = ""
    var destinationId: String = ""
    var payloadUtf8: String = ""
}

func decodeCastMessage(_ data: Data) -> CastMessage? {
    var msg = CastMessage()
    var offset = 0
    
    while offset < data.count {
        guard let (tag, newOffset) = decodeVarint(data, at: offset) else { break }
        let fieldNumber = Int(tag >> 3)
        let wireType = Int(tag & 0x7)
        offset = newOffset
        
        switch (fieldNumber, wireType) {
        case (2, 2):
            guard let (v, o) = decodeString(data, at: offset) else { return nil }
            msg.sourceId = v
            offset = o
        case (3, 2):
            guard let (v, o) = decodeString(data, at: offset) else { return nil }
            msg.destinationId = v
            offset = o
        case (4, 2):
            guard let (v, o) = decodeString(data, at: offset) else { return nil }
            msg.namespace = v
            offset = o
        case (6, 2):
            guard let (v, o) = decodeString(data, at: offset) else { return nil }
            msg.payloadUtf8 = v
            offset = o
        default:
            guard let o = skipField(data, at: offset, wireType: wireType) else { return nil }
            offset = o
        }
    }
    return msg
}

// MARK: - Message Handling

func processBuffer() {
    print("   processBuffer: buffer has \(receiveBuffer.count) bytes")
    
    while receiveBuffer.count >= 4 {
        // Read length safely
        let b0 = receiveBuffer[receiveBuffer.startIndex]
        let b1 = receiveBuffer[receiveBuffer.startIndex + 1]
        let b2 = receiveBuffer[receiveBuffer.startIndex + 2]
        let b3 = receiveBuffer[receiveBuffer.startIndex + 3]
        let length = UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3)
        
        print("   Message length: \(length)")
        
        let total = 4 + Int(length)
        guard receiveBuffer.count >= total else {
            print("   Need more data: have \(receiveBuffer.count), need \(total)")
            break
        }
        
        // Extract message
        let startIdx = receiveBuffer.startIndex + 4
        let endIdx = receiveBuffer.startIndex + total
        let msgData = Data(receiveBuffer[startIdx..<endIdx])
        
        // Remove from buffer
        receiveBuffer = Data(receiveBuffer.dropFirst(total))
        
        print("   Decoding \(msgData.count) bytes...")
        if let msg = decodeCastMessage(msgData) {
            handleMessage(msg)
        } else {
            print("❌ Failed to decode message")
            print("   First 50 bytes: \(Array(msgData.prefix(50)))")
        }
    }
}

func handleMessage(_ msg: CastMessage) {
    print("📨 Received: namespace=\(msg.namespace), from=\(msg.sourceId)")
    
    guard let data = msg.payloadUtf8.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else {
        print("   Payload: \(msg.payloadUtf8)")
        return
    }
    
    print("   Type: \(type)")
    
    if type == "RECEIVER_STATUS" {
        if let status = json["status"] as? [String: Any],
           let apps = status["applications"] as? [[String: Any]],
           let app = apps.first,
           let tid = app["transportId"] as? String {
            transportId = tid
            print("✅ Got transportId: \(tid)")
        }
    }
}

// MARK: - Main Test

print("\n1. Connecting to Chromecast at \(chromecastIP):\(chromecastPort)...")

let tlsOptions = NWProtocolTLS.Options()
sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, completion in
    completion(true)
}, DispatchQueue.global())

let params = NWParameters(tls: tlsOptions)
let connection = NWConnection(
    host: NWEndpoint.Host(chromecastIP),
    port: NWEndpoint.Port(integerLiteral: UInt16(chromecastPort)),
    using: params
)

let semaphore = DispatchSemaphore(value: 0)
var connected = false
var error: Error?

connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        print("✅ TLS Connected!")
        connected = true
        semaphore.signal()
    case .failed(let err):
        print("❌ Connection failed: \(err)")
        error = err
        semaphore.signal()
    default:
        break
    }
}

connection.start(queue: DispatchQueue.global())

// Wait for connection
_ = semaphore.wait(timeout: .now() + 10)

guard connected else {
    print("❌ Failed to connect")
    exit(1)
}

// Set up receive handler
func startReceiving() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
        if let data = content {
            print("📥 Received \(data.count) bytes")
            receiveBuffer.append(data)
            processBuffer()
        }
        if let error = error {
            print("❌ Receive error: \(error)")
        }
        if !isComplete && error == nil {
            startReceiving()
        }
    }
}

startReceiving()

// 2. Send CONNECT message
print("\n2. Sending CONNECT message...")
let connectPayload = "{\"type\":\"CONNECT\"}"
let connectMsg = encodeCastMessage(
    namespace: "urn:x-cast:com.google.cast.tp.connection",
    payload: connectPayload
)
connection.send(content: frameMessage(connectMsg), completion: .contentProcessed { err in
    if let err = err {
        print("❌ Send CONNECT error: \(err)")
    } else {
        print("✅ CONNECT sent")
    }
})

// Wait a bit for response
Thread.sleep(forTimeInterval: 1)

// 3. Send LAUNCH command
print("\n3. Sending LAUNCH command for Default Media Receiver...")
let launchPayload = "{\"type\":\"LAUNCH\",\"appId\":\"CC1AD845\",\"requestId\":1}"
let launchMsg = encodeCastMessage(
    namespace: "urn:x-cast:com.google.cast.receiver",
    payload: launchPayload
)
connection.send(content: frameMessage(launchMsg), completion: .contentProcessed { err in
    if let err = err {
        print("❌ Send LAUNCH error: \(err)")
    } else {
        print("✅ LAUNCH sent")
    }
})

// Wait for transportId
print("\n4. Waiting for RECEIVER_STATUS with transportId...")
for i in 1...15 {
    Thread.sleep(forTimeInterval: 1)
    print("   Waiting... (\(i)s)")
    if transportId != nil {
        print("\n✅ SUCCESS! Got transportId: \(transportId!)")
        break
    }
}

if transportId == nil {
    print("\n❌ TIMEOUT - No transportId received after 15 seconds")
    print("\nDebug info:")
    print("  - Buffer size: \(receiveBuffer.count) bytes")
}

// Clean up
connection.cancel()
print("\n🔌 Connection closed")
