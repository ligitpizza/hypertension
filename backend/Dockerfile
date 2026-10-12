# CareFlow API image for Cloud Run (docs/10 §4). Built by Cloud Build via
# `gcloud run deploy --source backend`, so Docker is not needed locally.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8080

WORKDIR /srv

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app
# ML artefacts (Increment 2) are copied into backend/ml_artifacts by tasks.py before deploy.
COPY ml_artifacts ./ml_artifacts

RUN useradd --create-home --uid 10001 appuser
USER appuser

CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips=*"]
