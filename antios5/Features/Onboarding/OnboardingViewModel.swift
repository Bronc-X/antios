// OnboardingViewModel.swift
// 引导流程视图模型 - 对齐 Web 端 useOnboarding Hook
//
// 功能对照:
// - Web: hooks/domain/useOnboarding.ts + app/actions/onboarding.ts
// - iOS: 本文件

import SwiftUI

// MARK: - Onboarding Types

struct OnboardingProgress: Equatable {
    var currentStep: Int
    var totalSteps: Int
    var completedSteps: [Int]
    var isComplete: Bool
}

struct OnboardingData: Codable {
    // 步骤 1: 基本信息
    var name: String?
    var age: Int?
    var gender: String?
    
    // 步骤 2: 反焦虑目标
    var primaryGoal: String?
    var concerns: [String]?
    
    // 步骤 3: 日常与触发因素
    var sleepHours: Double?
    var exerciseFrequency: String?
    var stressLevel: Int?
    
    // 步骤 4: 偏好设置
    var notificationEnabled: Bool?
    var dailyCheckinTime: String?
    var language: String?
}

// MARK: - API DTOs

private struct OnboardingProgressDTO: Codable {
    let current_step: Int
    let total_steps: Int
    let completed_steps: [Int]
    let is_complete: Bool
}

private struct SaveStepDTO: Codable {
    let step: Int
    let data: [String: String]
}

// MARK: - ViewModel

@MainActor
class OnboardingViewModel: ObservableObject {
    
    // MARK: - Published State (对齐 useOnboarding)
    
    @Published var progress = OnboardingProgress(
        currentStep: 1,
        totalSteps: 5,
        completedSteps: [],
        isComplete: false
    )
    @Published var currentStep: Int = 1
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var onboardingData = OnboardingData()
    
    // MARK: - Computed Properties
    
    var isComplete: Bool {
        progress.isComplete
    }
    
    // MARK: - Dependencies
    
    private let supabase = SupabaseManager.shared
    
    // MARK: - Load Progress
    
    func loadProgress() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        guard supabase.currentUser != nil else { return }
        
        do {
            let (data, response) = try await supabase.requestAppAPIRaw(
                path: "api/onboarding/progress",
                method: "GET",
                timeout: 7,
                contentType: nil
            )
            guard (200...299).contains(response.statusCode) else {
                return
            }
            
            let dto = try JSONDecoder().decode(OnboardingProgressDTO.self, from: data)
            
            progress = OnboardingProgress(
                currentStep: dto.current_step,
                totalSteps: dto.total_steps,
                completedSteps: dto.completed_steps,
                isComplete: dto.is_complete
            )
            currentStep = dto.current_step
        } catch {
            print("[Onboarding] Load progress error: \(error)")
        }
    }
    
    // MARK: - Save Step
    
    func saveStep(_ data: [String: String]) async -> Bool {
        isSaving = true
        error = nil
        defer { isSaving = false }
        
        do {
            let dto = SaveStepDTO(step: currentStep, data: data)
            let payload = try JSONEncoder().encode(dto)
            
            print("[Onboarding] 📤 发送步骤 \(currentStep) 数据...")
            
            let (responseData, response) = try await supabase.requestAppAPIRaw(
                path: "api/onboarding/save-step",
                method: "POST",
                body: payload,
                timeout: 8
            )
            guard (200...299).contains(response.statusCode) else {
                throw OnboardingError.requestFailed
            }
            
            if let progressDTO = try? JSONDecoder().decode(OnboardingProgressDTO.self, from: responseData) {
                progress = OnboardingProgress(
                    currentStep: progressDTO.current_step,
                    totalSteps: progressDTO.total_steps,
                    completedSteps: progressDTO.completed_steps,
                    isComplete: progressDTO.is_complete
                )
                currentStep = progressDTO.current_step
            }
            
            return true
        } catch {
            self.error = error.localizedDescription
            print("[Onboarding] Save step error: \(error)")
            return false
        }
    }
    
    // MARK: - Navigation
    
    func nextStep() {
        if currentStep < progress.totalSteps {
            currentStep += 1
        }
    }
    
    func prevStep() {
        if currentStep > 1 {
            currentStep -= 1
        }
    }
    
    // MARK: - Skip Onboarding
    
    func skip() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        
        do {
            let (_, response) = try await supabase.requestAppAPIRaw(
                path: "api/onboarding/skip",
                method: "POST",
                timeout: 7
            )
            guard (200...299).contains(response.statusCode) else {
                return false
            }
            
            progress.isComplete = true
            return true
        } catch {
            print("[Onboarding] Skip error: \(error)")
            return false
        }
    }
    
    // MARK: - Reset Onboarding
    
    func reset() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        
        do {
            let (_, response) = try await supabase.requestAppAPIRaw(
                path: "api/onboarding/reset",
                method: "POST",
                timeout: 7
            )
            guard (200...299).contains(response.statusCode) else {
                return false
            }
            
            progress = OnboardingProgress(
                currentStep: 1,
                totalSteps: 5,
                completedSteps: [],
                isComplete: false
            )
            currentStep = 1
            onboardingData = OnboardingData()
            return true
        } catch {
            print("[Onboarding] Reset error: \(error)")
            return false
        }
    }
    
}

// MARK: - Error

enum OnboardingError: LocalizedError {
    case missingApiUrl
    case requestFailed
    
    var errorDescription: String? {
        switch self {
        case .missingApiUrl: return "未配置 APP_API_BASE_URL"
        case .requestFailed: return "请求失败"
        }
    }
}
