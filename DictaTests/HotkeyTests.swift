import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import Dicta

final class HotkeyTests: XCTestCase {
    func testRawValuesRoundTripForPersistence() {
        for key in Hotkey.allCases {
            XCTAssertEqual(Hotkey(rawValue: key.rawValue), key)
        }
        XCTAssertNil(Hotkey(rawValue: "leftShift"))
    }

    func testKeyCodesMatchCarbonVirtualKeys() {
        XCTAssertEqual(Hotkey.fn.keyCode, Int64(kVK_Function))
        XCTAssertEqual(Hotkey.rightOption.keyCode, Int64(kVK_RightOption))
        XCTAssertEqual(Hotkey.rightCommand.keyCode, Int64(kVK_RightCommand))
        XCTAssertEqual(Hotkey.rightControl.keyCode, Int64(kVK_RightControl))
    }

    /// The right-side keys must use device-specific bits, never the side-agnostic masks — otherwise holding the
    /// left twin would mask the right key's release and leave the app stuck in "recording".
    func testRightSideKeysUseDeviceSpecificFlagsNotGenericMasks() {
        XCTAssertFalse(Hotkey.rightOption.flag.contains(.maskAlternate))
        XCTAssertFalse(Hotkey.rightCommand.flag.contains(.maskCommand))
        XCTAssertFalse(Hotkey.rightControl.flag.contains(.maskControl))
        XCTAssertEqual(Hotkey.fn.flag, .maskSecondaryFn)
    }

    func testEveryHotkeyHasDistinctKeyCodeAndFlag() {
        let codes = Set(Hotkey.allCases.map(\.keyCode))
        let flags = Set(Hotkey.allCases.map(\.flag.rawValue))
        XCTAssertEqual(codes.count, Hotkey.allCases.count)
        XCTAssertEqual(flags.count, Hotkey.allCases.count)
    }
}
