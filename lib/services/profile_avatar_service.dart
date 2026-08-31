import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_manager.dart';
import 'supabase_service.dart';

class ProfileAvatarService {
  ProfileAvatarService._();

  static const bucketName = 'profile-avatars';
  static const maxBytes = 5 * 1024 * 1024;

  static Future<String?> pickAndUpload() async {
    final file = await FilePicker.pickFile(type: FileType.image);

    if (file == null) return null;

    final bytes = await file.readAsBytes();

    if (bytes.isEmpty) {
      throw StateError('The selected photo could not be read.');
    }

    if (bytes.length > maxBytes) {
      throw ArgumentError('Choose a profile photo smaller than 5 MB.');
    }

    final extension = _safeExtension(
      file.name.contains('.') ? file.name.split('.').last : null,
    );
    final contentType = _contentType(extension);

    return upload(bytes: bytes, extension: extension, contentType: contentType);
  }

  static Future<String> upload({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Sign in before adding a profile photo.');
    }
    if (bytes.length > maxBytes) {
      throw ArgumentError('Choose a profile photo smaller than 5 MB.');
    }

    final normalizedExtension = _safeExtension(extension);
    final path = '${user.id}/avatar.$normalizedExtension';
    await client.storage
        .from(bucketName)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
            cacheControl: '3600',
          ),
        );

    final publicUrl = client.storage.from(bucketName).getPublicUrl(path);
    final avatarUrl = Uri.parse(publicUrl)
        .replace(
          queryParameters: {
            ...Uri.parse(publicUrl).queryParameters,
            'v': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        )
        .toString();

    await AuthManager.instance.updateAvatarUrl(avatarUrl);
    return avatarUrl;
  }

  static Future<void> remove() async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Sign in before changing your profile photo.');
    }

    await client.storage.from(bucketName).remove([
      for (final extension in const ['jpg', 'png', 'webp'])
        '${user.id}/avatar.$extension',
    ]);
    await AuthManager.instance.updateAvatarUrl(null);
  }

  static String _safeExtension(String? value) {
    final extension = (value ?? '').trim().toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
        ? (extension == 'jpeg' ? 'jpg' : extension)
        : 'jpg';
  }

  static String _contentType(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
