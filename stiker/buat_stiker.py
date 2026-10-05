# Membuat stiker QR survei (PNG + PDF 10x14 cm, 300 dpi).
# Pakai: pip install qrcode pillow && cd stiker && python3 buat_stiker.py
# Ganti URL di bawah jika nomor bot berubah.
import qrcode
from qrcode.constants import ERROR_CORRECT_Q
from PIL import Image, ImageDraw, ImageFont

URL = "https://wa.me/6285353418399?text=%2Fsurvei"
DPI = 300
W, H = 1181, 1654  # 10 x 14 cm @300dpi

COFFEE = (62, 39, 35)
CREAM = (248, 241, 231)
CARAMEL = (200, 135, 58)
WHITE = (255, 255, 255)
MUTED = (110, 90, 80)

F = "/usr/share/fonts/truetype/dejavu/"
def font(name, size): return ImageFont.truetype(F + name, size)
bold = lambda s: font("DejaVuSans-Bold.ttf", s)
reg = lambda s: font("DejaVuSans.ttf", s)
serif = lambda s: font("DejaVuSerif-Bold.ttf", s)

img = Image.new("RGB", (W, H), CREAM)
d = ImageDraw.Draw(img)

def center(y, text, f, fill):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill)

# Header band
d.rectangle([0, 0, W, 210], fill=COFFEE)
# simple coffee cup icon
cx, cy = W // 2, 70
d.rounded_rectangle([cx - 38, cy - 22, cx + 30, cy + 30], radius=12, fill=CARAMEL)
d.arc([cx + 14, cy - 12, cx + 52, cy + 22], start=270, end=90, fill=CARAMEL, width=9)
for dx in (-22, -4, 14):
    d.line([(cx + dx, cy - 58), (cx + dx + 6, cy - 46), (cx + dx, cy - 34)], fill=CREAM, width=5, joint="curve")
center(118, "CAFE WEDANA", serif(64), CREAM)

# Headline
center(255, "Isi Survei,", bold(84), COFFEE)
line = "Dapat Diskon "
f = bold(84)
w1 = d.textlength(line, font=f); w2 = d.textlength("2%!", font=f)
x = (W - (w1 + w2)) / 2
d.text((x, 355), line, font=f, fill=COFFEE)
d.text((x + w1, 355), "2%!", font=f, fill=CARAMEL)
center(470, "Bantu kami jadi lebih baik, cuma 1 menit", reg(38), MUTED)

# QR card
qr = qrcode.QRCode(error_correction=ERROR_CORRECT_Q, box_size=20, border=2)
qr.add_data(URL); qr.make(fit=True)
q = qr.make_image(fill_color=COFFEE, back_color=WHITE).convert("RGB")
QS = 560
q = q.resize((QS, QS), Image.NEAREST)
card = 640
cx0 = (W - card) // 2; cy0 = 545
d.rounded_rectangle([cx0 - 8, cy0 - 8, cx0 + card + 8, cy0 + card + 8], radius=44, fill=CARAMEL)
d.rounded_rectangle([cx0, cy0, cx0 + card, cy0 + card], radius=38, fill=WHITE)
img.paste(q, (cx0 + (card - QS) // 2, cy0 + (card - QS) // 2))
center(cy0 + card + 26, "Scan pakai kamera HP", bold(40), COFFEE)

# Steps
steps = [("1", "Scan", "QR"), ("2", "Tekan", "Kirim"), ("3", "Jawab 7", "pertanyaan"), ("4", "Tunjukkan", "kode ke kasir")]
top = 1335
colw = W / 4
for i, (n, a, b) in enumerate(steps):
    mx = colw * i + colw / 2
    r = 38
    d.ellipse([mx - r, top - r, mx + r, top + r], fill=CARAMEL)
    nw = d.textlength(n, font=bold(46))
    d.text((mx - nw / 2, top - 29), n, font=bold(46), fill=WHITE)
    for j, t in enumerate((a, b)):
        tw = d.textlength(t, font=reg(30))
        d.text((mx - tw / 2, top + 52 + j * 36), t, font=reg(30), fill=COFFEE)

# Footer
d.rectangle([0, H - 150, W, H], fill=COFFEE)
center(H - 128, "Atau chat WhatsApp 0853-5341-8399, ketik /survei", bold(32), CREAM)
center(H - 72, "Kode berlaku 7 hari, 1x transaksi. 1 survei per nomor tiap 30 hari.", reg(25), (220, 200, 185))

img.save("stiker-survei-qr.png", dpi=(DPI, DPI))
img.save("stiker-survei-qr.pdf", "PDF", resolution=DPI)
q.save("qr-saja.png", dpi=(DPI, DPI))
print("ok")
