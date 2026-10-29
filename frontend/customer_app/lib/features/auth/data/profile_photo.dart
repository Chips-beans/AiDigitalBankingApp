import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/api_client.dart';

const maxProfilePhotoBytes = 5 * 1024 * 1024;

class ProfilePhoto {
  ProfilePhoto(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
  factory ProfilePhoto.fromJson(Map<String, dynamic> json) {
    try {
      final type = json['contentType'];
      final encoded = json['imageBase64'];
      if (type != 'image/jpeg' && type != 'image/png') {
        throw const FormatException();
      }
      if (encoded is! String || encoded.length > 6990508) {
        throw const FormatException();
      }
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > maxProfilePhotoBytes) {
        throw const FormatException();
      }
      return ProfilePhoto(bytes, type as String);
    } on FormatException {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'The saved photo could not be loaded.',
      );
    }
  }
}

abstract interface class ProfilePhotoGateway {
  Future<ProfilePhoto?> readPhoto(String access);
  Future<ProfilePhoto> savePhoto(String access, Uint8List bytes);
}

/// Uses the same authenticated client and server envelope as other profile calls.
class HttpProfilePhotoGateway implements ProfilePhotoGateway {
  HttpProfilePhotoGateway(this.client);
  final ApiClient client;
  @override
  Future<ProfilePhoto?> readPhoto(String access) async {
    final response = await client.request(
      'GET',
      '/auth/profile/photo',
      accessToken: access,
    );
    if (response['data'] == null) return null;
    return _photo(response);
  }

  @override
  Future<ProfilePhoto> savePhoto(String access, Uint8List bytes) async =>
      _photo(
        await client.request(
          'PUT',
          '/auth/profile/photo',
          accessToken: access,
          photoBytes: bytes,
        ),
      );
  ProfilePhoto _photo(Map<String, dynamic> response) {
    if (response['data'] is! Map<String, dynamic>) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'The saved photo could not be confirmed.',
      );
    }
    return ProfilePhoto.fromJson(response['data'] as Map<String, dynamic>);
  }
}
