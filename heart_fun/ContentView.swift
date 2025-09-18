//
//  ContentView.swift
//  heart_fun
//
//  Created by Egor on 18.09.2025.
//


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
