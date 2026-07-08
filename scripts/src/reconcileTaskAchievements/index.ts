/**
 * Reconcile Task Starter / Task Expert achievements from task_completions.
 * Counts only completions with timeCompleted set and isValid === true.
 *
 * Run from pax_v2/scripts:
 *   npx tsx src/reconcileTaskAchievements/index.ts --dry-run
 *   npx tsx src/reconcileTaskAchievements/index.ts --apply --participant-id <uid>
 *   npx tsx src/reconcileTaskAchievements/index.ts --apply
 */
import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

const TASK_STARTER = "Task Starter";
const TASK_EXPERT = "Task Expert";
const TASK_STARTER_TASKS_NEEDED = 1;
const TASK_EXPERT_TASKS_NEEDED = 10;
const TASK_STARTER_AMOUNT = 100;
const TASK_EXPERT_AMOUNT = 200;

const serviceAccountPath = path.resolve(
  __dirname,
  "../../env/thepaxapp-firebase-adminsdk-fbsvc-d9e8b1fdff.json"
);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(
      JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"))
    ),
  });
}

const db = admin.firestore();

type AchievementDoc = {
  id: string;
  name?: string;
  participantId?: string;
  tasksCompleted?: number;
  tasksNeededForCompletion?: number;
  timeCompleted?: admin.firestore.Timestamp;
  timeCreated?: admin.firestore.Timestamp;
  timeUpdated?: admin.firestore.Timestamp;
  amountEarned?: number;
  txnHash?: string | null;
};

type ReconcileRow = {
  participantId: string;
  completedCount: number;
  taskStarterAction: string;
  taskExpertBefore: string;
  taskExpertAfter: string;
  applied: boolean;
};

function parseArgs() {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const participantIdIndex = args.indexOf("--participant-id");
  const participantId =
    participantIdIndex >= 0 ? args[participantIdIndex + 1] : undefined;

  if (participantIdIndex >= 0 && !participantId) {
    throw new Error("--participant-id requires a value");
  }

  return { apply, participantId };
}

function isCompletedCompletion(data: admin.firestore.DocumentData): boolean {
  if (!data.timeCompleted) return false;
  if (data.isValid !== true) return false;
  return true;
}

async function loadCompletedCounts(
  participantIdFilter?: string
): Promise<Map<string, number>> {
  const counts = new Map<string, number>();

  let query: admin.firestore.Query = db.collection("task_completions");
  if (participantIdFilter) {
    query = query.where("participantId", "==", participantIdFilter);
  }

  const snapshot = await query.get();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!isCompletedCompletion(data)) continue;

    const participantId = data.participantId as string | undefined;
    if (!participantId) continue;

    counts.set(participantId, (counts.get(participantId) ?? 0) + 1);
  }

  return counts;
}

async function loadAchievements(
  participantId: string
): Promise<AchievementDoc[]> {
  const snapshot = await db
    .collection("achievements")
    .where("participantId", "==", participantId)
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...(doc.data() as Omit<AchievementDoc, "id">),
  }));
}

function csvEscape(value: string | number | boolean): string {
  const str = String(value);
  if (str.includes(",") || str.includes('"') || str.includes("\n")) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

async function reconcileParticipant(
  participantId: string,
  completedCount: number,
  apply: boolean
): Promise<ReconcileRow> {
  const achievements = await loadAchievements(participantId);
  const taskStarter = achievements.find((a) => a.name === TASK_STARTER);
  const taskExpert = achievements.find((a) => a.name === TASK_EXPERT);

  const taskExpertBefore = taskExpert
    ? String(taskExpert.tasksCompleted ?? 0)
    : "missing";

  let taskStarterAction = "none";
  let taskExpertAfter = taskExpertBefore;
  let changed = false;

  const hasCompletedTaskStarter =
    taskStarter != null && taskStarter.timeCompleted != null;

  if (completedCount >= 1 && !hasCompletedTaskStarter) {
    taskStarterAction = taskStarter ? "complete_existing" : "create";
    changed = true;

    if (apply) {
      const now = admin.firestore.Timestamp.now();
      if (taskStarter) {
        await db.collection("achievements").doc(taskStarter.id).update({
          tasksCompleted: TASK_STARTER_TASKS_NEEDED,
          tasksNeededForCompletion: TASK_STARTER_TASKS_NEEDED,
          timeCompleted: now,
          timeUpdated: now,
          amountEarned: taskStarter.amountEarned ?? TASK_STARTER_AMOUNT,
        });
      } else {
        await db.collection("achievements").add({
          participantId,
          name: TASK_STARTER,
          tasksCompleted: TASK_STARTER_TASKS_NEEDED,
          tasksNeededForCompletion: TASK_STARTER_TASKS_NEEDED,
          timeCreated: now,
          timeCompleted: now,
          amountEarned: TASK_STARTER_AMOUNT,
        });
      }
    }
  }

  const targetExpertCount = Math.min(completedCount, TASK_EXPERT_TASKS_NEEDED);

  if (taskExpert?.txnHash) {
    taskExpertAfter = String(taskExpert.tasksCompleted ?? 0);
  } else if (targetExpertCount === 0) {
    taskExpertAfter = taskExpert
      ? String(taskExpert.tasksCompleted ?? 0)
      : "missing";
  } else if (!taskExpert) {
    taskExpertAfter = String(targetExpertCount);
    if (targetExpertCount > 0) {
      changed = true;
      if (apply) {
        const now = admin.firestore.Timestamp.now();
        await db.collection("achievements").add({
          participantId,
          name: TASK_EXPERT,
          tasksCompleted: targetExpertCount,
          tasksNeededForCompletion: TASK_EXPERT_TASKS_NEEDED,
          timeCreated: now,
          ...(targetExpertCount >= TASK_EXPERT_TASKS_NEEDED
            ? { timeCompleted: now, timeUpdated: now }
            : {}),
          amountEarned: TASK_EXPERT_AMOUNT,
        });
      }
    }
  } else {
    const current = taskExpert.tasksCompleted ?? 0;
    if (current < targetExpertCount) {
      taskExpertAfter = String(targetExpertCount);
      changed = true;

      if (apply) {
        const now = admin.firestore.Timestamp.now();
        const update: Record<string, unknown> = {
          tasksCompleted: targetExpertCount,
        };
        if (targetExpertCount >= TASK_EXPERT_TASKS_NEEDED) {
          update.timeCompleted = now;
          update.timeUpdated = now;
        }
        await db.collection("achievements").doc(taskExpert.id).update(update);
      }
    } else {
      taskExpertAfter = String(current);
    }
  }

  return {
    participantId,
    completedCount,
    taskStarterAction,
    taskExpertBefore,
    taskExpertAfter,
    applied: apply && changed,
  };
}

async function main() {
  const { apply, participantId } = parseArgs();
  const dryRun = !apply;

  console.log(
    dryRun
      ? "Dry run (no writes). Pass --apply to persist changes."
      : "Apply mode: writing changes to Firestore."
  );

  if (participantId) {
    console.log(`Filtering to participant: ${participantId}`);
  }

  const completedCounts = await loadCompletedCounts(participantId);
  const participantIds = [...completedCounts.keys()].sort();

  console.log(`Found ${participantIds.length} participant(s) with completions.`);

  const rows: ReconcileRow[] = [];
  for (const id of participantIds) {
    const completedCount = completedCounts.get(id) ?? 0;
    const row = await reconcileParticipant(id, completedCount, apply);
    rows.push(row);

    if (
      row.taskStarterAction !== "none" ||
      row.taskExpertBefore !== row.taskExpertAfter
    ) {
      console.log(
        `${id}: completions=${row.completedCount}, starter=${row.taskStarterAction}, expert ${row.taskExpertBefore} -> ${row.taskExpertAfter}${apply ? " (applied)" : " (dry-run)"}`
      );
    }
  }

  const outputsDir = path.resolve(__dirname, "../../outputs");
  fs.mkdirSync(outputsDir, { recursive: true });

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const outputPath = path.join(
    outputsDir,
    `task_achievement_reconcile_${timestamp}.csv`
  );

  const header =
    "participantId,completedCount,taskStarterAction,taskExpertBefore,taskExpertAfter,applied";
  const body = rows
    .map((row) =>
      [
        csvEscape(row.participantId),
        csvEscape(row.completedCount),
        csvEscape(row.taskStarterAction),
        csvEscape(row.taskExpertBefore),
        csvEscape(row.taskExpertAfter),
        csvEscape(row.applied),
      ].join(",")
    )
    .join("\n");

  fs.writeFileSync(outputPath, `${header}\n${body}\n`);
  console.log(`Wrote report: ${outputPath}`);

  const changedCount = rows.filter(
    (row) =>
      row.taskStarterAction !== "none" ||
      row.taskExpertBefore !== row.taskExpertAfter
  ).length;
  console.log(`Participants needing changes: ${changedCount}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
