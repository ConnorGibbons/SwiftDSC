//
//  DSCSymbolEnums.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/19/25.
//
//  Contains symbol meanings in the context of various DSC structures.

// Format specifier is sent twice consecutively in every call. Determines the structure of the message to follow.
public enum DSCFormatSpecifier: UInt8 {
    case geographicalSelective = 102
    case distressAlert = 112
    case commonInterestSelective = 114
    case allShips = 116
    case invididualStationSelective = 120
    case nationalNonCallingReserved = 121
    case automaticServiceSelective = 123
}

// Category is sent once, only in specific call formats. It describes the "degree of priority" of the call.
public enum DSCCategory: UInt8 {
    case routine = 100
    case safety = 108
    case urgency = 110
    case distress = 112
}

// let EOS_SYMBOLS: [DSCSymbol] = [DSCSymbol(symbol: 117)!, DSCSymbol(symbol: 122)!, DSCSymbol(symbol: 127)!]

public enum EOSSymbol: UInt8 {
    case acknowledgementRequired = 117
    case providingAcknowledgement = 122 // Couldn't think of a better name for this -- it means the message is an answer to a call requiring acknowledgement.
    case other = 127
}
