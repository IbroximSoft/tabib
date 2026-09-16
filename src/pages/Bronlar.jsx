import { useEffect, useMemo, useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { db, amal, xatoMatni } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Kutish } from '../components/Kutish'
import Modal, { Xabar } from '../components/Modal'

/* ---------- yordamchilar ---------- */
const son = (n) => (Number(n) || 0).toLocaleString('ru-RU').replace(/ /g, ' ')
const som = (n) => son(n) + ' soʻm'
const sana = (s) => (s ? new Date(s).toLocaleDateString('ru-RU') : '—')
const bugun = () => {
  const d = new Date()
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
}
const qoshKun = (s, n) => {
  const d = new Date(s + 'T00:00:00')
  d.setDate(d.getDate() + n)
  return d.toISOString().slice(0, 10)
}

/* Brauzer "сент." deb qaytaradi — oyni o'zimiz yozamiz */
const OYLAR = ['yan', 'fev', 'mar', 'apr', 'may', 'iyn',
               'iyl', 'avg', 'sen', 'okt', 'noy', 'dek']
const oyQisqa = (s) => OYLAR[new Date(s).getMonth()] || ''

const HOLAT_NOM = {
  kutilmoqda: 'Kutilmoqda', bugun: 'Bugun keladi', kechikkan: 'Kechikkan',
  qabul: 'Qabul qilindi', kelmadi: 'Kelmadi', bekor: 'Bekor qilingan'
}
const HOLAT_KLASS = {
  kutilmoqda: 'booked', bugun: 'free', kechikkan: 'partial',
  qabul: 'free', kelmadi: 'full', bekor: 'neutral'
}
const FILTR = [
  { k: 'faol', n: 'Kutilmoqda' },
  { k: 'bugun', n: 'Bugun' },
  { k: 'kechikkan', n: 'Kechikkan' },
  { k: 'qabul', n: 'Qabul qilingan' },
  { k: 'yopiq', n: 'Kelmadi / bekor' },
  { k: '', n: 'Hammasi' }
]

export default function Bronlar() {
  const { can } = useAuth()
  const nav = useNavigate()

  const [royxat, setRoyxat] = useState(null)
  const [bolimlar, setBolimlar] = useState([])
  const [kursKun, setKursKun] = useState(10)
  const [filtr, setFiltr] = useState('faol')
  const [qidiruv, setQidiruv] = useState('')
  const [xato, setXato] = useState('')
  const [modal, setModal] = useState(null)
  const [xabar, setXabar] = useState('')

  const bildir = (m) => { setXabar(m); setTimeout(() => setXabar(''), 4000) }

  const yukla = useCallback(async () => {
    const [b, bo, t] = await Promise.all([db.bronlar(), db.bolimlar(), db.tariflar()])
    if (b.error) {
      setXato('Bronlar koʻrinishi bazada hali oʻrnatilmagan. SQL Editorʼda 14_bronlar.sql faylini ishga tushiring.')
      return
    }
    setRoyxat(b.data || [])
    setBolimlar(bo.data || [])
    const k = (t.data || []).find((x) => x.kalit === 'kurs_kun')
    if (k) setKursKun(Number(k.qiymat))
  }, [])

  useEffect(() => { yukla() }, [yukla])

  const hisob = useMemo(() => {
    const a = royxat || []
    return {
      bugun: a.filter((b) => b.holat_matn === 'bugun').length,
      kechikkan: a.filter((b) => b.holat_matn === 'kechikkan').length,
      kutilmoqda: a.filter((b) => b.holat === 'kutilmoqda').length,
      hafta: a.filter((b) => b.holat === 'kutilmoqda' &&
        b.qolgan_kun >= 0 && b.qolgan_kun <= 7).length,
      toqnashuv: a.filter((b) => b.holat === 'kutilmoqda' && Number(b.toqnashuv) > 0).length
    }
  }, [royxat])

  const korinadi = useMemo(() => {
    const q = qidiruv.trim().toLowerCase()
    return (royxat || []).filter((b) => {
      if (filtr === 'faol' && b.holat !== 'kutilmoqda') return false
      if (filtr === 'bugun' && b.holat_matn !== 'bugun') return false
      if (filtr === 'kechikkan' && b.holat_matn !== 'kechikkan') return false
      if (filtr === 'qabul' && b.holat !== 'qabul_qilindi') return false
      if (filtr === 'yopiq' && !['kelmadi', 'bekor'].includes(b.holat)) return false
      if (q && !(`${b.ismi} ${b.telefon}`.toLowerCase().includes(q))) return false
      return true
    })
  }, [royxat, filtr, qidiruv])

  /* Bronni qabul qilish — ro'yxatga olish formasi Bemorlar ekranida,
     shunda hamroh qo'shish, dublikat tekshiruvi — hammasi bir joyda qoladi */
  function qabulQil(b) {
    nav('/bemorlar', { state: { bron: b } })
  }

  async function holatOzgartir(b, holat, sabab) {
    const { error } = await amal.bronHolat(b.bron_id, holat, sabab)
    if (error) return bildir(xatoMatni(error))
    setModal(null)
    bildir(holat === 'kelmadi'
      ? `${b.ismi} — kelmadi deb belgilandi.`
      : `${b.ismi} broni bekor qilindi.`)
    yukla()
  }

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>
  if (!royxat) return <Kutish />

  return (
    <div className="stack">
      <div className="kpis">
        <Kpi v={hisob.bugun} l="Bugun keladi" rang="g" />
        <Kpi v={hisob.hafta} l="Bu hafta" rang="a" />
        <Kpi v={hisob.kutilmoqda} l="Jami kutilmoqda" rang="b" />
        {hisob.kechikkan > 0 && <Kpi v={hisob.kechikkan} l="Kechikkan" rang="o" />}
        {hisob.toqnashuv > 0 && <Kpi v={hisob.toqnashuv} l="Xona toʻqnashuvi" rang="r" />}
      </div>

      <div className="toolbar">
        <div className="qidir">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
            strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
          <input value={qidiruv} onChange={(e) => setQidiruv(e.target.value)}
            placeholder="Ism yoki telefon" type="search" />
        </div>
        <span className="sp" />
        {can('bron') && (
          <button className="btn pri" onClick={() => setModal({ tur: 'yangi' })}>
            + Yangi bron
          </button>
        )}
      </div>

      <div className="chips">
        {FILTR.map((f) => (
          <button key={f.k} className={`chip${filtr === f.k ? ' on' : ''}`}
            onClick={() => setFiltr(f.k)}>{f.n}</button>
        ))}
      </div>

      {hisob.kechikkan > 0 && filtr === 'faol' && (
        <div className="alert warn">
          <span>◇</span>
          <div>
            <b>{hisob.kechikkan} ta bron kechikkan</b> — kelishi kerak boʻlgan kun oʻtib
            ketgan, lekin hali qabul qilinmagan. Ular xonani band qilib turadi.{' '}
            <button className="matn" onClick={() => setFiltr('kechikkan')}>Koʻrish</button>
          </div>
        </div>
      )}

      {korinadi.length === 0 ? (
        <div className="bosh-yoq">
          <div className="nm">Bu filtr boʻyicha bron yoʻq</div>
          <div className="muted">
            Kelishi rejalashtirilgan odamni shu yerdan band qilib qoʻying —
            u bemor boʻlmaguncha qarz hisoblanmaydi.
          </div>
        </div>
      ) : (
        <div className="bron-grid">
          {korinadi.map((b) => (
            <BronKart key={b.bron_id} b={b} can={can}
              qabul={() => qabulQil(b)}
              amal={(tur) => setModal({ tur, bron: b })} />
          ))}
        </div>
      )}

      {modal?.tur === 'yangi' && (
        <YangiBron bolimlar={bolimlar} kursKun={kursKun}
          yop={() => setModal(null)}
          tugadi={(m) => { setModal(null); bildir(m); yukla() }} />
      )}
      {(modal?.tur === 'kelmadi' || modal?.tur === 'bekor') && (
        <HolatModal b={modal.bron} tur={modal.tur}
          yop={() => setModal(null)}
          tasdiq={(sabab) => holatOzgartir(modal.bron, modal.tur, sabab)} />
      )}
      {modal?.tur === 'xona' && (
        <XonaModal b={modal.bron}
          yop={() => setModal(null)}
          tugadi={(m) => { setModal(null); bildir(m); yukla() }} />
      )}
      <Xabar matn={xabar} />
    </div>
  )
}

function Kpi({ v, l, rang = 'a' }) {
  return (
    <div className={`kpi ${rang}`}>
      <span className="bar" />
      <div className="v num">{v}</div>
      <div className="l">{l}</div>
    </div>
  )
}

/* ============================================================
   BRON KARTASI
   ============================================================ */
function BronKart({ b, can, qabul, amal: amalOch }) {
  const faol = b.holat === 'kutilmoqda'
  const kech = b.holat_matn === 'kechikkan'

  return (
    <div className={`card bron-kart${kech ? ' kech' : ''}`}>
      <div className="bk-bosh">
        <div className="bk-sana">
          <b>{new Date(b.kirish).getDate()}</b>
          <span>{oyQisqa(b.kirish)}</span>
        </div>
        <div className="bk-meta">
          <div className="nm">{b.ismi}</div>
          <div className="sb">
            <span className={`dot ${b.jins || 'erkak'}`} />
            {b.telefon}
            {b.kishi > 1 && ` · ${b.kishi} kishi`}
          </div>
        </div>
        <span className={`pill ${HOLAT_KLASS[b.holat_matn] || 'neutral'}`}>
          {HOLAT_NOM[b.holat_matn] || b.holat_matn}
        </span>
      </div>

      <dl className="dl bk-dl">
        <dt>Sanalar</dt>
        <dd>{sana(b.kirish)} — {sana(b.chiqish)} <span className="muted">({b.kun} kun)</span></dd>
        <dt>Joy</dt>
        <dd>{b.xona ? `${b.bolim} · ${b.xona}-xona` : b.bolim || 'Xona tanlanmagan'}</dd>
        {faol && b.qolgan_kun >= 0 && (
          <>
            <dt>Qolgan</dt>
            <dd>{b.qolgan_kun === 0 ? 'Bugun keladi' : `${b.qolgan_kun} kun`}</dd>
          </>
        )}
        {kech && (
          <>
            <dt>Kechikdi</dt>
            <dd style={{ color: 'var(--partial)' }}>{Math.abs(b.qolgan_kun)} kun</dd>
          </>
        )}
        {b.tashxis && (<><dt>Tashxis</dt><dd>{b.tashxis}</dd></>)}
      </dl>

      {b.izoh && <div className="bk-izoh">{b.izoh}</div>}

      {faol && Number(b.toqnashuv) > 0 && (
        <div className="alert warn sm">
          <span>◇</span>
          <div>
            {b.xona}-xonada hozir yotgan bemor {sana(b.kirish)} dan keyin ham qoladi.
            Boshqa xona kerak boʻladi.
          </div>
        </div>
      )}

      {/* Kuzatuvchida amal yo'q — bo'sh panel chizilmasin */}
      {faol && (can('royxat') || can('bron')) && (
        <div className="bk-oyoq">
          {can('royxat') && (
            <button className="btn pri sm" onClick={qabul}>Qabul qilish</button>
          )}
          {can('bron') && <>
            <button className={'btn sm' + (Number(b.toqnashuv) > 0 ? ' pri' : '')}
              onClick={() => amalOch('xona')}>
              {b.xona ? 'Xonani oʻzgartirish' : 'Xona tanlash'}
            </button>
            <button className="btn sm" onClick={() => amalOch('kelmadi')}>Kelmadi</button>
            <button className="btn sm" onClick={() => amalOch('bekor')}>Bekor</button>
          </>}
        </div>
      )}
    </div>
  )
}

/* ============================================================
   YANGI BRON
   ============================================================ */
function YangiBron({ bolimlar, kursKun, yop, tugadi }) {
  const [v, setV] = useState({
    ismi: '', telefon: '+998 ', jins: 'erkak',
    kirish: qoshKun(bugun(), 1),
    chiqish: qoshKun(bugun(), 1 + kursKun),
    kishi: '1', bolim_id: '', xona_id: '', izoh: '', tashxis: ''
  })
  const [joylar, setJoylar] = useState(null)
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)
  const set = (k, x) => setV((s) => ({ ...s, [k]: x }))

  /* kurs muddati tarifdan */
  useEffect(() => { set('chiqish', qoshKun(v.kirish, kursKun)) }, [v.kirish, kursKun])

  /* sanalar yoki jins o'zgarsa — bo'sh joylarni qayta so'raymiz */
  useEffect(() => {
    if (!v.kirish || !v.chiqish || v.chiqish <= v.kirish) { setJoylar([]); return }
    let bekor = false
    setJoylar(null)
    db.bronBoshJoylar(v.kirish, v.chiqish, v.jins).then(({ data, error }) => {
      if (bekor) return
      if (error) { setXato(xatoMatni(error)); setJoylar([]); return }
      setJoylar(data || [])
    })
    return () => { bekor = true }
  }, [v.kirish, v.chiqish, v.jins])

  /* tanlangan xona endi mos kelmasa — tozalaymiz */
  useEffect(() => {
    if (!v.xona_id || !joylar) return
    const x = joylar.find((j) => String(j.xona_id) === String(v.xona_id))
    if (!x || Number(x.bosh) < Number(v.kishi || 1)) set('xona_id', '')
  }, [joylar, v.kishi]) // eslint-disable-line react-hooks/exhaustive-deps

  const mos = useMemo(
    () => (joylar || []).filter((j) => Number(j.bosh) >= Number(v.kishi || 1)),
    [joylar, v.kishi])

  const tanlangan = useMemo(
    () => (joylar || []).find((j) => String(j.xona_id) === String(v.xona_id)),
    [joylar, v.xona_id])

  async function saqla() {
    setXato('')
    if (!v.ismi.trim()) return setXato('Ism-familiyani kiriting.')
    if (v.telefon.replace(/\D/g, '').length < 9) return setXato('Telefon raqamini toʻliq kiriting.')
    if (v.chiqish <= v.kirish) return setXato('Chiqish sanasi kirish sanasidan keyin boʻlishi kerak.')
    if (v.kirish < bugun()) return setXato('Bron oʻtgan sanaga qoʻyilmaydi.')
    if (!(Number(v.kishi) > 0)) return setXato('Kishilar sonini kiriting.')

    setBand(true)
    const { data, error } = await amal.bronQosh({
      ismi: v.ismi.trim(), telefon: v.telefon.trim(), jins: v.jins,
      kirish: v.kirish, chiqish: v.chiqish, kishi: Number(v.kishi),
      bolim_id: v.bolim_id ? Number(v.bolim_id) : (tanlangan ? tanlangan.bolim_id : null),
      xona_id: v.xona_id ? Number(v.xona_id) : null,
      izoh: v.izoh.trim()
    })
    if (error) { setBand(false); return setXato(xatoMatni(error)) }

    /* Tashxis alohida yoziladi — bron_qosh() imzosiga tegmaslik uchun.
       Bron allaqachon yaratilgan, shuning uchun bu qadam xato bersa
       ham bekor qilmaymiz, faqat aytamiz. */
    let ogoh = ''
    if (v.tashxis.trim() && data) {
      const { error: te } = await amal.bronTashxis(Number(data), v.tashxis.trim())
      if (te) ogoh = ' (tashxis yozilmadi)'
    }
    setBand(false)
    tugadi(`${v.ismi} uchun ${sana(v.kirish)} ga bron qoʻyildi.` + ogoh)
  }

  return (
    <Modal sarlavha="Yangi bron" yop={yop} kenglik={560}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Bekor qilish</button>
        <button className="btn pri" onClick={saqla} disabled={band}>
          {band ? 'Saqlanmoqda…' : 'Bron qoʻyish'}
        </button>
      </>}>
      {xato && <div className="alert err" style={{ marginBottom: 14 }}><span>▲</span><div>{xato}</div></div>}

      <div className="grid2">
        <div className="field full">
          <label htmlFor="bi">Ism-familiya</label>
          <input id="bi" value={v.ismi} onChange={(e) => set('ismi', e.target.value)}
            placeholder="Nazarov Bekzod" />
        </div>

        <div className="field">
          <label htmlFor="bt">Telefon raqami</label>
          <input id="bt" value={v.telefon} onChange={(e) => set('telefon', e.target.value)}
            inputMode="tel" />
        </div>
        <div className="field">
          <label>Jinsi</label>
          <div className="seg">
            <button type="button" className={v.jins === 'erkak' ? 'on erkak' : ''}
              onClick={() => set('jins', 'erkak')}>Erkak</button>
            <button type="button" className={v.jins === 'ayol' ? 'on ayol' : ''}
              onClick={() => set('jins', 'ayol')}>Ayol</button>
          </div>
        </div>

        <div className="field">
          <label htmlFor="bk">Kirish sanasi</label>
          <input id="bk" type="date" value={v.kirish} min={bugun()}
            onChange={(e) => set('kirish', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="bc">Rejadagi chiqish</label>
          <input id="bc" type="date" value={v.chiqish} min={v.kirish}
            onChange={(e) => set('chiqish', e.target.value)} />
          <div className="hint">1 kurs = {kursKun} kun.</div>
        </div>

        <div className="field">
          <label htmlFor="bn">Necha kishi</label>
          <input id="bn" type="number" min="1" max="20" value={v.kishi}
            onChange={(e) => set('kishi', e.target.value)} />
          <div className="hint">Hamrohi bilan kelsa — 2 yoki undan koʻp.</div>
        </div>
        <div className="field">
          <label htmlFor="bb">Boʻlim</label>
          <select id="bb" value={v.bolim_id} onChange={(e) => set('bolim_id', e.target.value)}>
            <option value="">— farqi yoʻq —</option>
            {bolimlar.map((b) => <option key={b.id} value={b.id}>{b.nomi}</option>)}
          </select>
        </div>

        <div className="field full">
          <label htmlFor="bx">Xona</label>
          <select id="bx" value={v.xona_id} onChange={(e) => set('xona_id', e.target.value)}
            disabled={joylar === null}>
            <option value="">— xonasiz bron (kelganda tanlanadi) —</option>
            {mos
              .filter((j) => !v.bolim_id || String(j.bolim_id) === String(v.bolim_id))
              .map((j) => (
                <option key={j.xona_id} value={j.xona_id}>
                  {j.xona}-xona · {j.bolim} · {j.bosh} boʻsh joy
                </option>
              ))}
          </select>
          <div className="hint">
            {joylar === null
              ? 'Boʻsh joylar tekshirilmoqda…'
              : mos.length === 0
                ? 'Bu sanalarda mos boʻsh xona yoʻq. Xonasiz bron qoʻying — kelganda joy tanlanadi.'
                : `Shu sanalarda ${mos.length} ta xonada joy bor. Roʻyxat oʻsha kunlarda yotadigan bemorlar va boshqa bronlarni hisobga oladi.`}
          </div>
        </div>

        {tanlangan && (
          <div className="field full">
            <div className="bron-narx">
              <div>
                <b>{tanlangan.xona}-xona · {tanlangan.turi}</b>
                <div className="muted">
                  {tanlangan.sigim} koyka · {tanlangan.band} band · {tanlangan.bron_band} bron
                </div>
              </div>
              <span className="sp" />
              <span className="num">{som(tanlangan.narx)}</span>
            </div>
            <div className="hint">
              Xona narxi — maʼlumot uchun. Pul bemor kelib xonaga joylashgandan keyin
              hisoblanadi, bron qarz yaratmaydi.
            </div>
          </div>
        )}

        <div className="field full">
          <label htmlFor="bt2">Kasallik tashxisi</label>
          <input id="bt2" value={v.tashxis} onChange={(e) => set('tashxis', e.target.value)}
            placeholder="Bel ogʻrigʻi, osteoxondroz" />
          <div className="hint">
            Bemor kelib roʻyxatga olinganda tashxis avtomatik oʻtadi va
            kasallik varaqasiga bosiladi.
          </div>
        </div>

        <div className="field full">
          <label htmlFor="bz">Izoh</label>
          <input id="bz" value={v.izoh} onChange={(e) => set('izoh', e.target.value)}
            placeholder="Telefon orqali, tanishi bor…" />
        </div>
      </div>
    </Modal>
  )
}

/* ============================================================
   KELMADI / BEKOR — sabab bilan
   ============================================================ */
function HolatModal({ b, tur, yop, tasdiq }) {
  const [sabab, setSabab] = useState('')
  const [band, setBand] = useState(false)
  const kelmadi = tur === 'kelmadi'

  return (
    <Modal sarlavha={kelmadi ? 'Kelmadi deb belgilash' : 'Bronni bekor qilish'}
      yop={yop} kenglik={440}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Orqaga</button>
        <button className="btn dan" disabled={band}
          onClick={() => { setBand(true); tasdiq(sabab) }}>
          {band ? '…' : (kelmadi ? 'Kelmadi' : 'Bekor qilish')}
        </button>
      </>}>
      <div className="karta-bosh">
        <div>
          <h3>{b.ismi}</h3>
          <div className="muted">
            {sana(b.kirish)} — {sana(b.chiqish)}
            {b.xona ? ` · ${b.xona}-xona` : ''}
          </div>
        </div>
      </div>

      <p className="muted" style={{ margin: '10px 0 14px' }}>
        {kelmadi
          ? 'Bron yopiladi va band qilingan joy boʻshaydi. Odam keyinroq kelsa yangi bron qoʻyiladi.'
          : 'Bron bekor qilinadi va joy boʻshaydi.'}
      </p>

      <div className="field">
        <label htmlFor="hs">Sabab</label>
        <input id="hs" value={sabab} onChange={(e) => setSabab(e.target.value)}
          placeholder={kelmadi ? 'Telefon koʻtarmadi' : 'Oʻzi bekor qildi'} />
        <div className="hint">Izohga yoziladi — keyin kim va nega yopganini bilish uchun.</div>
      </div>
    </Modal>
  )
}

/* ============================================================
   BRON XONASINI OʻZGARTIRISH

   Bron qoʻyilganda xona boʻsh edi, keyin oʻsha xonadagi
   bemorning muddati uzaytirildi — endi bron kuniga xona
   boʻshamaydi. Shu oynadan boshqa xona tanlanadi; bron
   oʻzgarmaydi, faqat joyi almashadi.
   ============================================================ */
function XonaModal({ b, yop, tugadi }) {
  const [joylar, setJoylar] = useState(null)
  const [tanlov, setTanlov] = useState(b.xona_id ? String(b.xona_id) : '')
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)

  /* p_bron beriladi — bronning OʻZI band qilgan joy hisobdan
     chiqariladi, aks holda xona doim "toʻla" koʻrinardi. */
  useEffect(() => {
    let bekor = false
    ;(async () => {
      const { data, error } = await db.bronBoshJoylar(b.kirish, b.chiqish, b.jins, b.bron_id)
      if (bekor) return
      if (error) { setXato(xatoMatni(error)); setJoylar([]); return }
      setJoylar(data || [])
    })()
    return () => { bekor = true }
  }, [b.bron_id, b.kirish, b.chiqish, b.jins])

  async function saqla() {
    setXato(''); setBand(true)
    const { data, error } = await amal.bronXona(b.bron_id, tanlov ? Number(tanlov) : null)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    tugadi(data === 'xonasiz'
      ? `${b.ismi} broni xonasiz qoldirildi.`
      : `${b.ismi} broni ${data}-xonaga koʻchirildi.`)
  }

  const yetarli = (j) => Number(j.bosh) >= Number(b.kishi || 1)
  const mos = (joylar || []).filter(yetarli)
  const tor = (joylar || []).filter((j) => !yetarli(j))

  return (
    <Modal sarlavha="Bron xonasini oʻzgartirish" yop={yop} kenglik={460}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Orqaga</button>
        <button className="btn pri" onClick={saqla}
          disabled={band || String(tanlov) === String(b.xona_id || '')}>
          {band ? '…' : 'Saqlash'}
        </button>
      </>}>

      <div className="karta-bosh">
        <div>
          <h3>{b.ismi}</h3>
          <div className="muted">
            {sana(b.kirish)} — {sana(b.chiqish)} · {b.kishi || 1} kishi
            {b.xona ? ` · hozir ${b.xona}-xona` : ' · xona tanlanmagan'}
          </div>
        </div>
      </div>

      {xato && <div className="alert err" style={{ margin: '12px 0' }}>
        <span>▲</span><div>{xato}</div></div>}

      {Number(b.toqnashuv) > 0 && (
        <div className="alert warn" style={{ margin: '12px 0' }}>
          <span>◇</span>
          <div>
            {b.xona}-xonada hozir yotgan bemor bron kuniga qadar chiqmaydi.
            Pastdagi roʻyxatda oʻsha sanalarda rostdan boʻsh xonalar bor.
          </div>
        </div>
      )}

      {joylar === null ? (
        <div className="muted" style={{ padding: '14px 0' }}>Boʻsh joylar qidirilmoqda…</div>
      ) : (
        <div className="field" style={{ marginTop: 12 }}>
          <label htmlFor="bx">Xona</label>
          <select id="bx" value={tanlov} onChange={(e) => setTanlov(e.target.value)}>
            <option value="">— xonasiz qoldirish —</option>
            {mos.map((j) => (
              <option key={j.xona_id} value={j.xona_id}>
                {j.xona}-xona · {j.bolim} · {j.bosh} ta boʻsh joy
              </option>
            ))}
          </select>
          <div className="hint">
            {mos.length === 0
              ? 'Bu sanalarda mos xona yoʻq. Bronni xonasiz qoldiring — odam kelganda joy tanlanadi.'
              : `Roʻyxatda ${sana(b.kirish)} – ${sana(b.chiqish)} kunlari `
                + `${b.kishi || 1} kishiga joy yetadigan xonalar bor.`}
            {tor.length > 0 && (
              <><br />Joy yetmaydigan xonalar koʻrsatilmadi: {tor.map((j) => j.xona).join(', ')}.</>
            )}
          </div>
        </div>
      )}
    </Modal>
  )
}
