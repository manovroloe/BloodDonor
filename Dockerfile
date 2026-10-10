# Build once, then reuse this image. Python packages are NEVER installed at startup.
# For a production release, override PYTHON_IMAGE with an approved image digest.
ARG PYTHON_IMAGE=python:3.13-slim
FROM ${PYTHON_IMAGE}
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HOST=0.0.0.0 \
    PORT=8000 \
    APP_ENV=production
WORKDIR /app
COPY requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir --no-deps -r requirements.txt \
    && python -m pip check \
    && groupadd --gid 10001 bloodcare \
    && useradd --uid 10001 --gid 10001 --no-create-home bloodcare
COPY --chown=10001:10001 server ./server
COPY --chown=10001:10001 client ./client
COPY --chown=10001:10001 run.py ./run.py
USER 10001:10001
EXPOSE 8000
LABEL org.opencontainers.image.title="BloodCare Website" \
      org.opencontainers.image.version="23.0.0"
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=3)" || exit 1
CMD ["python", "run.py"]
