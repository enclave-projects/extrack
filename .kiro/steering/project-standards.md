---
inclusion: always
---

# ExTrack Project Standards

## Project Overview
ExTrack is a comprehensive Flutter expense tracking application with the following key features:
- Transaction management (income/expense tracking)
- Smart reminder system with notifications
- Advanced filtering (by date, type, category)
- Professional PDF/CSV export functionality
- Multiple theme support
- Currency formatting with comma separators

## Code Standards

### Flutter/Dart Guidelines
- Use proper null safety throughout the codebase
- Follow Flutter's widget composition patterns
- Implement proper state management with StatefulWidget and streams
- Use meaningful variable and function names
- Add comprehensive error handling with try-catch blocks

### Architecture Patterns
- Single-file architecture for this project (main.dart contains all functionality)
- Stream-based notifications for real-time UI updates
- Utility classes for common operations (NumberFormatter)
- Consistent theme management across all UI components

### Data Management
- Use SharedPreferences for persistent storage
- Implement proper JSON serialization/deserialization
- Maintain data consistency across app restarts
- Handle edge cases for empty states and data corruption

## Feature Implementation Standards

### Currency Formatting
- Always use NumberFormatter.formatCurrency() for displaying monetary values
- Include currency symbols consistently across all features
- Format numbers with comma separators for better readability
- Support multiple currencies (₹, $, €, £, ¥)

### Notification System
- Use flutter_local_notifications for reminder functionality
- Implement proper timezone handling with timezone package
- Ensure notifications work when app is closed
- Provide clear action buttons ("Mark as Done", "Snooze")
- Use stream-based updates for real-time UI synchronization

### Export Functionality
- Generate professional PDF reports with bank statement formatting
- Include comprehensive transaction details with proper formatting
- Support CSV exports for spreadsheet compatibility
- Handle file permissions gracefully with fallback directories
- Include metadata (date ranges, currency info) in exports

### UI/UX Standards
- Maintain consistent spacing and padding throughout the app
- Use proper color schemes for different themes (light/dark/colorful)
- Implement visual feedback for user actions
- Provide clear filter chips and quick access options
- Ensure accessibility compliance in all UI components

## Testing and Quality Assurance
- Test on both Android and iOS platforms
- Verify notification functionality in closed app scenarios
- Test export functionality with various data sets
- Validate currency formatting across different locales
- Ensure proper error handling for edge cases

## Dependencies Management
- Keep dependencies up to date but maintain stability
- Use specific version constraints in pubspec.yaml
- Test thoroughly after dependency updates
- Document any breaking changes and migration steps