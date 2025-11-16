//  Files.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/6/25.
//
//  Tools for working with IQ recordings.

import Foundation
import Accelerate

// Note: This assumes that file pointer is already at end of file
func writeCallToFile(_ call: DSCCall, file: FileHandle) {
    guard let sentenceAsData = (call.description + "\n").data(using: .utf8) else {
        print("Failed to encode DSC call to data: \(call.description)")
        return
    }
    file.write(sentenceAsData)
}
