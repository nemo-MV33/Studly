import SwiftUI

@main
struct FirstApp: App {
    @AppStorage("hasSeenHello") var hasSeenHello: Bool = false

    var body: some Scene {
        WindowGroup {
            if hasSeenHello {
                MainView()
            } else {
                HelloView()
            }
        }
    }
}
