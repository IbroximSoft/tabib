/* ============================================================
   БЕМОР КАРТАСИ — markazda ishlatilayotgan qogʻoz varaqaning
   aynan oʻzi. Matnlar kirill alifbosida, qogʻozdagidek.

   BITTA A4 VARAQ, YOTIQ (landshaft), IKKI TOMONLAMA.
   Varaq oʻrtasidan buklanadi — 4 ta A5 bet chiqadi:

     TASHQI varaq:  [ 4-bet: yakun + TILXAT ] | [ 1-bet: muqova ]
     ICHKI  varaq:  [ 2-bet: I–II kurs      ] | [ 3-bet: III–IV kurs ]

   Buklanganda betlar 1 → 2 → 3 → 4 tartibida keladi.
   Shuning uchun tashqi varaqda 4-bet CHAPDA, muqova OʻNGDA turadi —
   qogʻozdagi karta ham xuddi shunday bosilgan.

   CHOP ETISH
     kartaHtml(y, 'tash') → tashqi varaq (4- va 1-bet)
     kartaHtml(y, 'ich')  → ichki varaq  (2- va 3-bet)
     kartaHtml(y)         → ikkalasi ketma-ket
     Printerda ikki tomonlama rejim boʻlmasa: avval tashqi varaqni
     chiqarib, qogʻozni agʻdarib, ichki varaqni chiqariladi.

   TIZIMDAN TOʻLDIRILADI
     familiya, ism, telefon, xona raqami, kelgan sanasi, tashxis,
     I-kurs boshlanish sanasi (= kelgan sanasi).
   QOʻLDA YOZILADI (bazada bunday maydon yoʻq)
     otasining ismi, manzil, tugʻilgan sanasi (т.й), № , imzolar.
   ============================================================ */
import { esc, kun } from '../lib/chop'

/* Tilxat matnidagi tabib ismi */
export const TABIB = 'Abdurahimov Muhiddin Abduvohobovich'
export const TABIB_KIR = 'Абдурахимов Мухиддин Абдувохобовичга'

/* Markaz nomi — kartada kirill va lotin yozuvida ikkalasi ham bor */
export const KARTA_MARKAZ = {
  kir: ['ЎЗБЕКИСТОН ХАЛҚ ТАБОБАТИ АССОЦИАЦЯСИГА',
        'ҚАРАШЛИ "АСАЛ АРИ ШИФО 777 ОК"',
        'ХУСУСИЙ ТАБОБАТ МАРКАЗИ'],
  lat: ['O‘ZBEKISTON XALQ TABOBATI ASSOTSIATSIYSIGA',
        'QARASHLI "ASAL ARI SHIFO 777 OK"',
        'XUSUSIY TABOBAT MARKAZI']
}

/* Markaz logotipi — chop etish uchun fayl ichiga joylangan.
   Tashqi manzilga bogʻlanmaydi, shuning uchun internetsiz ham,
   yashirin chop ramkasida ham albatta chiqadi. */
export const LOGO =
  'data:image/png;base64,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'

/* Chop etish varaqlari — ekrandagi tugmalar shu roʻyxatdan chiziladi */
export const TOMONLAR = [
  { k: 'tash', n: 'Tashqi varaq', tavsif: 'Muqova va tilxat beti (1- va 4-bet)' },
  { k: 'ich', n: 'Ichki varaq', tavsif: 'I–IV kurs muolajasi (2- va 3-bet)' }
]

export const kartaCss = `
@page { size: A4 landscape; margin: 6mm; }
* { box-sizing: border-box; }
body { margin: 0; font: 10px/1.3 "Times New Roman", "Liberation Serif", Georgia, serif;
       color: #000; -webkit-print-color-adjust: exact; print-color-adjust: exact }

/* --- bitta A4 varaqning bir tomoni --- */
.varaq { display: flex; width: 285mm; height: 198mm;
         page-break-after: always; page-break-inside: avoid; overflow: hidden }
.varaq:last-child { page-break-after: auto }

/* --- varaqning yarmi = kartaning bitta beti (A5) --- */
.yarim { width: 142.5mm; height: 198mm; padding: 0 4mm; overflow: hidden;
         display: flex; flex-direction: column }
.yarim.ikki { border-left: 1px dashed #b0b0b0 }

/* ============ 1-BET: MUQOVA ============ */
.shapka { display: flex; align-items: flex-start; gap: 1.5mm; margin-top: 1mm }
.shapka .yon { flex: 1; text-align: center; font-size: 6.6px; line-height: 1.45;
               font-weight: 700; text-transform: uppercase }
.gerb { width: 13mm; height: 13mm; flex: none; object-fit: contain; margin-top: -1mm }

.nomer { display: flex; align-items: stretch; margin-top: .6mm; width: 34mm }
.nomer b { font-weight: 700; font-size: 6.5px; border: 1px solid #000;
           width: 5mm; display: flex; align-items: center; justify-content: center }
.nomer i { flex: 1; border: 1px solid #000; border-left: 0; height: 4.4mm; display: block }

.bosh { text-align: center; font-weight: 700; margin: 3mm 0 0; font-size: 12.5px;
        line-height: 1.35; text-transform: uppercase }
.bosh2 { text-align: center; font-weight: 700; font-size: 16.5px; margin: 1mm 0 4mm }
.bosh2 u { display: inline-block; min-width: 34mm; border-bottom: 1px solid #000;
           text-decoration: none; margin-left: 1mm }

.ustun { display: flex; gap: 3mm; align-items: flex-start }
.ustun .chap { width: 60% }
.ustun .ong { flex: 1 }

/* chap ustun: Фамилия / Исми / Отаасини исми */
.qat { display: flex; align-items: flex-end; gap: 1.5mm; margin-bottom: 4mm }
.qat > label { flex: none; font-size: 8.5px; font-weight: 700; padding-bottom: .8mm }
.quti { flex: 1; border: 1px solid #000; height: 7mm; padding: 0 1.2mm;
        display: flex; align-items: center; font-size: 10px; font-weight: 700;
        overflow: hidden; white-space: nowrap }

/* Тел — uchta ustma-ust quti, oxirgisi "т.й" */
.tel { display: flex; gap: 1.5mm; align-items: flex-start; margin-bottom: 4mm }
.tel > label { flex: none; font-size: 8.5px; font-weight: 700; padding-top: 1.8mm }
.tel .ust { flex: none; width: 66% }
.tel .quti { margin-bottom: -1px }
.tel .quti.oxir { justify-content: space-between }
.tel .tj { font-size: 8px; font-weight: 700 }

.kelgan { font-size: 8.5px; font-weight: 700; margin-top: 6mm }
.kelgan u { display: inline-block; min-width: 26mm; border-bottom: 1px solid #000;
            text-decoration: none; text-align: center; font-size: 10px; margin-left: 1mm }

/* oʻng ustun: manzil jadvali */
.manzil { border: 1px solid #000; border-bottom: 0 }
.manzil .m { border-bottom: 1px solid #000; height: 5.8mm; padding: 0 1.2mm;
             display: flex; align-items: center; justify-content: flex-end;
             font-size: 8.5px; font-weight: 700 }
.manzil .ikkov { display: flex; border-bottom: 1px solid #000 }
.manzil .ikkov .m { flex: 1; border-bottom: 0 }
.manzil .ikkov .m:first-child { border-right: 1px solid #000; flex: none; width: 40% }

/* oʻng ustun: xona va kurs qatorlari */
.xona-blok { border: 1px solid #000; border-bottom: 0; margin-top: 7mm }
.xona-blok .x1 { border-bottom: 1px solid #000; padding: 2mm 1.5mm;
                 display: flex; align-items: center; gap: 1.5mm; font-size: 8.5px;
                 font-weight: 700 }
.xona-blok .x1 .q { border: 1px solid #000; height: 6mm; min-width: 22mm; padding: 0 1.5mm;
                    display: flex; align-items: center; justify-content: center;
                    font-size: 10px; font-weight: 700 }
.xona-blok .k { border-bottom: 1px solid #000; height: 6.4mm; padding: 0 1.5mm;
                display: flex; align-items: center; font-size: 8.5px; font-weight: 700 }

.tashxis { margin-top: 8mm }
.tashxis b { font-size: 11px }
.tashxis .qiymat { font-size: 11px; font-weight: 700; margin-left: 2mm }
.tashxis .chiz { border-bottom: 1px solid #000; height: 9mm }

/* ============ 4-BET: YAKUN + ТИЛХАТ ============ */
.yakun-sar { font-size: 8.5px; font-weight: 700; margin: 1mm 0 0 }
.chiz { border-bottom: 1px solid #000; height: 11.8mm }

.tilxat-sar { text-align: center; font-weight: 700; font-size: 10.5px;
              margin: 7mm 0 6mm; letter-spacing: .06em }
.men { display: flex; align-items: flex-end; gap: 1.5mm; font-size: 10px }
.men u { flex: 1; border-bottom: 1px solid #000; text-decoration: none;
         height: 6mm; text-align: center; font-weight: 700; font-size: 10.5px;
         padding-bottom: .5mm }
.men-izoh { text-align: center; font-size: 6.4px; margin: .6mm 0 0 }
.tmatn { font-size: 10px; line-height: 2.5; margin: 4mm 0 0 }
.tmatn .ich { display: block; text-indent: 6mm }
.tilxat-imzo { display: flex; gap: 10mm; margin-top: 15mm; padding: 0 4mm }
.tilxat-imzo > div { flex: 1; font-size: 10px }
.tilxat-imzo .ch { border-bottom: 1px solid #000; height: 7mm; margin-top: 1mm }

/* ============ 2- va 3-BET: KURS MUOLAJASI ============ */
.kurs { margin-bottom: 8mm }
.kurs:last-child { margin-bottom: 0 }
.kurs-sar { display: flex; align-items: baseline; margin-bottom: 2mm }
.kurs-sar .nomi { flex: 1; text-align: center; font-weight: 700; font-size: 9.5px;
                  padding-left: 16mm }
.kurs-sar .sn { flex: none; font-size: 8.5px; white-space: nowrap }
.kurs-sar .sn u { display: inline-block; min-width: 5mm; border-bottom: 1px solid #000;
                  text-decoration: none; text-align: center }
.kurs-sar .sn u.oy { min-width: 11mm }

.kqator { display: flex; align-items: flex-end; gap: 1.5mm; height: 12.4mm }
.kqator > label { flex: none; font-size: 8.5px; padding-bottom: .6mm }
.kliniya { flex: 1; position: relative; height: 10mm; border-bottom: 1px solid #000 }
.kliniya .im { position: absolute; right: 0; bottom: 2.4mm; width: 27mm; height: 5mm;
               border: 1px solid #000 }
.kliniya .iz { position: absolute; right: 0; bottom: .2mm; width: 27mm;
               text-align: center; font-size: 5.8px; font-style: italic }
.kqator .kn { flex: none; width: 11mm; font-size: 8.5px; padding-bottom: .6mm }
.kqator .diag { flex: none; width: 23mm; height: 8.4mm; border: 1px solid #000 }
.kqator .diag svg { display: block; width: 100%; height: 100% }

/* Ekranda koʻrish uchun (modal ichidagi oldindan koʻrish).
   Chop etishda @page hoshiyasi ishlaydi, ekranda esa yoʻq —
   shuning uchun bu yerda varaq toʻliq A4 oʻlchamida chiziladi. */
@media screen {
  body { background: #e8e8e8; padding: 6mm }
  .varaq { width: 297mm; height: 210mm; padding: 6mm; background: #fff;
           margin: 0 auto 6mm; box-shadow: 0 1px 5px rgba(0,0,0,.28) }
  .varaq:last-child { margin-bottom: 0 }
}
`

/* ------------------------------------------------------------
   YORDAMCHI QISMLAR
   ------------------------------------------------------------ */

/* sanani boʻlaklarga ajratish — kurs sarlavhasidagi «"10" "09" 2026» uchun */
function sanaBolak(s) {
  const d = s ? new Date(s) : null
  if (!d || isNaN(d)) return { kun: '', oy: '', yil: new Date().getFullYear() }
  return {
    kun: String(d.getDate()).padStart(2, '0'),
    oy: String(d.getMonth() + 1).padStart(2, '0'),
    yil: d.getFullYear()
  }
}

function chiziqlar(n) {
  return '<div class="chiz"></div>'.repeat(n)
}

/* qiyshiq chiziqli katak — fon rasmi emas, SVG:
   brauzer "fon grafikasi"ni oʻchirib qoʻysa ham chiqadi */
const DIAGONAL =
  '<span class="diag"><svg viewBox="0 0 100 40" preserveAspectRatio="none">' +
  '<line x1="0" y1="40" x2="100" y2="0" stroke="#000" stroke-width="1" ' +
  'vector-effect="non-scaling-stroke"/></svg></span>'

/* bitta kurs jadvali — 7 kun.
   sana: {kun, oy, yil} — I kursda kelgan sanasi bilan toʻldiriladi */
function kursBlok(nomi, sana) {
  const qatorlar = []
  for (let i = 1; i <= 7; i++) {
    qatorlar.push(
      `<div class="kqator">
         <label>Муолажа қилувчи</label>
         <span class="kliniya"><span class="im"></span><span class="iz">(имзо)</span></span>
         <span class="kn">${i}-кун</span>
         ${DIAGONAL}
       </div>`)
  }
  return `
<div class="kurs">
  <div class="kurs-sar">
    <span class="nomi">${esc(nomi)} - Курс муолажаси</span>
    <span class="sn">"<u>${esc(sana.kun)}</u>"<u class="oy">${esc(sana.oy)}</u>${esc(sana.yil)}</span>
  </div>
  ${qatorlar.join('')}
</div>`
}

/* varaqning bir tomoni: chap yarmi + oʻng yarmi */
function varaq(chap, ong) {
  return `<div class="varaq">
  <div class="yarim">${chap}</div>
  <div class="yarim ikki">${ong}</div>
</div>`
}

/* ------------------------------------------------------------
   BETLAR
   ------------------------------------------------------------ */

/* 1-bet — muqova: markaz sarlavhasi, bemor maʼlumotlari, tashxis */
function bet1(y) {
  const xona = y.xona ? `${esc(y.xona)}-хона` : ''
  return `
<div class="shapka">
  <div class="yon">${KARTA_MARKAZ.kir.map(esc).join('<br>')}</div>
  <img class="gerb" src="${LOGO}" alt="">
  <div class="yon">${KARTA_MARKAZ.lat.map(esc).join('<br>')}</div>
</div>
<div class="nomer"><b>№</b><i></i><i></i><i></i><i></i><i></i></div>

<div class="bosh">АСАЛ АРИ ШИФО 777 ОК ДА ДАВОЛАНИБ<br>МУОЛАЖА ОЛГАН БЕМОРНИНГ МАЪЛУМОТЛАР</div>
<div class="bosh2">ВАРАҚАСИ<u></u></div>

<div class="ustun">
  <div class="chap">
    <div class="qat"><label>Фамилия:</label>
      <span class="quti">${esc(y.familiya || '')}</span></div>
    <div class="qat"><label>Исми:</label>
      <span class="quti">${esc(y.ism || '')}</span></div>
    <div class="qat"><label>Отаасини исми:</label>
      <span class="quti"></span></div>

    <div class="tel"><label>Тел</label>
      <div class="ust">
        <div class="quti">${esc(y.telefon || '')}</div>
        <div class="quti"></div>
        <div class="quti oxir"><span></span><span class="tj">т.й</span></div>
      </div>
    </div>

    <div class="kelgan">Келган саънаси<u>${esc(kun(y.kirish_sana))}</u></div>
  </div>

  <div class="ong">
    <div class="manzil">
      <div class="m">viloyati</div>
      <div class="m">shahri</div>
      <div class="m">МФЙ</div>
      <div class="m">кўчаси</div>
      <div class="ikkov"><div class="m">уй</div><div class="m">хонадон</div></div>
    </div>

    <div class="xona-blok">
      <div class="x1">Хона рақами:<span class="q">${xona}</span></div>
      <div class="k">Муолажа қилувчи: 1-курс</div>
      <div class="k">Муолажа қилувчи: 2-курс</div>
      <div class="k">Муолажа қилувчи: 3-курс</div>
      <div class="k">Муолажа қилувчи: 4-курс</div>
    </div>
  </div>
</div>

<div class="tashxis">
  <b>Касаллик ташхиси</b><span class="qiymat">${esc(y.tashxis || '')}</span>
</div>`
}

/* 2-bet — I va II kurs (I kurs sanasi kelgan sanadan olinadi) */
function bet2(y) {
  const s = sanaBolak(y.kirish_sana)
  return kursBlok('I', s) + kursBlok('II', { kun: '', oy: '', yil: s.yil })
}

/* 3-bet — III va IV kurs */
function bet3(y) {
  const s = sanaBolak(y.kirish_sana)
  const bosh = { kun: '', oy: '', yil: s.yil }
  return kursBlok('III', bosh) + kursBlok('IV', bosh)
}

/* 4-bet — muolaja yakuni va ТИЛХАТ */
function bet4(y) {
  return `
<div class="yakun-sar">Муолажа якуни бўйича беморнинг холатидаги ўзгаришлар</div>
${chiziqlar(7)}

<div class="tilxat-sar">ТИЛХАТ</div>
<div class="men"><span>Мен,</span><u>${esc(y.fish || '')}</u></div>
<div class="men-izoh">(Беморнинг исми, шарифи, отасининг исми тўлиқ ёзилади)</div>

<div class="tmatn">
  ўз ҳоҳишим ва ихтиёрим билан халқ табобати усулида муолажа олиш учун табиб<br>
  <b>${esc(TABIB_KIR)}</b> мурожаат қилдим. Менга оғзаки келишув<br>
  асосида муолажа шартлари ва қоидалари тўлиқ тушунтирилди.
  <span class="ich">Муолажа жараёнига мен томондан хеч қандай эътирозларим йўқ.</span>
  <span class="ich">Тилхатни ўз қўлларим билан тўғри ёздим.</span>
</div>

<div class="tilxat-imzo">
  <div>Сана<div class="ch"></div></div>
  <div>Имзо<div class="ch"></div></div>
</div>`
}

/* ------------------------------------------------------------
   TO'LIQ HTML
   tomon: 'tash' | 'ich' | undefined (ikkalasi)
   ('old' va 'orqa' — eski nomlar, ular ham ishlayveradi)
   ------------------------------------------------------------ */
export function kartaHtml(y, tomon) {
  const tashqi = varaq(bet4(y), bet1(y))   /* [4-bet | 1-bet] */
  const ichki = varaq(bet2(y), bet3(y))    /* [2-bet | 3-bet] */
  if (tomon === 'tash' || tomon === 'old') return tashqi
  if (tomon === 'ich' || tomon === 'orqa') return ichki
  return tashqi + ichki
}
