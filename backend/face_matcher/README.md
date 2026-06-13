# HEART Face Matcher Backend

Cloud Run service for shared iOS/Android face matching.

## Deploy

Build from the repository root so Docker can copy the existing MobileFaceNet model:

```bash
gcloud builds submit . \
  --config backend/face_matcher/cloudbuild.yaml \
  --substitutions _IMAGE=us-central1-docker.pkg.dev/PROJECT_ID/heart/face-matcher
```

Deploy the image:

```bash
gcloud run deploy heart-face-matcher \
  --image us-central1-docker.pkg.dev/PROJECT_ID/heart/face-matcher \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars RECOGNITION_THRESHOLD=1.1
```

Then run Flutter with:

```bash
flutter run --dart-define=FACE_BACKEND_URL=https://YOUR-CLOUD-RUN-URL
```

The service still verifies Firebase ID tokens, so `--allow-unauthenticated`
only lets the app reach the HTTP endpoint. Unauthorized requests are rejected.
