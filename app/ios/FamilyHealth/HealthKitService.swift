import Foundation
import HealthKit

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    private func quantity(_ scope: HealthScope) -> (HKQuantityTypeIdentifier, HKUnit)? {
        switch scope {
        case .steps: return (.stepCount, .count())
        case .activeEnergy: return (.activeEnergyBurned, .kilocalorie())
        case .exerciseTime: return (.appleExerciseTime, .minute())
        case .heartRate: return (.heartRate, HKUnit.count().unitDivided(by: .minute()))
        case .bodyMass: return (.bodyMass, .gramUnit(with: .kilo))
        case .sleep: return nil
        }
    }
    func authorize(_ scopes: [HealthScope]) async throws {
        guard available, !scopes.isEmpty else { throw ClientError.server(422, "当前设备不支持健康数据，或尚未选择项目。") }
        let types: Set<HKObjectType> = Set(scopes.compactMap { scope -> HKObjectType? in
            if scope == .sleep { return HKObjectType.categoryType(forIdentifier: .sleepAnalysis) }
            return quantity(scope).flatMap { HKObjectType.quantityType(forIdentifier: $0.0) }
        })
        // Completion does not reveal read access for individual types.
        try await store.requestAuthorization(toShare: [], read: types)
        try Task.checkCancellation()
    }
    func snapshot(_ scopes: [HealthScope]) async throws -> HealthSnapshot {
        guard available else { throw ClientError.server(422, "当前设备不支持 Apple 健康。") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: end)!
        var readings: [HealthReading] = []
        for scope in scopes {
            try Task.checkCancellation()
            if [.steps, .activeEnergy, .exerciseTime].contains(scope) {
                readings += try await cumulative(scope, start: start, end: calendar.date(byAdding: .day, value: 1, to: end)!, calendar: calendar)
            } else {
                for offset in 0..<7 {
                    let day = calendar.date(byAdding: .day, value: offset, to: start)!
                    let next = calendar.date(byAdding: .day, value: 1, to: day)!
                    let value = try await discrete(scope, start: day, end: next)
                    if let value = value { readings.append(HealthReading(code: scope, day: AppDates.day(day, timeZone: calendar.timeZone), value: value)) }
                    try Task.checkCancellation()
                }
            }
        }
        return HealthSnapshot(windowStart: AppDates.day(start, timeZone: calendar.timeZone), windowEnd: AppDates.day(end, timeZone: calendar.timeZone), timezone: calendar.timeZone.identifier, records: readings)
    }
    private func cumulative(_ scope: HealthScope, start: Date, end: Date, calendar: Calendar) async throws -> [HealthReading] {
        guard let (identifier, unit) = quantity(scope), let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            var interval = DateComponents(); interval.day = 1
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: start, intervalComponents: interval)
            query.initialResultsHandler = { _, collection, error in
                if let error = error, (error as? HKError)?.code != .errorNoData { continuation.resume(throwing: error); return }
                var values: [HealthReading] = []
                collection?.enumerateStatistics(from: start, to: end.addingTimeInterval(-1)) { statistic, _ in
                    if let value = statistic.sumQuantity()?.doubleValue(for: unit), value.isFinite {
                        values.append(HealthReading(code: scope, day: AppDates.day(statistic.startDate, timeZone: calendar.timeZone), value: value))
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
    private func discrete(_ scope: HealthScope, start: Date, end: Date) async throws -> Double? {
        let type: HKSampleType
        if scope == .sleep { type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)! }
        else { type = HKQuantityType.quantityType(forIdentifier: quantity(scope)!.0)! }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: scope == .sleep ? [] : .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: scope == .sleep ? HKObjectQueryNoLimit : 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error = error {
                    if (error as? HKError)?.code == .errorNoData { continuation.resume(returning: nil) }
                    else { continuation.resume(throwing: error) }
                    return
                }
                if scope != .sleep {
                    let unit: HKUnit = scope == .heartRate ? HKUnit.count().unitDivided(by: .minute()) : .gramUnit(with: .kilo)
                    continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
                    return
                }
                let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                let intervals = (samples as? [HKCategorySample] ?? []).filter { asleep.contains($0.value) }
                    .map { (max(start, $0.startDate), min(end, $0.endDate)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
                guard let first = intervals.first else { continuation.resume(returning: nil); return }
                var lower = first.0; var upper = first.1; var total = 0.0
                for pair in intervals.dropFirst() {
                    if pair.0 <= upper { upper = max(upper, pair.1) }
                    else { total += upper.timeIntervalSince(lower); lower = pair.0; upper = pair.1 }
                }
                total += upper.timeIntervalSince(lower)
                continuation.resume(returning: total / 3600)
            }
            store.execute(query)
        }
    }
}
