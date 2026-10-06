// Local test proxy: forwards to StackCP and strips headers that block iframes.
// Usage: node tools/stackcp_proxy.js   (then the Flutter iframe points at http://localhost:8787/)
// TEST ONLY — not hardened for production.
const http = require('http');
const https = require('https');

const TARGET = process.env.TARGET_HOST || 'stackcp.com';
const PORT = Number(process.env.PORT || 8787);
// Public URL of this proxy, e.g. https://cp.yourdomain.com (no trailing slash)
const ORIGIN = process.env.PUBLIC_ORIGIN || `http://localhost:${PORT}`;
// Sites allowed to iframe the proxy, e.g. https://biznest-delta.vercel.app
const FRAME_ANCESTORS = process.env.FRAME_ANCESTORS || '*';

const rewriteText = (s) =>
  s.replace(new RegExp(`https?:\\/\\/(www\\.)?${TARGET.replace(/\./g, '\\.')}`, 'g'), ORIGIN)
   .replace(new RegExp(`https?:\\\\/\\\\/(www\\.)?${TARGET.replace(/\./g, '\\.')}`, 'g'), ORIGIN.replace('//', '\\/\\/'));

http.createServer((req, res) => {
  const headers = { ...req.headers, host: TARGET, 'accept-encoding': 'identity' };
  if (headers.origin) headers.origin = `https://${TARGET}`;
  if (headers.referer) headers.referer = headers.referer.replace(ORIGIN, `https://${TARGET}`);

  const up = https.request({ host: TARGET, path: req.url, method: req.method, headers }, (r) => {
    const h = { ...r.headers };
    delete h['x-frame-options'];
    delete h['content-security-policy'];
    delete h['content-security-policy-report-only'];
    delete h['content-length'];
    h['content-security-policy'] = `frame-ancestors ${FRAME_ANCESTORS}`;
    if (h.location) h.location = rewriteText(h.location);
    if (h['set-cookie']) {
      h['set-cookie'] = h['set-cookie'].map((c) =>
        c.replace(/;\s*Domain=[^;]*/i, '').replace(/;\s*SameSite=[^;]*/i, '; SameSite=None'));
    }
    const type = String(h['content-type'] || '');
    if (/text\/|json|javascript|xml/.test(type)) {
      const chunks = [];
      r.on('data', (d) => chunks.push(d));
      r.on('end', () => {
        res.writeHead(r.statusCode, h);
        res.end(rewriteText(Buffer.concat(chunks).toString('utf8')));
      });
    } else {
      res.writeHead(r.statusCode, h);
      r.pipe(res);
    }
  });
  up.on('error', (e) => { res.writeHead(502); res.end(String(e)); });
  req.pipe(up);
}).listen(PORT, () => console.log(`StackCP proxy on ${ORIGIN} -> https://${TARGET}`));
