import SwiftUI
import Playgrounds

struct ContentView: View {
    let services: AppServices

    var body: some View {
        BandStatusView(services: services)
    }
}

#Playground {
    _ = 1 + 2
}
