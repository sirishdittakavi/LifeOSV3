import Foundation

/// Pure validation rules for guided first-time setup (LifeOSOnboardingView,
/// RootTabView.swift), extracted out of the private View so its
/// empty-input/plan/task rejection behavior is unit-testable.
enum OnboardingValidation {
    static func canContinueFromIntent(_ improvementText: String) -> Bool {
        !improvementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canContinueFromOutcome(
        outcomeName: String,
        valueType: ResultValueType,
        direction: ResultDirection,
        target: Double,
        minimum: Double,
        maximum: Double
    ) -> Bool {
        guard !outcomeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if valueType == .milestone || valueType == .text { return true }
        // Onboarding always starts a fresh Goal with an implicit baseline of
        // 0 -- there is no prior check-in to read a baseline from yet.
        return ResultMeasureValidation.isValidTarget(
            valueType: valueType, direction: direction,
            baseline: 0, target: target, minimum: minimum, maximum: maximum
        )
    }

    static func canCreate(areaName: String, taskNamesAndWeekdays: [(name: String, weekdays: Set<Int>)]) -> Bool {
        guard !areaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !taskNamesAndWeekdays.isEmpty else { return false }
        return taskNamesAndWeekdays.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.weekdays.isEmpty
        }
    }
}
