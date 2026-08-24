import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pax/utils/error_message_util.dart';

void main() {
  group('ErrorMessageUtil', () {
    test('fromError uses FirebaseFunctionsException message', () {
      final exception = FirebaseFunctionsException(
        code: 'failed-precondition',
        message:
            'You need to complete GoodDollar face verification before participating in tasks.',
      );

      expect(
        ErrorMessageUtil.fromError(exception),
        'You need to complete GoodDollar face verification before participating in tasks.',
      );
    });

    test('userFacing strips firebase_functions bracket prefix', () {
      expect(
        ErrorMessageUtil.userFacing(
          '[firebase_functions/failed-precondition] You need to complete GoodDollar face verification before participating in tasks.',
        ),
        'You need to complete GoodDollar face verification before participating in tasks.',
      );
    });

    test('userFacing strips Exception prefix', () {
      expect(
        ErrorMessageUtil.userFacing(
          'Exception: You need to complete face verification in PaxWallet.',
        ),
        'You need to complete face verification in PaxWallet.',
      );
    });
  });
}
