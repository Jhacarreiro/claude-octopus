Introductory prose that the deterministic normalizer must ignore.

## Parallel decomposition

### 1. [REASONING] Contract audit

**Reads:** `/context/approved-plan.md`

Verify:
- Compare producer and consumer paths.
- Record an explicit blocked or resolved decision.

**Acceptance evidence:** path matrix.

---

### 2. [CODING] Android auth flow

**Files:**
- `app/build.gradle.kts`
- `app/src/main/App.kt`

**Creates:**
- `app/src/main/AuthScreen.kt`

Implement and verify:
- Replace anonymous startup with authenticated session observation.
- Add sign-out cache isolation.

**Acceptance evidence:** unit tests.

---

### 3. [CODING] CI artifact

**Files:** `.github/workflows/android-ci.yml`

Update CI to run:
- Android tests.
- Upload the debug APK.
