import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/data/profile_photo.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/5mQAAAAASUVORK5CYII=',
);

class DelayedPhotoGateway extends DemoAuthGateway {
  Completer<ProfilePhoto?>? read;
  bool failUpload = false;
  @override
  Future<ProfilePhoto?> readPhoto(String access) =>
      read?.future ?? super.readPhoto(access);
  @override
  Future<ProfilePhoto> savePhoto(String access, Uint8List bytes) async {
    if (failUpload) {
      throw const ApiFailure('OFFLINE', 'Cannot reach the service.');
    }
    return super.savePhoto(access, bytes);
  }
}

void main() {
  test('photo gateway sends authenticated multipart and parses saved and absent photos', () async {
    var calls = 0;
    final client = ApiClient(
      AppConfig(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        environment: 'dev',
        mode: 'api',
      ),
      client: MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/v1/auth/profile/photo');
        expect(request.headers['authorization'], 'Bearer private-token');
        if (request.method == 'PUT') {
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          expect(latin1.decode(request.bodyBytes), contains('name="photo"'));
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'contentType': 'image/png',
                'imageBase64': base64Encode(png),
              },
            }),
            200,
          );
        }
        return http.Response('{"success":true,"message":"Profile photo"}', 200);
      }),
    );
    final photos = HttpProfilePhotoGateway(client);
    expect((await photos.savePhoto('private-token', png)).bytes, png);
    expect(await photos.readPhoto('private-token'), isNull);
    expect(calls, 2);
    client.close();
  });

  test('photo errors do not replay uploads or claim a saved image', () async {
    var calls = 0;
    final client = ApiClient(
      AppConfig(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        environment: 'dev',
        mode: 'api',
      ),
      client: MockClient((request) async {
        calls++;
        return http.Response(
          '{"success":false,"error":"PROFILE_PHOTO_INVALID"}',
          400,
        );
      }),
    );
    await expectLater(
      HttpProfilePhotoGateway(client).savePhoto('private-token', png),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.code,
          'code',
          'PROFILE_PHOTO_INVALID',
        ),
      ),
    );
    expect(calls, 1);
    client.close();
  });

  test('malformed or oversized photo responses fail explicitly', () {
    for (final value in [
      {'contentType': 'image/svg+xml', 'imageBase64': base64Encode(png)},
      {'contentType': 'image/png', 'imageBase64': 'invalid-base64'},
      {'contentType': 'image/png', 'imageBase64': ''},
    ]) {
      expect(() => ProfilePhoto.fromJson(value), throwsA(isA<ApiFailure>()));
    }
  });

  Future<SessionController> signedIn(DelayedPhotoGateway gateway) async {
    final session = SessionController(gateway, MemorySessionVault());
    await session.initialize();
    session.openEmail();
    await session.beginEmail('photo@example.test');
    await session.verifyCode('123456');
    return session;
  }

  test('saved photos reload after reauthentication and failed replacement preserves the last saved image', () async {
    final gateway = DelayedPhotoGateway();
    final session = await signedIn(gateway);
    addTearDown(session.dispose);
    expect(await session.saveProfilePhoto(png), isTrue);
    final saved = session.profilePhoto;
    gateway.failUpload = true;
    expect(
      await session.saveProfilePhoto(Uint8List.fromList([1, 2, 3])),
      isFalse,
    );
    expect(session.profilePhoto, same(saved));
    expect(session.photoFailure?.code, 'OFFLINE');
    await session.signOut();
    expect(session.profilePhoto, isNull);
    expect(session.photoFailure, isNull);
    session.openEmail();
    await session.beginEmail('photo@example.test');
    await session.verifyCode('123456');
    await session.loadProfilePhoto();
    expect(session.profilePhoto?.bytes, png);
  });

  test(
    'late photo response after logout cannot publish private data',
    () async {
      final gateway = DelayedPhotoGateway()..read = Completer<ProfilePhoto?>();
      final session = await signedIn(gateway);
      addTearDown(session.dispose);
      final loading = session.loadProfilePhoto();
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      gateway.read!.complete(ProfilePhoto(png, 'image/png'));
      await loading;
      expect(session.profilePhoto, isNull);
      expect(session.photoBusy, isFalse);
      expect(session.photoLoaded, isFalse);
    },
  );
}
