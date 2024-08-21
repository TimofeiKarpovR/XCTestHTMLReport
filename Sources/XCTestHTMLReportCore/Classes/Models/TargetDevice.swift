//
//  RunDestination.swift
//  XCTestHTMLReport
//
//  Created by Titouan van Belle on 21.07.17.
//  Copyright © 2017 Tito. All rights reserved.
//

import Foundation
import XCResultKit

struct TargetDevice: Hashable, Comparable {
    let identifier: String
    let uniqueIdentifier: String
    let osVersion: String
    let model: String

    init(record: ActionDeviceRecord, eraseDeviceIds: Bool) {
        Logger.substep("Parsing ActionDeviceRecord")
        identifier = eraseDeviceIds ? "" : record.identifier
        uniqueIdentifier = eraseDeviceIds ? "Any" : UUID().uuidString
        osVersion = record.operatingSystemVersion
        model = record.modelName
    }

    static func <(lhs: TargetDevice, rhs: TargetDevice) -> Bool {
        lhs.model < rhs.model ||
        lhs.osVersion < rhs.osVersion ||
        lhs.identifier < rhs.identifier ||
        lhs.uniqueIdentifier < rhs.uniqueIdentifier
    }
}
