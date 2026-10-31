import 'package:flutter_test/flutter_test.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:customer_app/features/merchant/merchant_approval.dart';
import 'package:customer_app/features/auth/session_controller.dart';

import 'settings_test.dart' show settingsSession;
import 'merchant_approval_test.dart' show ApprovalRig, ApprovalNative;

class FailingStore extends MemoryHandoffStore {
  @override
  Future<void> write(String key, String? value) async =>
      throw StateError('Synthetic storage failure');
}

class FailedReturn extends ApprovalNative {
  bool failReturn = true;
  @override
  Future<void> open(String uri) async {
    if (failReturn) throw const HandoffFailure('HANDOFF_UNAVAILABLE');
    await super.open(uri);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('signed-out Customer resumes request only after existing sign-in and PIN gates', () async {
    final rig = ApprovalRig(await settingsSession(withPin: true));
    addTearDown(rig.dispose);
    await rig.session.signOut();
    await rig.start();
    expect(rig.model.hasRequest, true);
    expect(rig.model.details, isNull);
    expect(rig.requests, isEmpty);
    rig.session.openEmail();
    await rig.session.beginEmail('settings@example.test');
    await rig.session.verifyCode('123456');
    if (rig.session.phase == SessionPhase.signedIn &&
        !rig.session.identity!.profileComplete) {
      await rig.session.completeInformation('Seng', 'Sovanreach');
    }
    if (rig.session.phase == SessionPhase.pinLocked) {
      await rig.session.submitPin('0427');
    }
    await rig.model.poll();
    expect(rig.model.details, isNotNull);
    expect(rig.model.canDecide, true);
  });
  test(
    'failed secure persistence cannot approve from an in-memory request',
    () async {
      final rig = ApprovalRig(await settingsSession());
      addTearDown(rig.dispose);
      rig.model.dispose();
      rig.model = MerchantApproval(
        rig.session,
        rig.api,
        FailingStore(),
        native: rig.native,
        clock: () => rig.now,
      );
      await rig.start();
      await rig.model.loadDetails();
      expect(rig.model.storageBlocked, true);
      expect(rig.model.canDecide, false);
      await rig.model.decide(pin: '0427');
      expect(
        rig.requests.where((r) => r.url.path.endsWith('/approve')),
        isEmpty,
      );
    },
  );
  test('approved callback survives failed return and process recreation without reapproval', () async {
    final rig = ApprovalRig(await settingsSession());
    addTearDown(rig.dispose);
    final native = FailedReturn()..queue.add(rig.link);
    rig.model.dispose();
    rig.model = MerchantApproval(
      rig.session,
      rig.api,
      rig.store,
      native: native,
      clock: () => rig.now,
    );
    await rig.model.initialize();
    await rig.model.decide(pin: '0427');
    expect(rig.model.canReturn, true);
    expect(rig.model.pending!['callback'], startsWith(callbackBase));
    rig.model.dispose();
    rig.model = MerchantApproval(
      rig.session,
      rig.api,
      rig.store,
      native: native,
      clock: () => rig.now,
    );
    await rig.model.initialize();
    expect(rig.model.canReturn, true);
    native.failReturn = false;
    await rig.model.returnToMerchant();
    expect(native.opened.length, 1);
    expect(
      rig.requests.where((r) => r.url.path.endsWith('/approve')).length,
      1,
    );
    expect(rig.model.hasRequest, false);
  });
}
