import { useEffect, useMemo, useState, useCallback, useRef } from 'react'
import { db, xatoMatni } from '../lib/supabase'
import { useAuth, HISOBOT_TABLARI } from '../lib/auth'
import { Kutish } from '../components/Kutish'
import { chopEt } from '../lib/chop'

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
const oyBoshi = () => bugun().slice(0, 8) + '01'
const qisqaSana = (s) => {
  const d = new Date(s)
  return `${d.getDate()}.${String(d.getMonth() + 1).padStart(2, '0')}`
}

const ORALIQ = [
  { k: 'bugun', n: 'Bugun' },
  { k: '7', n: '7 kun' },
  { k: '30', n: '30 kun' },
  { k: 'oy', n: 'Bu oy' },
  { k: 'qol', n: 'Oraliq' }
]
const XATO_MATNI =
  'Hisobot funksiyalari bazada hali oʻrnatilmagan. SQL Editorʼda ' +
  '15_hisobotlar.sql faylini ishga tushiring.'

const TABLAR = [
  { k: 'xulosa', n: 'Xulosa' },
  { k: 'ovqat', n: 'Ovqat hisobi' },
  { k: 'bemorlar', n: 'Bemorlar' },
  { k: 'kassa', n: 'Kassa' },
  { k: 'bolim', n: 'Boʻlimlar' }
]

/* Grafik ranglari. Ikkalasi ham alohida tekshirilgan:
   rang ko'rmaydigan odam uchun ham ajralib turadi (OKLab ΔE),
   fon bilan kontrasti yetarli. Qorong'i uslub — yorug'ining
   aylantirilgani emas, alohida tanlangan. */
const RANG = {
  yorug: ['#3B6FB6', '#C97A0E', '#0E8C72'],
  qorongi: ['#4E86D0', '#BE8A28', '#2F9C7F']
}
const QATLAM = [
  { kalit: 'bemor', nom: 'Bemor' },
  { kalit: 'farzand', nom: 'Farzand' },
  { kalit: 'qarovchi', nom: 'Qarovchi' }
]

export default function Hisobotlar() {
  const { rol } = useAuth()

  /* Rolga tegishli bo'limlar. ruxsat = null bo'lsa — hammasi.
     Faqat ovqat ko'rinadigan rolda pulga oid so'rovlar umuman
     yuborilmaydi: baza ham, ekran ham ularni ko'rmaydi. */
  const ruxsat = HISOBOT_TABLARI[rol] || null
  const tablar = useMemo(
    () => (ruxsat ? TABLAR.filter((t) => ruxsat.includes(t.k)) : TABLAR),
    [rol] // eslint-disable-line react-hooks/exhaustive-deps
  )
  const toliq = !ruxsat

  const [oraliq, setOraliq] = useState('7')
  const [dan, setDan] = useState(qoshKun(bugun(), -6))
  const [gacha, setGacha] = useState(bugun())
  const [tab, setTab] = useState(tablar[0].k)

  /* Rol kech kelsa yoki ro'yxat o'zgarsa — ochiq bo'lmagan
     bo'limda qolib ketmaylik. */
  useEffect(() => {
    if (!tablar.some((t) => t.k === tab)) setTab(tablar[0].k)
  }, [tablar]) // eslint-disable-line react-hooks/exhaustive-deps

  const [d, setD] = useState(null)      // { xulosa, kunlik, ovqat, bemorlar, kassir, bolim, bron }
  const [xato, setXato] = useState('')
  const [yuklanmoqda, setYuklanmoqda] = useState(true)

  /* tugma bosilganda sanalarni qo'yamiz */
  function oraliqTanla(k) {
    setOraliq(k)
    if (k === 'bugun') { setDan(bugun()); setGacha(bugun()) }
    else if (k === '7') { setDan(qoshKun(bugun(), -6)); setGacha(bugun()) }
    else if (k === '30') { setDan(qoshKun(bugun(), -29)); setGacha(bugun()) }
    else if (k === 'oy') { setDan(oyBoshi()); setGacha(bugun()) }
  }

  const yukla = useCallback(async () => {
    setYuklanmoqda(true)

    /* Faqat ovqat hisobi ochiq rol — bitta so'rov yetadi */
    if (!toliq) {
      const o = await db.hisobotOvqat(dan, gacha)
      setYuklanmoqda(false)
      if (o.error) { setXato(XATO_MATNI); return }
      setXato('')
      setD({
        xulosa: null, kunlik: [], ovqat: o.data || [],
        bemorlar: [], kassir: [], bolim: [], bron: []
      })
      return
    }

    const [x, k, o, b, ks, bo, br] = await Promise.all([
      db.hisobotXulosa(dan, gacha),
      db.hisobotKunlik(dan, gacha),
      db.hisobotOvqat(dan, gacha),
      db.hisobotBemorlar(dan, gacha),
      db.hisobotKassir(dan, gacha),
      db.bolimHisoboti(),
      db.hisobotBron(dan, gacha)
    ])
    setYuklanmoqda(false)
    if (x.error) { setXato(XATO_MATNI); return }
    setXato('')
    setD({
      xulosa: (x.data || [])[0] || null,
      kunlik: k.data || [],
      ovqat: o.data || [],
      bemorlar: b.data || [],
      kassir: ks.data || [],
      bolim: (bo.data || []).filter((r) => Number(r.koykalar) > 0),
      bron: br.data || []
    })
  }, [dan, gacha, toliq])

  useEffect(() => { yukla() }, [yukla])

  const kun = useMemo(() => {
    const a = new Date(dan + 'T00:00:00'), b = new Date(gacha + 'T00:00:00')
    return Math.round((b - a) / 86400000) + 1
  }, [dan, gacha])

  function chop() {
    const t = tablar.find((x) => x.k === tab) || TABLAR[0]
    chopEt({
      html: chopHtml(tab, d, dan, gacha),
      css: chopCss,
      sarlavha: `${t.n} — ${sana(dan)} … ${sana(gacha)}`
    })
  }

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>

  return (
    <div className="stack">
      {/* ---------- sana oralig'i ---------- */}
      <div className="chips">
        {ORALIQ.map((o) => (
          <button key={o.k} className={`chip${oraliq === o.k ? ' on' : ''}`}
            onClick={() => oraliqTanla(o.k)}>{o.n}</button>
        ))}
        {oraliq === 'qol' && (
          <>
            <input className="mini" type="date" value={dan} max={gacha}
              onChange={(e) => setDan(e.target.value)} aria-label="Dan" />
            <input className="mini" type="date" value={gacha} min={dan} max={bugun()}
              onChange={(e) => setGacha(e.target.value)} aria-label="Gacha" />
          </>
        )}
        <span className="sp" />
        <button className="btn sm" onClick={chop} disabled={!d}>Chop etish</button>
      </div>

      <div className="muted" style={{ marginTop: -6 }}>
        {sana(dan)} — {sana(gacha)} · {kun} kun
      </div>

      {tablar.length > 1 && (
        <div className="tablar">
          {tablar.map((t) => (
            <button key={t.k} className={`tab${tab === t.k ? ' on' : ''}`}
              onClick={() => setTab(t.k)}>{t.n}</button>
          ))}
        </div>
      )}

      {yuklanmoqda || !d ? <Kutish /> : (
        <>
          {tab === 'xulosa' && <Xulosa d={d} />}
          {tab === 'ovqat' && <Ovqat d={d} />}
          {tab === 'bemorlar' && <Bemorlar d={d} />}
          {tab === 'kassa' && <Kassa d={d} />}
          {tab === 'bolim' && <Bolimlar d={d} />}
        </>
      )}
    </div>
  )
}

/* ============================================================
   XULOSA
   ============================================================ */
function Xulosa({ d }) {
  const x = d.xulosa || {}
  return (
    <>
      <div className="kpis">
        <Kpi v={som(x.tushum)} l="Tushum" rang="g" />
        <Kpi v={x.tolov_soni} l="Toʻlovlar soni" rang="a" />
        <Kpi v={x.yangi_bemor} l="Yangi bemor" rang="b" />
        <Kpi v={x.chiqqan} l="Chiqqan" rang="a" />
        <Kpi v={x.hozir_yotibdi} l="Hozir yotibdi" rang="b" />
        {Number(x.qaytarilgan) > 0 &&
          <Kpi v={som(x.qaytarilgan)} l="Qaytarilgan" rang="r" />}
        {Number(x.qarz_jami) > 0 && <Kpi v={som(x.qarz_jami)} l="Qarzdorlik" rang="r" />}
      </div>

      {Number(x.ortiqcha_jami) > 0 && (
        <div className="alert warn">
          <span>◇</span>
          <div>
            <b>{som(x.ortiqcha_jami)} qaytarilmagan</b> — {x.ortiqcha_soni} ta chiqib ketgan
            bemorda. Bemor rejadan erta ketsa hisob kamayadi, lekin toʻlangan pul joyida
            qoladi. Bu farq bemorniki: bemor kartasidagi “Toʻlov tarixi” dan qaytariladi
            (yoki admin sabab yozib xizmat hisobiga oʻtkazadi). Roʻyxat — pastdagi
            “Bemorlar” boʻlimida, <b>Ortiqcha toʻlov</b> filtri.
          </div>
        </div>
      )}

      <Grafik kunlik={d.kunlik} ovqat={d.ovqat} />

      <div className="card">
        <div className="bolim-bosh" style={{ padding: '12px 15px 0' }}>
          <h4>Kunlik jadval</h4>
        </div>
        <div className="jadval-o">
          <table>
            <thead>
              <tr>
                <th>Sana</th><th className="r">Keldi</th><th className="r">Ketdi</th>
                <th className="r">Yotgan</th><th className="r">Qarovchi</th>
                <th className="r">Ovqat</th><th className="r">Tushum</th>
              </tr>
            </thead>
            <tbody>
              {d.kunlik.map((r, i) => {
                const ov = d.ovqat.find((o) => o.sana === r.sana)
                return (
                  <tr key={r.sana}>
                    <td className="num">{sana(r.sana)}</td>
                    <td className="r num">{r.keldi}</td>
                    <td className="r num">{r.ketdi}</td>
                    <td className="r num"><b>{r.yotgan}</b></td>
                    <td className="r num muted">{r.shundan_qarovchi}</td>
                    <td className="r num">{ov ? ov.jami_porsiya : '—'}</td>
                    <td className="r num">{Number(r.tushum) ? son(r.tushum) : '—'}</td>
                  </tr>
                )
              })}
            </tbody>
            <tfoot>
              <tr>
                <td>Jami</td>
                <td className="r num">{d.kunlik.reduce((s, r) => s + Number(r.keldi), 0)}</td>
                <td className="r num">{d.kunlik.reduce((s, r) => s + Number(r.ketdi), 0)}</td>
                <td className="r">—</td><td className="r">—</td>
                <td className="r num">{d.ovqat.reduce((s, r) => s + Number(r.jami_porsiya), 0)}</td>
                <td className="r num">{son(d.kunlik.reduce((s, r) => s + Number(r.tushum), 0))}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>

      {d.bron.length > 0 && (
        <div className="card">
          <div className="bolim-bosh" style={{ padding: '12px 15px 0' }}><h4>Bronlar</h4></div>
          <div className="jadval-o">
            <table>
              <thead><tr><th>Holat</th><th className="r">Soni</th><th className="r">Kishi</th></tr></thead>
              <tbody>
                {d.bron.map((r) => (
                  <tr key={r.holat}>
                    <td>{r.holat}</td>
                    <td className="r num">{r.soni}</td>
                    <td className="r num">{son(r.kishi)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </>
  )
}

/* ============================================================
   GRAFIK — kunlik bandlik (rol boʻyicha) va tushum
   ============================================================ */
function Grafik({ kunlik, ovqat }) {
  const [qorongi, setQorongi] = useState(false)
  const [ustida, setUstida] = useState(null)
  const ram = useRef(null)

  /* uslub o'zgarsa ranglar ham o'zgarsin */
  useEffect(() => {
    const tekshir = () => {
      const t = document.documentElement.dataset.theme
      setQorongi(t === 'dark' ||
        (!t && window.matchMedia('(prefers-color-scheme: dark)').matches))
    }
    tekshir()
    const ob = new MutationObserver(tekshir)
    ob.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    return () => ob.disconnect()
  }, [])

  const ranglar = qorongi ? RANG.qorongi : RANG.yorug
  const qator = useMemo(() => ovqat.map((o) => ({
    sana: o.sana,
    bemor: Number(o.bemor), farzand: Number(o.farzand), qarovchi: Number(o.qarovchi),
    jami: Number(o.jami_kishi),
    tushum: Number((kunlik.find((k) => k.sana === o.sana) || {}).tushum || 0)
  })), [ovqat, kunlik])

  if (qator.length === 0) return null

  const eng = Math.max(1, ...qator.map((r) => r.jami))
  const engPul = Math.max(1, ...qator.map((r) => r.tushum))
  const kengBar = qator.length > 20 ? 1 : qator.length > 10 ? 2 : 3

  return (
    <div className="card grafik-karta">
      <div className="bolim-bosh" style={{ padding: '12px 15px 0' }}>
        <h4>Kunlik bandlik</h4>
        <span className="sp" />
        <div className="legend">
          {QATLAM.map((q, i) => (
            <span key={q.kalit}>
              <i style={{ background: ranglar[i] }} />{q.nom}
            </span>
          ))}
        </div>
      </div>

      <div className="grafik" ref={ram}
        onMouseLeave={() => setUstida(null)}>
        <div className="oq">
          <span>{eng}</span><span>{Math.round(eng / 2)}</span><span>0</span>
        </div>
        <div className="ustunlar">
          {qator.map((r, i) => (
            <div key={r.sana} className={`ustun${ustida === i ? ' on' : ''}`}
              onMouseEnter={() => setUstida(i)}
              onFocus={() => setUstida(i)}
              tabIndex={0}
              aria-label={`${sana(r.sana)}: jami ${r.jami} kishi`}>
              <div className="taxta">
                {QATLAM.map((q, j) => r[q.kalit] > 0 && (
                  <i key={q.kalit}
                    style={{
                      height: `${(r[q.kalit] / eng) * 100}%`,
                      background: ranglar[j]
                    }} />
                )).filter(Boolean).reverse()}
              </div>
              {/* Yorliq doim chiziladi — aks holda sanasiz ustunlar
                  balandroq boʻlib, taqqoslash buziladi */}
              <span className="lab">
                {(qator.length <= 10 || i % Math.ceil(qator.length / 8) === 0)
                  ? qisqaSana(r.sana) : ' '}
              </span>
            </div>
          ))}
        </div>

        {ustida != null && qator[ustida] && (
          /* Chap yarmida boʻlsa oʻngga, oʻng yarmida boʻlsa chapga
             suramiz — quti oʻzi tasvirlayotgan ustunni yopmasin */
          <div className={`ip${(ustida + 0.5) / qator.length > 0.5 ? ' chap' : ''}`}
            style={{ left: `${((ustida + 0.5) / qator.length) * 100}%` }}>
            <div className="quti">
              <b>{sana(qator[ustida].sana)}</b>
              {QATLAM.map((q, j) => (
                <span key={q.kalit}>
                  <i style={{ background: ranglar[j] }} />
                  {q.nom}: <b>{qator[ustida][q.kalit]}</b>
                </span>
              ))}
              <span className="jm">Jami: <b>{qator[ustida].jami}</b> kishi</span>
              <span className="jm">Tushum: <b>{son(qator[ustida].tushum)}</b></span>
            </div>
          </div>
        )}
      </div>

      {engPul > 1 && (
        <>
          <div className="bolim-bosh" style={{ padding: '4px 15px 0' }}>
            <h4>Kunlik tushum</h4>
            <span className="sp" />
            <span className="muted num">eng yuqori: {son(engPul)} soʻm</span>
          </div>
          <div className="grafik tushum">
            <div className="ustunlar">
              {qator.map((r, i) => (
                <div key={r.sana} className={`ustun${ustida === i ? ' on' : ''}`}
                  onMouseEnter={() => setUstida(i)} tabIndex={-1}
                  aria-label={`${sana(r.sana)}: ${son(r.tushum)} soʻm`}>
                  <div className="taxta">
                    {r.tushum > 0 && (
                      <i style={{
                        height: `${(r.tushum / engPul) * 100}%`,
                        background: qorongi ? '#2F9C7F' : '#0E8C72'
                      }} />
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </>
      )}

      <div className="hint" style={{ padding: '0 15px 12px' }}>
        Ustun ustiga kursorni olib borsangiz oʻsha kunning raqamlari chiqadi.
        Barcha sonlar pastdagi jadvalda ham bor.
      </div>
    </div>
  )
}

/* ============================================================
   OVQAT HISOBI
   ============================================================ */
function Ovqat({ d }) {
  const j = d.ovqat.reduce((s, r) => ({
    nonushta: s.nonushta + Number(r.nonushta),
    tushlik: s.tushlik + Number(r.tushlik),
    kechki: s.kechki + Number(r.kechki),
    jami: s.jami + Number(r.jami_porsiya),
    qarovchi: s.qarovchi + Number(r.qarovchi),
    farzand: s.farzand + Number(r.farzand),
    bemor: s.bemor + Number(r.bemor),
    kishi: s.kishi + Number(r.jami_kishi)
  }), {
    nonushta: 0, tushlik: 0, kechki: 0, jami: 0,
    qarovchi: 0, farzand: 0, bemor: 0, kishi: 0
  })

  return (
    <>
      <div className="kpis">
        <Kpi v={j.jami} l="Jami porsiya" rang="g" />
        <Kpi v={j.nonushta} l="Nonushta" rang="a" />
        <Kpi v={j.tushlik} l="Tushlik" rang="a" />
        <Kpi v={j.kechki} l="Kechki" rang="a" />
        <Kpi v={j.qarovchi + j.farzand} l="Shundan qarovchi va farzand (kun/kishi)" rang="b" />
      </div>

      <div className="alert info" style={{ display: 'block' }}>
        <b>Qarovchi va farzand ham ovqat oladi — hammasi shu hisobda.</b>
        <p className="muted" style={{ margin: '4px 0 0' }}>
          Har uch ustun — bemor, farzand, qarovchi — birga sanaladi, oshxonaga
          shu raqamlar beriladi.
        </p>
        <p className="muted" style={{ margin: '6px 0 0' }}>
          <b>Nonushta</b> — oʻsha kuni <b>kelganlardan</b> boshqa hamma
          (kelgan kuni nonushta yoʻq). <b>Tushlik</b> — oʻsha kuni yotgan
          hamma. <b>Kechki</b> — oʻsha kuni <b>ketganlardan</b> boshqa hamma.
          Shuning uchun uch raqam bir xil chiqmaydi.
        </p>
        <p className="muted" style={{ margin: '6px 0 0' }}>
          Hisob haqiqiy chiqish sanasi boʻyicha boradi: bemor rejadan erta
          ketsa, oʻsha kundan keyin ovqat hisobiga umuman kirmaydi.
        </p>
      </div>

      <div className="card">
        <div className="jadval-o">
          <table>
            <thead>
              <tr>
                <th>Sana</th>
                <th className="r">Bemor</th><th className="r">Farzand</th>
                <th className="r">Qarovchi</th><th className="r">Jami kishi</th>
                <th className="r">Nonushta</th><th className="r">Tushlik</th>
                <th className="r">Kechki</th><th className="r">Porsiya</th>
              </tr>
            </thead>
            <tbody>
              {d.ovqat.map((r) => (
                <tr key={r.sana}>
                  <td className="num">{sana(r.sana)}</td>
                  <td className="r num">{r.bemor}</td>
                  <td className="r num">{r.farzand}</td>
                  <td className="r num">{r.qarovchi}</td>
                  <td className="r num"><b>{r.jami_kishi}</b></td>
                  <td className="r num muted">{r.nonushta}</td>
                  <td className="r num muted">{r.tushlik}</td>
                  <td className="r num muted">{r.kechki}</td>
                  <td className="r num"><b>{r.jami_porsiya}</b></td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr>
                <td>Jami (kun/kishi)</td>
                <td className="r num">{j.bemor}</td>
                <td className="r num">{j.farzand}</td>
                <td className="r num">{j.qarovchi}</td>
                <td className="r num"><b>{j.kishi}</b></td>
                <td className="r num">{j.nonushta}</td>
                <td className="r num">{j.tushlik}</td>
                <td className="r num">{j.kechki}</td>
                <td className="r num"><b>{j.jami}</b></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>
    </>
  )
}

/* ============================================================
   BEMORLAR
   ============================================================ */
function Bemorlar({ d }) {
  const [f, setF] = useState('')
  const royxat = useMemo(() => d.bemorlar.filter((r) => {
    if (f === 'qarz' && !(Number(r.qarz) > 0)) return false
    if (f === 'ortiqcha' && !(Number(r.ortiqcha) > 0)) return false
    if (f === 'chiqdi' && r.holat !== 'chiqdi') return false
    if (f === 'yotmoqda' && r.holat !== 'yotmoqda') return false
    return true
  }), [d.bemorlar, f])

  const ortiqcha = d.bemorlar.filter((r) => Number(r.ortiqcha) > 0).length

  return (
    <>
      <div className="chips">
        {[
          { k: '', n: `Hammasi (${d.bemorlar.length})` },
          { k: 'yotmoqda', n: 'Yotmoqda' },
          { k: 'chiqdi', n: 'Chiqqan' },
          { k: 'qarz', n: 'Qarzdor' },
          ...(ortiqcha ? [{ k: 'ortiqcha', n: `Ortiqcha toʻlov (${ortiqcha})` }] : [])
        ].map((x) => (
          <button key={x.k} className={`chip${f === x.k ? ' on' : ''}`}
            onClick={() => setF(x.k)}>{x.n}</button>
        ))}
      </div>

      <div className="card">
        <div className="jadval-o">
          <table>
            <thead>
              <tr>
                <th>Bemor</th><th>Xona</th><th>Kirgan</th><th>Chiqqan</th>
                <th className="r">Kun</th><th className="r">Hisob</th>
                <th className="r">Toʻlangan</th><th className="r">Qarz</th>
              </tr>
            </thead>
            <tbody>
              {royxat.length === 0 ? (
                <tr><td colSpan={8} className="muted" style={{ padding: 18 }}>
                  Bu filtr boʻyicha yozuv yoʻq.</td></tr>
              ) : royxat.map((r) => (
                <tr key={r.yotqizish_id}>
                  <td>
                    <div className="nm">{r.fish}</div>
                    <div className="sb">
                      <span className={`dot ${r.jins}`} />
                      {r.roli !== 'bemor' && (r.roli === 'farzand' ? 'Farzand · ' : 'Qarovchi · ')}
                      {r.telefon}
                    </div>
                  </td>
                  <td>{r.xona}</td>
                  <td className="num">{sana(r.kirish_sana)}</td>
                  <td className="num">
                    {r.haqiqiy_chiqish
                      ? sana(r.haqiqiy_chiqish)
                      : <span className="muted">{sana(r.reja_chiqish)} (reja)</span>}
                  </td>
                  <td className="r num">{r.yotgan_kun}</td>
                  <td className="r num">{son(r.umumiy)}</td>
                  <td className="r num" style={{ color: 'var(--free)' }}>{son(r.tolangan)}</td>
                  <td className="r num">
                    {Number(r.qarz) > 0
                      ? <b style={{ color: 'var(--full)' }}>{son(r.qarz)}</b>
                      : Number(r.ortiqcha) > 0
                        ? <span className="pill partial">+{son(r.ortiqcha)}</span>
                        : <span className="muted">0</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {ortiqcha > 0 && (
        <div className="hint">
          <span className="pill partial">+summa</span> — bemor hisobdan ortiq toʻlagan.
          Erta ketgani uchun hisob kamaygan, farq qaytarilishi kerak.
        </div>
      )}
    </>
  )
}

/* ============================================================
   KASSA
   ============================================================ */
function Kassa({ d }) {
  const x = d.xulosa || {}
  const usullar = [
    { n: 'Naqd', v: Number(x.naqd) },
    { n: 'Plastik karta', v: Number(x.karta) },
    { n: 'Oʻtkazma', v: Number(x.otkazma) }
  ]
  const jami = Number(x.tushum) || 0
  /* 24_qaytarish.sql: qaytarilgan pul alohida ustunda keladi */
  const qaytarilgan = Number(x.qaytarilgan) || 0

  return (
    <>
      <div className="kpis">
        <Kpi v={som(x.tushum)} l="Jami tushum" rang="g" />
        <Kpi v={x.tolov_soni} l="Toʻlovlar soni" rang="a" />
        <Kpi v={jami && x.tolov_soni ? som(Math.round(jami / x.tolov_soni)) : '—'}
          l="Oʻrtacha toʻlov" rang="b" />
        {qaytarilgan > 0 && <>
          <Kpi v={som(qaytarilgan)} l="Qaytarilgan" rang="r" />
          <Kpi v={som(jami - qaytarilgan)} l="Sof tushum" rang="g" />
        </>}
      </div>

      {qaytarilgan > 0 && (
        <div className="alert info" style={{ display: 'block' }}>
          <b>{som(qaytarilgan)} bemorlarga qaytarilgan</b> — {x.qaytarish_soni} marta.
          <p className="muted" style={{ margin: '4px 0 0' }}>
            Tushum ustunlari faqat kirimni koʻrsatadi. Kassadagi haqiqiy pul —
            tushumdan qaytarilgani ayirilgani: <b>{som(jami - qaytarilgan)}</b>.
          </p>
        </div>
      )}

      <div className="card">
        <div className="bolim-bosh" style={{ padding: '12px 15px 0' }}>
          <h4>Toʻlov usullari</h4>
        </div>
        <div className="narx-royxat">
          {usullar.map((u) => (
            <div className="narx-qator" key={u.n}>
              <div className="body">
                <b>{u.n}</b>
                <div className="bar-chiziq" style={{ marginTop: 6 }}>
                  <i style={{ width: `${jami ? (u.v / jami) * 100 : 0}%` }} />
                </div>
              </div>
              <span className="num">{som(u.v)}</span>
              <span className="muted num" style={{ minWidth: 46, textAlign: 'right' }}>
                {jami ? Math.round((u.v / jami) * 100) : 0}%
              </span>
            </div>
          ))}
        </div>
      </div>

      <div className="card">
        <div className="bolim-bosh" style={{ padding: '12px 15px 0' }}>
          <h4>Kassirlar kesimi</h4>
        </div>
        <div className="jadval-o">
          <table>
            <thead><tr><th>Kassir</th><th className="r">Toʻlovlar</th><th className="r">Jami</th></tr></thead>
            <tbody>
              {d.kassir.length === 0 ? (
                <tr><td colSpan={3} className="muted" style={{ padding: 18 }}>
                  Bu oraliqda toʻlov boʻlmagan.</td></tr>
              ) : d.kassir.map((r) => (
                <tr key={r.kassir}>
                  <td>{r.kassir}</td>
                  <td className="r num">{r.tolovlar}</td>
                  <td className="r num">{som(r.jami)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  )
}

/* ============================================================
   BO'LIMLAR
   ============================================================ */
function Bolimlar({ d }) {
  return (
    <div className="card">
      <div className="bolim-bosh" style={{ padding: '12px 15px 0' }}>
        <h4>Boʻlimlar bandligi</h4>
        <span className="sp" />
        <span className="muted">hozirgi holat</span>
      </div>
      <div className="narx-royxat">
        {d.bolim.length === 0 ? (
          <div className="narx-qator"><span className="muted">Koykali boʻlim yoʻq.</span></div>
        ) : d.bolim.map((r) => (
          <div className="narx-qator" key={r.bolim}>
            <div className="body">
              <b>{r.bolim}</b>
              <div className="muted">
                {r.xonalar} xona · {r.koykalar} koyka · {r.band_koyka} band
              </div>
              <div className="bar-chiziq" style={{ marginTop: 6 }}>
                <i style={{ width: `${Number(r.bandlik_foiz) || 0}%` }} />
              </div>
            </div>
            <span className="num" style={{ minWidth: 54, textAlign: 'right' }}>
              {Number(r.bandlik_foiz) || 0}%
            </span>
          </div>
        ))}
      </div>
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
   CHOP ETISH
   ============================================================ */
const chopCss = `
@page { size: A4 landscape; margin: 12mm; }
body { font: 11px/1.4 "Times New Roman", Georgia, serif; color: #000; margin: 0 }
h1 { font-size: 15px; margin: 0 0 2mm }
.oraliq { font-size: 11px; color: #333; margin-bottom: 4mm }
table { width: 100%; border-collapse: collapse; margin-bottom: 5mm }
th, td { border: 1px solid #888; padding: 2px 4px; text-align: left }
th { background: #eee; font-size: 10px }
td.o, th.o { text-align: right }
tfoot td { font-weight: 700; background: #f4f4f4 }
.kartalar { display: flex; flex-wrap: wrap; gap: 3mm; margin-bottom: 5mm }
.kartalar div { border: 1px solid #888; padding: 2mm 3mm; min-width: 34mm }
.kartalar b { display: block; font-size: 13px }
.kartalar span { font-size: 9px; color: #444 }
`

function jadval(sarlavhalar, qatorlar, oyoq) {
  const th = sarlavhalar.map((s) =>
    `<th class="${s.o ? 'o' : ''}">${s.n}</th>`).join('')
  const tb = qatorlar.map((r) =>
    '<tr>' + r.map((c, i) =>
      `<td class="${sarlavhalar[i]?.o ? 'o' : ''}">${c ?? ''}</td>`).join('') + '</tr>').join('')
  const tf = oyoq
    ? '<tfoot><tr>' + oyoq.map((c, i) =>
        `<td class="${sarlavhalar[i]?.o ? 'o' : ''}">${c ?? ''}</td>`).join('') + '</tr></tfoot>'
    : ''
  return `<table><thead><tr>${th}</tr></thead><tbody>${tb}</tbody>${tf}</table>`
}

function chopHtml(tab, d, dan, gacha) {
  if (!d) return ''
  const bosh = (nom) =>
    `<h1>${nom}</h1><div class="oraliq">Muhiddin Tabib — boshqaruv tizimi · ` +
    `${sana(dan)} — ${sana(gacha)}</div>`
  const x = d.xulosa || {}

  if (tab === 'ovqat') {
    const j = d.ovqat.reduce((s, r) => ({
      n: s.n + Number(r.nonushta), t: s.t + Number(r.tushlik),
      k: s.k + Number(r.kechki), p: s.p + Number(r.jami_porsiya),
      b: s.b + Number(r.bemor), f: s.f + Number(r.farzand),
      q: s.q + Number(r.qarovchi), ki: s.ki + Number(r.jami_kishi)
    }), { n: 0, t: 0, k: 0, p: 0, b: 0, f: 0, q: 0, ki: 0 })
    return bosh('Ovqat hisoboti') +
      `<div class="oraliq">Bemor, farzand va qarovchi — hammasi sanalgan. ` +
      `Nonushta: oʻsha kuni kelganlarsiz · Tushlik: hamma · ` +
      `Kechki: oʻsha kuni ketganlarsiz.</div>` + jadval(
      [{ n: 'Sana' }, { n: 'Bemor', o: 1 }, { n: 'Farzand', o: 1 }, { n: 'Qarovchi', o: 1 },
       { n: 'Jami kishi', o: 1 }, { n: 'Nonushta', o: 1 }, { n: 'Tushlik', o: 1 },
       { n: 'Kechki', o: 1 }, { n: 'Porsiya', o: 1 }],
      d.ovqat.map((r) => [sana(r.sana), r.bemor, r.farzand, r.qarovchi,
        r.jami_kishi, r.nonushta, r.tushlik, r.kechki, r.jami_porsiya]),
      ['Jami (kun/kishi)', j.b, j.f, j.q, j.ki, j.n, j.t, j.k, j.p])
  }

  if (tab === 'bemorlar') {
    return bosh('Bemorlar hisoboti') + jadval(
      [{ n: 'Bemor' }, { n: 'Tel' }, { n: 'Xona' }, { n: 'Kirgan' }, { n: 'Chiqqan' },
       { n: 'Kun', o: 1 }, { n: 'Hisob', o: 1 }, { n: 'Toʻlangan', o: 1 }, { n: 'Qarz', o: 1 }],
      d.bemorlar.map((r) => [r.fish, r.telefon, r.xona, sana(r.kirish_sana),
        r.haqiqiy_chiqish ? sana(r.haqiqiy_chiqish) : '—',
        r.yotgan_kun, son(r.umumiy), son(r.tolangan), son(r.qarz)]))
  }

  if (tab === 'kassa') {
    return bosh('Kassa hisoboti') +
      `<div class="kartalar">
        <div><b>${som(x.tushum)}</b><span>Jami tushum</span></div>
        <div><b>${som(x.naqd)}</b><span>Naqd</span></div>
        <div><b>${som(x.karta)}</b><span>Karta</span></div>
        <div><b>${som(x.otkazma)}</b><span>Oʻtkazma</span></div>
        <div><b>${x.tolov_soni}</b><span>Toʻlovlar soni</span></div>
      </div>` + jadval(
      [{ n: 'Kassir' }, { n: 'Toʻlovlar', o: 1 }, { n: 'Jami', o: 1 }],
      d.kassir.map((r) => [r.kassir, r.tolovlar, son(r.jami)]))
  }

  if (tab === 'bolim') {
    return bosh('Boʻlimlar bandligi') + jadval(
      [{ n: 'Boʻlim' }, { n: 'Xonalar', o: 1 }, { n: 'Koykalar', o: 1 },
       { n: 'Band', o: 1 }, { n: 'Bandlik %', o: 1 }],
      d.bolim.map((r) => [r.bolim, r.xonalar, r.koykalar, r.band_koyka,
        (Number(r.bandlik_foiz) || 0) + '%']))
  }

  /* xulosa */
  return bosh('Xulosa hisoboti') +
    `<div class="kartalar">
      <div><b>${som(x.tushum)}</b><span>Tushum</span></div>
      <div><b>${x.tolov_soni}</b><span>Toʻlovlar</span></div>
      <div><b>${x.yangi_bemor}</b><span>Yangi bemor</span></div>
      <div><b>${x.chiqqan}</b><span>Chiqqan</span></div>
      <div><b>${x.ortacha_kun ?? '—'}</b><span>Oʻrtacha kun</span></div>
      <div><b>${x.hozir_yotibdi}</b><span>Hozir yotibdi</span></div>
      <div><b>${som(x.qarz_jami)}</b><span>Qarzdorlik</span></div>
      ${Number(x.ortiqcha_jami) > 0
        ? `<div><b>${som(x.ortiqcha_jami)}</b><span>Ortiqcha toʻlov</span></div>` : ''}
    </div>` + jadval(
    [{ n: 'Sana' }, { n: 'Keldi', o: 1 }, { n: 'Ketdi', o: 1 }, { n: 'Yotgan', o: 1 },
     { n: 'Qarovchi', o: 1 }, { n: 'Ovqat', o: 1 }, { n: 'Tushum', o: 1 }],
    d.kunlik.map((r) => {
      const ov = d.ovqat.find((o) => o.sana === r.sana)
      return [sana(r.sana), r.keldi, r.ketdi, r.yotgan, r.shundan_qarovchi,
        ov ? ov.jami_porsiya : '', son(r.tushum)]
    }),
    ['Jami',
     d.kunlik.reduce((s, r) => s + Number(r.keldi), 0),
     d.kunlik.reduce((s, r) => s + Number(r.ketdi), 0), '', '',
     d.ovqat.reduce((s, r) => s + Number(r.jami_porsiya), 0),
     son(d.kunlik.reduce((s, r) => s + Number(r.tushum), 0))])
}
