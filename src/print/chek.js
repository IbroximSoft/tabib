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

export const chekCss = `
@page { size: 80mm auto; margin: 3mm 3mm 6mm; }
* { box-sizing: border-box; }
body {
  margin: 0; width: 74mm;
  font: 12px/1.35 "Courier New", "DejaVu Sans Mono", monospace;
  color: #000; -webkit-font-smoothing: none;
}
.mkz { text-align: center; font-size: 10px; line-height: 1.2; margin-bottom: 4px }
.nom { text-align: center; font-size: 13px; font-weight: 700; letter-spacing: .02em }
.raqam { text-align: center; font-size: 14px; font-weight: 700; margin: 5px 0 2px }
.bosh { text-align: center; font-weight: 700; margin: 7px 0 3px }
.fish { text-align: center; font-size: 14px; font-weight: 700; line-height: 1.25;
        text-transform: uppercase; margin-bottom: 2px }
.mk { text-align: center; font-size: 11px }
.ch { border-top: 1px dashed #000; margin: 6px 0 }
.chq { border-top: 1px solid #000; margin: 6px 0 }
.q { display: flex; justify-content: space-between; gap: 6px; margin: 2px 0 }
.q span:last-child { text-align: right; white-space: nowrap }
.q.jami { font-weight: 700; font-size: 13px }
.oyoq { text-align: center; font-size: 10px; margin-top: 8px; line-height: 1.4 }
/* Pul qaytarish tilxati — chekdan darrov ajralib tursin */
.turi { text-align: center; font-size: 12px; font-weight: 700; letter-spacing: .04em;
        border: 1px solid #000; padding: 2px 0; margin: 4px 0 2px }
.imzo { margin-top: 10px; font-size: 11px }
.imzo .chiziq { border-bottom: 1px solid #000; height: 16px; margin-top: 12px }
.imzo .izoh { text-align: center; font-size: 9px; margin-top: 2px }
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
${c.telefon ? `<div class="mk">☎ ${esc(c.telefon)}</div>` : ''}

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
${q('Xodim', c.kassir || '—')}
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
