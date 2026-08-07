import Foundation
import UIKit
import Vision
import VisionKit
import SwiftUI

struct ScannedNutritionProduct: Sendable {
    let name: String
    let calories: Double
    let proteinGrams: Double
    let carbohydrateGrams: Double
    let fatGrams: Double
    let basisDescription: String
}

enum FoodProductLookupError: LocalizedError {
    case invalidBarcode
    case productNotFound
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: return "Enter or scan a valid barcode."
        case .productNotFound: return "This barcode was not found. You can still enter nutrition manually."
        case .unavailable: return "Nutrition lookup is unavailable right now. Check your internet connection or enter it manually."
        }
    }
}

enum FoodProductService {
    static func lookup(barcode: String) async throws -> ScannedNutritionProduct {
        let code = barcode.filter(\.isNumber)
        guard code.count >= 8 else { throw FoodProductLookupError.invalidBarcode }

        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "code,product_name,brands,serving_size,nutriments")
        ]
        guard let url = components.url else { throw FoodProductLookupError.invalidBarcode }

        var request = URLRequest(url: url)
        request.setValue("LifeOS/1.0 (https://github.com/sirishdittakavi/LifeOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw FoodProductLookupError.unavailable
            }
            let result = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
            guard result.status == 1, let product = result.product else {
                throw FoodProductLookupError.productNotFound
            }

            let nutrition = product.nutriments ?? .empty
            let hasServingNutrition = nutrition.energyKcalServing != nil || nutrition.proteinsServing != nil ||
                nutrition.carbohydratesServing != nil || nutrition.fatServing != nil
            let name = [product.productName, product.brands]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " — ")

            return ScannedNutritionProduct(
                name: name.isEmpty ? "Scanned food" : name,
                calories: hasServingNutrition ? (nutrition.energyKcalServing ?? 0) : (nutrition.energyKcal100g ?? 0),
                proteinGrams: hasServingNutrition ? (nutrition.proteinsServing ?? 0) : (nutrition.proteins100g ?? 0),
                carbohydrateGrams: hasServingNutrition ? (nutrition.carbohydratesServing ?? 0) : (nutrition.carbohydrates100g ?? 0),
                fatGrams: hasServingNutrition ? (nutrition.fatServing ?? 0) : (nutrition.fat100g ?? 0),
                basisDescription: hasServingNutrition ? (product.servingSize ?? "one serving") : "100 g"
            )
        } catch let error as FoodProductLookupError {
            throw error
        } catch {
            throw FoodProductLookupError.unavailable
        }
    }
}

private struct OpenFoodFactsResponse: Decodable {
    let status: Int?
    let product: OpenFoodFactsProduct?
}

private struct OpenFoodFactsProduct: Decodable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let nutriments: OpenFoodFactsNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case nutriments
    }
}

private struct OpenFoodFactsNutriments: Decodable {
    let energyKcalServing: Double?
    let energyKcal100g: Double?
    let proteinsServing: Double?
    let proteins100g: Double?
    let carbohydratesServing: Double?
    let carbohydrates100g: Double?
    let fatServing: Double?
    let fat100g: Double?

    static let empty = OpenFoodFactsNutriments(
        energyKcalServing: nil, energyKcal100g: nil,
        proteinsServing: nil, proteins100g: nil,
        carbohydratesServing: nil, carbohydrates100g: nil,
        fatServing: nil, fat100g: nil
    )

    enum CodingKeys: String, CodingKey {
        case energyKcalServing = "energy-kcal_serving"
        case energyKcal100g = "energy-kcal_100g"
        case proteinsServing = "proteins_serving"
        case proteins100g = "proteins_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case fatServing = "fat_serving"
        case fat100g = "fat_100g"
    }
}

struct RecognizedNutrition: Sendable {
    let calories: Double?
    let proteinGrams: Double?
    let carbohydrateGrams: Double?
    let fatGrams: Double?

    var foundAnyValue: Bool {
        calories != nil || proteinGrams != nil || carbohydrateGrams != nil || fatGrams != nil
    }
}

enum NutritionLabelRecognizer {
    static func recognize(imageData: Data) async throws -> RecognizedNutrition {
        let text = try await recognizeText(imageData: imageData)
        return RecognizedNutrition(
            calories: firstNumber(patterns: [
                #"([0-9]+(?:\.[0-9]+)?)\s*kcal"#,
                #"calories?[^0-9]{0,12}([0-9]+(?:\.[0-9]+)?)"#
            ], in: text),
            proteinGrams: firstNumber(patterns: [
                #"protein[^0-9]{0,14}([0-9]+(?:\.[0-9]+)?)\s*g"#
            ], in: text),
            carbohydrateGrams: firstNumber(patterns: [
                #"(?:total\s+)?carbohydrates?[^0-9]{0,14}([0-9]+(?:\.[0-9]+)?)\s*g"#,
                #"carbs?[^0-9]{0,14}([0-9]+(?:\.[0-9]+)?)\s*g"#
            ], in: text),
            fatGrams: firstNumber(patterns: [
                #"(?:total\s+)?fat[^0-9]{0,14}([0-9]+(?:\.[0-9]+)?)\s*g"#
            ], in: text)
        )
    }

    private static func recognizeText(imageData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n").lowercased())
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                try VNImageRequestHandler(data: imageData).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func firstNumber(patterns: [String], in text: String) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text),
                  let value = Double(text[range]) else { continue }
            return value
        }
        return nil
    }
}

struct BarcodeScannerSheet: View {
    let onBarcode: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BarcodeScannerView(onBarcode: onBarcode)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Scanner Unavailable",
                        systemImage: "barcode.viewfinder",
                        description: Text("Use a physical iPhone, or enter the barcode manually.")
                    )
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void
        var hasReturnedBarcode = false

        init(onBarcode: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasReturnedBarcode else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }
                hasReturnedBarcode = true
                dataScanner.stopScanning()
                onBarcode(payload)
                return
            }
        }
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) } else { onCancel() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

enum FoodImageProcessor {
    static func jpegData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1600
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.78)
    }
}
