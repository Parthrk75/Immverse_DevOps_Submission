// 15x ramp: 150 -> 2250 req/s in 3 min, hold, ramp down.  Thresholds = the SLOs.
// Run:  k6 run -e BASE=https://api.example.com loadtest/k6/peak.js
// Scaled-down local run: -e SCALE=0.05  (7 -> 112 req/s on kind), then extrapolate with scripts/capacity.py
import http from 'k6/http';
import { check } from 'k6';
const S = parseFloat(__ENV.SCALE || '1');
const BASE = __ENV.BASE || 'http://app.localtest.me:8080';
export const options = {
  scenarios: {
    peak: {
      executor: 'ramping-arrival-rate', timeUnit: '1s',
      preAllocatedVUs: Math.ceil(300 * S) + 20, maxVUs: Math.ceil(3000 * S) + 50,
      startRate: Math.ceil(150 * S),
      stages: [
        { target: Math.ceil(150 * S),  duration: '2m' },   // baseline
        { target: Math.ceil(2250 * S), duration: '3m' },   // 15x ramp  (scale-out must keep up)
        { target: Math.ceil(2250 * S), duration: '10m' },  // hold
        { target: Math.ceil(150 * S),  duration: '3m' },   // back down (scale-in, workers drain)
        { target: Math.ceil(150 * S),  duration: '2m' },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.001'],            // availability budget
    http_req_duration: ['p(95)<400'],           // p95 SLO
  },
};
export default function () {
  const r = http.get(`${BASE}/`);
  check(r, { 'status 200': (x) => x.status === 200 });
}
