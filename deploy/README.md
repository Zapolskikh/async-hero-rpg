# Развёртывание: Docker Compose + Portainer + Cloudflare

Игра доступна по адресу `https://games.imbapewpew.com/async-hero/`. Всё работает на домашнем сервере в одном стеке Portainer, наружу его выводит Cloudflare Tunnel.

```
браузер ──HTTPS──► Cloudflare ──Tunnel──► домашний сервер :8088
                                              └─ web (nginx)
                                                   ├─ /async-hero/       игра (Godot Web, только онлайн)
                                                   └─ /async-hero/api/   ──► api (FastAPI + воркеры Godot)
                                                                               └─► db (PostgreSQL)
                                              └─ backup: ежедневная копия базы
```

Веб-версия — релизная сборка: играть можно только через сервер. Локальных сохранений, офлайн-режима и промотки времени в ней нет. Золото, лут, бои и таймеры считает сервер, клиент только показывает результат.

## Как обновляется игра

1. Пуш в `main` → GitHub Actions прогоняет тесты (`tests`).
2. Если тесты зелёные, workflow `Docker images` собирает два образа одного коммита и публикует их в GitHub Container Registry:
   - `ghcr.io/zapolskikh/async-hero-api:latest` — сервер с правилами;
   - `ghcr.io/zapolskikh/async-hero-web:latest` — веб-клиент с nginx.

   Каждый образ также помечается SHA коммита.
3. Portainer подтягивает новые образы: кнопкой «Pull and redeploy» или автоматически по вебхуку (см. ниже).

Клиент и сервер знают номер своей сборки. Если игрок держит открытой старую вкладку, сервер ответит «нужно обновление», и игра предложит перезагрузить страницу.

## Первый запуск

### 1. Стек в Portainer

**Stacks → Add stack**:

- **Name:** `async-hero`
- **Build method:** Repository
  - Repository URL: `https://github.com/Zapolskikh/async-hero-rpg`
  - Reference: `refs/heads/main`
  - Compose path: `deploy/docker-compose.yml`

  Либо вставить содержимое `deploy/docker-compose.yml` в Web editor.
- **Environment variables** (образец — `deploy/.env.example`):
  - `POSTGRES_PASSWORD` — длинный случайный пароль, **обязательно**;
  - `HTTP_PORT` — порт на сервере, по умолчанию `8088`;
  - `BASE_PATH` — `/async-hero`;
  - `ADMIN_TOKEN` — случайная строка для служебных отчётов и закрытия сезона;
  - остальное можно оставить по умолчанию.
- **Deploy the stack.**

Проверка на самом сервере:
- `curl http://localhost:8088/healthz` → `ok`
- `curl http://localhost:8088/async-hero/api/health` → `{"ok":true,...,"build":"<sha>"}`

### 2. Cloudflare Tunnel

**Zero Trust → Networks → Tunnels →** ваш туннель **→ Public Hostname → Add**:

- **Subdomain:** `games`, **Domain:** `imbapewpew.com`
- **Path:** `async-hero*`. Если на `games.imbapewpew.com` других сайтов нет, путь можно не указывать.
- **Service:** `HTTP` → `localhost:8088`. Если cloudflared работает в Docker, укажите IP сервера в локальной сети или имя контейнера `web` в общей сети.

Cloudflare не обрезает путь: запрос `/async-hero/...` приходит в nginx целиком, так и задумано.

Рекомендуется в настройках Cloudflare для этого адреса:
- **SSL/TLS:** Full;
- **Caching → Cache Rules:** не кешировать `/async-hero/api/*` (ответы сервера личные). Статические файлы игры можно кешировать: у них версия в имени.

### 3. Автообновление (необязательно)

Portainer: **Stack → Webhooks → Create** → скопировать URL. GitHub: **Settings → Secrets and variables → Actions → New secret** `PORTAINER_WEBHOOK` = этот URL. После каждой успешной сборки GitHub Actions сам дернёт вебхук, и Portainer перезапустит стек на новых образах.

Если у Portainer нет доступа к интернету снаружи, достаточно нажимать **Pull and redeploy** вручную.

### 4. Образы в GHCR

Репозиторий публичный, и образы публикуются с привязкой к нему. Если Portainer всё же получает `unauthorized`, откройте на GitHub **Packages → async-hero-api / async-hero-web → Package settings → Change visibility → Public**.

## Резервные копии

Сервис `backup` каждый день делает `pg_dump` в том `backups`. Хранятся 7 дневных, 4 недельные и 6 месячных копий.

Восстановление:

```bash
docker compose -p async-hero exec -T db psql -U hero -d hero < backup.sql
```

Предварительно распакуйте копию из тома `async-hero_backups`.

## Сборка образов на самом сервере

Если не хочется зависеть от GitHub Actions, в `deploy/docker-compose.yml` у сервисов `api` и `web` замените `image:` на закомментированный рядом блок `build:`. Portainer соберёт образы из репозитория сам. Сборка веб-клиента скачивает Godot и шаблоны экспорта (около 1 ГБ) и занимает несколько минут.

## Локальная проверка без Docker

```bash
cd server && GODOT_BIN=godot ./run_local.sh                          # API на :8000
godot --path . -- --online-only=http://127.0.0.1:8000               # релизный клиент
```
