import 'package:cloud_functions/cloud_functions.dart';
import 'package:pax/models/poll/poll_data.dart';

class PollSubmissionService {
  final FirebaseFunctions _functions;

  PollSubmissionService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  Future<Map<String, dynamic>> submitPollResponse({
    required String screeningId,
    required String taskId,
    required List<PollAnswer> answers,
  }) async {
    final callable = _functions.httpsCallable('submitPollResponse');
    final result = await callable.call({
      'screeningId': screeningId,
      'taskId': taskId,
      'answers': answers.map((answer) => answer.toJson()).toList(),
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}
