import CoreML
import Foundation

actor SplatAngleClassificationService {
    static let shared = SplatAngleClassificationService()

    private var model: MLModel?

    enum ClassificationError: Error {
        case missingModel
        case missingImageConstraint
        case missingProbability
    }

    func probability(for image: CGImage) throws -> Float {
        try Task.checkCancellation()
        let model: MLModel
        if let cachedModel = self.model {
            model = cachedModel
        } else {
            guard let url = Bundle.main.url(forResource: "SplatAngleClassifier", withExtension: "mlmodelc") else {
                throw ClassificationError.missingModel
            }
            model = try MLModel(contentsOf: url)
            self.model = model
        }
        try Task.checkCancellation()
        guard let constraint = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            throw ClassificationError.missingImageConstraint
        }
        let input = try MLFeatureValue(cgImage: image, constraint: constraint)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": input])
        try Task.checkCancellation()
        let output = try model.prediction(from: provider)
        try Task.checkCancellation()
        guard let value = output.featureValue(for: "classLabel_probs")?.dictionaryValue["good"] else {
            throw ClassificationError.missingProbability
        }
        return value.floatValue
    }
}
