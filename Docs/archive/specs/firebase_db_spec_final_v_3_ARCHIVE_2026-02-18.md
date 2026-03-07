# ARCHIVE: Firebase Database Specification v3 (Firestore + Storage)

> Archive status: This document is a historical design snapshot and is not the current source of truth.
> Current live spec: `/Users/jimmy/Desktop/LoveSaving/Firebase/docs/DB_SPEC_2026-02-26.md`

## 1. Scope
This specification defines the Firestore and Storage data model for an iOS app where the product is **usable only after two users link into a single Group**. All core data is Group-scoped.

## 2. Invariants
- A Group has **exactly two** members.
- Users without `currentGroupId` MUST NOT create/read Group-scoped data.
- All core writes occur under `groups/{groupId}/...`.
- `loveBalance` is the canonical value shown on Home and MUST be maintained as a cached aggregate.

## 3. Authentication
- This spec assumes **Firebase Authentication** is used for sign-up/sign-in, password resets/changes, and email verification.
- **Passwords are not stored in Firestore** (no `password` or `passwordHash` fields in `users`). Password handling is managed by Firebase Auth.
- Firestore `users/{uid}` documents store profile and app state only.

## 4. Firestore Data Model (Tree)

```
Firestore
|
+-- users (collection)
|    |
|    +-- {uid} (document)
|         - displayName: string
|         - email: string
|         - photoURL?: string
|         - currentGroupId?: string               // missing/null until linked
|         - createdAt: timestamp
|         - updatedAt: timestamp
|
+-- invites (collection)
|    |
|    +-- {inviteId} (document)
|         - fromUid: string
|         - toUid: string                         // REQUIRED: identify recipient by uid
|         - status: string                        // "pending" | "accepted" | "rejected" | "expired"
|         - createdAt: timestamp
|         - respondedAt?: timestamp
|         - expiresAt?: timestamp
|
+-- groups (collection)
     |
     +-- {groupId} (document)
     |    - groupName: string                     // required display name
     |    - memberIds: array<string>              // MUST have length == 2
     |    - createdBy: string                     // uid
     |    - status: string                        // "active" | "inactive" (soft unlink)
     |    - loveBalance: number                   // required cached aggregate
     |    - lastEventAt: timestamp                // required for summary/sorting
     |    - createdAt: timestamp
     |    - updatedAt: timestamp
     |
     +-- events (subcollection)
     |    |
     |    +-- {eventId} (document)
     |         - createdBy: string                // uid
     |         - type: string                     // "deposit" | "withdraw"
     |         - tapCount: number                 // raw taps within debounce window
     |         - delta: number                    // sigmoid(tapCount) result (persisted)
     |         - note?: string
     |         - occurredAt: timestamp
     |         - location:
     |              - lat: number
     |              - lng: number
     |              - addressText?: string
     |         - media?: array<map>
     |              - storagePath: string
     |              - contentType: string
     |         - createdAt: timestamp
     |         - updatedAt: timestamp
     |
     +-- chats (subcollection)
          |
          +-- {chatId} (document)
          |    - createdBy: string                // uid
          |    - title?: string
          |    - createdAt: timestamp
          |    - updatedAt: timestamp
          |    - lastMessageAt: timestamp
          |
          +-- messages (subcollection)
               |
               +-- {messageId} (document)
                    - role: string                // "user" | "assistant" | "system"
                    - content: string
                    - createdAt: timestamp
```

## 5. Firebase Storage Layout (Media)

```
Firebase Storage
|
+-- groups/
     |
     +-- {groupId}/
          |
          +-- events/
               |
               +-- {eventId}/
                    |
                    +-- {filename}.jpg (or .png/.heic)
```

Firestore stores only `storagePath` (and basic metadata). The binary file lives in Storage.

## 6. Entity Definitions

### 6.1 User (`users/{uid}`)
Purpose: Identity/profile and pointer to the active Group.

Required
- `displayName` (string)
- `email` (string)
- `createdAt` (timestamp)
- `updatedAt` (timestamp)

Optional
- `photoURL` (string)
- `currentGroupId` (string) — missing/null until linked

### 6.2 Invite (`invites/{inviteId}`)
Purpose: Pre-Group lifecycle object for linking two users.

Required
- `fromUid` (string)
- `toUid` (string)
- `status` (string: pending/accepted/rejected/expired)
- `createdAt` (timestamp)

Optional
- `respondedAt` (timestamp)
- `expiresAt` (timestamp)

Note
- This spec uses **UID-based matching**. Do not rely on email matching for correctness or security.

### 6.3 Group (`groups/{groupId}`)
Purpose: Shared access boundary. All core app data is owned by a Group.

Required
- `groupName` (string)
- `memberIds` (array<string>) — MUST have length 2
- `createdBy` (string)
- `status` (string: active | inactive)
- `loveBalance` (number)
- `lastEventAt` (timestamp)
- `createdAt` (timestamp)
- `updatedAt` (timestamp)

### 6.4 Event (`groups/{groupId}/events/{eventId}`)
Purpose: Atomic interaction record representing one debounced deposit/withdraw action.

Required
- `createdBy` (string)
- `type` (string: deposit | withdraw)
- `tapCount` (number)
- `delta` (number)
- `occurredAt` (timestamp)
- `location.lat` (number)
- `location.lng` (number)
- `createdAt` (timestamp)
- `updatedAt` (timestamp)

Optional
- `note` (string)
- `location.addressText` (string)
- `media` (array<map>)

### 6.5 Chat & Message (`groups/{groupId}/chats/...`)
Purpose: Stores Insight chat sessions and message history.

Chat required
- `createdBy` (string)
- `createdAt` (timestamp)
- `updatedAt` (timestamp)
- `lastMessageAt` (timestamp)

Chat optional
- `title` (string)

Message required
- `role` (string: user | assistant | system)
- `content` (string)
- `createdAt` (timestamp)

## 7. Derived Fields and Consistency (Normative)

### 7.1 Source of truth
- `groups/{groupId}/events/*` is the activity log.

### 7.2 Cached fields
- `groups/{groupId}.loveBalance` is derived from events and is the canonical Home value.
- `groups/{groupId}.lastEventAt` tracks the most recent event timestamp.

### 7.3 Concurrency and atomicity (MUST)
To prevent lost updates when both users create events concurrently, Event creation MUST be implemented with atomic semantics.

When creating an Event, the writer MUST update the Group atomically:
- `loveBalance += event.delta`
- `lastEventAt = max(lastEventAt, event.occurredAt)`
- `updatedAt = now`

Implementation options (choose one):
- Client-side Firestore **transaction** that writes the Event doc and updates the Group doc.
- Server-side **Cloud Function** triggered by Event creation that updates the Group doc.

## 8. Unlink (Soft)
Unlinking MUST be implemented as a soft deactivation:
- Set `groups/{groupId}.status = "inactive"`
- Clear both users’ `users/{uid}.currentGroupId`
- Historical data is retained (events/chats remain).

## 9. LLM Insight Context
- The current implementation sends the **full set of Events** for the active Group as context when creating an Insight chat.
- Therefore, this schema intentionally does **not** store per-chat event references.

## 10. Indexing and Query Patterns
Firestore queries use indexes. Single-field indexes are automatic; composite indexes may be required for multi-field queries.

Primary queries
- Home: read `groups/{currentGroupId}`
- Journey list: `groups/{groupId}/events` ordered by `occurredAt desc`
- Chat list: `groups/{groupId}/chats` ordered by `lastMessageAt desc`

Typical indexes
- `events.occurredAt` (ordering)
- `chats.lastMessageAt` (ordering)

## 11. Minimal Examples

### 11.1 Invite
```json
// invites/inv_001
{
  "fromUid": "uid_A",
  "toUid": "uid_B",
  "status": "pending",
  "createdAt": "2026-02-18T10:00:00Z",
  "expiresAt": "2026-02-25T10:00:00Z"
}
```

### 11.2 Group + Event
```json
// groups/g_abc123
{
  "groupName": "Onlypaws",
  "memberIds": ["uid_A", "uid_B"],
  "createdBy": "uid_A",
  "status": "active",
  "loveBalance": 0,
  "lastEventAt": "2026-02-18T10:05:00Z",
  "createdAt": "2026-02-18T10:05:00Z",
  "updatedAt": "2026-02-18T10:05:00Z"
}
```

```json
// groups/g_abc123/events/e_0001
{
  "createdBy": "uid_A",
  "type": "deposit",
  "tapCount": 12,
  "delta": 7,
  "note": "Hot pot date",
  "occurredAt": "2026-02-18T10:06:30Z",
  "location": {
    "lat": 41.30,
    "lng": -72.92,
    "addressText": "Downtown"
  },
  "media": [
    {
      "storagePath": "groups/g_abc123/events/e_0001/img_1.jpg",
      "contentType": "image/jpeg"
    }
  ],
  "createdAt": "2026-02-18T10:06:35Z",
  "updatedAt": "2026-02-18T10:06:35Z"
}
```

## 12. Security Model (High Level)
- Users may read/write `groups/{groupId}/...` only if `request.auth.uid` is in `groups/{groupId}.memberIds` and `groups/{groupId}.status == "active"`.
- Users may read/write an Invite only if `request.auth.uid == fromUid` OR `request.auth.uid == toUid`.
- Users may read/write `users/{uid}` only for their own `uid` (or restrict writes to specific fields as needed).
