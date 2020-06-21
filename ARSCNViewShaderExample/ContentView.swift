import SwiftUI

struct ContentView: View {
    @State var shaderEnabled = true

    var body: some View {
        ARView(shaderEnabled: $shaderEnabled)
            .overlay(Toggle(isOn: $shaderEnabled) {
                Text("Shader enabled")
            }, alignment: .topTrailing)
    }
}
