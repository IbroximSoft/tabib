/* ============================================================
   TO'LOV CHEKI — 80 mm termal lenta
   Markazda hozir ishlatilayotgan chek qog'ozining ko'rinishi
   saqlangan: Bemor -> Palata -> To'lov -> Xodim/Sana.
   ============================================================ */
import { esc, pul2, kun, kunVaqt } from '../lib/chop'

/* Markaz nomi — o'zgarsa faqat shu yerni tahrirlash kifoya */
export const MARKAZ = {
  nomi: 'ASAL ARI SHIFO 777 OK',
  tavsif: 'Xususiy tabobat markazi'
}

const USUL = { naqd: 'Naqd', karta: 'Plastik karta', otkazma: 'Pul o‘tkazma' }

/* TERMAL PRINTER UCHUN.
   Termal kalla faqat QORA yoki OQ nuqta bosadi — kulrang yo'q.
   Shuning uchun:
     · ingichka (Courier, light) shrift emas — QALIN sans;
     · mayda o'lcham emas — 15px dan boshlanadi;
     · punktir chiziq emas — to'liq qora chiziq;
     · belgi-ikonka (☎) emas — oddiy harf.
   Aks holda nozik chiziqlar kulrangga aylanib, xira bosiladi. */
export const chekCss = `
@page { size: 80mm auto; margin: 4mm 4mm 8mm; }
* { box-sizing: border-box; }
body {
  margin: 0; width: 72mm;
  font: 700 15px/1.45 Arial, "Helvetica Neue", "Liberation Sans", "DejaVu Sans", sans-serif;
  color: #000; -webkit-font-smoothing: none;
  -webkit-print-color-adjust: exact; print-color-adjust: exact;
}
.mkz { text-align: center; font-size: 12px; line-height: 1.25; margin-bottom: 3px }
.nom { text-align: center; font-size: 17px; line-height: 1.2 }
.raqam { text-align: center; font-size: 18px; margin: 6px 0 2px }
.bosh { text-align: center; font-size: 16px; margin: 9px 0 4px }
.fish { text-align: center; font-size: 20px; line-height: 1.2;
        text-transform: uppercase; margin-bottom: 3px }
.mk { text-align: center; font-size: 14px }
.ch { border-top: 2px solid #000; margin: 7px 0 }
.chq { border-top: 2px solid #000; margin: 7px 0 }
.q { display: flex; justify-content: space-between; gap: 5px; margin: 3px 0;
     font-size: 15px }
.q span:first-child { flex: 0 1 auto }
.q span:last-child { flex: 1 1 auto; text-align: right; white-space: nowrap }
/* uzun matn (xodim ismi) chekdan chiqib ketmasin — koʻchsin */
.q.matn span:last-child { white-space: normal; overflow-wrap: anywhere }
.q.jami { font-size: 16px }
.oyoq { text-align: center; font-size: 13px; margin-top: 9px; line-height: 1.35 }
/* Pul qaytarish tilxati — chekdan darrov ajralib tursin */
.turi { text-align: center; font-size: 16px; letter-spacing: .04em;
        border: 2px solid #000; padding: 3px 0; margin: 5px 0 2px }
.imzo { margin-top: 11px; font-size: 14px }
.imzo .chiziq { border-bottom: 2px solid #000; height: 18px; margin-top: 14px }
.imzo .izoh { text-align: center; font-size: 12px; margin-top: 3px }
`

export function chekHtml(c) {
  const q = (a, b, klass = '') =>
    `<div class="q ${klass}"><span>${esc(a)}</span><span>${esc(b)}</span></div>`

  const yosh = c.yosh ? `${c.yosh} yosh` : ''
  const rol = c.roli && c.roli !== 'bemor'
    ? (c.roli === 'farzand' ? 'Farzand' : 'Qarovchi') : ''

  /* Manfiy summa — bu to'lov emas, QAYTARISH. Qog'ozi ham boshqacha:
     bemor imzo chekib pulni olganini tasdiqlaydi. */
  const qaytarish = Number(c.summa) < 0
  const summa = Math.abs(Number(c.summa) || 0)

  return `
<div class="mkz">${esc(MARKAZ.tavsif)}</div>
<div class="nom">${esc(MARKAZ.nomi)}</div>
<div class="raqam">${qaytarish ? 'Tilxat' : 'Chek'} № ${esc(c.chek_raqam || '')}</div>
${qaytarish ? '<div class="turi">PUL QAYTARILDI</div>' : ''}

<div class="ch"></div>
<div class="bosh">Bemor</div>
<div class="fish">${esc(c.fish || '')}</div>
${yosh ? `<div class="mk">${esc(yosh)}${rol ? ' · ' + esc(rol) : ''}</div>` : ''}
${c.telefon ? `<div class="mk">Tel: ${esc(c.telefon)}</div>` : ''}

<div class="ch"></div>
<div class="bosh">Palata</div>
${q(`${c.xona || '—'}-xona${c.koyka ? ', ' + c.koyka + '-koyka' : ''}`, '')}
${c.kunlik != null ? q('Bir kunlik', pul2(c.kunlik)) : ''}
${c.kurs_kun != null ? q('Kun', String(c.kurs_kun)) : ''}
${q('Jami', pul2(c.kurs_summa), 'jami')}

<div class="ch"></div>
<div class="bosh">${qaytarish ? 'Qaytarish' : 'To‘lov'}</div>
${q('Yotgan kun', String(c.yotgan_kun ?? ''))}
${q('Hisoblangan', pul2(c.umumiy))}
${qaytarish ? '' : q('Chegirma', pul2(0))}
${q(qaytarish ? 'Qaytarilgan summa' : 'Shu to‘lov', pul2(summa), 'jami')}
${q('Usuli', USUL[c.usuli] || c.usuli || '')}
${q('Jami to‘langan', pul2(c.tolangan))}
${q('Qarzdorlik', pul2(c.qolgan_qarz), 'jami')}

<div class="chq"></div>
${q('Kelgan', kun(c.kirish_sana))}
${q('Xodim', c.kassir || '—', 'matn')}
${q('Sana', kunVaqt(c.tolov_vaqti))}

${qaytarish ? `
<div class="imzo">
  Yuqoridagi summani to‘liq oldim:
  <div class="chiziq"></div>
  <div class="izoh">bemor (yoki uning vakili) imzosi</div>
</div>` : ''}

<div class="oyoq">
  ${qaytarish
    ? 'Tilxat ikki nusxada: biri bemorga, biri markazda qoladi.'
    : (Number(c.qolgan_qarz) > 0
        ? 'Qarzdorlik qoldi. Chiqishda to‘liq to‘lanadi.'
        : 'Qarzdorlik yo‘q.') + '<br>Chekni saqlab qo‘ying.'}
</div>`
}
