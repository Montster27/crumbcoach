import WidgetKit
import SwiftUI

// Widget extension entry. Returns the widgets we vend — currently just
// the in-progress bake Live Activity. Home Screen / Lock Screen
// complications (Stage 19) will register here when they land.

@main
struct GeekBreadWidgetsBundle: WidgetBundle {
    var body: some Widget {
        #if !targetEnvironment(macCatalyst)
        ActiveBakeLiveActivity()
        #endif
        ActiveBakeWidget()
    }
}
