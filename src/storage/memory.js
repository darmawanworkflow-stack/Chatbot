// Penyimpanan di memori: untuk uji coba dan test. Data hilang saat server restart.
function createMemoryStorage() {
  const responses = [];
  const codes = new Map();

  return {
    responses,
    codes,
    async init() {},

    async getLastSurveyAt(phone) {
      let last = null;
      for (const r of responses) {
        if (r.phone === phone && (!last || r.createdAt > last)) last = r.createdAt;
      }
      return last;
    },

    async saveResponse(response) {
      responses.push({ ...response });
    },

    async saveCode(record) {
      codes.set(record.code, { ...record, status: 'aktif', usedAt: null });
    },

    async findCode(code) {
      const record = codes.get(code);
      return record ? { ...record } : null;
    },

    async markCodeUsed(code, usedAt) {
      const record = codes.get(code);
      if (record) Object.assign(record, { status: 'terpakai', usedAt });
    },
  };
}

module.exports = { createMemoryStorage };
