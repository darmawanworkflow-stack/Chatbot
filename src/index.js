const { loadConfig } = require('./config');
const { createWhatsAppClient } = require('./whatsapp');
const { createSurveyBot } = require('./survey');
const { createApp } = require('./server');

async function main() {
  const config = loadConfig();

  let storage;
  if (config.storage === 'memory') {
    const { createMemoryStorage } = require('./storage/memory');
    storage = createMemoryStorage();
    console.warn('STORAGE=memory: data survei TIDAK disimpan permanen.');
  } else {
    const { createSheetsStorage } = require('./storage/sheets');
    storage = createSheetsStorage({ ...config.sheets, timeZone: config.survey.timeZone });
  }
  await storage.init();

  const wa = createWhatsAppClient(config.whatsapp);
  const bot = createSurveyBot({ wa, storage, config: config.survey });
  const app = createApp({ config, bot, wa });

  if (!config.whatsapp.appSecret) {
    console.warn('WHATSAPP_APP_SECRET kosong: tanda tangan webhook tidak diperiksa.');
  }
  app.listen(config.port, config.host, () =>
    console.log(`Chatbot survei berjalan di ${config.host}:${config.port}`),
  );
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
