import { useState } from 'react'
import Modal from './Modal'
import { useAuth, ROL_NOMI } from '../lib/auth'
import {
  supabase, amal, xatoMatni, loginEmail, raqamlar, parolTekshir
} from '../lib/supabase'

/* ============================================================
   MENING PROFILIM

   Har bir xodim o'zining ism-familiyasi, telefon raqami
   (u ayni paytda login) va parolini shu yerdan o'zgartiradi.
   Rol bu yerda ko'rinadi, lekin o'zgarmaydi — u super
   adminning ishi.

   PAROL QOIDASI
     Oddiy xodim yangi parol qo'yishdan oldin ESKI parolini
     yozishi shart. Tekshiruv alohida, sessiyani saqlamaydigan
     mijoz orqali ketadi — shunda joriy sessiya buzilmaydi.
     Super admin esa eski parolsiz ham o'zgartira oladi.
   ============================================================ */
export default function Profil({ yop, saqlandi }) {
  const { xodim, rol, session, chiqish } = useAuth()
  const superAdmin = rol === 'super_admin'

  const [v, setV] = useState({
    familiya: xodim?.familiya || (xodim?.fish || '').split(' ')[0] || '',
    ism: xodim?.ism || (xodim?.fish || '').split(' ').slice(1).join(' ') || '',
    telefon: xodim?.telefon || '',
    eski: '', parol: '', parol2: ''
  })
  const [korsat, setKorsat] = useState(false)
  const [xato, setXato] = useState('')
  const [qadam, setQadam] = useState('')
  const [band, setBand] = useState(false)

  const s = (k) => (e) => setV({ ...v, [k]: e.target.value })

  const raqam = raqamlar(v.telefon)
  const telOzgardi = raqam !== raqamlar(xodim?.telefon)
  const parolOzgardi = v.parol.length > 0
  const joriyLogin = session?.user?.email || ''

  async function saqla() {
    setXato('')
    if (!v.familiya.trim()) return setXato('Familiyani kiriting.')
    if (!v.ism.trim()) return setXato('Ismni kiriting.')
    if (telOzgardi && raqam.length < 9) return setXato('Telefon raqamini toʻliq kiriting.')
    if (parolOzgardi) {
      if (!superAdmin && !v.eski) return setXato('Eski parolingizni kiriting.')
      if (v.parol.length < 6) return setXato('Yangi parol kamida 6 ta belgidan iborat boʻlsin.')
      if (v.parol !== v.parol2) return setXato('Yangi parollar bir xil emas.')
      if (v.eski && v.eski === v.parol) return setXato('Yangi parol eskisidan farq qilsin.')
    }

    setBand(true)
    try {
      /* 1 — eski parol. Raqam oʻzgarishidan OLDIN tekshiriladi,
             chunki login manzili keyin oʻzgarib ketadi. */
      if (parolOzgardi && !superAdmin) {
        setQadam('Parol tekshirilmoqda…')
        const togri = await parolTekshir(joriyLogin, v.eski)
        if (!togri) throw new Error('Eski parol notoʻgʻri.')
      }

      /* 2 — ism va raqam */
      setQadam('Saqlanmoqda…')
      const { error: e1 } = await amal.meningProfilim({
        familiya: v.familiya.trim(),
        ism: v.ism.trim(),
        telefon: v.telefon.trim()
      })
      if (e1) throw e1

      /* 3 — yangi parol. Bu xodimning oʻz hisobi, shuning uchun
             hech qanday maxfiy kalit kerak emas. */
      if (parolOzgardi) {
        setQadam('Parol yangilanmoqda…')
        const { error: e2 } = await supabase.auth.updateUser({ password: v.parol })
        if (e2) throw e2
      }

      const nima = [telOzgardi && 'login', parolOzgardi && 'parol']
        .filter(Boolean).join(' va ')
      saqlandi(`Profilingiz saqlandi${nima ? `. Yangi ${nima} kuchga kirdi.` : '.'}`)
    } catch (err) {
      setXato(xatoMatni(err))
      setBand(false)
      setQadam('')
    }
  }

  return (
    <Modal sarlavha="Mening profilim" yop={yop} kenglik={470}
      amallar={<>
        <button className="btn" onClick={yop} disabled={band}>Yopish</button>
        <button className="btn pri" onClick={saqla} disabled={band}>
          {band ? (qadam || '…') : 'Saqlash'}
        </button>
      </>}>

      {xato && <div className="alert err" style={{ marginBottom: 13 }}>
        <span>▲</span><div>{xato}</div></div>}

      <div className="karta-bosh">
        <div>
          <h3>{xodim?.fish || '—'}</h3>
          <div className="muted">{ROL_NOMI[rol] || 'Huquq berilmagan'}</div>
        </div>
        <span className="sp" />
        <button className="btn sm" onClick={chiqish} disabled={band}>Chiqish</button>
      </div>

      <div className="row" style={{ gap: 10, flexWrap: 'nowrap', alignItems: 'flex-start' }}>
        <div className="field" style={{ flex: 1 }}>
          <label htmlFor="pf">Familiya</label>
          <input id="pf" value={v.familiya} onChange={s('familiya')} disabled={band} />
        </div>
        <div className="field" style={{ flex: 1 }}>
          <label htmlFor="pi">Ism</label>
          <input id="pi" value={v.ism} onChange={s('ism')} disabled={band} />
        </div>
      </div>

      <div className="field">
        <label htmlFor="pt">Telefon raqami — login</label>
        <input id="pt" value={v.telefon} onChange={s('telefon')} inputMode="tel"
          placeholder="+998 90 123 45 67" disabled={band} />
        <div className="hint">
          {telOzgardi
            ? <>Login <b>{loginEmail(v.telefon)}</b> ga oʻzgaradi — keyingi kirishda
                yangi raqamni yozasiz.</>
            : 'Tizimga shu raqam bilan kirasiz.'}
        </div>
      </div>

      <div className="bolim-bosh" style={{ marginTop: 6 }}><h4>Parolni oʻzgartirish</h4></div>

      {!superAdmin && (
        <div className="field">
          <label htmlFor="pe">Eski parol</label>
          <input id="pe" type={korsat ? 'text' : 'password'} value={v.eski}
            onChange={s('eski')} autoComplete="current-password" disabled={band} />
        </div>
      )}

      <div className="field">
        <label>Yangi parol</label>
        <div className="row" style={{ gap: 10, flexWrap: 'nowrap', alignItems: 'flex-start' }}>
          <input style={{ flex: 1 }} type={korsat ? 'text' : 'password'}
            value={v.parol} onChange={s('parol')} autoComplete="new-password"
            placeholder="Yangi parol" disabled={band} />
          <input style={{ flex: 1 }} type={korsat ? 'text' : 'password'}
            value={v.parol2} onChange={s('parol2')} autoComplete="new-password"
            placeholder="Takrorlang" disabled={band} />
        </div>
        <div className="hint">
          Boʻsh qoldirsangiz parol oʻzgarmaydi. Kamida 6 ta belgi.{' '}
          <button className="matn" type="button" onClick={() => setKorsat(!korsat)}>
            {korsat ? 'Yashirish' : 'Koʻrsatish'}
          </button>
          {superAdmin && <><br />Admin sifatida eski parolni yozmasangiz ham boʻladi.</>}
        </div>
      </div>
    </Modal>
  )
}
