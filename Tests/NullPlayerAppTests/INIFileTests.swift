import XCTest
@testable import NullPlayer

/// `INIFile` reads as Win32's `GetPrivateProfileString` does, the way Sonique's `skin.ini` is read.
final class INIFileTests: XCTestCase {
    private let text = "key=before\n[FILE]\n SkinName = Micro Aimp \n; note=x\n// also=x\nSkinName=second\n[Label] trailing\nTemplate= / %S\n[broken\nlost=1\n[file]\nAuthor=Me\n"

    func testSectionsAndKeysInAnyCaseTheFirstValueTrimmed() {
        let ini = INIFile(text)
        XCTAssertEqual(ini.value("file", "skinname"), "Micro Aimp")
        XCTAssertEqual(ini.value("LABEL", "Template"), "/ %S")
        XCTAssertNil(ini.value("", "key"), "lines before the first header belong to no section")
    }

    func testCommentsAndUnclosedHeadersAreSkipped() {
        let ini = INIFile(text)
        XCTAssertNil(ini.value("file", "; note"))
        XCTAssertNil(ini.value("file", "// also"))
        XCTAssertEqual(ini.value("label", "lost"), "1", "a header with no ] is skipped; its lines stay in the section before")
    }

    func testOnlyTheFirstSectionOfANameIsRead() {
        XCTAssertNil(INIFile(text).value("FILE", "Author"))
    }
}
