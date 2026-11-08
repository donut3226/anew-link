import CoreBluetooth
import Observation

/// Finds the Wena 3 band, reads its info and battery, and sends it time and weather.
/// Every write goes through `send(_:to:completion:)`, and only happens when the user taps a button.
/// It never subscribes to updates, and never pairs or unpairs.
///
/// `@Observable` means SwiftUI watches this object and redraws the screen
/// whenever `state`, `info` or `batteryPercent` changes.
///
/// It inherits from `NSObject` because CoreBluetooth is an older Objective-C framework,
/// and its "delegate" objects (the objects it calls back with results) must be NSObjects.
@Observable
final class BandConnection: NSObject {

    enum State: Equatable {
        case starting        // Waiting for Bluetooth to report its status
        case unsupported     // No Bluetooth, for example the Simulator
        case unauthorized    // The user said no to the Bluetooth permission
        case poweredOff      // Bluetooth is switched off
        case searching       // Scanning for the band
        case notFound        // Scan finished without finding it
        case connecting      // Opening our app's channel to the band
        case connected       // Ready, values are being read
        case failed(String)  // Something went wrong, with a message for the screen
    }

    enum TimeSyncStatus: Equatable {
        case idle
        case sending
        /// `at` is the real time of the sync. `wasTest` means the debug +5 min test.
        /// `timeZoneSkipped` means the zone packet wasn't sent because it isn't verified.
        case done(at: Date, wasTest: Bool, timeZoneSkipped: Bool)
        case failed(String)
    }

    private(set) var state: State = .starting
    private(set) var info: BandInfo?
    private(set) var batteryPercent: Int?
    private(set) var timeSync: TimeSyncStatus = .idle
    /// True while any packets are being written, so the screen can disable the send buttons.
    private(set) var isSending = false

    // @ObservationIgnored: SwiftUI doesn't need to watch these internal helpers.
    @ObservationIgnored private var central: CBCentralManager?
    /// We must keep a strong reference to the band, or iOS drops the connection.
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var scanTimeout: Task<Void, Never>?
    /// Packets still to send in the current send, in order.
    @ObservationIgnored private var pendingWrites: [Data] = []
    /// Which characteristic the current send writes to.
    @ObservationIgnored private var writeTarget: CBUUID?
    /// Called when the current send finishes: nil means success, otherwise an error message.
    @ObservationIgnored private var writeCompletion: ((String?) -> Void)?

    private static let scanDuration: Duration = .seconds(15)

    // MARK: - Called by the screen

    /// Starts Bluetooth. iOS asks for permission the first time this runs.
    func start() {
        if central == nil {
            // queue: nil means CoreBluetooth calls us back on the main thread,
            // which is where this class lives.
            central = CBCentralManager(delegate: self, queue: nil)
            // centralManagerDidUpdateState will be called next.
        } else {
            findBand()
        }
    }

    /// Closes our app's channel to the band. iOS keeps its own link,
    /// so notifications on the band keep working.
    func stop() {
        stopScan()
        if isSending {
            finishSend(error: "The send was interrupted.")
        }
        if let band = peripheral {
            peripheral = nil
            central?.cancelPeripheralConnection(band)
        }
    }

    /// Reads the values again, or searches again if we're not connected.
    func refresh() {
        if let band = peripheral, band.state == .connected, state == .connected {
            readValues(from: band)
        } else {
            findBand()
        }
    }

    /// Sends the iPhone's current time and time zone to the band (spec section 4).
    ///
    /// - Parameter offsetSeconds: added to the time sent. Always 0, except for the
    ///   debug-only test button, which sends +300 to prove the packet changes the band's clock.
    func syncTime(offsetSeconds: TimeInterval = 0) {
        guard !isSending else { return }

        let now = Date()
        var packets = [WenaPackets.setTime(now.addingTimeInterval(offsetSeconds))]
        let zonePacket = WenaPackets.setTimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT(for: now))
        if let zonePacket {
            packets.append(zonePacket)
        }

        let result = TimeSyncStatus.done(at: now, wasTest: offsetSeconds != 0, timeZoneSkipped: zonePacket == nil)
        timeSync = .sending
        send(packets, to: WenaGATT.controlCharacteristic) { [weak self] error in
            self?.timeSync = error.map { .failed($0) } ?? result
        }
    }

    /// Sends a weather packet (built by `WenaPackets.weather(days:)`) to characteristic 4002.
    /// `completion` gets nil on success, otherwise an error message.
    func sendWeather(_ packet: Data, completion: @escaping (String?) -> Void) {
        send([packet], to: WenaGATT.notificationCharacteristic, completion: completion)
    }

    // MARK: - Writing (the only code that writes to the band)

    /// Writes packets to one characteristic, one after another.
    private func send(_ packets: [Data], to uuid: CBUUID, completion: @escaping (String?) -> Void) {
        guard !isSending else {
            completion("Another send is still in progress.")
            return
        }
        guard state == .connected,
              let band = peripheral,
              let target = characteristic(uuid, in: band) else {
            completion("The band isn't ready. Tap Refresh and try again.")
            return
        }
        pendingWrites = packets
        writeTarget = uuid
        writeCompletion = completion
        isSending = true
        writeNextPacket(to: band, characteristic: target)
    }

    /// Sends the next waiting packet. With "write with response", the band confirms each one
    /// and `didWriteValueFor` calls this again, so packets go one at a time, in order.
    private func writeNextPacket(to band: CBPeripheral, characteristic: CBCharacteristic) {
        guard !pendingWrites.isEmpty else {
            finishSend(error: nil)
            return
        }
        let packet = pendingWrites.removeFirst()

        if characteristic.properties.contains(.write) {
            band.writeValue(packet, for: characteristic, type: .withResponse)
            // Continues in peripheral(_:didWriteValueFor:error:).
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            // No confirmation comes back, so carry straight on.
            band.writeValue(packet, for: characteristic, type: .withoutResponse)
            writeNextPacket(to: band, characteristic: characteristic)
        } else {
            finishSend(error: "That part of the band can't be written to.")
        }
    }

    private func finishSend(error: String?) {
        let completion = writeCompletion
        pendingWrites = []
        writeTarget = nil
        writeCompletion = nil
        isSending = false
        completion?(error)
    }

    private func characteristic(_ uuid: CBUUID, in band: CBPeripheral) -> CBCharacteristic? {
        band.services?
            .flatMap { $0.characteristics ?? [] }
            .first { $0.uuid == uuid }
    }

    // MARK: - Finding and connecting

    private func findBand() {
        guard let central, central.state == .poweredOn else { return }
        stop()
        info = nil
        batteryPercent = nil
        timeSync = .idle

        // Main path: ask iOS which already-connected devices offer the Wena service.
        let connected = central.retrieveConnectedPeripherals(withServices: [WenaGATT.commonService])
        if let band = connected.first {
            connect(to: band)
        } else {
            startScan()
        }
    }

    /// Fallback: listen for the band's advertisements for a short time.
    private func startScan() {
        state = .searching
        central?.scanForPeripherals(withServices: nil)

        scanTimeout?.cancel()
        scanTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.scanDuration)
            guard let self, !Task.isCancelled, self.state == .searching else { return }
            self.stopScan()
            self.state = .notFound
        }
    }

    private func stopScan() {
        scanTimeout?.cancel()
        scanTimeout = nil
        if central?.isScanning == true {
            central?.stopScan()
        }
    }

    private func connect(to band: CBPeripheral) {
        stopScan()
        peripheral = band
        band.delegate = self
        state = .connecting
        // This opens a channel for our app only. It does not pair or change the bond.
        central?.connect(band)
    }

    private func readValues(from band: CBPeripheral) {
        let wanted = [WenaGATT.infoCharacteristic, WenaGATT.stateCharacteristic]
        let characteristics = band.services?.flatMap { $0.characteristics ?? [] } ?? []
        for characteristic in characteristics where wanted.contains(characteristic.uuid) {
            band.readValue(for: characteristic)
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        if isSending {
            finishSend(error: "The send was interrupted.")
        }
    }
}

// MARK: - CBCentralManagerDelegate (Bluetooth status, scan results, connections)

extension BandConnection: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            findBand()
        case .poweredOff:
            stop()
            state = .poweredOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unsupported
        default:
            // .unknown or .resetting: iOS will call this again shortly.
            state = .starting
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard state == .searching, name == WenaGATT.advertisedName else { return }
        connect(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Only look for the services we need.
        peripheral.discoverServices([WenaGATT.commonService, WenaGATT.notificationService])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard peripheral == self.peripheral else { return }
        self.peripheral = nil
        fail("Couldn't connect to the band. \(error?.localizedDescription ?? "")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        // If we closed it ourselves in stop(), self.peripheral is already nil.
        guard peripheral == self.peripheral else { return }
        self.peripheral = nil
        fail("Lost the connection to the band.")
    }
}

// MARK: - CBPeripheralDelegate (services, characteristics and values from the band)

extension BandConnection: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            fail("Couldn't read the band's services. \(error.localizedDescription)")
            return
        }
        guard let common = peripheral.services?.first(where: { $0.uuid == WenaGATT.commonService }) else {
            fail("This device doesn't look like a Wena 3 band.")
            return
        }
        // Discovering 1514 and 4002 only looks them up. Nothing is written until a send button is tapped.
        peripheral.discoverCharacteristics(
            [WenaGATT.infoCharacteristic, WenaGATT.stateCharacteristic, WenaGATT.controlCharacteristic],
            for: common
        )
        if let notification = peripheral.services?.first(where: { $0.uuid == WenaGATT.notificationService }) {
            peripheral.discoverCharacteristics([WenaGATT.notificationCharacteristic], for: notification)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            fail("Couldn't read the band's characteristics. \(error.localizedDescription)")
            return
        }
        // The common service holds info and battery: once it's ready, we're connected.
        // (If 4002 isn't found, only the weather button fails, with a message.)
        guard service.uuid == WenaGATT.commonService else { return }
        state = .connected
        readValues(from: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            fail("Couldn't read from the band. \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }

        // Values are only shown on screen, never printed, so the serial stays out of logs.
        switch characteristic.uuid {
        case WenaGATT.infoCharacteristic:
            info = BandInfoParser.parseInfo(data)
            if info == nil { fail("The band sent device info in an unexpected format.") }
        case WenaGATT.stateCharacteristic:
            batteryPercent = BandInfoParser.parseBattery(data)
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard isSending, characteristic.uuid == writeTarget else { return }
        if let error {
            finishSend(error: "The band didn't accept the data. \(error.localizedDescription)")
            return
        }
        writeNextPacket(to: peripheral, characteristic: characteristic)
    }
}
