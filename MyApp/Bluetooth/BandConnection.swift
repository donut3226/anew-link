import CoreBluetooth
import Observation

/// Finds the Wena 3 band and reads its info and battery. Read-only:
/// it never writes to the band, never subscribes to updates, and never pairs or unpairs.
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

    private(set) var state: State = .starting
    private(set) var info: BandInfo?
    private(set) var batteryPercent: Int?

    // @ObservationIgnored: SwiftUI doesn't need to watch these internal helpers.
    @ObservationIgnored private var central: CBCentralManager?
    /// We must keep a strong reference to the band, or iOS drops the connection.
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var scanTimeout: Task<Void, Never>?

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

    // MARK: - Finding and connecting

    private func findBand() {
        guard let central, central.state == .poweredOn else { return }
        stop()
        info = nil
        batteryPercent = nil

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
        // Only look for the one service we need.
        peripheral.discoverServices([WenaGATT.commonService])
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
        guard let service = peripheral.services?.first(where: { $0.uuid == WenaGATT.commonService }) else {
            fail("This device doesn't look like a Wena 3 band.")
            return
        }
        peripheral.discoverCharacteristics(
            [WenaGATT.infoCharacteristic, WenaGATT.stateCharacteristic],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            fail("Couldn't read the band's characteristics. \(error.localizedDescription)")
            return
        }
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
}
