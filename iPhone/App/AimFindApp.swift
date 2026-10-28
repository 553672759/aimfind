// AimFind — App 入口（@main）：单页面，无 Tab、无引导、无服务装配。

import SwiftUI

@main
struct AimFindApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
