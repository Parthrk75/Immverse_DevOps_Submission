// Constant load used while DEPLOYING (zero-downtime proof) and during the bad-release demo.
import http from 'k6/http';
import { check } from 'k6';
const S = parseFloat(__ENV.SCALE || '1');
export const options = {
  scenarios: { steady: { executor: 'constant-arrival-rate', rate: Math.ceil(150 * S), timeUnit: '1s',
    duration: __ENV.DURATION || '15m', preAllocatedVUs: 50, maxVUs: 500 } },
  thresholds: { http_req_failed: ['rate<0.001'], http_req_duration: ['p(95)<400'] },
};
export default function () {
  const r = http.get(`${__ENV.BASE || 'http://app.localtest.me:8080'}/`);
  check(r, { ok: (x) => x.status === 200 });
}
