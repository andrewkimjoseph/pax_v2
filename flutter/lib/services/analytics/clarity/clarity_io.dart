import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:pax/env/env.dart';

Widget wrapWithClarity({required Widget child}) {
  return ClarityWidget(
    clarityConfig: ClarityConfig(projectId: Env.clarityProjectId),
    app: child,
  );
}

void setClarityUserId(String userId) {
  Clarity.setCustomUserId(userId);
}
