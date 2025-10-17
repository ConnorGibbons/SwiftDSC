//
//  AudioHandlers.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/16/25.
//

extension VHFDSCReceiver {
    
    // *** Unlocked ***
    
    func unlockedAudioHandler(_ audio: [Float]) {
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
    func unlockedDotPatternHandler(_ audio: [Float]) {
        var mutableAudio = claimAudioCache(); mutableAudio.append(contentsOf: audio)  // This needs to be here in case the dot pattern was split in half during the input.
        guard let dotPatternIndex = self.synchronizer.findDotPatternStart(audio: mutableAudio) else {
            self.abortToWaiting("Failed to find dot pattern -- returning to waiting state.")
            self.audioCache = audio
            return
        }
        debugPrint("Found dot pattern start at sample \(dotPatternIndex).")
        self.setState(.unlocked(dotPatternIndex: dotPatternIndex, preciseStartFound: false))
        unlockedAudioHandler(mutableAudio)
    }
    
    /// Looks for a precise start (see PacketSynchronizer). Sets state accordingly if found, recalls unlockedAudioHandler to begin looking for a lock.
    func unlockedPreciseStartHandler(_ audio: [Float], dotPatternIndex: Int) {
        var audioMutableCopy = audio
        if(retryCurrentTaskCounter > 0) { // If this isn't the first attempt, prior audio should have been stored in the cache.
            var cache = claimAudioCache()
            cache.append(contentsOf: audio)
            audioMutableCopy = cache
        }
        guard let preciseStartIndex = self.synchronizer.getPreciseStartingSample(audio: audioMutableCopy, dotPatternIndex: dotPatternIndex) else { // If precise start failed, abort if at max retries (set to waiting state), otherwise store audio in cache and retain state.
            // writeAudioToTempFile(audioMutableCopy)
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
    func unlockedAcquireLockHandler(_ audio: [Float]) {
        getNextSymbolsFromAudio(audio, useContext: retryCurrentTaskCounter > 0)
        if self.synchronizer.lockIsAcquired(dx: self.dx, rx: self.rx) {
            self.unlockedToLocked()
        }
        else {
            guard retryCurrentTaskCounter < self.maxLockingRetries else {
                printDXSymbols()
                printRXSymbols()
                abortToWaiting("Failed to find lock after \(self.maxLockingRetries) retries, aborting to waiting.")
                return
            }
            retryCurrentTaskCounter += 1
        }
    }
    
    // *** Locked ***
    
    func lockedAudioHandler(_ audio: [Float]) {
        getNextSymbolsFromAudio(audio)
        if(self.synchronizer.reachedEndSequence(dx: self.dxConfirmed)) {
            self.lockedToEnding()
        }
    }
    
    // *** Ending ***
    
    func endingAudioHandler(_ audio: [Float]) {
        getNextSymbolsFromAudio(audio)
        if let errorCheckSymbol = self.synchronizer.checkIfComplete(dx: self.dx, rx: self.rx) {
            endOfReceptionHandler(errorCheckSymbol: errorCheckSymbol)
        }
    }
    
}
