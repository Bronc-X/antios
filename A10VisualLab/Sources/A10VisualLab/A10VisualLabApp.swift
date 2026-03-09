import SwiftUI

@main
struct A10VisualLabApp: App {
    var body: some Scene {
        WindowGroup {
            A10VisualSystemShowcase(language: .zhHans)
                .frame(minWidth: 480, minHeight: 960)
        }
        .windowResizability(.contentSize)
    }
}
