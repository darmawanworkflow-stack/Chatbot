const crypto = require('node:crypto');
const express = require('express');
const { parseIncoming } = require('./whatsapp');
const { privacyPage } = require('./privacy');

function isValidSignature(appSecret, rawBody, header) {
  if (!header || !rawBody) return false;
  const expected = `sha256=${crypto.createHmac('sha256', appSecret).update(rawBody).digest('hex')}`;
  const a = Buffer.from(expected);
  const b = Buffer.from(header);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function createApp({ config, bot, wa, logger = console }) {
  const app = express();
  app.use(express.json({ verify: (req, _res, buf) => (req.rawBody = buf) }));

  const seenIds = new Set(); // Meta bisa mengirim ulang pesan yang sama
  const queues = new Map(); // pesan dari satu nomor diproses berurutan

  function enqueue(msg) {
    const previous = queues.get(msg.from) ?? Promise.resolve();
    const next = previous
      .then(() => bot.handleMessage(msg))
      .catch(async (err) => {
        logger.error(`Gagal memproses pesan dari ${msg.from}:`, err);
        await wa
          .sendText(msg.from, 'Maaf, sedang ada gangguan. Silakan kirim ulang pesan Anda sebentar lagi 🙏')
          .catch(() => {});
      });
    queues.set(msg.from, next);
    next.finally(() => {
      if (queues.get(msg.from) === next) queues.delete(msg.from);
    });
    return next;
  }

  app.get('/', (_req, res) => res.send('Chatbot survei aktif'));

  const privacyHtml = privacyPage({
    cafeName: config.survey?.cafeName || 'Kami',
    contact: config.survey?.privacyContact,
  });
  app.get('/privacy', (_req, res) => res.type('html').send(privacyHtml));

  // Verifikasi webhook saat didaftarkan di dashboard Meta.
  app.get('/webhook', (req, res) => {
    const { 'hub.mode': mode, 'hub.verify_token': token, 'hub.challenge': challenge } = req.query;
    if (mode === 'subscribe' && token === config.whatsapp.verifyToken) return res.status(200).send(challenge);
    return res.sendStatus(403);
  });

  app.post('/webhook', (req, res) => {
    const { appSecret } = config.whatsapp;
    if (appSecret && !isValidSignature(appSecret, req.rawBody, req.get('x-hub-signature-256'))) {
      return res.sendStatus(401);
    }
    res.sendStatus(200); // balas cepat agar Meta tidak mengirim ulang

    for (const msg of parseIncoming(req.body)) {
      if (seenIds.has(msg.id)) continue;
      seenIds.add(msg.id);
      if (seenIds.size > 5000) seenIds.delete(seenIds.values().next().value);
      enqueue(msg);
    }
  });

  return app;
}

module.exports = { createApp, isValidSignature };
