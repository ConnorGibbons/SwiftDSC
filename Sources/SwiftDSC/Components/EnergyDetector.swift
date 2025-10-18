//
//  EnergyDetector.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/6/25.
//
import Accelerate
import SignalTools

package class EnergyDetector {
    let sampleRate: Int
    let resistance: Float // Multiplied by standard deviation to create a threshold. Higher resistance = harder to pass gate
    var buffer: RingBuffer<DSPComplex>
    var bufferSize: Int {
        return buffer.count
    }
    var windowSize: Int
    
    var debugOutput: Bool
    
    init(sampleRate: Int, bufferDuration: Double?, windowSize: Double?, resistance: Float?, debugOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.debugOutput = debugOutput
        self.resistance = resistance ?? 0.5
        if bufferDuration == nil {
            self.buffer = RingBuffer<DSPComplex>.init(defaultVal: .init(real: 0, imag: 0), size: sampleRate / 2) // 500ms default
        }
        else {
            self.buffer = RingBuffer<DSPComplex>.init(defaultVal: .init(real: 0, imag: 0), size: Int(Double(sampleRate) * bufferDuration!))
        }
        if windowSize == nil {
            self.windowSize = Int(Double(sampleRate) * 0.025)
        }
        else {
            self.windowSize = Int(Double(sampleRate) * windowSize!)
        }
        
        debugPrint("EnergyDetector Window Size: \(self.windowSize); Buffer Len: \(buffer.count) ")
    }
    
    func addSamples(_ samples: [DSPComplex]) -> [Int] {
        if samples.count > bufferSize {
            debugPrint("Input array cannot be greater than buffer size -- input: \(samples.count), size: \(bufferSize)")
            return []
        }
        else if samples.isEmpty {
            debugPrint("EnergyDetector received no samples!")
            return []
        }
        self.buffer.write(samples)
        let threshold = self.processBuffer()
        var highEnergyIndicies: [Int] = []
        var currentIndex = 0
        let sampleMagnitudes = samples.magnitude()
        while (currentIndex + self.windowSize) < samples.count {
            let currentWindow = Array(sampleMagnitudes[currentIndex..<(currentIndex + self.windowSize)])
            let averageMagnitude = currentWindow.average()
            if averageMagnitude > threshold {
                highEnergyIndicies.append(currentIndex)
            }
            currentIndex += windowSize
        }
        
        return highEnergyIndicies
    }
    
    func processBuffer() -> Float {
        let magnitude = self.buffer.magnitude()
        let averageMagnitude = magnitude.average()
        let standardDeviation = magnitude.standardDeviation()
        return averageMagnitude + (resistance * standardDeviation)
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print("Energy Detector: " + str)
        }
    }
    
}
