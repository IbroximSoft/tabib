import { useEffect, useMemo, useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { db, xatoMatni } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Kutish } from '../components/Kutish'
import { Xabar } from '../components/Modal'
import { chopEt, kunVaqt } from '../lib/chop'
import { chekHtml, chekCss } from '../print/chek'

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

const USUL = { naqd: 'Naqd', karta: 'Plastik karta', otkazma: 'Oʻtkazma' }
const ORALIQ = [
  { k: 'bugun', n: 'Bugun' },
  { k: '7', n: '7 kun' },
  { k: '30', n: '30 kun' },
  { k: 'qol', n: 'Oraliq' }
]

export default function Tolovlar() {
  const { can } = useAuth()
  const nav = useNavigate()

  const [oraliq, setOraliq] = useState('bugun')
  const [dan, setDan] = useState(bugun())
  const [gacha, setGacha] = useState(bugun())
  const [usuli, setUsuli] = useState('')
  const [qidiruv, setQidiruv] = useState('')

  const [royxat, setRoyxat] = useState(null)
  const [qarzdorlar, setQarzdorlar] = useState([])
  const [xato, setXato] = useState('')
  const [xabar, setXabar] = useState('')
  const [tab, setTab] = useState('tolov')

  const bildir = (m) => { setXabar(m); setTimeout(() => setXabar(''), 4000) }

  function oraliqTanla(k) {
    setOraliq(k)
    if (k === 'bugun') { setDan(bugun()); setGacha(bugun()) }
    else if (k === '7') { setDan(qoshKun(bugun(), -6)); setGacha(bugun()) }
    else if (k === '30') { setDan(qoshKun(bugun(), -29)); setGacha(bugun()) }
  }

  const yukla = useCallback(async () => {
    const [t, q] = await Promise.all([
      db.tolovlar({ dan, gacha, usuli: usuli || undefined }),
      db.qarzdorlar()
    ])
    if (t.error) { setXato(xatoMatni(t.error)); setRoyxat([]); return }
    setXato('')
    setRoyxat(t.data || [])
    setQarzdorlar(q.data || [])
  }, [dan, gacha, usuli])

  useEffect(() => { yukla() }, [yukla])

  const korinadi = useMemo(() => {
    const s = qidiruv.trim().toLowerCase()
    if (!s) return royxat || []
    return (royxat || []).filter((r) =>
      `${r.fish} ${r.telefon} ${r.chek_raqam} ${r.xona}`.toLowerCase().includes(s))
  }, [royxat, qidiruv])

  /* Manfiy qator — bemorga qaytarilgan pul (24_qaytarish.sql).
     Tushum faqat kirimdan sanaladi, qaytarilgani alohida turadi,
     kassadagi haqiqiy pul esa ikkovining farqi. */
  const jami = useMemo(() => {
    const kirim = korinadi.filter((r) => Number(r.summa) > 0)
    const chiqim = korinadi.filter((r) => Number(r.summa) < 0)
    const yig = (a, u) => a.filter((r) => !u || r.usuli === u)
      .reduce((s, r) => s + Number(r.summa), 0)
    return {
      summa: yig(kirim),
      soni: kirim.length,
      naqd: yig(kirim, 'naqd'),
      karta: yig(kirim, 'karta'),
      otkazma: yig(kirim, 'otkazma'),
      qaytarilgan: -yig(chiqim),
      qaytarishSoni: chiqim.length,
      sof: yig(korinadi)
    }
  }, [korinadi])

  const qarzJami = useMemo(
    () => qarzdorlar.reduce((s, r) => s + Number(r.qarz), 0), [qarzdorlar])

  async function chekChiqar(tolovId) {
    const { data, error } = await db.chek(tolovId)
    if (error) return bildir(xatoMatni(error))
    const c = (data || [])[0]
    if (!c) return bildir('Chek maʼlumoti topilmadi.')
    chopEt({ html: chekHtml(c), css: chekCss, sarlavha: `Chek ${c.chek_raqam}` })
  }

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>
  if (!royxat) return <Kutish />

  return (
    <div className="stack">
      <div className="kpis">
        <Kpi v={som(jami.summa)} l="Tushum" rang="g" />
        <Kpi v={jami.soni} l="Toʻlovlar" rang="a" />
        <Kpi v={som(jami.naqd)} l="Naqd" rang="a" />
        <Kpi v={som(jami.karta + jami.otkazma)} l="Karta / oʻtkazma" rang="b" />
        {jami.qaytarilgan > 0 && <Kpi v={som(jami.qaytarilgan)} l="Qaytarilgan" rang="r" />}
        {qarzJami > 0 && <Kpi v={som(qarzJami)} l="Joriy qarzdorlik" rang="r" />}
      </div>

      <div className="tablar">
        <button className={`tab${tab === 'tolov' ? ' on' : ''}`}
          onClick={() => setTab('tolov')}>Toʻlovlar</button>
        <button className={`tab${tab === 'qarz' ? ' on' : ''}`}
          onClick={() => setTab('qarz')}>Qarzdorlar ({qarzdorlar.length})</button>
      </div>

      {tab === 'tolov' ? (
        <>
          <div className="toolbar">
            <div className="qidir">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
              <input value={qidiruv} onChange={(e) => setQidiruv(e.target.value)}
                placeholder="Bemor, telefon yoki chek raqami" type="search" />
            </div>
            <span className="sp" />
            <select className="mini" value={usuli} onChange={(e) => setUsuli(e.target.value)}>
              <option value="">Barcha usullar</option>
              <option value="naqd">Naqd</option>
              <option value="karta">Plastik karta</option>
              <option value="otkazma">Oʻtkazma</option>
            </select>
          </div>

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
          </div>

          {korinadi.length === 0 ? (
            <div className="bosh-yoq">
              <div className="nm">Bu oraliqda toʻlov yoʻq</div>
              <div className="muted">
                Toʻlov bemor kartasidagi “Toʻlov tarixi” boʻlimidan qabul qilinadi.
              </div>
            </div>
          ) : (
            <div className="card">
              <div className="jadval-o">
                <table className="mobil-karta">
                  <thead>
                    <tr>
                      <th>Chek</th><th>Bemor</th><th>Xona</th>
                      <th>Usuli</th><th>Kassir</th>
                      <th className="r">Summa</th><th className="r">Qolgan qarz</th><th></th>
                    </tr>
                  </thead>
                  <tbody>
                    {korinadi.map((r) => {
                      const qayt = Number(r.summa) < 0
                      return (
                      <tr key={r.tolov_id}>
                        <td className="bosh">
                          <div className="nm num">{r.chek_raqam}</div>
                          <div className="sb num">{kunVaqt(r.vaqt)}</div>
                          {qayt && <span className="pill partial">Qaytarildi</span>}
                        </td>
                        <td data-l="Bemor">
                          <button className="matn" onClick={() =>
                            nav('/bemorlar', { state: { qidir: r.telefon } })}>
                            {r.fish}
                          </button>
                          <div className="sb num">{r.telefon}</div>
                        </td>
                        <td data-l="Xona">{r.xona}</td>
                        <td data-l="Usuli">{USUL[r.usuli] || r.usuli}</td>
                        <td className="muted" data-l="Kassir">{r.kassir}</td>
                        <td className="r num" data-l="Summa">
                          <b style={qayt ? { color: 'var(--partial)' } : undefined}>
                            {qayt ? `− ${son(Math.abs(Number(r.summa)))}` : son(r.summa)}
                          </b>
                        </td>
                        <td className="r num" data-l="Qolgan qarz">
                          {Number(r.qolgan_qarz) > 0
                            ? <span style={{ color: 'var(--full)' }}>{son(r.qolgan_qarz)}</span>
                            : <span className="muted">0</span>}
                        </td>
                        <td className="r amal">
                          <button className="btn sm" onClick={() => chekChiqar(r.tolov_id)}>
                            {qayt ? 'Tilxat' : 'Chek'}
                          </button>
                        </td>
                      </tr>
                      )
                    })}
                  </tbody>
                  <tfoot>
                    {jami.qaytarilgan > 0 && (
                      <tr>
                        <td colSpan={5} className="muted">
                          Qaytarilgan — {jami.qaytarishSoni} ta
                        </td>
                        <td className="r num" data-l="Qaytarilgan"
                          style={{ color: 'var(--partial)' }}>
                          − {son(jami.qaytarilgan)}
                        </td>
                        <td colSpan={2}></td>
                      </tr>
                    )}
                    <tr>
                      <td colSpan={5}>
                        Jami — {jami.soni} ta toʻlov
                        {jami.qaytarilgan > 0 && ' (qaytarilgani ayirilgan)'}
                      </td>
                      <td className="r num" data-l="Jami summa"><b>{son(jami.sof)}</b></td>
                      <td colSpan={2}></td>
                    </tr>
                  </tfoot>
                </table>
              </div>
            </div>
          )}
        </>
      ) : (
        <>
          {qarzdorlar.length === 0 ? (
            <div className="bosh-yoq">
              <div className="nm">Qarzdor yoʻq</div>
              <div className="muted">Hamma bemor hisob-kitobini yopgan.</div>
            </div>
          ) : (
            <>
              <div className="alert info">
                <span>◇</span>
                <div>
                  Qarzi bor bemor chiqarilmaydi. Buxgalter toʻlovni qabul qilib chek beradi,
                  chek qorovulga topshiriladi. Toʻlov bemor kartasidan kiritiladi.
                </div>
              </div>
              <div className="card">
                <div className="jadval-o">
                  <table className="mobil-karta">
                    <thead>
                      <tr>
                        <th>Bemor</th><th>Xona</th>
                        <th className="r">Hisob</th><th className="r">Toʻlangan</th>
                        <th className="r">Qarz</th><th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {qarzdorlar.map((r) => (
                        <tr key={r.yotqizish_id}>
                          <td className="bosh">
                            <div className="nm">{r.fish}</div>
                            <div className="sb num">{r.telefon}</div>
                          </td>
                          <td data-l="Xona">{r.xona}</td>
                          <td className="r num" data-l="Hisob">{son(r.umumiy)}</td>
                          <td className="r num" data-l="Toʻlangan"
                            style={{ color: 'var(--free)' }}>{son(r.tolangan)}</td>
                          <td className="r num" data-l="Qarz">
                            <b style={{ color: 'var(--full)' }}>{son(r.qarz)}</b>
                          </td>
                          <td className="r amal">
                            {can('tolov') && (
                              <button className="btn sm" onClick={() =>
                                nav('/bemorlar', { state: { qidir: r.telefon } })}>
                                Kartasi
                              </button>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                    <tfoot>
                      <tr>
                        <td colSpan={4}>Jami</td>
                        <td className="r num" data-l="Jami qarz"><b>{son(qarzJami)}</b></td>
                        <td></td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              </div>
            </>
          )}
        </>
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
