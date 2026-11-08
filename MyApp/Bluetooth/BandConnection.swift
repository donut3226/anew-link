import CoreBluetooth
import Observation

/// Finds the Wena 3 band, reads its info and battery, sends it time and weather, and syncs activity.
/// Every packet write goes through `send(_:to:completion:)`, and only happens when the user taps a button.
/// The one other write is the 3002 subscription during `syncActivity`, which is switched off again
/// when the sync ends. It never pairs or unpairs.
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

    /// What came back from an activity sync.
    struct ActivitySyncResult: Equatable {
        let summary: ActivitySummary
        /// Every sample received, so they can be saved to Apple Health afterwards.
        let samples: [ActivitySample]
        let syncedAt: Date
        let packetCount: Int
        let badCRCCount: Int
        /// False if the sync ended because the band went quiet rather than sending "finish".
        let receivedFinish: Bool
    }

    enum ActivityStatus: Equatable {
        case idle
        case subscribing
        case receiving(packets: Int)
        case done(ActivitySyncResult)
        case failed(String)

        var inProgress: Bool {
            switch self {
            case .subscribing, .receiving: true
            default: false
            }
        }
    }

    private(set) var state: State = .starting
    private(set) var info: BandInfo?
    private(set) var batteryPercent: Int?
    private(set) var timeSync: TimeSyncStatus = .idle
    private(set) var activity: ActivityStatus = .idle
    /// True while any packets are being written, so the screen can disable the send buttons.
    private(set) var isSending = false
    /// The raw activity packets from the last sync, kept in memory only, for the debug copy button.
    @ObservationIgnored private(set) var rawActivityPackets: [Data] = []

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
    /// Puts the activity stream back together while a sync is running.
    @ObservationIgnored private var assembler: ActivityStreamAssembler?
    @ObservationIgnored private var activityStartedAt = Date()
    @ObservationIgnored private var activityTimeout: Task<Void, Never>?

    private static let scanDuration: Duration = .seconds(15)
    /// How long the band can go quiet before we treat the activity sync as over.
    private static let activitySilenceLimit: Duration = .seconds(15)

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
        if activity.inProgress {
            endActivity(.failed("The activity sync was interrupted."))
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

    // MARK: - Activity sync (spec section 7)

    /// Gets the last 24 hours of steps and heart rate from the band.
    ///
    /// Steps: subscribe to 3002 (so the band can stream to us), send requests A and B and start,
    /// collect the stream, then unsubscribe. Subscribing is the one write that doesn't go through
    /// `send`, because it's a standard Bluetooth switch rather than a Wena packet.
    func syncActivity() {
        guard !isSending, !activity.inProgress else { return }
        guard state == .connected,
              let band = peripheral,
              let stream = characteristic(WenaGATT.activityCharacteristic, in: band) else {
            activity = .failed("The band isn't ready. Tap Refresh and try again.")
            return
        }
        assembler = ActivityStreamAssembler()
        rawActivityPackets = []
        activityStartedAt = Date()
        activity = .subscribing
        band.setNotifyValue(true, for: stream)
        // Continues in peripheral(_:didUpdateNotificationStateFor:error:).
        restartActivityTimeout()
    }

    /// Called once the band has confirmed the subscription: send the request packets.
    private func requestActivity() {
        let now = WenaPackets.wenaTimestamp(for: activityStartedAt)
        let dayAgo = WenaPackets.wenaTimestamp(for: activityStartedAt.addingTimeInterval(-24 * 60 * 60))
        let packets = [
            // Steps and heart rate from 24 hours ago. Everything else "newer than now", which is nothing.
            WenaPackets.activityRequestA(steps: dayAgo, heartRate: dayAgo, behaviour: now, vo2: now),
            WenaPackets.activityRequestB(stress: now, bodyEnergy: now, calories: now, events: now),
            WenaPackets.activityStart,
        ]
        activity = .receiving(packets: 0)
        send(packets, to: WenaGATT.activityCharacteristic) { [weak self] error in
            if let error {
                self?.endActivity(.failed(error))
            }
        }
    }

    /// Handles one notification from 3002.
    private func handleActivityPacket(_ data: Data) {
        guard activity.inProgress, var assembler else { return }
        rawActivityPackets.append(data)
        let event = assembler.feed(data)
        self.assembler = assembler

        switch event {
        case .gap:
            endActivity(.failed("Some data went missing during the transfer. Tap Sync activity to try again."))
        case .finished:
            endActivity(.done(result(from: assembler, receivedFinish: true)))
        case .accepted, .ignored, .badCRC:
            activity = .receiving(packets: assembler.packetCount)
            restartActivityTimeout()
        }
    }

    /// If the band goes quiet for too long, finish with what we have (or fail if we got nothing).
    private func restartActivityTimeout() {
        activityTimeout?.cancel()
        activityTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.activitySilenceLimit)
            guard let self, !Task.isCancelled, self.activity.inProgress else { return }
            if let assembler = self.assembler, !assembler.samples.isEmpty {
                self.endActivity(.done(self.result(from: assembler, receivedFinish: false)))
            } else {
                self.endActivity(.failed("The band didn't send any activity data."))
            }
        }
    }

    private func result(from assembler: ActivityStreamAssembler, receivedFinish: Bool) -> ActivitySyncResult {
        ActivitySyncResult(summary: ActivitySummary(samples: assembler.samples, now: activityStartedAt),
                           samples: assembler.samples,
                           syncedAt: activityStartedAt,
                           packetCount: assembler.packetCount,
                           badCRCCount: assembler.badCRCCount,
                           receivedFinish: receivedFinish)
    }

    /// Ends the activity sync and switches the band's "send me updates" setting back off.
    private func endActivity(_ status: ActivityStatus) {
        activityTimeout?.cancel()
        activityTimeout = nil
        assembler = nil
        if let band = peripheral,
           let stream = characteristic(WenaGATT.activityCharacteristic, in: band),
           stream.isNotifying {
            band.setNotifyValue(false, for: stream)
        }
        activity = status
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
        activity = .idle

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
        if activity.inProgress {
            endActivity(.failed("The activity sync was interrupted."))
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
        peripheral.discoverServices([WenaGATT.commonService, WenaGATT.notificationService, WenaGATT.activityService])
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
        if let activityService = peripheral.services?.first(where: { $0.uuid == WenaGATT.activityService }) {
            peripheral.discoverCharacteristics([WenaGATT.activityCharacteristic], for: activityService)
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
        // Activity stream packets are handled separately, and never logged.
        if characteristic.uuid == WenaGATT.activityCharacteristic {
            if let error {
                if activity.inProgress {
                    endActivity(.failed("Couldn't receive activity data. \(error.localizedDescription)"))
                }
            } else if let data = characteristic.value {
                handleActivityPacket(data)
            }
            return
        }

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
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == WenaGATT.activityCharacteristic, activity == .subscribing else { return }
        if let error {
            endActivity(.failed("The band didn't allow the activity subscription. \(error.localizedDescription)"))
        } else if characteristic.isNotifying {
            requestActivity()
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
