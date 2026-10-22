import AmmuttaCore
@preconcurrency import CoreBluetooth
import Foundation
import Observation

enum HeartRateStatus: Equatable {
    /// No sensor wanted right now.
    case idle
    /// Looking for the remembered sensor, or waiting for it to come back in range.
    case searching
    case connected
    case bluetoothOff
    case denied
    case unsupported
}

struct DiscoveredSensor: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// 0 (weak) to 1 (strong).
    let signal: Double
}

/// A Bluetooth heart-rate sensor: the one the user picked is remembered and kept connected
/// while a workout is active or the sensor screen is open.
@MainActor
protocol HeartRateSource: AnyObject {
    var status: HeartRateStatus { get }
    /// The latest valid reading, nil when there is none (not connected, or no skin contact).
    var bpm: Int? { get }
    var sensorID: UUID? { get }
    var sensorName: String? { get }
    /// Sensors seen while scanning.
    var discovered: [DiscoveredSensor] { get }
    /// Receives every valid reading.
    var onReading: ((Int, Date) -> Void)? { get set }

    /// Scans for nearby sensors. Asks for Bluetooth permission the first time.
    func startScanning()
    func stopScanning()
    func connect(_ sensor: DiscoveredSensor)
    func forget()
    func setWorkoutActive(_ active: Bool)
}

/// Standard Bluetooth Heart Rate Service only (`0x180D` / `0x2A37`). Any strap, armband or
/// watch that shares heart rate works, Google Fitbit Air included, with no vendor-specific code.
///
/// CoreBluetooth calls the delegate on the main queue, so the callbacks hop onto the main actor.
@Observable
final class BluetoothHeartRateSource: NSObject, HeartRateSource {
    private static let service = CBUUID(string: "180D")
    private static let measurement = CBUUID(string: "2A37")
    private enum Keys {
        static let sensorID = "heartRateSensorID"
        static let sensorName = "heartRateSensorName"
    }

    private(set) var bpm: Int?
    private(set) var sensorID: UUID?
    private(set) var sensorName: String?
    private(set) var discovered: [DiscoveredSensor] = []
    private var bluetoothState: CBManagerState = .unknown
    private var connected = false
    private var scanning = false
    private var workoutActive = false

    @ObservationIgnored var onReading: ((Int, Date) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var found: [UUID: CBPeripheral] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sensorID = defaults.string(forKey: Keys.sensorID).flatMap(UUID.init(uuidString:))
        sensorName = defaults.string(forKey: Keys.sensorName)
        super.init()
    }

    var status: HeartRateStatus {
        switch bluetoothState {
        case .poweredOff: .bluetoothOff
        case .unauthorized: .denied
        case .unsupported: .unsupported
        default:
            if connected { .connected } else if wantsSensor { .searching } else { .idle }
        }
    }

    private var wantsSensor: Bool { sensorID != nil && (scanning || workoutActive) }

    func startScanning() {
        scanning = true
        update()
    }

    func stopScanning() {
        scanning = false
        discovered = []
        found = [:]
        update()
    }

    func connect(_ sensor: DiscoveredSensor) {
        disconnect()
        sensorID = sensor.id
        sensorName = sensor.name
        defaults.set(sensor.id.uuidString, forKey: Keys.sensorID)
        defaults.set(sensor.name, forKey: Keys.sensorName)
        peripheral = found[sensor.id]
        update()
    }

    func forget() {
        disconnect()
        sensorID = nil
        sensorName = nil
        defaults.removeObject(forKey: Keys.sensorID)
        defaults.removeObject(forKey: Keys.sensorName)
        update()
    }

    func setWorkoutActive(_ active: Bool) {
        workoutActive = active
        update()
    }

    /// Brings Bluetooth in line with what is wanted: scanning while the sensor screen is open,
    /// and a connection to the remembered sensor while it is wanted.
    private func update() {
        if central == nil {
            // Creating the manager asks for permission, so only do it when Bluetooth is needed.
            guard scanning || wantsSensor else { return }
            central = CBCentralManager(delegate: self, queue: .main)
            return // Continues in centralManagerDidUpdateState.
        }
        guard let central, central.state == .poweredOn else { return }

        if scanning, !central.isScanning {
            central.scanForPeripherals(withServices: [Self.service])
        } else if !scanning, central.isScanning {
            central.stopScan()
        }

        if wantsSensor, let sensorID {
            if peripheral == nil {
                peripheral = central.retrievePeripherals(withIdentifiers: [sensorID]).first
            }
            if let peripheral, peripheral.state == .disconnected {
                peripheral.delegate = self
                // A pending connection never times out: iOS connects when the sensor is in range.
                central.connect(peripheral)
            }
        } else {
            disconnect()
        }
    }

    private func disconnect() {
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        connected = false
        bpm = nil
    }

    // MARK: Events

    fileprivate func handleState(_ state: CBManagerState) {
        bluetoothState = state
        if state != .poweredOn {
            peripheral = nil
            connected = false
            bpm = nil
        }
        update()
    }

    fileprivate func handleDiscovery(_ peripheral: CBPeripheral, name: String?, rssi: Int) {
        let id = peripheral.identifier
        found[id] = peripheral
        // RSSI 127 means unknown; -100 dBm or less is the weakest usable signal.
        let signal = rssi == 127 ? 0 : min(max(Double(rssi + 100) / 60, 0), 1)
        let sensor = DiscoveredSensor(id: id, name: name ?? peripheral.name ?? L10n.sensorUnnamed, signal: signal)
        if let index = discovered.firstIndex(where: { $0.id == id }) {
            discovered[index] = sensor
        } else {
            discovered.append(sensor)
        }
    }

    fileprivate func handleConnection(_ peripheral: CBPeripheral) {
        guard peripheral.identifier == sensorID else { return }
        connected = true
        if let name = peripheral.name, name != sensorName {
            sensorName = name
            defaults.set(name, forKey: Keys.sensorName)
        }
        peripheral.discoverServices([Self.service])
    }

    fileprivate func handleDisconnection(_ peripheral: CBPeripheral) {
        guard peripheral.identifier == sensorID else { return }
        connected = false
        bpm = nil
        // Reconnect quietly when it comes back in range.
        if wantsSensor, central?.state == .poweredOn {
            central?.connect(peripheral)
        }
    }

    fileprivate func handleServices(_ peripheral: CBPeripheral) {
        for service in peripheral.services ?? [] where service.uuid == Self.service {
            peripheral.discoverCharacteristics([Self.measurement], for: service)
        }
    }

    fileprivate func handleCharacteristics(_ peripheral: CBPeripheral, in service: CBService) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.measurement {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    fileprivate func handleMeasurement(_ bytes: [UInt8]) {
        bpm = HeartRateMeasurement.bpm(from: bytes)
        if let reading = bpm {
            onReading?(reading, .now)
        }
    }
}

extension BluetoothHeartRateSource: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated { handleState(state) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue
        MainActor.assumeIsolated { handleDiscovery(peripheral, name: name, rssi: rssi) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { handleConnection(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated { handleDisconnection(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated { handleDisconnection(peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        MainActor.assumeIsolated { handleServices(peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        MainActor.assumeIsolated { handleCharacteristics(peripheral, in: service) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == CBUUID(string: "2A37"), let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        MainActor.assumeIsolated { handleMeasurement(bytes) }
    }
}

/// A stand-in sensor for tests and UI tests: no Bluetooth, readings only when asked for.
@Observable
final class FakeHeartRateSource: HeartRateSource {
    private(set) var bpm: Int?
    private(set) var sensorID: UUID?
    private(set) var sensorName: String?
    private(set) var discovered: [DiscoveredSensor] = []
    private(set) var workoutActive = false
    private(set) var scanning = false
    /// Sent once when a workout starts, so UI tests show a reading.
    @ObservationIgnored private let readingOnStart: Int?
    @ObservationIgnored var onReading: ((Int, Date) -> Void)?

    init(sensorName: String? = nil, readingOnStart: Int? = nil) {
        self.sensorName = sensorName
        sensorID = sensorName == nil ? nil : UUID()
        self.readingOnStart = readingOnStart
        if let sensorName {
            discovered = [DiscoveredSensor(id: UUID(), name: sensorName + " 2", signal: 0.6)]
        }
    }

    var status: HeartRateStatus {
        if sensorID == nil { return .idle }
        return bpm == nil ? (workoutActive || scanning ? .searching : .idle) : .connected
    }

    func startScanning() { scanning = true }
    func stopScanning() { scanning = false }

    func connect(_ sensor: DiscoveredSensor) {
        sensorID = sensor.id
        sensorName = sensor.name
    }

    func forget() {
        sensorID = nil
        sensorName = nil
        bpm = nil
    }

    func setWorkoutActive(_ active: Bool) {
        workoutActive = active
        if active, let readingOnStart {
            emit(readingOnStart, at: .now)
        } else if !active {
            bpm = nil
        }
    }

    func emit(_ bpm: Int, at date: Date) {
        self.bpm = bpm
        onReading?(bpm, date)
    }
}
