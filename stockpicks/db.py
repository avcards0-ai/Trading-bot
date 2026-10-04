"""Users, login sessions and subscriptions in SQLite."""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Iterator

SESSION_DAYS = 30
RESET_MINUTES = 60
# Stripe statuses that keep access. past_due keeps it while Stripe retries the
# card; Stripe cancels the subscription (and we revoke) if every retry fails.
ACCESS_STATUSES = ("active", "trialing", "past_due")

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    stripe_customer_id TEXT UNIQUE,
    stripe_subscription_id TEXT,
    subscription_status TEXT NOT NULL DEFAULT 'none',
    current_period_end INTEGER,
    cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
    comped INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS reset_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS stripe_events (
    id TEXT PRIMARY KEY,
    received_at INTEGER NOT NULL
);
"""


@dataclass
class User:
    id: int
    email: str
    created_at: int
    stripe_customer_id: str | None
    stripe_subscription_id: str | None
    subscription_status: str
    current_period_end: int | None
    cancel_at_period_end: bool
    comped: bool

    @property
    def has_access(self) -> bool:
        return self.comped or self.subscription_status in ACCESS_STATUSES


# --- Passwords and tokens ---------------------------------------------------

_SCRYPT = {"n": 2**14, "r": 8, "p": 1}


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, dklen=32, **_SCRYPT)
    b64 = base64.b64encode
    return f"scrypt${_SCRYPT['n']}${_SCRYPT['r']}${_SCRYPT['p']}${b64(salt).decode()}${b64(digest).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, n, r, p, salt, digest = stored.split("$")
        if scheme != "scrypt":
            return False
        expected = base64.b64decode(digest)
        actual = hashlib.scrypt(
            password.encode("utf-8"), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p), dklen=len(expected)
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(actual, expected)


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# Spend the same time on unknown emails as on wrong passwords, so login
# timing doesn't reveal who has an account.
_DUMMY_HASH = hash_password(secrets.token_hex(8))


class Database:
    def __init__(self, path: str):
        self.path = path
        if os.path.dirname(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
        with self.connect() as conn:
            conn.executescript(SCHEMA)

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self.path, timeout=10)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        try:
            yield conn
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
        finally:
            conn.close()

    @staticmethod
    def _user(row: sqlite3.Row | None) -> User | None:
        if row is None:
            return None
        return User(
            id=row["id"],
            email=row["email"],
            created_at=row["created_at"],
            stripe_customer_id=row["stripe_customer_id"],
            stripe_subscription_id=row["stripe_subscription_id"],
            subscription_status=row["subscription_status"],
            current_period_end=row["current_period_end"],
            cancel_at_period_end=bool(row["cancel_at_period_end"]),
            comped=bool(row["comped"]),
        )

    # Users

    def create_user(self, email: str, password: str) -> User | None:
        """Create a user, or return None if the email is taken."""
        try:
            with self.connect() as conn:
                cur = conn.execute(
                    "INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)",
                    (email.strip(), hash_password(password), int(time.time())),
                )
                user_id = cur.lastrowid
        except sqlite3.IntegrityError:
            return None
        return self.get_user(user_id)

    def get_user(self, user_id: int) -> User | None:
        with self.connect() as conn:
            return self._user(conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone())

    def get_user_by_email(self, email: str) -> User | None:
        with self.connect() as conn:
            return self._user(conn.execute("SELECT * FROM users WHERE email = ?", (email.strip(),)).fetchone())

    def get_user_by_customer(self, customer_id: str) -> User | None:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM users WHERE stripe_customer_id = ?", (customer_id,)).fetchone()
            return self._user(row)

    def authenticate(self, email: str, password: str) -> User | None:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM users WHERE email = ?", (email.strip(),)).fetchone()
        if row is None:
            verify_password(password, _DUMMY_HASH)
            return None
        return self._user(row) if verify_password(password, row["password_hash"]) else None

    def set_password(self, user_id: int, password: str) -> None:
        with self.connect() as conn:
            conn.execute("UPDATE users SET password_hash = ? WHERE id = ?", (hash_password(password), user_id))
            # Changing the password signs out every device.
            conn.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))

    def update_subscription(
        self,
        user_id: int,
        *,
        customer_id: str | None,
        subscription_id: str | None,
        status: str,
        current_period_end: int | None,
        cancel_at_period_end: bool,
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """UPDATE users SET stripe_customer_id = COALESCE(?, stripe_customer_id),
                       stripe_subscription_id = COALESCE(?, stripe_subscription_id),
                       subscription_status = ?, current_period_end = ?, cancel_at_period_end = ?
                   WHERE id = ?""",
                (customer_id, subscription_id, status, current_period_end, int(cancel_at_period_end), user_id),
            )

    def set_customer(self, user_id: int, customer_id: str) -> None:
        with self.connect() as conn:
            conn.execute("UPDATE users SET stripe_customer_id = ? WHERE id = ?", (customer_id, user_id))

    def set_comped(self, email: str, comped: bool) -> bool:
        with self.connect() as conn:
            cur = conn.execute("UPDATE users SET comped = ? WHERE email = ?", (int(comped), email.strip()))
            return cur.rowcount > 0

    def list_users(self) -> list[User]:
        with self.connect() as conn:
            return [self._user(r) for r in conn.execute("SELECT * FROM users ORDER BY id")]

    # Sessions

    def create_session(self, user_id: int) -> str:
        token = secrets.token_urlsafe(32)
        now = int(time.time())
        with self.connect() as conn:
            conn.execute("DELETE FROM sessions WHERE expires_at < ?", (now,))
            conn.execute(
                "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)",
                (_token_hash(token), user_id, now + SESSION_DAYS * 86400),
            )
        return token

    def user_for_session(self, token: str) -> User | None:
        if not token:
            return None
        with self.connect() as conn:
            row = conn.execute(
                """SELECT users.* FROM sessions JOIN users ON users.id = sessions.user_id
                   WHERE sessions.token_hash = ? AND sessions.expires_at > ?""",
                (_token_hash(token), int(time.time())),
            ).fetchone()
        return self._user(row)

    def delete_session(self, token: str) -> None:
        with self.connect() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash = ?", (_token_hash(token),))

    # Password resets

    def create_reset_token(self, user_id: int) -> str:
        token = secrets.token_urlsafe(32)
        now = int(time.time())
        with self.connect() as conn:
            conn.execute("DELETE FROM reset_tokens WHERE expires_at < ? OR user_id = ?", (now, user_id))
            conn.execute(
                "INSERT INTO reset_tokens (token_hash, user_id, expires_at) VALUES (?, ?, ?)",
                (_token_hash(token), user_id, now + RESET_MINUTES * 60),
            )
        return token

    def reset_token_user(self, token: str) -> User | None:
        with self.connect() as conn:
            row = conn.execute(
                """SELECT users.* FROM reset_tokens JOIN users ON users.id = reset_tokens.user_id
                   WHERE reset_tokens.token_hash = ? AND reset_tokens.expires_at > ?""",
                (_token_hash(token), int(time.time())),
            ).fetchone()
        return self._user(row)

    def use_reset_token(self, token: str, password: str) -> bool:
        user = self.reset_token_user(token)
        if user is None:
            return False
        with self.connect() as conn:
            conn.execute("DELETE FROM reset_tokens WHERE user_id = ?", (user.id,))
        self.set_password(user.id, password)
        return True

    # Stripe webhook de-duplication

    def event_seen(self, event_id: str) -> bool:
        with self.connect() as conn:
            return conn.execute("SELECT 1 FROM stripe_events WHERE id = ?", (event_id,)).fetchone() is not None

    def mark_event(self, event_id: str) -> None:
        with self.connect() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO stripe_events (id, received_at) VALUES (?, ?)", (event_id, int(time.time()))
            )
