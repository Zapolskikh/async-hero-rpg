# Web client of the release stack: Godot "Web Online" export (online only, no local saves)
# served by nginx, which also forwards <BASE_PATH>/api/ to the game server.
# Build from the repository root:
#   docker build -f deploy/web/Dockerfile --build-arg GAME_BUILD=$(git rev-parse HEAD) -t async-hero-web .
# GAME_BUILD must match the api image: a client of another build is asked to reload.

FROM debian:bookworm-slim AS export
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG GODOT_VERSION=4.5.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip ca-certificates python3 libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
RUN base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable" \
 && curl -fsSL --retry 3 -o /tmp/godot.zip "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && curl -fsSL --retry 3 -o /tmp/templates.tpz "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
 && mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
 && unzip -q /tmp/templates.tpz 'templates/web_*' -d /tmp/templates \
 && mv /tmp/templates/templates/web_* /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/ \
 && rm -rf /tmp/godot /tmp/godot.zip /tmp/templates /tmp/templates.tpz

WORKDIR /game
COPY . .
ARG GAME_BUILD=0000000
RUN [[ "$GAME_BUILD" =~ ^[0-9a-f]{7,40}$ ]] || { echo "GAME_BUILD must be a commit SHA"; exit 1; } \
 && printf '{"build": "%s"}\n' "$GAME_BUILD" > build.json \
 && (godot --headless --editor --path . --quit >/dev/null 2>&1 || true) \
 && mkdir -p build/web-online \
 && entry="game-${GAME_BUILD:0:12}.html" \
 && godot --headless --path . --export-release "Web Online" "build/web-online/$entry" \
 && python3 tools/prepare_web_build.py build/web-online --entry "$entry" --commit "$GAME_BUILD"

FROM nginx:1.27-alpine
ENV BASE_PATH=/async-hero \
    API_UPSTREAM=api:8000
COPY deploy/web/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=export /game/build/web-online /usr/share/nginx/html
HEALTHCHECK --interval=30s --timeout=5s CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
