import Foundation

/// A conservative recent-trend estimate, not a probability or a writer attribution.
struct StorageForecast: Sendable {
    enum Status: String { case unavailable, collecting, stale, unstable, steady, declining, atReserve, belowReserve, unattainable }
    let status: Status
    let title: String
    let detail: String
    var bytesPerHour: Double? = nil
    var hoursToReserve: Double? = nil
    var samples = 0
    var spanMinutes: Double = 0

    static func evaluate(_ history: [Capacity], target: Int64, now: Date = Date()) -> StorageForecast {
        guard let latest = history.last, latest.total > 0, latest.free >= 0, latest.free <= latest.total, target > 0 else {
            return .init(status: .unavailable, title: "Capacity unavailable", detail: "Refresh capacity to start observing the home volume.")
        }
        let age = now.timeIntervalSince(latest.date)
        guard age >= -5, age <= 180 else {
            return .init(status: .stale, title: "Refresh before forecasting", detail: "The latest reading is stale or its timestamp is ahead of this Mac’s clock.")
        }
        if target > latest.total {
            return .init(status: .unattainable, title: "Reserve exceeds this volume", detail: "Choose a target below the home volume’s total capacity.")
        }
        if latest.free < target {
            return .init(status: .belowReserve, title: "Already below your reserve", detail: "The measured shortfall is \(gb(Double(target - latest.free))) GB. Review cleanup candidates; a forecast cannot restore space.")
        }
        if latest.free == target {
            return .init(status: .atReserve, title: "At your reserve boundary", detail: "The reserve is met exactly, with no measured headroom. Further writes may take available space below the target.")
        }
        // Use only the latest uninterrupted segment. Sleep gaps, clock reversals,
        // capacity changes and substantial recoveries invalidate the prior trend.
        var readings = [latest]
        for prior in history.dropLast().reversed() {
            let next = readings.last!
            let gap = next.date.timeIntervalSince(prior.date)
            guard gap > 0, gap <= 300, prior.total == latest.total,
                  prior.free >= 0, prior.free <= prior.total,
                  Double(next.free) - Double(prior.free) <= 1e9,
                  latest.date.timeIntervalSince(prior.date) <= 5400 else { break }
            if gap >= 50 { readings.append(prior) }
        }
        readings.reverse()
        let span = latest.date.timeIntervalSince(readings[0].date)
        guard readings.count >= 6, span >= 900 else {
            return .init(status: .collecting, title: "Learning the recent trend", detail: "Keep monitoring on for at least 15 uninterrupted minutes. Long gaps or recovered space restart the observation window.", samples: readings.count, spanMinutes: span / 60)
        }
        let rates = zip(readings, readings.dropFirst()).map { first, second in
            (Double(first.free) - Double(second.free)) / second.date.timeIntervalSince(first.date) * 3600
        }.sorted()
        let median = rates[rates.count / 2]
        let netRate = (Double(readings[0].free) - Double(latest.free)) / span * 3600
        if abs(netRate) < 1e9 && abs(median) < 1e9 {
            return .init(status: .steady, title: "No sustained decline detected", detail: "Recent net change is below the 1 GB/hour reporting threshold. This does not guarantee future space.", samples: readings.count, spanMinutes: span / 60)
        }
        let positive = rates.filter { $0 > 0 }.count
        guard median >= 1e9, netRate >= 1e9, Double(positive) / Double(rates.count) >= 0.75,
              netRate / median >= 0.5, netRate / median <= 2,
              rates[rates.count * 3 / 4] - rates[rates.count / 4] <= median * 2 else {
            return .init(status: .unstable, title: "Changes are too uneven to predict", detail: "Recent readings include bursts, reversals or recovery. No time-to-reserve estimate is shown.", samples: readings.count, spanMinutes: span / 60)
        }
        let hours = Double(latest.free - target) / median
        let horizon = min(24, span / 3600 * 4)
        let projection = hours <= horizon ? hours : nil
        let timing = projection.map { "At this rate, the reserve boundary is about \(max(1, Int(($0 * 60).rounded()))) minutes away." }
            ?? "The reserve boundary is beyond the supported projection window; no arrival time is shown."
        return .init(status: .declining, title: "Available space is falling", detail: "Recent pace: \(gb(median)) GB/hour. \(timing) This assumes the recent pace continues; it is not a guarantee.", bytesPerHour: median, hoursToReserve: projection, samples: readings.count, spanMinutes: span / 60)
    }

    private static func gb(_ bytes: Double) -> String { String(format: "%.1f", bytes / 1e9) }

    var advisorEvidence: String {
        let observation: String
        switch status {
        case .unavailable: observation = "Capacity could not be read. Refresh before drawing conclusions."
        case .collecting: observation = "The continuous observation window is too short to estimate a trend."
        case .stale: observation = "The latest reading is stale or its timestamp is invalid. Refresh first."
        case .unstable: observation = "Changes are uneven. Timing is withheld because the trend is unreliable."
        case .steady: observation = "No sustained decline was detected in the recent window. Future behavior can change."
        case .declining: observation = "Recent available space declined consistently. Any future projection assumes that pace continues; that assumption may fail."
        case .atReserve: observation = "Measured available space equals the reserve target, with no headroom."
        case .belowReserve: observation = "Measured available space is already below the reserve target. Review cleanup candidates in Yeoback."
        case .unattainable: observation = "The chosen reserve exceeds total volume capacity. Reduce the target."
        }
        return "Home-volume observation: \(observation) No cause, process or folder attribution was measured. Nothing is removed automatically."
    }

    func evidence(capacity: Capacity?, target: Int64) -> String {
        "Home-volume available GB: \(capacity.map { Self.gb(Double($0.free)) } ?? "unknown"). Target GB: \(Self.gb(Double(target))). Status: \(status.rawValue). \(title). \(detail) Trend samples: \(samples), span minutes: \(Int(spanMinutes)). No process or folder attribution was measured. Candidate sizes are estimates; moving to Trash usually does not release space until it is emptied. Nothing is removed automatically."
    }
}
