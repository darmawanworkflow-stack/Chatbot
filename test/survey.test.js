const test = require('node:test');
const assert = require('node:assert/strict');
const { createSurveyBot } = require('../src/survey');
const { createMemoryStorage } = require('../src/storage/memory');
const { QUESTIONS } = require('../src/questions');

const CUSTOMER = '6281111111111';
const ADMIN = '6289999999999';

function setup({ start = new Date('2026-10-04T03:00:00Z'), cooldownDays = 30 } = {}) {
  const sent = [];
  const wa = {
    async sendText(to, body) { sent.push({ to, kind: 'text', body }); },
    async sendButtons(to, body, buttons) { sent.push({ to, kind: 'buttons', body, buttons }); },
    async sendList(to, body, buttonText, rows) { sent.push({ to, kind: 'list', body, rows }); },
  };
  const clock = { now: start };
  const storage = createMemoryStorage();
  const bot = createSurveyBot({
    wa,
    storage,
    now: () => clock.now,
    config: {
      cafeName: 'Cafe Uji',
      discountPercent: 2,
      codePrefix: 'CAFE',
      codeValidDays: 7,
      cooldownDays,
      adminNumbers: [ADMIN],
      timeZone: 'Asia/Jakarta',
    },
  });
  const say = (text, from = CUSTOMER) => bot.handleMessage({ from, name: 'Budi', text });
  const tap = (replyId) => bot.handleMessage({ from: CUSTOMER, name: 'Budi', text: '', replyId });
  return { bot, storage, sent, clock, say, tap, last: () => sent[sent.length - 1] };
}

async function completeSurvey(t) {
  await t.say('/survei');
  await t.tap('rasa:5');
  await t.tap('pelayanan:4');
  await t.say('3'); // angka diketik juga diterima
  await t.tap('kebersihan:5');
  await t.tap('harga:4');
  await t.say('9');
  await t.say('Tambah menu non-kopi');
  return t.last().body.match(/CAFE-[A-Z0-9]{6}/)[0];
}

test('alur survei lengkap menyimpan jawaban dan memberi kode diskon', async () => {
  const t = setup();
  const code = await completeSurvey(t);

  assert.equal(t.storage.responses.length, 1);
  assert.deepEqual(t.storage.responses[0].answers, {
    rasa: 5, pelayanan: 4, kecepatan: 3, kebersihan: 5, harga: 4, nps: 9, saran: 'Tambah menu non-kopi',
  });
  assert.equal(t.storage.responses[0].code, code);
  assert.equal(t.storage.codes.get(code).status, 'aktif');
  assert.match(t.last().body, /diskon 2%/);
  assert.equal(t.bot.sessions.size, 0);
});

test('pertanyaan rating dikirim sebagai daftar pilihan 1-5', async () => {
  const t = setup();
  await t.say('/SURVEI');
  assert.equal(t.last().kind, 'list');
  assert.match(t.last().body, new RegExp(`Pertanyaan 1/${QUESTIONS.length}`));
  assert.deepEqual(t.last().rows.map((r) => r.id), ['rasa:5', 'rasa:4', 'rasa:3', 'rasa:2', 'rasa:1']);
});

test('jawaban tidak valid dan tombol lama tidak memajukan survei', async () => {
  const t = setup();
  await t.say('/survei');
  await t.say('enak sekali');
  assert.match(t.last().body, /Pertanyaan 1\//);
  await t.tap('rasa:5');
  await t.tap('rasa:3'); // tombol dari pertanyaan 1 ditekan lagi
  assert.match(t.last().body, /Pertanyaan 2\//);
  assert.match(t.last().body, /Mohon pilih/);
});

test('NPS menerima 0-10 dan saran bisa dilewati', async () => {
  const t = setup();
  await t.say('/survei');
  for (const id of ['rasa', 'pelayanan', 'kecepatan', 'kebersihan', 'harga']) await t.tap(`${id}:4`);
  await t.say('11');
  assert.match(t.last().body, /0 sampai 10/);
  await t.say('10');
  assert.equal(t.last().kind, 'buttons');
  await t.tap('saran:skip');
  assert.equal(t.storage.responses[0].answers.nps, 10);
  assert.equal(t.storage.responses[0].answers.saran, '');
});

test('satu nomor hanya bisa mengisi sekali dalam masa cooldown', async () => {
  const t = setup();
  await completeSurvey(t);
  t.clock.now = new Date('2026-10-20T03:00:00Z');
  await t.say('/survei');
  assert.match(t.last().body, /sudah mengisi survei/);
  assert.equal(t.bot.sessions.size, 0);

  t.clock.now = new Date('2026-11-04T03:00:00Z');
  await t.say('/survei');
  assert.equal(t.last().kind, 'list');
});

test('/batal menghentikan survei', async () => {
  const t = setup();
  await t.say('/survei');
  await t.say('/batal');
  assert.match(t.last().body, /dibatalkan/);
  await t.say('5');
  assert.match(t.last().body, /Ketik \*\/survei\*/);
});

test('sesi kedaluwarsa setelah 30 menit tanpa jawaban', async () => {
  const t = setup();
  await t.say('/survei');
  t.clock.now = new Date(t.clock.now.getTime() + 31 * 60 * 1000);
  await t.say('5');
  assert.match(t.last().body, /Ketik \*\/survei\*/);
});

test('kasir bisa cek dan memakai kode sekali saja', async () => {
  const t = setup();
  const code = await completeSurvey(t);

  await t.say(`/cek ${code.toLowerCase()}`, ADMIN);
  assert.match(t.last().body, /VALID/);
  assert.match(t.last().body, /6281\*\*\*\*111/);

  await t.say(`/pakai ${code}`, ADMIN);
  assert.match(t.last().body, /berhasil dipakai/);
  assert.equal(t.storage.codes.get(code).status, 'terpakai');

  await t.say(`/pakai ${code}`, ADMIN);
  assert.match(t.last().body, /sudah dipakai/);
});

test('kode kedaluwarsa ditolak, dan pelanggan biasa tidak bisa /pakai', async () => {
  const t = setup();
  const code = await completeSurvey(t);

  await t.say(`/pakai ${code}`);
  assert.doesNotMatch(t.last().body, /berhasil/);
  assert.equal(t.storage.codes.get(code).status, 'aktif');

  t.clock.now = new Date('2026-10-12T03:00:00Z');
  await t.say(`/cek ${code}`, ADMIN);
  assert.match(t.last().body, /kedaluwarsa/);
  await t.say('/cek CAFE-ZZZZZZ', ADMIN);
  assert.match(t.last().body, /tidak ditemukan/);
});
