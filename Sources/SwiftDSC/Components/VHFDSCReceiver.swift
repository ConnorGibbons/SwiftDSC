//
//  VHFDSCReceiver.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/4/25.
//

import Accelerate
import RTLSDRWrapper
import SignalTools

/// Enumerates the different states the receiver can be in.
/// waiting: Not currently receiving a transmission.
/// unlocked: Receiving dot pattern and phasing sequence, acquiring timing.
/// locked: Dot pattern + phasing complete, timing locked.
/// ending: Receiving ending sequence.
package enum DSCReveiverState: Equatable {
    case waiting
    case unlocked(dotPatternIndex: Int, preciseStartFound: Bool) // Index of dot pattern is stored (-1 if not found), and Bool based on whether precise start was found.
    case locked
    case ending
    
    var isUnlocked: Bool {
        if case .unlocked = self {
            return true
        }
        return false
    }
    
}

public enum DSCErrors: Error {
    case inputSampleRateTooLow
    case sampleRateMismatch
}


public class VHFDSCReceiver {
    // Constants
    let baud: Int = 1200
    let markFreq: Int = 1300
    let spaceFreq: Int = 2100
    let energyDetectionWindowSize = 0.025
    let energyDetectionResistance = 0.5
    let collapseTimesThreshold = 0.075
    let collapseTimesBuffer = 0.0
    let maxLockingRetries = 1
    
    // Parameters
    let inputSampleRate: Int
    let internalSampleRate: Int
    
    // State
    var state: DSCReveiverState
    var dx: [DSCSymbol] = []
    var dxConfirmed: [DSCSymbol] = [] // Storage for dx symbols that have passed errror checking / resolution.
    var rx: [DSCSymbol] = []
    var totalSymbolsReceived: Int = 0
    var bitCache: BitBuffer
    var audioCache: [Float]
    var retryCurrentTaskCounter: Int = 0
    
    // Debug
    var debugBuffer: [Float] = []
    
    // Components
    package let energyDetector: EnergyDetector
    package let preprocessor: SignalPreprocessor
    package let processor: SignalProcessor
    package let decoder: VHFDSCPacketDecoder
    package let synchronizer: VHFDSCPacketSynchronizer
    package let validator: PacketValidator
    
    public init(inputSampleRate: Int, internalSampleRate: Int) throws {
        guard inputSampleRate >= internalSampleRate else {
            throw DSCErrors.inputSampleRateTooLow
        }
        guard inputSampleRate % internalSampleRate == 0 else {
            print("Input sample rate must be a multiple of internal sample rate.")
            throw DSCErrors.sampleRateMismatch
        }
        guard internalSampleRate % 1200 == 0 else {
            print("Internal sample rate must be a multiple of 1200 (DSC Baud)")
            throw DSCErrors.sampleRateMismatch
        }
        
        // Parameters
        self.inputSampleRate = inputSampleRate
        self.internalSampleRate = internalSampleRate
        
        // State
        self.state = .waiting
        self.dx = []
        self.dxConfirmed = []
        self.rx = []
        self.totalSymbolsReceived = 0
        self.bitCache = BitBuffer()
        self.audioCache = []
        
        // Components
        self.energyDetector = EnergyDetector(sampleRate: internalSampleRate, bufferDuration: 1, windowSize: 0.025, resistance: 0.5)
        self.preprocessor = SignalPreprocessor(inputSampleRate: inputSampleRate, outputSampleRate: internalSampleRate)
        self.processor = try SignalProcessor(sampleRate: internalSampleRate)
        self.decoder = VHFDSCPacketDecoder(sampleRate: internalSampleRate)
        self.synchronizer = VHFDSCPacketSynchronizer(sampleRate: internalSampleRate, decoder: decoder)
        self.validator = PacketValidator()
    }
    
    public func processSamples(_ samples: [DSPComplex]) {
        var samplesMutableCopy = samples
        let preprocessedSamples = self.preprocessor.processSignal(&samplesMutableCopy)
        switch state {
        case .waiting:
            guard let (startTime, endTime) = getHighEnergyTimes(preprocessedSamples).first else { return }
            let endSample = min(timeToSampleIndex(endTime, sampleRate: self.internalSampleRate), preprocessedSamples.count - 1) // Preventing out of bounds errors
            let startSample = max(timeToSampleIndex(startTime, sampleRate: self.internalSampleRate), 0) 
            let signalSamples = Array(preprocessedSamples[startSample...endSample])
            let audio = self.processor.frequencyOverTime(signalSamples)
            self.state = .unlocked(dotPatternIndex: -1, preciseStartFound: false)
            processAudio(audio)
        default:
            let audio = self.processor.frequencyOverTime(preprocessedSamples)
            processAudio(audio)
        }
    }
    
    private func processAudio(_ audio: [Float]) {
        switch state {
        case .waiting:
            print("Hit a disallowed case -- processAudio called while state is 'waiting'.")
            return
        case .unlocked:
            unlockedAudioHandler(audio)
        case .locked:
            lockedAudioHandler(audio)
        default:
            return
        }
    }
    
    // ########################################
    // --- Per-state Audio Handlers / Logic ---
    // ########################################
    
    // *** Unlocked ***
    
    private func unlockedAudioHandler(_ audio: [Float]) {
        switch self.state {
        case .unlocked(let dotPatternIndex, let preciseStartFound):
            if(dotPatternIndex == -1) { // Block for where dot pattern isn't yet found. Looks for it, if found, moves to that state & recalls handler. Else, back to waiting.
                unlockedDotPatternHandler(audio)
            }
            else if(!preciseStartFound) { // Block for where dot pattern is found, but precise start isn't. If found, adjust state. Else, allow for one retry in case signal was cut off.
                unlockedPreciseStartHandler(audio, dotPatternIndex: dotPatternIndex)
            }
            else { // Block for when dot pattern & precise start have been found. We only escape this once full 14 symbol phasing sequence is detected.
                unlockedAcquireLockHandler(audio)
            }
        default:
            print("Hit a disallowed case -- unlockedAudioHandler called while state is not 'unlocked'.")
            return
        }
    }
    
    /// Looks for dot pattern start. Sets state accordingly if found, recalls unlockedAudioHandler to begin looking for precise start.
    private func unlockedDotPatternHandler(_ audio: [Float]) {
        guard let dotPatternIndex = self.synchronizer.findDotPatternStart(audio: audio) else {
            self.abortToWaiting("Failed to find dot pattern -- returning to waiting state.")
            return
        }
        debugPrint("Found dot pattern start at sample \(dotPatternIndex).")
        self.setState(.unlocked(dotPatternIndex: dotPatternIndex, preciseStartFound: false))
        unlockedAudioHandler(audio)
    }
    
    /// Looks for a precise start (see PacketSynchronizer). Sets state accordingly if found, recalls unlockedAudioHandler to begin looking for a lock.
    private func unlockedPreciseStartHandler(_ audio: [Float], dotPatternIndex: Int) {
        var audioMutableCopy = audio
        if(retryCurrentTaskCounter > 0) { // If this isn't the first attempt, prior audio should have been stored in the cache.
            var cache = claimAudioCache()
            cache.append(contentsOf: audio)
            audioMutableCopy = cache
        }
        guard let preciseStartIndex = self.synchronizer.getPreciseStartingSample(audio: audioMutableCopy, dotPatternIndex: dotPatternIndex) else { // If precise start failed, abort if at max retries (set to waiting state), otherwise store audio in cache and retain state.
            if retryCurrentTaskCounter >= self.maxLockingRetries {
                self.abortToWaiting("Unable to find a precise starting index after \(retryCurrentTaskCounter) retries, returning to waiting.")
                return
            }
            else {
                retryCurrentTaskCounter += 1
                self.audioCache = audioMutableCopy
                return
            }
        }
        debugPrint("Found precise start at sample \(preciseStartIndex).")
        // If we reached here, finding a precise start succeeded, state should be updated accordingly & handler recalled with new audio starting at precise index.
        let newAudio = Array(audioMutableCopy[preciseStartIndex...])
        self.retryCurrentTaskCounter = 0
        self.setState(.unlocked(dotPatternIndex: dotPatternIndex, preciseStartFound: true))
        unlockedAudioHandler(newAudio)
    }
    
    /// Checks if lock is achieved (see PacketSynchronizer). Sets state to .locked if found, does *not* recall unlockedAudioHandler.
    private func unlockedAcquireLockHandler(_ audio: [Float]) {
        getNextSymbolsFromAudio(audio, useContext: retryCurrentTaskCounter > 0)
        if self.synchronizer.lockIsAcquired(dx: self.dx, rx: self.rx) {
            self.unlockedToLocked()
        }
        else {
            guard retryCurrentTaskCounter < self.maxLockingRetries else { abortToWaiting("Failed to find lock after \(self.maxLockingRetries) retries, aborting to waiting."); return }
            retryCurrentTaskCounter += 1
        }
    }
    
    // *** Locked ***
    
    private func lockedAudioHandler(_ audio: [Float]) {
        getNextSymbolsFromAudio(audio)
        if(self.synchronizer.reachedEndSequence(dx: self.dxConfirmed)) {
            self.lockedToEnding()
        }
    }
    
    // *** Ending ***
    
    private func endingAudioHandler(_ audio: [Float]) {
        getNextSymbolsFromAudio(audio)
        if let errorCheckSymbol = self.synchronizer.checkIfComplete(dx: self.dx, rx: self.rx) {
            endOfReceptionHandler(errorCheckSymbol: errorCheckSymbol)
        }
    }
   
    // #########################
    // --- State Transitions ---
    // #########################
    
    // DSCReceiverState --> Waiting
    private func abortToWaiting(_ message: String) {
        self.debugPrint(message)
        self.state = .waiting
        self.clearState()
    }
    
    // Unlocked --> Locked
    private func unlockedToLocked() {
        // Dropping phasing symbols from storage since they aren't really relevant past this point.
        self.dx = Array(self.dx.dropFirst(6))
        self.rx = Array(self.rx.dropFirst(8))
        self.setState(.locked)
    }
    
    // Locked --> Ending
    private func lockedToEnding() {
        self.setState(.ending)
        if let errorCheckSymbol = self.synchronizer.checkIfComplete(dx: self.dx, rx: self.rx) {
            endOfReceptionHandler(errorCheckSymbol: errorCheckSymbol)
        }
    }
    
    // --- Helpers ---
    
    private func setState(_ newState: DSCReveiverState) {
        guard newState != self.state else { print("Failed attempt to transition to same state, \(newState)"); return }
        print("Transitioning from \(self.state) to \(newState)")
        self.state = newState
    }
    
    /// Prints only if self.debugPrint is true.
    private func debugPrint(_ str: String) {
        if(true) { // Keep in mind need to add self.debugOutput later
            print(str)
        }
    }
    
    /// Cleanup dx/rx, init DSCSentence from dx, emit DSCSentence, clear state and return
    private func endOfReceptionHandler(errorCheckSymbol: DSCSymbol) {
        self.cleanDXAndRX(errorCheckSymbol: errorCheckSymbol)
        self.printDXSymbols()
        self.printRXSymbols()
        self.clearState()
    }
    
    private func cleanDXAndRX(errorCheckSymbol: DSCSymbol) {
        guard let dxErrorCheckIndex = self.dx.firstIndex(where: {$0 == errorCheckSymbol}) else {
            print("Could not clean DX/RX -- provided error check symbol is not present in DX")
            return
        }
        guard let rxErrorCheckIndex = self.dx.firstIndex(where: {$0 == errorCheckSymbol}) else {
            print("Could not clean DX/RX -- provided error check symbol is not present in RX")
            return
        }
        dx.removeSubrange(dxErrorCheckIndex+3..<dx.count) // Error check symbol ("I") is third-to-last in dx,
        rx.removeSubrange(rxErrorCheckIndex+1..<rx.count) // Error check symbol is the last in RX.
    }
    
    /// Wipes receiver to a clean state, removing stored symbols, bit cache, audio cache.
    private func clearState() {
        _ = self.claimBitCache()
        _ = self.claimAudioCache()
        self.dx.removeAll()
        self.rx.removeAll()
        self.retryCurrentTaskCounter = 0
    }
    
    /// Set current bit cache, audio cache.
    /// Audio cache should  be aligned such that 0th element is the first sample of the next bit.
    private func setCached(bits: BitBuffer, audio: [Float]) {
        self.bitCache = bits
        self.audioCache = audio
    }
    
    /// Consumes the currently stored audio cache -- deletes & returns it.
    private func claimAudioCache() -> [Float] {
        let retVal: [Float] = self.audioCache
        self.audioCache.removeAll()
        return retVal
    }
    
    private func claimBitCache() -> BitBuffer {
        let retVal: BitBuffer = self.bitCache
        self.bitCache = BitBuffer()
        return retVal
    }
    
    private func storeSymbols(_ symbols: [DSCSymbol]) {
        var currIsDX = totalSymbolsReceived % 2 == 0
        for i in 0..<symbols.count {
            if(currIsDX) { self.dx.append(symbols[i]) }
            else { self.rx.append(symbols[i]) }
            currIsDX.toggle()
        }
        if(state == .locked || state == .ending) {
            guard let confirmed = validator.confirmDX(dx: self.dx, rx: self.rx) else {
                abortToWaiting("Encountered an unrecoverable error, aborting to waiting.")
                return;
            }
            self.dxConfirmed = confirmed
        }
        self.totalSymbolsReceived += symbols.count
    }
    
    private func getNextSymbolsFromAudio(_ audio: [Float], useContext: Bool = true) {
        var audioMutableCopy = audio
        var contextBits = BitBuffer()
        var audioCache = claimAudioCache()
        if(useContext) {
            if(!audioCache.isEmpty) {
                audioCache.append(contentsOf: audio)
                audioMutableCopy = audioCache
            }
            contextBits = claimBitCache()
        }
        guard let (symbols, leftoverAudio) = self.decoder.decodeToSymbols(samples: audioMutableCopy, context: &contextBits) else {
            abortToWaiting("Failed to demodulate audio to symbols, aborting to waiting.")
            return
        }
        setCached(bits: contextBits, audio: leftoverAudio)
        storeSymbols(symbols)
    }
    
    package func getHighEnergyTimes(_ signal: [DSPComplex]) -> [(Double, Double)] {
        var samplesToProcess: [[DSPComplex]] = []
        if(signal.count > energyDetector.bufferSize) {
            samplesToProcess = splitArray(signal, sectionSize: energyDetector.bufferSize)
        }
        else {
            samplesToProcess.append(signal)
        }
        
        var highEnergyIndices: [Int] = []
        var currentChunkNum = 0
        while(currentChunkNum < samplesToProcess.count) {
            var newHighEnergyIndicies = self.energyDetector.addSamples(samplesToProcess[currentChunkNum])
            addBufferOffsetToIndexArray(&newHighEnergyIndicies, currentChunkNum)
            highEnergyIndices.append(contentsOf: newHighEnergyIndicies)
            currentChunkNum += 1
        }
        guard highEnergyIndices.count > 1 else {
            // debugPrint("Exited early due to not finding enough high energy indicies")
            print("Exited early due to not finding enough high energy indicies")
            return []
        }
        
        let highEnergyTimes = highEnergyIndices.map { sampleIndexToTime($0, sampleRate: self.internalSampleRate) }
        return collapseTimeArray(highEnergyTimes, threshold: self.collapseTimesThreshold, addBuffer: self.collapseTimesBuffer)
    }
    
    package func addBufferOffsetToIndexArray(_ indexArray: inout [Int], _ bufferOffset: Int) {
        var index = 0
        let bufferIndexOffset = bufferOffset * self.energyDetector.bufferSize
        while index < indexArray.count {
            indexArray[index] += bufferIndexOffset
            index += 1
        }
    }
    
    func printDXSymbols() {
        print("*DX*")
        for symbol in dx {
            print(symbol.symbol ?? "nil")
        }
    }
    
    func printRXSymbols() {
        print("*RX*")
        for symbol in rx {
            print(symbol.symbol ?? "nil")
        }
    }
    
}
