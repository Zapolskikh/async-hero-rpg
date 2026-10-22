# Game server image: FastAPI + a pool of Godot headless processes that run the
# shared game rules (scripts/ + worker/ from the Godot project).
# Build from the repository root:  docker build -f server/Dockerfile -t async-hero-server .
FROM python:3.12-slim

ARG GODOT_VERSION=4.5.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip ca-certificates libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /srv/game
COPY server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir -r server/requirements.txt

# Only what the rules need: no art, no UI scenes.
COPY project.godot ./
COPY scripts ./scripts
COPY worker ./worker
RUN godot --headless --import --path /srv/game >/dev/null 2>&1 || true \
 && test -f .godot/global_script_class_cache.cfg

COPY server/app server/app
ENV GODOT_BIN=godot PROJECT_DIR=/srv/game PYTHONUNBUFFERED=1
WORKDIR /srv/game/server
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
