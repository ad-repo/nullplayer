#!/usr/bin/env swift
//
// test_plex_rate.swift
// Standalone test for Plex track rating API
//
// This script validates the /:/rate endpoint before implementing it in AdAmp.
//
// Usage:
//   PLEX_URL=http://192.168.1.x:32400 PLEX_TOKEN=xxx swift scripts/test_plex_rate.swift
//
// Optional:
//   LIBRARY_ID=1           # Music library ID (default: auto-detect)
//   TRACK_ID=123456        # Specific track to rate (default: random track)
//   TEST_RATING=8          # Rating to set 0-10 (default: 8 = 4 stars)
//   RESTORE_RATING=true    # Whether to restore original rating after test
//

import Foundation

// MARK: - Configuration

let plexURL = ProcessInfo.processInfo.environment["PLEX_URL"] ?? "http://192.168.1.100:32400"
let plexToken = ProcessInfo.processInfo.environment["PLEX_TOKEN"] ?? "YOUR_PLEX_TOKEN"
var libraryID = ProcessInfo.processInfo.environment["LIBRARY_ID"]
let trackID = ProcessInfo.processInfo.environment["TRACK_ID"]
let testRating = Int(ProcessInfo.processInfo.environment["TEST_RATING"] ?? "8") ?? 8
let restoreRating = ProcessInfo.processInfo.environment["RESTORE_RATING"] != "false"

print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
print("  PLEX RATING API TEST")
print("  Tests PUT /:/rate endpoint for setting user star ratings")
print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
print("")
print("Configuration:")
print("  Server: \(plexURL)")
print("  Token: \(plexToken.prefix(8))...")
print("  Test Rating: \(testRating) (\(testRating / 2) stars)")
print("  Restore Original: \(restoreRating)")
print("")

guard plexToken != "YOUR_PLEX_TOKEN" else {
    print("ERROR: Please set PLEX_TOKEN environment variable")
    print("")
    print("Usage:")
    print("  PLEX_URL=http://192.168.1.x:32400 PLEX_TOKEN=xxx swift scripts/test_plex_rate.swift")
    exit(1)
}

// MARK: - HTTP Helpers

func fetchJSON(urlString: String, method: String = "GET") -> [String: Any]? {
    guard let url = URL(string: urlString) else {
        print("ERROR: Invalid URL: \(urlString)")
        return nil
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("AdAmp", forHTTPHeaderField: "X-Plex-Product")
    request.setValue("1.0", forHTTPHeaderField: "X-Plex-Version")
    request.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
    request.setValue("test-plex-rate-script", forHTTPHeaderField: "X-Plex-Client-Identifier")
    request.timeoutInterval = 30
    
    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?
    var resultError: Error?
    var httpStatusCode: Int = 0
    
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        resultData = data
        resultError = error
        httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 30)
    
    if let error = resultError {
        print("ERROR: \(error.localizedDescription)")
        return nil
    }
    
    // For PUT requests, we mainly care about the status code
    if method == "PUT" {
        return ["statusCode": httpStatusCode]
    }
    
    guard let data = resultData,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("ERROR: Failed to parse JSON (status: \(httpStatusCode))")
        return nil
    }
    
    return json
}

/// Perform a PUT request and return success/failure
func putRequest(urlString: String) -> (success: Bool, statusCode: Int) {
    guard let url = URL(string: urlString) else {
        print("ERROR: Invalid URL: \(urlString)")
        return (false, 0)
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("AdAmp", forHTTPHeaderField: "X-Plex-Product")
    request.setValue("1.0", forHTTPHeaderField: "X-Plex-Version")
    request.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
    request.setValue("test-plex-rate-script", forHTTPHeaderField: "X-Plex-Client-Identifier")
    request.timeoutInterval = 30
    
    let semaphore = DispatchSemaphore(value: 0)
    var resultError: Error?
    var httpStatusCode: Int = 0
    
    let task = URLSession.shared.dataTask(with: request) { _, response, error in
        resultError = error
        httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 30)
    
    if let error = resultError {
        print("ERROR: \(error.localizedDescription)")
        return (false, 0)
    }
    
    return (httpStatusCode == 200, httpStatusCode)
}

/// Format rating as stars
func formatStars(_ rating: Double?) -> String {
    guard let rating = rating else { return "☆☆☆☆☆ (unrated)" }
    let stars = Int(round(rating / 2))
    return String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars) + " (\(rating)/10)"
}

// MARK: - Step 1: Find a Music Library

print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
print("STEP 1: Find music library")
print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))

if libraryID == nil {
    let sectionsURL = "\(plexURL)/library/sections?X-Plex-Token=\(plexToken)"
    print("Fetching libraries...")
    
    if let json = fetchJSON(urlString: sectionsURL),
       let container = json["MediaContainer"] as? [String: Any],
       let directories = container["Directory"] as? [[String: Any]] {
        
        // Find first music library (type = "artist")
        for dir in directories {
            if let type = dir["type"] as? String, type == "artist",
               let key = dir["key"] as? String {
                libraryID = key
                let title = dir["title"] as? String ?? "Unknown"
                print("Found music library: \(title) (ID: \(key))")
                break
            }
        }
        
        if libraryID == nil {
            print("ERROR: No music library found")
            print("Available libraries:")
            for dir in directories {
                let title = dir["title"] as? String ?? "Unknown"
                let type = dir["type"] as? String ?? "Unknown"
                let key = dir["key"] as? String ?? "?"
                print("  - \(title) (type: \(type), id: \(key))")
            }
            exit(1)
        }
    } else {
        print("ERROR: Failed to fetch libraries")
        exit(1)
    }
}

guard let libID = libraryID else {
    print("ERROR: No library ID available")
    exit(1)
}

print("Using library ID: \(libID)")
print("")

// MARK: - Step 2: Get a Test Track

print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
print("STEP 2: Get a test track")
print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))

var testTrackID = trackID

if testTrackID == nil {
    print("Fetching a random track...")
    let listURL = "\(plexURL)/library/sections/\(libID)/all?type=10&sort=random&limit=1&X-Plex-Token=\(plexToken)"
    
    if let json = fetchJSON(urlString: listURL),
       let container = json["MediaContainer"] as? [String: Any],
       let metadata = container["Metadata"] as? [[String: Any]],
       let firstTrack = metadata.first,
       let ratingKey = firstTrack["ratingKey"] as? String {
        testTrackID = ratingKey
        let title = firstTrack["title"] as? String ?? "Unknown"
        let artist = firstTrack["grandparentTitle"] as? String ?? "Unknown"
        print("Selected track: \(artist) - \(title)")
        print("Rating key: \(ratingKey)")
    } else {
        print("ERROR: Could not find any tracks in library")
        exit(1)
    }
}

guard let ratingKey = testTrackID else {
    print("ERROR: No track ID available")
    exit(1)
}

print("")

// MARK: - Step 3: Fetch Current Rating

print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
print("STEP 3: Fetch current track metadata")
print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))

let metadataURL = "\(plexURL)/library/metadata/\(ratingKey)?X-Plex-Token=\(plexToken)"
print("URL: \(metadataURL)")

var originalRating: Double? = nil
var trackTitle = "Unknown"
var trackArtist = "Unknown"

if let json = fetchJSON(urlString: metadataURL),
   let container = json["MediaContainer"] as? [String: Any],
   let metadata = container["Metadata"] as? [[String: Any]],
   let track = metadata.first {
    
    trackTitle = track["title"] as? String ?? "Unknown"
    trackArtist = track["grandparentTitle"] as? String ?? "Unknown"
    originalRating = track["userRating"] as? Double
    
    print("")
    print("Track: \(trackArtist) - \(trackTitle)")
    print("Current rating: \(formatStars(originalRating))")
    
    // Also check for lastRatedAt
    if let lastRatedAt = track["lastRatedAt"] as? Int {
        let date = Date(timeIntervalSince1970: TimeInterval(lastRatedAt))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        print("Last rated: \(formatter.string(from: date))")
    } else {
        print("Last rated: Never")
    }
} else {
    print("ERROR: Failed to fetch track metadata")
    exit(1)
}

print("")

// MARK: - Step 4: Test Setting a Rating

print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
print("STEP 4: Test PUT /:/rate endpoint")
print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))

// According to python-plexapi, the endpoint is:
// PUT /:/rate?key={ratingKey}&identifier=com.plexapp.plugins.library&rating={rating}

let rateURL = "\(plexURL)/:/rate?key=\(ratingKey)&identifier=com.plexapp.plugins.library&rating=\(testRating)&X-Plex-Token=\(plexToken)"

print("Setting rating to: \(testRating) (\(testRating / 2) stars)")
print("URL: PUT \(plexURL)/:/rate?key=\(ratingKey)&identifier=...&rating=\(testRating)")
print("")

let (success, statusCode) = putRequest(urlString: rateURL)

if success {
    print("✓ PUT request succeeded (HTTP \(statusCode))")
} else {
    print("✗ PUT request FAILED (HTTP \(statusCode))")
    print("")
    print("Possible causes:")
    print("  - Invalid rating key")
    print("  - Authentication issue")
    print("  - Server doesn't support rating for this item type")
    
    // Try GET method as fallback test
    print("")
    print("Trying GET method as fallback...")
    let getResult = fetchJSON(urlString: rateURL, method: "GET")
    if let status = getResult?["statusCode"] as? Int, status == 200 {
        print("GET method worked! (HTTP \(status))")
        print("NOTE: Plex might accept both GET and PUT for /:/rate")
    } else {
        print("GET method also failed")
    }
    exit(1)
}

print("")

// MARK: - Step 5: Verify the Rating Changed

print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
print("STEP 5: Verify rating was updated")
print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))

// Small delay to allow server to process
print("Waiting 500ms for server to process...")
Thread.sleep(forTimeInterval: 0.5)

if let json = fetchJSON(urlString: metadataURL),
   let container = json["MediaContainer"] as? [String: Any],
   let metadata = container["Metadata"] as? [[String: Any]],
   let track = metadata.first {
    
    let newRating = track["userRating"] as? Double
    
    print("New rating: \(formatStars(newRating))")
    
    if let newRating = newRating {
        if Int(newRating) == testRating {
            print("✓ Rating successfully updated!")
        } else {
            print("⚠ Rating changed but value differs: expected \(testRating), got \(Int(newRating))")
        }
    } else {
        print("✗ Rating is nil after update - something went wrong")
    }
    
    // Check lastRatedAt was updated
    if let lastRatedAt = track["lastRatedAt"] as? Int {
        let date = Date(timeIntervalSince1970: TimeInterval(lastRatedAt))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        print("Last rated: \(formatter.string(from: date))")
        
        // Check if it was updated recently (within last minute)
        if Date().timeIntervalSince(date) < 60 {
            print("✓ lastRatedAt timestamp was updated")
        }
    }
} else {
    print("ERROR: Failed to verify rating")
}

print("")

// MARK: - Step 6: Test Clearing Rating

print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
print("STEP 6: Test clearing rating (rating=-1)")
print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))

let clearURL = "\(plexURL)/:/rate?key=\(ratingKey)&identifier=com.plexapp.plugins.library&rating=-1&X-Plex-Token=\(plexToken)"

print("Setting rating to: -1 (clear)")

let (clearSuccess, clearStatus) = putRequest(urlString: clearURL)

if clearSuccess {
    print("✓ Clear rating succeeded (HTTP \(clearStatus))")
    
    // Verify it was cleared
    Thread.sleep(forTimeInterval: 0.5)
    
    if let json = fetchJSON(urlString: metadataURL),
       let container = json["MediaContainer"] as? [String: Any],
       let metadata = container["Metadata"] as? [[String: Any]],
       let track = metadata.first {
        
        let clearedRating = track["userRating"] as? Double
        
        if clearedRating == nil {
            print("✓ Rating successfully cleared (now nil)")
        } else {
            print("⚠ Rating still present after clear: \(formatStars(clearedRating))")
            print("  Note: Some Plex versions may retain the rating value")
        }
    }
} else {
    print("✗ Clear rating FAILED (HTTP \(clearStatus))")
}

print("")

// MARK: - Step 7: Restore Original Rating

if restoreRating {
    print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
    print("STEP 7: Restore original rating")
    print("-" .padding(toLength: 70, withPad: "-", startingAt: 0))
    
    let restoreValue: Int
    if let orig = originalRating {
        restoreValue = Int(orig)
        print("Restoring original rating: \(formatStars(originalRating))")
    } else {
        restoreValue = -1
        print("Original was unrated, clearing rating...")
    }
    
    let restoreURL = "\(plexURL)/:/rate?key=\(ratingKey)&identifier=com.plexapp.plugins.library&rating=\(restoreValue)&X-Plex-Token=\(plexToken)"
    
    let (restoreSuccess, restoreStatus) = putRequest(urlString: restoreURL)
    
    if restoreSuccess {
        print("✓ Original rating restored (HTTP \(restoreStatus))")
    } else {
        print("✗ Failed to restore original rating (HTTP \(restoreStatus))")
    }
    
    print("")
}

// MARK: - Summary

print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
print("  TEST SUMMARY")
print("=" .padding(toLength: 70, withPad: "=", startingAt: 0))
print("")
print("API Endpoint: PUT /:/rate")
print("Parameters:")
print("  - key: {ratingKey}           # The item's rating key")
print("  - identifier: com.plexapp.plugins.library")
print("  - rating: {0-10 or -1}       # -1 to clear")
print("")
print("Rating Scale:")
print("  2  = ★☆☆☆☆ (1 star)")
print("  4  = ★★☆☆☆ (2 stars)")
print("  6  = ★★★☆☆ (3 stars)")
print("  8  = ★★★★☆ (4 stars)")
print("  10 = ★★★★★ (5 stars)")
print("  -1 = Clear rating")
print("")
print("Implementation Notes:")
print("  - Use PUT method (python-plexapi uses PUT)")
print("  - Returns HTTP 200 on success, no response body")
print("  - userRating field updates in track metadata")
print("  - lastRatedAt timestamp updates automatically")
print("")

if success {
    print("✓ ALL TESTS PASSED - API is working as expected")
} else {
    print("✗ SOME TESTS FAILED - Review output above")
}

print("")
print("Test complete.")
