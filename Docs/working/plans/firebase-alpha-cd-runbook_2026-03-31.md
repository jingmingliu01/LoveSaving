# Firebase Alpha CD Runbook

Last updated: 2026-03-31

## Goal

Provide a safe first CD step for this repo:

- merge code into `main`
- manually click a GitHub Actions workflow
- deploy Firebase configuration to the `alpha` environment

This workflow currently deploys only:

- Firestore rules
- Firestore indexes
- Cloud Storage rules

It does **not** deploy:

- Firebase Functions
- Cloud Run / Spring Boot services
- any non-Firebase GCP resources

## Workflow

Workflow file:

- [deploy-firebase-alpha.yml](/Users/jimmy/Desktop/LoveSaving/.github/workflows/deploy-firebase-alpha.yml)

Trigger:

- `workflow_dispatch`

Guardrail:

- must run from `main`

GitHub Environment:

- `alpha`

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

Practical recommendation:

- create one dedicated deploy service account for alpha
- do not reuse an overly broad personal credential

## What the workflow actually does

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

## Why this scope is intentionally narrow

This is the safest first CD slice.

It lets you establish:

- GitHub Environment usage
- manual promotion to `alpha`
- Firebase credential handling
- deploy auditability

without also coupling in:

- Spring Boot container builds
- Cloud Run deploys
- Secret Manager wiring
- Cloud Tasks / service account rollout

## Future expansion

Later, you can add separate workflows for:

1. Firebase Functions deployment
2. Spring Boot / Cloud Run alpha deployment
3. Beta / production promotion

Those should remain separate so the current `Deploy Firebase Alpha` button stays predictable.
