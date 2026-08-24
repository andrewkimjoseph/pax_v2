import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";
import { createClient } from "@supabase/supabase-js";
import ws from "ws";

import { isPollActiveOnPax } from "../../utils/pollPublicationState";
import { FUNCTION_RUNTIME_OPTS, DB, AUTH } from "../../utils/config";
import { requireParticipantHasVerifiedWithdrawalMethod } from "../../utils/helpers/requireParticipantHasVerifiedWithdrawalMethod";

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    throw new HttpsError(
      "failed-precondition",
      "Supabase is not configured for poll submissions."
    );
  }
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws as any },
  });
}

function toDateOnly(
  dateOfBirth: FirebaseFirestore.Timestamp | null | undefined
): string | null {
  if (!dateOfBirth) return null;
  return dateOfBirth.toDate().toISOString().slice(0, 10);
}

type PollAnswerInput = {
  questionId: string;
  questionOptionId: string;
};

export const submitPollResponse = onCall(
  FUNCTION_RUNTIME_OPTS,
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError(
          "unauthenticated",
          "The function must be called by an authenticated user."
        );
      }

      const userId = request.auth.uid;
      const userRecord = await AUTH.getUser(userId);
      if (userRecord.disabled) {
        throw new HttpsError("permission-denied", "This user is disabled.");
      }

      const { screeningId, taskId, questionOptionId, answers } = request.data as {
        screeningId: string;
        taskId: string;
        questionOptionId?: string;
        answers?: PollAnswerInput[];
      };

      if (!screeningId || !taskId) {
        throw new HttpsError(
          "invalid-argument",
          "Missing required parameters: screeningId, taskId."
        );
      }

      const firestore = DB();

      const taskCompletionsRef = firestore.collection("task_completions");
      const querySnapshot = await taskCompletionsRef
        .where("screeningId", "==", screeningId)
        .where("taskId", "==", taskId)
        .limit(1)
        .get();

      if (querySnapshot.empty) {
        throw new HttpsError(
          "not-found",
          "No task completion found with the provided screeningId and taskId."
        );
      }

      const taskCompletionDoc = querySnapshot.docs[0];
      const taskCompletionData = taskCompletionDoc.data();

      if (taskCompletionData.timeCompleted) {
        throw new HttpsError(
          "already-exists",
          "This poll has already been answered."
        );
      }

      const participantDoc = await firestore.collection("participants").doc(userId).get();
      if (!participantDoc.exists) {
        throw new HttpsError("not-found", "Participant profile not found.");
      }

      await requireParticipantHasVerifiedWithdrawalMethod(userId);

      const participant = participantDoc.data()!;
      const supabase = getSupabaseAdmin();

      const { data: pollTask, error: pollTaskError } = await supabase
        .from("tasks")
        .select("id, is_active, deadline")
        .eq("pax_task_id", taskId)
        .single();

      if (pollTaskError || !pollTask) {
        throw new HttpsError("not-found", "Poll not found.");
      }

      const isCollecting = isPollActiveOnPax({
        isActive: pollTask.is_active,
        deadline: pollTask.deadline,
      });

      if (!isCollecting) {
        throw new HttpsError(
          "failed-precondition",
          pollTask.deadline && new Date(pollTask.deadline) <= new Date()
            ? "This poll has ended."
            : "This poll is not accepting responses."
        );
      }

      const { data: questions, error: questionsError } = await supabase
        .from("questions")
        .select("id")
        .eq("task_id", pollTask.id)
        .order("sort_order", { ascending: true });

      if (questionsError || !questions?.length) {
        throw new HttpsError("not-found", "Poll questions not found.");
      }

      const questionIds = new Set(questions.map((q) => q.id));

      let normalizedAnswers: PollAnswerInput[];

      if (Array.isArray(answers) && answers.length > 0) {
        normalizedAnswers = answers;
      } else if (questionOptionId) {
        normalizedAnswers = [
          {
            questionId: questions[0].id,
            questionOptionId,
          },
        ];
      } else {
        throw new HttpsError(
          "invalid-argument",
          "Missing answers: provide answers[] or legacy questionOptionId."
        );
      }

      if (normalizedAnswers.length !== questions.length) {
        throw new HttpsError(
          "invalid-argument",
          "You must answer every poll question before submitting."
        );
      }

      const answeredQuestionIds = new Set<string>();
      for (const answer of normalizedAnswers) {
        if (!answer.questionId || !answer.questionOptionId) {
          throw new HttpsError("invalid-argument", "Each answer must include questionId and questionOptionId.");
        }
        if (!questionIds.has(answer.questionId)) {
          throw new HttpsError("invalid-argument", "Invalid question for this poll.");
        }
        if (answeredQuestionIds.has(answer.questionId)) {
          throw new HttpsError("invalid-argument", "Duplicate answer for the same question.");
        }
        answeredQuestionIds.add(answer.questionId);
      }

      for (const answer of normalizedAnswers) {
        const { data: option, error: optionError } = await supabase
          .from("question_options")
          .select("id")
          .eq("id", answer.questionOptionId)
          .eq("question_id", answer.questionId)
          .single();

        if (optionError || !option) {
          throw new HttpsError("invalid-argument", "Invalid answer option.");
        }
      }

      const { data: existingAnswers, error: existingError } = await supabase
        .from("answers")
        .select("question_id")
        .eq("participant_id", userId)
        .in(
          "question_id",
          normalizedAnswers.map((answer) => answer.questionId)
        );

      if (existingError) {
        throw new HttpsError("internal", existingError.message);
      }

      if (existingAnswers && existingAnswers.length > 0) {
        throw new HttpsError("already-exists", "You have already answered this poll.");
      }

      const { error: participantError } = await supabase.from("participants").upsert({
        id: userId,
        gender: participant.gender ?? null,
        country: participant.country ?? null,
        date_of_birth: toDateOnly(participant.dateOfBirth),
        display_name: participant.displayName ?? null,
        updated_at: new Date().toISOString(),
      });

      if (participantError) {
        throw new HttpsError("internal", participantError.message);
      }

      const answerRows = normalizedAnswers.map((answer) => ({
        task_id: pollTask.id,
        pax_task_id: taskId,
        question_id: answer.questionId,
        question_option_id: answer.questionOptionId,
        participant_id: userId,
        pax_task_completion_id: taskCompletionDoc.id,
      }));

      const { error: answerError } = await supabase.from("answers").insert(answerRows);

      if (answerError) {
        if (answerError.code === "23505") {
          throw new HttpsError("already-exists", "You have already answered this poll.");
        }
        throw new HttpsError("internal", answerError.message);
      }

      await taskCompletionDoc.ref.update({
        timeCompleted: FieldValue.serverTimestamp(),
        timeUpdated: FieldValue.serverTimestamp(),
        isValid: true,
      });

      logger.info("Poll response submitted", {
        userId,
        taskId,
        screeningId,
        taskCompletionId: taskCompletionDoc.id,
        answerCount: normalizedAnswers.length,
      });

      return {
        success: true,
        taskCompletionId: taskCompletionDoc.id,
      };
    } catch (error) {
      logger.error("Error submitting poll response", { error });
      throw error;
    }
  }
);
