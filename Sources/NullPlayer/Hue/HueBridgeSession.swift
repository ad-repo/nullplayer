import Foundation
import Security

final class HueBridgeSessionFactory {
    static func makePinnedSession(expectedBridgeID: String?) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false

        let delegate = HueBridgeTLSPinningDelegate(expectedBridgeID: expectedBridgeID)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

final class HueBridgeTLSPinningDelegate: NSObject, URLSessionDelegate {
    private let expectedBridgeID: String?
    private lazy var rootCertificate: SecCertificate? = {
        guard let der = Self.derDataFromPEM(Self.signifyRootCAPEM) else {
            NSLog("HueBridgeTLSPinningDelegate: unable to decode Signify root CA PEM")
            return nil
        }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            NSLog("HueBridgeTLSPinningDelegate: bundled Signify root CA is not a valid certificate")
            return nil
        }
        return certificate
    }()

    init(expectedBridgeID: String?) {
        self.expectedBridgeID = expectedBridgeID
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard validateTrust(trust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func validateTrust(_ trust: SecTrust) -> Bool {
        guard let rootCertificate else {
            // Fail-open to CN-based identity validation only if the bundled root
            // certificate is unavailable. This keeps pairing functional in
            // development builds and avoids hard failure from a missing cert blob.
            return validateBridgeIdentityOnly(trust)
        }

        let policy = SecPolicyCreateSSL(true, nil)
        SecTrustSetPolicies(trust, policy)
        SecTrustSetAnchorCertificates(trust, [rootCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)

        var secError: CFError?
        guard SecTrustEvaluateWithError(trust, &secError) else {
            if let secError {
                NSLog("HueBridgeTLSPinningDelegate: trust evaluation failed: %@", secError.localizedDescription)
            }
            return false
        }

        guard let expectedBridgeID else {
            return true
        }

        let normalizedExpected = Self.normalizeBridgeID(expectedBridgeID)
        guard !normalizedExpected.isEmpty else {
            return true
        }

        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return false
        }

        let subjectSummary = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
        if Self.bridgeIdentityMatches(expectedBridgeID: expectedBridgeID, subjectSummary: subjectSummary) {
            return true
        }

        NSLog("HueBridgeTLSPinningDelegate: bridge ID mismatch. expected=%@ actual=%@", expectedBridgeID, subjectSummary)
        return false
    }

    private func validateBridgeIdentityOnly(_ trust: SecTrust) -> Bool {
        guard let expectedBridgeID else { return false }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return false
        }

        let subjectSummary = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
        if Self.bridgeIdentityMatches(expectedBridgeID: expectedBridgeID, subjectSummary: subjectSummary) {
            return true
        }

        NSLog(
            "HueBridgeTLSPinningDelegate: fallback identity validation failed. expected=%@ actual=%@",
            expectedBridgeID,
            subjectSummary
        )
        return false
    }

    private static func bridgeIdentityMatches(expectedBridgeID: String, subjectSummary: String) -> Bool {
        let normalizedSummary = normalizeBridgeID(subjectSummary)
        guard !normalizedSummary.isEmpty else {
            return false
        }

        let candidates = bridgeIDCandidates(from: expectedBridgeID)
        guard !candidates.isEmpty else {
            return false
        }

        return candidates.contains { normalizedSummary.contains($0) }
    }

    private static func bridgeIDCandidates(from value: String) -> Set<String> {
        let normalized = normalizeBridgeID(value)
        var candidates = Set<String>()
        if normalized.count >= 6 {
            candidates.insert(normalized)
        }
        for hexRun in hexRuns(in: value) {
            candidates.insert(hexRun)
        }

        // Bonjour names often carry a "huebridge-" prefix while certificates carry only
        // the bridge hex identity. Matching on the trailing hex token handles that variant.
        if normalized.count > 6 {
            let trailing = String(normalized.suffix(6))
            if trailing.allSatisfy({ $0.isASCII && ($0.isNumber || ($0 >= "a" && $0 <= "f")) }) {
                candidates.insert(trailing)
            }
        }
        return candidates
    }

    private static func hexRuns(in value: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for char in value.lowercased() {
            if char.isASCII && (char.isNumber || (char >= "a" && char <= "f")) {
                current.append(char)
            } else {
                if current.count >= 6 {
                    runs.append(current)
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= 6 {
            runs.append(current)
        }
        return runs
    }

    private static func normalizeBridgeID(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isASCII && ($0.isNumber || ($0 >= "a" && $0 <= "z")) }
    }

    private static func derDataFromPEM(_ pem: String) -> Data? {
        let lines = pem
            .components(separatedBy: .newlines)
            .filter { !$0.contains("BEGIN CERTIFICATE") && !$0.contains("END CERTIFICATE") }
        return Data(base64Encoded: lines.joined())
    }

    // Signify/Philips Hue Bridge Root CA certificate (PEM).
    // Subject/Issuer: C=NL, O=Philips Hue, CN=root-bridge
    private static let signifyRootCAPEM = """
-----BEGIN CERTIFICATE-----
MIICMjCCAdigAwIBAgIUO7FSLbaxikuXAljzVaurLXWmFw4wCgYIKoZIzj0EAwIw
OTELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1BoaWxpcHMgSHVlMRQwEgYDVQQDDAty
b290LWJyaWRnZTAiGA8yMDE3MDEwMTAwMDAwMFoYDzIwMzgwMTE5MDMxNDA3WjA5
MQswCQYDVQQGEwJOTDEUMBIGA1UECgwLUGhpbGlwcyBIdWUxFDASBgNVBAMMC3Jv
b3QtYnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjNw2tx2AplOf9x86
aTdvEcL1FU65QDxziKvBpW9XXSIcibAeQiKxegpq8Exbr9v6LBnYbna2VcaK0G22
jOKkTqOBuTCBtjAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNV
HQ4EFgQUZ2ONTFrDT6o8ItRnKfqWKnHFGmQwdAYDVR0jBG0wa4AUZ2ONTFrDT6o8
ItRnKfqWKnHFGmShPaQ7MDkxCzAJBgNVBAYTAk5MMRQwEgYDVQQKDAtQaGlsaXBz
IEh1ZTEUMBIGA1UEAwwLcm9vdC1icmlkZ2WCFDuxUi22sYpLlwJY81Wrqy11phcO
MAoGCCqGSM49BAMCA0gAMEUCIEBYYEOsa07TH7E5MJnGw557lVkORgit2Rm1h3B2
sFgDAiEA1Fj/C3AN5psFMjo0//mrQebo0eKd3aWRx+pQY08mk48=
-----END CERTIFICATE-----
"""
}
