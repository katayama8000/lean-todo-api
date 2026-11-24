from http.client import HTTPConnection
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

ROOT = Path(__file__).resolve().parent.parent
PROJECT = f"lean-todo-test-{uuid4().hex[:10]}"
ENV = {**os.environ, "TODO_HOST_PORT": "0"}


def compose(*args, capture=False):
    result = subprocess.run(
        ["docker", "compose", "-p", PROJECT, *args],
        cwd=ROOT,
        env=ENV,
        check=True,
        text=True,
        capture_output=capture,
    )
    return result.stdout.strip() if capture else None


def request(base, method, path, expected, payload=None, raw=None):
    body = json.dumps(payload).encode() if payload is not None else raw
    headers = {"Content-Type": "application/json"} if body is not None else {}
    req = Request(base + path, data=body, headers=headers, method=method)
    try:
        response = urlopen(req, timeout=5)
    except HTTPError as error:
        response = error
    with response:
        data = response.read()
        assert response.code == expected, (method, path, response.code, data)
        return json.loads(data) if data and expected != 413 else data, response.headers


def check_chunked_limit(base):
    connection = HTTPConnection(base.removeprefix("http://"), timeout=5)
    try:
        connection.request(
            "POST",
            "/todos",
            body=iter([b" " * 8192] * 3),
            headers={"Content-Type": "application/json"},
            encode_chunked=True,
        )
        response = connection.getresponse()
        assert response.status == 413, (response.status, response.read())
    finally:
        connection.close()


def wait_for_api(base):
    for _ in range(100):
        try:
            result, _ = request(base, "GET", "/health", 200)
        except (URLError, ConnectionError):
            time.sleep(0.1)
        else:
            assert result == {"status": "ok"}
            return
    raise RuntimeError("API did not become ready.")


def main():
    try:
        compose("up", "--build", "-d")
        base = f"http://{compose('port', 'api', '8080', capture=True)}"
        wait_for_api(base)

        assert request(base, "GET", "/todos", 200)[0] == []
        request(base, "POST", "/todos", 400, {"title": "  "})
        request(base, "POST", "/todos", 400, {"title": "a" * 201})
        request(base, "POST", "/todos", 400, raw=b"{")
        request(base, "POST", "/todos", 400, raw=b'{"title":"\xff"}')
        request(base, "POST", "/todos", 413, {"title": "a" * 20000})
        check_chunked_limit(base)
        request(base, "GET", "/todos/9223372036854775808", 400)
        assert request(base, "PATCH", "/todos", 405)[1]["Allow"] == "GET, POST"

        title = "日本語 ' ); DROP TABLE todos; --"
        todo, headers = request(base, "POST", "/todos", 201, {"title": f"  {title}  "})
        assert todo == {"id": 1, "title": title, "completed": False}
        path = headers["Location"]
        assert path == f"/todos/{todo['id']}"
        assert request(base, "GET", path, 200)[0] == todo

        request(base, "PUT", path, 400, {"title": "Missing completed"})
        updated, _ = request(base, "PUT", path, 200, {"title": "Done", "completed": True})
        assert updated == {"id": todo["id"], "title": "Done", "completed": True}

        compose("stop", "--timeout", "1", "api")
        compose("rm", "-f", "api")
        compose("up", "-d", "--no-build")
        base = f"http://{compose('port', 'api', '8080', capture=True)}"
        wait_for_api(base)
        assert request(base, "GET", "/todos", 200)[0] == [updated]
        assert request(base, "DELETE", path, 204)[0] == b""
        request(base, "GET", path, 404)
        request(base, "PUT", path, 404, {"title": "Gone", "completed": False})
        request(base, "DELETE", path, 404)
        assert request(base, "GET", "/todos", 200)[0] == []
        print("PASS: HTTP CRUD, validation, body limit, and SQLite volume persistence")
    except Exception:
        subprocess.run(["docker", "compose", "-p", PROJECT, "logs"], cwd=ROOT, env=ENV)
        raise
    finally:
        compose("down", "--timeout", "1", "--volumes", "--rmi", "local")


if __name__ == "__main__":
    main()
