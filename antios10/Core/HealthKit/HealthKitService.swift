// HealthKitService.swift
// HealthKit 服务

import Foundation
import HealthKit

struct HealthKitWorkoutSummary: Equatable {
    let id: String
    let activityName: String
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
}

@MainActor
final class HealthKitService: ObservableObject, HealthKitServicing {
    static let shared = HealthKitService()
    
    private let healthStore = HKHealthStore()

    private init() {}
    
    @Published var isAuthorized = false
    @Published var lastBackgroundUpdate: Date?
    
    /// 是否为模拟器环境
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    var isAvailable: Bool {
        // 模拟器不支持 HealthKit，静默返回 false
        guard !isSimulator else { return false }
        return HKHealthStore.isHealthDataAvailable()
    }
    
    // MARK: - 授权
    
    func requestAuthorization() async throws {
        // 模拟器环境下静默跳过，不抛出错误
        guard !isSimulator else {
            print("[HealthKit] ⚠️ 模拟器不支持 HealthKit，静默跳过")
            return
        }
        
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }
        
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType()
        ]
        
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        isAuthorized = isAuthorizedForRead()
    }

    /// 当前授权状态（用于界面展示）
    func isAuthorizedForRead() -> Bool {
        guard isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return false
        }
        return healthStore.authorizationStatus(for: type) == .sharingAuthorized
    }
    
    // MARK: - 查询方法
    
    func queryLatestHRV() async throws -> Double {
        try await queryLatestHRV(from: nil, to: nil)
    }

    func queryLatestHRV(from startDate: Date?, to endDate: Date?) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate: NSPredicate?
        if startDate != nil || endDate != nil {
            predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate, .strictEndDate]
            )
        } else {
            predicate = nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(throwing: HealthKitError.noData)
                    return
                }
                let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
    
    func queryRestingHeartRate(from startDate: Date, to endDate: Date) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.typeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(throwing: HealthKitError.noData)
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    func querySteps(from startDate: Date, to endDate: Date) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.typeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
    
    func querySleepDuration(from startDate: Date, to endDate: Date) async throws -> Double {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.typeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                
                let asleepSamples = samples.filter { sample in
                    if #available(iOS 16.0, *) {
                        return sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                               sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                               sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                               sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    } else {
                        return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
                    }
                }
                
                let totalSeconds = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Anti-anxiety wearable ingestion bundle

    /// 采集 Apple Watch / HealthKit 指标并封装为统一入链契约。
    func collectAppleWatchIngestionBundle(
        from startDate: Date? = nil,
        to endDate: Date = Date()
    ) async throws -> AppleWatchIngestionBundle {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        if !isAuthorizedForRead() {
            try await requestAuthorization()
        }

        let calendar = Calendar.current
        let start = startDate ?? calendar.startOfDay(for: endDate)

        async let hrvValue = queryLatestHRV()
        async let rhrValue = queryRestingHeartRate(from: start, to: endDate)
        async let stepsValue = querySteps(from: start, to: endDate)
        async let sleepHours = querySleepDuration(from: start, to: endDate)

        let now = ISO8601DateFormatter().string(from: endDate)
        var snapshots: [WearableMetricSnapshot] = []

        if let hrv = try? await hrvValue, hrv > 0 {
            snapshots.append(WearableMetricSnapshot(
                metricType: "hrv",
                value: hrv,
                unit: "ms",
                recordedAt: now,
                source: "apple_watch_healthkit"
            ))
        }

        if let rhr = try? await rhrValue, rhr > 0 {
            snapshots.append(WearableMetricSnapshot(
                metricType: "resting_heart_rate",
                value: rhr,
                unit: "bpm",
                recordedAt: now,
                source: "apple_watch_healthkit"
            ))
        }

        if let steps = try? await stepsValue, steps > 0 {
            snapshots.append(WearableMetricSnapshot(
                metricType: "steps",
                value: steps,
                unit: "count",
                recordedAt: now,
                source: "apple_watch_healthkit"
            ))
        }

        if let sleep = try? await sleepHours, sleep > 0 {
            snapshots.append(WearableMetricSnapshot(
                metricType: "sleep_score",
                value: sleepScore(fromHours: sleep),
                unit: "score",
                recordedAt: now,
                source: "apple_watch_healthkit"
            ))
        }

        return AppleWatchIngestionBundle(
            collectedAt: now,
            snapshots: snapshots,
            source: "apple_watch_healthkit"
        )
    }

    private func sleepScore(fromHours hours: Double) -> Double {
        switch hours {
        case 7...9:
            return 90
        case 6..<7, 9..<10:
            return 75
        case 5..<6:
            return 60
        default:
            return 45
        }
    }

    func queryLatestWorkout(
        since startDate: Date? = nil,
        to endDate: Date = Date()
    ) async throws -> HealthKitWorkoutSummary? {
        guard isAvailable else {
            return nil
        }

        let predicate: NSPredicate?
        if let startDate {
            predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate, .strictEndDate]
            )
        } else {
            predicate = nil
        }

        let workoutType = HKObjectType.workoutType()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workout = results?.first as? HKWorkout else {
                    continuation.resume(returning: nil)
                    return
                }

                let summary = HealthKitWorkoutSummary(
                    id: workout.uuid.uuidString,
                    activityName: Self.displayName(for: workout.workoutActivityType),
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationMinutes: max(1, Int((workout.duration / 60).rounded()))
                )
                continuation.resume(returning: summary)
            }
            healthStore.execute(query)
        }
    }

    func hasMorningRecoverySignals(at date: Date = Date()) async -> Bool {
        guard isAvailable else { return false }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -18, to: startOfDay) ?? startOfDay

        async let sleepTask = try? querySleepDuration(from: sleepWindowStart, to: date)
        async let rhrTask = try? queryRestingHeartRate(from: startOfDay, to: date)
        async let hrvTask = try? queryLatestHRV(from: startOfDay, to: date)

        let sleep = await sleepTask
        let restingHeartRate = await rhrTask
        let hrv = await hrvTask

        return (sleep ?? 0) > 0 || (restingHeartRate ?? 0) > 0 || (hrv ?? 0) > 0
    }

    nonisolated private static func displayName(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running:
            return "running"
        case .walking:
            return "walking"
        case .cycling:
            return "cycling"
        case .traditionalStrengthTraining:
            return "strength"
        case .highIntensityIntervalTraining:
            return "hiit"
        case .swimming:
            return "swimming"
        case .hiking:
            return "hiking"
        case .yoga:
            return "yoga"
        case .functionalStrengthTraining:
            return "functional_strength"
        default:
            return "workout"
        }
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable, typeNotAvailable, noData
    
    var errorDescription: String? {
        switch self {
        case .notAvailable: return "HealthKit 不可用"
        case .typeNotAvailable: return "数据类型不可用"
        case .noData: return "未找到数据"
        }
    }
}
