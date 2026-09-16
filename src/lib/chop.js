/* ============================================================
   CHOP ETISH
   Sahifani buzmasdan printerga yuborish uchun yashirin ramka
   (iframe) ochamiz. Shunda karta A4, chek esa 80 mm lentaga
   chiqadi — ikkalasi bir-biriga xalaqit bermaydi.
   ============================================================ */

/* Bemor ismi ichida < yoki & bo'lsa sahifa buzilmasin */
export const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))

export function chopEt({ html, css, sarlavha = 'Chop etish', keyin }) {
  const eski = document.getElementById('chop-ramka')
  if (eski) eski.remove()

  const f = document.createElement('iframe')
  f.id = 'chop-ramka'
  f.setAttribute('aria-hidden', 'true')
  f.setAttribute('tabindex', '-1')
  /* Ekrandan tashqariga chiqaramiz. display:none qilib bo'lmaydi —
     ba'zi brauzerlar ko'rinmaydigan ramkani chop etmaydi. */
  f.style.cssText =
    /* Yotiq A4 (297mm) ham sig'sin — aks holda karta qisilib qoladi */
    'position:fixed;left:-10000px;top:0;width:297mm;height:297mm;border:0;'

  document.body.appendChild(f)

  const d = f.contentWindow.document
  d.open()
  d.write(
    '<!doctype html><html lang="uz"><head><meta charset="utf-8">' +
    '<title>' + esc(sarlavha) + '</title><style>' + css + '</style>' +
    '</head><body>' + html + '</body></html>'
  )
  d.close()

  let tugadi = false
  const tozala = () => {
    if (tugadi) return
    tugadi = true
    setTimeout(() => { f.remove(); if (keyin) keyin() }, 800)
  }

  const bosh = () => {
    try {
      f.contentWindow.focus()
      f.contentWindow.onafterprint = tozala
      f.contentWindow.print()
    } catch (e) {
      /* chop oynasi ochilmasa ham ramka qolib ketmasin */
    }
    setTimeout(tozala, 4000)
  }

  if (d.readyState === 'complete') setTimeout(bosh, 60)
  else f.onload = () => setTimeout(bosh, 60)
}

/* --- formatlash --- */

/* 2 000 000,00 — chek qog'ozidagi ko'rinish */
export const pul2 = (n) => {
  const v = Number(n) || 0
  return v.toLocaleString('ru-RU', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    .replace(/ /g, ' ')
}

/* 2 000 000 */
export const pul0 = (n) =>
  (Number(n) || 0).toLocaleString('ru-RU').replace(/ /g, ' ')

export const kun = (s) => {
  if (!s) return ''
  const d = new Date(s)
  if (isNaN(d)) return String(s)
  return d.toLocaleDateString('ru-RU')
}

export const kunVaqt = (s) => {
  if (!s) return ''
  const d = new Date(s)
  if (isNaN(d)) return String(s)
  return d.toLocaleDateString('ru-RU') + ' ' +
    d.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' })
}
