const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

admin.initializeApp();

exports.resolveUserIdentifier = onCall(async (request) => {
  const startedAt = Date.now();
  const authUid = request.auth && request.auth.uid ? request.auth.uid : null;

  if (!request.auth) {
    logger.warn("resolve_user_identifier_denied", {
      op: "resolve_user_identifier",
      status: "unauthenticated",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
    });
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const rawIdentifier = request.data && request.data.identifier;
  if (typeof rawIdentifier !== "string") {
    logger.warn("resolve_user_identifier_invalid_argument", {
      op: "resolve_user_identifier",
      status: "invalid_argument",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      identifier_type: typeof rawIdentifier,
    });
    throw new HttpsError("invalid-argument", "identifier must be a string.");
  }

  const trimmed = rawIdentifier.trim();
  if (!trimmed) {
    logger.warn("resolve_user_identifier_empty_identifier", {
      op: "resolve_user_identifier",
      status: "invalid_argument",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
    });
    throw new HttpsError("invalid-argument", "identifier is required.");
  }

  const identifier = trimmed.includes("@") ? trimmed.toLowerCase() : trimmed;

  try {
    let userRecord;
    if (identifier.includes("@")) {
      userRecord = await admin.auth().getUserByEmail(identifier);
    } else {
      userRecord = await admin.auth().getUser(identifier);
    }

    logger.info("resolve_user_identifier_success", {
      op: "resolve_user_identifier",
      status: "success",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      target_uid: userRecord.uid,
      identifier_kind: identifier.includes("@") ? "email" : "uid",
    });

    return {
      uid: userRecord.uid,
      displayName: userRecord.displayName || null,
      email: userRecord.email || null
    };
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      logger.info("resolve_user_identifier_not_found", {
        op: "resolve_user_identifier",
        status: "not_found",
        latency_ms: Date.now() - startedAt,
        auth_uid: authUid,
        identifier_kind: identifier.includes("@") ? "email" : "uid",
      });
      throw new HttpsError("not-found", "User not found.");
    }
    logger.error("resolve_user_identifier_internal_error", {
      op: "resolve_user_identifier",
      status: "internal_error",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      error_code: error && error.code ? error.code : "unknown",
      error_message: error && error.message ? error.message : "unknown",
    });
    throw new HttpsError("internal", "Failed to resolve user identifier.");
  }
});

exports.respondToInvite = onCall(async (request) => {
  const startedAt = Date.now();
  const authUid = request.auth && request.auth.uid ? request.auth.uid : null;

  if (!request.auth) {
    logger.warn("respond_to_invite_denied", {
      op: "respond_to_invite",
      status: "unauthenticated",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
    });
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const inviteId = request.data && request.data.inviteId;
  const rawStatus = request.data && request.data.status;
  if (typeof inviteId !== "string" || typeof rawStatus !== "string") {
    logger.warn("respond_to_invite_invalid_argument", {
      op: "respond_to_invite",
      status: "invalid_argument",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      invite_id_type: typeof inviteId,
      status_type: typeof rawStatus,
    });
    throw new HttpsError("invalid-argument", "inviteId and status are required.");
  }

  const status = rawStatus.trim().toLowerCase();
  if (!["accepted", "rejected", "expired"].includes(status)) {
    logger.warn("respond_to_invite_invalid_status", {
      op: "respond_to_invite",
      status: "invalid_argument",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      invite_id: inviteId,
      requested_status: rawStatus,
    });
    throw new HttpsError("invalid-argument", "Unsupported invite status.");
  }

  const db = admin.firestore();
  const inviteRef = db.collection("invites").doc(inviteId);
  const inviteSnapshot = await inviteRef.get();
  if (!inviteSnapshot.exists) {
    logger.info("respond_to_invite_not_found", {
      op: "respond_to_invite",
      status: "not_found",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      invite_id: inviteId,
    });
    throw new HttpsError("not-found", "Invite not found.");
  }

  const invite = inviteSnapshot.data();
  const isParticipant = authUid === invite.fromUid || authUid === invite.toUid;
  const isRecipient = authUid === invite.toUid;
  const isPending = invite.status === "pending";

  if (!isParticipant || (status !== "expired" && !isRecipient)) {
    logger.warn("respond_to_invite_permission_denied", {
      op: "respond_to_invite",
      status: "permission_denied",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      invite_id: inviteId,
      invite_from: invite.fromUid || null,
      invite_to: invite.toUid || null,
      requested_status: status,
    });
    throw new HttpsError("permission-denied", "You are not allowed to respond to this invite.");
  }

  if (!isPending) {
    logger.info("respond_to_invite_not_pending", {
      op: "respond_to_invite",
      status: "failed_precondition",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      invite_id: inviteId,
      current_status: invite.status || null,
      requested_status: status,
    });
    throw new HttpsError("failed-precondition", "Invite is no longer pending.");
  }

  if (status === "expired" && !isParticipant) {
    throw new HttpsError("permission-denied", "Only invite participants can expire an invite.");
  }

  try {
    const batch = db.batch();
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    batch.update(inviteRef, {
      status,
      respondedAt: timestamp,
    });

    let groupId = null;
    if (status === "accepted") {
      const groupRef = db.collection("groups").doc();
      groupId = groupRef.id;
      batch.set(groupRef, {
        groupName: "LoveSaving Group",
        memberIds: [invite.fromUid, invite.toUid],
        createdBy: invite.fromUid,
        sourceInviteId: inviteId,
        status: "active",
        loveBalance: 0,
        lastEventAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      });

      batch.set(db.collection("users").doc(invite.fromUid), {
        currentGroupId: groupId,
        updatedAt: timestamp,
      }, { merge: true });
      batch.set(db.collection("users").doc(invite.toUid), {
        currentGroupId: groupId,
        updatedAt: timestamp,
      }, { merge: true });
    }

    await batch.commit();

    logger.info("respond_to_invite_success", {
      op: "respond_to_invite",
      status: "success",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      invite_id: inviteId,
      requested_status: status,
      group_id: groupId,
    });

    return {
      inviteId,
      status,
      groupId,
    };
  } catch (error) {
    logger.error("respond_to_invite_internal_error", {
      op: "respond_to_invite",
      status: "internal_error",
      latency_ms: Date.now() - startedAt,
      auth_uid: authUid,
      invite_id: inviteId,
      requested_status: status,
      error_code: error && error.code ? error.code : "unknown",
      error_message: error && error.message ? error.message : "unknown",
    });
    throw new HttpsError("internal", "Failed to update invite.");
  }
});
