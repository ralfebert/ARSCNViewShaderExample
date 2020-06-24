import ARKit
import os
import SwiftUI
import MetalKit

struct ARView: UIViewRepresentable {
    @Binding var shaderEnabled: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        context.coordinator.view = sceneView

        // Set the view's delegate
        sceneView.delegate = context.coordinator

        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true

        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!

        // Set the scene to the view
        sceneView.scene = scene

        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.delegate = context.coordinator
        sceneView.session.run(configuration)

        return sceneView
    }

    func updateUIView(_: ARSCNView, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(shaderEnabled: _shaderEnabled)
    }

    class Coordinator: NSObject, ARSessionDelegate, ARSCNViewDelegate {
        @Binding var shaderEnabled: Bool
        weak var view: ARSCNView? {
            didSet {
                self.textureLoader = MTKTextureLoader(device: view!.device!)
            }
        }
        var maskImage: CGImage?
        var maskLock = NSLock()
        var materialProperty = SCNMaterialProperty()
        var textureLoader : MTKTextureLoader!

        var queue: OperationQueue = {
            let queue = OperationQueue()
            queue.name = "Image processing"
            queue.qualityOfService = .userInteractive
            return queue
        }()

        init(shaderEnabled: Binding<Bool>) {
            _shaderEnabled = shaderEnabled
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // skip mask update if another operation is still running so the background queue can never get clogged with work
            if queue.operationCount > 0 {
                return
            }
            guard let view = self.view else { return }

            guard let frame = session.currentFrame else { return }
            guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else { return }
            let imageBuffer = frame.capturedImage

            let image = CIImage(cvImageBuffer: imageBuffer)
            let imageSize = CGSize(width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))
            let viewPort = view.bounds

            // ------------------------------------------------------
            // The camera image doesn't match the view rotation and aspect ratio
            // The following code transform the image to match the display in the ARSCNView
            // See also: https://stackoverflow.com/questions/58809070/transforming-arframecapturedimage-to-view-size/58817480#58817480

            // 1) Convert to "normalized image coordinates"
            let normalizeTransform = CGAffineTransform(scaleX: 1.0 / imageSize.width, y: 1.0 / imageSize.height)

            // 2) Flip the Y axis (for some mysterious reason this is only necessary in portrait mode)

            let flipTransform = interfaceOrientation.isPortrait ? CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: -1, y: -1) : .identity

            // 3) Apply the transformation provided by ARFrame
            // This transformation converts:
            // - From Normalized image coordinates (Normalized image coordinates range from (0,0) in the upper left corner of the image to (1,1) in the lower right corner)
            // - To view coordinates ("a coordinate space appropriate for rendering the camera image onscreen")
            // See also: https://developer.apple.com/documentation/arkit/arframe/2923543-displaytransform

            let displayTransform = frame.displayTransform(for: interfaceOrientation, viewportSize: viewPort.size)

            // 4) Convert to view size
            let toViewPortTransform = CGAffineTransform(scaleX: viewPort.size.width, y: viewPort.size.height)

            // Transform the image and crop it to the viewport
            let transformedImage = image
                .transformed(by: normalizeTransform
                    .concatenating(flipTransform)
                    .concatenating(displayTransform)
                    .concatenating(toViewPortTransform)
                )
                .cropped(to: viewPort)

            queue.addOperation {
                // in the actual project, here a mask for the sky is computed
                // for this simplified example project, it just computes a posterized grayscale image
                let maskImage = transformedImage
                    .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 2])
                    .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])

                let context = CIContext(options: nil)
                guard let maskCGImage = context.createCGImage(maskImage, from: maskImage.extent) else {
                    os_log("No mask image result", type: .error)
                    return
                }

                let width = 256
                let height = 256
                let imageRect: CGRect = CGRect(x: 0, y: 0, width: width, height: height)
                let colorSpace = CGColorSpaceCreateDeviceGray()

                let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                let cgContext = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)!
                cgContext.draw(maskCGImage, in: imageRect)
                let imageRef = cgContext.makeImage()

                // ------------------------------------------------------
                // Pass the mask to SceneKit
                // Access to maskImage is locked because Swift properties are not atomic
                // and this property is accessed from the bg thread and the SceneKit render thread
                self.maskLock.lock()
                self.maskImage = imageRef
                self.maskLock.unlock()
            }
        }

        func renderer(_: SCNSceneRenderer, willRenderScene _: SCNScene, atTime _: TimeInterval) {
            guard let view = self.view else { return }

            // Access to maskImage is locked because Swift properties are not atomic
            // and this property is accessed from the bg thread and the SceneKit render thread
            maskLock.lock()
            defer { self.maskLock.unlock() }

            if let maskImage = maskImage, self.shaderEnabled {
                // load SCNTechnique if not already loaded
                if view.technique == nil {
                    // Apply a SCNTechnique to post-process the SceneKit rendering
                    // using a metal fragment shader
                    view.technique = SCNTechnique(name: "mask_technique")
                }

                // set mask image as image sampler for shader
                let material = SCNMaterialProperty(contents: try! textureLoader.newTexture(cgImage: maskImage))
                view.technique?.setObject(material, forKeyedSubscript: "mask" as NSCopying)
                // view.technique?.setObject(maskImage, forKeyedSubscript: "mask" as NSCopying)
            } else {
                view.technique = nil
            }
        }
    }
}
