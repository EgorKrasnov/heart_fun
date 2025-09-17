import SwiftUI
import CoreBluetooth

class HeartRateViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var heartRate: Int = 0
    
    private var centralManager: CBCentralManager!
    private var heartRatePeripheral: CBPeripheral?
    
    let heartRateServiceCBUUID = CBUUID(string: "180D")
    let heartRateMeasurementCharacteristicCBUUID = CBUUID(string: "2A37")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // Bluetooth state
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [heartRateServiceCBUUID], options: nil)
        }
    }
    
    // Device discovered
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        heartRatePeripheral = peripheral
        heartRatePeripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    // Connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([heartRateServiceCBUUID])
    }
    
    // Services
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([heartRateMeasurementCharacteristicCBUUID], for: service)
        }
    }
    
    // Characteristics
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == heartRateMeasurementCharacteristicCBUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // Data updates
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == heartRateMeasurementCharacteristicCBUUID,
           let data = characteristic.value {
            parseHeartRateData(data)
        }
    }
    
    private func parseHeartRateData(_ data: Data) {
        let reportData = [UInt8](data)
        let flag = reportData[0]
        let hrFormatUInt16 = (flag & 0x01) != 0
        var bpm: UInt16 = 0
        
        if hrFormatUInt16 {
            bpm = UInt16(reportData[1]) | (UInt16(reportData[2]) << 8)
        } else {
            bpm = UInt16(reportData[1])
        }
        
        DispatchQueue.main.async {
            self.heartRate = Int(bpm)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = HeartRateViewModel()
    
    var body: some View {
        VStack {
            Text("❤️ Heart Rate")
                .font(.title)
                .padding()
            
            Text("\(viewModel.heartRate) bpm")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.red)
        }
    }
}
