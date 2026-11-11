final class MessageException implements Exception {
  final String message;

  const MessageException(this.message);

  @override
  String toString() => message;
}

final class AgeSecretKeyRequiredException implements Exception {
  const AgeSecretKeyRequiredException();
}

/// A profile download that a later request for the same profile replaced
/// before it reached the file.
final class ProfileUpdateSupersededException implements Exception {
  const ProfileUpdateSupersededException();
}
