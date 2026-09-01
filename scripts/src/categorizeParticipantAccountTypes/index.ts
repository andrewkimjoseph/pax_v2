/**
 * Backfill participants.accountType ("v1" | "v2") for users missing it.
 * Classification mirrors account_type_provider.dart + PaxAccount model,
 * with onboardingType fallback when wallet signals are absent.
 *
 * Run from pax_v2/scripts:
 *   npm run categorize-account-types
 *   npm run categorize-account-types:apply
 *   npm run categorize-account-types:apply -- --participant-id <uid>
 */
import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

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

type AccountType = "v1" | "v2";
type InferredType = AccountType | "unknown";

type PaxAccountData = {
  contractAddress?: string | null;
  eoWalletAddress?: string | null;
  serverWalletId?: string | null;
};

type PaxWalletData = {
  participantId?: string;
  eoAddress?: string | null;
};

type PaymentMethodData = {
  participantId?: string;
  name?: string;
};

type CategorizeRow = {
  participantId: string;
  currentAccountType: string;
  onboardingType: string;
  inferredType: InferredType;
  reason: string;
  contractAddress: string;
  eoWalletAddress: string;
  hasPaxWallet: string;
  paymentMethodNames: string;
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

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isUncategorizedAccountType(value: unknown): boolean {
  return value == null || (typeof value === "string" && value.trim() === "");
}

function csvEscape(value: string | number | boolean): string {
  const str = String(value);
  if (str.includes(",") || str.includes('"') || str.includes("\n")) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function indexByParticipantId<T extends { participantId?: string }>(
  docs: admin.firestore.QueryDocumentSnapshot[]
): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const doc of docs) {
    const data = doc.data() as T;
    const participantId = data.participantId;
    if (!participantId) continue;
    const existing = map.get(participantId) ?? [];
    existing.push(data);
    map.set(participantId, existing);
  }
  return map;
}

function inferAccountType(
  paxAccount: PaxAccountData | undefined,
  paxWallets: PaxWalletData[],
  paymentMethods: PaymentMethodData[],
  onboardingType: string | null | undefined
): { inferredType: InferredType; reason: string } {
  const contractAddress = paxAccount?.contractAddress;
  const eoWalletAddress = paxAccount?.eoWalletAddress;
  const serverWalletId = paxAccount?.serverWalletId;

  if (isNonEmptyString(contractAddress)) {
    return { inferredType: "v1", reason: "contractAddress" };
  }

  if (isNonEmptyString(eoWalletAddress)) {
    return { inferredType: "v2", reason: "eoWalletAddress" };
  }

  const hasPaxWalletDoc = paxWallets.some((wallet) =>
    isNonEmptyString(wallet.eoAddress)
  );
  if (hasPaxWalletDoc) {
    return { inferredType: "v2", reason: "pax_wallets" };
  }

  const paymentMethodNames = paymentMethods
    .map((method) => method.name)
    .filter((name): name is string => isNonEmptyString(name));

  if (paymentMethodNames.includes("PaxWallet")) {
    return { inferredType: "v2", reason: "payment_method_PaxWallet" };
  }

  if (isNonEmptyString(serverWalletId)) {
    return { inferredType: "v1", reason: "serverWalletId" };
  }

  const legacyPaymentMethod = paymentMethodNames.find((name) =>
    ["MiniPay", "GoodWallet"].includes(name)
  );
  if (legacyPaymentMethod) {
    return {
      inferredType: "v1",
      reason: `payment_method_${legacyPaymentMethod}`,
    };
  }

  if (onboardingType === "v1_legacy") {
    return { inferredType: "v1", reason: "onboardingType_v1_legacy" };
  }

  if (onboardingType === "v2_native") {
    return { inferredType: "v2", reason: "onboardingType_v2_native" };
  }

  if (onboardingType === "mixed") {
    return { inferredType: "v2", reason: "onboardingType_mixed" };
  }

  return { inferredType: "unknown", reason: "no_wallet_or_onboarding_signals" };
}

async function loadUncategorizedParticipants(
  participantIdFilter?: string
): Promise<
  Array<{
    id: string;
    accountType: string | null | undefined;
    onboardingType: string | null | undefined;
  }>
> {
  if (participantIdFilter) {
    const doc = await db
      .collection("participants")
      .doc(participantIdFilter)
      .get();
    if (!doc.exists) {
      throw new Error(`Participant not found: ${participantIdFilter}`);
    }
    const data = doc.data() ?? {};
    return [
      {
        id: doc.id,
        accountType: data.accountType,
        onboardingType: data.onboardingType,
      },
    ];
  }

  const snapshot = await db.collection("participants").get();
  return snapshot.docs
    .map((doc) => ({
      id: doc.id,
      accountType: doc.data().accountType as string | null | undefined,
      onboardingType: doc.data().onboardingType as string | null | undefined,
    }))
    .filter((participant) => isUncategorizedAccountType(participant.accountType));
}

async function loadPaxAccounts(
  participantIds: Set<string>
): Promise<Map<string, PaxAccountData>> {
  const map = new Map<string, PaxAccountData>();
  if (participantIds.size === 0) return map;

  const snapshot = await db.collection("pax_accounts").get();
  for (const doc of snapshot.docs) {
    if (!participantIds.has(doc.id)) continue;
    map.set(doc.id, doc.data() as PaxAccountData);
  }
  return map;
}

async function loadPaxWalletsByParticipantId(): Promise<
  Map<string, PaxWalletData[]>
> {
  const snapshot = await db.collection("pax_wallets").get();
  return indexByParticipantId<PaxWalletData>(snapshot.docs);
}

async function loadPaymentMethodsByParticipantId(): Promise<
  Map<string, PaymentMethodData[]>
> {
  const snapshot = await db.collection("payment_methods").get();
  return indexByParticipantId<PaymentMethodData>(snapshot.docs);
}

async function categorizeParticipant(
  participantId: string,
  currentAccountType: string | null | undefined,
  onboardingType: string | null | undefined,
  paxAccount: PaxAccountData | undefined,
  paxWallets: PaxWalletData[],
  paymentMethods: PaymentMethodData[],
  apply: boolean
): Promise<CategorizeRow> {
  const { inferredType, reason } = inferAccountType(
    paxAccount,
    paxWallets,
    paymentMethods,
    onboardingType
  );

  const paymentMethodNames = paymentMethods
    .map((method) => method.name)
    .filter((name): name is string => isNonEmptyString(name))
    .join(";");

  let applied = false;
  if (
    apply &&
    (inferredType === "v1" || inferredType === "v2")
  ) {
    await db.collection("participants").doc(participantId).update({
      accountType: inferredType,
      timeUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    applied = true;
  }

  return {
    participantId,
    currentAccountType:
      currentAccountType == null || currentAccountType === ""
        ? "null"
        : currentAccountType,
    onboardingType:
      onboardingType == null || onboardingType === ""
        ? "null"
        : onboardingType,
    inferredType,
    reason,
    contractAddress: isNonEmptyString(paxAccount?.contractAddress)
      ? "yes"
      : "no",
    eoWalletAddress: isNonEmptyString(paxAccount?.eoWalletAddress)
      ? "yes"
      : "no",
    hasPaxWallet: paxWallets.some((wallet) => isNonEmptyString(wallet.eoAddress))
      ? "yes"
      : "no",
    paymentMethodNames,
    applied,
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

  const participants = await loadUncategorizedParticipants(participantId);
  console.log(
    `Found ${participants.length} uncategorized participant(s) (accountType null/missing).`
  );

  const participantIdSet = new Set(participants.map((participant) => participant.id));

  const [paxAccounts, paxWalletsByParticipantId, paymentMethodsByParticipantId] =
    await Promise.all([
      loadPaxAccounts(participantIdSet),
      loadPaxWalletsByParticipantId(),
      loadPaymentMethodsByParticipantId(),
    ]);

  const rows: CategorizeRow[] = [];
  for (const participant of participants.sort((a, b) => a.id.localeCompare(b.id))) {
    const row = await categorizeParticipant(
      participant.id,
      participant.accountType,
      participant.onboardingType,
      paxAccounts.get(participant.id),
      paxWalletsByParticipantId.get(participant.id) ?? [],
      paymentMethodsByParticipantId.get(participant.id) ?? [],
      apply
    );
    rows.push(row);

    if (row.inferredType !== "unknown") {
      console.log(
        `${row.participantId}: ${row.currentAccountType} -> ${row.inferredType} (${row.reason})${apply ? " (applied)" : " (dry-run)"}`
      );
    }
  }

  const outputsDir = path.resolve(__dirname, "../../outputs");
  fs.mkdirSync(outputsDir, { recursive: true });

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const outputPath = path.join(
    outputsDir,
    `account_type_categorize_${timestamp}.csv`
  );

  const header = [
    "participantId",
    "currentAccountType",
    "onboardingType",
    "inferredType",
    "reason",
    "contractAddress",
    "eoWalletAddress",
    "hasPaxWallet",
    "paymentMethodNames",
    "applied",
  ].join(",");

  const body = rows
    .map((row) =>
      [
        csvEscape(row.participantId),
        csvEscape(row.currentAccountType),
        csvEscape(row.onboardingType),
        csvEscape(row.inferredType),
        csvEscape(row.reason),
        csvEscape(row.contractAddress),
        csvEscape(row.eoWalletAddress),
        csvEscape(row.hasPaxWallet),
        csvEscape(row.paymentMethodNames),
        csvEscape(row.applied),
      ].join(",")
    )
    .join("\n");

  fs.writeFileSync(outputPath, `${header}\n${body}\n`);
  console.log(`Wrote report: ${outputPath}`);

  const v1Count = rows.filter((row) => row.inferredType === "v1").length;
  const v2Count = rows.filter((row) => row.inferredType === "v2").length;
  const unknownCount = rows.filter((row) => row.inferredType === "unknown").length;
  const appliedCount = rows.filter((row) => row.applied).length;
  const walletSignalCount = rows.filter(
    (row) => row.inferredType !== "unknown" && !row.reason.startsWith("onboardingType_")
  ).length;
  const onboardingFallbackCount = rows.filter((row) =>
    row.reason.startsWith("onboardingType_")
  ).length;

  console.log(`Inferred v1: ${v1Count}`);
  console.log(`Inferred v2: ${v2Count}`);
  console.log(`Unknown (skipped): ${unknownCount}`);
  console.log(`Classified via wallet signals: ${walletSignalCount}`);
  console.log(`Classified via onboardingType fallback: ${onboardingFallbackCount}`);
  console.log(`Applied writes: ${appliedCount}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
