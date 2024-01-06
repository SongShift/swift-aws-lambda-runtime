//
//  LambdaError.swift
//
//
//  Created by Ben Rosen on 1/6/24.
//

import Foundation

public struct LambdaError: Error {
    let errorType: String
    let errorMessage: String
    
    public init(errorType: String, errorMessage: String) {
        self.errorType = errorType
        self.errorMessage = errorMessage
    }
}
