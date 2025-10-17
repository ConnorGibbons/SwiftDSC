//
//  StateTransitions.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/16/25.
//

extension VHFDSCReceiver {
    
    // DSCReceiverState --> Waiting
    func abortToWaiting(_ message: String) {
        self.debugPrint(message, level: .errorsOnly)
        self.state = .waiting
        self.clearState()
    }
    
    // Unlocked --> Locked
    func unlockedToLocked() {
        // Dropping phasing symbols from storage since they aren't really relevant past this point.
        self.dx = Array(self.dx.dropFirst(6))
        self.rx = Array(self.rx.dropFirst(8))
        self.setState(.locked)
        if self.synchronizer.reachedEndSequence(dx: self.dxConfirmed) {
            lockedToEnding()
        }
    }
    
    // Locked --> Ending
    func lockedToEnding() {
        self.setState(.ending)
        if let errorCheckSymbol = self.synchronizer.checkIfComplete(dx: self.dx, rx: self.rx) {
            endOfReceptionHandler(errorCheckSymbol: errorCheckSymbol)
        }
    }
    
}
