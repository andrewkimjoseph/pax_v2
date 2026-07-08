import 'package:flutter/material.dart' show InkWell, PopScope;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/poll/poll_data.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/providers/db/tasks/task_provider.dart';
import 'package:pax/providers/local/activity_providers.dart';
import 'package:pax/providers/local/screening_context/screening_context_provider.dart';
import 'package:pax/providers/local/task_completion_state_provider.dart';
import 'package:pax/providers/local/task_context/task_context_provider.dart';
import 'package:pax/services/poll_service.dart';
import 'package:pax/services/poll_submission_service.dart';
import 'package:pax/services/task_completion_service.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/error_message_util.dart';
import 'package:pax/widgets/submit_poll_drawer.dart';
import 'package:pax/widgets/task_timer.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class AnswerPollView extends ConsumerStatefulWidget {
  const AnswerPollView({super.key});

  @override
  ConsumerState<AnswerPollView> createState() => _AnswerPollViewState();
}

class _AnswerPollViewState extends ConsumerState<AnswerPollView> {
  final PollService _pollService = PollService();
  final PollSubmissionService _pollSubmissionService = PollSubmissionService();

  PollData? _pollData;
  final Map<String, String> _selectedOptionsByQuestionId = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(taskCompletionProvider.notifier).reset();
      _loadPoll();
    });
  }

  bool get _allQuestionsAnswered {
    final poll = _pollData;
    if (poll == null) return false;
    return poll.questions.every(
      (question) => _selectedOptionsByQuestionId.containsKey(question.id),
    );
  }

  Future<void> _loadPoll() async {
    final taskContext = ref.read(taskContextProvider);
    final currentTask = taskContext?.task;
    final taskId = currentTask?.id;

    if (taskId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Task not found';
      });
      return;
    }

    try {
      final poll = await _pollService.fetchPublishedPoll(taskId);
      if (!mounted) return;
      setState(() {
        _pollData = poll;
        _isLoading = false;
        _errorMessage = poll == null ? 'Poll is not available yet' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = ErrorMessageUtil.userFacing(e.toString());
      });
    }
  }

  void _openConfirmationDrawer() {
    if (!_allQuestionsAnswered || _isSubmitting) return;

    openDrawer(
      context: context,
      expands: false,
      builder: (context) {
        return SubmitPollDrawer(onSubmitPoll: _submitAnswer);
      },
      position: OverlayPosition.bottom,
    );
  }

  Future<void> _submitAnswer() async {
    if (_isSubmitting || !_allQuestionsAnswered) return;

    final taskContext = ref.read(taskContextProvider);
    final currentTask = taskContext?.task;
    final screeningContext = ref.read(screeningContextProvider);
    final screeningId = screeningContext?.screening?.id;
    final taskId = currentTask?.id;
    final poll = _pollData;

    if (taskId == null || screeningId == null || poll == null) {
      _showErrorDialog('Missing task or screening information');
      return;
    }

    setState(() => _isSubmitting = true);

    ref.read(analyticsProvider).taskCompletionStarted({
      'taskId': taskId,
      'screeningId': screeningId,
      'taskCompletionId': screeningContext?.screeningResult?.taskCompletionId,
    });

    if (!mounted) return;

    late BuildContext loadingDialogContext;
    showDialog<void>(
      barrierDismissible: false,
      context: context,
      builder: (dialogContext) {
        loadingDialogContext = dialogContext;
        return _buildCompletionDialog();
      },
    );

    try {
      final answers =
          poll.questions
              .map(
                (question) => PollAnswer(
                  questionId: question.id,
                  questionOptionId: _selectedOptionsByQuestionId[question.id]!,
                ),
              )
              .toList();

      final result = await _pollSubmissionService.submitPollResponse(
        screeningId: screeningId,
        taskId: taskId,
        answers: answers,
      );

      await ref.read(taskCompletionServiceProvider).onTaskRecordedComplete(
        screeningId: screeningId,
        taskId: taskId,
        taskCompletionId: result['taskCompletionId'] as String,
      );

      if (!mounted) return;

      if (loadingDialogContext.mounted && loadingDialogContext.canPop()) {
        loadingDialogContext.pop();
      }

      ref.read(analyticsProvider).taskCompletionComplete({
        'taskId': taskId,
        'screeningId': screeningId,
      });

      final participantId = ref.read(participantProvider).participant?.id;
      if (participantId != null) {
        ref.invalidate(availableTasksStreamProvider(participantId));
        await ref
            .read(activityNotifierProvider.notifier)
            .loadActivities(participantId);
      }
      if (mounted) {
        context.pushReplacement('/tasks/task-complete');
      }
    } catch (e) {
      if (!mounted) return;

      if (loadingDialogContext.mounted && loadingDialogContext.canPop()) {
        loadingDialogContext.pop();
      }

      ref.read(analyticsProvider).taskCompletionFailed({
        'taskId': taskId,
        'screeningId': screeningId,
        'error': e.toString(),
      });
      _showErrorDialog(ErrorMessageUtil.userFacing(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildCompletionDialog() {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator().withPadding(bottom: 24),
            Text(
              'Marking task as completed...',
              style: TextStyle(
                color: PaxColors.black,
                fontSize: 16,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder:
          (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Error'),
              content: Text(message),
              actions: [
                Button(
                  style: ButtonStyle.primary(),
                  onPressed: () => context.go('/home'),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTask = ref.watch(taskContextProvider)?.task;
    final taskTitle = currentTask?.title;

    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () => context.go('/home'),
                child: FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              const Spacer(),
              const Text(
                'Poll',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Consumer(
                builder: (context, ref, _) {
                  final screening =
                      ref.watch(screeningContextProvider)?.screening;
                  if (screening?.timeCreated != null) {
                    return TaskTimer(
                      screeningTimeCreated: screening!.timeCreated!.toDate(),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ).withPadding(top: 16, horizontal: 8),
        const Divider(color: PaxColors.lightGrey),
      ],
      footers: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 16),
          color: Colors.white,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    onPressed:
                        !_allQuestionsAnswered || _isSubmitting
                            ? null
                            : _openConfirmationDrawer,
                    child:
                        _isSubmitting
                            ? const CircularProgressIndicator(onSurface: true)
                            : Text(
                              'Submit poll',
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 14,
                                color: PaxColors.white,
                              ),
                            ),
                  ),
                ),
              ).withPadding(bottom: 50),
            ],
          ),
        ),
      ],
      child: PopScope(
        canPop: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (taskTitle != null && taskTitle.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                color: PaxColors.white,
                child: Text(
                  taskTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: PaxColors.deepPurple,
                    height: 1.3,
                  ),
                ),
              ),
              const Divider(color: PaxColors.lightGrey, height: 1),
            ],
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          textAlign: TextAlign.center,
          style: TextStyle(color: PaxColors.red),
        ),
      );
    }

    final poll = _pollData!;
    final sortedQuestions = [...poll.questions]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return AbsorbPointer(
      absorbing: _isSubmitting,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var qIndex = 0; qIndex < sortedQuestions.length; qIndex++) ...[
              if (qIndex > 0) const SizedBox(height: 28),
              Text(
                sortedQuestions[qIndex].text,
                style: TextStyle(
                  fontSize: sortedQuestions.length > 1 ? 18 : 22,
                  fontWeight:
                      sortedQuestions.length > 1
                          ? FontWeight.w600
                          : FontWeight.bold,
                  color: PaxColors.deepPurple,
                ),
              ),
              const SizedBox(height: 16),
              RadioGroup<String>(
                value: _selectedOptionsByQuestionId[sortedQuestions[qIndex].id],
                onChanged:
                    _isSubmitting
                        ? null
                        : (value) {
                          setState(() {
                            _selectedOptionsByQuestionId[sortedQuestions[qIndex]
                                    .id] =
                                value;
                          });
                        },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var i = 0;
                      i < sortedQuestions[qIndex].options.length;
                      i++
                    ) ...[
                      if (i > 0) const Gap(12),
                      RadioItem(
                        value: sortedQuestions[qIndex].options[i].id,
                        trailing: Text(
                          sortedQuestions[qIndex].options[i].text,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color:
                                _isSubmitting
                                    ? PaxColors.deepPurple.withValues(
                                      alpha: 0.5,
                                    )
                                    : PaxColors.deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
