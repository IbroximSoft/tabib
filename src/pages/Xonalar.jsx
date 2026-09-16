import { useEffect, useMemo, useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { db, amal, xatoMatni } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Kutish } from '../components/Kutish'
import Modal, { Xabar } from '../components/Modal'

const son = (n) => (Number(n) || 0).toLocaleString('ru-RU').replace(/ /g, ' ')
const som = (n) => son(n) + ' soʻm'
const sana = (s) => (s ? new Date(s).toLocaleDateString('ru-RU') : '—')

const HOLAT_NOM = {
  bosh: 'Boʻsh', qisman: 'Qisman band', toliq: 'Toʻla',
  bron: 'Bron qilingan', tamir: 'Taʼmirda'
}
const HOLAT_KLASS = {
  bosh: 'free', qisman: 'partial', toliq: 'full', bron: 'booked', tamir: 'repair'
}
const FILTR = [
  { k: '', n: 'Hammasi' },
  { k: 'bosh_joy', n: 'Boʻsh joyi bor' },
  { k: 'toliq', n: 'Toʻla' },
  { k: 'tamir', n: 'Taʼmirda' }
]

export default function Xonalar() {
  const { can, rol } = useAuth()
  const nav = useNavigate()

  const [xonalar, setXonalar] = useState(null)
  const [koykalar, setKoykalar] = useState([])
  const [bolimlar, setBolimlar] = useState([])
  const [turlar, setTurlar] = useState([])
  const [xonasizlar, setXonasizlar] = useState([])
  const [filtr, setFiltr] = useState('')
  const [bolim, setBolim] = useState('')
  const [qidiruv, setQidiruv] = useState('')
  const [xato, setXato] = useState('')
  const [modal, setModal] = useState(null)
  const [xabar, setXabar] = useState('')

  const bildir = (m) => { setXabar(m); setTimeout(() => setXabar(''), 4000) }

  const yukla = useCallback(async () => {
    const [x, k, b, t, y] = await Promise.all([
      db.xonalar(), db.koykaHolati(), db.bolimlar(), db.xonaNarxlari(),
      db.yotqizishlar({ holat: 'yotmoqda' })
    ])
    if (x.error) { setXato(xatoMatni(x.error)); return }
    if (k.error) {
      setXato('Xonalar koʻrinishi bazada hali oʻrnatilmagan. SQL Editorʼda 12_xonalar_korinishi.sql faylini ishga tushiring.')
      return
    }
    setXonalar(x.data || [])
    setKoykalar(k.data || [])
    setBolimlar(b.data || [])
    setTurlar(t.data || [])
    /* xonaga hali joylashtirilmagan bemorlar — boʻsh joyga bosilganda taklif qilinadi */
    setXonasizlar((y.data || []).filter((r) => !r.xonada))
  }, [])

  useEffect(() => { yukla() }, [yukla])

  /* koykalarni xonalar bo'yicha guruhlaymiz */
  const koykaMap = useMemo(() => {
    const m = {}
    koykalar.forEach((k) => { (m[k.xona_id] = m[k.xona_id] || []).push(k) })
    Object.values(m).forEach((a) => a.sort((p, q) => p.koyka - q.koyka))
    return m
  }, [koykalar])

  const korinadi = useMemo(() => {
    const q = qidiruv.trim().toLowerCase()
    return (xonalar || []).filter((x) => {
      if (bolim && String(x.bolim_id) !== String(bolim)) return false
      if (filtr === 'bosh_joy' && (x.tamirlashda || Number(x.band) >= Number(x.sigim))) return false
      if (filtr === 'toliq' && x.holat !== 'toliq') return false
      if (filtr === 'tamir' && !x.tamirlashda) return false
      if (q && !String(x.raqam).toLowerCase().includes(q)) return false
      return true
    })
  }, [xonalar, bolim, filtr, qidiruv])

  /* bo'limlar bo'yicha bo'lib chiqamiz */
  const guruh = useMemo(() => {
    const m = new Map()
    korinadi.forEach((x) => {
      if (!m.has(x.bolim_id)) {
        m.set(x.bolim_id, { id: x.bolim_id, nomi: x.bolim, tartib: x.bolim_tartib, xonalar: [] })
      }
      m.get(x.bolim_id).xonalar.push(x)
    })
    return [...m.values()]
      .sort((a, b) => (a.tartib || 0) - (b.tartib || 0))
      .map((g) => ({
        ...g,
        xonalar: g.xonalar.sort((a, b) =>
          String(a.raqam).localeCompare(String(b.raqam), 'uz', { numeric: true })),
        sigim: g.xonalar.reduce((s, x) => s + Number(x.sigim), 0),
        band: g.xonalar.reduce((s, x) => s + Number(x.band), 0)
      }))
  }, [korinadi])

  const jami = useMemo(() => {
    const a = xonalar || []
    return {
      sigim: a.reduce((s, x) => s + Number(x.sigim), 0),
      band: a.reduce((s, x) => s + Number(x.band), 0),
      tamir: a.filter((x) => x.tamirlashda).length,
      tasdiqlanmagan: a.reduce((s, x) => s + Number(x.tasdiqlanmagan || 0), 0)
    }
  }, [xonalar])

  async function tamirga(x, holat) {
    const { error } = await amal.xonaTamir(x.id, holat)
    if (error) return bildir(xatoMatni(error))
    bildir(holat ? `${x.raqam}-xona taʼmirga qoʻyildi.` : `${x.raqam}-xona ishga qaytarildi.`)
    yukla()
  }

  /* bo'sh koykaga bosilganda — avval xonasiz bemorlar taklif qilinadi,
     ular ichida mos keladigani bo'lmasa yangi bemor qo'shiladi */
  function boshKoykaga(k) {
    setModal({ tur: 'bosh', koyka: k })
  }

  /* yangi bemor — Bemorlar ekranidagi qabul formasi shu koyka bilan ochiladi */
  function yangiBemor(k) {
    nav('/bemorlar', {
      state: {
        yangiKoyka: k.koyka_id,
        jins: k.bolim_jinsi !== 'aralash' ? k.bolim_jinsi : null
      }
    })
  }

  async function joylash(y, k) {
    const { error } = await amal.koykaBiriktir(y.yotqizish_id, k.koyka_id)
    if (error) return bildir(xatoMatni(error))
    setModal(null)
    bildir(`${y.fish} ${k.xona}-xona, ${k.koyka}-koykaga joylashtirildi.`)
    yukla()
  }

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>
  if (!xonalar) return <Kutish />

  return (
    <div className="stack">
      {/* ---------- yuqori ko'rsatkichlar ---------- */}
      <div className="kpis">
        <Kpi v={`${jami.band} / ${jami.sigim}`} l="Koyka band" rang="a" />
        <Kpi v={jami.sigim - jami.band} l="Boʻsh koyka" rang="g" />
        <Kpi v={xonalar.length} l="Jami xona" rang="b" />
        {jami.tamir > 0 && <Kpi v={jami.tamir} l="Taʼmirdagi xona" rang="o" />}
        {jami.tasdiqlanmagan > 0 &&
          <Kpi v={jami.tasdiqlanmagan} l="Tasdiqlanmagan bemor" rang="r" />}
      </div>

      {/* ---------- asboblar ---------- */}
      <div className="toolbar">
        <div className="qidir">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
            strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
          <input value={qidiruv} onChange={(e) => setQidiruv(e.target.value)}
            placeholder="Xona raqami" type="search" />
        </div>
        <span className="sp" />
        {rol === 'super_admin' && (
          <button className="btn pri" onClick={() => setModal({ tur: 'yangi' })}>
            + Xona qoʻshish
          </button>
        )}
      </div>

      <div className="chips">
        {FILTR.map((f) => (
          <button key={f.k} className={`chip${filtr === f.k ? ' on' : ''}`}
            onClick={() => setFiltr(f.k)}>{f.n}</button>
        ))}
        <span className="sp" />
        <select className="mini" value={bolim} onChange={(e) => setBolim(e.target.value)}>
          <option value="">Barcha boʻlimlar</option>
          {bolimlar.map((b) => <option key={b.id} value={b.id}>{b.nomi}</option>)}
        </select>
      </div>

      {/* ---------- bo'limlar ---------- */}
      {guruh.length === 0 ? (
        <div className="todo">Bu filtr boʻyicha xona topilmadi.</div>
      ) : guruh.map((g) => (
        <div key={g.id} className="bolim-blok">
          <div className="bolim-sarlavha">
            <h3>{g.nomi}</h3>
            <span className="sp" />
            <span className="muted num">{g.band} / {g.sigim} koyka band</span>
          </div>
          <div className="bar-chiziq">
            <i style={{ width: `${g.sigim ? (g.band / g.sigim) * 100 : 0}%` }} />
          </div>

          <div className="xona-grid">
            {g.xonalar.map((x) => (
              <XonaKart
                key={x.id} x={x} koykalar={koykaMap[x.id] || []}
                rol={rol} can={can}
                bemorga={(k) => setModal({ tur: 'bemor', koyka: k })}
                boshga={boshKoykaga}
                tamirga={tamirga}
              />
            ))}
          </div>
        </div>
      ))}

      {modal?.tur === 'yangi' && (
        <YangiXona bolimlar={bolimlar} turlar={turlar}
          yop={() => setModal(null)}
          tugadi={(m) => { setModal(null); bildir(m); yukla() }} />
      )}
      {modal?.tur === 'bemor' && (
        <KoykaKarta k={modal.koyka} can={can} yop={() => setModal(null)}
          ochish={() => { setModal(null); nav('/bemorlar', { state: { qidir: modal.koyka.telefon } }) }} />
      )}
      {modal?.tur === 'bosh' && (
        <BoshJoy
          k={modal.koyka}
          xonasizlar={xonasizlar}
          joylay={can('joylash')}
          yop={() => setModal(null)}
          joylash={joylash}
          yangi={() => yangiBemor(modal.koyka)} />
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
   XONA KARTASI
   ============================================================ */
function XonaKart({ x, koykalar, rol, can, bemorga, boshga, tamirga }) {
  const bosh = Number(x.sigim) - Number(x.band)
  const jinsPill = x.xona_jinsi
    ? <span className={`pill ${x.xona_jinsi === 'erkak' ? 'booked' : 'full'}`}>
        {x.xona_jinsi === 'erkak' ? 'Erkaklar' : 'Ayollar'}
      </span>
    : null

  return (
    <div className={`card xona-kart${x.tamirlashda ? ' tamir' : ''}`}>
      <div className="xk-bosh">
        <span className="xk-raqam">{x.raqam}</span>
        <div className="xk-meta">
          <div className="row" style={{ gap: 6 }}>
            <span className="pill neutral">{x.turi}</span>
            {jinsPill}
          </div>
          <div className="muted" style={{ marginTop: 3 }}>
            {x.sigim} joylik{can('pul') ? ` · ${som(x.narx)}` : ''}
          </div>
        </div>
        <span className={`pill ${HOLAT_KLASS[x.holat] || 'neutral'}`}>
          {HOLAT_NOM[x.holat] || x.holat}
        </span>
      </div>

      <div className="xk-koykalar">
        {koykalar.map((k) => k.yotqizish_id ? (
          <button key={k.koyka_id}
            className={`koyka-satr band${k.tasdiqlanmagan ? ' ogoh' : ''}`}
            onClick={() => bemorga(k)}>
            <span className="koyka-raqam">{k.koyka}</span>
            <span className={`dot ${k.jins}`} />
            <div className="body">
              <div className="nm">{k.fish}</div>
              <div className="sb">
                {k.roli !== 'bemor' && (k.roli === 'farzand' ? 'Farzand · ' : 'Qarovchi · ')}
                {k.tasdiqlanmagan
                  ? `muddati ${sana(k.reja_chiqish)} da tugagan`
                  : `${k.yotgan_kun}-kun · ${sana(k.reja_chiqish)} gacha`}
              </div>
            </div>
            {can('pul') && Number(k.qarz) > 0 && <span className="pill full">qarz</span>}
          </button>
        ) : (
          <button key={k.koyka_id} className="koyka-satr bosh"
            disabled={x.tamirlashda}
            onClick={() => boshga(k)}>
            <span className="koyka-raqam">{k.koyka}</span>
            <span className="plus">+</span>
            <div className="body"><div className="nm">Boʻsh joy</div></div>
          </button>
        ))}
      </div>

      {(rol === 'super_admin' || rol === 'administrator') && (
        <div className="xk-oyoq">
          <span className="muted">{bosh > 0 ? `${bosh} boʻsh joy` : 'boʻsh joy yoʻq'}</span>
          <span className="sp" />
          {x.tamirlashda ? (
            <button className="btn sm" onClick={() => tamirga(x, false)}>Ishga qaytarish</button>
          ) : (
            <button className="btn sm" disabled={Number(x.band) > 0}
              title={Number(x.band) > 0 ? 'Xonada bemor bor' : undefined}
              onClick={() => tamirga(x, true)}>Taʼmirga qoʻyish</button>
          )}
        </div>
      )}
    </div>
  )
}

/* ============================================================
   BO'SH JOY — kimni joylashtiramiz?
   Avval xonasiz kutayotgan bemorlar, keyin yangi bemor.
   ============================================================ */
function BoshJoy({ k, xonasizlar, joylay, yop, joylash, yangi }) {
  const [band, setBand] = useState(null)
  const jinsli = k.bolim_jinsi && k.bolim_jinsi !== 'aralash'

  const mos = useMemo(
    () => xonasizlar.filter((y) => !jinsli || y.jins === k.bolim_jinsi),
    [xonasizlar, jinsli, k.bolim_jinsi])

  const nomos = xonasizlar.length - mos.length

  async function bosildi(y) {
    setBand(y.yotqizish_id)
    await joylash(y, k)
    setBand(null)
  }

  return (
    <Modal sarlavha={`${k.xona}-xona · ${k.koyka}-koyka`} yop={yop} kenglik={480}
      amallar={<>
        <button className="btn" onClick={yop}>Bekor qilish</button>
        <button className="btn pri" onClick={yangi}>+ Yangi bemor</button>
      </>}>
      <div className="muted" style={{ marginBottom: 12 }}>
        {k.bolim}
        {jinsli && ` · faqat ${k.bolim_jinsi === 'erkak' ? 'erkaklar' : 'ayollar'}`}
      </div>

      {!joylay ? (
        <div className="alert warn"><span>◇</span>
          <div>Sizda bemorni joylashtirish huquqi yoʻq.</div></div>
      ) : mos.length > 0 ? (
        <>
          <div className="field" style={{ marginBottom: 0 }}>
            <label>Xonasiz kutayotgan bemorlar</label>
          </div>
          <div className="bosh-royxat">
            {mos.map((y) => (
              <button key={y.yotqizish_id} className="koyka-satr"
                disabled={band !== null} onClick={() => bosildi(y)}>
                <span className={`dot ${y.jins}`} />
                <div className="body">
                  <div className="nm">{y.fish}</div>
                  <div className="sb">
                    {y.roli !== 'bemor' && (y.roli === 'farzand' ? 'Farzand · ' : 'Qarovchi · ')}
                    {y.yosh} yosh · {sana(y.kirish_sana)} dan
                    {y.asosiy_fish ? ` · ${y.asosiy_fish} bilan` : ''}
                  </div>
                </div>
                <span className="pill free">
                  {band === y.yotqizish_id ? 'joylashmoqda…' : 'joylashtirish'}
                </span>
              </button>
            ))}
          </div>
          <div className="hint" style={{ marginTop: 8 }}>
            Roʻyxatdagi bemorni tanlasangiz shu koykaga biriktiriladi.
            {nomos > 0 && ` Jinsi mos kelmagani uchun ${nomos} ta bemor koʻrsatilmadi.`}
          </div>
        </>
      ) : (
        <div className="bosh-yoq">
          <div className="nm">Xonasiz kutayotgan bemor yoʻq</div>
          <div className="muted">
            {nomos > 0
              ? `Xonasiz ${nomos} ta bemor bor, lekin jinsi bu boʻlimga mos kelmaydi.`
              : 'Bu koykaga yangi bemorni roʻyxatga olib joylashtiring.'}
          </div>
        </div>
      )}
    </Modal>
  )
}

/* ============================================================
   KOYKADAGI BEMOR — qisqa karta
   ============================================================ */
function KoykaKarta({ k, can, yop, ochish }) {
  return (
    <Modal sarlavha={`${k.xona}-xona · ${k.koyka}-koyka`} yop={yop} kenglik={440}
      amallar={<>
        <button className="btn" onClick={yop}>Yopish</button>
        <button className="btn pri" onClick={ochish}>Bemor kartasini ochish</button>
      </>}>
      <div className="karta-bosh">
        <div>
          <h3>{k.fish}</h3>
          <div className="muted">
            {k.jins === 'erkak' ? 'Erkak' : 'Ayol'}
            {k.roli !== 'bemor' && ` · ${k.roli === 'farzand' ? 'Farzand' : 'Qarovchi'}`}
          </div>
        </div>
        {k.tasdiqlanmagan
          ? <span className="pill partial">Tasdiqlanmagan</span>
          : <span className="pill free">Yotibdi</span>}
      </div>

      <dl className="dl">
        <dt>Telefon</dt>
        <dd><a href={`tel:${(k.telefon || '').replace(/\s/g, '')}`}>{k.telefon || '—'}</a></dd>
        <dt>Boʻlim</dt><dd>{k.bolim}</dd>
        <dt>Kirgan</dt><dd>{sana(k.kirish_sana)}</dd>
        <dt>Reja boʻyicha</dt><dd>{sana(k.reja_chiqish)}</dd>
        <dt>Yotgan kun</dt><dd className="num">{k.yotgan_kun}</dd>
        {can('pul') && (<>
          <dt>Qarz</dt>
          <dd className="num" style={{ color: Number(k.qarz) > 0 ? 'var(--full)' : 'var(--ink-3)' }}>
            {som(k.qarz)}
          </dd>
        </>)}
      </dl>

      {k.tasdiqlanmagan && (
        <div className="alert warn" style={{ marginTop: 12 }}>
          <span>◇</span>
          <div>Reja muddati oʻtgan. Bemor kartasidan chiqaring yoki muddatni uzaytiring —
            aks holda u ovqat hisobiga kirmaydi.</div>
        </div>
      )}
    </Modal>
  )
}

/* ============================================================
   YANGI XONA
   ============================================================ */
function YangiXona({ bolimlar, turlar, yop, tugadi }) {
  const [v, setV] = useState({
    bolim_id: bolimlar[0]?.id || '', raqam: '',
    turi: turlar[0]?.turi || 'Standart', sigim: '2'
  })
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)
  const set = (k, x) => setV((s) => ({ ...s, [k]: x }))
  const tur = turlar.find((t) => t.turi === v.turi)

  async function saqla() {
    if (!v.bolim_id) return setXato('Boʻlimni tanlang.')
    if (!v.raqam.trim()) return setXato('Xona raqamini kiriting.')
    if (!(Number(v.sigim) > 0)) return setXato('Koykalar sonini kiriting.')
    setBand(true); setXato('')
    const { error } = await amal.xonaQosh(Number(v.bolim_id), v.raqam.trim(), v.turi, Number(v.sigim))
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    tugadi(`${v.raqam}-xona qoʻshildi.`)
  }

  return (
    <Modal sarlavha="Yangi xona" yop={yop} kenglik={480}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Bekor qilish</button>
        <button className="btn pri" onClick={saqla} disabled={band}>
          {band ? 'Saqlanmoqda…' : 'Qoʻshish'}
        </button>
      </>}>
      {xato && <div className="alert err" style={{ marginBottom: 14 }}><span>▲</span><div>{xato}</div></div>}

      <div className="grid2">
        <div className="field full">
          <label htmlFor="xb">Boʻlim</label>
          <select id="xb" value={v.bolim_id} onChange={(e) => set('bolim_id', e.target.value)}>
            {bolimlar.map((b) => (
              <option key={b.id} value={b.id}>
                {b.nomi}{b.jins !== 'aralash' ? ` (${b.jins === 'erkak' ? 'erkaklar' : 'ayollar'})` : ' (aralash)'}
              </option>
            ))}
          </select>
          <div className="hint">Boʻlimsiz xona boʻlmaydi. Jins qoidasi boʻlimdan kelib chiqadi.</div>
        </div>

        <div className="field">
          <label htmlFor="xr">Xona raqami</label>
          <input id="xr" value={v.raqam} onChange={(e) => set('raqam', e.target.value)} placeholder="16" />
        </div>
        <div className="field">
          <label htmlFor="xs">Koykalar soni</label>
          <input id="xs" type="number" min="1" max="20" value={v.sigim}
            onChange={(e) => set('sigim', e.target.value)} />
        </div>

        <div className="field full">
          <label htmlFor="xt">Xona turi</label>
          <select id="xt" value={v.turi} onChange={(e) => set('turi', e.target.value)}>
            {turlar.map((t) => <option key={t.turi} value={t.turi}>{t.turi}</option>)}
          </select>
          <div className="hint">
            {tur ? `Narxi: ${som(tur.narx)} — turga bogʻlangan, Sozlamalardan oʻzgartiriladi.`
                 : 'Narx xona turiga bogʻlangan.'}
          </div>
        </div>
      </div>
    </Modal>
  )
}
