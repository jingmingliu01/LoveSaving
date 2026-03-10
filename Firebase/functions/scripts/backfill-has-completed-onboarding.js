#!/usr/bin/env node

const admin = require("firebase-admin");

function resolveProjectId() {
  return (
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    null
  );
}

async function main() {
  const projectId = resolveProjectId();
  if (!projectId) {
    throw new Error(
      "Missing project id. Set FIREBASE_PROJECT_ID, GCLOUD_PROJECT, or GOOGLE_CLOUD_PROJECT before running."
    );
  }

  const isDryRun = process.argv.includes("--dry-run");

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });

  const db = admin.firestore();
  const usersSnapshot = await db.collection("users").get();

  let scanned = 0;
  let updated = 0;
  let alreadyPresent = 0;
  let failures = 0;
  let batch = db.batch();
  let pendingOps = 0;

  for (const doc of usersSnapshot.docs) {
    scanned += 1;
    const data = doc.data();
    if (Object.prototype.hasOwnProperty.call(data, "hasCompletedOnboarding")) {
      alreadyPresent += 1;
      continue;
    }

    updated += 1;
    if (isDryRun) {
      continue;
    }

    batch.set(
      doc.ref,
      {
        hasCompletedOnboarding: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    pendingOps += 1;

    if (pendingOps === 400) {
      try {
        await batch.commit();
      } catch (error) {
        failures += pendingOps;
        console.error("Batch commit failed:", error);
      }
      batch = db.batch();
      pendingOps = 0;
    }
  }

  if (!isDryRun && pendingOps > 0) {
    try {
      await batch.commit();
    } catch (error) {
      failures += pendingOps;
      console.error("Final batch commit failed:", error);
    }
  }

  console.log(
    JSON.stringify(
      {
        projectId,
        dryRun: isDryRun,
        scanned,
        updated,
        alreadyPresent,
        failures,
      },
      null,
      2
    )
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
