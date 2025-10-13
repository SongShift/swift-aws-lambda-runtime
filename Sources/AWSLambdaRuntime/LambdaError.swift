//
//  LambdaError.swift
//
//
//  Created by Ben Rosen on 1/6/24.
//

import Foundation

public struct LambdaError: Error, Codable, Equatable {
    public let errorType: String
    public let errorMessage: String
    
    public init(errorType: String, errorMessage: String) {
        self.errorType = errorType
        self.errorMessage = errorMessage
    }
    
    public static func == (lhs: LambdaError, rhs: LambdaError) -> Bool {
        return lhs.errorType == rhs.errorType
    }
}
