import { useEffect, useState, useCallback } from 'react'
import { db, amal, xatoMatni, authHisobOch, loginEmail, raqamlar }
  from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Kutish } from '../components/Kutish'
import Modal, { Xabar } from '../components/Modal'

const son = (n) => (Number(n) || 0).toLocaleString('ru-RU').replace(/ /g, ' ')
const som = (n) => son(n) + ' soʻm'
const vaqt = (s) => (s ? new Date(s).toLocaleString('ru-RU', {
  day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit'
}) : '—')

/* Kurs narxlari — bemor yoshiga qarab avtomatik tanlanadi.
   Eng ko'p ishlatiladigani birinchi turadi. */
const KURS = [
  { k: 'kattalar', n: 'Kattalar kursi',   i: '15 yoshdan katta — asosiy narx' },
  { k: 'yosh_15',  n: 'Bolalar kursi',    i: '15 yoshgacha' },
  { k: 'yosh_10',  n: 'Bolalar kursi',    i: '10 yoshgacha' },
  { k: 'yosh_5',   n: 'Bolalar kursi',    i: '5 yoshgacha' },
  { k: 'qarovchi', n: 'Qarovchi kursi',   i: 'bemor bilan keladigan hamroh' },
  { k: 'chet_el',  n: 'Chet el qoʻshimchasi', i: 'kurs narxiga qoʻshiladi' }
]
const KURS_KALIT = KURS.map((x) => x.k).concat('kurs_kun')

/* Admin bera oladigan rollar. "Admin" — eng yuqorisi, huquqlari
   sizniki bilan bir xil (bazadagi nomi super_admin). */
const ROLLAR = [
  { k: 'administrator', n: 'Registrator',
    i: 'Bemorlarni roʻyxatga oladi, joylashtiradi, bron qiladi. Pulga tegmaydi.' },
  { k: 'buxgalter', n: 'Buxgalter',
    i: 'Toʻlov qabul qiladi, chek chiqaradi, narxlarni boshqaradi.' },
  { k: 'viewer', n: 'Kuzatuvchi',
    i: 'Faqat koʻradi — hech narsani oʻzgartira olmaydi.' },
  { k: 'super_admin', n: 'Admin',
    i: 'Hamma narsani boshqaradi: narxlar, xodimlar, hisobotlar, toʻlovlar. Sizga teng huquq.' }
]
const ROL_PILL = {
  super_admin: 'partial', administrator: 'booked',
  buxgalter: 'free', viewer: 'neutral'
}

/* ============================================================
   SOZLAMALAR — ikki boʻlim: narxlar va xodimlar
   ============================================================ */
export default function Sozlamalar() {
  const { rol } = useAuth()
  const superAdmin = rol === 'super_admin'
  const [tab, setTab] = useState('narx')

  if (!superAdmin) return <Narxlar />

  return (
    <div className="stack">
      <div className="tablar" style={{ margin: 0 }}>
        <button className={'tab' + (tab === 'narx' ? ' on' : '')}
          onClick={() => setTab('narx')}>Narxlar</button>
        <button className={'tab' + (tab === 'bolim' ? ' on' : '')}
          onClick={() => setTab('bolim')}>Boʻlimlar</button>
        <button className={'tab' + (tab === 'xodim' ? ' on' : '')}
          onClick={() => setTab('xodim')}>Xodimlar</button>
      </div>
      {tab === 'narx' ? <Narxlar /> : tab === 'bolim' ? <Bolimlar /> : <Xodimlar />}
    </div>
  )
}

function Narxlar() {
  const { rol } = useAuth()
  const ozgartira = rol === 'super_admin' || rol === 'buxgalter'
  const damOzgartira = rol === 'super_admin'

  const [tariflar, setTariflar] = useState(null)
  const [turlar, setTurlar] = useState([])
  const [tarix, setTarix] = useState([])
  const [xato, setXato] = useState('')
  const [ogoh, setOgoh] = useState('')
  const [xabar, setXabar] = useState('')

  const bildir = (m) => { setXabar(m); setTimeout(() => setXabar(''), 4000) }

  const yukla = useCallback(async () => {
    const [t, x, h] = await Promise.all([db.tariflar(), db.xonaNarxlari(), db.narxTarixi(20)])
    if (t.error) { setXato(xatoMatni(t.error)); return }
    setTariflar(t.data || [])
    setTurlar(x.data || [])
    setTarix(h.data || [])
    setOgoh(x.error || h.error
      ? 'Narx boshqaruvi bazada hali toʻliq oʻrnatilmagan. SQL Editorʼda 09, 10 va 11-fayllarni ishga tushiring.'
      : '')
  }, [])

  useEffect(() => { yukla() }, [yukla])

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>
  if (!tariflar) return <Kutish />

  const tMap = {}
  tariflar.forEach((t) => { tMap[t.kalit] = t })
  const kursKun = tMap.kurs_kun ? Number(tMap.kurs_kun.qiymat) : null
  const boshqa = tariflar.filter((t) => !KURS_KALIT.includes(t.kalit))

  const saqlaTarif = (kalit, nomi) => async (yangi) => {
    const { error } = await amal.tarifOzgartir(kalit, yangi)
    if (error) return xatoMatni(error)
    bildir(`${nomi}: ${son(yangi)} qilib saqlandi.`)
    yukla()
  }

  return (
    <div className="stack">
      {ogoh && <div className="alert err"><span>▲</span><div>{ogoh}</div></div>}

      {!ozgartira && (
        <div className="alert info">
          <span>◇</span>
          <div>Narxlarni faqat <b>admin</b> va <b>buxgalter</b> oʻzgartira oladi.
            Siz faqat koʻrishingiz mumkin.</div>
        </div>
      )}

      {ozgartira && !tMap.kattalar && (
        <div className="alert warn">
          <span>◇</span>
          <div><b>Kattalar kursi narxi belgilanmagan.</b> 15 yoshdan katta bemorlar shu
            narx boʻyicha hisoblanadi — busiz kassa notoʻgʻri chiqadi.</div>
        </div>
      )}

      {/* ---------------- kurs narxlari ---------------- */}
      <div className="card">
        <div className="card-h">
          <h3>Kurs narxlari</h3>
          <span className="sp" />
          <span className="muted">1 kurs uchun</span>
        </div>
        <div className="card-b" style={{ paddingBottom: 4 }}>
          <div className="muted" style={{ maxWidth: '64ch' }}>
            Bemor qabul qilinganda kurs narxi <b>yoshiga qarab avtomatik</b> tanlanadi.
            Bemorning umumiy hisobi = kurs narxi + xona narxi.
          </div>
        </div>
        <div className="narx-royxat">
          {KURS.filter((x) => tMap[x.k]).map((x) => (
            <NarxQator key={x.k} nomi={x.n} izoh={x.i}
              qiymat={Number(tMap[x.k].qiymat)} ozgartira={ozgartira}
              saqla={saqlaTarif(x.k, x.n)} />
          ))}
          {boshqa.map((t) => (
            <NarxQator key={t.kalit} nomi={t.kalit} izoh={t.izoh}
              qiymat={Number(t.qiymat)} ozgartira={ozgartira}
              saqla={saqlaTarif(t.kalit, t.kalit)} />
          ))}
        </div>
      </div>

      {/* ---------------- kurs davomiyligi ---------------- */}
      {kursKun != null && (
        <div className="card">
          <div className="card-h"><h3>Kurs davomiyligi</h3></div>
          <div className="narx-royxat">
            <NarxQator
              nomi="1 kurs necha kun"
              izoh={`Kunlik hisob shu songa boʻlinadi — bemor ${kursKun} kundan kam yotsa, faqat yotgan kunlari uchun toʻlaydi.`}
              qiymat={kursKun} birlik="kun" ozgartira={ozgartira}
              saqla={saqlaTarif('kurs_kun', 'Kurs davomiyligi')} />
          </div>
        </div>
      )}

      {/* ---------------- xona turlari ---------------- */}
      <div className="card">
        <div className="card-h">
          <h3>Xona narxlari</h3>
          <span className="sp" />
          <span className="muted">1 kurs uchun</span>
        </div>
        <div className="card-b" style={{ paddingBottom: 4 }}>
          <div className="muted" style={{ maxWidth: '64ch' }}>
            Narx <b>xona turiga</b> bogʻlangan — har bir xonani alohida narxlash shart emas.
            Xona puli har bir mustaqil bemorga yoziladi; uning farzandi va qarovchisi
            xona uchun toʻlamaydi.
          </div>
        </div>
        {turlar.length === 0 ? (
          <div className="card-b muted">Xona turlari topilmadi.</div>
        ) : (
          <div className="narx-royxat">
            {turlar.map((t) => (
              <NarxQator
                key={t.turi}
                nomi={t.turi}
                izoh={`${t.xona_soni} xona · ${t.koyka_soni} koyka${t.xonalar ? ' · ' + t.xonalar : ''}`}
                qiymat={Number(t.narx)}
                ozgartira={ozgartira}
                saqla={async (yangi) => {
                  const { error } = await amal.xonaTuriNarx(t.turi, yangi)
                  if (error) return xatoMatni(error)
                  bildir(`${t.turi} xonalari narxi ${son(yangi)} qilib saqlandi.`)
                  yukla()
                }}
              />
            ))}
          </div>
        )}
      </div>

      {/* ---------------- dam olish narxlari ---------------- */}
      <div className="card">
        <div className="card-h">
          <h3>Dam olish narxlari</h3>
          <span className="sp" />
          <span className="muted">kuniga</span>
        </div>
        <div className="card-b" style={{ paddingBottom: 4 }}>
          <div className="muted" style={{ maxWidth: '64ch' }}>
            Bemor davolanishni toʻxtatib, xonada shunchaki <b>dam olsa</b> (ovqat
            kiradi, davolanish kirmaydi) — shu narx <b>kunlik</b> hisoblanadi, xona
            turiga qarab. Necha kun dam olsa, shuncha kun uchun toʻlaydi.
          </div>
        </div>
        {turlar.length === 0 ? (
          <div className="card-b muted">Xona turlari topilmadi.</div>
        ) : (
          <div className="narx-royxat">
            {turlar.map((t) => (
              <NarxQator
                key={t.turi}
                nomi={t.turi}
                izoh={`${t.xona_soni} xona · ${t.koyka_soni} koyka${t.xonalar ? ' · ' + t.xonalar : ''}`}
                qiymat={Number(t.dam_olish_narxi)}
                birlik="soʻm/kun"
                ozgartira={damOzgartira}
                saqla={async (yangi) => {
                  const { error } = await amal.xonaTuriDamNarx(t.turi, yangi)
                  if (error) return xatoMatni(error)
                  bildir(`${t.turi} xonalari dam olish narxi ${son(yangi)} qilib saqlandi.`)
                  yukla()
                }}
              />
            ))}
          </div>
        )}
      </div>

      {/* ---------------- tarix ---------------- */}
      <div className="card">
        <div className="card-h"><h3>Narx oʻzgarishlari</h3></div>
        {tarix.length === 0 ? (
          <div className="card-b muted">Hozircha oʻzgarish yoʻq.</div>
        ) : (
          <div className="scroll-x">
            <table>
              <thead>
                <tr><th>Nima</th><th className="r">Eski</th><th className="r">Yangi</th>
                  <th>Kim</th><th>Qachon</th></tr>
              </thead>
              <tbody>
                {tarix.map((t) => {
                  const k = KURS.find((x) => x.k === t.nomi)
                  return (
                    <tr key={t.id}>
                      <td>
                        <b>{k ? `${k.n} (${k.i})` : t.nomi === 'kurs_kun' ? 'Kurs davomiyligi' : t.nomi}</b>
                        <div className="muted" style={{ fontSize: 11.5 }}>
                          {t.tur === 'tarif' ? 'kurs narxi' : t.tur === 'xona_turi' ? 'xona turi' : t.tur}
                        </div>
                      </td>
                      <td className="r num muted">{t.eski == null ? '—' : son(t.eski)}</td>
                      <td className="r num"><b>{son(t.yangi)}</b></td>
                      <td className="muted">{t.kim || '—'}</td>
                      <td className="muted num">{vaqt(t.vaqt)}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="muted" style={{ maxWidth: '64ch' }}>
        Narx oʻzgarishi faqat <b>keyingi</b> qabullarga taʼsir qiladi. Allaqachon
        roʻyxatga olingan bemorlarning hisobi oʻsha kungi narx boʻyicha qolaveradi.
      </div>

      <Xabar matn={xabar} />
    </div>
  )
}

/* ---------------- bitta narx qatori ---------------- */
function NarxQator({ nomi, izoh, qiymat, birlik = 'soʻm', ozgartira, saqla }) {
  const [tahrir, setTahrir] = useState(false)
  const [qiy, setQiy] = useState(String(qiymat))
  const [band, setBand] = useState(false)
  const [xato, setXato] = useState('')

  useEffect(() => { setQiy(String(qiymat)) }, [qiymat])

  async function yubor() {
    const n = Number(qiy)
    if (!Number.isFinite(n) || n < 0) return setXato('Notoʻgʻri son.')
    setBand(true); setXato('')
    const x = await saqla(n)
    setBand(false)
    if (x) { setXato(x); return }
    setTahrir(false)
  }

  return (
    <div className="narx-qator">
      <div className="body">
        <b>{nomi}</b>
        {izoh && <div className="muted">{izoh}</div>}
        {xato && <div style={{ color: 'var(--full)', fontSize: 12.5, marginTop: 3 }}>{xato}</div>}
      </div>

      {tahrir ? (
        <div className="row" style={{ gap: 7, flexWrap: 'nowrap' }}>
          <input className="narx-input" type="number" min="0" step="10000" value={qiy}
            onChange={(e) => setQiy(e.target.value)} autoFocus
            onKeyDown={(e) => { if (e.key === 'Enter') yubor(); if (e.key === 'Escape') setTahrir(false) }} />
          <button className="btn sm" onClick={() => { setTahrir(false); setQiy(String(qiymat)); setXato('') }}
            disabled={band}>Bekor</button>
          <button className="btn pri sm" onClick={yubor} disabled={band}>
            {band ? '…' : 'Saqlash'}
          </button>
        </div>
      ) : (
        <div className="row" style={{ gap: 10, flexWrap: 'nowrap' }}>
          <span className="num narx-qiymat">
            {son(qiymat)} <span className="muted">{birlik}</span>
          </span>
          {ozgartira && (
            <button className="btn sm" onClick={() => setTahrir(true)}>Oʻzgartirish</button>
          )}
        </div>
      )}
    </div>
  )
}


/* ============================================================
   BO'LIMLAR — bo'lim qo'shish/tahrirlash va har bir bo'limning
   bemor narxlari (30_bolim_narxlari.sql). Qarovchi va farzand
   narxi bundan mustaqil — "Narxlar" tabidagi umumiy tariflarda,
   hamma bo'lim uchun bir xil qoladi (mijoz bilan tasdiqlangan).
   ============================================================ */
const BOLIM_NARX = [
  { k: 'kattalar', n: 'Kattalar kursi',       i: '15 yoshdan katta — asosiy narx' },
  { k: 'yosh_15',  n: 'Bolalar kursi',        i: '15 yoshgacha' },
  { k: 'yosh_10',  n: 'Bolalar kursi',        i: '10 yoshgacha' },
  { k: 'yosh_5',   n: 'Bolalar kursi',        i: '5 yoshgacha' },
  { k: 'chet_el',  n: 'Chet el qoʻshimchasi', i: 'kurs narxiga qoʻshiladi' }
]

function Bolimlar() {
  const [bolimlar, setBolimlar] = useState(null)
  const [narxlar, setNarxlar] = useState([])
  const [xato, setXato] = useState('')
  const [ogoh, setOgoh] = useState('')
  const [xabar, setXabar] = useState('')
  const [yangi, setYangi] = useState(false)   // "+ Yangi boʻlim" forma ochiqmi

  const bildir = (m) => { setXabar(m); setTimeout(() => setXabar(''), 4000) }

  const yukla = useCallback(async () => {
    const [b, n] = await Promise.all([db.bolimlar(), db.bolimNarxlari()])
    if (b.error) { setXato(xatoMatni(b.error)); return }
    setBolimlar(b.data || [])
    setNarxlar(n.data || [])
    setOgoh(n.error
      ? 'Boʻlim narxlari bazada hali oʻrnatilmagan. SQL Editorʼda 30-faylni ishga tushiring.'
      : '')
  }, [])

  useEffect(() => { yukla() }, [yukla])

  if (xato) return <div className="alert err"><span>▲</span><div>{xato}</div></div>
  if (bolimlar === null) return <Kutish />

  const narxMap = {}
  narxlar.forEach((n) => { narxMap[`${n.bolim_id}:${n.kalit}`] = Number(n.qiymat) })

  return (
    <div className="stack">
      {ogoh && <div className="alert err"><span>▲</span><div>{ogoh}</div></div>}

      <div className="alert info">
        <span>◇</span>
        <div>
          Har bir boʻlim <b>oʻz bemor narxini</b> belgilaydi (yosh toifalari boʻyicha).
          Qarovchi va farzand narxi esa <b>umumiy</b> — "Narxlar" boʻlimida, hamma
          boʻlim uchun bir xil qoladi. Xona puli bundan alohida, xona turiga bogʻliq.
        </div>
      </div>

      <div className="card">
        <div className="card-h"><h3>Boʻlimlar</h3></div>
        <div className="narx-royxat">
          {bolimlar.map((b) => (
            <BolimQator key={b.id} b={b} bildir={bildir} yukla={yukla} />
          ))}
        </div>
        <div className="card-b">
          {yangi ? (
            <YangiBolim bildir={bildir} yukla={yukla} yop={() => setYangi(false)} />
          ) : (
            <button className="btn" onClick={() => setYangi(true)}>+ Yangi boʻlim</button>
          )}
        </div>
      </div>

      {bolimlar.map((b) => (
        <div className="card" key={b.id}>
          <div className="card-h"><h3>{b.nomi} — bemor narxlari</h3></div>
          <div className="narx-royxat">
            {BOLIM_NARX.map((x) => (
              <NarxQator key={x.k} nomi={x.n} izoh={x.i}
                qiymat={narxMap[`${b.id}:${x.k}`] ?? 0}
                ozgartira
                saqla={async (yangiQ) => {
                  const { error } = await amal.bolimNarxOzgartir(b.id, x.k, yangiQ)
                  if (error) return xatoMatni(error)
                  bildir(`${b.nomi}: ${x.n} (${x.i}) ${son(yangiQ)} qilib saqlandi.`)
                  yukla()
                }} />
            ))}
          </div>
        </div>
      ))}

      <Xabar matn={xabar} />
    </div>
  )
}

/* ---------------- bitta bo'lim qatori (nomi/jinsi, tahrirlash) ---------------- */
function BolimQator({ b, bildir, yukla }) {
  const [tahrir, setTahrir] = useState(false)
  const [nomi, setNomi] = useState(b.nomi)
  const [jins, setJins] = useState(b.jins)
  const [band, setBand] = useState(false)
  const [xato, setXato] = useState('')

  async function saqla() {
    if (!nomi.trim()) return setXato('Nomini kiriting.')
    setBand(true); setXato('')
    const { error } = await amal.bolimTahrir(b.id, nomi.trim(), jins)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    bildir(`${nomi.trim()} saqlandi.`)
    setTahrir(false)
    yukla()
  }

  return (
    <div className="narx-qator">
      <div className="body">
        {tahrir ? (
          <div className="row" style={{ gap: 7, flexWrap: 'wrap' }}>
            <input value={nomi} onChange={(e) => setNomi(e.target.value)} autoFocus
              style={{ minWidth: 180 }} />
            <select value={jins} onChange={(e) => setJins(e.target.value)}>
              <option value="erkak">Erkaklar</option>
              <option value="ayol">Ayollar</option>
              <option value="aralash">Aralash</option>
            </select>
          </div>
        ) : (
          <>
            <b>{b.nomi}</b>
            <div className="muted">
              {b.jins === 'aralash' ? 'Aralash' : b.jins === 'erkak' ? 'Erkaklar' : 'Ayollar'}
            </div>
          </>
        )}
        {xato && <div style={{ color: 'var(--full)', fontSize: 12.5, marginTop: 3 }}>{xato}</div>}
      </div>

      <div className="row" style={{ gap: 7, flexWrap: 'nowrap' }}>
        {tahrir ? (
          <>
            <button className="btn sm"
              onClick={() => { setTahrir(false); setNomi(b.nomi); setJins(b.jins); setXato('') }}
              disabled={band}>Bekor</button>
            <button className="btn pri sm" onClick={saqla} disabled={band}>
              {band ? '…' : 'Saqlash'}
            </button>
          </>
        ) : (
          <button className="btn sm" onClick={() => setTahrir(true)}>Tahrirlash</button>
        )}
      </div>
    </div>
  )
}

/* ---------------- yangi bo'lim qo'shish forma ---------------- */
function YangiBolim({ bildir, yukla, yop }) {
  const [nomi, setNomi] = useState('')
  const [jins, setJins] = useState('aralash')
  const [band, setBand] = useState(false)
  const [xato, setXato] = useState('')

  async function saqla() {
    if (!nomi.trim()) return setXato('Boʻlim nomini kiriting.')
    setBand(true); setXato('')
    const { error } = await amal.bolimQosh(nomi.trim(), jins)
    setBand(false)
    if (error) return setXato(xatoMatni(error))
    bildir(`${nomi.trim()} qoʻshildi.`)
    yop()
    yukla()
  }

  return (
    <div className="row" style={{ gap: 7, flexWrap: 'wrap' }}>
      <input placeholder="Boʻlim nomi (masalan: Bolalar boʻlimi)"
        value={nomi} onChange={(e) => setNomi(e.target.value)} autoFocus
        style={{ minWidth: 220 }} />
      <select value={jins} onChange={(e) => setJins(e.target.value)}>
        <option value="erkak">Erkaklar</option>
        <option value="ayol">Ayollar</option>
        <option value="aralash">Aralash</option>
      </select>
      <button className="btn sm" onClick={yop} disabled={band}>Bekor</button>
      <button className="btn pri sm" onClick={saqla} disabled={band}>
        {band ? '…' : 'Qoʻshish'}
      </button>
      {xato && <div style={{ color: 'var(--full)', fontSize: 12.5, width: '100%' }}>{xato}</div>}
    </div>
  )
}

/* ============================================================
   XODIMLAR — profil ochish va boshqarish (faqat super admin)

   Parol Supabase Auth'da saqlanadi, bazada emas. Shuning uchun
   profil ochish ikki qadamdan iborat:
     1) Auth'da hisob ochiladi (telefon raqamdan yasalgan
        ichki pochta + parol bilan);
     2) xodim_qosh() shu hisobni profilga bog'laydi.
   Birinchisi alohida, sessiyani saqlamaydigan mijoz orqali
   ketadi — super admin o'z hisobidan chiqib qolmasin.
   ============================================================ */
function Xodimlar() {
  const { xodim } = useAuth()
  const [royxat, setRoyxat] = useState(null)
  const [xato, setXato] = useState('')
  const [xabar, setXabar] = useState('')
  const [modal, setModal] = useState(null)   // {tur:'yangi'|'tahrir', x}

  const bildir = (m) => { setXabar(m); setTimeout(() => setXabar(''), 5000) }

  /* 25_yashirin_admin.sql: roʻyxatda koʻrinmaydigan hisob bormi.
     null — baza hali yangilanmagan, belgi umuman koʻrsatilmaydi. */
  const [yashirinBor, setYashirinBor] = useState(null)

  const yukla = useCallback(async () => {
    amal.yashirinBormi().then(({ data, error }) =>
      setYashirinBor(error ? null : data === true))
    const { data, error } = await db.xodimlar()
    if (error) {
      setXato(/v_xodimlar|does not exist|schema cache/i.test(error.message || '')
        ? 'Xodimlar boʻlimi bazada hali oʻrnatilmagan. SQL Editorʼda '
          + '17_xodimlar.sql faylini ishga tushiring.'
        : xatoMatni(error))
      setRoyxat([])
      return
    }
    setXato('')
    setRoyxat(data || [])
  }, [])

  useEffect(() => { yukla() }, [yukla])

  if (royxat === null) return <Kutish />

  const faol = royxat.filter((x) => x.faol)
  const ochirilgan = royxat.filter((x) => !x.faol)

  /* "Roʻyxatda koʻrinmasin" belgisi kimga koʻrinadi:
       · oʻzi yashirin boʻlganga — doim;
       · hali birorta yashirin hisob boʻlmasa — adminlarga
         (tizim egasi birinchi marta oʻzini yashirishi uchun).
     Yashirin hisob paydo boʻlgach, boshqalar buni koʻrmaydi. */
  const menYashirin = royxat.some((x) => x.id === xodim?.id && x.yashirin)
  const yashirinKorsat = yashirinBor !== null && (menYashirin || yashirinBor === false)

  return (
    <div className="stack">
      {xato && <div className="alert err"><span>▲</span><div>{xato}</div></div>}

      <div className="card">
        <div className="card-h">
          <h3>Xodimlar</h3>
          <span className="sp" />
          <button className="btn pri sm" onClick={() => setModal({ tur: 'yangi' })}
            disabled={!!xato}>
            + Yangi profil
          </button>
        </div>

        <div className="card-b" style={{ paddingBottom: 4 }}>
          <div className="muted" style={{ maxWidth: '64ch' }}>
            Xodim tizimga <b>telefon raqami va paroli</b> bilan kiradi.
            Ikkalasini ham <b>Tahrirlash</b> orqali oʻzgartirasiz — parolni
            bilish shart emas. Xodim ishdan boʻshasa, oʻchirmang:
            <b>faolsizlantiring</b>, shunda uning nomi eski cheklar va
            hisobotlarda qolaveradi.
          </div>
        </div>

        {faol.length === 0 ? (
          <div className="card-b muted">Faol xodim yoʻq.</div>
        ) : (
          <div className="narx-royxat">
            {faol.map((x) => (
              <XodimQator key={x.id} x={x} men={xodim?.id === x.id}
                tahrir={() => setModal({ tur: 'tahrir', x })}
                ozgart={async (p) => {
                  const { error } = await amal.xodimTahrir({ id: x.id, ...p })
                  if (error) return xatoMatni(error)
                  bildir(`${x.fish} — saqlandi.`)
                  yukla()
                }} />
            ))}
          </div>
        )}
      </div>

      {ochirilgan.length > 0 && (
        <div className="card">
          <div className="card-h">
            <h3>Faolsizlantirilganlar</h3>
            <span className="sp" />
            <span className="muted">{ochirilgan.length} ta</span>
          </div>
          <div className="narx-royxat">
            {ochirilgan.map((x) => (
              <XodimQator key={x.id} x={x} men={xodim?.id === x.id}
                tahrir={() => setModal({ tur: 'tahrir', x })}
                ozgart={async (p) => {
                  const { error } = await amal.xodimTahrir({ id: x.id, ...p })
                  if (error) return xatoMatni(error)
                  bildir(`${x.fish} — saqlandi.`)
                  yukla()
                }} />
            ))}
          </div>
        </div>
      )}

      <div className="muted" style={{ maxWidth: '64ch' }}>
        Parolni oʻqib boʻlmaydi — u shifrlangan holda saqlanadi. Lekin xodim
        unutsa, <b>Tahrirlash</b> orqali yangisini qoʻyib berasiz: eski parolni
        bilish shart emas.
      </div>

      {modal?.tur === 'yangi' && (
        <YangiXodim
          yop={() => setModal(null)}
          tugadi={(m) => { setModal(null); bildir(m); yukla() }} />
      )}
      {modal?.tur === 'tahrir' && (
        <XodimTahrir x={modal.x} men={xodim?.id === modal.x.id}
          yashirinKorsat={yashirinKorsat}
          yop={() => setModal(null)}
          tugadi={(m) => { setModal(null); bildir(m); yukla() }} />
      )}

      <Xabar matn={xabar} />
    </div>
  )
}

/* ---------------- bitta xodim qatori ---------------- */
function XodimQator({ x, men, tahrir, ozgart }) {
  const [band, setBand] = useState(false)
  const [xato, setXato] = useState('')

  async function faollik() {
    setBand(true); setXato('')
    const e = await ozgart({ faol: !x.faol })
    setBand(false)
    if (e) setXato(e)
  }

  return (
    <div className="narx-qator">
      <div className="body">
        <b>{x.fish}{men && <span className="muted"> — siz</span>}</b>
        <div className="muted">
          {x.telefon || 'raqam yoʻq'}
          {!x.kira_oladi && ' · hisob bogʻlanmagan, kira olmaydi'}
        </div>
        {xato && <div style={{ color: 'var(--full)', fontSize: 12.5, marginTop: 3 }}>{xato}</div>}
      </div>

      <div className="row" style={{ gap: 8 }}>
        {x.yashirin && <span className="pill neutral">Roʻyxatda yoʻq</span>}
        <span className={'pill ' + (ROL_PILL[x.rol] || 'neutral')}>{x.rol_matn}</span>
        <button className="btn sm" onClick={tahrir}>Tahrirlash</button>
        {!men && (
          <button className={'btn sm' + (x.faol ? ' dan' : '')}
            onClick={faollik} disabled={band}>
            {band ? '…' : x.faol ? 'Faolsizlantirish' : 'Faollashtirish'}
          </button>
        )}
      </div>
    </div>
  )
}

/* ---------------- yangi profil ---------------- */
function YangiXodim({ yop, tugadi }) {
  const [v, setV] = useState({
    familiya: '', ism: '', telefon: '', parol: '', parol2: '', rol: 'administrator'
  })
  const [korsat, setKorsat] = useState(false)
  const [xato, setXato] = useState('')
  const [qadam, setQadam] = useState('')
  const [band, setBand] = useState(false)

  const s = (k) => (e) => setV({ ...v, [k]: e.target.value })
  const raqam = raqamlar(v.telefon)

  async function saqla() {
    setXato('')
    if (!v.familiya.trim()) return setXato('Familiyani kiriting.')
    if (!v.ism.trim()) return setXato('Ismni kiriting.')
    if (raqam.length < 9) return setXato('Telefon raqamini toʻliq kiriting.')
    if (v.parol.length < 6) return setXato('Parol kamida 6 ta belgidan iborat boʻlsin.')
    if (v.parol !== v.parol2) return setXato('Parollar bir xil emas.')

    setBand(true)
    try {
      /* 1 — raqam bandmi? Auth'da bekorga hisob ochilmasin */
      setQadam('Raqam tekshirilmoqda…')
      const { data: bandmi, error: e1 } = await amal.xodimTelefonBand(v.telefon)
      if (e1) throw e1
      if (bandmi) throw new Error('Bu telefon raqami bilan xodim allaqachon bor.')

      /* 2 — Auth'da hisob */
      setQadam('Hisob ochilmoqda…')
      const authId = await authHisobOch(loginEmail(v.telefon), v.parol)

      /* 3 — profil */
      setQadam('Profil saqlanmoqda…')
      const { error: e3 } = await amal.xodimQosh({
        auth_id: authId,
        familiya: v.familiya.trim(),
        ism: v.ism.trim(),
        telefon: v.telefon.trim(),
        rol: v.rol
      })
      if (e3) throw e3

      const r = ROLLAR.find((x) => x.k === v.rol)
      tugadi(`${v.familiya.trim()} ${v.ism.trim()} qoʻshildi — ${r ? r.n.toLowerCase() : v.rol}. `
        + `Login: ${v.telefon.trim()}`)
    } catch (err) {
      setXato(xatoMatni(err))
      setBand(false)
      setQadam('')
    }
  }

  return (
    <Modal sarlavha="Yangi xodim profili" yop={yop} kenglik={470}
      amallar={
        <>
          <button className="btn" onClick={yop} disabled={band}>Bekor qilish</button>
          <button className="btn pri" onClick={saqla} disabled={band}>
            {band ? (qadam || '…') : 'Profil ochish'}
          </button>
        </>
      }>

      {xato && <div className="alert err" style={{ marginBottom: 13 }}>
        <span>▲</span><div>{xato}</div></div>}

      <div className="row" style={{ gap: 10, flexWrap: 'nowrap', alignItems: 'flex-start' }}>
        <div className="field" style={{ flex: 1 }}>
          <label>Familiya</label>
          <input value={v.familiya} onChange={s('familiya')} autoFocus disabled={band} />
        </div>
        <div className="field" style={{ flex: 1 }}>
          <label>Ism</label>
          <input value={v.ism} onChange={s('ism')} disabled={band} />
        </div>
      </div>

      <div className="field">
        <label>Telefon raqami — login</label>
        <input value={v.telefon} onChange={s('telefon')} inputMode="tel"
          placeholder="+998 90 123 45 67" disabled={band} />
        <div className="hint">
          Xodim shu raqam bilan kiradi. Keyin Tahrirlash orqali oʻzgartirsa boʻladi.
          {raqam.length >= 9 && <>
            {' '}Ichki login: <b>{loginEmail(v.telefon)}</b> — bu manzilga
            hech qachon xat yuborilmaydi.
          </>}
        </div>
      </div>

      <div className="row" style={{ gap: 10, flexWrap: 'nowrap', alignItems: 'flex-start' }}>
        <div className="field" style={{ flex: 1 }}>
          <label>Parol</label>
          <input type={korsat ? 'text' : 'password'} value={v.parol}
            onChange={s('parol')} autoComplete="new-password" disabled={band} />
        </div>
        <div className="field" style={{ flex: 1 }}>
          <label>Parolni takrorlang</label>
          <input type={korsat ? 'text' : 'password'} value={v.parol2}
            onChange={s('parol2')} autoComplete="new-password" disabled={band} />
        </div>
      </div>
      <div className="field" style={{ marginTop: -6 }}>
        <div className="hint">
          Kamida 6 ta belgi.{' '}
          <button className="matn" type="button" onClick={() => setKorsat(!korsat)}>
            {korsat ? 'Parolni yashirish' : 'Parolni koʻrsatish'}
          </button>
        </div>
      </div>

      <div className="field">
        <label>Status</label>
        <div className="chips">
          {ROLLAR.map((r) => (
            <button key={r.k} type="button"
              className={'chip' + (v.rol === r.k ? ' on' : '')}
              onClick={() => setV({ ...v, rol: r.k })} disabled={band}>
              {r.n}
            </button>
          ))}
        </div>
        <div className="hint">{(ROLLAR.find((r) => r.k === v.rol) || {}).i}</div>
      </div>
    </Modal>
  )
}

/* ---------------- profilni tahrirlash ---------------- */
function XodimTahrir({ x, men, yashirinKorsat, yop, tugadi }) {
  const [v, setV] = useState({
    familiya: x.familiya || '', ism: x.ism || '', rol: x.rol,
    telefon: x.telefon || '', parol: '', parol2: '',
    yashirin: x.yashirin === true
  })
  const [korsat, setKorsat] = useState(false)
  const [xato, setXato] = useState('')
  const [qadam, setQadam] = useState('')
  const [band, setBand] = useState(false)

  const s = (k) => (e) => setV({ ...v, [k]: e.target.value })
  const sa = x.rol === 'super_admin'

  const raqam = raqamlar(v.telefon)
  const telOzgardi = raqam !== raqamlar(x.telefon)
  const parolOzgardi = v.parol.length > 0

  async function saqla() {
    setXato('')
    if (!v.familiya.trim()) return setXato('Familiyani kiriting.')
    if (!v.ism.trim()) return setXato('Ismni kiriting.')
    if (telOzgardi && raqam.length < 9) return setXato('Telefon raqamini toʻliq kiriting.')
    if (parolOzgardi) {
      if (v.parol.length < 6) return setXato('Parol kamida 6 ta belgidan iborat boʻlsin.')
      if (v.parol !== v.parol2) return setXato('Parollar bir xil emas.')
    }

    setBand(true)
    try {
      setQadam('Saqlanmoqda…')
      const { error: e1 } = await amal.xodimTahrir({
        id: x.id,
        familiya: v.familiya.trim(),
        ism: v.ism.trim(),
        rol: men || sa ? null : v.rol
      })
      if (e1) throw e1

      if (telOzgardi) {
        setQadam('Login yangilanmoqda…')
        const { error: e2 } = await amal.xodimTelefon(x.id, v.telefon.trim())
        if (e2) throw e2
      }
      if (parolOzgardi) {
        setQadam('Parol yangilanmoqda…')
        const { error: e3 } = await amal.xodimParol(x.id, v.parol)
        if (e3) throw e3
      }
      if (yashirinKorsat && v.yashirin !== (x.yashirin === true)) {
        setQadam('Belgilanmoqda…')
        const { error: e4 } = await amal.xodimYashir(x.id, v.yashirin)
        if (e4) throw e4
      }

      const nima = [telOzgardi && 'login', parolOzgardi && 'parol']
        .filter(Boolean).join(' va ')
      tugadi(`${v.familiya.trim()} ${v.ism.trim()} — saqlandi`
        + (nima ? `. Yangi ${nima} kuchga kirdi.` : '.'))
    } catch (err) {
      setXato(xatoMatni(err))
      setBand(false)
      setQadam('')
    }
  }

  return (
    <Modal sarlavha="Profilni tahrirlash" yop={yop} kenglik={470}
      amallar={
        <>
          <button className="btn" onClick={yop} disabled={band}>Bekor qilish</button>
          <button className="btn pri" onClick={saqla} disabled={band}>
            {band ? (qadam || '…') : 'Saqlash'}
          </button>
        </>
      }>

      {xato && <div className="alert err" style={{ marginBottom: 13 }}>
        <span>▲</span><div>{xato}</div></div>}

      <div className="row" style={{ gap: 10, flexWrap: 'nowrap', alignItems: 'flex-start' }}>
        <div className="field" style={{ flex: 1 }}>
          <label>Familiya</label>
          <input value={v.familiya} onChange={s('familiya')} autoFocus disabled={band} />
        </div>
        <div className="field" style={{ flex: 1 }}>
          <label>Ism</label>
          <input value={v.ism} onChange={s('ism')} disabled={band} />
        </div>
      </div>

      <div className="field">
        <label htmlFor="tt">Telefon raqami — login</label>
        <input id="tt" value={v.telefon} onChange={s('telefon')} inputMode="tel"
          placeholder="+998 90 123 45 67" disabled={band} />
        <div className="hint">
          {telOzgardi
            ? <>Login <b>{loginEmail(v.telefon)}</b> ga oʻzgaradi.
                {men && ' Bu sizning hisobingiz — keyingi kirishda yangi raqamni yozasiz.'}
                {' '}Parol oʻzgarmaydi.</>
            : 'Xodim shu raqam bilan kiradi. Oʻzgartirsangiz, login ham oʻzgaradi.'}
        </div>
      </div>

      <div className="field">
        <label>Parol</label>
        <div className="row" style={{ gap: 10, flexWrap: 'nowrap', alignItems: 'flex-start' }}>
          <input style={{ flex: 1 }} type={korsat ? 'text' : 'password'}
            value={v.parol} onChange={s('parol')} autoComplete="new-password"
            placeholder="Yangi parol" disabled={band || !x.kira_oladi} />
          <input style={{ flex: 1 }} type={korsat ? 'text' : 'password'}
            value={v.parol2} onChange={s('parol2')} autoComplete="new-password"
            placeholder="Takrorlang" disabled={band || !x.kira_oladi} />
        </div>
        <div className="hint">
          {x.kira_oladi
            ? <>Boʻsh qoldirsangiz parol oʻzgarmaydi. Kamida 6 ta belgi.{' '}
                <button className="matn" type="button" onClick={() => setKorsat(!korsat)}>
                  {korsat ? 'Yashirish' : 'Koʻrsatish'}
                </button></>
            : 'Bu profilga hisob bogʻlanmagan — parol oʻrnatib boʻlmaydi.'}
        </div>
      </div>

      <div className="field">
        <label>Status</label>
        {men ? (
          <>
            <div className="row"><span className={'pill ' + (ROL_PILL[x.rol] || 'neutral')}>
              {x.rol_matn}</span></div>
            <div className="hint">Oʻz rolingizni oʻzgartira olmaysiz.</div>
          </>
        ) : sa ? (
          <>
            <div className="row"><span className={'pill ' + (ROL_PILL[x.rol] || 'neutral')}>
              {x.rol_matn}</span></div>
            <div className="hint">Admin rolini faqat baza orqali oʻzgartirish mumkin —
              tasodifan huquqdan ayirib qoʻyilmasin.</div>
          </>
        ) : (
          <>
            <div className="chips">
              {ROLLAR.map((r) => (
                <button key={r.k} type="button"
                  className={'chip' + (v.rol === r.k ? ' on' : '')}
                  onClick={() => setV({ ...v, rol: r.k })} disabled={band}>
                  {r.n}
                </button>
              ))}
            </div>
            <div className="hint">{(ROLLAR.find((r) => r.k === v.rol) || {}).i}</div>
          </>
        )}
      </div>

      {/* Roʻyxatda koʻrinmaydigan hisob — tizim egasi uchun */}
      {yashirinKorsat && (
        <div className="field">
          <label>Koʻrinishi</label>
          <label className="row" style={{ gap: 8, cursor: 'pointer' }}>
            <input type="checkbox" checked={v.yashirin} disabled={band}
              onChange={(e) => setV({ ...v, yashirin: e.target.checked })} />
            <span>Roʻyxatda koʻrinmasin</span>
          </label>
          <div className="hint">
            Belgilangan hisob xodimlar roʻyxatida umuman koʻrinmaydi va uni
            boshqa adminlar tahrirlay, parolini almashtira olmaydi. Buni
            keyin faqat shu hisobning oʻzi ortga qaytara oladi.
          </div>
        </div>
      )}
    </Modal>
  )
}
