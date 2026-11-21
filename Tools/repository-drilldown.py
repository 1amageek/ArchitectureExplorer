"""Exercise scoped navigation through the actual CLI and authenticated HTTP host."""
import http.client
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
from urllib.parse import quote, urlsplit

root = Path(__file__).resolve().parents[1]
cli = root / ".build/debug/architecture"
web = root / "Apps/ArchitectureExplorerWeb/.build/debug/architecture-web"
with tempfile.TemporaryDirectory() as temp:
    directory = Path(temp)
    repo = directory / "app"
    src = repo / "src"
    src.mkdir(parents=True)
    text = "export class Box { open(): number { return 1 } }"
    (src / "model.ts").write_text(text)
    (src / "link.ts").symlink_to(directory / "outside.ts")
    (directory / "outside.ts").write_text("out of scope")
    (repo / "node_modules").mkdir()
    (src / "boot.ts").write_text('import { Box } from "./model.js"; \nexport function start() { return new Box(); }')
    (repo / "compose.yaml").write_text(
        "services:\n  api:\n    build: {context: ., target: server}\n    networks: [private]\n    volumes: [state:/var/lib/app]\n"
        "  worker:\n    depends_on: {api: {condition: service_healthy}}\n    networks: [private]\nnetworks: {private: {}}\nvolumes: {state: {}}\n")
    (repo / "Dockerfile").write_text('FROM node AS server\nENTRYPOINT ["node","dist/boot.js"]\n')
    (repo / "tsconfig.json").write_text('{"compilerOptions":{"outDir":"dist","rootDir":"src"}}')
    (src / "Types.swift").write_text("struct Item { func save() {} }")
    (src / "types.rs").write_text("struct Item {}\nimpl Item { fn save(&self) {} }")
    (src / "damaged.ts").write_bytes(b"\xff")
    (src / "big.ts").write_text("a" * 20000)
    catalog = directory / "map.json"
    catalog.write_text(json.dumps({"nodes": [{"id": "app", "label": "app", "role": "Repository",
        "details": {"checkouts": ["app"]}}], "edges": [], "title": "Example"}))
    proc = subprocess.Popen([cli, "explore", "--workspace", directory, "--repository-map", catalog,
        "--no-open", "--web-helper", web], stdout=subprocess.PIPE, start_new_session=True)
    try:
        assert select.select([proc.stdout], [], [], 20)[0]
        url = urlsplit(json.loads(proc.stdout.readline())["url"])
        origin = "http://" + url.netloc

        def request(path, headers=None, body=None):
            conn = http.client.HTTPConnection(url.hostname, url.port, timeout=5)
            conn.request("POST" if body else "GET", path, body, headers or {})
            response = conn.getresponse()
            result = response.status, response.getheaders(), response.read()
            conn.close()
            return result

        endpoint = "/api?method=repository.browse&params="
        assert request(endpoint + "%7B%7D")[0] == 403
        _, headers, _ = request("/session", {"Origin": origin, "Content-Type": "application/json"},
            json.dumps({"token": url.fragment.removeprefix("token=")}))
        cookie = next(v for k, v in headers if k.lower() == "set-cookie" and v.startswith("architecture-session-")).split(";")[0]
        def browse(params, status=200):
            code, _, body = request(endpoint + quote(json.dumps(params)), {"Cookie": cookie})
            assert code == status, (code, body)
            return json.loads(body)

        assert [n["id"] for n in browse({})["nodes"]] == ["app"]
        deployment = browse({"repo": "app"})
        assert deployment["architecture"] == "Deployment architecture"
        assert set(n["id"] for n in deployment["nodes"]) == {"service:api", "service:worker", "network:private", "volume:state"}
        assert {tuple(e[k] for k in ("source","target","label")) for e in deployment["edges"]} == {
            ("service:worker","service:api","Requires healthy service"),
            ("service:api","volume:state","Mounts"), ("service:api","network:private","Joins"), ("service:worker","network:private","Joins")}
        assert browse({"repo":"app","path":["src"]}) == deployment
        composition = browse({"repo":"app","service":"api"})
        assert ("entry","binding:Box","Constructs") in [tuple(e[k] for k in ("source","target","label")) for e in composition["edges"]]
        assert all(n["language"] == "typescript" for n in composition["nodes"])
        assert composition["edges"][0]["details"]["evidence"].startswith("src/boot.ts:2 · Constructs Box")
        assert any(n.get("sourcePath") == ["src","boot.ts"] for n in composition["nodes"])
        assert "unresolved" in browse({"repo":"app","service":"worker"})["outlineNotice"].lower()
        (repo / "compose.yaml").unlink()
        assert browse({"repo":"app"})["architecture"] == "Architecture unresolved"
        (repo / "package.json").write_text('{"name":"App","exports":{".":"./dist/boot.js"},"dependencies":{"library":"1.0"}}')
        package = browse({"repo":"app"})
        assert [(e["target"],e["label"]) for e in sorted(package["edges"], key=lambda e:e["target"])] == [
            ("export:.","Exports"),("package:library","Depends on")]
        result = browse({"repo": "app", "path": ["src", "model.ts"]})
        assert result["text"] == text
        assert all(n["language"] == "typescript" for n in result["nodes"])
        owner, method = result["nodes"]
        assert (owner["label"], method["label"], method["parentID"]) == ("Box", "open", owner["id"])
        assert text[method["startByte"]:method["endByte"]].startswith("open()")
        for source in ["Types.swift", "types.rs"]:
            outline = browse({"repo": "app", "path": ["src", source]})["nodes"]
            assert all(n["language"] == ("swift" if source.endswith(".swift") else "rust") for n in outline)
            assert any(node["label"] == "Item" for node in outline), outline
            assert any(node["label"] == "save" for node in outline), outline
        assert "error" in browse({"repo": "app", "path": ["src", "damaged.ts"]}, 400)
        big = browse({"repo": "app", "path": ["src", "big.ts"]})
        assert big["truncated"] and len(big["text"]) == 16384 and "nodes" not in big
        for path in [[".."], [".git"], ["src", "link.ts"], ["node_modules"]]:
            assert "error" in browse({"repo": "app", "path": path}, 400)
        repo.rename(directory / "moved")
        assert not browse({})["nodes"]
        assert "error" in browse({"repo": "app"}, 400)
        assert subprocess.run([cli, "daemon", "status", "--workspace", directory], capture_output=True, timeout=5).returncode != 0
        print("PASS: real CLI, no daemon, local HTTP authentication, deployment relationships, service composition, package graph, unresolved scope, lexical outline, preview budget, removal and path boundaries")
    finally:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=10)
