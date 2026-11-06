// Spike: can the Mac act as a Bluetooth hands-free unit for an Android phone on macOS 27?
// Usage: hfp "<paired phone name>"  then type: dial <number> | answer | end | audio | phone | quit
import Foundation
import IOBluetooth

final class Spike: NSObject, IOBluetoothHandsFreeDeviceDelegate {
    var hf: IOBluetoothHandsFreeDevice!

    init(device: IOBluetoothDevice) {
        super.init()
        hf = IOBluetoothHandsFreeDevice(device: device, delegate: self)
    }

    func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) { log("connected status=\(status!)") }
    func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) { log("disconnected status=\(status!)") }
    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) { log("audio (SCO) opened status=\(status!)") }
    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) { log("audio (SCO) closed status=\(status!)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isServiceAvailable v: NSNumber!) { log("service=\(v!)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isCallActive v: NSNumber!) { log("callActive=\(v!)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, callSetupMode v: NSNumber!) { log("callSetup=\(v!)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, incomingCallFrom number: String!) { log("incoming call from \(number ?? "?")") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, ringAttempt v: NSNumber!) { log("ring \(v!)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, currentCall call: [AnyHashable: Any]!) { log("current call \(call ?? [:])") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, signalStrength v: NSNumber!) { log("signal=\(v!)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, batteryCharge v: NSNumber!) { log("battery=\(v!)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, unhandledResultCode code: String!) { log("unhandled \(code ?? "")") }
}

func log(_ s: String) { print("[\(Date().formatted(date: .omitted, time: .standard))] \(s)") }

let name = CommandLine.arguments.dropFirst().first ?? "S24"
let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
guard let phone = paired.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains(name) }) else {
    print("No paired device matching \"\(name)\". Paired: \(paired.map { $0.name ?? "?" })")
    exit(1)
}
log("found \(phone.name ?? "?") \(phone.addressString ?? "")")
let spike = Spike(device: phone)
spike.hf.connect()

// Read commands off the main thread; IOBluetooth delivers callbacks on the main run loop.
Thread.detachNewThread {
    while let line = readLine() {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        DispatchQueue.main.async {
            switch parts.first {
            case "dial": spike.hf.dialNumber(parts.count > 1 ? parts[1] : "")
            case "answer": spike.hf.acceptCall()
            case "end": spike.hf.endCall()
            case "audio": spike.hf.transferAudioToComputer()
            case "phone": spike.hf.transferAudioToPhone()
            case "quit": spike.hf.disconnect(); exit(0)
            default: print("commands: dial <number> | answer | end | audio | phone | quit")
            }
        }
    }
}
RunLoop.main.run()
