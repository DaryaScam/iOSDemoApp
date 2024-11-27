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
    
    func startAdvertising(_ serviceData: [UInt8]) {
        guard peripheralManager.state == .poweredOn else {
            print("Peripheral manager is not powered on.")
            return
        }
        
        let serviceUuid = CBUUID(string: "0000fff9-0000-1000-8000-00805f9b34fb")
        let advertisementData = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUuid],
            CBAdvertisementDataLocalNameKey: "MyPeripheral",
            CBAdvertisementDataServiceDataKey: [
                serviceUuid:serviceData
            ]

        ] as [String : Any]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
    }
    
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
    }
}
