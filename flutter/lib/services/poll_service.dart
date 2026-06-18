import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pax/models/poll/poll_data.dart';
import 'package:pax/utils/secret_constants.dart' as secrets;

class PollService {
  Map<String, String> get _headers => {
    'apikey': secrets.supabaseAnonKey,
    'Authorization': 'Bearer ${secrets.supabaseAnonKey}',
  };

  Future<PollData?> fetchPublishedPoll(String paxTaskId) async {
    final taskUri = Uri.parse(
      '${secrets.supabaseUrl}/rest/v1/tasks?pax_task_id=eq.$paxTaskId&is_active=eq.true&select=id,pax_task_id,title',
    );

    final taskResponse = await http.get(taskUri, headers: _headers);
    if (taskResponse.statusCode != 200) {
      throw Exception('Failed to load poll task');
    }

    final tasks = jsonDecode(taskResponse.body) as List<dynamic>;
    if (tasks.isEmpty) return null;

    final task = tasks.first as Map<String, dynamic>;
    final taskId = task['id'] as String;

    final questionUri = Uri.parse(
      '${secrets.supabaseUrl}/rest/v1/questions?task_id=eq.$taskId&select=id,question_text,sort_order&order=sort_order.asc',
    );
    final questionResponse = await http.get(questionUri, headers: _headers);
    if (questionResponse.statusCode != 200) {
      throw Exception('Failed to load poll questions');
    }

    final questionsJson = jsonDecode(questionResponse.body) as List<dynamic>;
    if (questionsJson.isEmpty) return null;

    final questionIds =
        questionsJson
            .map((item) => (item as Map<String, dynamic>)['id'] as String)
            .toList();

    final optionsFilter = '(${questionIds.join(',')})';
    final optionsUri = Uri.parse(
      '${secrets.supabaseUrl}/rest/v1/question_options?question_id=in.$optionsFilter&select=id,question_id,option_text,sort_order&order=sort_order.asc',
    );
    final optionsResponse = await http.get(optionsUri, headers: _headers);
    if (optionsResponse.statusCode != 200) {
      throw Exception('Failed to load poll options');
    }

    final optionsJson = jsonDecode(optionsResponse.body) as List<dynamic>;
    final optionsByQuestionId = <String, List<PollOption>>{};
    for (final item in optionsJson) {
      final map = item as Map<String, dynamic>;
      final questionId = map['question_id'] as String;
      final option = PollOption.fromJson(map);
      optionsByQuestionId.putIfAbsent(questionId, () => []).add(option);
    }

    final questions =
        questionsJson.map((item) {
            final map = item as Map<String, dynamic>;
            final questionId = map['id'] as String;
            final options = <PollOption>[
              ...(optionsByQuestionId[questionId] ?? const []),
            ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            return PollQuestion(
              id: questionId,
              text: map['question_text'] as String,
              sortOrder: map['sort_order'] as int? ?? 0,
              options: options,
            );
          }).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return PollData(
      taskId: taskId,
      paxTaskId: task['pax_task_id'] as String,
      title: task['title'] as String,
      questions: questions,
    );
  }
}
