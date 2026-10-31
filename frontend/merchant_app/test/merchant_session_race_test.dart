import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';

class SlowEndAuth implements MerchantAuthGateway {
  int authorizations = 0;
  final ending = Completer<void>();
  @override
  Future<MerchantIdentity> authorize() async {
    authorizations++;
    return const MerchantIdentity(ownerId: 42);
  }

  @override
  Future<void> cancel() => ending.future;
  @override
  Future<void> signOut() => ending.future;
}

void main() {
  for (final logout in [false, true]) {
    test(
      '${logout ? 'logout' : 'cancel'} settles before a new sign-in can begin',
      () async {
        final auth = SlowEndAuth();
        final session = MerchantSession(auth);
        await session.signIn();
        final finishing = logout ? session.signOut() : session.cancel();
        expect(session.phase, MerchantPhase.signedOut);
        expect(session.busy, true);
        await session.signIn();
        expect(auth.authorizations, 1);
        auth.ending.complete();
        await finishing;
        expect(session.busy, false);
        await session.signIn();
        expect(auth.authorizations, 2);
        session.dispose();
      },
    );
  }
}
