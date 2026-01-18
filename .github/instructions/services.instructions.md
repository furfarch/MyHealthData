---
description: 'Service layer guidelines for MyHealthData - CloudKit, export, and business logic'
applyTo: 'MyHealthData/Services/**/*.swift'
---

# Services Layer

## Purpose

Services contain business logic, CloudKit operations, and utility functions that don't belong in Views or Models.

## Service Patterns

### CloudKit Services
- Use `CloudSyncService` for cloud synchronization
- Use `CloudKitManager` for CloudKit operations
- Handle CloudKit errors gracefully with appropriate fallback behavior
- Respect the per-record `isCloudEnabled` flag

### Export Services
- Use `ExportService` for exporting records
- Support both PDF and HTML export formats
- Use `PDFRenderer` (platform-specific: iOS or macOS version)
- Use `HTMLTemplateRenderer` for HTML generation

### Service Organization
```swift
import Foundation
import CloudKit
import SwiftData

final class MyService {
    // Dependencies
    private let modelContext: ModelContext?
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
    
    // Public API
    func performOperation() async throws {
        // Implementation
    }
    
    // Private helpers
    private func helperMethod() {
        // Implementation
    }
}
```

## Error Handling

Services should handle errors gracefully:

```swift
func performCloudOperation() async throws {
    do {
        // Attempt operation
    } catch let error as CKError {
        print("[ServiceName] CloudKit error: \(error)")
        throw error
    } catch {
        print("[ServiceName] Unexpected error: \(error)")
        throw error
    }
}
```

## Platform-Specific Code

When needed, use conditional compilation:

```swift
#if os(iOS)
// iOS-specific implementation
import UIKit
#elseif os(macOS)
// macOS-specific implementation
import AppKit
#endif
```

## CloudKit Best Practices

- Check `isCloudEnabled` before CloudKit operations
- Handle network errors and retries appropriately
- Respect CloudKit quota limits
- Use appropriate CloudKit zones (private vs shared)
- Track sharing state with `isSharingEnabled` and `cloudShareRecordName`

## Do

- Keep services focused and single-purpose
- Make services testable (dependency injection)
- Log errors with component prefix: `[ServiceName]`
- Handle async operations properly with async/await
- Provide clear error messages

## Don't

- Don't put UI code in services
- Don't access ModelContext directly from CloudKit callbacks without MainActor
- Don't expose CloudKit implementation details to Views
- Don't perform long-running operations synchronously
