"""Prove that the cleanup preserves v22 markup, styles, database, and routes."""
from pathlib import Path
import ast
import hashlib
import json
import os
import re
import tempfile
import unittest
from dataclasses import replace
from unittest.mock import patch
from server.core.config import ConfigurationError, Settings
from server.main import create_app
from server.repositories.supabase import SupabaseRepository
from server.repositories.query import build_params
from server.schemas.database import DbRequest
from fastapi import HTTPException
import httpx

ROOT = Path(__file__).resolve().parents[1]
BASELINE = json.loads((ROOT / "tests/v22_baseline.json").read_text())

class IntegrityTests(unittest.TestCase):
    def test_database_styles_and_images_unchanged(self):
        for name, digest in BASELINE["unchanged"].items():
            with self.subTest(name=name):
                self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), digest)

    def test_html_unchanged_except_module_entrypoint_and_theme_filename(self):
        for name, digest in BASELINE["html_normalized"].items():
            with self.subTest(name=name):
                self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), digest)

    def test_every_original_endpoint_is_retained(self):
        app = create_app(Settings(environment="test"))
        routes = {(method, r.path) for r in app.routes if hasattr(r, "methods") for method in r.methods}
        for item in BASELINE["routes"]:
            self.assertIn((item["method"], item["path"]), routes)

    def test_existing_pdf_renderer_unchanged(self):
        tree = ast.parse((ROOT / "server/services/profile_pdf.py").read_text())
        actual = {n.name: hashlib.sha256(ast.dump(n, include_attributes=False).encode()).hexdigest() for n in tree.body if isinstance(n, ast.FunctionDef)}
        self.assertEqual(actual, BASELINE["pdf_functions"])

    def test_browser_module_imports_exist(self):
        for file in (ROOT / "client/js").rglob("*.js"):
            for name in re.findall(r"from\s+['\"]([^'\"]+)['\"]", file.read_text()):
                self.assertTrue(name.startswith("."), f"Unexpected external module in {file.name}")
                self.assertTrue((file.parent / name).is_file(), f"Missing {name} in {file}")

    def test_static_html_links_resolve(self):
        client = ROOT / "client"
        for page in client.glob("*.html"):
            for link in re.findall(r'(?:href|src)=["\']([^"\']+)', page.read_text()):
                if link.startswith(("http:", "https:", "mailto:", "tel:", "#", "/api/", "/logout", "data:")):
                    continue
                name = link.split("?", 1)[0].split("#", 1)[0]
                if name:
                    target = client / name.lstrip("/") if name.startswith("/") else page.parent / name
                    self.assertTrue(target.exists(), f"{page.name} references missing {link}")

    def test_runtime_entrypoints_do_not_install_packages(self):
        for name in ["run.py", "scripts/start.py", "start.bat", "start.sh"]:
            source = (ROOT / name).read_text().lower()
            self.assertNotIn('"pip"', source)
            self.assertNotIn("pip install", source)

    def test_requirements_are_exact_pins(self):
        for line in (ROOT / "requirements.txt").read_text().splitlines():
            if line and not line.startswith("#"):
                self.assertRegex(line, r"^[A-Za-z0-9_.-]+==[^\s]+")

class ConfigTests(unittest.TestCase):
    def test_production_requires_configuration(self):
        with self.assertRaises(ConfigurationError):
            Settings(environment="production").validate()

    def test_production_requires_https_and_secure_cookies(self):
        c = Settings(supabase_url="https://test.example.invalid", supabase_anon_key="public", environment="production", public_origin="https://bloodcare.example.invalid")
        with self.assertRaises(ConfigurationError): c.validate()
        replace(c, cookie_secure=True).validate()
        with self.assertRaises(ConfigurationError): replace(c, cookie_secure=True, public_origin="http://bloodcare.example.invalid").validate()

    def test_invalid_url_does_not_echo_private_value(self):
        with self.assertRaises(ConfigurationError) as caught:
            Settings(supabase_url="https://private:secret@example.invalid/path").validate()
        self.assertNotIn("secret", str(caught.exception))

    def test_placeholder_is_not_configured(self):
        self.assertFalse(Settings(supabase_url="https://YOUR_PROJECT_ID.supabase.co", supabase_anon_key="YOUR_SUPABASE_ANON_KEY").configured)

    def test_environment_overrides_env_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / ".env"
            file.write_text("PORT=8010\nSUPABASE_URL=https://file.example.invalid\nSUPABASE_ANON_KEY=test-key\n")
            with patch.dict(os.environ, {"PORT": "8020", "APP_ENV": "test"}, clear=True):
                settings = Settings.from_env(file)
            self.assertEqual(settings.port, 8020)
            self.assertTrue(settings.configured)

    def test_secret_file_support(self):
        with tempfile.TemporaryDirectory() as tmp:
            secret = Path(tmp) / "key"
            secret.write_text("file-secret")
            with patch.dict(os.environ, {"SUPABASE_SERVICE_ROLE_KEY_FILE": str(secret)}, clear=True):
                settings = Settings.from_env(Path(tmp) / ".env")
            self.assertEqual(settings.supabase_service_role_key, "file-secret")
            self.assertNotIn("file-secret", repr(settings))

    def test_invalid_numeric_setting(self):
        with patch.dict(os.environ, {"PORT": "invalid"}, clear=True):
            with self.assertRaises(ConfigurationError): Settings.from_env("nonexistent.env")

    def test_new_style_api_key_is_not_used_as_bearer_jwt(self):
        repo = SupabaseRepository(None, Settings(supabase_url="https://test.example.invalid", supabase_anon_key="sb_publishable_test", supabase_service_role_key="sb_secret_test"))
        self.assertNotIn("Authorization", repo.headers())
        self.assertNotIn("Authorization", repo.headers(admin=True))
        self.assertEqual(repo.headers("user-jwt")["Authorization"], "Bearer user-jwt")

    def test_storage_path_rejects_traversal(self):
        for path in ["../other-bucket/file.png", "a/../b", "a\\b", "/root", ""]:
            with self.assertRaises(HTTPException): SupabaseRepository.object_path(path)
        self.assertEqual(SupabaseRepository.object_path("folder/one two.png"), "folder/one%20two.png")

    def test_in_filter_escapes_values(self):
        body = DbRequest(table="facilities", filters=[{"column": "name", "op": "in", "value": ["A,B", "Plain"]}])
        self.assertEqual(dict(build_params(body))["name"], 'in.("A,B",Plain)')

if __name__ == "__main__":
    unittest.main()
