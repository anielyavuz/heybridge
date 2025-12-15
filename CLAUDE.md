# CLAUDE.md - AI Development Context

## Project Overview
**HeyBridge** is a Slack-inspired team communication platform built with Flutter and Firebase. This document serves as a reference for AI assistants (like Claude) to understand the project structure, patterns, and development guidelines.

---

## 🎯 Project Vision
Create a modern, real-time team collaboration platform with:
- **Multi-workspace** support (like Slack)
- **Real-time messaging** with channels and direct messages
- **Thread-based conversations**
- **File sharing** and rich media support
- **Cross-platform** support (iOS, Android, Web)

---

## 📁 Project Structure

```
lib/
├── main.dart                 # App entry point with Firebase initialization
├── models/                   # Data models
│   └── user_model.dart      # User data structure
├── screens/                  # UI screens
│   ├── login_screen.dart    # Login UI (responsive)
│   ├── sign_up_screen.dart  # Registration UI (responsive)
│   └── workspace_screen.dart # Workspace selection UI
└── services/                 # Business logic & API services
    ├── auth_service.dart    # Firebase Authentication
    └── firestore_service.dart # Firestore database operations
```

---

## 🛠 Tech Stack

### Frontend
- **Flutter** 3.8.1+
- **Dart** SDK
- **Provider** for state management

### Backend & Services
- **Firebase Authentication** (Email/Password, Google, Apple ready)
- **Cloud Firestore** for real-time database
- **Firebase Storage** (planned for file uploads)
- **Firebase Cloud Messaging** (planned for notifications)

### Platform Support
- ✅ iOS (13.0+)
- ✅ Android (API 23+, Android 6.0+)
- ✅ Web
- ⏳ macOS (configured but not optimized)
- ⏳ Windows (configured but not optimized)
- ⏳ Linux (configured but not optimized)

---

## 🏗 Architecture & Design Patterns

### UI/UX Principles
1. **Responsive Design**: Mobile-first with desktop optimization
   - Use `MediaQuery` to detect screen size
   - Separate layouts for mobile (<800px) and desktop (≥800px)
   - Example: `login_screen.dart` has `_buildMobileLayout()` and `_buildDesktopLayout()`

2. **Dark Theme Primary**: Slack-inspired dark theme
   - Background: `#1A1D21`
   - Secondary: `#2D3748`
   - Primary accent: `#4A9EFF`

3. **Material Design 3**: Using `useMaterial3: true`

### Code Patterns

#### 1. Screen Structure
```dart
class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  // Controllers
  final _controller = TextEditingController();

  // Services
  final _service = MyService();

  // State
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(...);
  }
}
```

#### 2. Service Pattern
```dart
class MyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createData(Model data) async {
    try {
      await _firestore.collection('collection').doc(data.id).set(data.toMap());
    } catch (e) {
      throw Exception('Error message: $e');
    }
  }
}
```

#### 3. Model Pattern
```dart
class MyModel {
  final String id;
  final DateTime createdAt;

  MyModel({required this.id, required this.createdAt});

  Map<String, dynamic> toMap() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MyModel.fromMap(Map<String, dynamic> map) => MyModel(
    id: map['id'] ?? '',
    createdAt: DateTime.parse(map['createdAt']),
  );
}
```

---

## 🔐 Security & Best Practices

### Critical Security Rules
1. ❌ **NEVER** store passwords in Firestore
2. ✅ **ALWAYS** use Firebase Auth for authentication
3. ✅ **ALWAYS** validate user input on both client and server
4. ✅ **ALWAYS** use proper Firestore security rules

### Data Privacy
- Passwords are only handled by Firebase Auth
- User documents store: `uid`, `email`, `displayName`, `photoURL`, `timestamps`, `workspaceIds`
- Sensitive data should be encrypted if stored

### Error Handling
```dart
try {
  // Operation
} catch (e) {
  if (mounted) {
    _showError(e.toString());
  }
} finally {
  if (mounted) {
    setState(() => _isLoading = false);
  }
}
```

---

## 🗄 Database Structure

### Current Collections

#### `users/`
```javascript
{
  uid: string,              // Firebase Auth UID
  email: string,            // User email
  displayName: string,      // Display name (auto: email prefix)
  photoURL?: string,        // Profile picture URL
  createdAt: timestamp,     // Account creation
  lastSeen: timestamp,      // Last activity
  workspaceIds: string[]    // Array of workspace IDs user belongs to
}
```

### Planned Collections (Phase 2+)

#### `workspaces/{workspaceId}`
```javascript
{
  id: string,
  name: string,
  description: string,
  ownerId: string,
  memberIds: string[],
  channelIds: string[],
  inviteCode: string,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

#### `workspaces/{workspaceId}/channels/{channelId}`
```javascript
{
  id: string,
  name: string,
  description: string,
  isPrivate: boolean,
  memberIds: string[],
  createdBy: string,
  createdAt: timestamp
}
```

#### `workspaces/{workspaceId}/channels/{channelId}/messages/{messageId}`
```javascript
{
  id: string,
  senderId: string,
  text: string,
  attachments: array,
  replyToId?: string,
  reactions: {emoji: userId[]},
  createdAt: timestamp,
  updatedAt?: timestamp,
  isEdited: boolean,
  isDeleted: boolean
}
```

See `docs/roadMap.txt` for complete database schema.

---

## 📋 Development Roadmap

### ✅ Phase 1: Authentication & User Management (COMPLETED)
- Firebase setup (Auth, Firestore)
- Login & Sign Up screens (responsive)
- User model & Firestore integration
- Auto-create user on registration
- Workspace selection screen
- Logout functionality

### 🔄 Phase 2: Workspace Management (IN PROGRESS)
- Workspace model & service
- Create/Join workspace
- Workspace list & switching
- Workspace settings

### ⏳ Phase 3-9: (PLANNED)
See `docs/roadMap.txt` for detailed breakdown.

---

## 🚀 Getting Started

### Prerequisites
```bash
flutter --version  # 3.8.1+
firebase CLI
```

### Setup
```bash
# Install dependencies
flutter pub get

# Run on specific device
flutter run -d <device-id>

# iOS
flutter run -d ios

# Android
flutter run -d android

# Web
flutter run -d chrome
```

### Firebase Configuration
- iOS: `ios/Runner/GoogleService-Info.plist`
- Android: `android/app/google-services.json`
- Web, macOS, Windows: Auto-configured via `firebase_options.dart`

---

## 🎨 UI/UX Guidelines

### Responsive Breakpoints
- **Mobile**: < 800px width
- **Desktop**: ≥ 800px width

### Color Palette
```dart
// Background
Color(0xFF1A1D21)  // Primary background
Color(0xFF2D3748)  // Secondary/Cards

// Accent
Color(0xFF4A9EFF)  // Primary accent (buttons, links)

// Text
Colors.white       // Primary text
Colors.white70     // Secondary text
Colors.white60     // Tertiary text
Colors.white38     // Placeholder text
```

### Typography
- **Headings**: Bold, White
- **Body**: Regular, White70
- **Captions**: White60
- **Hints**: White38

### Component Patterns
- **Buttons**: Rounded corners (8px), consistent padding
- **Input Fields**: Dark background (#2D3748), no border, 8px radius
- **Cards**: Same as inputs, subtle elevation
- **Icons**: 24px default, colored appropriately

---

## 🧪 Testing Strategy

### Manual Testing Checklist
- [ ] Test on iOS device/simulator
- [ ] Test on Android device/emulator
- [ ] Test on Web (Chrome, Safari, Firefox)
- [ ] Test different screen sizes (phone, tablet, desktop)
- [ ] Test auth flows (login, signup, logout)
- [ ] Test error states
- [ ] Test loading states

### Future: Automated Testing
- Unit tests for services
- Widget tests for screens
- Integration tests for flows

---

## 📝 Git Workflow

### Branch Strategy
- `main`: Production-ready code
- `develop`: Integration branch (future)
- `feature/*`: Feature branches (future)

### Commit Message Format
```
<type>: <description>

<body>

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

---

## 🐛 Common Issues & Solutions

### Issue: iOS Pod Install Fails
**Solution**:
- Check iOS deployment target is 13.0+
- Clean pods: `cd ios && rm -rf Pods Podfile.lock && pod install`

### Issue: Android Build Fails
**Solution**:
- Check minSdk is 23+
- Verify Google Services JSON is present
- Run `flutter clean && flutter pub get`

### Issue: Overflow Errors on Mobile
**Solution**:
- Wrap content in `SingleChildScrollView`
- Use responsive layout patterns
- Check MediaQuery breakpoints

### Issue: Firebase Auth Errors
**Solution**:
- Verify Firebase config files
- Check Firebase Console authentication methods enabled
- Ensure internet permissions are set

---

## 📋 Logging System (LoggerService)

### Overview
HeyBridge uses a centralized logging system (`LoggerService`) for debugging, monitoring, and troubleshooting. All logs are stored locally in JSON format and can be viewed in the app via Profile > "Logları Görüntüle" (See Logs).

### Usage Pattern
```dart
// Import
import 'services/logger_service.dart';

// Initialize in class
final LoggerService _logger = LoggerService();

// Log methods
_logger.debug('Debug message', category: 'CATEGORY', data: {'key': 'value'});
_logger.info('Info message', category: 'CATEGORY', data: {'key': 'value'});
_logger.warning('Warning message', category: 'CATEGORY');
_logger.error('Error message', category: 'CATEGORY', data: {'error': e.toString()});
_logger.success('Success message', category: 'CATEGORY');
```

### Categories (Use Consistently)
| Category | Usage |
|----------|-------|
| `AUTH` | Authentication operations (login, signup, logout) |
| `FCM` | Firebase Cloud Messaging token operations |
| `FCM_API` | FCM backend API calls |
| `MESSAGE` | Channel and DM message operations |
| `DM` | Direct message operations |
| `FIRESTORE` | Firestore database operations |
| `UI` | UI interactions and navigation |
| `NAVIGATION` | Screen navigation |
| `PHASE` | Development phase milestones |
| `FEATURE` | Feature-specific operations |

### Implementation Requirements
**IMPORTANT**: When adding new services or modifying existing ones, ALWAYS add LoggerService:

1. **Services** - Add `_logger` field and log critical operations:
   - API calls (start, success, error)
   - Authentication state changes
   - Data mutations (create, update, delete)
   - Error handling

2. **Screens** - Log user interactions:
   - Button taps
   - Form submissions
   - Navigation events

### Log Levels
- `debug`: Detailed info for debugging (development only)
- `info`: General information about operations
- `warning`: Potential issues that don't break functionality
- `error`: Errors that affect functionality
- `success`: Successful completion of important operations

### Storage
- Logs stored in: `heybridge_logs.json` (local device storage)
- Max logs in memory: 1000 (oldest removed automatically)
- Can be exported via `_logger.exportLogs()`
- View in app: Profile > Logları Görüntüle

### Example Implementation
```dart
class MyService {
  final LoggerService _logger = LoggerService();

  Future<void> doSomething() async {
    _logger.info('Starting operation', category: 'MY_CATEGORY');
    try {
      // ... operation
      _logger.success('Operation completed', category: 'MY_CATEGORY', data: {'result': 'ok'});
    } catch (e) {
      _logger.error('Operation failed: $e', category: 'MY_CATEGORY');
      rethrow;
    }
  }
}
```

---

## 🤖 AI Assistant Guidelines

### When Working on This Project:

1. **Always Read First**
   - Check existing code patterns before suggesting new ones
   - Review `roadMap.txt` for planned features
   - Understand current phase before implementing

2. **Follow Existing Patterns**
   - Use established service patterns
   - Maintain responsive design approach
   - Keep dark theme consistency

3. **Security First**
   - Never suggest storing passwords
   - Always validate user input
   - Use proper error handling

4. **Responsive By Default**
   - Always consider mobile AND desktop
   - Use MediaQuery for breakpoints
   - Test overflow scenarios

5. **Document Changes**
   - Update this file for major changes
   - Update roadMap.txt when completing phases
   - Keep comments clear and concise

6. **Git Commits**
   - Use conventional commit format
   - Include co-author attribution
   - Write descriptive commit messages

---

## 📚 Key Files Reference

### Must-Read Files
- `docs/roadMap.txt` - Complete development roadmap
- `lib/main.dart` - App initialization
- `lib/services/auth_service.dart` - Auth patterns
- `lib/screens/login_screen.dart` - Responsive UI example

### Configuration Files
- `pubspec.yaml` - Dependencies
- `firebase_options.dart` - Firebase config
- `ios/Podfile` - iOS dependencies
- `android/app/build.gradle.kts` - Android config

---

## 🔮 Future Considerations

### Performance Optimization
- Implement message pagination
- Add image caching
- Optimize Firestore queries
- Use virtual scrolling for long lists

### Accessibility
- Screen reader support
- Keyboard navigation
- High contrast mode
- Font scaling

### Analytics
- User engagement tracking
- Error monitoring
- Performance monitoring

---

## 📞 Support & Resources

### Documentation
- [Flutter Docs](https://docs.flutter.dev)
- [Firebase Docs](https://firebase.google.com/docs)
- [Slack API Docs](https://api.slack.com) (for inspiration)

### Project-Specific
- GitHub: https://github.com/anielyavuz/heybridge
- Roadmap: `docs/roadMap.txt`

---

## ✨ Credits

**Built with:**
- Flutter & Dart
- Firebase
- Claude Code (AI Pair Programming)

**Design Inspiration:**
- Slack
- Discord
- Microsoft Teams

---

**Last Updated**: 2025-12-16
**Current Phase**: Phase 1 Complete ✅ | Phase 2 In Progress 🔄
**Flutter Version**: 3.8.1+
**Dart Version**: 3.8.1+
