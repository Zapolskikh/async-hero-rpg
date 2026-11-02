"""Account linking: e-mail + password, one-time transfer codes, Google (and later Apple).

A guest account works on one device (its token). Linking a way to log in lets the player
open the same account elsewhere: every login creates a new device session; the guest
token keeps working. Passwords are stored as scrypt hashes, codes and tokens as sha256.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import re
import secrets
import time
import urllib.parse
import urllib.request

from sqlalchemy import delete, select

from . import db
from .config import Settings

EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,24}$")
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O, 1/I
CODE_TTL = 10 * 60
LOGIN_WINDOW = 15 * 60
LOGIN_TRIES = 8


class AccountError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2 ** 14, r=8, p=1, dklen=32)
    return "scrypt$%s$%s" % (base64.b64encode(salt).decode(), base64.b64encode(digest).decode())


def check_password(password: str, stored: str) -> bool:
    try:
        _kind, salt, digest = stored.split("$")
        got = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=2 ** 14, r=8, p=1, dklen=32)
        return hmac.compare_digest(got, base64.b64decode(digest))
    except (ValueError, TypeError):
        return False


def mask_email(email: str) -> str:
    name, _, domain = email.partition("@")
    return (name[:1] + "***" if len(name) > 1 else "*") + "@" + domain


def normalize_email(email: str) -> str:
    email = (email or "").strip().lower()
    if not EMAIL_RE.match(email):
        raise AccountError(400, "bad email")
    return email


def check_new_password(password: str) -> None:
    if not isinstance(password, str) or len(password) < 8 or len(password) > 128:
        raise AccountError(400, "password must be 8-128 characters")


class Accounts:
    def __init__(self, settings: Settings):
        self.s = settings
        self._tries: dict[str, list[float]] = {}
        self.clock = time.time

    # ------------------------------------------------------------------ sessions

    async def new_session(self, s, account_id: str) -> str:
        token = secrets.token_urlsafe(32)
        s.add(db.DeviceSession(token_hash=hash_token(token), account_id=account_id))
        return token

    async def session_account(self, token: str) -> str | None:
        async with db.Session() as s, s.begin():
            row = await s.get(db.DeviceSession, hash_token(token))
            if row is None:
                return None
            row.last_seen = db.utcnow()
            return row.account_id

    async def logout(self, token: str) -> None:
        async with db.Session() as s, s.begin():
            await s.execute(delete(db.DeviceSession).where(db.DeviceSession.token_hash == hash_token(token)))

    # ------------------------------------------------------------------ status

    async def info(self, account_id: str) -> dict:
        async with db.Session() as s:
            creds = (await s.execute(select(db.Credential).where(db.Credential.account_id == account_id))).scalars().all()
        linked = {c.kind: (mask_email(c.subject) if c.kind == "email" else True) for c in creds}
        return {
            "account_id": account_id,
            "linked": {"email": linked.get("email"), "google": bool(linked.get("google")), "apple": bool(linked.get("apple"))},
            "guest": not creds,
            "providers": {"google": bool(self.s.google_client_id), "apple": bool(self.s.apple_client_id)},
            "google_client_id": self.s.google_client_id,
        }

    # ------------------------------------------------------------------ e-mail

    def _throttle(self, key: str) -> None:
        now = self.clock()
        tries = [t for t in self._tries.get(key, []) if now - t < LOGIN_WINDOW]
        if len(tries) >= LOGIN_TRIES:
            raise AccountError(429, "too many attempts, try later")
        tries.append(now)
        self._tries[key] = tries

    async def link_email(self, account_id: str, email: str, password: str) -> dict:
        email = normalize_email(email)
        check_new_password(password)
        async with db.Session() as s, s.begin():
            mine = (await s.execute(select(db.Credential).where(db.Credential.account_id == account_id,
                                                                db.Credential.kind == "email"))).scalar_one_or_none()
            if mine is not None:
                raise AccountError(409, "email already linked")
            taken = (await s.execute(select(db.Credential).where(db.Credential.kind == "email",
                                                                 db.Credential.subject == email))).scalar_one_or_none()
            if taken is not None:
                raise AccountError(409, "email belongs to another account")
            s.add(db.Credential(account_id=account_id, kind="email", subject=email, secret=hash_password(password)))
        return await self.info(account_id)

    async def login_email(self, email: str, password: str) -> tuple[str, str]:
        email = normalize_email(email)
        self._throttle("email:" + email)
        async with db.Session() as s, s.begin():
            cred = (await s.execute(select(db.Credential).where(db.Credential.kind == "email",
                                                                db.Credential.subject == email))).scalar_one_or_none()
            if cred is None or not check_password(password or "", cred.secret):
                raise AccountError(401, "wrong email or password")
            return cred.account_id, await self.new_session(s, cred.account_id)

    async def change_password(self, account_id: str, old: str, new: str, keep_token: str) -> dict:
        check_new_password(new)
        async with db.Session() as s, s.begin():
            cred = (await s.execute(select(db.Credential).where(db.Credential.account_id == account_id,
                                                                db.Credential.kind == "email"))).scalar_one_or_none()
            if cred is None:
                raise AccountError(404, "no email linked")
            self._throttle("change:" + account_id)
            if not check_password(old or "", cred.secret):
                raise AccountError(401, "wrong password")
            cred.secret = hash_password(new)
            # other devices are logged out: a changed password is often a stolen one
            await s.execute(delete(db.DeviceSession).where(db.DeviceSession.account_id == account_id,
                                                           db.DeviceSession.token_hash != hash_token(keep_token)))
            acc = await s.get(db.Account, account_id)
            if acc is not None and acc.token_hash != hash_token(keep_token):
                acc.token_hash = hash_token(secrets.token_urlsafe(32))   # the guest token stops working too
        return await self.info(account_id)

    # ------------------------------------------------------------------ transfer codes

    async def new_transfer_code(self, account_id: str) -> dict:
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))
        now = self.clock()
        async with db.Session() as s, s.begin():
            await s.execute(delete(db.TransferCode).where(db.TransferCode.account_id == account_id))
            s.add(db.TransferCode(code_hash=hash_token(code), account_id=account_id, expires_at=now + CODE_TTL))
        return {"code": code[:4] + "-" + code[4:], "expires_at": now + CODE_TTL, "ttl": CODE_TTL}

    async def use_transfer_code(self, code: str, client_key: str) -> tuple[str, str]:
        self._throttle("code:" + client_key)
        code = re.sub(r"[^A-Za-z0-9]", "", code or "").upper()
        async with db.Session() as s, s.begin():
            row = await s.get(db.TransferCode, hash_token(code))
            if row is None or row.used or row.expires_at < self.clock():
                raise AccountError(404, "code is wrong or expired")
            row.used = True
            return row.account_id, await self.new_session(s, row.account_id)

    # ------------------------------------------------------------------ Google / Apple

    async def _google_subject(self, id_token: str) -> str:
        if not self.s.google_client_id:
            raise AccountError(501, "google sign-in is not configured")
        url = "https://oauth2.googleapis.com/tokeninfo?" + urllib.parse.urlencode({"id_token": id_token})

        def fetch() -> dict:
            with urllib.request.urlopen(url, timeout=10) as r:
                return json.loads(r.read().decode())
        try:
            info = await asyncio.to_thread(fetch)
        except Exception as e:   # bad token -> HTTP 400 from Google
            raise AccountError(401, "google token rejected") from e
        if info.get("aud") != self.s.google_client_id or info.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
            raise AccountError(401, "google token is for another app")
        if float(info.get("exp", 0)) < self.clock():
            raise AccountError(401, "google token expired")
        return str(info["sub"])

    async def provider_subject(self, kind: str, id_token: str) -> str:
        if kind == "google":
            return await self._google_subject(id_token)
        if kind == "apple":
            raise AccountError(501, "apple sign-in is not configured")
        raise AccountError(400, "unknown provider")

    async def link_provider(self, account_id: str, kind: str, id_token: str) -> dict:
        subject = await self.provider_subject(kind, id_token)
        async with db.Session() as s, s.begin():
            taken = (await s.execute(select(db.Credential).where(db.Credential.kind == kind,
                                                                 db.Credential.subject == subject))).scalar_one_or_none()
            if taken is not None:
                raise AccountError(409, "this %s account is linked to another player" % kind)
            mine = (await s.execute(select(db.Credential).where(db.Credential.account_id == account_id,
                                                                db.Credential.kind == kind))).scalar_one_or_none()
            if mine is not None:
                raise AccountError(409, "%s already linked" % kind)
            s.add(db.Credential(account_id=account_id, kind=kind, subject=subject))
        return await self.info(account_id)

    async def login_provider(self, kind: str, id_token: str) -> tuple[str, str]:
        subject = await self.provider_subject(kind, id_token)
        async with db.Session() as s, s.begin():
            cred = (await s.execute(select(db.Credential).where(db.Credential.kind == kind,
                                                                db.Credential.subject == subject))).scalar_one_or_none()
            if cred is None:
                raise AccountError(404, "no player with this %s account" % kind)
            return cred.account_id, await self.new_session(s, cred.account_id)
