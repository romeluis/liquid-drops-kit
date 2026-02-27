# LiquidDropsKit

A Swift Package that provides `LiquidDrop`, `LiquidDrops`, and `.liquidDropsHost()` for liquid-glass toast notifications.

## Add to an Xcode app

1. In Xcode: `File` -> `Add Package Dependencies...`
2. Click `Add Local...`
3. Select this folder: `LiquidDropsKit`
4. Add product `LiquidDropsKit` to your app target.

## Use

```swift
import SwiftUI
import LiquidDropsKit

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .liquidDropsHost()
        }
    }
}
```

```swift
LiquidDrops.show(
    LiquidDrop(
        title: "Copied",
        subtitle: "Paste anywhere",
        duration: .recommended,
        effectStyle: .clear
    )
)
```
