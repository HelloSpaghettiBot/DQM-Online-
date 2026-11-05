import importlib.util
import json
import logging
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("dqm_web", ROOT / "web/service.py")
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)

class AccountTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(dir=ROOT / ".local")
        folder = Path(cls.directory.name)
        cls.database = folder / "accounts.db"
        service.initialize(cls.database)
        cls.server = service.ThreadingHTTPServer(("127.0.0.1", 0), service.Handler)
        cls.server.database = cls.database
        cls.server.public = ROOT / "web/public"
        cls.server.status_file = folder / "status.json"
        cls.server.origins = ["https://403world.com"]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.directory.cleanup()

    def request(self, endpoint, payload=None, origin="https://403world.com"):
        headers = {"Origin": origin, "Content-Type": "application/json"}
        request = Request(self.base + "/DQM" + endpoint, json.dumps(payload).encode() if payload is not None else None, headers)
        try:
            with urlopen(request, timeout=10) as response: return response.status, json.load(response)
        except HTTPError as error:
            with error: return error.code, json.load(error)

    def test_account_password_and_ticket(self):
        body = {"username": "tester", "password": "a private password 7492"}
        self.assertEqual(self.request("/api/register", body)[0], 201)
        self.assertEqual(self.request("/api/register", body)[0], 409)
        self.assertEqual(self.request("/api/login", {**body, "password": "the wrong password"})[0], 401)
        code, result = self.request("/api/login", body)
        self.assertEqual(code, 200)
        self.assertEqual(len(result["ticket"]), 64)
        with sqlite3.connect(self.database) as db:
            row = db.execute("SELECT password_hash,password_salt FROM accounts WHERE username='tester'").fetchone()
            self.assertNotEqual(row[0], body["password"])
            self.assertEqual(len(row[1]), 32)
            self.assertEqual(db.execute("SELECT count(*) FROM login_tickets").fetchone()[0], 1)

    def test_cross_origin_rejected(self):
        code, result = self.request("/api/register", {"username": "nobody", "password": "a private password"}, origin="https://untrusted.example")
        self.assertEqual(code, 403)

    def test_status_has_no_private_fields(self):
        code, result = self.request("/api/status")
        self.assertEqual(code, 200)
        self.assertFalse(result["online"])
        self.assertNotIn("accounts", result)

    def test_unsafe_name_rejected(self):
        self.assertEqual(self.request("/api/register", {"username": "name'; DROP TABLE accounts;", "password": "not a real password"})[0], 400)

if __name__ == "__main__": unittest.main()
