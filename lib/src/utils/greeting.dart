/// "Good Morning"/"Good Afternoon"/"Good Evening" based on the device clock.
/// Boundaries: before 12 = morning, before 17 = afternoon, else evening —
/// matches the common convention most greeting UIs use.
String timeOfDayGreeting(DateTime now) {
  if (now.hour < 12) return 'Good Morning';
  if (now.hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

/// First name to greet the user by, preferring their Firebase display name
/// (splitting off the first word so "Raj Sharma" greets as "Raj"), falling
/// back to the local part of their email, then to a generic greeting with
/// no name at all when neither is available (guest/anonymous sessions).
String? firstNameFrom({String? displayName, String? email}) {
  final name = displayName?.trim();
  if (name != null && name.isNotEmpty) {
    return name.split(RegExp(r'\s+')).first;
  }
  final emailParts = email?.split('@');
  final localPart = (emailParts != null && emailParts.isNotEmpty) ? emailParts.first.trim() : null;
  if (localPart != null && localPart.isNotEmpty) {
    return localPart[0].toUpperCase() + localPart.substring(1);
  }
  return null;
}
