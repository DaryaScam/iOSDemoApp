//
//  QRDeviceRegisterView.swift
//  im-hybrid-demo
//

import SwiftUI


struct QRDeviceRegisterView: View {    
    @State private var qrresult = ""
    private var bleManager = BluetoothManager()

    var body: some View {
        VStack {
            Text("Register Devices")
                .font(.title)
            
            NavigationStack {
                List{
                    HStack {
                        Image(systemName: "network")
                        
                        Text("Web Session")
                        Spacer()
                        Text("Registered on Nov 25, 2024")
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "iphone")
                        Text("iPhone 12")
                        Spacer()
                        Text("Registered on Jan 1, 2023")
                            .font(.caption)
                    }

                    
                    NavigationLink(destination: {
                        ReadQRView(resultCode: $qrresult)
                            .onChange(of: qrresult) {
                                do {
                                    if qrresult.isEmpty {
                                        return
                                    }
                                    
                                    if qrresult.starts(with: "FIDO:/") {
                                        // Hybrid flow [TODO]
                                        let challengeinst = try DecodeCabLEChallenge($0)
                                        let advertisingData = try GenerateAdvertisingData(challengeinst)
    
                                        bleManager.startAdvertising(advertisingData)
                                    } else {
                                        
                                    }
//
//        
                                } catch {
                                    print("Error")
                                    print(error)
                                }
                            }
                    }) {
                        Text("Add new device")
                    }
                }
            }
            
            
        }
    }
}
