# Flutter Client

This directory is the Android-first Flutter client for Excellent Calendar.

## Current scope

The current implementation builds the first Inbox home page only. It includes:

- A custom `InboxPage` with no default `AppBar`.
- The requested component split: `InboxTopBar`, `TaskListCard`, `TaskListItem`,
  `CustomCheckbox`, `AddTaskButton`, `BottomNavBar`, and `BottomNavItem`.
- A lightweight `InboxTaskViewData` view model aligned with the documented
  `Importance` values.
- An `InboxTaskGateway` interface and `MockInboxTaskAdapter` for display data.

This pass does not implement task creation, completion persistence, JSON
storage, MethodChannel calls, Kotlin services, JNI, or C++ business logic.

## Run locally

```powershell
cd A:\calendar\ExcellentCalendarAPP\flutter_client
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d <device-id>
```

If there is only one connected Android device, `flutter run` is enough.

## Architecture direction

The page currently depends only on the Dart gateway contract:

```text
InboxPage
  -> InboxTaskGateway
  -> MockInboxTaskAdapter
```

The intended production path is:

```text
Flutter UI
  -> Dart Gateway Interface
  -> Dart MethodChannel Adapter
  -> Kotlin MethodChannel Handler
  -> JNI / C++ Core
  -> JSON Storage Repository
```

Keep UI code out of JSON file access, native Android APIs, and C++ details.
