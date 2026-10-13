"""HTTP contract and service tests using a fully mocked Supabase transport."""
from __future__ import annotations
import json
import unittest
from dataclasses import replace
from unittest.mock import patch
import httpx
from fastapi.testclient import TestClient
from server.core.config import Settings
from server.main import create_app

USER_ID = "33333333-3333-4333-8333-333333333333"
STAFF_ID = "44444444-4444-4444-8444-444444444444"
FACILITY_ID = "11111111-1111-4111-8111-111111111111"
CONTACT_ID = "55555555-5555-4555-8555-555555555555"
CONFIG = Settings(supabase_url="https://supabase.example.invalid", supabase_anon_key="test-public-key", supabase_service_role_key="test-service-key", environment="test")

class Upstream:
    def __init__(self):
        self.calls = []
        self.role = "admin"
        self.active = True
        self.refresh_status = 200
        self.db_status = 200
        self.assignment_status = 200
        self.rpc_status = 200
        self.offline = False
        self.logout_offline = False
        self.profile_unauthorized_once = False
        self.rows = [{"id": FACILITY_ID, "name": "Test Facility", "active": True}]

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.calls.append(request)
        path = request.url.path
        if self.offline or self.logout_offline and path.endswith("/logout"):
            raise httpx.ConnectError("simulated-private-upstream-detail", request=request)
        body = json.loads(request.content) if request.content and "application/json" in request.headers.get("content-type", "") else {}
        def res(data, status=200, headers=None):
            return httpx.Response(status, json=data, headers=headers)
        if path.endswith("/auth/v1/token") or path.endswith("/auth/v1/signup"):
            if request.url.params.get("grant_type") == "refresh_token" and self.refresh_status != 200:
                return res({"message": "Invalid refresh token"}, self.refresh_status)
            return res({"access_token": "test-access", "refresh_token": "test-refresh", "expires_in": 3600, "user": {"id": USER_ID, "email": "test@example.invalid"}})
        if path.endswith("/auth/v1/user"):
            return res({"id": USER_ID, "email": "test@example.invalid"})
        if "/auth/v1/admin/users" in path:
            return res({"id": STAFF_ID})
        if path.endswith("/auth/v1/logout"):
            return res({})
        if path.endswith("/rest/v1/staff_profiles"):
            return res([] if self.role == "user" else [{"id": USER_ID, "email": "test@example.invalid", "full_name": "Test Admin", "role": self.role, "active": self.active}])
        if path.endswith("/rest/v1/contact_messages"):
            if request.method == "PATCH":
                return res([{"id": CONTACT_ID, **body}])
            return res([{"id": CONTACT_ID, "email": "sender@example.invalid", "full_name": "Test Sender", "inquiry_type": "general"}])
        if path.endswith("/rpc/my_bloodcare_profile"):
            if self.profile_unauthorized_once:
                self.profile_unauthorized_once = False
                return res({"message": "Expired token"}, 401)
            return res({"account": {"id": USER_ID, "full_name": "Test User", "email": "test@example.invalid"}, "profile": None, "requests": [], "appointments": [], "donations": []})
        if path.endswith("/rpc/admin_set_staff_facilities"):
            return res({"message": "Facility assignment result"}, self.assignment_status)
        if path.endswith("/rpc/submit_contact_message"):
            return res(CONTACT_ID)
        if "/rest/v1/rpc/" in path:
            return res(self.rows if self.rpc_status == 200 else {"message": "RPC denied"}, self.rpc_status)
        if "/rest/v1/" in path:
            return res(self.rows if self.db_status == 200 else {"message": "Database denied"}, self.db_status, {"content-range": f"0-0/{len(self.rows)}"})
        if "/storage/v1/object/public/" in path:
            return httpx.Response(200, content=b"image-fixture", headers={"content-type": "image/png"})
        if "/storage/v1/" in path:
            return res({"path": "image.png"})
        raise AssertionError(f"Unexpected test upstream request: {request.method} {path}")

class ApiTests(unittest.TestCase):
    def setUp(self):
        self.upstream = Upstream()
        self.app = create_app(CONFIG, transport=httpx.MockTransport(self.upstream))
        self.client = self.enterContext(TestClient(self.app, headers={"X-BloodCare-Request": "1"}))

    def login_cookie(self):
        self.client.cookies.set("bc_access_token", "test-access")

    def db(self, **overrides):
        return self.client.post("/api/db", json={"table": "facilities", **overrides})

    def test_liveness_does_not_call_supabase(self):
        response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["ok"])
        self.assertEqual(len(self.upstream.calls), 0)

    def test_readiness_calls_database_and_caches(self):
        self.assertEqual(self.client.get("/api/ready").status_code, 200)
        self.assertEqual(self.client.get("/api/ready").status_code, 200)
        self.assertEqual(len(self.upstream.calls), 1)

    def test_readiness_reports_outage(self):
        self.upstream.offline = True
        self.assertEqual(self.client.get("/api/ready").status_code, 503)

    def test_unconfigured_site_can_render_but_is_not_ready(self):
        with TestClient(create_app(Settings(environment="test"))) as client:
            self.assertEqual(client.get("/").status_code, 200)
            self.assertEqual(client.get("/api/health").status_code, 200)
            self.assertEqual(client.get("/api/ready").status_code, 503)

    def test_public_pages_and_assets(self):
        for url in ["/", "/index.html", "/login.html", "/map.html", "/js/app.js", "/js/pages/blood-search.js", "/css/theme.css"]:
            with self.subTest(url=url):
                self.assertEqual(self.client.get(url).status_code, 200)

    def test_private_files_are_not_served(self):
        for url in ["/.env", "/requirements.txt", "/server/main.py", "/supabase/schema.sql"]:
            with self.subTest(url=url):
                self.assertEqual(self.client.get(url).status_code, 404)

    def test_account_redirect_preserves_search(self):
        r = self.client.get("/blood-search.html?blood_type=A%2B&facility_id=" + FACILITY_ID, follow_redirects=False)
        self.assertEqual(r.status_code, 303)
        self.assertIn("next=", r.headers["location"])
        self.assertIn("facility_id", r.headers["location"])

    def test_management_pages_require_session_cookie(self):
        self.assertEqual(self.client.get("/admin.html", follow_redirects=False).status_code, 303)

    def test_cookie_only_page_gate_does_not_replace_real_api_authorization(self):
        self.login_cookie()
        self.assertEqual(self.client.get("/blood-search.html").status_code, 200)
        self.upstream.role = "user"
        self.assertEqual(self.client.get("/api/admin/config").status_code, 403)

    def test_no_store_on_api_and_protected_html(self):
        self.login_cookie()
        for url in ["/api/auth/session", "/profile.html"]:
            self.assertIn("no-store", self.client.get(url).headers["cache-control"])

    def test_assets_revalidate(self):
        self.assertIn("no-cache", self.client.get("/js/app.js").headers["cache-control"])

    def test_security_headers(self):
        h = self.client.get("/").headers
        self.assertEqual(h["x-content-type-options"], "nosniff")
        self.assertEqual(h["x-frame-options"], "DENY")
        self.assertEqual(len(h["x-request-id"]), 32)

    def test_cross_origin_write_rejected_even_with_marker(self):
        r = self.client.post("/api/db", json={"table": "facilities"}, headers={"Origin": "https://attacker.example"})
        self.assertEqual(r.status_code, 403)
        self.assertEqual(len(self.upstream.calls), 0)

    def test_same_origin_post_allowed(self):
        self.assertEqual(self.client.post("/api/db", json={"table": "facilities"}, headers={"Origin": "http://testserver"}).status_code, 200)

    def test_missing_origin_and_marker_rejected(self):
        self.client.headers.pop("X-BloodCare-Request")
        self.assertEqual(self.db().status_code, 403)

    def test_null_origin_rejected(self):
        self.assertEqual(self.client.post("/api/auth/refresh", headers={"Origin": "null"}).status_code, 403)

    def test_cross_site_logout_navigation_rejected(self):
        self.assertEqual(self.client.get("/logout", headers={"Sec-Fetch-Site": "cross-site"}).status_code, 403)

    def test_native_same_origin_logout(self):
        self.login_cookie()
        self.client.headers.pop("X-BloodCare-Request")
        r = self.client.post("/logout", headers={"Origin": "http://testserver"}, follow_redirects=False)
        self.assertEqual(r.status_code, 303)
        self.assertIn("Max-Age=0", r.headers["set-cookie"])

    def test_sign_in_sets_httponly_cookies(self):
        r = self.client.post("/api/auth/sign-in", json={"email": " TEST@EXAMPLE.INVALID ", "password": "test-password"})
        self.assertEqual(r.status_code, 200)
        self.assertIn("HttpOnly", r.headers["set-cookie"])
        self.assertNotIn("access_token", r.json())
        self.assertEqual(json.loads(self.upstream.calls[0].content)["email"], "test@example.invalid")

    def test_disabled_staff_denied_and_cookies_cleared(self):
        self.upstream.active = False
        r = self.client.post("/api/auth/sign-in", json={"email": "test@example.invalid", "password": "test-password"})
        self.assertEqual(r.status_code, 403)
        self.assertIn("Max-Age=0", r.headers["set-cookie"])

    def test_sign_up_contract(self):
        r = self.client.post("/api/auth/sign-up", json={"email": "test@example.invalid", "password": "test-password", "full_name": "Test User"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["session"], True)

    def test_guest_session_returns_null_user(self):
        self.assertIsNone(self.client.get("/api/auth/session").json()["user"])

    def test_refresh_rejected_clears_response_cookies(self):
        self.client.cookies.set("bc_refresh_token", "invalid-refresh")
        self.upstream.refresh_status = 400
        r = self.client.post("/api/auth/refresh")
        self.assertEqual(r.status_code, 401)
        self.assertIn("Max-Age=0", r.headers["set-cookie"])

    def test_refresh_outage_does_not_clear_cookies(self):
        self.client.cookies.set("bc_refresh_token", "existing-refresh")
        self.upstream.refresh_status = 503
        r = self.client.post("/api/auth/refresh")
        self.assertEqual(r.status_code, 503)
        self.assertNotIn("set-cookie", r.headers)

    def test_logout_survives_upstream_outage(self):
        self.login_cookie(); self.upstream.logout_offline = True
        r = self.client.post("/api/auth/sign-out")
        self.assertEqual(r.status_code, 200)
        self.assertIn("Max-Age=0", r.headers["set-cookie"])

    def test_database_user_token_preserved(self):
        self.login_cookie()
        self.assertEqual(self.db().status_code, 200)
        self.assertEqual(self.upstream.calls[-1].headers["authorization"], "Bearer test-access")
        self.assertEqual(self.upstream.calls[-1].headers["apikey"], "test-public-key")

    def test_public_database_never_uses_service_key(self):
        self.db()
        self.assertEqual(self.upstream.calls[-1].headers["apikey"], "test-public-key")

    def test_disallowed_table_and_rpc(self):
        self.assertEqual(self.db(table="auth.users").status_code, 400)
        self.assertEqual(self.client.post("/api/rpc/unknown_function", json={}).status_code, 400)
        self.assertEqual(len(self.upstream.calls), 0)

    def test_query_filters_order_range_and_count(self):
        r = self.db(filters=[{"op": "eq", "column": "active", "value": True}], orders=[{"column": "name", "ascending": False}], range={"start": 0, "end": 4}, count="exact")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["count"], 1)
        q = self.upstream.calls[-1].url.params
        self.assertEqual(q["active"], "eq.true")
        self.assertEqual(q["order"], "name.desc")
        self.assertEqual(q["limit"], "5")

    def test_invalid_ranges_rejected(self):
        for span in [{"start": 10, "end": 5}, {"start": 0, "end": 5000}]:
            self.assertEqual(self.db(range=span).status_code, 422)

    def test_single_and_maybe_single(self):
        self.assertEqual(self.db(single=True).json()["data"]["id"], FACILITY_ID)
        self.upstream.rows = []
        self.assertIsNone(self.db(maybe_single=True).json()["data"])
        self.assertEqual(self.db(single=True).status_code, 406)

    def test_database_errors_preserved(self):
        self.upstream.db_status = 403
        self.assertEqual(self.db().status_code, 403)

    def test_upstream_errors_are_generic(self):
        self.upstream.offline = True
        r = self.db()
        self.assertEqual(r.status_code, 503)
        self.assertNotIn("simulated-private", r.text)

    def test_rpc_user_token_preserved(self):
        self.login_cookie()
        r = self.client.post("/api/rpc/public_facility_inventory", json={"p_blood_type": "A+"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(json.loads(self.upstream.calls[-1].content)["p_blood_type"], "A+")
        self.assertEqual(self.upstream.calls[-1].headers["apikey"], "test-public-key")

    def test_contact_submission(self):
        r = self.client.post("/api/contact", json={"full_name": " Test Sender ", "email": " TEST@EXAMPLE.INVALID ", "phone": "09123456789", "message": "This is a test message."})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["id"], CONTACT_ID)
        self.assertEqual(self.upstream.calls[-1].headers["apikey"], "test-public-key")

    def test_invalid_contact_phone(self):
        r = self.client.post("/api/contact", json={"full_name": "Test Sender", "email": "test@example.invalid", "phone": "invalid-phone", "message": "This is a test message."})
        self.assertEqual(r.status_code, 422)
        self.assertEqual(len(self.upstream.calls), 0)

    def test_admin_requires_login(self):
        self.assertEqual(self.client.get("/api/admin/config").status_code, 401)

    def test_staff_cannot_use_admin_endpoints(self):
        self.login_cookie(); self.upstream.role = "staff"
        self.assertEqual(self.client.get("/api/admin/config").status_code, 403)

    def test_admin_config_exposes_booleans_not_keys(self):
        self.login_cookie()
        r = self.client.get("/api/admin/config")
        self.assertEqual(r.status_code, 200)
        self.assertNotIn("test-service-key", r.text)
        self.assertIsInstance(r.json()["staff_auth_ready"], bool)

    def staff_body(self):
        return {"full_name": "Test Staff", "email": "new@example.invalid", "password": "test-password", "confirm_password": "test-password", "role": "staff", "primary_facility_id": FACILITY_ID}

    def test_admin_provisioning_keeps_rpc_scoped_to_admin_user(self):
        self.login_cookie()
        r = self.client.post("/api/admin/staff", json=self.staff_body())
        self.assertEqual(r.status_code, 200)
        create = next(x for x in self.upstream.calls if x.url.path.endswith("/admin/users"))
        assignment = next(x for x in self.upstream.calls if x.url.path.endswith("/admin_set_staff_facilities"))
        self.assertEqual(create.headers["apikey"], "test-service-key")
        self.assertEqual(assignment.headers["apikey"], "test-public-key")
        self.assertEqual(assignment.headers["authorization"], "Bearer test-access")

    def test_staff_creation_failure_rolls_back_auth_user(self):
        self.login_cookie(); self.upstream.assignment_status = 400
        self.assertEqual(self.client.post("/api/admin/staff", json=self.staff_body()).status_code, 400)
        self.assertTrue(any(x.method == "DELETE" and "/auth/v1/admin/users/" in x.url.path for x in self.upstream.calls))

    def test_password_mismatch_does_not_create_auth_user(self):
        self.login_cookie(); body = self.staff_body(); body["confirm_password"] = "different-password"
        self.assertEqual(self.client.post("/api/admin/staff", json=body).status_code, 422)
        self.assertFalse(any("/auth/v1/admin/users" in x.url.path for x in self.upstream.calls))

    def test_staff_password_reset(self):
        self.login_cookie()
        r = self.client.post(f"/api/admin/staff/{STAFF_ID}/password", json={"password": "new-password", "confirm_password": "new-password"})
        self.assertEqual(r.status_code, 200)

    def test_contact_reply_uses_mock_email_and_records_delivery(self):
        self.login_cookie()
        with patch("server.services.admin.send_contact_reply") as send:
            r = self.client.post(f"/api/admin/contact/{CONTACT_ID}/reply", json={"message": "Test reply"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(send.call_count, 1)
        self.assertEqual(r.json()["data"]["email_delivery_status"], "sent")

    def test_email_failure_does_not_mark_replied_or_leak_error(self):
        self.login_cookie()
        with patch("server.services.admin.send_contact_reply", side_effect=RuntimeError("private-smtp-detail")):
            r = self.client.post(f"/api/admin/contact/{CONTACT_ID}/reply", json={"message": "Test reply"})
        self.assertEqual(r.status_code, 503)
        self.assertNotIn("private-smtp-detail", r.text)
        self.assertFalse(any(x.method == "PATCH" for x in self.upstream.calls))

    def test_profile_ticket_http_contract(self):
        self.login_cookie()
        with patch("server.services.profile.build_profile_pdf", return_value=b"%PDF-fixture"):
            r = self.client.get("/api/profile/ticket.pdf")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.headers["content-type"], "application/pdf")
        self.assertIn("BloodCare_Profile_Account.pdf", r.headers["content-disposition"])
        self.assertIn("no-store", r.headers["cache-control"])

    def test_profile_ticket_refreshes_once(self):
        self.login_cookie(); self.client.cookies.set("bc_refresh_token", "test-refresh")
        self.upstream.profile_unauthorized_once = True
        with patch("server.services.profile.build_profile_pdf", return_value=b"%PDF-fixture"):
            r = self.client.get("/api/profile/ticket.pdf")
        self.assertEqual(r.status_code, 200)
        self.assertIn("set-cookie", r.headers)
        self.assertEqual(sum(x.url.path.endswith("/auth/v1/token") for x in self.upstream.calls), 1)

    def test_storage_upload(self):
        self.login_cookie()
        r = self.client.post("/api/storage/upload/event-images/test.png", files={"file": ("test.png", b"png-fixture", "image/png")})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self.upstream.calls[-1].headers["apikey"], "test-public-key")

    def test_storage_upload_needs_login(self):
        r = self.client.post("/api/storage/upload/event-images/test.png", files={"file": ("test.png", b"png-fixture", "image/png")})
        self.assertEqual(r.status_code, 401)

    def test_storage_buckets_are_allowlisted(self):
        self.assertEqual(self.client.get("/api/storage/public/private/test.png").status_code, 404)

    def test_public_image_response(self):
        r = self.client.get("/api/storage/public/event-images/test.png")
        self.assertEqual(r.content, b"image-fixture")
        self.assertIn("max-age=3600", r.headers["cache-control"])

    def test_storage_delete(self):
        self.login_cookie()
        r = self.client.request("DELETE", "/api/storage/event-images", json={"paths": ["test.png"]})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(json.loads(self.upstream.calls[-1].content), {"prefixes": ["test.png"]})

    def test_unknown_api_route_is_json(self):
        r = self.client.get("/api/does-not-exist")
        self.assertEqual(r.status_code, 404)
        self.assertIn("application/json", r.headers["content-type"])

    def test_production_secure_cookie_and_host_checks(self):
        config = replace(CONFIG, environment="production", cookie_secure=True, public_origin="https://bloodcare.example.invalid")
        with TestClient(create_app(config, transport=httpx.MockTransport(self.upstream)), base_url="https://bloodcare.example.invalid", headers={"X-BloodCare-Request": "1"}) as client:
            r = client.post("/api/auth/sign-in", json={"email": "test@example.invalid", "password": "test-password"})
            self.assertIn("Secure", r.headers["set-cookie"])
            self.assertIn("strict-transport-security", r.headers)
            self.assertEqual(client.get("/api/health", headers={"Host": "attacker.example"}).status_code, 400)
            self.assertEqual(client.get("/openapi.json").status_code, 404)

if __name__ == "__main__":
    unittest.main()
