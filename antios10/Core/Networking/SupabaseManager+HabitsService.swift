import Foundation

// MARK: - Habits Service
extension SupabaseManager {
    struct HabitStatus: Identifiable, Equatable {
        let id: String
        let title: String
        let description: String?
        let minResistanceLevel: Int?
        var isCompleted: Bool
    }

    private struct HabitRowV2: Codable {
        let id: FlexibleId
        let title: String
        let description: String?
        let min_resistance_level: Int?
        let created_at: String?
    }

    private struct HabitRowLegacy: Codable {
        let id: FlexibleId
        let habit_name: String
        let cue: String?
        let response: String?
        let reward: String?
        let belief_score: Int?
        let created_at: String?
    }

    private struct HabitCompletionRow: Codable {
        let habit_id: FlexibleId
        let completed_at: String?
    }

    func getHabitsForToday(referenceDate: Date = Date()) async throws -> [HabitStatus] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let backend = await resolveHabitsBackend(userId: user.id)
        var habits = try await fetchHabits(backend: backend, userId: user.id)
        if habits.isEmpty {
            habits = try await seedDefaultHabits(backend: backend, userId: user.id)
        }

        let completedIds = try await fetchHabitCompletionIds(
            backend: backend,
            userId: user.id,
            referenceDate: referenceDate
        )

        if !completedIds.isEmpty {
            let completedSet = Set(completedIds)
            habits = habits.map { habit in
                var updated = habit
                updated.isCompleted = completedSet.contains(habit.id)
                return updated
            }
        }

        return habits
    }

    func setHabitCompletion(habitId: String, isCompleted: Bool, referenceDate: Date = Date()) async throws {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        let backend = await resolveHabitsBackend(userId: user.id)

        let (start, end) = dayRange(for: referenceDate)
        let habitValue = habitIdPayloadValue(habitId)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        switch backend {
        case .v2:
            if isCompleted {
                let payload: [String: AnyCodable] = [
                    "user_id": AnyCodable(user.id),
                    "habit_id": habitValue,
                    "completed_at": AnyCodable(dateFormatter.string(from: referenceDate))
                ]
                try await requestVoid("habit_completions", method: "POST", body: payload, prefer: "return=representation")
            } else {
                let endpoint = "habit_completions?user_id=eq.\(user.id)&habit_id=eq.\(habitId)&completed_at=gte.\(start)&completed_at=lt.\(end)"
                try await requestVoid(endpoint, method: "DELETE", body: nil, prefer: nil)
            }
        case .legacy:
            if isCompleted {
                let payload: [String: AnyCodable] = [
                    "habit_id": habitValue,
                    "completed_at": AnyCodable(dateFormatter.string(from: referenceDate))
                ]
                try await requestVoid("habit_log", method: "POST", body: payload, prefer: "return=representation")
            } else {
                let endpoint = "habit_log?habit_id=eq.\(habitId)&completed_at=gte.\(start)&completed_at=lt.\(end)"
                try await requestVoid(endpoint, method: "DELETE", body: nil, prefer: nil)
            }
        }

        await captureUserSignal(
            domain: "habits",
            action: isCompleted ? "completed" : "uncompleted",
            summary: "habit \(habitId) -> \(isCompleted ? "done" : "undone")",
            metadata: [
                "habit_id": habitId,
                "completed": isCompleted,
                "backend": (backend == .v2 ? "v2" : "legacy")
            ]
        )
    }

    private func resolveHabitsBackend(userId: String) async -> HabitsBackend {
        if let cached = habitsBackendCache {
            return cached
        }
        do {
            let _: [HabitRowV2] = try await request("habits?user_id=eq.\(userId)&select=id&limit=1")
            habitsBackendCache = .v2
            return .v2
        } catch {
            habitsBackendCache = .legacy
            return .legacy
        }
    }

    private func fetchHabits(backend: HabitsBackend, userId: String) async throws -> [HabitStatus] {
        switch backend {
        case .v2:
            let endpoint = "habits?user_id=eq.\(userId)&select=id,title,description,min_resistance_level,created_at&order=created_at.asc"
            let rows: [HabitRowV2] = try await request(endpoint)
            return rows.map { row in
                HabitStatus(
                    id: row.id.value,
                    title: row.title,
                    description: row.description,
                    minResistanceLevel: row.min_resistance_level,
                    isCompleted: false
                )
            }
        case .legacy:
            let endpoint = "user_habits?user_id=eq.\(userId)&select=id,habit_name,cue,response,reward,belief_score,created_at&order=created_at.asc"
            do {
                let rows: [HabitRowLegacy] = try await request(endpoint)
                return rows.map { row in
                    let description = [row.cue, row.response, row.reward].compactMap { $0 }.first
                    return HabitStatus(
                        id: row.id.value,
                        title: row.habit_name,
                        description: description,
                        minResistanceLevel: row.belief_score,
                        isCompleted: false
                    )
                }
            } catch {
                let fallbackEndpoint = "user_habits?user_id=eq.\(userId)&select=id,habit_name,cue,response,reward,created_at&order=created_at.asc"
                let rows: [HabitRowLegacy] = try await request(fallbackEndpoint)
                return rows.map { row in
                    let description = [row.cue, row.response, row.reward].compactMap { $0 }.first
                    return HabitStatus(
                        id: row.id.value,
                        title: row.habit_name,
                        description: description,
                        minResistanceLevel: nil,
                        isCompleted: false
                    )
                }
            }
        }
    }

    private func seedDefaultHabits(backend: HabitsBackend, userId: String) async throws -> [HabitStatus] {
        let defaults = defaultHabitTemplates()
        switch backend {
        case .v2:
            for habit in defaults {
                let payload: [String: AnyCodable] = [
                    "user_id": AnyCodable(userId),
                    "title": AnyCodable(habit.title),
                    "description": AnyCodable(habit.description ?? ""),
                    "min_resistance_level": AnyCodable(habit.minResistanceLevel ?? 3)
                ]
                let _: [[String: AnyCodable]]? = try? await request("habits", method: "POST", body: payload, prefer: "return=representation")
            }
        case .legacy:
            for habit in defaults {
                let payload: [String: AnyCodable] = [
                    "user_id": AnyCodable(userId),
                    "habit_name": AnyCodable(habit.title),
                    "cue": AnyCodable(habit.description ?? ""),
                    "belief_score": AnyCodable(habit.minResistanceLevel ?? 3)
                ]
                let inserted: [[String: AnyCodable]]? = try? await request("user_habits", method: "POST", body: payload, prefer: "return=representation")
                if inserted == nil {
                    let fallbackPayload: [String: AnyCodable] = [
                        "user_id": AnyCodable(userId),
                        "habit_name": AnyCodable(habit.title),
                        "cue": AnyCodable(habit.description ?? "")
                    ]
                    let _: [[String: AnyCodable]]? = try? await request("user_habits", method: "POST", body: fallbackPayload, prefer: "return=representation")
                }
            }
        }
        return try await fetchHabits(backend: backend, userId: userId)
    }

    private func defaultHabitTemplates() -> [HabitStatus] {
        [
            HabitStatus(id: UUID().uuidString, title: "补水 2000ml", description: "保持全天水分摄入", minResistanceLevel: 2, isCompleted: false),
            HabitStatus(id: UUID().uuidString, title: "完成 5 分钟呼吸", description: "降低紧张水平", minResistanceLevel: 1, isCompleted: false),
            HabitStatus(id: UUID().uuidString, title: "完成 20 分钟运动", description: "提升能量与心率变异性", minResistanceLevel: 3, isCompleted: false),
            HabitStatus(id: UUID().uuidString, title: "22:30 前入睡", description: "稳定昼夜节律", minResistanceLevel: 3, isCompleted: false)
        ]
    }

    private func fetchHabitCompletionIds(
        backend: HabitsBackend,
        userId: String,
        referenceDate: Date
    ) async throws -> [String] {
        let (start, end) = dayRange(for: referenceDate)
        let endpoint: String
        switch backend {
        case .v2:
            endpoint = "habit_completions?user_id=eq.\(userId)&completed_at=gte.\(start)&completed_at=lt.\(end)&select=habit_id"
        case .legacy:
            endpoint = "habit_log?completed_at=gte.\(start)&completed_at=lt.\(end)&select=habit_id"
        }

        let rows: [HabitCompletionRow] = (try? await request(endpoint)) ?? []
        return rows.map { $0.habit_id.value }
    }

    private func dayRange(for date: Date) -> (String, String) {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        return (start, end)
    }

    private func habitIdPayloadValue(_ habitId: String) -> AnyCodable {
        if let intValue = Int(habitId) {
            return AnyCodable(intValue)
        }
        return AnyCodable(habitId)
    }
}
