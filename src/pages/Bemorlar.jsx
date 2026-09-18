import { useEffect, useMemo, useState, useCallback } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { db, amal, xatoMatni } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Kutish } from '../components/Kutish'
import Modal, { Xabar } from '../components/Modal'
import { chopEt, kunVaqt } from '../lib/chop'
import { kartaHtml, kartaCss, TOMONLAR } from '../print/karta'
import { chekHtml, chekCss } from '../print/chek'
import { VILOYATLAR, SNG_DAVLATLAR } from '../lib/hududlar'

/* ---------- yordamchilar ---------- */
const son = (n) => (Number(n) || 0).toLocaleString('ru-RU').replace(/\u00A0/g, ' ')
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
const faqatRaqam = (s) => String(s || '').replace(/\D/g, '')
/* PostgREST filtriga tushadigan belgilarni tozalaymiz */
const tozala = (s) => s.replace(/[(),*"\\]/g, ' ').trim()

const HOLATLAR = [
  { k: 'yotmoqda', n: 'Yotmoqda' },
  { k: 'xonasiz', n: 'Xonasiz' },
  { k: 'chiqdi', n: 'Chiqqan' },
  { k: '', n: 'Hammasi' }
]
const ROL_NOM = { bemor: 'Bemor', farzand: 'Farzand', qarovchi: 'Qarovchi' }

/* ============================================================
   ASOSIY EKRAN
   ============================================================ */
export default function Bemorlar() {
  const { can, rol } = useAuth()
  const loc = useLocation()
  const nav = useNavigate()

  const [f, setF] = useState({ holat: 'yotmoqda', q: '', bolim_id: '', jins: '', qarzdor: '' })
  const [qidiruv, setQidiruv] = useState('')
  const [royxat, setRoyxat] = useState(null)
  const [faol, setFaol] = useState([])          // barcha yotayotganlar — koyka bandligi uchun
  const [ref, setRef] = useState({ bolimlar: [], koykalar: [], kursKun: 10 })
  const [xato, setXato] = useState('')
  const [modal, setModal] = useState(null)      // {tur, yozuv}
  const [xabar, setXabar] = useState('')

  const bildir = useCallback((m) => {
    setXabar(m)
    setTimeout(() => setXabar(''), 4000)
  }, [])

  /* qidiruvni kechiktirib yuboramiz */
  useEffect(() => {
    const t = setTimeout(() => setF((x) => ({ ...x, q: qidiruv })), 300)
    return () => clearTimeout(t)
  }, [qidiruv])

  /* ma'lumotnomalar — bir marta */
  useEffect(() => {
    let bekor = false
    ;(async () => {
      const [b, k, t] = await Promise.all([db.bolimlar(), db.koykalar(), db.tariflar()])
      if (bekor) return
      const kurs = (t.data || []).find((x) => x.kalit === 'kurs_kun')
      setRef({
        bolimlar: b.data || [],
        koykalar: k.data || [],
        kursKun: kurs ? Number(kurs.qiymat) : 10
      })
    })()
    return () => { bekor = true }
  }, [])

  /* ro'yxat */
  const yukla = useCallback(async () => {
    setXato('')
    const filtr = {
      holat: f.holat === 'xonasiz' ? 'yotmoqda' : f.holat || undefined,
      bolim_id: f.bolim_id || undefined,
      jins: f.jins || undefined,
      qarzdor: f.qarzdor === '' ? undefined : f.qarzdor === 'ha',
      q: f.q ? tozala(f.q) : undefined
    }
    const [r, a] = await Promise.all([db.yotqizishlar(filtr), db.yotqizishlar({ holat: 'yotmoqda' })])
    if (r.error) { setXato(xatoMatni(r.error)); setRoyxat([]); return { d: [], a: [] } }
    let d = r.data || []
    if (f.holat === 'xonasiz') d = d.filter((x) => !x.xonada)
    const aData = a.data || []
    setRoyxat(d)
    setFaol(aData)
    return { d, a: aData }
  }, [f])

  useEffect(() => { yukla() }, [yukla])

  /* Xonalar ekranidan kelgan buyruq: bemorni qidirish yoki
     tanlangan koykaga yangi bemor qabul qilish */
  useEffect(() => {
    const st = loc.state
    if (!st) return
    if (st.qidir) {
      setQidiruv(st.qidir)
      setF((x) => ({ ...x, holat: '' }))
    }
    if (st.yangiKoyka) {
      setModal({ tur: 'yangi', koyka: st.yangiKoyka, jins: st.jins })
    }
    /* Bronlar ekranidan "Qabul qilish" bosilgan — forma bron
       ma'lumotlari bilan to'ldiriladi, saqlangach bron belgilanadi */
    if (st.bron) {
      setModal({ tur: 'yangi', bron: st.bron, jins: st.bron.jins })
    }
    nav(loc.pathname, { replace: true, state: null })
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  /* band koykalar va xona jinslari */
  const { bandKoyka, xonaJins } = useMemo(() => {
    const band = new Set()
    const jins = {}
    faol.forEach((y) => {
      if (!y.xona_id || y.koyka == null) return
      band.add(y.xona_id + ':' + y.koyka)
      jins[y.xona_id] = y.jins
    })
    return { bandKoyka: band, xonaJins: jins }
  }, [faol])

  const bolimMap = useMemo(() => {
    const m = {}
    ref.bolimlar.forEach((b) => { m[b.id] = b })
    return m
  }, [ref.bolimlar])

  /* berilgan jins uchun bo'sh koykalar, xonalar bo'yicha guruhlangan */
  const boshJoylar = useCallback((jinsi) => {
    const guruh = new Map()
    ref.koykalar.forEach((k) => {
      const x = k.xonalar
      if (!x || x.tamirlashda) return
      if (bandKoyka.has(k.xona_id + ':' + k.raqam)) return
      const bo = bolimMap[x.bolim_id]
      if (!bo) return
      if (bo.jins !== 'aralash' && bo.jins !== jinsi) return
      if (bo.jins !== 'aralash') {
        const mavjud = xonaJins[k.xona_id]
        if (mavjud && mavjud !== jinsi) return
      }
      const kalit = k.xona_id
      if (!guruh.has(kalit)) {
        guruh.set(kalit, { xona_id: k.xona_id, xona: x.raqam, bolim: bo.nomi, koykalar: [] })
      }
      guruh.get(kalit).koykalar.push({ id: k.id, raqam: k.raqam })
    })
    return [...guruh.values()]
      .map((g) => ({ ...g, koykalar: g.koykalar.sort((a, b) => a.raqam - b.raqam) }))
      .sort((a, b) => String(a.xona).localeCompare(String(b.xona), 'uz', { numeric: true }))
  }, [ref.koykalar, bandKoyka, xonaJins, bolimMap])

  const yopVaYangila = (m) => { setModal(null); if (m) bildir(m); yukla() }
  /* Modalni yopmasdan yangilash — toʻlov qabul qilinganda kerak:
     buxgalter chekni koʻrib turib yana chiqara olsin.
     MUHIM: faqat fon roʻyxatini emas, OCHIQ TURGAN modalning "y"
     obyektini ham yangilaymiz — aks holda toʻlov qabul qilingandan
     keyin ham kartada eski qarz koʻrinib, "Chiqarish" yopiq boʻlib
     qolaverardi (modal yopib-qayta ochilgandagina toʻgʻrilanardi). */
  const yangila = async (m) => {
    if (m) bildir(m)
    const { d, a } = await yukla()
    setModal((cur) => {
      if (!cur || !cur.yozuv) return cur
      const yangi = a.find((x) => x.yotqizish_id === cur.yozuv.yotqizish_id)
        || d.find((x) => x.yotqizish_id === cur.yozuv.yotqizish_id)
      return yangi ? { ...cur, yozuv: yangi } : cur
    })
  }

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>

  return (
    <div className="stack">
      {/* ---------- asboblar paneli ---------- */}
      <div className="toolbar">
        <div className="qidir">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
            strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
          <input
            value={qidiruv}
            onChange={(e) => setQidiruv(e.target.value)}
            placeholder="Ism yoki telefon boʻyicha qidirish"
            type="search"
          />
        </div>
        <span className="sp" />
        {can('royxat') && (
          <button className="btn pri" onClick={() => setModal({ tur: 'yangi' })}>
            + Yangi bemor
          </button>
        )}
      </div>

      <div className="chips">
        {HOLATLAR.map((h) => (
          <button key={h.k} className={`chip${f.holat === h.k ? ' on' : ''}`}
            onClick={() => setF((x) => ({ ...x, holat: h.k }))}>{h.n}</button>
        ))}
        <span className="sp" />
        <select className="mini" value={f.bolim_id}
          onChange={(e) => setF((x) => ({ ...x, bolim_id: e.target.value }))}>
          <option value="">Barcha boʻlimlar</option>
          {ref.bolimlar.map((b) => <option key={b.id} value={b.id}>{b.nomi}</option>)}
        </select>
        <select className="mini" value={f.jins}
          onChange={(e) => setF((x) => ({ ...x, jins: e.target.value }))}>
          <option value="">Jinsi</option>
          <option value="erkak">Erkak</option>
          <option value="ayol">Ayol</option>
        </select>
        {can('pul') && (
          <select className="mini" value={f.qarzdor}
            onChange={(e) => setF((x) => ({ ...x, qarzdor: e.target.value }))}>
            <option value="">Qarzi</option>
            <option value="ha">Qarzdor</option>
            <option value="yoq">Qarzsiz</option>
          </select>
        )}
      </div>

      {/* ---------- ro'yxat ---------- */}
      {!royxat ? <Kutish /> : royxat.length === 0 ? (
        <div className="todo">Bu filtr boʻyicha bemor topilmadi.</div>
      ) : (
        <div className="card">
          <div className="scroll-x">
            <table className="clickable mobil-karta">
              <thead>
                <tr>
                  <th>Bemor</th>
                  <th>Xona</th>
                  <th>Kirish</th>
                  <th>Reja</th>
                  <th className="r">Kun</th>
                  {can('pul') && <th className="r">Qarz</th>}
                  <th>Holat</th>
                </tr>
              </thead>
              <tbody>
                {royxat.map((y) => (
                  <tr key={y.yotqizish_id} onClick={() => setModal({ tur: 'karta', yozuv: y })}>
                    <td className="bosh">
                      <div className="nm">{y.fish}</div>
                      <div className="sb">
                        <span className={`dot ${y.jins}`} />
                        {y.jins === 'erkak' ? 'Erkak' : 'Ayol'}
                        {y.roli !== 'bemor' && ` · ${ROL_NOM[y.roli]}`}
                        {y.telefon && ` · ${y.telefon}`}
                      </div>
                      {y.asosiy_fish && (
                        <div className="sb bog"><span className="ok-strelka">↳</span>{y.asosiy_fish} bilan</div>
                      )}
                      {y.hamroh_soni > 0 && (
                        <div className="sb bog">
                          <span className="ok-strelka">↳</span>{y.hamroh_soni} ta hamroh
                        </div>
                      )}
                    </td>
                    <td className="num" data-l="Xona / koyka">
                      {y.xonada ? `${y.xona} / ${y.koyka}` : <span className="muted">xonasiz</span>}
                    </td>
                    <td className="num" data-l="Kirgan">{sana(y.kirish_sana)}</td>
                    <td className="num" data-l="Reja boʻyicha">{sana(y.reja_chiqish)}</td>
                    <td className="r num" data-l="Yotgan kun">{y.yotgan_kun}</td>
                    {can('pul') && (
                      <td className="r num" data-l="Qarz">
                        {Number(y.qarz) > 0
                          ? <b style={{ color: 'var(--full)' }}>{son(y.qarz)}</b>
                          : <span className="muted">—</span>}
                      </td>
                    )}
                    <td data-l="Holat"><HolatPill y={y} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {royxat && royxat.length > 0 && (
        <div className="muted">Jami: {royxat.length} ta yozuv</div>
      )}

      {/* ---------- modallar ---------- */}
      {modal?.tur === 'yangi' && (
        <YangiBemor
          ref_={ref} boshJoylar={boshJoylar} can={can}
          boshKoyka={modal.koyka} boshJins={modal.jins} bron={modal.bron}
          yop={() => setModal(null)} tugadi={yopVaYangila}
          ochBemor={(b) => { setModal(null); setQidiruv(b.telefon); setF((x) => ({ ...x, holat: '' })) }}
        />
      )}
      {modal?.tur === 'karta' && (
        <BemorKarta
          y={modal.yozuv} rol={rol} can={can}
          ochish={(tur) => setModal({ tur, yozuv: modal.yozuv })}
          yop={() => setModal(null)} tugadi={yopVaYangila} yangila={yangila}
        />
      )}
      {modal?.tur === 'joylash' && (
        <Joylashtirish
          y={modal.yozuv} boshJoylar={boshJoylar}
          yop={() => setModal({ tur: 'karta', yozuv: modal.yozuv })} tugadi={yopVaYangila}
        />
      )}
      {modal?.tur === 'uzaytir' && (
        <Uzaytirish
          y={modal.yozuv} kursKun={ref.kursKun}
          yop={() => setModal({ tur: 'karta', yozuv: modal.yozuv })} tugadi={yopVaYangila}
        />
      )}
      {modal?.tur === 'malumotTahrir' && (
        <MalumotTahrir
          y={modal.yozuv}
          yop={() => setModal({ tur: 'karta', yozuv: modal.yozuv })} tugadi={yopVaYangila}
        />
      )}
      <Xabar matn={xabar} />
    </div>
  )
}

/* ---------- holat belgisi ---------- */
function HolatPill({ y }) {
  if (y.holat === 'chiqdi') return <span className="pill neutral">Chiqdi</span>
  if (y.holat === 'bekor') return <span className="pill neutral">Bekor</span>
  const kechikkan = y.reja_chiqish < bugun()
  if (kechikkan) return <span className="pill partial">Tasdiqlanmagan</span>
  if (!y.xonada) return <span className="pill booked">Xonasiz</span>
  if (y.reja_chiqish === bugun()) return <span className="pill partial">Bugun chiqadi</span>
  return <span className="pill free">Yotmoqda</span>
}

/* ============================================================
   YANGI BEMOR
   ============================================================ */
function YangiBemor({ ref_, boshJoylar, can, yop, tugadi, ochBemor, boshKoyka, boshJins, bron }) {
  /* Bron ma'lumotlari — "Nazarov Bekzod" bitta maydonda kelgani uchun
     birinchi so'zni familiya, qolganini ism deb olamiz. */
  const bronBosh = useMemo(() => {
    if (!bron) return null
    const qism = String(bron.ismi || '').trim().split(/\s+/)
    return {
      familiya: qism[0] || '',
      ism: qism.slice(1).join(' ') || '',
      telefon: bron.telefon || '+998 ',
      jins: bron.jins || 'erkak',
      kirish: bron.kirish < bugun() ? bugun() : bron.kirish,
      reja_chiqish: bron.chiqish,
      tashxis: bron.tashxis || ''
    }
  }, [bron])

  const [v, setV] = useState({
    familiya: bronBosh?.familiya || '',
    ism: bronBosh?.ism || '',
    jins: bronBosh?.jins || boshJins || 'erkak',
    telefon: bronBosh?.telefon || '+998 ',
    yosh: '',
    chet_el: false,
    kirish: bronBosh?.kirish || bugun(),
    reja_chiqish: bronBosh?.reja_chiqish || qoshKun(bugun(), ref_.kursKun),
    koyka_id: boshKoyka ? String(boshKoyka) : '', oldindan: '',
    tashxis: bronBosh?.tashxis || '',
    /* Qo'shimcha ma'lumotlar — 27_bemor_malumotlari.sql.
       Hammasi ixtiyoriy: bo'sh qoldirilsa kartada qo'lda
       to'ldirish uchun joy bo'sh qolaveradi. */
    otasining_ismi: '', tugilgan_sana: '',
    viloyat: '', tuman: '', mahalla: '', kocha: '', uy_raqami: '', kvartira: ''
  })
  const [hamrohlar, setHamrohlar] = useState([])
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)
  const [oxshash, setOxshash] = useState([])
  const [qayta, setQayta] = useState(null)   // mavjud bemorni qayta qabul qilish
  const [ochiqBron, setOchiqBron] = useState([])  // shu raqamga ochiq bron
  const [bronPisand, setBronPisand] = useState(false) // ogohlantirish yopildi
  const [bronXabar, setBronXabar] = useState('')  // bron qo'llanilgach izoh

  const set = (k, x) => setV((s) => ({ ...s, [k]: x }))

  /* Viloyat (yoki chet elda mamlakat) o'zgarsa — tuman ro'yxati
     mos kelmay qolgani uchun tozalanadi. */
  const tumanlar = useMemo(
    () => (VILOYATLAR.find((r) => r.nomi === v.viloyat) || {}).tumanlar || [],
    [v.viloyat]
  )
  useEffect(() => {
    if (v.tuman && !tumanlar.includes(v.tuman)) set('tuman', '')
  }, [tumanlar]) // eslint-disable-line react-hooks/exhaustive-deps

  /* Chet el fuqarosi belgisi almashsa — viloyat/tuman maydoni
     boshqa ro'yxatga ishora qilganda eskisi qolib ketmasin. */
  useEffect(() => { set('viloyat', ''); set('tuman', '') }, [v.chet_el]) // eslint-disable-line react-hooks/exhaustive-deps

  /* ---- hamrohlar ---- */
  const hQosh = (roli) => setHamrohlar((s) => [...s, {
    kalit: Date.now() + Math.random(),
    roli, familiya: v.familiya, ism: '', jins: roli === 'qarovchi' ? 'ayol' : 'erkak',
    yosh: '', koyka_id: ''
  }])
  const hOchir = (kalit) => setHamrohlar((s) => s.filter((h) => h.kalit !== kalit))
  const hSet = (kalit, k, x) =>
    setHamrohlar((s) => s.map((h) => (h.kalit === kalit ? { ...h, [k]: x } : h)))

  /* Shu formada allaqachon tanlangan koykalar boshqa qatorda chiqmasin */
  const joylarUchun = useCallback((jinsi, ozKoyka) => {
    const olingan = new Set(
      [v.koyka_id, ...hamrohlar.map((h) => h.koyka_id)].filter(Boolean).map(String)
    )
    if (ozKoyka) olingan.delete(String(ozKoyka))
    return boshJoylar(jinsi)
      .map((g) => ({ ...g, koykalar: g.koykalar.filter((k) => !olingan.has(String(k.id))) }))
      .filter((g) => g.koykalar.length > 0)
  }, [boshJoylar, v.koyka_id, hamrohlar])

  /* kurs muddati tarifdan kelib chiqadi.
     Bron bo'lsa — birinchi safar tegmaymiz, bronda kelishilgan
     sanalar saqlanadi. Keyin kirish o'zgartirilsa qayta hisoblanadi. */
  const [bronSana, setBronSana] = useState(!!bron)
  useEffect(() => {
    if (bronSana) { setBronSana(false); return }
    set('reja_chiqish', qoshKun(v.kirish, ref_.kursKun))
  }, [v.kirish, ref_.kursKun]) // eslint-disable-line react-hooks/exhaustive-deps

  /* Bronda xona band qilingan bo'lsa — o'sha xonadagi birinchi bo'sh koyka.
     Xona to'lib qolgan bo'lishi ham mumkin (bron kunidan keyin kelgan
     bo'lsa) — o'shanda administratorga aytiladi. */
  const [bronXonaBand, setBronXonaBand] = useState(false)
  useEffect(() => {
    if (!bron?.xona_id || v.koyka_id) return
    const g = boshJoylar(v.jins).find((x) => String(x.xona_id) === String(bron.xona_id))
    if (g && g.koykalar[0]) { set('koyka_id', String(g.koykalar[0].id)); setBronXonaBand(false) }
    else setBronXonaBand(true)
  }, [bron, boshJoylar]) // eslint-disable-line react-hooks/exhaustive-deps

  /* jins o'zgarsa tanlangan koyka mos kelmay qolishi mumkin */
  const joylar = useMemo(() => joylarUchun(v.jins, v.koyka_id), [joylarUchun, v.jins, v.koyka_id])
  useEffect(() => {
    if (!v.koyka_id) return
    const bor = boshJoylar(v.jins).some((g) =>
      g.koykalar.some((k) => String(k.id) === String(v.koyka_id)))
    if (!bor) set('koyka_id', '')
  }, [v.jins]) // eslint-disable-line react-hooks/exhaustive-deps

  /* Shu raqam allaqachon asosiy bemorga tegishlimi? */
  const takror = useMemo(
    () => oxshash.find((o) => !o.hamroh && faqatRaqam(o.telefon) === faqatRaqam(v.telefon)),
    [oxshash, v.telefon]
  )
  useEffect(() => { if (!takror) setQayta(null) }, [takror])

  /* telefon bo'yicha mavjud bemorni qidiramiz — dublikat bo'lmasin */
  useEffect(() => {
    const raqam = v.telefon.replace(/\D/g, '')
    if (raqam.length < 9) { setOxshash([]); return }
    let bekor = false
    const t = setTimeout(async () => {
      const [o, b] = await Promise.all([
        db.bemorQidir(v.telefon.trim()),
        db.bronQidir(v.telefon.trim())
      ])
      if (bekor) return
      setOxshash(o.data || [])
      /* 19_bron_bogla.sql hali ishga tushmagan bo'lsa xato keladi —
         forma shundan buzilmasin, shunchaki ogohlantirish bo'lmaydi */
      setOchiqBron(b.error ? [] : (b.data || []))
    }, 400)
    return () => { bekor = true; clearTimeout(t) }
  }, [v.telefon])

  /* Bron bo'yicha kelgan bo'lsa yoki bronni e'tiborsiz qoldirish
     tanlangan bo'lsa — ogohlantirish ko'rsatilmaydi */
  const bronOgoh = useMemo(
    () => (bron || bronPisand ? null : ochiqBron[0] || null),
    [bron, bronPisand, ochiqBron]
  )

  /* Ogohlantirishdagi "Bron bo'yicha qabul qilish" — formani
     bronning sanalari, xonasi va tashxisi bilan to'ldiramiz. */
  function bronniOl(b) {
    const qism = String(b.ismi || '').trim().split(/\s+/)
    setV((s) => ({
      ...s,
      familiya: s.familiya || qism[0] || '',
      ism: s.ism || qism.slice(1).join(' ') || '',
      jins: b.jins || s.jins,
      kirish: b.kirish < bugun() ? bugun() : b.kirish,
      reja_chiqish: b.chiqish,
      tashxis: s.tashxis || b.tashxis || ''
    }))
    setBronSana(true)
    if (b.xona_id) {
      const g = boshJoylar(b.jins || v.jins)
        .find((x) => String(x.xona_id) === String(b.xona_id))
      if (g && g.koykalar[0]) {
        set('koyka_id', String(g.koykalar[0].id))
        setBronXabar(`Bron boʻyicha ${b.xona}-xona tanlandi.`)
      } else {
        setBronXabar(`Bronda ${b.xona}-xona kelishilgan edi, lekin hozir unda `
          + 'boʻsh koyka yoʻq — boshqa xona tanlang.')
      }
    } else {
      setBronXabar('Bron xonasiz edi — xonani shu yerdan tanlang.')
    }
    setBronPisand(true)
  }

  async function saqla() {
    setXato('')
    if (!v.familiya.trim() || !v.ism.trim()) return setXato('Familiya va ismni kiriting.')
    if (v.telefon.replace(/\D/g, '').length < 9) return setXato('Telefon raqamini toʻliq kiriting.')
    if (takror && !qayta) return setXato('Bu telefon raqami band. Mavjud bemorni oching yoki qayta qabul qiling.')
    if (!v.yosh || Number(v.yosh) <= 0) return setXato('Yoshni kiriting.')
    if (v.reja_chiqish <= v.kirish) return setXato('Rejadagi chiqish sanasi kirish sanasidan keyin boʻlishi kerak.')
    if (!v.koyka_id) return setXato('Xonani tanlang. Bemor keyinroq kelsa — Bronlar boʻlimidan joy band qiling.')

    for (const h of hamrohlar) {
      const nom = ROL_NOM[h.roli].toLowerCase()
      if (!h.familiya.trim() || !h.ism.trim()) return setXato(`Hamroh (${nom}) familiya va ismini kiriting.`)
      if (!h.yosh || Number(h.yosh) <= 0) return setXato(`Hamroh (${nom}) yoshini kiriting.`)
      if (!h.koyka_id) return setXato(`Hamroh (${nom}) uchun ham koyka tanlang.`)
    }

    setBand(true)
    const { data, error } = await amal.bemorQabul({
      familiya: v.familiya.trim(), ism: v.ism.trim(), jins: v.jins,
      telefon: v.telefon.trim(), yosh: Number(v.yosh), chet_el: v.chet_el,
      koyka_id: v.koyka_id ? Number(v.koyka_id) : null,
      kirish: v.kirish, reja_chiqish: v.reja_chiqish,
      oldindan: v.oldindan ? Number(v.oldindan) : 0,
      bemor_id: qayta ? qayta.id : null,
      hamrohlar: hamrohlar.map((h) => ({
        roli: h.roli,
        familiya: h.familiya.trim(),
        ism: h.ism.trim(),
        jins: h.jins,
        yosh: Number(h.yosh),
        telefon: v.telefon.trim(),
        chet_el: v.chet_el,
        koyka_id: h.koyka_id ? Number(h.koyka_id) : null
      }))
    })
    if (error) { setBand(false); return setXato(xatoMatni(error)) }

    /* Bron bo'yicha kelgan bo'lsa — bronni qabul qilindi deb belgilaymiz.
       Bemor allaqachon yozilgan, shuning uchun bu qadam xato bersa ham
       ro'yxatga olishni bekor qilmaymiz — faqat aytamiz. */
    let ogoh = ''
    /* Tashxis alohida yoziladi — bemor_qabul() imzosiga tegmaslik uchun.
       Bu qadam xato bersa ham bemor allaqachon ro'yxatda, shuning
       uchun ro'yxatga olishni bekor qilmaymiz, faqat aytamiz. */
    if (v.tashxis.trim() && data) {
      const { error: te } = await amal.tashxisYoz(Number(data), v.tashxis.trim())
      if (te) ogoh = ' (tashxis yozilmadi — kartadan qoʻshing)'
    }
    /* Otasining ismi, tugʻilgan sana, manzil — xuddi tashxis kabi
       alohida yoziladi. Hech biri to'ldirilmagan bo'lsa so'rov
       umuman yuborilmaydi. */
    const malumotBorMi = v.otasining_ismi.trim() || v.tugilgan_sana || v.viloyat.trim()
      || v.tuman.trim() || v.mahalla.trim() || v.kocha.trim() || v.uy_raqami.trim() || v.kvartira.trim()
    if (malumotBorMi && data) {
      const { error: me } = await amal.bemorMalumot(Number(data), {
        otasining_ismi: v.otasining_ismi.trim(),
        tugilgan_sana: v.tugilgan_sana || null,
        viloyat: v.chet_el ? '' : v.viloyat.trim(),
        tuman: v.chet_el ? '' : v.tuman.trim(),
        mahalla: v.mahalla.trim(), kocha: v.kocha.trim(),
        uy_raqami: v.uy_raqami.trim(), kvartira: v.kvartira.trim(),
        fuqaroligi: v.chet_el ? v.viloyat.trim() : ''
      })
      if (me) ogoh = ' (qoʻshimcha maʼlumotlar yozilmadi — kartadan qoʻshing)'
    }
    if (bron?.bron_id && data) {
      const { error: be } = await amal.bronQabulBelgila(bron.bron_id, Number(data))
      if (be) ogoh = ' (bron belgilanmadi — Bronlar boʻlimidan qoʻlda yoping)'
    }
    setBand(false)

    tugadi(
      (hamrohlar.length
        ? `${v.familiya} ${v.ism} va ${hamrohlar.length} ta hamrohi roʻyxatga olindi.`
        : `${v.familiya} ${v.ism} roʻyxatga olindi.`) +
      (bron ? ' Bron yopildi.' : '') + ogoh
    )
  }

  return (
    <Modal sarlavha={bron ? 'Bron boʻyicha qabul qilish' : 'Yangi bemorni roʻyxatga olish'}
      yop={yop} kenglik={620}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Bekor qilish</button>
        <button className="btn pri" onClick={saqla} disabled={band}>
          {band ? 'Saqlanmoqda…' : 'Roʻyxatga olish'}
        </button>
      </>}>
      {bron && (
        <div className="alert info" style={{ marginBottom: 14, display: 'block' }}>
          <b>{sana(bron.kirish)} ga qoʻyilgan bron</b>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            {!bron.xona
              ? 'Xonasiz bron edi — endi xona tanlanadi. '
              : bronXonaBand
                ? `${bron.xona}-xona band qilingan edi, lekin hozir unda boʻsh koyka yoʻq — boshqa xona tanlang. `
                : `${bron.xona}-xona band qilingan — koyka shu xonadan tanlandi. `}
            Roʻyxatga olingach bron avtomatik yopiladi.
            {bron.izoh && <><br />Izoh: {bron.izoh}</>}
          </p>
        </div>
      )}
      {xato && <div className="alert err" style={{ marginBottom: 14 }}><span>▲</span><div>{xato}</div></div>}

      <div className="grid2">
        <div className="field">
          <label htmlFor="fam">Familiya</label>
          <input id="fam" value={v.familiya} onChange={(e) => set('familiya', e.target.value)} placeholder="Nazarov" />
        </div>
        <div className="field">
          <label htmlFor="ism">Ism</label>
          <input id="ism" value={v.ism} onChange={(e) => set('ism', e.target.value)} placeholder="Bekzod" />
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
          <label htmlFor="yosh">Yoshi</label>
          <input id="yosh" type="number" min="0" max="120" value={v.yosh}
            onChange={(e) => set('yosh', e.target.value)} placeholder="45" />
          <div className="hint">Tarif yoshga qarab hisoblanadi.</div>
        </div>

        <div className="field full">
          <label htmlFor="tel">Telefon raqami</label>
          <input id="tel" type="tel" value={v.telefon} onChange={(e) => set('telefon', e.target.value)}
            placeholder="+998 90 000 00 00" />
          {takror && !qayta && (
            <div className="alert err" style={{ marginTop: 8, display: 'block' }}>
              <b>Bu raqam band — {takror.fish}</b>
              <p className="muted" style={{ margin: '3px 0 9px' }}>
                {takror.jins === 'erkak' ? 'Erkak' : 'Ayol'} · {takror.yosh} yosh
                {takror.oxirgi_tashrif && ` · oxirgi tashrif ${sana(takror.oxirgi_tashrif)}`}
              </p>
              <div className="row">
                <button type="button" className="btn sm" onClick={() => ochBemor(takror)}>
                  Kartasini ochish
                </button>
                <button type="button" className="btn pri sm" onClick={() => setQayta(takror)}>
                  Qayta qabul qilish
                </button>
              </div>
            </div>
          )}
          {/* 19_bron_bogla.sql: shu raqamga ochiq bron bormi.
              Xodim Bronlar ekraniga o'tmasdan yozayotgan bo'lsa
              ham, kelishilgan xona, sana va tashxis yo'qolmasin. */}
          {bronOgoh && (
            <div className="alert warn" style={{ marginTop: 8, display: 'block' }}>
              <b>Bu raqamga bron qilingan — {bronOgoh.ismi}</b>
              <p className="muted" style={{ margin: '3px 0 9px' }}>
                {sana(bronOgoh.kirish)} – {sana(bronOgoh.chiqish)}
                {bronOgoh.xona ? ` · ${bronOgoh.xona}-xona` : ' · xonasiz'}
                {bronOgoh.kishi > 1 && ` · ${bronOgoh.kishi} kishi`}
                {bronOgoh.tashxis && <><br />Tashxis: {bronOgoh.tashxis}</>}
                {bronOgoh.izoh && <><br />Izoh: {bronOgoh.izoh}</>}
              </p>
              <div className="row">
                <button type="button" className="btn pri sm" onClick={() => bronniOl(bronOgoh)}>
                  Bron boʻyicha qabul qilish
                </button>
                <button type="button" className="btn sm" onClick={() => setBronPisand(true)}>
                  Bu boshqa odam
                </button>
              </div>
            </div>
          )}
          {qayta && (
            <div className="alert ok" style={{ marginTop: 8 }}>
              <span>✓</span>
              <div>
                <b>{qayta.fish}</b> uchun yangi tashrif ochiladi — yangi yozuv yaratilmaydi,
                tarixi saqlanadi.{' '}
                <button type="button" className="btn sm" style={{ marginLeft: 6 }}
                  onClick={() => setQayta(null)}>Bekor</button>
              </div>
            </div>
          )}
        </div>

        <div className="field full">
          <label htmlFor="chet">Fuqaroligi</label>
          <select id="chet" value={v.chet_el ? '1' : '0'} onChange={(e) => set('chet_el', e.target.value === '1')}>
            <option value="0">Oʻzbekiston</option>
            <option value="1">Chet el fuqarosi</option>
          </select>
        </div>

        {/* 27_bemor_malumotlari.sql: bemor kartasida chiqadigan
            qo'shimcha ma'lumotlar. Hammasi ixtiyoriy — bo'sh
            qoldirilsa kartada qo'lda to'ldirish uchun joy qolaveradi. */}
        <div className="field">
          <label htmlFor="otasi">Otasining ismi</label>
          <input id="otasi" value={v.otasining_ismi}
            onChange={(e) => set('otasining_ismi', e.target.value)} placeholder="Baxtiyorovich" />
        </div>
        <div className="field">
          <label htmlFor="tugsana">Tugʻilgan sanasi</label>
          <input id="tugsana" type="date" value={v.tugilgan_sana}
            onChange={(e) => set('tugilgan_sana', e.target.value)} />
        </div>

        <div className="field">
          <label htmlFor="vil">{v.chet_el ? 'Fuqaroligi davlati' : 'Viloyat'}</label>
          <select id="vil" value={v.viloyat} onChange={(e) => set('viloyat', e.target.value)}>
            <option value="">— tanlanmagan —</option>
            {(v.chet_el ? SNG_DAVLATLAR : VILOYATLAR.map((r) => r.nomi)).map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        </div>
        {!v.chet_el && (
          <div className="field">
            <label htmlFor="tum">Tuman</label>
            <select id="tum" value={v.tuman} onChange={(e) => set('tuman', e.target.value)}
              disabled={!v.viloyat}>
              <option value="">— tanlanmagan —</option>
              {tumanlar.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </div>
        )}

        <div className="field">
          <label htmlFor="mfy">Mahalla</label>
          <input id="mfy" value={v.mahalla} onChange={(e) => set('mahalla', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="koch">Koʻcha</label>
          <input id="koch" value={v.kocha} onChange={(e) => set('kocha', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="uy">Uy raqami</label>
          <input id="uy" value={v.uy_raqami} onChange={(e) => set('uy_raqami', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="kv">Kvartira</label>
          <input id="kv" value={v.kvartira} onChange={(e) => set('kvartira', e.target.value)} />
        </div>

        <div className="field">
          <label htmlFor="kir">Kirish sanasi</label>
          <input id="kir" type="date" value={v.kirish} onChange={(e) => set('kirish', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="rej">Rejadagi chiqish</label>
          <input id="rej" type="date" value={v.reja_chiqish} min={qoshKun(v.kirish, 1)}
            onChange={(e) => set('reja_chiqish', e.target.value)} />
          <div className="hint">1 kurs = {ref_.kursKun} kun.</div>
        </div>

        <div className="field full">
          <label htmlFor="koyka">Xona va koyka</label>
          <select id="koyka" value={v.koyka_id} onChange={(e) => set('koyka_id', e.target.value)}>
            <option value="">— xonani tanlang —</option>
            {joylar.map((g) => (
              <optgroup key={g.xona_id} label={`${g.xona}-xona · ${g.bolim}`}>
                {g.koykalar.map((k) => (
                  <option key={k.id} value={k.id}>{g.xona}-xona · {k.raqam}-koyka</option>
                ))}
              </optgroup>
            ))}
          </select>
          <div className="hint">
            {bronXabar ? <b>{bronXabar}</b> : joylar.length === 0
              ? 'Bu jins uchun boʻsh joy yoʻq. Bemor keyinroq kelsa — Bronlar boʻlimidan joy band qiling.'
              : 'Xona tanlash majburiy. Roʻyxatda faqat jinsi mos keladigan boʻsh koykalar bor.'}
          </div>
        </div>

        <div className="field full">
          <label htmlFor="tash">Kasallik tashxisi</label>
          <input id="tash" value={v.tashxis} onChange={(e) => set('tashxis', e.target.value)}
            placeholder="Bel ogʻrigʻi, osteoxondroz" />
          <div className="hint">Kasallik varaqasiga bosilib chiqadi. Keyin oʻzgartirsa boʻladi.</div>
        </div>

        {/* Oldindan toʻlov — kassa ishi. Registrator pulga tegmaydi. */}
        {can('pul') && (
          <div className="field full">
            <label htmlFor="old">Oldindan toʻlov (ixtiyoriy)</label>
            <input id="old" type="number" min="0" step="10000" value={v.oldindan}
              onChange={(e) => set('oldindan', e.target.value)} placeholder="0" />
          </div>
        )}
      </div>

      {/* ---------- hamrohlar ---------- */}
      <div className="bolim-bosh">
        <h4>Hamrohlar</h4>
        <span className="sp" />
        <button type="button" className="btn sm" onClick={() => hQosh('farzand')}>+ Farzand</button>
        <button type="button" className="btn sm" onClick={() => hQosh('qarovchi')}>+ Qarovchi</button>
      </div>

      {hamrohlar.length === 0 ? (
        <div className="hint">
          Farzand yoki qarovchi shu yerda qoʻshiladi — ular avtomatik shu bemorga biriktiriladi.
          Telefon raqami bemornikidan olinadi.
        </div>
      ) : hamrohlar.map((h) => {
        const hJoylar = joylarUchun(h.jins, h.koyka_id)
        const jinsFarq = h.jins !== v.jins
        return (
          <div className="hamroh" key={h.kalit}>
            <div className="hamroh-h">
              <span className={`pill ${h.roli === 'qarovchi' ? 'booked' : 'free'}`}>
                {ROL_NOM[h.roli]}
              </span>
              <span className="sp" />
              <button type="button" className="btn icon sm" onClick={() => hOchir(h.kalit)}
                aria-label="Olib tashlash">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                  strokeWidth="2.2" strokeLinecap="round"><path d="M18 6 6 18M6 6l12 12" /></svg>
              </button>
            </div>
            <div className="grid2">
              <div className="field">
                <label>Familiya</label>
                <input value={h.familiya} onChange={(e) => hSet(h.kalit, 'familiya', e.target.value)} />
              </div>
              <div className="field">
                <label>Ism</label>
                <input value={h.ism} onChange={(e) => hSet(h.kalit, 'ism', e.target.value)} />
              </div>
              <div className="field">
                <label>Jinsi</label>
                <div className="seg">
                  <button type="button" className={h.jins === 'erkak' ? 'on erkak' : ''}
                    onClick={() => hSet(h.kalit, 'jins', 'erkak')}>Erkak</button>
                  <button type="button" className={h.jins === 'ayol' ? 'on ayol' : ''}
                    onClick={() => hSet(h.kalit, 'jins', 'ayol')}>Ayol</button>
                </div>
              </div>
              <div className="field">
                <label>Yoshi</label>
                <input type="number" min="0" max="120" value={h.yosh}
                  onChange={(e) => hSet(h.kalit, 'yosh', e.target.value)} />
              </div>
              <div className="field full">
                <label>Xona va koyka</label>
                <select value={h.koyka_id} onChange={(e) => hSet(h.kalit, 'koyka_id', e.target.value)}>
                  <option value="">— koykani tanlang —</option>
                  {hJoylar.map((g) => (
                    <optgroup key={g.xona_id} label={`${g.xona}-xona · ${g.bolim}`}>
                      {g.koykalar.map((k) => (
                        <option key={k.id} value={k.id}>{g.xona}-xona · {k.raqam}-koyka</option>
                      ))}
                    </optgroup>
                  ))}
                </select>
                {jinsFarq && (
                  <div className="hint">
                    Bemordan boshqa jinsda — birga faqat aralash (Oilaviy yoki Premium)
                    boʻlim xonasida yotishi mumkin.
                  </div>
                )}
              </div>
            </div>
          </div>
        )
      })}
    </Modal>
  )
}

/* ============================================================
   BEMOR KARTASI
   ============================================================ */
function BemorKarta({ y, rol, can, ochish, yop, tugadi, yangila }) {
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)

  const [hamroh, setHamroh] = useState([])
  const [aylantir, setAylantir] = useState(false)
  const [qarovchigaAylantir, setQarovchigaAylantir] = useState(false)
  const [damBand, setDamBand] = useState(false)
  const [tab, setTab] = useState('malumot')
  /* karta qaysi varagʻi koʻrsatilyapti/chiqarilyapti: 'tash' yoki 'ich' */
  const [tomon, setTomon] = useState('tash')

  const kartaChop = useCallback((t) => {
    const nom = t === 'tash' ? 'tashqi varaq'
      : t === 'ich' ? 'ichki varaq' : 'ikkala varaq'
    chopEt({
      html: kartaHtml(y, t), css: kartaCss,
      sarlavha: `Kasallik varaqasi — ${y.fish} (${nom})`
    })
  }, [y])

  const qarz = Number(y.qarz) || 0
  const faol = y.holat === 'yotmoqda'

  /* OLDINDAN TO'LOV ≠ ORTIQCHA TO'LOV.
     Yotgan bemor butun kursni oldindan to'lagan bo'lsa, hisob
     kunlar bo'yicha o'sib boradi — "to'langan > hisob" holati
     normal, pul qaytarilmaydi: u kursni yotib o'taydi.
       ortiqcha    — chiqib ketgan bemorda: hisob muzlagan,
                     farq rostdan bemorniki, qaytarilishi kerak.
       qaytariladi — yotgan bemorda: BUGUN ketsa qancha qaytishi.
                     Ogohlantirish emas, chiqarish oynasidagi raqam. */
  const farq = Math.max(0, (Number(y.tolangan) || 0) - (Number(y.umumiy) || 0))
  const ortiqcha = faol ? 0 : farq
  const qaytariladi = faol ? farq : 0

  const [qaytarmasdan, setQaytarmasdan] = useState(false)
  const [sabab, setSabab] = useState('')
  /* Xato yozuvni oʻchirish — faqat adminda */
  const [ochirOchiq, setOchirOchiq] = useState(false)
  const [ochirSabab, setOchirSabab] = useState('')
  /* Chiqarish tasdig'i: pul qaytariladigan bo'lsa ochiladi */
  const [chiqarOchiq, setChiqarOchiq] = useState(false)
  const [chusuli, setChusuli] = useState('naqd')

  useEffect(() => {
    if (!y.hamroh_soni) return
    let bekor = false
    db.hamrohlar(y.yotqizish_id).then(({ data }) => { if (!bekor) setHamroh(data || []) })
    return () => { bekor = true }
  }, [y.yotqizish_id, y.hamroh_soni])

  async function qarovchidanBemorga() {
    setXato(''); setBand(true)
    const { data, error } = await amal.qarovchiniBemorga(y.yotqizish_id)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    const r = (data || [])[0]
    /* Endi bu "bemor" — kartasi uchun otasining ismi, tugʻilgan
       sanasi, manzili kerak boʻladi. Xabar bilan birga shu forma
       darhol ochiladi, unutilib qolmasin. */
    if (yangila) yangila(r && can('pul')
      ? `${y.fish} bemorga aylantirildi. ${r.qarovchi_kuni} kun qarovchi (${som(r.qarovchi_puli)}) + yangi kurs (${som(r.bemor_puli)}) = ${som(r.yangi_summa)}.`
      : `${y.fish} bemorga aylantirildi.`)
    ochish('malumotTahrir')
  }

  async function bemordanQarovchiga() {
    setXato(''); setBand(true)
    const { data, error } = await amal.bemorniQarovchiga(y.yotqizish_id)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    const r = (data || [])[0]
    setQarovchigaAylantir(false)
    tugadi(r
      ? `${y.fish} qarovchiga aylantirildi. ${r.bemor_kuni} kun davolanish (${som(r.bemor_puli)}) hisoblandi.`
      : `${y.fish} qarovchiga aylantirildi.`)
  }

  /* DAVOLANISH <-> DAM OLISH — joriy bosqich muzlaydi (qarz bo'lsa
     xatolik chiqadi, avval to'lov qabul qilish kerak), yangi bosqich
     bugundan boshlanadi (28_dam_olish.sql). */
  async function holatniOzgartir(yangiHolat) {
    setXato(''); setDamBand(true)
    const { data, error } = await amal.holatOzgartir(y.yotqizish_id, yangiHolat)
    setDamBand(false)
    if (error) return setXato(xatoMatni(error))
    const r = (data || [])[0]
    tugadi(r
      ? `${y.fish}: ${r.yakunlangan_kun} kunlik oldingi bosqich ${som(r.yakunlangan_summa)} qilib hisoblandi. Endi: ${yangiHolat === 'dam_olish' ? 'dam olmoqda' : 'davolanmoqda'}.`
      : `${y.fish} holati oʻzgartirildi.`)
  }

  async function chiqar() {
    /* Pul qaytariladigan bo'lsa oddiy chiqarish ishlamaydi (baza ham
       ruxsat bermaydi) — kassirdan tasdiq so'raymiz. */
    if (qaytariladi > 0) { setXato(''); setChiqarOchiq(true); return }
    setXato(''); setBand(true)
    const { error } = await amal.bemorChiqar(y.yotqizish_id)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    tugadi(`${y.fish} chiqarildi.`)
  }

  /* CHIQARISH VA PULNI QAYTARISH — bitta amalda.
     Bazada bitta tranzaksiya: bemor chiqadi, hisob muzlaydi,
     ortiqcha pul qaytariladi va tilxat raqami qaytadi. */
  async function chiqarVaQaytar() {
    setXato(''); setBand(true)
    const { data, error } = await amal.chiqarQaytarib(y.yotqizish_id, chusuli)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    const r = (data || [])[0]
    const s = Number(r?.qaytarildi) || 0
    setChiqarOchiq(false)
    /* Tilxat darhol printerga — bemor imzo chekib pulni oladi */
    if (r?.tolov_id) {
      const { data: c } = await db.chek(r.tolov_id)
      const ch = (c || [])[0]
      if (ch) chopEt({
        html: chekHtml(ch), css: chekCss,
        sarlavha: `Tilxat ${ch.chek_raqam}`
      })
    }
    tugadi(s > 0
      ? `${y.fish} chiqarildi. ${som(s)} qaytarildi${r?.chek_raqam ? `, tilxat ${r.chek_raqam}` : ''}.`
      : `${y.fish} chiqarildi.`)
  }

  /* Super admin: pul bemorga qaytarilmaydi, xizmat hisobiga o'tadi.
     Hisob ko'tariladi, sabab yozuvda qoladi — hisob-kitob yopiladi. */
  async function chiqarQaytarmasdan() {
    if (!sabab.trim()) return setXato('Sababni yozing — pul bemorga qaytarilmayapti.')
    setXato(''); setBand(true)
    const { data, error } = await amal.chiqarOrtiqchaBilan(y.yotqizish_id, sabab.trim())
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    setQaytarmasdan(false); setChiqarOchiq(false)
    tugadi(`${y.fish} chiqarildi. ${som(data ?? qaytariladi)} xizmat hisobiga oʻtkazildi.`)
  }

  /* Chiqib ketgan bemorda ortiqcha qolgan bo'lsa — faqat hisobni yopamiz */
  async function hisobgaOtkaz() {
    if (!sabab.trim()) return setXato('Sababni yozing — pul bemorga qaytarilmayapti.')
    setXato(''); setBand(true)
    const { data, error } = await amal.ortiqchaHisobga(y.yotqizish_id, sabab.trim())
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    setQaytarmasdan(false)
    tugadi(`${som(data ?? ortiqcha)} xizmat hisobiga oʻtkazildi — hisob yopildi.`)
  }

  /* XATO YOZUVNI OʻCHIRISH (faqat admin)
     Toʻlovi boʻlmasa baza yozuvni butunlay oʻchiradi, toʻlov
     boʻlsa — "bekor" deb belgilaydi. Qaysi yoʻl bilan ketgani
     javobdagi xabarda aytiladi. */
  async function ochir() {
    setXato(''); setBand(true)
    const { data, error } = await amal.bemorOchir(
      y.yotqizish_id, ochirSabab.trim() || null)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    const r = (data || [])[0]
    setOchirOchiq(false)
    tugadi(r?.xabar || `${y.fish} oʻchirildi.`)
  }

  /* Toʻlov tarixi faqat pulni koʻradiganlarga */
  const TABLAR = [
    { k: 'malumot', n: 'Maʼlumot' },
    { k: 'karta', n: 'Karta olish' },
    ...(can('pul') ? [{ k: 'tolov', n: 'Toʻlov tarixi' }] : [])
  ]

  return (
    <Modal sarlavha="Bemor kartasi" yop={yop} kenglik={560}
      amallar={
        tab === 'karta' ? (
          <>
            <button className="btn" onClick={yop}>Yopish</button>
            {TOMONLAR.map((t) => (
              <button key={t.k}
                className={'btn' + (t.k === tomon ? ' pri' : '')}
                onClick={() => { setTomon(t.k); kartaChop(t.k) }}>
                {t.n}
              </button>
            ))}
          </>
        ) : tab === 'tolov' ? (
          <button className="btn" onClick={yop}>Yopish</button>
        ) : faol && (can('uzaytir') || can('chiqar') || can('tolov')) ? (
          <>
            {can('uzaytir') && <button className="btn" onClick={() => ochish('uzaytir')}>Muddatni uzaytirish</button>}
            {/* Qarz bo'lsa chiqarish yopiq. Kassirni boshi berk ko'chada
                qoldirmaslik uchun to'g'ridan-to'g'ri to'lovga o'tkazamiz. */}
            {can('tolov') && qarz > 0 && (
              <button className="btn pri" onClick={() => setTab('tolov')}>
                Toʻlov qabul qilish
              </button>
            )}
            {can('chiqar') && (
              <button className="btn dan" onClick={chiqar}
                disabled={band || qarz > 0 || chiqarOchiq}
                title={qarz > 0 ? 'Qarzdorlik mavjud'
                  : chiqarOchiq ? 'Pastdagi tasdiqni toʻldiring' : undefined}>
                {band ? '…' : qaytariladi > 0 ? 'Chiqarish va pulni qaytarish' : 'Chiqarish'}
              </button>
            )}
          </>
        ) : /* kuzatuvchida amal yo'q — bo'sh panel qolmasin */
          <button className="btn" onClick={yop}>Yopish</button>
      }>

      <div className="karta-bosh">
        <div>
          <h3>{y.fish}</h3>
          <div className="muted">
            {y.jins === 'erkak' ? 'Erkak' : 'Ayol'} · {y.yosh} yosh
            {y.roli !== 'bemor' && ` · ${ROL_NOM[y.roli]}`}
            {y.chet_el && ' · chet el fuqarosi'}
          </div>
          {y.asosiy_fish && (
            <div className="muted" style={{ marginTop: 2 }}>
              <b>{y.asosiy_fish}</b> ning {ROL_NOM[y.roli].toLowerCase()}i
            </div>
          )}
        </div>
        <div className="row" style={{ gap: 6, flexWrap: 'nowrap' }}>
          {faol && y.roli === 'bemor' && y.holat_turi === 'dam_olish' && (
            <span className="pill partial">Dam olmoqda</span>
          )}
          <HolatPill y={y} />
        </div>
      </div>

      <div className="tablar">
        {TABLAR.map((t) => (
          <button key={t.k} className={`tab${tab === t.k ? ' on' : ''}`}
            onClick={() => setTab(t.k)}>{t.n}</button>
        ))}
      </div>

      {xato && <div className="alert err" style={{ marginBottom: 12 }}><span>▲</span><div>{xato}</div></div>}

      {tab === 'karta' && (
        <KartaTab y={y} tomon={tomon} setTomon={setTomon} chop={kartaChop} />
      )}
      {tab === 'tolov' && <TolovTab y={y} can={can} yangila={yangila || tugadi} />}

      {tab === 'malumot' && <>
      <dl className="dl">
        <dt>Telefon</dt>
        <dd><a href={`tel:${(y.telefon || '').replace(/\s/g, '')}`}>{y.telefon || '—'}</a></dd>
        <dt>Joyi</dt>
        <dd>{y.xonada ? `${y.bolim} · ${y.xona}-xona · ${y.koyka}-koyka` : 'Joylashtirilmagan'}</dd>
        <dt>Kirgan</dt><dd>{sana(y.kirish_sana)}</dd>
        <dt>Reja boʻyicha</dt><dd>{sana(y.reja_chiqish)}</dd>
        {y.haqiqiy_chiqish && (
          <>
            <dt>Haqiqatda chiqqan</dt>
            <dd>
              {sana(y.haqiqiy_chiqish)}
              {y.reja_farqi < 0 && <span className="pill booked" style={{ marginLeft: 8 }}>
                {Math.abs(y.reja_farqi)} kun erta</span>}
            </dd>
          </>
        )}
        <dt>Yotgan kun</dt><dd className="num">{y.yotgan_kun}</dd>
        <dt>Tashxis</dt>
        <dd><Tashxis y={y} can={can} yangila={yangila} /></dd>
      </dl>

      {y.roli === 'bemor' && can('royxat') && (
        <button className="btn sm" style={{ marginBottom: 10 }}
          onClick={() => ochish('malumotTahrir')}>
          Otasining ismi, manzil, tugʻilgan sana — tahrirlash
        </button>
      )}

      {can('pul') && (
        <div className="pul pul4">
          <div><span>Kurs boʻyicha</span><b className="num muted">{som(y.kurs_summa)}</b></div>
          <div><span>{y.holat === 'chiqdi' ? 'Yakuniy' : 'Hozirgacha'}</span>
            <b className="num">{som(y.umumiy)}</b></div>
          <div><span>Toʻlangan</span><b className="num" style={{ color: 'var(--free)' }}>{som(y.tolangan)}</b></div>
          {ortiqcha > 0 ? (
            <div><span>Qaytariladi</span>
              <b className="num" style={{ color: 'var(--partial)' }}>{som(ortiqcha)}</b></div>
          ) : (
            <div><span>Qarz</span><b className="num" style={{ color: qarz > 0 ? 'var(--full)' : 'var(--ink-3)' }}>
              {som(qarz)}</b></div>
          )}
        </div>
      )}
      {can('pul') && faol && y.xonada && Number(y.umumiy) < Number(y.kurs_summa) && (
        <div className="hint" style={{ marginTop: 8 }}>
          Hisob yotgan kunlar boʻyicha boradi — {y.yotgan_kun} kun. Bemor bugun ketsa
          shu summani toʻlab qarzsiz chiqadi; kursni oxirigacha yotsa {som(y.kurs_summa)} boʻladi.
        </div>
      )}

      {hamroh.length > 0 && (
        <div className="hamroh-royxat">
          <div className="bolim-bosh"><h4>Hamrohlari</h4></div>
          {hamroh.map((h) => (
            <div className="hamroh-qator" key={h.yotqizish_id}>
              <span className={`pill ${h.roli === 'qarovchi' ? 'booked' : 'free'}`}>
                {ROL_NOM[h.roli]}
              </span>
              <div className="body">
                <div className="nm">{h.fish}</div>
                <div className="sb">
                  {h.jins === 'erkak' ? 'Erkak' : 'Ayol'} · {h.yosh} yosh
                  {h.xona ? ` · ${h.xona}-xona · ${h.koyka}-koyka` : ' · xonasiz'}
                </div>
              </div>
              {can('pul') && <span className="num muted">{som(h.summa)}</span>}
            </div>
          ))}
        </div>
      )}

      {faol && y.roli === 'qarovchi' && can('royxat') && (
        aylantir ? (
          <div className="alert info" style={{ marginTop: 14, display: 'block' }}>
            <b>Qarovchi bemorga aylanadi</b>
            <p className="muted" style={{ margin: '4px 0 10px' }}>
              Qarovchi sifatida yotgan kunlari kunlik hisobda qoʻshiladi, soʻng bugundan
              yangi kurs boshlanadi. Chiqish sanasi ham yangilanadi.
            </p>
            <div className="row">
              <button className="btn sm" onClick={() => setAylantir(false)} disabled={band}>Bekor</button>
              <button className="btn pri sm" onClick={qarovchidanBemorga} disabled={band}>
                {band ? '…' : 'Tasdiqlash'}
              </button>
            </div>
          </div>
        ) : (
          <button className="btn block" style={{ marginTop: 14 }} onClick={() => setAylantir(true)}>
            Bemorga aylantirish
          </button>
        )
      )}

      {/* DAVOLANISH <-> DAM OLISH (28_dam_olish.sql). Faqat asosiy
          bemorga, xonada yotganida. Qarz bo'lsa baza o'zi rad qiladi —
          xato xabarida "avval to'lovni qabul qiling" deb chiqadi. */}
      {faol && y.roli === 'bemor' && y.xonada && can('dam_olish') && (
        <div className="alert info" style={{ marginTop: 14, display: 'block' }}>
          <b>{y.holat_turi === 'dam_olish' ? 'Bemor hozir dam olmoqda' : 'Bemor hozir davolanmoqda'}</b>
          <p className="muted" style={{ margin: '4px 0 10px' }}>
            {y.holat_turi === 'dam_olish'
              ? 'Dam olish kunlik narx boʻyicha hisoblanmoqda. Davolanishni davom ettirsa — bu YANGI KURS boʻladi va toʻliq kurs narxi yoziladi.'
              : 'Davolanishni toʻxtatib, shu xonada dam olishga oʻtkazish mumkin — narx kunlik (xona turiga qarab) hisoblanadi.'}
          </p>
          <button className="btn pri sm" disabled={damBand}
            onClick={() => holatniOzgartir(y.holat_turi === 'dam_olish' ? 'davolanish' : 'dam_olish')}>
            {damBand ? '…' : y.holat_turi === 'dam_olish'
              ? 'Davolanishni boshlash (yangi kurs)'
              : 'Dam olishga oʻtkazish'}
          </button>
        </div>
      )}

      {faol && y.roli === 'bemor' && !y.hamroh_soni && can('royxat') && (
        qarovchigaAylantir ? (
          <div className="alert info" style={{ marginTop: 14, display: 'block' }}>
            <b>Bemor qarovchiga aylanadi</b>
            <p className="muted" style={{ margin: '4px 0 10px' }}>
              Hozirgacha davolangan kunlari hisobda qoʻshiladi, soʻng bugundan
              qarovchi tarifi bilan davom etadi.
            </p>
            <div className="row">
              <button className="btn sm" onClick={() => setQarovchigaAylantir(false)} disabled={band}>Bekor</button>
              <button className="btn pri sm" onClick={bemordanQarovchiga} disabled={band}>
                {band ? '…' : 'Tasdiqlash'}
              </button>
            </div>
          </div>
        ) : (
          <button className="btn block" style={{ marginTop: 14 }} onClick={() => setQarovchigaAylantir(true)}>
            Qarovchiga aylantirish
          </button>
        )
      )}

      {faol && !y.xonada && can('joylash') && (
        <button className="btn block" style={{ marginTop: 14 }} onClick={() => ochish('joylash')}>
          Xonaga joylashtirish
        </button>
      )}
      {faol && y.xonada && can('joylash') && (
        <button className="btn block" style={{ marginTop: 14 }} onClick={() => ochish('joylash')}>
          Xonani almashtirish
        </button>
      )}

      {can('pul') && faol && qarz > 0 && (
        <div className="alert warn" style={{ marginTop: 14 }}>
          <span>◇</span>
          <div>
            <b>Chiqarish yopiq — {som(qarz)} qarz bor.</b> Buxgalter toʻlovni qabul qilib chek
            beradi, chek qorovulga topshiriladi. Qarz nolga tushgach tugma ochiladi.
          </div>
        </div>
      )}

      {/* ---------- ERTA KETYAPTI: chiqarishda pul qaytariladi ----------
          Bu ogohlantirish emas — oldindan toʻlov normal holat.
          Faqat "bugun ketsa shuncha qaytadi" deb aytib turadi. */}
      {can('pul') && faol && qaytariladi > 0 && (
        <div className="alert info" style={{ marginTop: 14, display: 'block' }}>
          <b>Bemor bugun ketsa {som(qaytariladi)} qaytariladi.</b>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            Oldindan {som(y.tolangan)} toʻlangan, bugungi hisob {som(y.umumiy)}.
            Erta ketgani uchun hisob kamayadi, farqi bemorniki — u chiqarish
            paytida kassadan qaytariladi va tilxat chiqadi.
          </p>

          {can('chiqar') && !chiqarOchiq && (
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn pri sm" onClick={() => setChiqarOchiq(true)}>
                Chiqarish va pulni qaytarish
              </button>
            </div>
          )}

          {/* Tasdiq: kassir pulni qanday qaytarayotganini belgilaydi */}
          {chiqarOchiq && can('chiqar') && (
            <div className="tolov-forma" style={{ marginTop: 12 }}>
              <div className="pul" style={{ marginTop: 0, marginBottom: 10 }}>
                <div><span>Yakuniy hisob</span><b className="num">{som(y.umumiy)}</b></div>
                <div><span>Toʻlangan</span>
                  <b className="num" style={{ color: 'var(--free)' }}>{som(y.tolangan)}</b></div>
                <div><span>Qaytariladi</span>
                  <b className="num" style={{ color: 'var(--partial)' }}>{som(qaytariladi)}</b></div>
              </div>
              <div className="field">
                <label htmlFor="chu">Pul qanday qaytariladi</label>
                <select id="chu" value={chusuli} onChange={(e) => setChusuli(e.target.value)}
                  disabled={band}>
                  <option value="naqd">Naqd</option>
                  <option value="karta">Plastik karta</option>
                  <option value="otkazma">Oʻtkazma</option>
                </select>
                <div className="hint">
                  Bemor chiqariladi va {som(qaytariladi)} oʻsha zahoti qaytariladi —
                  ikkalasi bitta amalda. Tilxat printerga chiqadi, bemor imzo chekadi.
                </div>
              </div>
              <div className="row" style={{ marginTop: 10 }}>
                <button className="btn sm" onClick={() => setChiqarOchiq(false)} disabled={band}>
                  Bekor
                </button>
                {rol === 'super_admin' && !qaytarmasdan && (
                  <button className="btn sm" onClick={() => setQaytarmasdan(true)} disabled={band}>
                    Qaytarmasdan chiqarish
                  </button>
                )}
                <span className="sp" />
                <button className="btn pri sm" onClick={chiqarVaQaytar} disabled={band}>
                  {band ? '…' : `Chiqarish va ${som(qaytariladi)} qaytarish`}
                </button>
              </div>

              {/* Pul bemorga berilmaydi — xizmat hisobiga oʻtadi */}
              {qaytarmasdan && rol === 'super_admin' && (
                <div className="field" style={{ marginTop: 12 }}>
                  <label htmlFor="qsab">Nega qaytarilmaydi?</label>
                  <input id="qsab" value={sabab} onChange={(e) => setSabab(e.target.value)}
                    placeholder="masalan: bemor qaytarib olishdan bosh tortdi" disabled={band} />
                  <div className="hint">
                    {som(qaytariladi)} xizmat hisobiga oʻtkaziladi — kassadan pul
                    chiqmaydi, sabab bemor yozuvida qoladi.
                  </div>
                  <div className="row" style={{ marginTop: 10 }}>
                    <button className="btn sm" onClick={() => setQaytarmasdan(false)} disabled={band}>
                      Bekor
                    </button>
                    <span className="sp" />
                    <button className="btn dan sm" onClick={chiqarQaytarmasdan} disabled={band}>
                      {band ? '…' : 'Qaytarmasdan chiqarish'}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* ---------- CHIQIB KETGAN, PUL HALI QAYTARILMAGAN ---------- */}
      {can('pul') && ortiqcha > 0 && (
        <div className="alert warn" style={{ marginTop: 14, display: 'block' }}>
          <b>Bemorga {som(ortiqcha)} qaytarilishi kerak.</b>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            Yakuniy hisob {som(y.umumiy)}, toʻlangani {som(y.tolangan)} — farqi bemorniki.
          </p>
          {can('tolov') && (
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn pri sm" onClick={() => setTab('tolov')}>
                Pulni qaytarish
              </button>
              {rol === 'super_admin' && !qaytarmasdan && (
                <button className="btn sm" onClick={() => setQaytarmasdan(true)}>
                  Qaytarmasdan yopish
                </button>
              )}
            </div>
          )}

          {/* Pul bemorga qaytarilmaydi — sababi yoziladi va hisob yopiladi */}
          {qaytarmasdan && rol === 'super_admin' && (
            <div className="tolov-forma" style={{ marginTop: 12 }}>
              <div className="field">
                <label htmlFor="qsab2">Nega qaytarilmaydi?</label>
                <input id="qsab2" value={sabab} onChange={(e) => setSabab(e.target.value)}
                  placeholder="masalan: bemor qaytarib olishdan bosh tortdi" disabled={band} />
                <div className="hint">
                  {som(ortiqcha)} xizmat hisobiga oʻtkaziladi — kassadan pul chiqmaydi,
                  sabab bemor yozuvida qoladi. Bemor allaqachon chiqarilgan, faqat
                  hisob yopiladi.
                </div>
              </div>
              <div className="row" style={{ marginTop: 10 }}>
                <button className="btn sm" onClick={() => setQaytarmasdan(false)} disabled={band}>
                  Bekor
                </button>
                <span className="sp" />
                <button className="btn dan sm" onClick={hisobgaOtkaz} disabled={band}>
                  {band ? '…' : 'Hisobni yopish'}
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ---------- XATO YOZUVNI OʻCHIRISH (faqat admin) ---------- */}
      {rol === 'super_admin' && (
        <div style={{ marginTop: 18 }}>
          <div className="bolim-bosh"><h4>Xatoni tuzatish</h4></div>

          {!ochirOchiq ? (
            <>
              <div className="muted" style={{ maxWidth: '64ch' }}>
                Bemor xato kiritilgan boʻlsa (ikki marta yozilgan, boshqa odam
                tanlangan) yozuvni oʻchirib tashlash mumkin.
              </div>
              <button className="btn dan sm" style={{ marginTop: 10 }}
                onClick={() => setOchirOchiq(true)} disabled={band}>
                Bemorni oʻchirish
              </button>
            </>
          ) : (
            <div className="tolov-forma">
              <div className="field">
                <label htmlFor="osab">Nega oʻchirilyapti?</label>
                <input id="osab" value={ochirSabab} disabled={band}
                  onChange={(e) => setOchirSabab(e.target.value)}
                  placeholder="masalan: ikki marta kiritilgan" />
                <div className="hint">
                  Toʻlovi boʻlmasa yozuv butunlay oʻchadi — qarovchi va farzandlari
                  bilan birga. Toʻlov qabul qilingan boʻlsa <b>oʻchmaydi</b>:
                  “bekor qilindi” deb belgilanadi, sabab yozuvda qoladi, koyka
                  boʻshaydi, kassa hisoboti esa oʻzgarmaydi. Bu holda sabab yozish shart.
                </div>
              </div>
              <div className="row" style={{ marginTop: 10 }}>
                <button className="btn sm" disabled={band}
                  onClick={() => { setOchirOchiq(false); setOchirSabab('') }}>
                  Bekor
                </button>
                <span className="sp" />
                <button className="btn dan sm" onClick={ochir} disabled={band}>
                  {band ? '…' : 'Oʻchirish'}
                </button>
              </div>
            </div>
          )}
        </div>
      )}
      </>}
    </Modal>
  )
}

/* ============================================================
   TASHXIS — koʻrsatish va joyida tahrirlash
   ============================================================ */
function Tashxis({ y, can, yangila }) {
  const [tahrir, setTahrir] = useState(false)
  const [matn, setMatn] = useState(y.tashxis || '')
  const [band, setBand] = useState(false)
  const [xato, setXato] = useState('')
  const [joriy, setJoriy] = useState(y.tashxis || '')

  async function saqla() {
    setBand(true); setXato('')
    const { data, error } = await amal.tashxisYoz(y.yotqizish_id, matn.trim())
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    setJoriy(data || '')
    setTahrir(false)
    if (yangila) yangila('Tashxis saqlandi.')
  }

  if (!tahrir) {
    return (
      <span className="tashxis-satr">
        {joriy
          ? <span>{joriy}</span>
          : <span className="muted">kiritilmagan</span>}
        {can('royxat') && (
          <button className="matn" onClick={() => { setMatn(joriy); setTahrir(true) }}>
            {joriy ? 'oʻzgartirish' : 'qoʻshish'}
          </button>
        )}
      </span>
    )
  }

  return (
    <span className="tashxis-tahrir">
      <input value={matn} onChange={(e) => setMatn(e.target.value)}
        placeholder="Bel ogʻrigʻi, osteoxondroz" autoFocus
        onKeyDown={(e) => { if (e.key === 'Enter') saqla() }} />
      <button className="btn sm pri" onClick={saqla} disabled={band}>
        {band ? '…' : 'Saqlash'}
      </button>
      <button className="btn sm" onClick={() => setTahrir(false)} disabled={band}>Bekor</button>
      {xato && <div className="hint" style={{ color: 'var(--full)' }}>{xato}</div>}
    </span>
  )
}

/* ============================================================
   KARTA OLISH — kasallik varaqasining koʻrinishi va chop etish
   ============================================================ */
function KartaTab({ y, tomon, setTomon, chop }) {
  const src = useMemo(
    () => '<!doctype html><html lang="uz"><head><meta charset="utf-8"><style>' +
          kartaCss + '</style></head><body>' + kartaHtml(y, tomon) + '</body></html>',
    [y, tomon])

  const joriy = TOMONLAR.find((t) => t.k === tomon) || TOMONLAR[0]

  return (
    <>
      <div className="alert info" style={{ marginBottom: 12, display: 'block' }}>
        <b>Bitta A4 varaq, yotiq holatda — qogʻozdagi kartaning aynan oʻzi.</b>
        <p className="muted" style={{ margin: '4px 0 0' }}>
          Varaq oʻrtasidan buklanadi, 4 ta bet chiqadi. Printerda qogʻoz
          yoʻnalishini <b>“Landscape / Yotiq”</b> qilib qoʻying va
          <b> masshtabni 100%</b> da qoldiring. Avval <b>tashqi varaqni</b>{' '}
          chiqaring, soʻng qogʻozni agʻdarib <b>ichki varaqni</b> chiqaring.
        </p>
      </div>

      <div className="tablar" style={{ margin: '0 0 12px' }}>
        {TOMONLAR.map((t) => (
          <button key={t.k} className={'tab' + (t.k === tomon ? ' on' : '')}
            onClick={() => setTomon(t.k)}>
            {t.n}
          </button>
        ))}
      </div>

      <div className="karta-oldi-ram">
        <iframe className="karta-oldi" srcDoc={src}
          title={`Kasallik varaqasi — ${joriy.n}`} />
      </div>

      <div className="hint" style={{ marginTop: 8 }}>
        {joriy.tavsif}. Familiya, ism, telefon, xona raqami, kelgan sanasi va
        tashxis tizimdan toʻldiriladi; otasining ismi, manzil, tugʻilgan sanasi
        (т.й) va № qoʻlda yoziladi.{' '}
        <button className="matn" onClick={() => chop()}>
          Ikkala varaqni ketma-ket chiqarish
        </button>
      </div>
    </>
  )
}

/* ============================================================
   TO'LOV TARIXI — roʻyxat, chekni qayta chiqarish, yangi toʻlov
   ============================================================ */
const USUL_NOM = { naqd: 'Naqd', karta: 'Plastik karta', otkazma: 'Oʻtkazma' }

function TolovTab({ y, can, yangila }) {
  const [royxat, setRoyxat] = useState(null)
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)
  const [ochiq, setOchiq] = useState(false)
  /* Modal ochiq qolgani uchun pul raqamlarini shu yerda yangilab boramiz —
     aks holda toʻlovdan keyin eski qarz koʻrinib turaveradi. */
  const [pul, setPul] = useState({
    tolangan: Number(y.tolangan) || 0,
    qarz: Number(y.qarz) || 0
  })
  const qarz = pul.qarz
  /* Hisob (umumiy) qaytarishdan o'zgarmaydi — faqat to'langani kamayadi */
  const hisob = Number(y.umumiy) || 0
  const faol = y.holat === 'yotmoqda'
  /* Yotgan bemorda oldindan to'lov ortiqcha emas — u kursni yotib
     o'taydi. Pul faqat chiqarish paytida qaytariladi (bemor
     kartasidagi "Chiqarish va pulni qaytarish"). */
  const farq = Math.max(0, pul.tolangan - hisob)
  const ortiqcha = faol ? 0 : farq
  const qaytariladi = faol ? farq : 0
  const [summa, setSumma] = useState(qarz > 0 ? String(qarz) : '')
  const [usuli, setUsuli] = useState('naqd')

  /* Qaytarish formasi */
  const [qochiq, setQochiq] = useState(false)
  const [qsumma, setQsumma] = useState('')
  const [qusuli, setQusuli] = useState('naqd')
  const [qizoh, setQizoh] = useState('')

  const yukla = useCallback(async () => {
    const { data, error } = await db.tolovlar({ yotqizish_id: y.yotqizish_id })
    if (error) { setXato(xatoMatni(error)); setRoyxat([]); return }
    setRoyxat(data || [])
  }, [y.yotqizish_id])

  useEffect(() => { yukla() }, [yukla])

  async function chekChiqar(tolovId) {
    setXato('')
    const { data, error } = await db.chek(tolovId)
    if (error) return setXato(xatoMatni(error))
    const c = (data || [])[0]
    if (!c) return setXato('Chek maʼlumoti topilmadi.')
    chopEt({ html: chekHtml(c), css: chekCss, sarlavha: `Chek ${c.chek_raqam}` })
  }

  async function qabulQil() {
    const s = Number(String(summa).replace(/\s/g, ''))
    if (!(s > 0)) return setXato('Toʻlov summasini kiriting.')
    setXato(''); setBand(true)
    const { data, error } = await amal.tolovQosh(y.yotqizish_id, s, usuli)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    const r = (data || [])[0]
    setOchiq(false); setSumma('')
    setPul((p) => ({
      tolangan: p.tolangan + s,
      qarz: r ? Number(r.qolgan_qarz) || 0 : Math.max(0, p.qarz - s)
    }))
    await yukla()
    /* Chek darhol printerga ketadi — buxgalter uni qorovulga beradi */
    if (r?.tolov_id) await chekChiqar(r.tolov_id)
    yangila(r
      ? `Toʻlov qabul qilindi. ${r.chek_raqam} — qolgan qarz: ${som(r.qolgan_qarz)}.`
      : 'Toʻlov qabul qilindi.')
  }

  /* PULNI QAYTARISH
     Bemor hisobdan ortiq toʻlagan boʻlsa (erta ketgan). Bazaga manfiy
     toʻlov tushadi: kassadagi pul kamayadi, tarixda koʻrinib turadi,
     bemorga esa imzo qoʻyadigan tilxat chiqariladi. */
  async function qaytar() {
    const s = Number(String(qsumma).replace(/\s/g, ''))
    if (!(s > 0)) return setXato('Qaytariladigan summani kiriting.')
    if (s > ortiqcha) return setXato(`Koʻpi bilan ${som(ortiqcha)} qaytarish mumkin.`)
    setXato(''); setBand(true)
    const { data, error } = await amal.tolovQaytar(y.yotqizish_id, s, qusuli, qizoh || null)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    const r = (data || [])[0]
    setQochiq(false); setQsumma(''); setQizoh('')
    setPul((p) => ({ tolangan: p.tolangan - s, qarz: p.qarz }))
    await yukla()
    /* Tilxat darhol printerga — bemor imzo chekib pulni oladi */
    if (r?.tolov_id) await chekChiqar(r.tolov_id)
    yangila(r
      ? `${som(s)} qaytarildi. Tilxat ${r.chek_raqam}.`
      : `${som(s)} qaytarildi.`)
  }

  return (
    <>
      <dl className="dl">
        <dt>Kelgan</dt><dd>{sana(y.kirish_sana)}</dd>
        <dt>Reja boʻyicha</dt><dd>{sana(y.reja_chiqish)}</dd>
        {y.haqiqiy_chiqish && (<><dt>Chiqqan</dt><dd>{sana(y.haqiqiy_chiqish)}</dd></>)}
        <dt>Yotgan kun</dt><dd className="num">{y.yotgan_kun}</dd>
        <dt>Joyi</dt>
        <dd>{y.xonada ? `${y.xona}-xona · ${y.koyka}-koyka` : 'Joylashtirilmagan'}</dd>
      </dl>

      <div className="pul pul4">
        <div><span>Kurs boʻyicha</span><b className="num muted">{som(y.kurs_summa)}</b></div>
        <div><span>Hisoblangan</span><b className="num">{som(y.umumiy)}</b></div>
        <div><span>Toʻlangan</span><b className="num" style={{ color: 'var(--free)' }}>{som(pul.tolangan)}</b></div>
        {ortiqcha > 0 ? (
          <div><span>Qaytariladi</span>
            <b className="num" style={{ color: 'var(--partial)' }}>{som(ortiqcha)}</b></div>
        ) : (
          <div><span>Qarz</span><b className="num" style={{ color: qarz > 0 ? 'var(--full)' : 'var(--ink-3)' }}>
            {som(qarz)}</b></div>
        )}
      </div>

      {xato && <div className="alert err" style={{ margin: '12px 0' }}><span>▲</span><div>{xato}</div></div>}

      {/* ---------- OLDINDAN TO'LOV (bemor hali yotibdi) ---------- */}
      {qaytariladi > 0 && (
        <div className="alert info" style={{ margin: '12px 0', display: 'block' }}>
          <b>Oldindan toʻlangan — bugun ketsa {som(qaytariladi)} qaytariladi.</b>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            Bu ortiqcha toʻlov emas: bemor kursni yotib oʻtaydi va hisob har kuni
            oʻsib boradi. Erta ketsa, farqi chiqarish paytida qaytariladi —
            “Maʼlumot” boʻlimidagi <b>Chiqarish va pulni qaytarish</b> tugmasi.
          </p>
        </div>
      )}

      {/* ---------- ORTIQCHA TO'LOVNI QAYTARISH (chiqib ketgan) ---------- */}
      {ortiqcha > 0 && (
        <div className="alert warn" style={{ margin: '12px 0', display: 'block' }}>
          <b>Bemorga {som(ortiqcha)} qaytarilishi kerak.</b>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            Yakuniy hisob {som(y.umumiy)}, toʻlangani {som(pul.tolangan)} — farqi bemorniki.
          </p>
          {!can('tolov') && (
            <p className="muted" style={{ margin: '6px 0 0' }}>
              Pulni buxgalter qaytaradi.
            </p>
          )}
        </div>
      )}

      {can('tolov') && ortiqcha > 0 && (
        qochiq ? (
          <div className="tolov-forma">
            <div className="grid2">
              <div className="field">
                <label htmlFor="qs">Qaytariladigan summa</label>
                <input id="qs" type="number" min="1" max={ortiqcha} value={qsumma}
                  onChange={(e) => setQsumma(e.target.value)} placeholder="0" />
                <div className="hint">
                  Koʻpi bilan {som(ortiqcha)} ·{' '}
                  <button className="matn" onClick={() => setQsumma(String(ortiqcha))}>
                    toʻliq summani qoʻyish
                  </button>
                </div>
              </div>
              <div className="field">
                <label htmlFor="qu">Qanday qaytarildi</label>
                <select id="qu" value={qusuli} onChange={(e) => setQusuli(e.target.value)}>
                  <option value="naqd">Naqd</option>
                  <option value="karta">Plastik karta</option>
                  <option value="otkazma">Oʻtkazma</option>
                </select>
              </div>
            </div>
            <div className="field" style={{ marginTop: 10 }}>
              <label htmlFor="qi">Izoh</label>
              <input id="qi" value={qizoh} onChange={(e) => setQizoh(e.target.value)}
                placeholder="masalan: rejadan 4 kun erta ketdi" />
            </div>
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn sm" onClick={() => setQochiq(false)} disabled={band}>Bekor</button>
              <span className="sp" />
              <button className="btn pri sm" onClick={qaytar} disabled={band}>
                {band ? 'Saqlanmoqda…' : 'Qaytarish va tilxat chiqarish'}
              </button>
            </div>
          </div>
        ) : (
          <button className="btn block pri" style={{ marginTop: 4 }}
            onClick={() => { setQsumma(String(ortiqcha)); setQochiq(true) }}>
            Pulni qaytarish — {som(ortiqcha)}
          </button>
        )
      )}

      {can('tolov') && y.holat === 'yotmoqda' && (
        ochiq ? (
          <div className="tolov-forma">
            <div className="grid2">
              <div className="field">
                <label htmlFor="ts">Summa</label>
                <input id="ts" type="number" min="1" value={summa}
                  onChange={(e) => setSumma(e.target.value)} placeholder="0" />
                {qarz > 0 && (
                  <div className="hint">
                    Qarz: {som(qarz)} ·{' '}
                    <button className="matn" onClick={() => setSumma(String(qarz))}>
                      toʻliq qarzni qoʻyish
                    </button>
                  </div>
                )}
              </div>
              <div className="field">
                <label htmlFor="tu">Usuli</label>
                <select id="tu" value={usuli} onChange={(e) => setUsuli(e.target.value)}>
                  <option value="naqd">Naqd</option>
                  <option value="karta">Plastik karta</option>
                  <option value="otkazma">Oʻtkazma</option>
                </select>
              </div>
            </div>
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn sm" onClick={() => setOchiq(false)} disabled={band}>Bekor</button>
              <span className="sp" />
              <button className="btn pri sm" onClick={qabulQil} disabled={band}>
                {band ? 'Saqlanmoqda…' : 'Qabul qilish va chek chiqarish'}
              </button>
            </div>
          </div>
        ) : (
          <button className="btn block" style={{ marginTop: 14 }} onClick={() => setOchiq(true)}>
            + Toʻlov qabul qilish
          </button>
        )
      )}

      <div className="bolim-bosh" style={{ marginTop: 18 }}><h4>Toʻlovlar</h4></div>

      {royxat === null ? (
        <div className="muted" style={{ padding: '10px 0' }}>Yuklanmoqda…</div>
      ) : royxat.length === 0 ? (
        <div className="bosh-yoq">
          <div className="nm">Hali toʻlov yoʻq</div>
          <div className="muted">Toʻlov qabul qilinganda chek shu yerda saqlanadi.</div>
        </div>
      ) : (
        <div className="chek-royxat">
          {royxat.map((t) => {
            /* Manfiy summa — bu qaytarilgan pul */
            const qayt = Number(t.summa) < 0
            return (
              <div className="chek-qator" key={t.tolov_id}>
                <div className="body">
                  <div className="nm" style={qayt ? { color: 'var(--partial)' } : undefined}>
                    {qayt ? `− ${som(Math.abs(Number(t.summa)))}` : som(t.summa)}
                    {qayt && <span className="pill partial" style={{ marginLeft: 8 }}>Qaytarildi</span>}
                  </div>
                  <div className="sb">
                    {t.chek_raqam} · {USUL_NOM[t.usuli] || t.usuli} · {kunVaqt(t.vaqt)}
                  </div>
                  <div className="sb bog">
                    {qayt ? 'Qaytardi' : 'Kassir'}: {t.kassir}{t.izoh ? ` · ${t.izoh}` : ''}
                  </div>
                </div>
                <button className="btn sm" onClick={() => chekChiqar(t.tolov_id)}>
                  {qayt ? 'Tilxat' : 'Chek'}
                </button>
              </div>
            )
          })}
        </div>
      )}
    </>
  )
}

/* ============================================================
   JOYLASHTIRISH
   ============================================================ */
function Joylashtirish({ y, boshJoylar, yop, tugadi }) {
  const [koyka, setKoyka] = useState('')
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)
  const joylar = useMemo(() => boshJoylar(y.jins), [boshJoylar, y.jins])

  async function saqla() {
    if (!koyka) return setXato('Koykani tanlang.')
    setXato(''); setBand(true)
    const { error } = await amal.koykaBiriktir(y.yotqizish_id, Number(koyka))
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    tugadi(`${y.fish} joylashtirildi.`)
  }

  return (
    <Modal sarlavha="Xonaga joylashtirish" yop={yop} kenglik={480}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Orqaga</button>
        <button className="btn pri" onClick={saqla} disabled={band || !koyka}>Joylashtirish</button>
      </>}>
      <div className="karta-bosh">
        <div>
          <h3>{y.fish}</h3>
          <div className="muted">{y.jins === 'erkak' ? 'Erkak' : 'Ayol'} · {y.yosh} yosh</div>
        </div>
      </div>
      {xato && <div className="alert err" style={{ marginBottom: 12 }}><span>▲</span><div>{xato}</div></div>}

      <div className="field">
        <label htmlFor="jk">Boʻsh koykalar</label>
        <select id="jk" value={koyka} onChange={(e) => setKoyka(e.target.value)}>
          <option value="">— tanlang —</option>
          {joylar.map((g) => (
            <optgroup key={g.xona_id} label={`${g.xona}-xona · ${g.bolim}`}>
              {g.koykalar.map((k) => (
                <option key={k.id} value={k.id}>{g.xona}-xona · {k.raqam}-koyka</option>
              ))}
            </optgroup>
          ))}
        </select>
        <div className="hint">
          {joylar.length === 0
            ? 'Mos boʻsh joy yoʻq. Xona qoʻshing yoki boshqa bemorni chiqaring.'
            : 'Jinsi mos kelmaydigan xonalar roʻyxatga umuman kirmaydi.'}
        </div>
      </div>
    </Modal>
  )
}

/* ============================================================
   MUDDATNI UZAYTIRISH
   ============================================================ */
function Uzaytirish({ y, kursKun, yop, tugadi }) {
  const [yangi, setYangi] = useState(qoshKun(bugun(), 3))
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)

  async function saqla() {
    if (yangi <= y.kirish_sana) return setXato('Sana kirish sanasidan keyin boʻlishi kerak.')
    setXato(''); setBand(true)
    const { data, error } = await amal.muddatUzaytir(y.yotqizish_id, yangi)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    const ogoh = (data || []).map((r) => r.ogohlantirish).filter(Boolean)
    tugadi(ogoh.length ? ogoh[0] : `${y.fish} muddati ${sana(yangi)} gacha uzaytirildi.`)
  }

  return (
    <Modal sarlavha="Muddatni uzaytirish" yop={yop} kenglik={460}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Orqaga</button>
        <button className="btn pri" onClick={saqla} disabled={band}>Tasdiqlash</button>
      </>}>
      <div className="karta-bosh">
        <div>
          <h3>{y.fish}</h3>
          <div className="muted">Joriy reja: {sana(y.reja_chiqish)}</div>
        </div>
      </div>
      {xato && <div className="alert err" style={{ marginBottom: 12 }}><span>▲</span><div>{xato}</div></div>}

      <div className="field">
        <label htmlFor="yn">Yangi chiqish sanasi</label>
        <input id="yn" type="date" value={yangi} min={bugun()} onChange={(e) => setYangi(e.target.value)} />
      </div>
      <div className="row">
        {[3, 5, kursKun].map((n, i) => (
          <button key={i} className="btn sm" onClick={() => setYangi(qoshKun(bugun(), n))}>+{n} kun</button>
        ))}
      </div>
      <div className="hint" style={{ marginTop: 10 }}>
        Uzaytirilgach bemor yana ovqat hisobiga qoʻshiladi. Narx avtomatik qayta hisoblanmaydi —
        qoʻshimcha toʻlov boʻlsa, Toʻlovlar boʻlimidan kiritiladi.
      </div>
    </Modal>
  )
}

/* ============================================================
   BEMOR MA'LUMOTLARINI TAHRIRLASH
   (otasining ismi, tugʻilgan sana, manzil — 27_bemor_malumotlari.sql)
   ============================================================ */
function MalumotTahrir({ y, yop, tugadi }) {
  const [v, setV] = useState({
    otasining_ismi: y.otasining_ismi || '',
    tugilgan_sana: y.tugilgan_sana || '',
    chet_el: !!y.chet_el,
    viloyat: y.chet_el ? (y.fuqaroligi || '') : (y.viloyat || ''),
    tuman: y.tuman || '',
    mahalla: y.mahalla || '', kocha: y.kocha || '',
    uy_raqami: y.uy_raqami || '', kvartira: y.kvartira || ''
  })
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)
  const set = (k, x) => setV((s) => ({ ...s, [k]: x }))

  const tumanlar = useMemo(
    () => (VILOYATLAR.find((r) => r.nomi === v.viloyat) || {}).tumanlar || [],
    [v.viloyat]
  )
  useEffect(() => {
    if (v.tuman && !tumanlar.includes(v.tuman)) set('tuman', '')
  }, [tumanlar]) // eslint-disable-line react-hooks/exhaustive-deps

  async function saqla() {
    setXato(''); setBand(true)
    const { error } = await amal.bemorMalumot(y.yotqizish_id, {
      otasining_ismi: v.otasining_ismi.trim(),
      tugilgan_sana: v.tugilgan_sana || null,
      viloyat: v.chet_el ? '' : v.viloyat.trim(),
      tuman: v.chet_el ? '' : v.tuman.trim(),
      mahalla: v.mahalla.trim(), kocha: v.kocha.trim(),
      uy_raqami: v.uy_raqami.trim(), kvartira: v.kvartira.trim(),
      fuqaroligi: v.chet_el ? v.viloyat.trim() : ''
    })
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    tugadi(`${y.fish} maʼlumotlari saqlandi.`)
  }

  return (
    <Modal sarlavha={`${y.fish} — qoʻshimcha maʼlumotlar`} yop={yop} kenglik={480}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Bekor</button>
        <button className="btn pri" onClick={saqla} disabled={band}>{band ? '…' : 'Saqlash'}</button>
      </>}>
      {xato && <div className="alert err" style={{ marginBottom: 12 }}><span>▲</span><div>{xato}</div></div>}
      <div className="hint" style={{ marginBottom: 12 }}>
        Bu maʼlumotlar bemor kartasida va hujjatlarda ishlatiladi. Hammasi ixtiyoriy.
      </div>

      <div className="grid2">
        <div className="field full">
          <label htmlFor="mt-chet">Fuqaroligi</label>
          <select id="mt-chet" value={v.chet_el ? '1' : '0'}
            onChange={(e) => set('chet_el', e.target.value === '1')}>
            <option value="0">Oʻzbekiston</option>
            <option value="1">Chet el fuqarosi</option>
          </select>
        </div>

        <div className="field">
          <label htmlFor="mt-otasi">Otasining ismi</label>
          <input id="mt-otasi" value={v.otasining_ismi}
            onChange={(e) => set('otasining_ismi', e.target.value)} placeholder="Baxtiyorovich" />
        </div>
        <div className="field">
          <label htmlFor="mt-tugsana">Tugʻilgan sanasi</label>
          <input id="mt-tugsana" type="date" value={v.tugilgan_sana}
            onChange={(e) => set('tugilgan_sana', e.target.value)} />
        </div>

        <div className="field">
          <label htmlFor="mt-vil">{v.chet_el ? 'Fuqaroligi davlati' : 'Viloyat'}</label>
          <select id="mt-vil" value={v.viloyat} onChange={(e) => set('viloyat', e.target.value)}>
            <option value="">— tanlanmagan —</option>
            {(v.chet_el ? SNG_DAVLATLAR : VILOYATLAR.map((r) => r.nomi)).map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        </div>
        {!v.chet_el && (
          <div className="field">
            <label htmlFor="mt-tum">Tuman</label>
            <select id="mt-tum" value={v.tuman} onChange={(e) => set('tuman', e.target.value)}
              disabled={!v.viloyat}>
              <option value="">— tanlanmagan —</option>
              {tumanlar.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </div>
        )}

        <div className="field">
          <label htmlFor="mt-mfy">Mahalla</label>
          <input id="mt-mfy" value={v.mahalla} onChange={(e) => set('mahalla', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="mt-koch">Koʻcha</label>
          <input id="mt-koch" value={v.kocha} onChange={(e) => set('kocha', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="mt-uy">Uy raqami</label>
          <input id="mt-uy" value={v.uy_raqami} onChange={(e) => set('uy_raqami', e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="mt-kv">Kvartira</label>
          <input id="mt-kv" value={v.kvartira} onChange={(e) => set('kvartira', e.target.value)} />
        </div>
      </div>
    </Modal>
  )
}
