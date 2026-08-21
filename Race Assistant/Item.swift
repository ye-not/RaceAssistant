//
//  Item.swift
//  Race Assistant
//
//  Created by Petr on 21.08.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
