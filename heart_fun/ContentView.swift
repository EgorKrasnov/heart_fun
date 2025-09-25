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
            if self.heartRateHistory.count > 10000 {
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
    
    func calculateZonePercents(green: Int, yellow: Int, red: Int) -> (green: Double, yellow: Double, red: Double) {
        guard heartRateHistory.count > 1 else { return (0, 0, 0) }
        
        var greenTime: TimeInterval = 0
        var yellowTime: TimeInterval = 0
        var redTime: TimeInterval = 0
        
        for i in 1..<heartRateHistory.count {
            let prev = heartRateHistory[i-1]
            let curr = heartRateHistory[i]
            
            // интервал времени между точками
            let dt = curr.time.timeIntervalSince(prev.time)
            let bpm = prev.bpm
            
            if bpm < green {
                // ниже зелёной зоны не считаем (можно добавить как "синюю" зону при желании)
                continue
            } else if bpm < yellow {
                greenTime += dt
            } else if bpm < red {
                yellowTime += dt
            } else {
                redTime += dt
            }
        }
        
        let total = greenTime + yellowTime + redTime
        guard total > 0 else { return (0, 0, 0) }
        
        return (greenTime/total * 100,
                yellowTime/total * 100,
                redTime/total * 100)
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
    @State private var selectedEntry: (time: Date, bpm: Int)? = nil   // 👈 подсвеченная точка
    
    @State private var greenZone: Int = 100
    @State private var yellowZone: Int = 150
    @State private var redZone: Int = 180
    @State private var zoneError: String? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                // статус
                Text(viewModel.connectionStatus)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                // выбор устройства
                if !viewModel.discoveredDevices.isEmpty {
                    Picker("Устройство", selection: $selectedDeviceID) {
                        ForEach(viewModel.discoveredDevices, id: \.identifier) { device in
                            Text(device.name ?? device.identifier.uuidString)
                                .tag(Optional(device.identifier))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.discoveredDevices) { list in
                        // если ничего не выбрано – выбрать первое
                        if selectedDeviceID == nil, let first = list.first {
                            selectedDeviceID = first.identifier
                        }
                        // если выбранное устройство исчезло – выбрать новое первое
                        else if let id = selectedDeviceID,
                                !list.contains(where: { $0.identifier == id }),
                                let first = list.first {
                            selectedDeviceID = first.identifier
                        }
                    }
                    .onAppear {
                        if selectedDeviceID == nil, let first = viewModel.discoveredDevices.first {
                            selectedDeviceID = first.identifier
                        }
                    }

                    Button("🔗 Pair") {
                        guard let id = selectedDeviceID,
                              let device = viewModel.discoveredDevices.first(where: { $0.identifier == id }) else { return }
                        viewModel.connectTo(device)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Поиск устройств…")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            
            // Кнопки действий
            HStack {
                Button("📤  Share") {
                    if let url = viewModel.exportCSV() {
                        exportURL = url
                        showShareSheet = true
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("🗑 Clear") {
                    viewModel.clearHistory()
                }
                .buttonStyle(.bordered)
            }
//            .padding(.top, 10)
            
            VStack {
                HStack {
                    VStack {
                        Text("Зелёная")
                        Picker("Зелёная", selection: $greenZone) {
                            ForEach(60..<200) { bpm in
                                Text("\(bpm)").tag(bpm)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 80)
                    }
                    
                    VStack {
                        Text("Жёлтая")
                        Picker("Жёлтая", selection: $yellowZone) {
                            ForEach(60..<200) { bpm in
                                Text("\(bpm)").tag(bpm)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 80)
                    }
                    
                    VStack {
                        Text("Красная")
                        Picker("Красная", selection: $redZone) {
                            ForEach(60..<220) { bpm in
                                Text("\(bpm)").tag(bpm)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 80)
                    }
                }
                
                if let error = zoneError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            .onChange(of: [greenZone, yellowZone, redZone]) { _ in
                if !(greenZone < yellowZone && yellowZone < redZone) {
                    zoneError = "Значения должны быть по возрастанию"
                } else {
                    zoneError = nil
                }
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
                    
                    // подсветка зоны — если порядок корректный
                    if zoneError == nil {
                        RectangleMark(
                            xStart: .value("Start", viewModel.heartRateHistory.first?.time ?? Date()),
                            xEnd: .value("End", viewModel.heartRateHistory.last?.time ?? Date()),
                            yStart: .value("Low", greenZone),
                            yEnd: .value("High", yellowZone)
                        )
                        .foregroundStyle(Color.green.opacity(0.2))
                        
                        RectangleMark(
                            xStart: .value("Start", viewModel.heartRateHistory.first?.time ?? Date()),
                            xEnd: .value("End", viewModel.heartRateHistory.last?.time ?? Date()),
                            yStart: .value("Low", yellowZone),
                            yEnd: .value("High", redZone)
                        )
                        .foregroundStyle(Color.yellow.opacity(0.2))
                        
                        RectangleMark(
                            xStart: .value("Start", viewModel.heartRateHistory.first?.time ?? Date()),
                            xEnd: .value("End", viewModel.heartRateHistory.last?.time ?? Date()),
                            yStart: .value("Low", redZone),
                            yEnd: .value("High", 220) // верхний предел
                        )
                        .foregroundStyle(Color.red.opacity(0.2))
                    }
                    
                    // 👇 Подсветка выбранной точки
                    if let entry = selectedEntry {
                        RuleMark(x: .value("Time", entry.time))
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        
                        PointMark(
                            x: .value("Time", entry.time),
                            y: .value("HR", entry.bpm)
                        )
                        .foregroundStyle(.blue)
                        .annotation(position: .top, alignment: .center) {
                            Text("\(entry.bpm) bpm")
                                .font(.caption)
                                .padding(4)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(5)
                        }
                    }
                }
                .chartYScale(domain: 0...(redZone + 40))
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
                // 👇 overlay для жеста
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if let date: Date = proxy.value(atX: value.location.x) {
                                            if let nearest = viewModel.heartRateHistory.min(by: {
                                                abs($0.time.timeIntervalSince(date)) <
                                                abs($1.time.timeIntervalSince(date))
                                            }) {
                                                selectedEntry = (nearest.time, nearest.bpm)
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedEntry = nil
                                    }
                            )
                    }
                }
            } else {
                Text("График доступен только на iOS 16+")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
            
            let percents = viewModel.calculateZonePercents(
                green: greenZone,
                yellow: yellowZone,
                red: redZone
            )

            HStack {
                VStack {
                    Text("I")
                        .foregroundColor(.green)
                    Text(String(format: "%.1f %%", percents.green))
                        .font(.headline)
                }
                Spacer()
                VStack {
                    Text("II")
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f %%", percents.yellow))
                        .font(.headline)
                }
                Spacer()
                VStack {
                    Text("III")
                        .foregroundColor(.red)
                    Text(String(format: "%.1f %%", percents.red))
                        .font(.headline)
                }
            }
            .padding(.horizontal)

            

            
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
