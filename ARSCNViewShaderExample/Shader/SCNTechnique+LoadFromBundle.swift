import os
import SceneKit

extension SCNTechnique {
    convenience init?(name: String, bundle: Bundle = Bundle.main) {
        guard let url = bundle.url(forResource: name, withExtension: "plist"), let techniqueDictionary = NSDictionary(contentsOf: url) as? [String: AnyObject] else {
            os_log("Could not load technique %{public}s dictionary", type: .error, name)
            return nil
        }
        self.init(dictionary: techniqueDictionary)
    }
}
