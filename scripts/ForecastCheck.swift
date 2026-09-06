import Foundation

@main struct ForecastCheck {
    static func main() async throws {
        let now = Date()
        let total: Int64 = 1_000_000_000_000
        let target: Int64 = 150_000_000_000
        func series(_ values: [Int64], step: Double = 60) -> [Capacity] {
            values.enumerated().map { Capacity(date: now.addingTimeInterval(Double($0.offset - values.count + 1) * step), total: total, free: $0.element) }
        }
        var count = 0
        func check(_ name: String, _ condition: Bool) throws {
            guard condition else { throw StorageError.message("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        let decline = series((0..<16).map { 170_000_000_000 - Int64($0) * 500_000_000 })
        let result = StorageForecast.evaluate(decline, target: target, now: now)
        try check("steady decline pace", result.status == .declining && result.bytesPerHour == 30_000_000_000)
        try check("reserve timing", abs((result.hoursToReserve ?? -1) - 12.5 / 30) < 0.0001)
        let boundary = StorageForecast.evaluate(decline, target: decline.last!.free, now: now)
        try check("exact reserve has no future arrival time", boundary.status == .atReserve && boundary.hoursToReserve == nil)
        try check("AI input excludes numeric forecasts", !result.advisorEvidence.contains(where: { $0.isNumber }))
        try check("empty history", StorageForecast.evaluate([], target: target, now: now).status == .unavailable)
        try check("short window", StorageForecast.evaluate(Array(decline.suffix(5)), target: target, now: now).status == .collecting)
        try check("stale reading", StorageForecast.evaluate(decline, target: target, now: now.addingTimeInterval(181)).status == .stale)
        try check("future clock", StorageForecast.evaluate(decline, target: target, now: now.addingTimeInterval(-20)).status == .stale)
        try check("already below reserve", StorageForecast.evaluate(decline, target: 180_000_000_000, now: now).status == .belowReserve)
        try check("impossible reserve", StorageForecast.evaluate(decline, target: total + 1, now: now).status == .unattainable)
        try check("stable capacity", StorageForecast.evaluate(series(Array(repeating: 200_000_000_000, count: 16)), target: target, now: now).status == .steady)
        try check("burst does not imply sustained trend", StorageForecast.evaluate(series(Array(repeating: 200_000_000_000, count: 15) + [190_000_000_000]), target: target, now: now).status == .unstable)
        try check("recovery resets evidence", StorageForecast.evaluate(series((0..<15).map { 170_000_000_000 - Int64($0) * 500_000_000 } + [190_000_000_000]), target: target, now: now).status == .collecting)
        try check("sleep gap resets evidence", StorageForecast.evaluate(series([200_000_000_000, 190_000_000_000], step: 3600), target: target, now: now).status == .collecting)
        try check("distant projection withheld", StorageForecast.evaluate(decline, target: 10_000_000_000, now: now).hoursToReserve == nil)
        let invalid = [Capacity(date: now, total: total, free: -1)]
        try check("invalid capacity rejected", StorageForecast.evaluate(invalid, target: target, now: now).status == .unavailable)
        print("Forecast checks: \(count) passed")
        if CommandLine.arguments.contains("--ai") {
            print("AI availability: \(LocalStorageAdvisor.unavailableReason ?? "available")")
            let evidence = result.advisorEvidence
            print("Synthetic aggregate input: \(evidence)")
            let start = Date()
            let explanation = try await LocalStorageAdvisor.explain(evidence)
            try check("real local model returned text", !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            print("AI duration seconds: \(Date().timeIntervalSince(start))")
            print("Actual AI response: \(explanation)")
        }
    }
}
