import Foundation

/// Which underlying data source a Result Measure's value comes from. Moved
/// here (out of ImprovementDashboardView.swift) so AddGoalValidation, which
/// needs it, stays buildable by the headless SPM package -- Views/ is
/// excluded from that target.
enum ResultSource: String, CaseIterable, Identifiable {
    case manual = "Manual check-in"
    case activityMeasurement = "Activity measurement"
    case nutritionMetric = "Nutrition"
    case bodyMetric = "Body metric"
    var id: String { rawValue }
}

/// Pure validation rules for the 3-step Add Goal flow (AddGoalView,
/// ImprovementDashboardView.swift), extracted out of the View so its
/// empty-input and result-source gating is unit-testable.
enum AddGoalValidation {
    static func canSave(
        name: String,
        measureName: String,
        selectedAreaIDs: Set<UUID>,
        valueType: ResultValueType,
        direction: ResultDirection,
        baseline: Double,
        target: Double,
        minimum: Double,
        maximum: Double,
        resultSource: ResultSource,
        selectedMeasurementDefinitionID: UUID?,
        selectedNutritionMetric: NutritionEngine.Metric?,
        selectedBodyMetricDefinitionID: UUID?
    ) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !measureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedAreaIDs.isEmpty else { return false }

        let isFreeform = valueType == .text || valueType == .milestone
        guard isFreeform || ResultMeasureValidation.isValidTarget(
            valueType: valueType, direction: direction, baseline: baseline,
            target: target, minimum: minimum, maximum: maximum
        ) else { return false }

        switch resultSource {
        case .manual:
            return true
        case .activityMeasurement:
            return isFreeform || selectedMeasurementDefinitionID != nil
        case .nutritionMetric:
            return isFreeform || selectedNutritionMetric != nil
        case .bodyMetric:
            return isFreeform || selectedBodyMetricDefinitionID != nil
        }
    }
}
