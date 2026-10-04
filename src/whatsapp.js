// Klien kecil untuk WhatsApp Cloud API (Graph API Meta).

function createWhatsAppClient({ token, phoneNumberId, apiVersion = 'v23.0', fetchImpl = fetch }) {
  const url = `https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`;

  async function send(payload) {
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', recipient_type: 'individual', ...payload }),
    });
    if (!res.ok) {
      throw new Error(`WhatsApp API ${res.status}: ${await res.text()}`);
    }
    return res.json();
  }

  return {
    sendText(to, body) {
      return send({ to, type: 'text', text: { body } });
    },

    // Maksimal 3 tombol, judul tombol maksimal 20 karakter.
    sendButtons(to, body, buttons) {
      return send({
        to,
        type: 'interactive',
        interactive: {
          type: 'button',
          body: { text: body },
          action: {
            buttons: buttons.map((b) => ({ type: 'reply', reply: { id: b.id, title: b.title } })),
          },
        },
      });
    },

    // Template pesan yang sudah disetujui Meta (wajib untuk pesan di luar jendela 24 jam).
    sendTemplate(to, name, languageCode, components = []) {
      return send({
        to,
        type: 'template',
        template: {
          name,
          language: { code: languageCode },
          ...(components.length ? { components } : {}),
        },
      });
    },

    // Maksimal 10 baris, judul baris maksimal 24 karakter.
    sendList(to, body, buttonText, rows) {
      return send({
        to,
        type: 'interactive',
        interactive: {
          type: 'list',
          body: { text: body },
          action: {
            button: buttonText,
            sections: [{ title: 'Pilihan', rows }],
          },
        },
      });
    },
  };
}

// Mengubah payload webhook Meta menjadi daftar pesan sederhana.
function parseIncoming(body) {
  const messages = [];
  for (const entry of body?.entry ?? []) {
    for (const change of entry.changes ?? []) {
      const value = change.value ?? {};
      const names = new Map((value.contacts ?? []).map((c) => [c.wa_id, c.profile?.name ?? '']));
      for (const m of value.messages ?? []) {
        const msg = { id: m.id, from: m.from, name: names.get(m.from) ?? '', text: '', replyId: '' };
        if (m.type === 'text') {
          msg.text = m.text?.body ?? '';
        } else if (m.type === 'interactive') {
          const reply = m.interactive?.button_reply ?? m.interactive?.list_reply;
          msg.replyId = reply?.id ?? '';
          msg.text = reply?.title ?? '';
        } else if (m.type === 'button') {
          msg.text = m.button?.text ?? '';
        }
        messages.push(msg);
      }
    }
  }
  return messages;
}

module.exports = { createWhatsAppClient, parseIncoming };
