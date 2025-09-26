//
//  Helpers.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/16/25.
//

import SignalTools
import Accelerate

extension VHFDSCReceiver {
    
    // --- Helpers ---
    // Functions for VHFDSCReceiver that exist for convenience / Don't fit neatly into another category.
    
    func setState(_ newState: DSCReveiverState) {
        guard newState != self.state else { print("Failed attempt to transition to same state, \(newState)"); return }
        print("Transitioning from \(self.state) to \(newState)")
        self.state = newState
    }
    
    /// Prints only if self.debugPrint is true.
    func debugPrint(_ str: String) {
        if(true) { // Keep in mind need to add self.debugOutput later
            print(str)
        }
    }
    
    /// Cleanup dx/rx, init DSCSentence from dx, emit DSCSentence, clear state and return
    func endOfReceptionHandler(errorCheckSymbol: DSCSymbol) {
        self.cleanDXAndRX(errorCheckSymbol: errorCheckSymbol)
        self.printDXConfirmedSymbols()
        if let sentence = getDSCCall(callSymbols: dxConfirmed) {
            self.emittedCallHandler(sentence)
        } else {
            print("Failed to parse call symbols as DSCSentence.")
            print("\(dxConfirmed)")
        }
        self.clearState()
    }
    
    /// Removes any extraneous symbols after the ending sequence.
    /// This might not be necessary since any logic after ending reception should use dxConfirmed, which intrinsically will not have the extra symbols.
    func cleanDXAndRX(errorCheckSymbol: DSCSymbol) {
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
    func clearState() {
        _ = self.claimBitCache()
        _ = self.claimAudioCache()
        self.dx.removeAll()
        self.rx.removeAll()
        self.dxConfirmed.removeAll()
        self.retryCurrentTaskCounter = 0
    }
    
    /// Set current bit cache, audio cache.
    /// Audio cache should  be aligned such that 0th element is the first sample of the next bit.
    func setCached(bits: BitBuffer, audio: [Float]) {
        self.bitCache = bits
        self.audioCache = audio
    }
    
    /// Consumes the currently stored audio cache -- deletes & returns it.
    func claimAudioCache() -> [Float] {
        let retVal: [Float] = self.audioCache
        self.audioCache.removeAll()
        return retVal
    }
    
    func claimBitCache() -> BitBuffer {
        let retVal: BitBuffer = self.bitCache
        self.bitCache = BitBuffer()
        return retVal
    }
    
    func storeSymbols(_ symbols: [DSCSymbol]) {
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
    
    func getNextSymbolsFromAudio(_ audio: [Float], useContext: Bool = true) {
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
    
    func getHighEnergyTimes(_ signal: [DSPComplex]) -> [(Double, Double)] {
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
    
    func printDXConfirmedSymbols() {
        print("*DX (Confirmed)*")
        for symbol in dxConfirmed {
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
