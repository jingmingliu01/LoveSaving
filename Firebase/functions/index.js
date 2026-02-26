const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

admin.initializeApp();

exports.resolveUserIdentifier = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const rawIdentifier = request.data && request.data.identifier;
  if (typeof rawIdentifier !== "string") {
    throw new HttpsError("invalid-argument", "identifier must be a string.");
  }

  const trimmed = rawIdentifier.trim();
  if (!trimmed) {
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

    return {
      uid: userRecord.uid,
      displayName: userRecord.displayName || null,
      email: userRecord.email || null
    };
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "User not found.");
    }
    throw new HttpsError("internal", "Failed to resolve user identifier.");
  }
});
