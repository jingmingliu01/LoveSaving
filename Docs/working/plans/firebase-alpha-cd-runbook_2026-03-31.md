# Firebase Alpha CD Runbook

Last updated: 2026-03-31

## Goal

Provide a safe first CD step for this repo:

- merge code into `main`
- manually click a GitHub Actions workflow
- deploy Firebase configuration and Functions to the `alpha` environment

There are now two manual alpha workflows:

- `Deploy Firebase Alpha`
  - Firestore rules
  - Firestore indexes
  - Cloud Storage rules
- `Deploy Firebase Functions Alpha`
  - Firebase Functions from `Firebase/functions`

It does **not** deploy:

- Cloud Run / Spring Boot services
- any non-Firebase GCP resources

## Workflow

Workflow files:

- [deploy-firebase-alpha.yml](../../../.github/workflows/deploy-firebase-alpha.yml)
- [deploy-firebase-functions-alpha.yml](../../../.github/workflows/deploy-firebase-functions-alpha.yml)

Trigger:

- both use `workflow_dispatch`

Guardrail:

- both must run from `main`

GitHub Environment:

- both use `alpha`

## Required GitHub Environment Secrets

In GitHub:

`Settings -> Environments -> alpha`

Add these secrets:

### `FIREBASE_PROJECT_ID`

Example:

```text
lovesaving-72814
```

### `FIREBASE_SERVICE_ACCOUNT_JSON`

This should be the full JSON contents of a Firebase/GCP service account with permission to deploy:

- Firestore rules
- Firestore indexes
- Storage rules
- Firebase Functions

Practical recommendation:

- create one dedicated `alpha` deploy service account
- do not reuse an overly broad personal credential

## Recommended Alpha Deployer Service Account

Recommended name:

- `firebase-alpha-deployer-sa`

Recommended role set if you want one `alpha` service account to cover:

- Firebase config deployment
- Firebase Functions deployment
- future Cloud Run / Spring Boot alpha deployment

Project-level roles:

- `Firebase Admin`
- `Cloud Datastore Index Admin`
- `Service Usage Consumer`
- `Cloud Functions Admin`
- `Cloud Run Developer`
- `Artifact Registry Writer`

Service-account-level role:

- `Service Account User`

Notes:

- `Service Usage Consumer` is required for Firebase CLI operations that use project services.
- `Cloud Functions Admin` covers `firebase deploy --only functions`.
- `Cloud Run Developer` and `Artifact Registry Writer` are not used by the Firebase workflows today, but let you reuse the same `alpha` deployer later for Spring Boot / Cloud Run CD.
- `Service Account User` should ideally be granted on the specific runtime service accounts that future Cloud Run services and Functions use, instead of broadly across the project.

## What the workflow actually does

### `Deploy Firebase Alpha`

1. Verifies the run is on `main`
2. Checks out the repo
3. Installs Firebase CLI
4. Validates:
   - `Firebase/firebase.json`
   - `Firebase/firestore.indexes.json`
   - `Firebase/firestore.rules`
   - `Firebase/storage.rules`
5. Materializes the service account JSON from the GitHub secret
6. Runs:

```bash
firebase deploy \
  --project "$FIREBASE_PROJECT_ID" \
  --config Firebase/firebase.json \
  --only firestore:rules,firestore:indexes,storage \
  --non-interactive
```

### `Deploy Firebase Functions Alpha`

1. Verifies the run is on `main`
2. Checks out the repo
3. Installs Node.js `20`
4. Installs Firebase CLI
5. Validates:
   - `Firebase/firebase.json`
   - `Firebase/functions/package.json`
   - `Firebase/functions/package-lock.json`
   - `Firebase/functions/index.js`
6. Runs `npm ci` inside `Firebase/functions`
7. Materializes the service account JSON from the GitHub secret
8. Runs:

```bash
firebase deploy \
  --project "$FIREBASE_PROJECT_ID" \
  --config Firebase/firebase.json \
  --only functions \
  --non-interactive
```

## Why the workflows stay split

This is safer than a single all-in-one Firebase button.

It lets you establish:

- GitHub Environment usage
- manual promotion to `alpha`
- Firebase credential handling
- deploy auditability

without coupling every Firebase change to a Functions rollout.

Benefits:

- rules/indexes/storage changes can ship without touching Functions
- Functions deploy failures do not block Firebase config deploys
- GitHub Actions history is easier to read
- rollback scope is smaller

Cloud Run / Spring Boot deployment should remain a separate workflow later.

## Future expansion

Later, you can add separate workflows for:

1. Spring Boot / Cloud Run alpha deployment
2. Beta / production promotion

The current alpha service account role set already leaves room for that future Cloud Run step, but this runbook intentionally keeps Firebase and Cloud Run as different deployment workflows.
