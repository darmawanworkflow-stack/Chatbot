const { google } = require('googleapis');
const { QUESTIONS } = require('../questions');

const RESPONSE_SHEET = 'Respon';
const CODE_SHEET = 'Kode Diskon';

const RESPONSE_HEADERS = ['Waktu', 'Nomor WA', 'Nama', ...QUESTIONS.map((q) => q.label), 'Kode Diskon', 'Timestamp (UTC)'];
const CODE_HEADERS = ['Kode', 'Nomor WA', 'Dibuat', 'Berlaku Sampai', 'Status', 'Dipakai Pada', 'Kedaluwarsa (UTC)'];

// Kolom huruf berdasarkan indeks (0 -> A). Cukup untuk < 26 kolom.
const col = (index) => String.fromCharCode(65 + index);

function createSheetsStorage({ spreadsheetId, credentials, keyFile, timeZone }) {
  const auth = new google.auth.GoogleAuth({
    credentials,
    keyFile: credentials ? undefined : keyFile,
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
  });
  const api = google.sheets({ version: 'v4', auth }).spreadsheets;

  const localTime = (date) => date.toLocaleString('sv-SE', { timeZone }); // "YYYY-MM-DD HH:MM:SS"
  const respLastCol = col(RESPONSE_HEADERS.length - 1);
  const codeLastCol = col(CODE_HEADERS.length - 1);

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
      const missing = [RESPONSE_SHEET, CODE_SHEET].filter((t) => !existing.has(t));
      if (missing.length) {
        await api.batchUpdate({
          spreadsheetId,
          requestBody: { requests: missing.map((title) => ({ addSheet: { properties: { title } } })) },
        });
      }
      for (const [sheet, headers] of [
        [RESPONSE_SHEET, RESPONSE_HEADERS],
        [CODE_SHEET, CODE_HEADERS],
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
  };
}

module.exports = { createSheetsStorage, RESPONSE_HEADERS, CODE_HEADERS };
