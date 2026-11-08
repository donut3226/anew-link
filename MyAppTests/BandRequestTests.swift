import Foundation
import Testing
@testable import MyApp

/// Checks parsing of band-to-phone requests on 4002 (spec section 6).
struct BandRequestTests {

    @Test(arguments: [
        (UInt8(0), "Sync tick"),
        (1, "Get calendar"),
        (2, "Locate phone"),
        (3, "Get weather"),
        (4, "Riiiver side button"),
        (5, "Riiiver home icon"),
        (6, "Unknown (payment?)"),
        (11, "Music info"),
        (42, "Unknown type 42"),
    ])
    func names(type: UInt8, name: String) throws {
        let request = try #require(BandRequest(Data([type])))
        #expect(request.type == type)
        #expect(request.name == name)
        #expect(request.notificationID == nil)
    }

    @Test func removeNotificationReadsLittleEndianID() throws {
        let request = try #require(BandRequest(Data([10, 0x04, 0x03, 0x02, 0x01])))
        #expect(request.name == "Remove notification")
        #expect(request.notificationID == 0x0102_0304)
    }

    @Test func removeNotificationWithoutIDHasNone() throws {
        #expect(try #require(BandRequest(Data([10]))).notificationID == nil)
    }

    @Test func emptyDataIsNil() {
        #expect(BandRequest(Data()) == nil)
    }
}
