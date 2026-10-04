const { QUESTIONS, RATING_OPTIONS } = require('./questions');
const { generateCode } = require('./codes');
const { createPromo } = require('./promo');

const DAY_MS = 24 * 60 * 60 * 1000;
const SESSION_TTL_MS = 30 * 60 * 1000; // survei dianggap batal jika 30 menit tidak dijawab
const SKIP_ID = 'skip';

function createSurveyBot({ wa, storage, config, now = () => new Date() }) {
  const sessions = new Map();
  const admins = new Set(config.adminNumbers);
  const promo = createPromo({ wa, storage, config, now });

  const formatDate = (date) =>
    new Date(date).toLocaleDateString('id-ID', {
      timeZone: config.timeZone,
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });

  function getSession(phone) {
    const session = sessions.get(phone);
    if (!session) return null;
    if (now() - session.updatedAt > SESSION_TTL_MS) {
      sessions.delete(phone);
      return null;
    }
    return session;
  }

  async function handleMessage(msg) {
    const text = (msg.text || '').trim();
    const command = text.toLowerCase();

    if (admins.has(msg.from)) {
      if (/^\/(cek|pakai)\b/.test(command)) return handleAdmin(msg.from, text);
      if (/^\/(promo|tespromo|kirim)\b/.test(command)) return promo.handleAdmin(msg.from, text);
      if (command === '/batal' && promo.cancelPending(msg.from)) {
        return wa.sendText(msg.from, 'Pengiriman promo dibatalkan.');
      }
    }
    if (promo.isStop(command)) {
      sessions.delete(msg.from);
      return promo.unsubscribe(msg);
    }
    if (promo.isJoin(command)) return promo.subscribe(msg);
    if (command === '/survei' || command === 'survei') {
      return startSurvey(msg);
    }
    if (command === '/batal') {
      const hadSession = sessions.delete(msg.from);
      return wa.sendText(
        msg.from,
        hadSession
          ? 'Survei dibatalkan. Ketik /survei kapan saja untuk mulai lagi.'
          : 'Tidak ada survei yang sedang berjalan. Ketik /survei untuk mulai.',
      );
    }

    const session = getSession(msg.from);
    if (session?.stage === 'consent') {
      sessions.delete(msg.from);
      if (await promo.handleConsentReply(msg)) return undefined;
    } else if (session) {
      return handleAnswer(session, msg);
    }

    return wa.sendText(
      msg.from,
      `Halo! Terima kasih sudah menghubungi ${config.cafeName} 😊\n\n` +
        `Ketik */survei* untuk mengisi survei kepuasan singkat (${QUESTIONS.length} pertanyaan, ±1 menit) ` +
        `dan dapatkan *diskon ${config.discountPercent}%* untuk kunjungan berikutnya.`,
    );
  }

  async function startSurvey({ from, name }) {
    if (config.cooldownDays > 0) {
      const last = await storage.getLastSurveyAt(from);
      if (last && now() - last < config.cooldownDays * DAY_MS) {
        const nextAllowed = new Date(last.getTime() + config.cooldownDays * DAY_MS);
        return wa.sendText(
          from,
          `Terima kasih, Anda sudah mengisi survei pada ${formatDate(last)} 🙏\n` +
            `Survei berikutnya bisa diisi mulai ${formatDate(nextAllowed)}.`,
        );
      }
    }

    const session = { from, name: name || '', step: 0, answers: {}, updatedAt: now() };
    sessions.set(from, session);
    await wa.sendText(
      from,
      `Terima kasih sudah mau membantu ${config.cafeName}! 🙌\n\n` +
        `Ada ${QUESTIONS.length} pertanyaan singkat. Setelah selesai, Anda akan menerima ` +
        `*kode diskon ${config.discountPercent}%*.\n\nKetik /batal untuk membatalkan.`,
    );
    return askQuestion(session);
  }

  function askQuestion(session, hint = '') {
    const q = QUESTIONS[session.step];
    const header = `${hint ? `${hint}\n\n` : ''}*Pertanyaan ${session.step + 1}/${QUESTIONS.length}*\n${q.text}`;

    if (q.type === 'rating') {
      const rows = RATING_OPTIONS.map((o) => ({
        id: `${q.id}:${o.value}`,
        title: o.title,
        description: o.description,
      }));
      return wa.sendList(session.from, `${header}\n\nTekan *Pilih nilai* di bawah.`, 'Pilih nilai', rows);
    }
    if (q.type === 'nps') {
      return wa.sendText(
        session.from,
        `${header}\n\nBalas dengan angka *0* (tidak mungkin) sampai *10* (sangat mungkin).`,
      );
    }
    return wa.sendButtons(session.from, `${header}\n\nKetik jawaban Anda, atau tekan *Lewati*.`, [
      { id: `${q.id}:${SKIP_ID}`, title: 'Lewati' },
    ]);
  }

  // Mengembalikan { ok: true, value } atau { ok: false, hint }.
  function parseAnswer(q, { text, replyId }) {
    const trimmed = (text || '').trim();

    if (q.type === 'rating') {
      // Tombol dari pertanyaan lain (pesan lama) tidak dihitung.
      if (replyId) {
        const [qid, value] = replyId.split(':');
        if (qid === q.id && /^[1-5]$/.test(value)) return { ok: true, value: Number(value) };
      } else if (/^[1-5]$/.test(trimmed)) {
        return { ok: true, value: Number(trimmed) };
      }
      return { ok: false, hint: 'Mohon pilih nilai dari daftar, atau balas angka 1 sampai 5.' };
    }

    if (q.type === 'nps') {
      if (!replyId && /^(10|[0-9])$/.test(trimmed)) return { ok: true, value: Number(trimmed) };
      return { ok: false, hint: 'Mohon balas dengan satu angka dari 0 sampai 10.' };
    }

    if (replyId) {
      if (replyId === `${q.id}:${SKIP_ID}`) return { ok: true, value: '' };
      return { ok: false, hint: 'Mohon ketik jawaban Anda, atau tekan Lewati.' };
    }
    if (['-', 'lewati', 'skip', 'tidak ada'].includes(trimmed.toLowerCase())) return { ok: true, value: '' };
    if (trimmed) return { ok: true, value: trimmed.slice(0, 1000) };
    return { ok: false, hint: 'Mohon ketik jawaban Anda, atau tekan Lewati.' };
  }

  async function handleAnswer(session, msg) {
    const q = QUESTIONS[session.step];
    const result = parseAnswer(q, msg);
    session.updatedAt = now();
    if (!result.ok) return askQuestion(session, result.hint);

    session.answers[q.id] = result.value;
    if (session.step < QUESTIONS.length - 1) {
      session.step += 1;
      return askQuestion(session);
    }
    return finishSurvey(session);
  }

  async function newUniqueCode() {
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = generateCode(config.codePrefix);
      if (!(await storage.findCode(code))) return code;
    }
    throw new Error('Gagal membuat kode diskon unik');
  }

  // Jika penyimpanan gagal, sesi tetap di pertanyaan terakhir sehingga pelanggan bisa mengirim ulang.
  async function finishSurvey(session) {
    const createdAt = now();
    const expiresAt = new Date(createdAt.getTime() + config.codeValidDays * DAY_MS);
    const code = await newUniqueCode();

    await storage.saveCode({ code, phone: session.from, createdAt, expiresAt });
    await storage.saveResponse({
      phone: session.from,
      name: session.name,
      answers: session.answers,
      code,
      createdAt,
    });
    sessions.delete(session.from);

    await wa.sendText(
      session.from,
      `Terima kasih atas masukan Anda! 🙏☕\n\n` +
        `Kode diskon ${config.discountPercent}% Anda:\n*${code}*\n\n` +
        `Tunjukkan pesan ini ke kasir saat membayar.\n` +
        `Berlaku sampai ${formatDate(expiresAt)}, untuk 1x transaksi.`,
    );

    // Pertanyaan promo diajukan setelah kode diberikan, agar jelas diskon tidak bergantung pada jawabannya.
    if (await promo.shouldAskConsent(session.from)) {
      sessions.set(session.from, { ...session, stage: 'consent', updatedAt: now() });
      await promo.askConsent(session.from);
    }
  }

  async function handleAdmin(from, text) {
    const [rawCommand, rawCode] = text.split(/\s+/);
    const command = rawCommand.toLowerCase();
    const code = (rawCode || '').toUpperCase();
    if (!code) {
      return wa.sendText(from, `Format: ${command} KODE\nContoh: ${command} ${config.codePrefix || 'KODE'}-AB12CD`);
    }

    const record = await storage.findCode(code);
    if (!record) return wa.sendText(from, `❌ Kode ${code} tidak ditemukan.`);

    const masked = record.phone ? `${record.phone.slice(0, 4)}****${record.phone.slice(-3)}` : '-';
    const usedAtText = record.usedAt instanceof Date ? formatDate(record.usedAt) : record.usedAt;
    let problem = '';
    if (record.status === 'terpakai') problem = `sudah dipakai (${usedAtText})`;
    else if (record.expiresAt < now()) problem = `sudah kedaluwarsa sejak ${formatDate(record.expiresAt)}`;

    if (problem) return wa.sendText(from, `❌ Kode ${code} ${problem}.\nPelanggan: ${masked}`);

    if (command === '/cek') {
      return wa.sendText(
        from,
        `✅ Kode ${code} VALID (diskon ${config.discountPercent}%).\n` +
          `Pelanggan: ${masked}\nBerlaku sampai ${formatDate(record.expiresAt)}.\n\n` +
          `Kirim /pakai ${code} untuk menandai sudah dipakai.`,
      );
    }

    await storage.markCodeUsed(code, now());
    return wa.sendText(
      from,
      `✅ Kode ${code} berhasil dipakai. Berikan diskon ${config.discountPercent}% ke pelanggan.\n` +
        `Kode ini sekarang tidak bisa dipakai lagi.`,
    );
  }

  return { handleMessage, sessions, promoIdle: () => promo.idle() };
}

module.exports = { createSurveyBot };
