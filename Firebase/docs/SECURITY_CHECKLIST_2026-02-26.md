# LoveBank Firebase Security Audit Checklist

Last updated: 2026-02-26
Scope: Firestore rules, Storage rules, and callable function access model

## A. Global invariants

- [ ] Rules version is `2` for Firestore and Storage.
- [ ] Firestore uses server-time guards (`field == request.time`) for system timestamps.
- [ ] Storage writes are size/type constrained.
- [ ] Deprecated `userLookup` path is disabled in Firestore rules.
- [ ] User lookup uses callable Cloud Function with authenticated caller requirement.

## B. Firestore checklist by path

### `/users/{uid}`

- [ ] CREATE allowed only when `request.auth.uid == uid`.
- [ ] CREATE requires valid shape: `displayName,email,emailLower,createdAt,updatedAt`.
- [ ] CREATE requires `createdAt == request.time` and `updatedAt == request.time`.
- [ ] READ allowed only for self.
- [ ] UPDATE self-path only allows `displayName,photoURL,fcmToken,updatedAt` changes.
- [ ] UPDATE self-path enforces immutable `createdAt,email,emailLower,currentGroupId`.
- [ ] UPDATE link-path only allows `currentGroupId,updatedAt` and requires group/link state-machine checks.
- [ ] UPDATE unlink-path only allows `currentGroupId,updatedAt` and requires inactive-group unlink checks.
- [ ] DELETE allowed only for self.

### `/userLookup/{uid}` (deprecated)

- [ ] CREATE denied.
- [ ] READ denied.
- [ ] UPDATE denied.
- [ ] DELETE denied.

### `/invites/{inviteId}`

- [ ] CREATE requires authenticated caller and `request.auth.uid == fromUid`.
- [ ] CREATE requires `status == "pending"`, `fromUid != toUid`, `createdAt == request.time`.
- [ ] READ allowed only to invite participants (`fromUid` or `toUid`).
- [ ] UPDATE allowed only when existing status is `pending`.
- [ ] UPDATE only allows `status,respondedAt` as affected keys.
- [ ] UPDATE requires valid transition: `accepted/rejected` by `toUid`, `expired` by participant.
- [ ] UPDATE enforces `respondedAt == request.time`.
- [ ] DELETE denied.

### `/groups/{groupId}`

- [ ] CREATE requires signed-in caller.
- [ ] CREATE requires accepted invite linkage (`sourceInviteId`) and member consistency.
- [ ] CREATE requires caller to be invite `toUid`.
- [ ] CREATE requires `createdBy` to match invite `fromUid`.
- [ ] CREATE requires strict shape and `createdAt/updatedAt == request.time`.
- [ ] READ allowed for group participants, including inactive groups.
- [ ] UPDATE allowed only for active group members.
- [ ] UPDATE aggregate path allows only `loveBalance,lastEventAt,updatedAt`.
- [ ] UPDATE aggregate path enforces `lastEventAt` monotonic non-decreasing.
- [ ] UPDATE soft-unlink path only allows `status,updatedAt` and enforces `active -> inactive`.
- [ ] DELETE denied.

### `/groups/{groupId}/events/{eventId}`

- [ ] CREATE allowed only for active group members.
- [ ] CREATE requires `createdBy == request.auth.uid`.
- [ ] CREATE requires strict shape for `type,tapCount,delta,note,occurredAt,location,media`.
- [ ] CREATE enforces `createdAt == request.time`, `recordedAt == request.time`, `updatedAt == request.time`.
- [ ] CREATE media entries must match `storagePath/contentType` schema and allowed mime set.
- [ ] CREATE media list length is capped.
- [ ] READ allowed for group participants (active or inactive).
- [ ] UPDATE allowed only for active group members and event creator.
- [ ] UPDATE only allows `note,location,media,updatedAt` as affected keys.
- [ ] UPDATE enforces immutable `createdBy,type,tapCount,delta,occurredAt,createdAt,recordedAt`.
- [ ] UPDATE enforces `updatedAt == request.time`.
- [ ] DELETE denied.

### `/groups/{groupId}/chats/{chatId}`

- [ ] CREATE allowed only for active group members.
- [ ] CREATE requires `createdBy == request.auth.uid` and server-time `createdAt/updatedAt`.
- [ ] READ allowed for group participants.
- [ ] UPDATE allowed only for active group members.
- [ ] UPDATE only allows `title,updatedAt,lastMessageAt` and requires monotonic `lastMessageAt`.
- [ ] DELETE denied.

### `/groups/{groupId}/chats/{chatId}/messages/{messageId}`

- [ ] CREATE allowed only for active group members.
- [ ] CREATE requires valid shape `role,content,createdAt` and `createdAt == request.time`.
- [ ] READ allowed for group participants.
- [ ] UPDATE denied.
- [ ] DELETE denied.

## C. Storage checklist by path

### `/groups/{groupId}/events/{eventId}/{allPaths=**}`

- [ ] READ allowed only for group participants.
- [ ] WRITE allowed only for active group members.
- [ ] WRITE requires `request.resource != null` (delete is blocked).
- [ ] WRITE requires `request.resource.size <= 8MB`.
- [ ] WRITE requires image content type in allow-list (`jpeg/jpg/png/heic/heif/webp`).
- [ ] Cross-service read uses Firestore group doc for membership/status check.

## D. Callable function checklist

### `resolveUserIdentifier` (Cloud Functions, callable)

- [ ] Caller must be authenticated (`request.auth` required).
- [ ] Input must include non-empty string `identifier`.
- [ ] Email identifiers normalized to lowercase.
- [ ] Resolution path: `getUserByEmail` for email, `getUser` for uid.
- [ ] Output limited to `uid,displayName,email`.
- [ ] Not-found mapped to callable `not-found` error.

## E. Operational checks

- [ ] Firestore rules deployed to target project.
- [ ] Firestore indexes deployed to target project.
- [ ] Storage rules deployed to target project.
- [ ] Function deployed and ACTIVE in target region.
- [ ] Storage bucket initialized in Firebase console.
- [ ] Deprecated `userLookup` collection data removed.
