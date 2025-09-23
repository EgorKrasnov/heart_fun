import SwiftUI
import Combine
import CoreBluetooth
import Charts   // iOS 16+
import ActivityKit

// --- ViewModel ---
class HeartRateViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var heartRate: Int = 0
    @Published var connectionStatus: String = "🔍 Поиск..."
    @Published var deviceName: String? = nil
    @Published var heartRateHistory: [(time: Date, bpm: Int, rr: [Double])] = []
    @Published var discoveredDevices: [CBPeripheral] = []   // 👈 список найденных

    private var centralManager: CBCentralManager!
    private var heartRatePeripheral: CBPeripheral?
    
    private static var startedLive = false
    private static var liveActivity: Activity<HeartActivityAttributes>?
    
    let heartRateServiceCBUUID = CBUUID(string: "180D")
    let heartRateMeasurementCharacteristicCBUUID = CBUUID(string: "2A37")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Bluetooth lifecycle
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectionStatus = "🔍 Поиск устройств..."
            centralManager.scanForPeripherals(withServices: [heartRateServiceCBUUID], options: nil)
        } else {
            connectionStatus = "❌ Bluetooth выключен"
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        // Добавляем в список, если ещё нет
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }

    /// Подключение к выбранному устройству
    func connectTo(_ peripheral: CBPeripheral) {
        heartRatePeripheral = peripheral
        heartRatePeripheral?.delegate = self
        deviceName = peripheral.name ?? "Неизвестное устройство"
        connectionStatus = "⏳ Подключение..."
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = "✅ Подключено"
        peripheral.discoverServices([heartRateServiceCBUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "⚠️ Отключено"
        deviceName = nil
        heartRatePeripheral = nil
        centralManager.scanForPeripherals(withServices: [heartRateServiceCBUUID], options: nil)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([heartRateMeasurementCharacteristicCBUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == heartRateMeasurementCharacteristicCBUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if characteristic.uuid == heartRateMeasurementCharacteristicCBUUID,
           let data = characteristic.value {
            parseHeartRateData(data)
            startLiveActivityIfNeeded()
            updateLiveActivity()
        }
    }
    
    
    // MARK: - Парсинг HR
    private func parseHeartRateData(_ data: Data) {
        let reportData = [UInt8](data)
        let flag = reportData[0]
        let hrFormatUInt16 = (flag & 0x01) != 0
        
        var bpm: UInt16 = 0
        var index = 1
        
        if hrFormatUInt16 {
            bpm = UInt16(reportData[1]) | (UInt16(reportData[2]) << 8)
            index += 2
        } else {
            bpm = UInt16(reportData[1])
            index += 1
        }
        
        var rrIntervals: [Double] = []
        while index + 1 < reportData.count {
            let rr = UInt16(reportData[index]) | (UInt16(reportData[index+1]) << 8)
            let rrMs = Double(rr) / 1024.0 * 1000.0
            rrIntervals.append(rrMs)
            index += 2
        }
        
        DispatchQueue.main.async {
            let now = Date()
            self.heartRate = Int(bpm)
            self.heartRateHistory.append((time: now, bpm: Int(bpm), rr: rrIntervals))
            if self.heartRateHistory.count > 500 {
                self.heartRateHistory.removeFirst()
            }
        }
    }
    
    // MARK: - Сброс истории
    func clearHistory() {
        heartRateHistory.removeAll()
    }
    
    // MARK: - Экспорт истории
    func exportCSV() -> URL? {
        var csv = "timestamp,heart_rate,rr_intervals_ms\n"
        let formatter = ISO8601DateFormatter()
        
        for entry in heartRateHistory {
            let ts = formatter.string(from: entry.time)
            let rrJoined = entry.rr.map { String(format: "%.2f", $0) }.joined(separator: "|")
            csv += "\(ts),\(entry.bpm),\(rrJoined)\n"
        }
        
        do {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("heart_rate_history.csv")
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
    
    // MARK: - Live Activity (оставлено для фоновой работы, но без кнопок)
    func startLiveActivityIfNeeded() {
        guard !Self.startedLive else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let initial = HeartActivityAttributes.ContentState(heartRate: heartRate)
        let attrs   = HeartActivityAttributes(deviceName: deviceName ?? "Пульсометр")

        do {
            if #available(iOS 17.0, *) {
                let content = ActivityContent(state: initial, staleDate: nil)
                Self.liveActivity = try Activity.request(attributes: attrs, content: content)
            } else {
                Self.liveActivity = try Activity.request(attributes: attrs, contentState: initial)
            }
            Self.startedLive = true
        } catch {}
    }

    func updateLiveActivity() {
        let state = HeartActivityAttributes.ContentState(heartRate: heartRate)
        Task {
            if let act = Self.liveActivity {
                if #available(iOS 17.0, *) {
                    await act.update(ActivityContent(state: state, staleDate: nil))
                } else {
                    await act.update(using: state)
                }
            }
        }
    }
}


// --- Share Sheet ---
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


// --- SwiftUI View ---
struct ContentView: View {
    @StateObject private var viewModel = HeartRateViewModel()
    
    @State private var selectedDeviceID: UUID? = nil
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("❤️ Heart Rate Monitor")
                .font(.title2)
                .padding(.top)
            
            Text(viewModel.connectionStatus)
                .font(.headline)
                .foregroundColor(.blue)
            
            if !viewModel.discoveredDevices.isEmpty {
                Picker("Выберите устройство", selection: $selectedDeviceID) {
                    // (необязательно) плейсхолдер — на случай если не успели автоназначить
                    Text("Выберите устройство…").tag(nil as UUID?)

                    ForEach(viewModel.discoveredDevices, id: \.identifier) { device in
                        Text(device.name ?? device.identifier.uuidString)
                            .tag(device.identifier as UUID?)
                    }
                }
                .pickerStyle(.menu)
                // когда список обновился — выбрать первое, если ещё ничего не выбрано,
                // и «починить» выбор, если текущее устройство пропало
                .onChange(of: viewModel.discoveredDevices) { list in
                    if selectedDeviceID == nil, let first = list.first {
                        selectedDeviceID = first.identifier
                    } else if let id = selectedDeviceID,
                              !list.contains(where: { $0.identifier == id }) {
                        selectedDeviceID = list.first?.identifier
                    }
                }
                // при первом появлении Picker тоже выставим выбор
                .onAppear {
                    if selectedDeviceID == nil, let first = viewModel.discoveredDevices.first {
                        selectedDeviceID = first.identifier
                    }
                }

                Button("🔗 Подключиться") {
                    guard let id = selectedDeviceID,
                          let device = viewModel.discoveredDevices.first(where: { $0.identifier == id }) else { return }
                    viewModel.connectTo(device)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Поиск устройств...")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
             
             // --- остальная часть интерфейса ---
             Text("\(viewModel.heartRate) bpm")
                 .font(.system(size: 48, weight: .bold, design: .rounded))
                 .foregroundColor(.red)
                 .padding()
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(viewModel.heartRateHistory, id: \.time) { entry in
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value("HR", entry.bpm)
                        )
                        .foregroundStyle(.red)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.second().minute())
                        }
                    }
                }
                .frame(height: 200)
                .padding()
            } else {
                Text("График доступен только на iOS 16+")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
            
            // Кнопки действий
            HStack {
                Button("📤 Экспортировать в CSV") {
                    if let url = viewModel.exportCSV() {
                        exportURL = url
                        showShareSheet = true
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("🗑 Обнулить график") {
                    viewModel.clearHistory()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 10)
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showShareSheet) {
            if let exportURL = exportURL {
                ActivityView(activityItems: [exportURL])
            }
        }
    }
}
