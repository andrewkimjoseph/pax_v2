class PollOption {
  final String id;
  final String text;
  final int sortOrder;

  const PollOption({
    required this.id,
    required this.text,
    required this.sortOrder,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['id'] as String,
      text: json['option_text'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class PollQuestion {
  final String id;
  final String text;
  final int sortOrder;
  final List<PollOption> options;

  const PollQuestion({
    required this.id,
    required this.text,
    required this.sortOrder,
    required this.options,
  });
}

class PollData {
  final String taskId;
  final String paxTaskId;
  final String title;
  final List<PollQuestion> questions;

  const PollData({
    required this.taskId,
    required this.paxTaskId,
    required this.title,
    required this.questions,
  });
}

class PollAnswer {
  final String questionId;
  final String questionOptionId;

  const PollAnswer({
    required this.questionId,
    required this.questionOptionId,
  });

  Map<String, String> toJson() => {
        'questionId': questionId,
        'questionOptionId': questionOptionId,
      };
}
