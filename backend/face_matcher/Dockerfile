FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV MODEL_PATH=/app/models/mobilefacenet.tflite

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY backend/face_matcher/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY backend/face_matcher/app /app/app
COPY assets/models/mobilefacenet.tflite /app/models/mobilefacenet.tflite

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
