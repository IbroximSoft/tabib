import { useState } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { useAuth, ROL_NOMI, sahifaOchiq, HISOBOT_TABLARI } from '../lib/auth'
import Profil from './Profil'
import { Xabar } from './Modal'
import logo from '../assets/logo.png'

const SAHIFALAR = [
  { yol: '/',          nom: 'Dashboard',  ic: '◍', huquq: null },
  { yol: '/bemorlar',  nom: 'Bemorlar',   ic: '👤', huquq: null },
  { yol: '/xonalar',   nom: 'Xonalar',    ic: '▤', huquq: null },
  { yol: '/bronlar',   nom: 'Bronlar',    ic: '◷', huquq: null },
  { yol: '/tolovlar',  nom: 'Toʻlovlar',  ic: '₴', huquq: null },
  { yol: '/hisobot',   nom: 'Hisobotlar', ic: '▦', huquq: null },
  { yol: '/sozlama',   nom: 'Sozlamalar', ic: '⚙', huquq: 'sozlama' }
]

const BUGUN = () => new Date().toLocaleDateString('ru-RU')

export default function Layout() {
  const { xodim, rol, can, chiqish } = useAuth()
  const loc = useLocation()
  const [profil, setProfil] = useState(false)
  const [xabar, setXabar] = useState('')
  /* Registrator va buxgalterda hisobot sahifasida faqat ovqat
     hisobi bor — nomi ham shunday tursin, adashtirmasin. */
  const korinadi = SAHIFALAR
    .filter(s => sahifaOchiq(rol, s.yol, can))
    .map(s => (s.yol === '/hisobot' && HISOBOT_TABLARI[rol]
      ? { ...s, nom: 'Ovqat hisobi' } : s))
  const joriy = korinadi.find(s => s.yol === loc.pathname) || korinadi[0]

  const tema = () => {
    const h = document.documentElement
    h.dataset.theme = h.dataset.theme === 'dark' ? 'light' : 'dark'
  }

  return (
    <div className="app">
      <aside className="side">
        <div className="brand">
          <img src={logo} alt="" />
          <div className="t">
            <b>Muhiddin Tabib</b>
            <span>Boshqaruv tizimi</span>
          </div>
        </div>
        <nav>
          {korinadi.map(s => (
            <NavLink key={s.yol} to={s.yol} end={s.yol === '/'}
              className={({ isActive }) => isActive ? 'on' : ''}>
              <span className="ic">{s.ic}</span>{s.nom}
            </NavLink>
          ))}
        </nav>
        <div className="side-foot">
          <button className="who" onClick={() => setProfil(true)}
            title="Mening profilim">
            <b>{xodim?.fish || '—'}</b>
            <span>{ROL_NOMI[rol] || 'Huquq berilmagan'}</span>
          </button>
          <button className="btn icon" onClick={tema} title="Yorugʻ / qorongʻi">◐</button>
          <button className="btn icon" onClick={chiqish} title="Chiqish">⏻</button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <h2>{joriy?.nom}</h2>
          <span className="date num">{BUGUN()}</span>
          <span className="sp" />
          {/* Profil tugmasi har qanday ekranda ko'rinadi — mobilda
              yon menyu yashirin, shuning uchun chiqish ham shu yerdan */}
          <button className="btn sm" onClick={() => setProfil(true)}
            title="Mening profilim">
            <span className="hide-m">{xodim?.fish || 'Profil'}</span>
            <span className="faqat-m">Profil</span>
          </button>
          <button className="btn sm hide-m" onClick={chiqish}>Chiqish</button>
        </header>
        <div className="content"><Outlet /></div>
      </div>

      {profil && (
        <Profil yop={() => setProfil(false)}
          saqlandi={(m) => {
            setProfil(false)
            setXabar(m)
            setTimeout(() => setXabar(''), 5000)
          }} />
      )}
      <Xabar matn={xabar} />

      <nav className="bottom-nav">
        {korinadi.slice(0, 5).map(s => (
          <NavLink key={s.yol} to={s.yol} end={s.yol === '/'}
            className={({ isActive }) => isActive ? 'on' : ''}>
            <span className="ic">{s.ic}</span>{s.nom}
          </NavLink>
        ))}
      </nav>
    </div>
  )
}
