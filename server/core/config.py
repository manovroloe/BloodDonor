"""Environment configuration; private values are never served to the browser."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

from dotenv import dotenv_values

ROOT_DIR = Path(__file__).resolve().parents[2]
CLIENT_DIR = ROOT_DIR / "client"

class ConfigurationError(ValueError):
    """An actionable configuration error, without secret values."""

def _bool(value: str, name: str) -> bool:
    text = str(value).strip().lower()
    if text not in {"true", "false", "1", "0", "yes", "no", "on", "off"}:
        raise ConfigurationError(f"{name} must be true or false.")
    return text in {"true", "1", "yes", "on"}

def _integer(value: str, name: str, minimum: int, maximum: int) -> int:
    try:
        result = int(value)
    except (TypeError, ValueError) as exc:
        raise ConfigurationError(f"{name} must be a whole number.") from exc
    if not minimum <= result <= maximum:
        raise ConfigurationError(f"{name} must be between {minimum} and {maximum}.")
    return result

def _is_real(value: str) -> bool:
    return bool(value) and not any(x in value.upper() for x in ("YOUR_PROJECT", "YOUR_SUPABASE", "YOUR_GMAIL", "CHANGE_ME"))

@dataclass(frozen=True, slots=True)
class Settings:
    supabase_url: str = ""
    supabase_anon_key: str = field(default="", repr=False)
    supabase_service_role_key: str = field(default="", repr=False)
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = field(default="", repr=False)
    smtp_password: str = field(default="", repr=False)
    smtp_from_email: str = field(default="", repr=False)
    smtp_from_name: str = "BloodCare"
    smtp_use_tls: bool = True
    cookie_secure: bool = False
    host: str = "127.0.0.1"
    port: int = 8000
    environment: str = "development"
    public_origin: str = ""
    allowed_hosts: tuple[str, ...] = ()
    forwarded_allow_ips: str = "127.0.0.1"
    workers: int = 1
    log_level: str = "info"
    max_upload_mb: int = 10
    client_dir: Path = CLIENT_DIR

    @property
    def configured(self) -> bool:
        return _is_real(self.supabase_url) and _is_real(self.supabase_anon_key)

    @property
    def auth_admin_configured(self) -> bool:
        return self.configured and _is_real(self.supabase_service_role_key)

    @property
    def smtp_configured(self) -> bool:
        return _is_real(self.smtp_host) and _is_real(self.smtp_from_email)

    @property
    def production(self) -> bool:
        return self.environment == "production"

    @property
    def trusted_hosts(self) -> list[str]:
        if self.allowed_hosts:
            return list(self.allowed_hosts)
        if self.public_origin:
            return list(dict.fromkeys([urlsplit(self.public_origin).hostname or "", "localhost", "127.0.0.1", "[::1]"]))
        return ["*"]

    def validate(self) -> None:
        if self.environment not in {"development", "test", "production"}:
            raise ConfigurationError("APP_ENV must be development, test, or production.")
        if self.log_level not in {"debug", "info", "warning", "error", "critical"}:
            raise ConfigurationError("LOG_LEVEL must be debug, info, warning, error, or critical.")
        if self.supabase_url and _is_real(self.supabase_url):
            parts = urlsplit(self.supabase_url)
            if parts.scheme not in {"http", "https"} or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment or parts.path not in {"", "/"}:
                raise ConfigurationError("SUPABASE_URL must be an HTTP(S) project origin without credentials or a path.")
        if self.public_origin:
            parts = urlsplit(self.public_origin)
            if parts.scheme not in {"http", "https"} or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment or parts.path not in {"", "/"}:
                raise ConfigurationError("PUBLIC_ORIGIN must contain only the website scheme, hostname, and optional port.")
        if self.production:
            if not self.configured:
                raise ConfigurationError("Production requires SUPABASE_URL and SUPABASE_ANON_KEY.")
            if not self.supabase_url.startswith("https://"):
                raise ConfigurationError("Production requires an HTTPS SUPABASE_URL.")
            if not self.public_origin.startswith("https://"):
                raise ConfigurationError("Production requires PUBLIC_ORIGIN=https://your-real-domain.")
            if not self.cookie_secure:
                raise ConfigurationError("Production requires COOKIE_SECURE=true.")
            if "*" in self.allowed_hosts:
                raise ConfigurationError("Production ALLOWED_HOSTS must not contain a wildcard-only entry.")

    @classmethod
    def from_env(cls, env_file: str | Path | None = None) -> "Settings":
        # The path is relative to the project, never the terminal's working folder.
        requested = env_file if env_file is not None else os.getenv("BLOODCARE_ENV_FILE")
        path = Path(requested) if requested else ROOT_DIR / ".env"
        if not path.is_absolute():
            path = ROOT_DIR / path
        values = {k: str(v or "") for k, v in dotenv_values(path).items()} if path.is_file() else {}
        values.update(os.environ)  # The host's secret manager wins over local .env.
        def get(name: str, default: str = "") -> str:
            secret_file = values.get(name + "_FILE", "").strip()
            if secret_file:
                try:
                    return Path(secret_file).read_text(encoding="utf-8").strip()
                except OSError as exc:
                    raise ConfigurationError(f"Unable to read the configured {name}_FILE.") from exc
            return values.get(name, default).strip()
        environment = get("APP_ENV", "development").lower()
        username = get("SMTP_USERNAME")
        result = cls(
            supabase_url=get("SUPABASE_URL").rstrip("/"),
            supabase_anon_key=get("SUPABASE_ANON_KEY") or get("SUPABASE_PUBLISHABLE_KEY"),
            supabase_service_role_key=get("SUPABASE_SERVICE_ROLE_KEY") or get("SUPABASE_SECRET_KEY"),
            smtp_host=get("SMTP_HOST"), smtp_port=_integer(get("SMTP_PORT", "587") or "587", "SMTP_PORT", 1, 65535),
            smtp_username=username, smtp_password=get("SMTP_PASSWORD"),
            smtp_from_email=get("SMTP_FROM_EMAIL") or username,
            smtp_from_name=get("SMTP_FROM_NAME", "BloodCare") or "BloodCare",
            smtp_use_tls=_bool(get("SMTP_USE_TLS", "true"), "SMTP_USE_TLS"),
            cookie_secure=_bool(get("COOKIE_SECURE", "true" if environment == "production" else "false"), "COOKIE_SECURE"),
            host=get("HOST", "127.0.0.1") or "127.0.0.1", port=_integer(get("PORT", "8000"), "PORT", 1, 65535),
            environment=environment, public_origin=get("PUBLIC_ORIGIN").rstrip("/"),
            allowed_hosts=tuple(x.strip() for x in get("ALLOWED_HOSTS").split(",") if x.strip()),
            forwarded_allow_ips=get("FORWARDED_ALLOW_IPS", "127.0.0.1"),
            workers=_integer(get("WORKERS", "1"), "WORKERS", 1, 32),
            log_level=get("LOG_LEVEL", "info").lower(),
            max_upload_mb=_integer(get("MAX_UPLOAD_MB", "10"), "MAX_UPLOAD_MB", 1, 100),
        )
        result.validate()
        return result
