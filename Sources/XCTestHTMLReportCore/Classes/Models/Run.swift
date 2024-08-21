//
//  Run.swift
//  XCTestHTMLReport
//
//  Created by Titouan van Belle on 21.10.17.
//  Copyright © 2017 Tito. All rights reserved.
//

import Foundation
import XCResultKit

struct Run: HTML {
    let files: [ResultFile]
    let runDestination: RunDestination
    let testSummaries: [TestSummary]
    let logContent: RenderingContent
    var status: Status {
        if let _ = testSummaries.first(where: { $0.status == .failure }) {
            return .failure
        }
        if let _ = testSummaries.first(where: { $0.status == .skipped }) {
            return .skipped
        }
        return .success
    }

    var allTests: [Test] {
        let tests = testSummaries.flatMap(\.tests)
        return tests.flatMap { test -> [Test] in
            let subTests = test.descendantSubTests
            if subTests.isEmpty {
                return [test]
            }
            return subTests
        }
    }

    var numberOfTests: Int {
        let a = allTests
        return a.count
    }

    var numberOfPassedTests: Int {
        allTests.filter { $0.status == .success }.count
    }

    var numberOfSkippedTests: Int {
        allTests.filter { $0.status == .skipped }.count
    }

    var numberOfFailedTests: Int {
        allTests.filter { $0.status == .failure }.count
    }

    var numberOfMixedTests: Int {
        allTests.filter { $0.status == .mixed }.count
    }

    init?(
        action: ActionRecord,
        file: ResultFile,
        renderingMode: Summary.RenderingMode,
        downsizeImagesEnabled: Bool,
        downsizeScaleFactor: CGFloat
    ) {
        files = [file]
        runDestination = RunDestination(record: action.runDestination, eraseDeviceIds: false)

        guard
            let testReference = action.actionResult.testsRef,
            let testPlanSummaries = file.getTestPlanRunSummaries(id: testReference.id)
        else {
            Logger.warning("Can't find test reference for action \(action.title ?? "")")
            return nil
        }

        // TODO: (Pierre Felgines) 02/10/2019 Use only emittedOutput from logs objects
        // For now XCResultKit do not handle logs
        if let logReference = action.actionResult.logRef {
            logContent = file.exportLogsContent(
                id: logReference.id,
                renderingMode: renderingMode
            )
        } else {
            Logger.warning("Can't find test reference for action \(action.title ?? "")")
            logContent = .none
        }
                
        let cpuCount = ProcessInfo.processInfo.processorCount
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = cpuCount * 2
        
        let queue = DispatchQueue(label: "com.xchtmlreport.lock")
        
        var summaries = [TestSummary]()
        
        testPlanSummaries.summaries
            .flatMap(\.testableSummaries)
            .forEach { testableSummary in
                let operation = BlockOperation {
                    let summary = TestSummary(
                        summary: testableSummary,
                        file: file,
                        renderingMode: renderingMode,
                        downsizeImagesEnabled: downsizeImagesEnabled,
                        downsizeScaleFactor: downsizeScaleFactor,
                        removeAllTestsGroup: false
                    )
                    queue.sync {
                        summaries.append(summary)
                    }
                }
                operationQueue.addOperation(operation)
            }
        
        operationQueue.waitUntilAllOperationsAreFinished()
        
        testSummaries = summaries.sorted { $0.testName < $1.testName }        
    }

    init?(
        fileWithActions: [(ResultFile, ActionRecord)],
        renderingMode: Summary.RenderingMode,
        downsizeImagesEnabled: Bool,
        downsizeScaleFactor: CGFloat
    ) {
        files = fileWithActions.map { $0.0 }

        guard let firstAction = fileWithActions.first?.1 else {
            Logger.warning("Grouped actions list is empty")
            return nil
        }

        runDestination = RunDestination(record: firstAction.runDestination, eraseDeviceIds: true)
                
        let cpuCount = ProcessInfo.processInfo.processorCount
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = cpuCount * 2
        
        let queue = DispatchQueue(label: "com.xchtmlreport.lock")
        var summaries = [TestSummary]()

        for (file, action) in fileWithActions {
            guard
                let testReference = action.actionResult.testsRef,
                let testPlanSummaries = file.getTestPlanRunSummaries(id: testReference.id)
            else {
                Logger.warning("Can't find test reference for action \(action.title ?? "")")
                continue
            }
            
            testPlanSummaries.summaries
                .flatMap(\.testableSummaries)
                .forEach { testableSummary in
                    let operation = BlockOperation {
                        let summary = TestSummary(
                            summary: testableSummary,
                            file: file,
                            renderingMode: renderingMode,
                            downsizeImagesEnabled: downsizeImagesEnabled,
                            downsizeScaleFactor: downsizeScaleFactor,
                            removeAllTestsGroup: true
                        )
                        queue.sync {
                            summaries.append(summary)
                        }
                    }
                    operationQueue.addOperation(operation)
                }
        }
        
        operationQueue.waitUntilAllOperationsAreFinished()
        
        testSummaries = summaries.sorted { $0.testName < $1.testName }        
        // TODO: handle logs for grouped runs
        logContent = .none
    }

    private var logSource: String? {
        switch logContent {
        case let .url(url):
            return url.relativePath
        case let .data(data):
            return "data:text/plain;base64,\(data.base64EncodedString())"
        case .none:
            return nil
        }
    }

    // PRAGMA MARK: - HTML

    var htmlTemplate = HTMLTemplates.run

    var htmlPlaceholderValues: [String: String] {
        [
            "DEVICE_IDENTIFIER": runDestination.targetDevice.uniqueIdentifier,
            "LOG_SOURCE": logSource ?? "",
            "N_OF_TESTS": String(numberOfTests),
            "N_OF_PASSED_TESTS": String(numberOfPassedTests),
            "N_OF_SKIPPED_TESTS": String(numberOfSkippedTests),
            "N_OF_FAILED_TESTS": String(numberOfFailedTests),
            "N_OF_MIXED_TESTS": String(numberOfMixedTests),
            "TEST_SUMMARIES": testSummaries.map(\.html).joined(),
        ]
    }
}

extension Run: ContainingAttachment {
    var screenshotAttachments: [Attachment] {
        allAttachments.filter(\.isScreenshot)
    }

    var allAttachments: [Attachment] {
        allTests.map(\.allAttachments).reduce([], +)
    }
}
