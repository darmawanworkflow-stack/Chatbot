function intEnv(env, name, fallback) {
  const raw = env[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) throw new Error(`${name} harus berupa angka >= 0`);
  return value;
}

function loadConfig(env = process.env) {
  const storage = (env.STORAGE || 'sheets').toLowerCase();
  const required = ['WHATSAPP_TOKEN', 'WHATSAPP_PHONE_NUMBER_ID', 'WHATSAPP_VERIFY_TOKEN'];
  if (storage === 'sheets') required.push('SPREADSHEET_ID');
  const missing = required.filter((name) => !env[name]);
  if (missing.length) throw new Error(`Variabel environment belum diisi: ${missing.join(', ')}`);

  let googleCredentials;
  if (env.GOOGLE_SERVICE_ACCOUNT_JSON) {
    googleCredentials = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON);
  }

  return {
    port: intEnv(env, 'PORT', 3000),
    whatsapp: {
      token: env.WHATSAPP_TOKEN,
      phoneNumberId: env.WHATSAPP_PHONE_NUMBER_ID,
      verifyToken: env.WHATSAPP_VERIFY_TOKEN,
      appSecret: env.WHATSAPP_APP_SECRET || '',
      apiVersion: env.GRAPH_API_VERSION || 'v23.0',
    },
    storage,
    sheets: {
      spreadsheetId: env.SPREADSHEET_ID,
      credentials: googleCredentials,
      keyFile: env.GOOGLE_APPLICATION_CREDENTIALS,
    },
    survey: {
      cafeName: env.CAFE_NAME || 'Cafe Kami',
      discountPercent: intEnv(env, 'DISCOUNT_PERCENT', 2),
      codePrefix: env.CODE_PREFIX ?? 'CAFE',
      codeValidDays: intEnv(env, 'CODE_VALID_DAYS', 7),
      cooldownDays: intEnv(env, 'SURVEY_COOLDOWN_DAYS', 30),
      adminNumbers: (env.ADMIN_NUMBERS || '')
        .split(',')
        .map((n) => n.replace(/\D/g, ''))
        .filter(Boolean),
      timeZone: env.TIMEZONE || 'Asia/Jakarta',
      promoLanguage: env.PROMO_TEMPLATE_LANGUAGE || 'id',
      broadcastDelayMs: intEnv(env, 'BROADCAST_DELAY_MS', 200),
    },
  };
}

module.exports = { loadConfig };
