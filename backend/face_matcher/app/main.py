import io
import math
import os
import uuid
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

import firebase_admin
import numpy as np
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from firebase_admin import auth, credentials, firestore, storage
from PIL import Image
from tflite_runtime.interpreter import Interpreter


MODEL_PATH = os.environ.get("MODEL_PATH", "/app/models/mobilefacenet.tflite")
RECOGNITION_THRESHOLD = float(os.environ.get("RECOGNITION_THRESHOLD", "1.1"))
STORAGE_BUCKET = os.environ.get("FIREBASE_STORAGE_BUCKET", "heart-nagaland.firebasestorage.app")
INPUT_SIZE = 112

app = FastAPI(title="HEART Face Matcher")
interpreter: Interpreter | None = None
input_details: list[dict[str, Any]] = []
output_details: list[dict[str, Any]] = []


def _init_firebase() -> None:
    if firebase_admin._apps:
        return

    options = {"storageBucket": STORAGE_BUCKET}
    credentials_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if credentials_path:
        firebase_admin.initialize_app(credentials.Certificate(credentials_path), options)
    else:
        firebase_admin.initialize_app(options=options)


def _db() -> firestore.Client:
    _init_firebase()
    return firestore.client()


@app.on_event("startup")
def startup() -> None:
    global interpreter, input_details, output_details
    _init_firebase()
    interpreter = Interpreter(model_path=MODEL_PATH, num_threads=2)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()


def _require_uid(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Firebase ID token")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        decoded = auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase ID token") from exc
    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Invalid Firebase ID token")
    return uid


def _embedding_from_bytes(raw: bytes) -> list[float]:
    if interpreter is None:
        raise HTTPException(status_code=503, detail="Model is not loaded")

    if not raw:
        raise HTTPException(status_code=400, detail="Image file is empty")

    try:
        image = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid image file") from exc

    image = image.resize((INPUT_SIZE, INPUT_SIZE))
    arr = np.asarray(image).astype(np.float32)
    arr = (arr / 127.5) - 1.0
    arr = np.expand_dims(arr, axis=0)

    detail = input_details[0]
    if detail["dtype"] == np.uint8:
        scale, zero_point = detail["quantization"]
        if scale == 0:
            raise HTTPException(status_code=500, detail="Invalid model quantization")
        arr = (arr / scale + zero_point).astype(np.uint8)

    interpreter.set_tensor(detail["index"], arr)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]["index"])[0].astype(np.float32)

    norm = np.linalg.norm(output)
    if norm == 0:
        raise HTTPException(status_code=422, detail="Could not create face embedding")
    return (output / norm).astype(float).tolist()


async def _bytes_and_embedding_from_upload(file: UploadFile) -> tuple[bytes, list[float]]:
    raw = await file.read()
    return raw, _embedding_from_bytes(raw)


def _storage_download_url(path: str, raw: bytes) -> str:
    bucket = storage.bucket()
    blob = bucket.blob(path)
    token = str(uuid.uuid4())
    blob.metadata = {"firebaseStorageDownloadTokens": token}
    blob.upload_from_string(raw, content_type="image/jpeg")
    encoded = quote(path, safe="")
    return f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{encoded}?alt=media&token={token}"


def _distance(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        raise HTTPException(status_code=422, detail="Registered face embedding is invalid")
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _date_key() -> str:
    return datetime.now(timezone.utc).date().isoformat()


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "modelLoaded": interpreter is not None}


@app.post("/register-face")
async def register_face(
    image: UploadFile = File(...),
    face_image_url: str | None = Form(default=None),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    uid = _require_uid(authorization)
    raw, embedding = await _bytes_and_embedding_from_upload(image)
    now = _iso_now()
    if not face_image_url:
      face_image_url = _storage_download_url(f"users/{uid}/face_registration.jpg", raw)

    update = {
        "faceEmbedding": embedding,
        "faceRegistered": True,
        "faceRegisteredAt": now,
        "faceEmbeddingProvider": "cloud_run_mobilefacenet",
        "updatedAt": now,
    }
    if face_image_url:
        update["faceImageUrl"] = face_image_url

    _db().collection("users").document(uid).set(update, merge=True)
    return {"ok": True, "registered": True, "embeddingSize": len(embedding)}


@app.post("/verify-attendance")
async def verify_attendance(
    image: UploadFile = File(...),
    type: str = Form(...),
    date: str | None = Form(default=None),
    verification_photo_url: str | None = Form(default=None),
    latitude: str | None = Form(default=None),
    longitude: str | None = Form(default=None),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    uid = _require_uid(authorization)
    if type not in {"check_in", "check_out"}:
        raise HTTPException(status_code=400, detail="type must be check_in or check_out")

    users = _db().collection("users")
    user_ref = users.document(uid)
    user_doc = user_ref.get()
    if not user_doc.exists:
        raise HTTPException(status_code=404, detail="User profile not found")

    user = user_doc.to_dict() or {}
    registered = user.get("faceEmbedding")
    if not isinstance(registered, list) or not registered:
        raise HTTPException(status_code=409, detail="No registered face found")

    raw, embedding = await _bytes_and_embedding_from_upload(image)
    registered_embedding = [float(v) for v in registered]
    distance = _distance(embedding, registered_embedding)
    matched = distance <= RECOGNITION_THRESHOLD
    confidence = max(0.0, min(1.0, 1.0 - (distance / max(RECOGNITION_THRESHOLD, 1e-6))))

    if not matched:
        return {
            "ok": True,
            "matched": False,
            "distance": distance,
            "threshold": RECOGNITION_THRESHOLD,
        }

    now = _iso_now()
    date = date or _date_key()
    lat = float(latitude) if latitude not in (None, "") else None
    lng = float(longitude) if longitude not in (None, "") else None
    if not verification_photo_url:
        millis = int(datetime.now(timezone.utc).timestamp() * 1000)
        verification_photo_url = _storage_download_url(
            f"users/{uid}/attendance/{date}_{type}_{millis}.jpg",
            raw,
        )

    attendance = _db().collection("attendance")
    existing = list(
        attendance.where("userId", "==", uid).where("date", "==", date).limit(1).stream()
    )

    event = {
        "type": type,
        "time": now,
        "confidence": confidence,
        "distance": distance,
        "photoUrl": verification_photo_url,
    }
    if lat is not None and lng is not None:
        event["latitude"] = lat
        event["longitude"] = lng

    if existing:
        ref = existing[0].reference
        data = existing[0].to_dict() or {}
        events = list(data.get("events") or [])
        events.append(event)
        events.sort(key=lambda item: item.get("time", ""))
        update = {
            "events": events,
            "type": type,
            "time": now,
            "timestamp": now,
            "confidence": confidence,
            "photoUrl": verification_photo_url,
            "personId": uid,
            "personName": user.get("name") or "User",
            "employeeId": uid,
            "updatedAt": now,
        }
        if type == "check_in":
            update["checkInTime"] = now
            update["checkInConfidence"] = confidence
        else:
            update["checkoutTime"] = now
            update["checkoutConfidence"] = confidence
        if lat is not None and lng is not None:
            update["latitude"] = lat
            update["longitude"] = lng
        ref.update(update)
        attendance_id = ref.id
    else:
        record = {
            "personId": uid,
            "personName": user.get("name") or "User",
            "employeeId": uid,
            "userId": uid,
            "date": date,
            "timestamp": now,
            "time": now,
            "confidence": confidence,
            "type": type,
            "events": [event],
            "createdAt": now,
            "photoUrl": verification_photo_url,
        }
        if type == "check_in":
            record["checkInTime"] = now
            record["checkInConfidence"] = confidence
        else:
            record["checkoutTime"] = now
            record["checkoutConfidence"] = confidence
        if lat is not None and lng is not None:
            record["latitude"] = lat
            record["longitude"] = lng
        attendance_id = attendance.add(record)[1].id

    return {
        "ok": True,
        "matched": True,
        "attendanceId": attendance_id,
        "distance": distance,
        "threshold": RECOGNITION_THRESHOLD,
        "confidence": confidence,
        "event": event,
        "date": date,
    }
