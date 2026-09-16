import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { db, xatoMatni } from '../lib/supabase'
import { Kutish } from '../components/Kutish'
import { useAuth } from '../lib/auth'
import { chopEt, kunVaqt } from '../lib/chop'
import { chekHtml, chekCss } from '../print/chek'

const som = (n) => (Math.round(n) || 0).toLocaleString('ru-RU').replace(/\u00A0/g, ' ') + ' soʻm'
const son = (n) => (n ?? 0).toLocaleString('ru-RU').replace(/\u00A0/g, ' ')
const sanaQisqa = (s) => {
  if (!s) return '\u2014'
  const d = new Date(s + 'T00:00:00')
  return `${d.getDate()}.${String(d.getMonth() + 1).padStart(2, '0')}`
}

function Kpi({ v, l, rang = 'a', pul, bos, on }) {
  if (!bos) {
    return (
      <div className={`kpi ${rang}`}>
        <span className="bar" />
        <div className={`v num ${pul ? 'money' : ''}`}>{v}</div>
        <div className="l">{l}</div>
      </div>
    )
  }
  return (
    <button type="button" className={`kpi bos ${rang}${on ? ' on' : ''}`} onClick={bos}>
      <span className="bar" />
      <div className={`v num ${pul ? 'money' : ''}`}>{v}</div>
      <div className="l">{l}</div>
    </button>
  )
}

/* ============================================================
   DASHBOARD
   Buxgalterga kassa ko'rinishi, qolganlarga to'liq ko'rinish.
   ============================================================ */
export default function Dashboard() {
  const { rol } = useAuth()
  return rol === 'buxgalter' ? <Kassa /> : <Toliq />
}

function Toliq() {
  const { can } = useAuth()
  const nav = useNavigate()
  const [u, setU] = useState(null)
  const [qarzdorlar, setQarzdorlar] = useState([])
  const [konflikt, setKonflikt] = useState([])
  const [bolimlar, setBolimlar] = useState([])
  const [bronlar, setBronlar] = useState([])
  const [yotganlar, setYotganlar] = useState([])
  const [xato, setXato] = useState('')

  useEffect(() => {
    let bekor = false
    ;(async () => {
      try {
        const [a, b, c, d, e, f] = await Promise.all([
          db.umumiy(), db.qarzdorlar(), db.bronKonfliktlari(), db.bolimHisoboti(),
          db.bronlar({ holat: 'kutilmoqda' }),
          db.yotqizishlar({ holat: 'yotmoqda' })
        ])
        if (bekor) return
        const x = a.error || b.error || c.error || d.error
        if (x) throw x
        setU(a.data); setQarzdorlar(b.data || [])
        setKonflikt(c.data || []); setBolimlar(d.data || [])
        /* Bronlar bazada hali o'rnatilmagan bo'lsa — dashboard
           shundan yiqilmasin, shunchaki ro'yxat bo'sh bo'ladi. */
        setBronlar(e.error ? [] : (e.data || []))
        setYotganlar(f.error ? [] : (f.data || []))
      } catch (err) {
        if (!bekor) setXato(xatoMatni(err))
      }
    })()
    return () => { bekor = true }
  }, [])

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>
  if (!u) return <Kutish />

  return (
    <div className="stack">
      <div className="kpis">
        <Kpi v={son(u.hozir_yotmoqda)} l="Hozir yotmoqda" rang="g" />
        <Kpi v={son(u.bugun_keldi)} l="Bugun keldi" rang="a" />
        <Kpi v={son(u.bugun_ketishi_kerak)} l="Bugun ketishi kerak" rang="o" />
        <Kpi v={son(u.bosh_xona)} l="Boʻsh xona" rang="g" />
        <Kpi v={son(u.band_xona)} l="Band xona" rang="r" />
        <Kpi v={son(u.bron)} l="Bron" rang="b" />
        {can('pul') && <Kpi v={son(u.qarzdor_soni)} l="Qarzdor bemor" rang="r" />}
        {can('pul') && <Kpi v={som(u.bugungi_tushum)} l="Bugungi tushum" rang="a" pul />}
      </div>

      {u.xonasiz > 0 && (
        <div className="alert info">
          <span>◇</span>
          <div><b>{u.xonasiz} ta bemor xonaga joylashtirilmagan.</b> Ular xona band
            qilmagan holda roʻyxatda turibdi.</div>
        </div>
      )}

      {konflikt.length > 0 && (
        <div className="alert err">
          <span>▲</span>
          <div>
            <b>Bron konflikti aniqlandi.</b>
            {konflikt.map((k) => (
              <div key={k.bron_id} style={{ marginTop: 4 }}>
                {k.xona}-xona {new Date(k.bron_kirish).toLocaleDateString('ru-RU')} kuni{' '}
                <b>{k.bron_bemor}</b> uchun bron qilingan, hozirgi bemor{' '}
                {k.hozirgi_bemor} {new Date(k.hozirgi_chiqish).toLocaleDateString('ru-RU')} gacha yotadi.
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Ketadiganlar roʻyxati — hisob-kitobni yopadiganlarga:
          admin, kassir va kuzatuvchi. Registratorda chiqarish
          ham, pul ham yoʻq — unga bu roʻyxat keraksiz. */}
      {(can('chiqar') || can('pul')) && (
        <BugunKetadi royxat={yotganlar} pul={can('pul')}
          ochish={(r) => nav('/bemorlar', { state: { qidir: r.telefon || r.fish } })} />
      )}

      <BugunKeladi bronlar={bronlar} can={can}
        qabul={(b) => nav('/bemorlar', { state: { bron: b } })} />

      {can('pul') && <div className="card">
        <div className="card-h">
          <h3>Qarzdor bemorlar</h3>
          <span className="sp" />
          <span className="pill full num">{som(u.qarz_jami)}</span>
        </div>
        {qarzdorlar.length ? (
          <table className="mobil-karta">
            <thead>
              <tr><th>Bemor</th><th>Xona</th><th className="r">Umumiy</th>
                <th className="r">Toʻlangan</th><th className="r">Qarz</th></tr>
            </thead>
            <tbody>
              {qarzdorlar.map((q) => (
                <tr key={q.yotqizish_id}>
                  <td className="bosh" style={{ fontWeight: 500 }}>{q.fish}</td>
                  <td className="num" data-l="Xona">{q.xona}</td>
                  <td className="r num" data-l="Umumiy">{son(q.umumiy)}</td>
                  <td className="r num" data-l="Toʻlangan"
                    style={{ color: 'var(--free)' }}>{son(q.tolangan)}</td>
                  <td className="r num" data-l="Qarz"
                    style={{ color: 'var(--full)', fontWeight: 600 }}>
                    {son(q.qarz)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : <div className="card-b muted">Qarzdorlik yoʻq.</div>}
      </div>}

      <div className="card">
        <div className="card-h"><h3>Boʻlimlar boʻyicha bandlik</h3></div>
        <div className="card-b stack" style={{ gap: 12 }}>
          {bolimlar.map((b) => (
            <div key={b.bolim}>
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <span style={{ fontWeight: 500 }}>{b.bolim}</span>
                <span className="muted num">{b.band_koyka} / {b.koykalar} koyka</span>
              </div>
              <div style={{ height: 6, background: 'var(--line-2)', borderRadius: 4,
                marginTop: 7, overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${b.bandlik_foiz || 0}%`,
                  background: 'var(--accent)' }} />
              </div>
            </div>
          ))}
        </div>
      </div>

      {can('pul') && (
        <div className="row">
          <span className="muted">Shu oydagi tushum:</span>
          <span className="pill neutral num">{som(u.oylik_tushum)}</span>
        </div>
      )}
    </div>
  )
}

/* ============================================================
   KASSA KOʻRINISHI — buxgalter uchun

   Tepada uchta raqam: qarzdor bemor, bugungi tushum, umumiy
   qarz. Har birining ustiga bosilsa, keragi ochiladi.
   Pastda — toʻlovlar: kim, qancha, qanday va qachon toʻlagan.
   ============================================================ */
const USUL_NOM = { naqd: 'Naqd', karta: 'Plastik karta', otkazma: 'Oʻtkazma' }

const bugunSana = () => {
  const d = new Date()
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
}
const kunQosh = (s, n) => {
  const d = new Date(s + 'T00:00:00')
  d.setDate(d.getDate() + n)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
}
const oyBoshi = () => bugunSana().slice(0, 8) + '01'

const DAVRLAR = [
  { k: 'bugun', n: 'Bugun',       oraliq: () => [bugunSana(), bugunSana()] },
  { k: 'kecha', n: 'Kecha',       oraliq: () => [kunQosh(bugunSana(), -1), kunQosh(bugunSana(), -1)] },
  { k: 'hafta', n: 'Oxirgi 7 kun', oraliq: () => [kunQosh(bugunSana(), -6), bugunSana()] },
  { k: 'oy',    n: 'Shu oy',      oraliq: () => [oyBoshi(), bugunSana()] }
]

function Kassa() {
  const nav = useNavigate()
  const [u, setU] = useState(null)
  const [qarzdorlar, setQarzdorlar] = useState([])
  const [yotganlar, setYotganlar] = useState([])
  const [tolovlar, setTolovlar] = useState(null)
  const [davr, setDavr] = useState('bugun')
  const [ochiq, setOchiq] = useState(null)      // 'qarzdor' yoki null
  const [xato, setXato] = useState('')
  const [xabar, setXabar] = useState('')

  const bildir = (m) => { setXabar(m); setTimeout(() => setXabar(''), 4000) }

  /* tepadagi raqamlar — bir marta */
  useEffect(() => {
    let bekor = false
    ;(async () => {
      const [a, b, c] = await Promise.all([
        db.umumiy(), db.qarzdorlar(), db.yotqizishlar({ holat: 'yotmoqda' })
      ])
      if (bekor) return
      if (a.error || b.error) { setXato(xatoMatni(a.error || b.error)); return }
      setU(a.data)
      setQarzdorlar([...(b.data || [])].sort((x, y) => Number(y.qarz) - Number(x.qarz)))
      setYotganlar(c.error ? [] : (c.data || []))
    })()
    return () => { bekor = true }
  }, [])

  /* to'lovlar — davr o'zgarganda qayta */
  const yuklaTolov = useCallback(async () => {
    const d = DAVRLAR.find((x) => x.k === davr) || DAVRLAR[0]
    const [dan, gacha] = d.oraliq()
    setTolovlar(null)
    const { data, error } = await db.tolovlar({ dan, gacha })
    if (error) { setXato(xatoMatni(error)); return }
    setTolovlar(data || [])
  }, [davr])

  useEffect(() => { yuklaTolov() }, [yuklaTolov])

  async function chekChiqar(tolovId) {
    const { data, error } = await db.chek(tolovId)
    if (error) return bildir(xatoMatni(error))
    const c = (data || [])[0]
    if (!c) return bildir('Chek maʼlumoti topilmadi.')
    chopEt({ html: chekHtml(c), css: chekCss, sarlavha: `Chek ${c.chek_raqam}` })
  }

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>
  if (!u) return <Kutish />

  const jami = (tolovlar || []).reduce((a, t) => a + Number(t.summa || 0), 0)
  const usulJami = (k) => (tolovlar || [])
    .filter((t) => t.usuli === k)
    .reduce((a, t) => a + Number(t.summa || 0), 0)
  const davrNomi = (DAVRLAR.find((x) => x.k === davr) || DAVRLAR[0]).n

  return (
    <div className="stack">
      {/* ---------------- tepadagi uchta raqam ---------------- */}
      <div className="kpis kpi3">
        <Kpi rang="r" v={son(u.qarzdor_soni)} l="Qarzdor bemor"
          on={ochiq === 'qarzdor'}
          bos={() => setOchiq(ochiq === 'qarzdor' ? null : 'qarzdor')} />
        <Kpi rang="g" v={som(u.bugungi_tushum)} l="Bugungi tushum" pul
          on={ochiq === null && davr === 'bugun'}
          bos={() => { setOchiq(null); setDavr('bugun') }} />
        <Kpi rang="o" v={som(u.qarz_jami)} l="Umumiy qarz" pul
          on={ochiq === 'qarzdor'}
          bos={() => setOchiq(ochiq === 'qarzdor' ? null : 'qarzdor')} />
      </div>

      {/* ---------------- bugun/ertaga ketadiganlar ---------------- */}
      <BugunKetadi royxat={yotganlar} pul
        ochish={(r) => nav('/bemorlar', { state: { qidir: r.telefon || r.fish } })} />

      {/* ---------------- qarzdorlar (bosilganda) ---------------- */}
      {ochiq === 'qarzdor' && (
        <div className="card">
          <div className="card-h">
            <h3>Qarzdor bemorlar</h3>
            <span className="sp" />
            <span className="pill full num">{som(u.qarz_jami)}</span>
            <button className="btn sm" onClick={() => setOchiq(null)}>Yopish</button>
          </div>
          {qarzdorlar.length ? (
            <div className="scroll-x">
              <table className="mobil-karta">
                <thead>
                  <tr><th>Bemor</th><th>Xona</th><th className="r">Umumiy</th>
                    <th className="r">Toʻlangan</th><th className="r">Qarz</th><th></th></tr>
                </thead>
                <tbody>
                  {qarzdorlar.map((q) => (
                    <tr key={q.yotqizish_id}>
                      <td className="bosh">
                        <div className="nm">{q.fish}</div>
                        <div className="sb num muted">{q.telefon}</div>
                      </td>
                      <td className="num" data-l="Xona">{q.xona}</td>
                      <td className="r num" data-l="Umumiy">{son(q.umumiy)}</td>
                      <td className="r num" data-l="Toʻlangan"
                        style={{ color: 'var(--free)' }}>{son(q.tolangan)}</td>
                      <td className="r num" data-l="Qarz"
                        style={{ color: 'var(--full)', fontWeight: 600 }}>
                        {son(q.qarz)}</td>
                      <td className="r amal">
                        <button className="btn sm" onClick={() =>
                          nav('/bemorlar', { state: { qidir: q.telefon || q.fish } })}>
                          Toʻlov
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <div className="card-b muted">Qarzdorlik yoʻq.</div>}
        </div>
      )}

      {/* ---------------- to'lovlar ---------------- */}
      <div className="card">
        <div className="card-h">
          <h3>Toʻlovlar</h3>
          <span className="sp" />
          <span className="pill neutral num">{som(jami)}</span>
        </div>

        <div className="card-b" style={{ paddingBottom: 0 }}>
          <div className="chips">
            {DAVRLAR.map((d) => (
              <button key={d.k} className={'chip' + (davr === d.k ? ' on' : '')}
                onClick={() => setDavr(d.k)}>{d.n}</button>
            ))}
          </div>

          {tolovlar && tolovlar.length > 0 && (
            <div className="row" style={{ marginTop: 11, gap: 8 }}>
              <span className="pill free num">Naqd {son(usulJami('naqd'))}</span>
              <span className="pill booked num">Karta {son(usulJami('karta'))}</span>
              <span className="pill neutral num">Oʻtkazma {son(usulJami('otkazma'))}</span>
              <span className="sp" />
              <span className="muted">{tolovlar.length} ta toʻlov</span>
            </div>
          )}
        </div>

        {tolovlar === null ? (
          <div className="card-b muted">Yuklanmoqda…</div>
        ) : tolovlar.length === 0 ? (
          <div className="card-b muted">{davrNomi} boʻyicha toʻlov yoʻq.</div>
        ) : (
          <div className="scroll-x" style={{ marginTop: 12 }}>
            <table className="mobil-karta">
              <thead>
                <tr><th>Kim toʻladi</th><th>Xona</th><th className="r">Summa</th>
                  <th>Usuli</th><th>Qabul qilgan</th><th>Vaqt</th><th></th></tr>
              </thead>
              <tbody>
                {tolovlar.map((t) => {
                  /* Manfiy summa — bemorga qaytarilgan pul */
                  const qayt = Number(t.summa) < 0
                  return (
                  <tr key={t.tolov_id}>
                    <td className="bosh">
                      <div className="nm">{t.fish}</div>
                      <div className="sb num muted">{t.chek_raqam}</div>
                      {qayt && <span className="pill partial">Qaytarildi</span>}
                    </td>
                    <td className="num" data-l="Xona">{t.xona || '—'}</td>
                    <td className="r num" data-l="Summa"
                      style={{ fontWeight: 600, color: qayt ? 'var(--partial)' : undefined }}>
                      {qayt ? `− ${son(Math.abs(Number(t.summa)))}` : son(t.summa)}
                    </td>
                    <td data-l="Usuli">{USUL_NOM[t.usuli] || t.usuli}</td>
                    <td className="muted" data-l="Qabul qilgan">{t.kassir}</td>
                    <td className="muted num" data-l="Vaqt">{kunVaqt(t.vaqt)}</td>
                    <td className="r amal">
                      <button className="btn sm" onClick={() => chekChiqar(t.tolov_id)}>
                        {qayt ? 'Tilxat' : 'Chek'}
                      </button>
                    </td>
                  </tr>
                  )
                })}
              </tbody>
              <tfoot>
                <tr>
                  <td colSpan={2}>Jami</td>
                  <td className="r num"><b>{son(jami)}</b></td>
                  <td colSpan={4}></td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </div>

      {xabar && <div className="toast ok">{xabar}</div>}
    </div>
  )
}

/* ============================================================
   BUGUN VA ERTAGA KETADIGAN BEMORLAR

   Admin va kassir ish boshida darrov koʻrsin: bugun kim
   chiqadi, ertaga kimni tayyorlash kerak, kimda qarz qolgan,
   kimga pul qaytariladi. Muddati oʻtib ketganlar ham shu
   yerda — ular koykani band qilib turadi.
   ============================================================ */
function BugunKetadi({ royxat, pul, ochish }) {
  const b = bugunSana()
  const e = kunQosh(b, 1)

  const tanla = (r) => {
    const s = r.reja_chiqish
    if (!s || r.holat !== 'yotmoqda') return null
    if (s < b) return 'otgan'
    if (s === b) return 'bugun'
    if (s === e) return 'ertaga'
    return null
  }

  const guruh = { otgan: [], bugun: [], ertaga: [] }
  for (const r of royxat || []) {
    const k = tanla(r)
    if (k) guruh[k].push(r)
  }
  const jami = guruh.otgan.length + guruh.bugun.length + guruh.ertaga.length
  if (jami === 0) return null

  const qator = (r, tur) => {
    const qarz = Number(r.qarz) || 0
    /* Oldindan koʻp toʻlagan boʻlsa, chiqarishda qaytariladi */
    const qaytadi = Math.max(0, (Number(r.tolangan) || 0) - (Number(r.umumiy) || 0))
    return (
      <div className="narx-qator" key={r.yotqizish_id}>
        <div className="body">
          <b>{r.fish}</b>
          <div className="muted">
            {r.telefon || 'raqam yoʻq'}
            {r.xonada ? ` · ${r.xona}-xona · ${r.koyka}-koyka` : ' · xona yoʻq'}
            {r.roli !== 'bemor' && ` · ${r.roli === 'qarovchi' ? 'Qarovchi' : 'Farzand'}`}
            {tur === 'otgan'
              ? ` · muddati ${sanaQisqa(r.reja_chiqish)} da tugagan`
              : ` · ${sanaQisqa(r.reja_chiqish)}`}
          </div>
        </div>
        <div className="row" style={{ gap: 8 }}>
          {pul && qarz > 0 && <span className="pill full num">Qarz {son(qarz)}</span>}
          {pul && qarz === 0 && qaytadi > 0 &&
            <span className="pill partial num">Qaytadi {son(qaytadi)}</span>}
          {pul && qarz === 0 && qaytadi === 0 && <span className="pill free">Hisob yopiq</span>}
          <button className="btn sm" onClick={() => ochish(r)}>Ochish</button>
        </div>
      </div>
    )
  }

  /* birinchi blokda ustki chiziq kerak emas */
  const birinchi = ['otgan', 'bugun', 'ertaga'].find((k) => guruh[k].length > 0)
  const blok = (k, sarlavha, izoh) => guruh[k].length > 0 && (
    <div key={k}>
      <div className="card-b" style={{ paddingBottom: 4, paddingTop: 12,
        borderTop: k === birinchi ? 'none' : '1px solid var(--line-2)' }}>
        <div className="muted"><b>{sarlavha}</b> — {izoh}</div>
      </div>
      <div className="narx-royxat">{guruh[k].map((r) => qator(r, k))}</div>
    </div>
  )

  return (
    <div className={'card' + (guruh.otgan.length ? ' ogoh-kech' : ' ogoh')}>
      {/* telefon ekranida uchta belgi bir qatorga sigʻmaydi — koʻchsin */}
      <div className="card-h" style={{ flexWrap: 'wrap', rowGap: 6 }}>
        <h3>Ketadigan bemorlar</h3>
        <span className="sp" />
        {guruh.otgan.length > 0 &&
          <span className="pill full num">{guruh.otgan.length} ta muddati oʻtgan</span>}
        {guruh.bugun.length > 0 &&
          <span className="pill partial num">{guruh.bugun.length} ta bugun</span>}
        {guruh.ertaga.length > 0 &&
          <span className="pill booked num">{guruh.ertaga.length} ta ertaga</span>}
      </div>

      {blok('otgan', 'Muddati oʻtgan',
        'reja boʻyicha allaqachon chiqishi kerak edi, koyka hali band.')}
      {blok('bugun', 'Bugun ketadi',
        'hisob-kitobni yopib, chiqarib yuboring.')}
      {blok('ertaga', 'Ertaga ketadi',
        'bugundan tayyorlab qoʻying — qarzi boʻlsa aytib qoʻyiladi.')}
    </div>
  )
}

/* ============================================================
   BUGUN KELADIGAN BRONLAR

   Super admin va registrator ekranida turadi: bugun kimni
   kutayotganini ish boshida darrov koʻrsin, Bronlar boʻlimiga
   kirib qidirmasin. Kechikkanlari ham shu yerda — ular xonani
   band qilib turadi, tezroq yopilgani maʼqul.
   ============================================================ */
function BugunKeladi({ bronlar, can, qabul }) {
  const bugun = (bronlar || []).filter((b) => b.holat_matn === 'bugun')
  const kech = (bronlar || []).filter((b) => b.holat_matn === 'kechikkan')

  if (bugun.length === 0 && kech.length === 0) return null

  const qator = (b, kechikkan) => (
    <div className="narx-qator" key={b.bron_id}>
      <div className="body">
        <b>{b.ismi}</b>
        <div className="muted">
          {b.telefon}
          {b.xona ? ` · ${b.xona}-xona` : ' · xona tanlanmagan'}
          {b.kishi > 1 && ` · ${b.kishi} kishi`}
          {kechikkan && ` · ${Math.abs(b.qolgan_kun)} kun kechikdi`}
          {b.tashxis && <><br />Tashxis: {b.tashxis}</>}
        </div>
      </div>
      <div className="row" style={{ gap: 8 }}>
        {Number(b.toqnashuv) > 0 && (
          <span className="pill partial">Xona band</span>
        )}
        {can('royxat') && (
          <button className={'btn sm' + (kechikkan ? '' : ' pri')}
            onClick={() => qabul(b)}>
            Qabul qilish
          </button>
        )}
      </div>
    </div>
  )

  return (
    <div className={'card' + (bugun.length > 0 ? ' ogoh' : ' ogoh-kech')}>
      <div className="card-h">
        <h3>{bugun.length > 0 ? 'Bugun keladigan bronlar' : 'Kechikkan bronlar'}</h3>
        <span className="sp" />
        {bugun.length > 0 && (
          <span className="pill partial num">{bugun.length} ta bugun</span>
        )}
        {kech.length > 0 && (
          <span className="pill full num">{kech.length} ta kechikkan</span>
        )}
      </div>

      {bugun.length > 0 && (
        <>
          <div className="card-b" style={{ paddingBottom: 4 }}>
            <div className="muted">
              Shu odamlar <b>bugun</b> kelishi kerak. Kelgach “Qabul qilish” ni
              bosing — forma bronning xonasi, sanalari va tashxisi bilan toʻladi.
            </div>
          </div>
          <div className="narx-royxat">{bugun.map((b) => qator(b, false))}</div>
        </>
      )}

      {kech.length > 0 && (
        <>
          <div className="card-b" style={{ paddingBottom: 4,
            borderTop: bugun.length > 0 ? '1px solid var(--line-2)' : 'none',
            paddingTop: bugun.length > 0 ? 12 : undefined }}>
            <div className="muted">
              <b>Kelishi kerak boʻlgan kun oʻtib ketgan.</b> Ular hali ham xonani
              band qilib turibdi — qabul qiling yoki Bronlar boʻlimidan yoping.
            </div>
          </div>
          <div className="narx-royxat">{kech.map((b) => qator(b, true))}</div>
        </>
      )}
    </div>
  )
}
