//
//  CallFormats.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/19/25.
//

public protocol DSCCall {
    var formatSpecifier: DSCFormatSpecifier { get }
    var selfID: MMSI { get }
    var EOS: DSCSymbol { get }
}

public struct DistressAlert: DSCCall {
    public let formatSpecifier: DSCFormatSpecifier = .distressAlert
    public var selfID: MMSI
    public var EOS: DSCSymbol
}
