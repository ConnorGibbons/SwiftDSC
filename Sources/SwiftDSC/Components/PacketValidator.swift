//
//  PacketValidator.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/15/25.
//
//

/// Handles error detection / correction for DSC signals.
package class PacketValidator {
    
    /// Uses RX line to confirm / correct the symbols in DX.
    /// DX is taken to be the source of truth unless the symbol is nil & RX has a valid symbol in that position.
    /// Will abort and return 'nil' if an unrecoverable error is found in DX.
    package func confirmDX(dx: [DSCSymbol], rx: [DSCSymbol]) -> [DSCSymbol]? {
        let eosPos = dx.firstIndex(where: {
            EOS_SYMBOLS.contains($0)
        })
        
        let count = min((eosPos ?? (Int.max - 1)) + 1, min(dx.count, rx.count)) // Stop at EOS symbol, or, the last symbol whose position exists in both DX & RX.
        var confirmedDX = [DSCSymbol].init(repeating: DSCSymbol(code: 0), count: count)
         
        // Pass 1: For any nils in DX, check if a valid entry exists in RX, if so then take that.
        for i in 0..<count {
            if dx[i].codeIsValid == false {
                if rx[i].codeIsValid == true {
                    confirmedDX[i] = rx[i]
                }
                else {
                    print("Unrecoverable error: \(dx[i]) -- rx: \(rx[i])")
                    return nil
                }
            }
            else { confirmedDX[i] = dx[i] }
        }
        
        // Pass 2: Detect discrepancies between DX/RX
        for i in 0..<count {
            if dx[i] != rx[i] {
                print("Discrepancy at index \(i): \(dx[i]) -- rx: \(rx[i])")
            }
        }
        return confirmedDX
    }
    
}
