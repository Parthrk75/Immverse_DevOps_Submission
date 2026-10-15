#!/usr/bin/env python3
"""STAND-IN for the black-box app, used ONLY for the local kind demo (the real app is not rewritten).
Implements the documented contract: :8080 /healthz /readyz /metrics, a Redis-queue worker,
SIGTERM draining, and a failure injector so we can ship a deliberately BAD release.
  ERROR_RATE=0.3  -> 30 % of API requests return 500      (bad-release demo)
  LATENCY_MS=900  -> adds latency                           (latency-gate demo)
"""
import json, os, random, signal, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))
LATENCY_MS = int(os.getenv("LATENCY_MS", "0"))
BUCKETS = [0.05, 0.1, 0.2, 0.4, 0.8, 1.6, float("inf")]
lock = threading.Lock()
counts = {}                 # status -> n
hist = [0] * len(BUCKETS)   # cumulative later
hist_sum = 0.0
ready = True


def observe(status, dur):
    global hist_sum
    with lock:
        counts[status] = counts.get(status, 0) + 1
        hist_sum += dur
        for i, b in enumerate(BUCKETS):
            if dur <= b:
                hist[i] += 1      # first matching bucket only; exporter makes it cumulative
                break


def metrics():
    out = ["# TYPE http_requests_total counter"]
    with lock:
        for s, n in counts.items():
            out.append(f'http_requests_total{{status="{s}"}} {n}')
        out.append("# TYPE http_request_duration_seconds histogram")
        cum = 0
        for b, n in zip(BUCKETS, hist):
            cum += n
            le = "+Inf" if b == float("inf") else b
            out.append(f'http_request_duration_seconds_bucket{{le="{le}"}} {cum}')
        out.append(f"http_request_duration_seconds_sum {hist_sum}")
        out.append(f"http_request_duration_seconds_count {cum}")
    return "\n".join(out) + "\n"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz": return self._send(200, b'{"ok":true}')
        if self.path == "/readyz": return self._send(200 if ready else 503, b'{"ready":%s}' % (b"true" if ready else b"false"))
        if self.path == "/metrics": return self._send(200, metrics().encode(), "text/plain")
        t0 = time.time()
        if LATENCY_MS: time.sleep(LATENCY_MS / 1000)
        time.sleep(random.uniform(0.005, 0.03))
        status = 500 if random.random() < ERROR_RATE else 200
        observe(status, time.time() - t0)
        self._send(status, json.dumps({"status": status}).encode())


def run_api():
    global ready
    srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)

    def term(*_):
        global ready
        ready = False                       # fail readiness first, keep serving in-flight requests
        threading.Thread(target=lambda: (time.sleep(5), srv.shutdown()), daemon=True).start()
    signal.signal(signal.SIGTERM, term)
    srv.serve_forever()
    print("api drained, exiting")


def run_worker():
    import redis  # pip install redis
    r = redis.Redis(host=os.environ["REDIS_HOST"], password=os.getenv("REDIS_PASSWORD") or None)
    stop = {"v": False}
    signal.signal(signal.SIGTERM, lambda *_: stop.update(v=True))   # stop pulling, finish current job
    done = 0
    while not stop["v"]:
        item = r.blpop("jobs", timeout=2)
        if not item: continue
        time.sleep(float(os.getenv("JOB_SECONDS", "5")))            # simulated job
        done += 1
        print(f"job done total={done}", flush=True)
    print(f"worker drained cleanly after {done} jobs", flush=True)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "api"
    if "--migrate-only" in sys.argv:
        print("migrations applied (stub)"); sys.exit(0)
    run_worker() if mode == "worker" else run_api()
