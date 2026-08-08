import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct FoodTrackerView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
    @State private var showingAddEntry = false
    @State private var showingGoals = false

    private var todayEntries: [FoodEntry] {
        guard let profile = selection.profile else { return [] }
        return entries.filter {
            $0.profile?.id == profile.id && Calendar.current.isDateInToday($0.date)
        }
    }

    private var totals: (calories: Double, protein: Double, carbs: Double, fat: Double, water: Double) {
        todayEntries.reduce(into: (0, 0, 0, 0, 0)) { result, entry in
            result.0 += entry.calories
            result.1 += entry.proteinGrams
            result.2 += entry.carbohydrateGrams
            result.3 += entry.fatGrams
            result.4 += entry.waterMilliliters
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NutritionSummary(totals: totals, profile: selection.profile)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Today's food") {
                    if todayEntries.isEmpty {
                        ContentUnavailableView(
                            "No Food Logged",
                            systemImage: "fork.knife",
                            description: Text("Tap + to record a meal, snack, drink or water.")
                        )
                    } else {
                        ForEach(todayEntries) { entry in
                            FoodEntryRow(entry: entry)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfilePicker(selection: selection)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingGoals = true } label: {
                        Image(systemName: "target")
                    }
                    .disabled(selection.profile == nil)
                    Button { showingAddEntry = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(selection.profile == nil)
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                if let profile = selection.profile {
                    AddFoodEntryView(profile: profile)
                }
            }
            .sheet(isPresented: $showingGoals) {
                if let profile = selection.profile {
                    ProfileGoalsView(profile: profile)
                }
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        offsets.map { todayEntries[$0] }.forEach(modelContext.delete)
        modelContext.saveOrReport()
    }
}

private struct NutritionSummary: View {
    let totals: (calories: Double, protein: Double, carbs: Double, fat: Double, water: Double)
    let profile: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TODAY'S NUTRITION")
                .font(.caption).bold().foregroundStyle(.secondary)
            HStack(spacing: 8) {
                NutritionMetric(value: totals.calories, target: profile?.calorieGoal ?? 0, unit: "kcal", color: .orange)
                NutritionMetric(value: totals.protein, target: profile?.proteinGoalGrams ?? 0, unit: "protein g", color: .red)
                NutritionMetric(value: totals.carbs, target: profile?.carbohydrateGoalGrams ?? 0, unit: "carbs g", color: .blue)
            }
            HStack(spacing: 8) {
                NutritionMetric(value: totals.fat, target: profile?.fatGoalGrams ?? 0, unit: "fat g", color: .purple)
                NutritionMetric(value: totals.water, target: profile?.waterGoalMilliliters ?? 0, unit: "water ml", color: .cyan)
            }
        }
        .padding()
    }
}

private struct NutritionMetric: View {
    let value: Double
    let target: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(value))").font(.title3).bold().foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
            if target > 0 {
                ProgressView(value: min(value / target, 1))
                    .tint(color)
                Text("of \(Int(target))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.headline)
                        Text("\(entry.mealType.rawValue) · \(entry.servings.formatted(.number.precision(.fractionLength(0...2)))) serving(s) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(entry.calories)) kcal").font(.subheadline).bold()
                }
                Text("P \(Int(entry.proteinGrams))g · C \(Int(entry.carbohydrateGrams))g · F \(Int(entry.fatGrams))g · Water \(Int(entry.waterMilliliters))ml")
                    .font(.caption2).foregroundStyle(.secondary)
                Label(entry.nutritionSource, systemImage: entry.barcode == nil ? "square.and.pencil" : "barcode")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AddFoodEntryView: View {
    let profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var mealType: MealType = .breakfast
    @State private var name = ""
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var water = 0.0
    @State private var note = ""
    @State private var barcode = ""
    @State private var nutritionSource = "Manual"
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingBarcodeScanner = false
    @State private var showingCamera = false
    @State private var isLookingUpBarcode = false
    @State private var isRecognizingPhoto = false
    @State private var captureStatus: String?
    @State private var servings = 1.0
    @State private var barcodeNutritionBase: ScannedNutritionProduct?

    var body: some View {
        NavigationStack {
            Form {
                Section("Scan or photo") {
                    Button {
                        showingBarcodeScanner = true
                    } label: {
                        Label("Scan Product Barcode", systemImage: "barcode.viewfinder")
                    }

                    HStack {
                        TextField("Enter barcode manually", text: $barcode)
                            .keyboardType(.numberPad)
                        Button("Look Up") { lookupBarcode() }
                            .disabled(barcode.filter(\.isNumber).count < 8 || isLookingUpBarcode)
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Label or Food Photo", systemImage: "photo")
                    }

                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Label or Food Photo", systemImage: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    if let data = photoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if isLookingUpBarcode || isRecognizingPhoto {
                        HStack {
                            ProgressView()
                            Text(isLookingUpBarcode ? "Looking up nutrition…" : "Reading nutrition label…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let captureStatus {
                        Text(captureStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Meal") {
                    Picker("Type", selection: $mealType) {
                        ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Food or drink", text: $name)
                    Stepper("Servings: \(servings.formatted(.number.precision(.fractionLength(0...2))))",
                            value: $servings, in: 0.25...20, step: 0.25)
                    DatePicker("Time", selection: $date)
                }
                Section("Nutrition") {
                    numberField("Calories", value: $calories, suffix: "kcal")
                    numberField("Protein", value: $protein, suffix: "g")
                    numberField("Carbohydrates", value: $carbs, suffix: "g")
                    numberField("Fat", value: $fat, suffix: "g")
                    numberField("Water", value: $water, suffix: "ml")
                }
                Section("Notes") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: selectedPhoto) {
                loadSelectedPhoto()
            }
            .onChange(of: servings) {
                applyBarcodeNutritionForServingCount()
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerSheet(
                    onBarcode: { scannedCode in
                        barcode = scannedCode
                        showingBarcodeScanner = false
                        lookupBarcode()
                    },
                    onCancel: { showingBarcodeScanner = false }
                )
            }
            .sheet(isPresented: $showingCamera) {
                CameraImagePicker(
                    onImage: { image in
                        showingCamera = false
                        useImage(image)
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(suffix).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let entry = FoodEntry(
            profile: profile, date: date, mealType: mealType,
            name: name.trimmingCharacters(in: .whitespaces), calories: calories,
            proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat,
            waterMilliliters: water, note: note,
            barcode: barcode.isEmpty ? nil : barcode,
            nutritionSource: nutritionSource,
            photoData: photoData,
            servings: servings
        )
        modelContext.insert(entry)
        if modelContext.saveOrReport() { dismiss() }
        else { modelContext.delete(entry) }
    }

    private func lookupBarcode() {
        isLookingUpBarcode = true
        captureStatus = nil
        Task {
            do {
                let product = try await FoodProductService.lookup(barcode: barcode)
                name = product.name
                barcodeNutritionBase = product
                servings = 1
                applyBarcodeNutritionForServingCount()
                nutritionSource = "Barcode · Open Food Facts (\(product.basisDescription))"
                captureStatus = "Nutrition filled for \(product.basisDescription). Review the values, then save."
            } catch {
                captureStatus = error.localizedDescription
            }
            isLookingUpBarcode = false
        }
    }

    private func loadSelectedPhoto() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                captureStatus = "The selected photo could not be loaded."
                return
            }
            useImage(image)
        }
    }

    private func useImage(_ image: UIImage) {
        guard let data = FoodImageProcessor.jpegData(from: image) else {
            captureStatus = "The photo could not be prepared."
            return
        }
        photoData = data
        barcodeNutritionBase = nil
        servings = 1
        recognizeNutritionLabel(in: data)
    }

    private func recognizeNutritionLabel(in data: Data) {
        isRecognizingPhoto = true
        captureStatus = nil
        Task {
            do {
                let result = try await NutritionLabelRecognizer.recognize(imageData: data)
                if let value = result.calories { calories = value }
                if let value = result.proteinGrams { protein = value }
                if let value = result.carbohydrateGrams { carbs = value }
                if let value = result.fatGrams { fat = value }
                if result.foundAnyValue {
                    nutritionSource = "Nutrition label photo"
                    captureStatus = "Nutrition values extracted from the label. Review them before saving."
                } else {
                    captureStatus = "Photo saved. No nutrition label was detected, so enter values manually."
                }
            } catch {
                captureStatus = "Photo saved, but the label could not be read. Enter nutrition manually."
            }
            isRecognizingPhoto = false
        }
    }

    private func applyBarcodeNutritionForServingCount() {
        guard let product = barcodeNutritionBase else { return }
        calories = product.calories * servings
        protein = product.proteinGrams * servings
        carbs = product.carbohydrateGrams * servings
        fat = product.fatGrams * servings
    }
}
