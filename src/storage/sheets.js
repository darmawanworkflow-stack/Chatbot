const { sheets: sheetsApi, auth: googleAuth } = require('@googleapis/sheets');
const { QUESTIONS } = require('../questions');

const RESPONSE_SHEET = 'Respon';
const CODE_SHEET = 'Kode Diskon';
const SUBSCRIBER_SHEET = 'Pelanggan Promo';

const RESPONSE_HEADERS = ['Waktu', 'Nomor WA', 'Nama', ...QUESTIONS.map((q) => q.label), 'Kode Diskon', 'Timestamp (UTC)'];
const CODE_HEADERS = ['Kode', 'Nomor WA', 'Dibuat', 'Berlaku Sampai', 'Status', 'Dipakai Pada', 'Kedaluwarsa (UTC)'];
// Status: aktif (mau promo), menolak (tidak mau saat ditanya), berhenti (membalas STOP)
const SUBSCRIBER_HEADERS = ['Nomor WA', 'Nama', 'Status', 'Diperbarui', 'Sumber'];

// Kolom huruf berdasarkan indeks (0 -> A). Cukup untuk < 26 kolom.
const col = (index) => String.fromCharCode(65 + index);

function createSheetsStorage({ spreadsheetId, credentials, keyFile, timeZone }) {
  const auth = new googleAuth.GoogleAuth({
    credentials,
    keyFile: credentials ? undefined : keyFile,
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
  });
  const api = sheetsApi({ version: 'v4', auth }).spreadsheets;

  const localTime = (date) => date.toLocaleString('sv-SE', { timeZone }); // "YYYY-MM-DD HH:MM:SS"
  const respLastCol = col(RESPONSE_HEADERS.length - 1);
  const codeLastCol = col(CODE_HEADERS.length - 1);
  const subLastCol = col(SUBSCRIBER_HEADERS.length - 1);

  async function readRows(range) {
    const res = await api.values.get({ spreadsheetId, range });
    return res.data.values ?? [];
  }

  async function append(sheet, row) {
    await api.values.append({
      spreadsheetId,
      range: `'${sheet}'!A1`,
      valueInputOption: 'RAW',
      insertDataOption: 'INSERT_ROWS',
      requestBody: { values: [row] },
    });
  }

  return {
    // Membuat tab dan baris judul jika belum ada.
    async init() {
      const meta = await api.get({ spreadsheetId, fields: 'sheets.properties.title' });
      const existing = new Set(meta.data.sheets.map((s) => s.properties.title));
      const missing = [RESPONSE_SHEET, CODE_SHEET, SUBSCRIBER_SHEET].filter((t) => !existing.has(t));
      if (missing.length) {
        await api.batchUpdate({
          spreadsheetId,
          requestBody: { requests: missing.map((title) => ({ addSheet: { properties: { title } } })) },
        });
      }
      for (const [sheet, headers] of [
        [RESPONSE_SHEET, RESPONSE_HEADERS],
        [CODE_SHEET, CODE_HEADERS],
        [SUBSCRIBER_SHEET, SUBSCRIBER_HEADERS],
      ]) {
        const rows = await readRows(`'${sheet}'!A1:${col(headers.length - 1)}1`);
        if (!rows.length) {
          await api.values.update({
            spreadsheetId,
            range: `'${sheet}'!A1`,
            valueInputOption: 'RAW',
            requestBody: { values: [headers] },
          });
        }
      }
    },

    async getLastSurveyAt(phone) {
      const rows = await readRows(`'${RESPONSE_SHEET}'!A2:${respLastCol}`);
      let last = null;
      for (const row of rows) {
        if (row[1] !== phone) continue;
        const at = new Date(row[RESPONSE_HEADERS.length - 1]);
        if (!Number.isNaN(at.getTime()) && (!last || at > last)) last = at;
      }
      return last;
    },

    async saveResponse({ phone, name, answers, code, createdAt }) {
      await append(RESPONSE_SHEET, [
        localTime(createdAt),
        phone,
        name,
        ...QUESTIONS.map((q) => answers[q.id] ?? ''),
        code,
        createdAt.toISOString(),
      ]);
    },

    async saveCode({ code, phone, createdAt, expiresAt }) {
      await append(CODE_SHEET, [
        code,
        phone,
        localTime(createdAt),
        localTime(expiresAt),
        'aktif',
        '',
        expiresAt.toISOString(),
      ]);
    },

    async findCode(code) {
      const rows = await readRows(`'${CODE_SHEET}'!A2:${codeLastCol}`);
      const index = rows.findIndex((row) => row[0] === code);
      if (index === -1) return null;
      const row = rows[index];
      return {
        code: row[0],
        phone: row[1],
        expiresAt: new Date(row[6]),
        status: row[4] || 'aktif',
        usedAt: row[5] || null,
        rowNumber: index + 2,
      };
    },

    async markCodeUsed(code, usedAt) {
      const record = await this.findCode(code);
      if (!record) return;
      await api.values.update({
        spreadsheetId,
        range: `'${CODE_SHEET}'!E${record.rowNumber}:F${record.rowNumber}`,
        valueInputOption: 'RAW',
        requestBody: { values: [['terpakai', localTime(usedAt)]] },
      });
    },

    async getSubscriber(phone) {
      const rows = await readRows(`'${SUBSCRIBER_SHEET}'!A2:${subLastCol}`);
      const index = rows.findIndex((row) => row[0] === phone);
      if (index === -1) return null;
      const [, name = '', status = '', updatedAt = '', source = ''] = rows[index];
      return { phone, name, status, updatedAt, source, rowNumber: index + 2 };
    },

    async setSubscriber({ phone, name, status, updatedAt, source }) {
      const existing = await this.getSubscriber(phone);
      const row = [phone, name || existing?.name || '', status, localTime(updatedAt), source];
      if (!existing) return append(SUBSCRIBER_SHEET, row);
      await api.values.update({
        spreadsheetId,
        range: `'${SUBSCRIBER_SHEET}'!A${existing.rowNumber}:${subLastCol}${existing.rowNumber}`,
        valueInputOption: 'RAW',
        requestBody: { values: [row] },
      });
    },

    async listSubscribers(status = 'aktif') {
      const rows = await readRows(`'${SUBSCRIBER_SHEET}'!A2:${subLastCol}`);
      return rows
        .filter((row) => row[0] && row[2] === status)
        .map(([phone, name = '']) => ({ phone, name, status }));
    },
  };
}

module.exports = { createSheetsStorage, RESPONSE_HEADERS, CODE_HEADERS, SUBSCRIBER_HEADERS };
