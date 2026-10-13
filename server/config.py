"""Compatibility import. New backend code uses injected core.config.Settings."""
from .core.config import CLIENT_DIR, ROOT_DIR, Settings
settings = Settings.from_env()
