// Persetujuan promo (opt-in), berhenti (STOP), dan broadcast template oleh admin.

const PENDING_TTL_MS = 10 * 60 * 1000; // konfirmasi /kirim berlaku 10 menit
const STOP_WORDS = ['stop', 'berhenti', '/berhenti', 'stop promo', 'berhenti promo'];
const JOIN_WORDS = ['/langganan', 'langganan'];
const CONSENT_YES = 'promo:ya';
const CONSENT_NO = 'promo:tidak';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function createPromo({ wa, storage, config, now = () => new Date() }) {
  const pending = new Map(); // admin -> broadcast yang menunggu /kirim
  let activeBroadcast = null;

  const isStop = (command) => STOP_WORDS.includes(command);
  const isJoin = (command) => JOIN_WORDS.includes(command);

  async function setStatus(phone, name, status, source) {
    await storage.setSubscriber({ phone, name, status, updatedAt: now(), source });
  }

  // ---- Pelanggan ----

  // Ditanyakan sekali setelah survei, hanya ke nomor yang belum pernah ditanya.
  async function shouldAskConsent(phone) {
    return !(await storage.getSubscriber(phone));
  }

  function askConsent(phone) {
    return wa.sendButtons(
      phone,
      `Satu lagi (opsional) 😊\nMau menerima info promo & menu baru dari ${config.cafeName} lewat WhatsApp?\n\n` +
        'Kami kirim sesekali saja, dan Anda bisa berhenti kapan pun dengan membalas *STOP*.',
      [
        { id: CONSENT_YES, title: 'Ya, mau' },
        { id: CONSENT_NO, title: 'Tidak, terima kasih' },
      ],
    );
  }

  // Mengembalikan false jika pesan bukan jawaban persetujuan.
  async function handleConsentReply({ from, name, text, replyId }) {
    const answer = (text || '').trim().toLowerCase();
    let status = null;
    if (replyId === CONSENT_YES || (!replyId && ['ya', 'mau', 'ya, mau'].includes(answer))) status = 'aktif';
    if (replyId === CONSENT_NO || (!replyId && ['tidak', 'gak', 'nggak', 'no'].includes(answer))) status = 'menolak';
    if (!status) return false;

    await setStatus(from, name, status, 'survei');
    await wa.sendText(
      from,
      status === 'aktif'
        ? 'Siap! Anda akan menerima info promo dari kami 🎉\nBalas *STOP* kapan saja untuk berhenti.'
        : 'Baik, kami tidak akan mengirim promo. Terima kasih! 🙏',
    );
    return true;
  }

  async function unsubscribe({ from, name }) {
    const existing = await storage.getSubscriber(from);
    if (existing) await setStatus(from, name, 'berhenti', 'STOP');
    return wa.sendText(
      from,
      'Anda tidak akan menerima pesan promo lagi dari kami.\nKetik /langganan jika ingin menerima lagi.',
    );
  }

  async function subscribe({ from, name }) {
    await setStatus(from, name, 'aktif', 'langganan');
    return wa.sendText(from, 'Terima kasih! Anda akan menerima info promo dari kami 🎉\nBalas *STOP* untuk berhenti.');
  }

  // ---- Admin ----

  // Format: /promo nama_template [nama] [https://link-gambar.jpg]
  function parseBroadcastCommand(text) {
    const [, template = '', ...rest] = text.trim().split(/\s+/);
    if (!/^[a-z0-9_]+$/.test(template)) return null;
    let withName = false;
    let imageUrl = '';
    for (const arg of rest) {
      if (arg.toLowerCase() === 'nama') withName = true;
      else if (/^https:\/\/\S+$/i.test(arg)) imageUrl = arg;
      else return null;
    }
    return { template, withName, imageUrl };
  }

  function buildComponents({ withName, imageUrl }, name) {
    const components = [];
    if (imageUrl) components.push({ type: 'header', parameters: [{ type: 'image', image: { link: imageUrl } }] });
    if (withName) components.push({ type: 'body', parameters: [{ type: 'text', text: name || 'Kak' }] });
    return components;
  }

  const sendPromo = (phone, name, broadcast) =>
    wa.sendTemplate(phone, broadcast.template, config.promoLanguage, buildComponents(broadcast, name));

  const shortError = (err) => String(err?.message || err).slice(0, 300);

  const usage =
    'Format:\n/promo nama_template\n/promo nama_template nama\n/promo nama_template https://link-gambar.jpg\n\n' +
    'Tambahkan *nama* jika template memakai {{1}} untuk nama pelanggan, dan link gambar jika template ' +
    'memakai header gambar.';

  async function handleAdmin(from, text) {
    const command = text.trim().split(/\s+/)[0].toLowerCase();

    if (command === '/tespromo') {
      const broadcast = parseBroadcastCommand(text);
      if (!broadcast) return wa.sendText(from, usage.replaceAll('/promo', '/tespromo'));
      try {
        await sendPromo(from, 'Admin', broadcast);
        return wa.sendText(from, `✅ Template *${broadcast.template}* terkirim ke nomor Anda. Cek tampilannya.`);
      } catch (err) {
        return wa.sendText(from, `❌ Gagal mengirim template:\n${shortError(err)}`);
      }
    }

    if (command === '/promo') {
      const broadcast = parseBroadcastCommand(text);
      if (!broadcast) return wa.sendText(from, usage);
      const subscribers = await storage.listSubscribers('aktif');
      if (!subscribers.length) return wa.sendText(from, 'Belum ada pelanggan yang setuju menerima promo.');
      pending.set(from, { ...broadcast, createdAt: now() });
      return wa.sendText(
        from,
        `📣 Template *${broadcast.template}* akan dikirim ke *${subscribers.length} pelanggan*.\n\n` +
          `Pastikan sudah dicoba dengan /tespromo.\nBalas */kirim* untuk mengirim, atau */batal*.`,
      );
    }

    if (command === '/kirim') {
      const broadcast = pending.get(from);
      if (!broadcast || now() - broadcast.createdAt > PENDING_TTL_MS) {
        pending.delete(from);
        return wa.sendText(from, 'Tidak ada promo yang menunggu dikirim. Mulai dengan /promo nama_template.');
      }
      if (activeBroadcast) return wa.sendText(from, 'Masih ada promo yang sedang dikirim. Tunggu sampai selesai.');
      pending.delete(from);
      const subscribers = await storage.listSubscribers('aktif');
      await wa.sendText(from, `⏳ Mengirim ke ${subscribers.length} pelanggan...`);
      activeBroadcast = runBroadcast(from, broadcast, subscribers).finally(() => {
        activeBroadcast = null;
      });
      return undefined; // berjalan di latar belakang, laporan dikirim setelah selesai
    }

    return undefined;
  }

  async function runBroadcast(admin, broadcast, subscribers) {
    let sent = 0;
    const errors = [];
    for (const [i, sub] of subscribers.entries()) {
      if (i > 0 && config.broadcastDelayMs) await sleep(config.broadcastDelayMs);
      try {
        await sendPromo(sub.phone, sub.name, broadcast);
        sent += 1;
      } catch (err) {
        errors.push(shortError(err));
      }
    }
    await wa
      .sendText(
        admin,
        `✅ Promo *${broadcast.template}* selesai dikirim.\nBerhasil: ${sent}\nGagal: ${errors.length}` +
          (errors.length ? `\n\nContoh error:\n${errors[0]}` : ''),
      )
      .catch(() => {});
  }

  function cancelPending(admin) {
    return pending.delete(admin);
  }

  return {
    isStop,
    isJoin,
    shouldAskConsent,
    askConsent,
    handleConsentReply,
    unsubscribe,
    subscribe,
    handleAdmin,
    cancelPending,
    idle: () => activeBroadcast ?? Promise.resolve(),
  };
}

module.exports = { createPromo };
