#!/usr/bin/env python3
"""A pretend Klipsch Cinema 1200 for the build checks. Answers the same web calls as the real one:
GET /api/getData?path=…&roles=value and POST /api/setData."""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 80
LOG = open(sys.argv[2] if len(sys.argv) > 2 else "fake_soundbar.log", "a", buffering=1)

values = {
    "settings:/deviceName": {"type": "string_", "string_": "Living Room"},
    "settings:/system/manufacturer": {"type": "string_", "string_": "Klipsch"},
    "settings:/system/modelName": {"type": "string_", "string_": "Klipsch Cinema 1200"},
    "settings:/system/serialNumber": {"type": "string_", "string_": "KC1200TEST"},
    "settings:/version": {"type": "string_", "string_": "2.6.1"},
    "player:volume": {"type": "i32_", "i32_": 25},
    "settings:/mediaPlayer/mute": {"type": "bool_", "bool_": False},
    "settings:/cinema/physicalAudioInput": {"type": "cinemaPhysicalAudioInput", "cinemaPhysicalAudioInput": "tv"},
    "settings:/cinema/nightMode": {"type": "cinemaNightMode", "cinemaNightMode": "nightMode_0"},
    "settings:/cinema/dialogMode": {"type": "cinemaDialogMode", "cinemaDialogMode": "dialog_0"},
    "settings:/cinema/postProcessorMode": {"type": "cinemaPostProcessorMode", "cinemaPostProcessorMode": "standard"},
    "settings:/cinema/ledMode": {"type": "cinemaLEDMode", "cinemaLEDMode": "normal"},
    "cinema:/channelVolumeSet": {"type": "variant", "variant": {"sub": 0, "surr_L": 0, "surr_R": 0}},
    "settings:/cinema/dsp/cinemaBass": {"type": "double_", "double_": 0.0},
    "settings:/cinema/dsp/cinemaMid": {"type": "double_", "double_": 0.0},
    "settings:/cinema/dsp/cinemaTreble": {"type": "double_", "double_": 0.0},
}
power = {"target": "networkStandby"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/api/getData":
            return self.reply(404, {"error": "not found"})
        path = parse_qs(url.query).get("path", [""])[0]
        LOG.write(f"GET {path}\n")
        if path == "powermanager:target":
            return self.reply(200, [{"type": "powerTarget", "powerTarget": {"target": power["target"], "nextTarget": "none", "nextReason": "none"}}])
        if path == "player:volume":
            # The real soundbar wraps this one differently.
            return self.reply(200, {"path": path, "roles": "value", "value": values[path]})
        if path in values:
            return self.reply(200, [values[path]])
        return self.reply(500, {"error": "unknown path"})

    def do_POST(self):
        if urlparse(self.path).path != "/api/setData":
            return self.reply(404, {"error": "not found"})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        path, role, value = body.get("path"), body.get("roles"), body.get("value", {})
        LOG.write(f"SET {path} {role} {json.dumps(value, sort_keys=True)}\n")
        if path == "powermanager:targetRequest" and role == "activate":
            power["target"] = value.get("target", "online")
            return self.reply(200, {})
        if path not in values:
            return self.reply(500, {"error": "unknown path"})
        # Like the real one, changing any setting while on standby wakes it.
        power["target"] = "online"
        if path == "cinema:/channelVolumeSet":
            values[path]["variant"].update(value.get("variant", {}))
        else:
            values[path] = value
        return self.reply(200, {})


print(f"Pretend soundbar listening on {PORT}", flush=True)
ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
