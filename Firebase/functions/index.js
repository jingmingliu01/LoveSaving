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
