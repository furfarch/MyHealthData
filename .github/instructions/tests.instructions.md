---
description: 'Testing guidelines for MyHealthData using Swift Testing framework'
applyTo: 'MyHealthDataTests/**/*.swift'
---

# Testing Guidelines

## Test Framework

Use Swift Testing framework, NOT XCTest:
- Use `@Test` macro for test functions
- Use `#expect()` for assertions (not XCTAssert)
- Import with `@testable import MyHealthData`

## Test Structure

```swift
import Testing
import Foundation
import SwiftData
@testable import MyHealthData

struct MyFeatureTests {
    @Test func testBasicBehavior() async throws {
        // Test implementation
    }
    
    @Test @MainActor func testWithModelContext() async throws {
        // Test implementation
    }
}
```

## Testing Patterns

### Testing Models
```swift
@Test func testModelProperty() async throws {
    let record = MedicalRecord()
    record.personalGivenName = "John"
    #expect(record.personalGivenName == "John")
}
```

### Testing Persistence
```swift
@Test @MainActor func testPersistence() async throws {
    let schema = Schema([MedicalRecord.self])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        cloudKitDatabase: .none
    )
    
    let testUUID = "TEST-\(UUID().uuidString)"
    
    // First container - create and save
    do {
        let container1 = try ModelContainer(for: schema, configurations: [config])
        let context1 = container1.mainContext
        
        let record = MedicalRecord()
        record.uuid = testUUID
        record.personalGivenName = "Test"
        
        context1.insert(record)
        try context1.save()
    }
    
    // Second container - verify persistence
    do {
        let container2 = try ModelContainer(for: schema, configurations: [config])
        let context2 = container2.mainContext
        
        // Fetch and filter in-memory (avoid predicate macros)
        let all = try context2.fetch(FetchDescriptor<MedicalRecord>())
        let records = all.filter { $0.uuid == testUUID }
        
        #expect(records.count == 1)
        
        // Cleanup
        if let record = records.first {
            context2.delete(record)
            try context2.save()
        }
    }
}
```

### Testing Computed Properties
```swift
@Test func testDisplayName() async throws {
    let record = MedicalRecord()
    record.personalGivenName = "John"
    record.personalFamilyName = "Doe"
    #expect(record.displayName == "Doe - John")
}
```

## Requirements

- Mark tests with SwiftData/ModelContext as `@MainActor`
- Mark async tests with `async throws`
- Clean up test data after tests complete
- For persistence tests, create separate ModelContainer instances
- **IMPORTANT**: Avoid using predicate APIs/macros; fetch all and filter in-memory instead
- Use descriptive test names that explain what is being tested
- Test edge cases: empty strings, nil values, boundary conditions

## Test Data

- Use synthetic/mock data only
- Never use real medical information
- Generate unique identifiers for test records
- Clean up all test records after tests complete

## Do

- Test one thing per test function
- Group related tests in structs
- Use meaningful test names
- Test both success and failure paths
- Verify cascade delete behavior for relationships

## Don't

- Don't use XCTest framework (use Swift Testing instead)
- Don't use real patient data
- Don't leave test data in persistent storage
- Don't use predicate macros in tests
- Don't forget to mark MainActor when needed
