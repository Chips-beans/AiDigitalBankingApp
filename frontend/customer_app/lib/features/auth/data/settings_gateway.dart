import '../../../core/network/api_client.dart';
import 'auth_gateway.dart';

class SettingsGateway {
  const SettingsGateway(this.auth);
  final AuthGateway auth;
  Future<SessionIdentity> updateProfile(
    String token,
    String first,
    String last,
  ) async {
    final gateway = auth;
    if (gateway is! HttpAuthGateway) {
      if (gateway is! ContinuationGateway) {
        throw const ApiFailure(
          'PROFILE_UNAVAILABLE',
          'Profile changes are unavailable for this sign-in provider.',
        );
      }
      return (gateway as ContinuationGateway).completeProfile(
        token,
        first,
        last,
      );
    }
    final result = await gateway.client.request(
      'PUT',
      '/auth/profile/details',
      accessToken: token,
      body: {'firstName': first, 'lastName': last},
    );
    if (result['data'] is! Map<String, dynamic>) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'Profile changes could not be confirmed. Refresh before retrying.',
      );
    }
    return SessionIdentity.fromJson(result['data'] as Map<String, dynamic>);
  }
}

abstract interface class PinChangeGateway {
  Future<void> change(
    String access,
    String current,
    String pin,
    String confirm,
  );
}
