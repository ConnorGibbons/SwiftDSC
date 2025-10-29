//
//  main.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/19/25.
//
import Foundation
import Accelerate
import RTLSDRWrapper
import SignalTools
import TCPUtils
import Network
import Darwin

// Constants
let MIN_BUFFER_LEN = 96_000
let DEFAULT_INPUT_SAMPLE_RATE = 288_000
let DEFAULT_INTERNAL_SAMPLE_RATE = 12000

class RuntimeState {
    // Args
    var debugConfig: DebugConfiguration = DebugConfiguration(debugOutput: .none)
    var offlineSamples: [DSPComplex]? = nil
    var offlineCenterFrequency: Int? = nil
    var offlineSampleRate: Int? = nil
    var outputValidCallsToConsole: Bool = false
    var useDigitalAGC: Bool = false
    var bandwidth: Int = 72000
    var sdrDeviceIndex: Int = 0
    var sdrHost: String? = nil
    var sdrPort: UInt16? = nil
    var maxBitFlips: Int = 0
    
    // State
    var outputServer: TCPServer?           // Outputs NMEA to listeners
    var relayServer: RTLTCPRelayServer?    // Retransmits rtl_tcp stream (read-only) so visualizers can be used.
    var firstSampleRecieved: Bool = false
    var outputFile: FileHandle?
    var validCalls: [DSCCall] = []
    // var invalidCalls: [DSCCall] = []
    var shouldExit: Bool = false
}

public struct DebugConfiguration {
    let debugOutput: DebugLevel
}

public enum DebugLevel: Int, Comparable {
    case extensive = 0
    case limited = 1
    case errorsOnly = 2
    case none = 3
    
    public static func < (lhs: DebugLevel, rhs: DebugLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum LaunchArgument: String {
    case debugOutput = "-d"
    case offlineDecodingTest = "-ot"
    case outputValidCallsToConsole = "-n"
    case useDigitalAGC = "-agc"
    case tcpServer = "-tcp"
    case bandwidth = "-b"
    case deviceIndex = "-di"
    case saveFile = "-s"
    case help = "-h"
    case relayServer = "-rs"
}

func showHelp() {
    print("SwiftDSC - DSC Receiver")
    print("Usage: SwiftDSC [options]")
    print("")
    print("Options:")
    print("  -h              Show this help message")
    print("  -d <level>      Enable debug output. Options are: 'extensive', 'limited', 'errorsonly' and 'none'. 'none' is the default if -d isn't provided.")
    print("  -ot <file path, center frequency, sample rate> Perform offline decoding test using specified file as input, must be 16-bit WAV where IQ samples are interleaved")
    print("  -n              Print valid DSC calls to console (human readable)")
    print("  -agc            Enable digital AGC")
    print("  -tcp <port>     Start TCP server on specified port (1-65535). Received calls will be output as NMEA 0183 via the server.")
    print("  -b <bandwidth>  Set tuner bandwidth in Hz (1000-200000)")
    print("  -di <index>     Set SDR device index or host:port for TCP connection -- an rtl_tcp server must be running on the specified host if using TCP.")
    print("  -s <file path>  Save decoded calls to file")
    print("  -rs <port>      Relays rtl_tcp input to specified port (1-65535). Only use this if using SDR over rtl_tcp.")
    print("")
    print("Examples:")
    print("  SwiftDSC -d -n   Run with debug output and console printing")
    print("  SwiftDSC -tcp 50050            Start TCP server on port 50050")
    print("  SwiftDSC -di 192.168.1.1:1234  Connect to remote SDR via TCP")
}

func mapCLIArgsToVariables() -> RuntimeState {
    let args = CommandLine.arguments
    let runtimeState = RuntimeState()
    let argCount = args.count
    var currArgIndex = 1
    while currArgIndex < argCount {
        var argument = LaunchArgument(rawValue: args[currArgIndex])
        guard argument != nil else {
            print("Unrecognized argument: \(args[currArgIndex])")
            currArgIndex += 1
            continue
        }
        argument = argument!
        let nextArgument: String? = (currArgIndex + 1) < argCount ? args[currArgIndex + 1] : nil
        currArgIndex += 1
        
        switch argument {
        case .debugOutput:
            currArgIndex += 1
            var providedDebugLevel: DebugLevel = .none
            switch nextArgument?.lowercased() {
            case "extensive": providedDebugLevel = .extensive
            case "limited": providedDebugLevel = .limited
            case "errorsonly": providedDebugLevel = .errorsOnly
            case "none": providedDebugLevel = .none
            default: print("Invalid or no debug level provided with -d. Options are: 'extensive', 'limited', 'errorsonly' and 'none'."); exit(64)
            }
            runtimeState.debugConfig = DebugConfiguration(debugOutput: providedDebugLevel)
            
        case .offlineDecodingTest:
            currArgIndex += 1
            guard FileManager.default.fileExists(atPath: nextArgument ?? "failPlaceholder") else {
                print("File (\(nextArgument ?? "[none]")) provided for offline testing doesn't exist of is not accessible.")
                exit(64)
            }
            do {
                let samples = try readIQFromWAV16Bit(filePath: nextArgument ?? "failPlaceholder")
                guard let centerFrequency = Int(args[currArgIndex]) else {
                    print("Center frequency provided for offline test (\(args[currArgIndex])) was not parsable to an integer.")
                    exit(64)
                }
                currArgIndex = currArgIndex + 1
                guard currArgIndex < argCount else {
                    print("Offline Decoding Test did not recieve enough arguments (file path, center frequency <Int>, sample rate <Int> required.")
                    exit(64)
                }
                guard let sampleRate = Int(args[currArgIndex]) else {
                    print("Sample rate provided for offline test (\(args[currArgIndex])) was not parsable to an integer.")
                    exit(64)
                }
                currArgIndex = currArgIndex + 1
                runtimeState.offlineSampleRate = sampleRate
                runtimeState.offlineCenterFrequency = centerFrequency
                runtimeState.offlineSamples = samples
            }
            catch {
                print("Unable to open file for offline testing, \(error.localizedDescription)")
                exit(64)
            }
            
        case .outputValidCallsToConsole:
            print("Printing valid calls to console: Enabled.")
            runtimeState.outputValidCallsToConsole = true
            
        case .useDigitalAGC:
            print("Digital AGC: Enabled.")
            runtimeState.useDigitalAGC = true
            
        case .bandwidth:
            currArgIndex += 1
            if let userBandwidth = Int(nextArgument ?? "failPlaceholder") {
                if(userBandwidth > 200000 || userBandwidth < 1000) {
                    print("Bandwidth \(userBandwidth) out of range ([1000, 200000]), using default (\(runtimeState.bandwidth))")
                    continue
                }
                runtimeState.bandwidth = userBandwidth
            }
            else {
                print("-b argument requires an integer value be provided.")
                exit(64)
            }
            
        case .deviceIndex:
            currArgIndex += 1
            if let userDeviceIndex = nextArgument {
                if(userDeviceIndex.contains(":")) {
                    let split = userDeviceIndex.split(separator: ":")
                    if(split.count != 2) {
                        print("The provided host/port combo for rtl-sdr device was invalid.")
                        exit(64)
                    }
                    runtimeState.sdrHost = String(split[0])
                    runtimeState.sdrPort = UInt16(split[1])!
                }
                else {
                    let indexAsInt: Int? = Int(userDeviceIndex)
                    if(indexAsInt == nil) {
                        print("The provided index for rtl-sdr device was invalid.")
                        exit(64)
                    }
                    runtimeState.sdrDeviceIndex = indexAsInt!
                }
            }
            else {
                print("-di must be accompanied with a device index, either an integer (USB), or an IP/port combo (e.g. 192.168.1.100:12345).")
                exit(64)
            }
            
        case .tcpServer:
            currArgIndex += 1
            if let serverPort = Int(nextArgument ?? "failPlaceholder") {
                if(serverPort < 1 || serverPort > 65535) {
                    print("The provided TCP server port (\(serverPort)) was invalid, must be greater than 1 and less than 65535")
                    exit(64)
                }
                let port = UInt16(serverPort)
                do {
                    runtimeState.outputServer = try TCPServer(port: port, actionOnNewConnection: { newConnection in
                        print("New connection to AIS server: \(newConnection.connectionName)")
                    })
                }
                catch {
                    print("Failed to setup TCP server: \(error)")
                    exit(1)
                }
            }
            else {
                print("-tcp must be accompanied with an integer (1-65535), specifying the port to listen on.")
                exit(64)
            }
            
        case .help:
            showHelp()
            exit(0)
            
        case .saveFile:
            currArgIndex += 1
            if let filePath = nextArgument {
                do {
                    let fileExists = FileManager.default.fileExists(atPath: filePath)
                    if(!fileExists) {
                        let wasSuccessful = FileManager.default.createFile(atPath: filePath, contents: nil)
                        if(!wasSuccessful) {
                            print("Unable to create file at path: \(filePath)")
                            exit(64)
                        }
                    }
                    let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
                    fileHandle.seekToEndOfFile()
                    runtimeState.outputFile = fileHandle
                }
                catch {
                    print("Unable to open file for writing: \(error.localizedDescription), path: \(filePath)")
                    exit(64)
                }
            }
            else {
                print("-s must be accompanied with a file path (e.g. -s path/to/file.txt)")
                exit(64)
            }
        
        case .relayServer:
            currArgIndex += 1
            if let port = UInt16(nextArgument ?? "failPlaceholder") { runtimeState.relayServer = RTLTCPRelayServer(port: port) }
            else {
                print("Invalid or no port provided to relay server. Allowed values are 1-65535.")
                exit(64)
            }
        
        default:
            print("Unrecognized argument: \(String(describing: argument))")
            exit(64)
        }
    }
    return runtimeState
}


let state = mapCLIArgsToVariables()
do {
    try main(state: state)
}
catch {
    print(error.localizedDescription)
}

func main(state: RuntimeState) throws {
    if state.offlineSamples != nil {
        try offlineTesting(state: state)
        exit(0)
    }

    if(state.outputServer != nil) {
        print("Starting TCP Server for AIS data...")
        state.outputServer?.startServer()
    }
    
    let sdr: RTLSDR = try {
        if state.sdrHost != nil && state.sdrPort != nil {
            let sdr = try RTLSDR_TCP(host: state.sdrHost!, port: state.sdrPort!)
            state.relayServer?.associateSDR(sdr: sdr)
            try state.relayServer?.start()
            return sdr
        }
        else {
            return try RTLSDR_USB(deviceIndex: state.sdrDeviceIndex)
        }
    }()
    
    defer {
        sdr.stopAsyncRead()
    }
    
    try sdr.setCenterFrequency(VHF_DSC_CENTER_FREQUENCY)
    try sdr.setDigitalAGCEnabled(state.useDigitalAGC)
    try sdr.setSampleRate(DEFAULT_INPUT_SAMPLE_RATE)
    try? sdr.setTunerBandwidth(state.bandwidth) // This won't work on RTLSDR_TCP because it's not implemented yet
    let receiver = try VHFDSCReceiver(inputSampleRate: DEFAULT_INPUT_SAMPLE_RATE, internalSampleRate: 48000, debugConfig: state.debugConfig)
    receiver.setCallEmissionHandler { call in
        handleCall(call, state: state)
    }
    
    var inputBuffer: [DSPComplex] = []
    
    sdr.asyncReadSamples(callback: { (inputData) in
        guard inputData.count > 16 else {
            if(state.debugConfig.debugOutput == .extensive) {
                print("inputData too short, skipping")
            }
            return
        }
        inputBuffer.append(contentsOf: inputData)
        if(inputBuffer.count >= MIN_BUFFER_LEN) {
            receiver.processSamples(inputBuffer)
            if(state.relayServer != nil) {
                let transportReadyBytes = inputData.mapForTransportFormat()
                state.relayServer?.handleSDRData(data: transportReadyBytes.withUnsafeBytes { Data($0) })
            }
            inputBuffer = []
        }
    })
    
    registerSignalHandler()
    atexit_b { // Like 'atexit' but allows for capturing context. who knew?
        print("Number of DSC Calls Received: \(state.validCalls.count)")
    }
    
    let mainThreadBlockingSemaphore = DispatchSemaphore(value: 0)
    let checkStopConditionsLoop = AsyncTimedLoop() {
        if !sdr.isActive {
            mainThreadBlockingSemaphore.signal()
        }
    }
    checkStopConditionsLoop.startTimedLoop(interval: 0.5)
    mainThreadBlockingSemaphore.wait()
}

func handleCall(_ call: DSCCall, state: RuntimeState) {
    state.validCalls.append(call)
    if(state.outputValidCallsToConsole) {
        print(call.description)
    }
    
    if let outputFile = state.outputFile {
        writeCallToFile(call, file: outputFile)
    }
    
    if let server = state.outputServer {
        do {
            try server.broadcastMessage(call.description)
        }
        catch {
            print("Failed to broadcase message: \(error)")
        }
    }
}

// Required for atexit block to be called when closed via Ctrl+C
func registerSignalHandler() {
    signal(SIGINT) { _ in
        exit(0)
    }
}

