---
description: 'SwiftUI view guidelines for MyHealthData'
applyTo: 'MyHealthData/Views/**/*.swift'
---

# SwiftUI Views

## Required Patterns

### View Structure
- Keep views focused and single-purpose
- Extract complex UI into separate view components
- Use descriptive view names that indicate their purpose

### Data Access
```swift
@Environment(\.modelContext) private var modelContext
@Query private var records: [MedicalRecord]
```

### State Management
- Use `@State` for view-local mutable state
- Use `@Binding` for two-way data flow with parent views
- Use `@Environment` for accessing system/app-wide values
- Use `@Query` for fetching SwiftData models

### Main Actor
- Mark views as `@MainActor` if they perform UI-critical async operations
- ModelContext operations should happen on MainActor when used in views

## Preview Providers

Always provide previews for views using the `#Preview` macro:

```swift
#Preview {
    MyView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
```

For views with bindings:
```swift
#Preview {
    @Previewable @State var isPresented = true
    MySheet(isPresented: $isPresented)
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
```

## Conditional Rendering

Account for both human and pet records:
```swift
if record.isPet {
    // Pet-specific UI
    Text(record.personalName)
} else {
    // Human-specific UI
    Text("\(record.personalGivenName) \(record.personalFamilyName)")
}
```

Or use the computed property:
```swift
Text(record.displayName)
```

## Do

- Use computed properties for derived UI state
- Leverage SwiftUI's declarative syntax
- Keep view files focused on UI, delegate logic to Services
- Handle loading and error states gracefully
- Use appropriate form controls (TextField, DatePicker, Toggle, etc.)

## Don't

- Don't put business logic in views
- Don't perform heavy computation in body (use computed properties or @State)
- Don't forget to save ModelContext after changes
- Don't mix UIKit and SwiftUI unnecessarily
