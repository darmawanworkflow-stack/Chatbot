const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createApp } = require('../src/server');
const { parseIncoming } = require('../src/whatsapp');

const config = { whatsapp: { verifyToken: 'verif', appSecret: 'secret' } };

function payload(messages) {
  return {
    object: 'whatsapp_business_account',
    entry: [{ changes: [{ value: { contacts: [{ wa_id: '628123', profile: { name: 'Sari' } }], messages } }] }],
  };
}

async function withServer(handler, fn) {
  const received = [];
  const bot = { handleMessage: async (m) => { received.push(m); if (handler) await handler(m); } };
  const wa = { sendText: async () => {} };
  const server = createApp({ config, bot, wa, logger: { error() {} } }).listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await fn(base, received);
  } finally {
    server.close();
  }
}

function sign(body) {
  return `sha256=${crypto.createHmac('sha256', 'secret').update(body).digest('hex')}`;
}

test('parseIncoming membaca teks, tombol, dan nama kontak', () => {
  const msgs = parseIncoming(payload([
    { id: 'a', from: '628123', type: 'text', text: { body: '/survei' } },
    { id: 'b', from: '628123', type: 'interactive', interactive: { type: 'list_reply', list_reply: { id: 'rasa:5', title: '⭐⭐⭐⭐⭐' } } },
  ]));
  assert.deepEqual(msgs[0], { id: 'a', from: '628123', name: 'Sari', text: '/survei', replyId: '' });
  assert.equal(msgs[1].replyId, 'rasa:5');
  assert.deepEqual(parseIncoming({ entry: [{ changes: [{ value: { statuses: [{}] } }] }] }), []);
});

test('verifikasi webhook GET', async () => {
  await withServer(null, async (base) => {
    let res = await fetch(`${base}/webhook?hub.mode=subscribe&hub.verify_token=verif&hub.challenge=123`);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), '123');
    res = await fetch(`${base}/webhook?hub.mode=subscribe&hub.verify_token=salah&hub.challenge=123`);
    assert.equal(res.status, 403);
  });
});

test('POST webhook menolak tanda tangan salah dan membuang pesan duplikat', async () => {
  await withServer(null, async (base, received) => {
    const body = JSON.stringify(payload([{ id: 'x1', from: '628123', type: 'text', text: { body: 'halo' } }]));
    const post = (signature) =>
      fetch(`${base}/webhook`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Hub-Signature-256': signature },
        body,
      });

    assert.equal((await post('sha256=salah')).status, 401);
    assert.equal((await post(sign(body))).status, 200);
    assert.equal((await post(sign(body))).status, 200);
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(received.length, 1);
    assert.equal(received[0].text, 'halo');
  });
});
