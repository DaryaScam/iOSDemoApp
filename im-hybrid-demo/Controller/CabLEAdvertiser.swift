//
//  CabLEAdvertiser.swift
//  im-hybrid-demo
//

import SwiftUI
import CoreBluetooth
import AVKit

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, ObservableObject {
    @Published var isBluetoothEnabled = false
    @Published var discoveredPeripherals = [CBPeripheral]()
    @Published var isAdvertising = false
    
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    // Central Manager (Scanning)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            isBluetoothEnabled = true
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            isBluetoothEnabled = false
            centralManager.stopScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(peripheral) {
            discoveredPeripherals.append(peripheral)
        }
    }
    
    // Peripheral Manager (Advertising)
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print("Peripheral Manager is powered on and ready to advertise.")
        } else {
            print("Peripheral Manager is not available.")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("Failed to start advertising: \(error.localizedDescription)")
        } else {
            print("Successfully started advertising.")
        }
    }
    
    func startAdvertising(_ serviceData: [UInt8]) {
        guard peripheralManager.state == .poweredOn else {
            print("Peripheral manager is not powered on. State: \(peripheralManager.state)")
            return
        }
                
        // Hack to advertise iOS service data
        let iOSServiceDataHack = Data([0xf1, 0xd0, 0x00]) + Data(serviceData)
        let restOfData = iOSServiceDataHack.dropFirst(16)
    

        // Create CBUUIDs from the parts
        let sUuid1 = CBUUID(data: iOSServiceDataHack.prefix(16))
        let sUuid2 = CBUUID(data: restOfData.prefix(4))
        let sUuid3 = CBUUID(data: restOfData.dropFirst(4))

        let advertisementData = [
            CBAdvertisementDataLocalNameKey: "Hybrid-ish Device",
            CBAdvertisementDataServiceUUIDsKey: [sUuid1, sUuid2, sUuid3]
        ] as [String : Any]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
    }
    
    func stopAdvertising() {
        peripheralManager.removeAllServices()
        peripheralManager.stopAdvertising()
        isAdvertising = false
    }
}
