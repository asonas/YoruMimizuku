import Foundation
import MetricKit
import os
import YoruMimizukuKit

/// Subscribes to MetricKit so the OS delivers aggregated field metrics (launch
/// time, memory, animation hitches) and diagnostics (hangs, crashes). Payloads
/// arrive roughly once per day, so this is for trend data from real usage rather
/// than live profiling — pair it with Instruments for in-session work.
/// `@unchecked Sendable`: stateless apart from an immutable `Logger`, so the
/// shared instance is safe to register from any context.
final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsSubscriber()

    private let log = Logger(subsystem: PerfSignpost.subsystem, category: "Metrics")

    /// Registers with `MXMetricManager`. Safe to call once at launch.
    func start() {
        MXMetricManager.shared.add(self)
        log.debug("MetricKit subscriber registered")
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                log.info("MXMetricPayload \(json, privacy: .public)")
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                log.info("MXDiagnosticPayload \(json, privacy: .public)")
            }
        }
    }
}
