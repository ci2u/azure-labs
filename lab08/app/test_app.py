"""Unit tests the pipeline runs before it builds an image. Run: python -m unittest -v"""
import threading
import unittest
import urllib.request
from http.server import ThreadingHTTPServer

import app


class BuildMessageTest(unittest.TestCase):
    def test_message_format(self):
        self.assertEqual(app.build_message("Hi", "pod-1", "v9"), "Hi from pod-1 (version v9)\n")


class HttpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # port 0 = let the OS pick a free port
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}", timeout=5) as resp:
            return resp.status, resp.read().decode()

    def test_healthz(self):
        self.assertEqual(self.get("/healthz"), (200, "ok\n"))

    def test_home_page(self):
        status, body = self.get("/")
        self.assertEqual(status, 200)
        self.assertTrue(body.startswith(app.GREETING))
        self.assertIn(f"(version {app.VERSION})", body)


if __name__ == "__main__":
    unittest.main()
