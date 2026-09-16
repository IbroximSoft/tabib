import { useState } from 'react'
import { useAuth } from '../lib/auth'
import { xatoMatni, sozlanmagan } from '../lib/supabase'
import logo from '../assets/logo.png'

export default function Login() {
  const { kirish } = useAuth()
  const [login, setLogin] = useState('')
  const [parol, setParol] = useState('')
  const [korsat, setKorsat] = useState(false)
  const [xato, setXato] = useState('')
  const [band, setBand] = useState(false)

  async function yubor(e) {
    e.preventDefault()
    setXato('')
    if (!login.trim() || !parol) {
      setXato('Telefon raqami va parolni kiriting.')
      return
    }
    setBand(true)
    try {
      await kirish(login.trim(), parol)
    } catch (err) {
      setXato(xatoMatni(err))
      setBand(false)
    }
  }

  return (
    <div className="login">
      <aside className="login-art">
        <div className="art-in">
          <div className="brandline">
            <span className="mark">M</span>
            <b>Muhiddin Tabib</b>
          </div>

          <div className="mid">
            <h1>Bemorlar va xonalar bir joyda</h1>
            <p>
              Qabul, joylashtirish, toʻlov va chiqish — hammasi bitta tizimda.
              Xona bandligi real holatda koʻrinadi.
            </p>
            <div className="stats">
              <div className="stat"><b>4</b><span>boʻlim</span></div>
              <div className="stat"><b>27</b><span>koyka</span></div>
              <div className="stat"><b>24/7</b><span>nazorat</span></div>
            </div>
          </div>
        </div>
      </aside>

      <main className="login-form">
        <div className="login-box">
          <div className="logo-slot">
            <img src={logo} alt="Muhiddin Tabib" />
          </div>

          <h2>Tizimga kirish</h2>
          <div className="sub">Telefon raqamingiz va parolingiz bilan kiring.</div>

          {sozlanmagan && (
            <div className="err">
              Supabase ulanmagan. Loyiha papkasida <b>.env</b> faylini yarating va
              <b> VITE_SUPABASE_URL</b> hamda <b>VITE_SUPABASE_ANON_KEY</b> qiymatlarini yozing.
            </div>
          )}
          {xato && <div className="err">{xato}</div>}

          <form onSubmit={yubor}>
            <div className="field">
              <label htmlFor="login">Telefon raqami</label>
              <input
                id="login" type="text" inputMode="tel" autoComplete="username"
                value={login} onChange={(e) => setLogin(e.target.value)}
                placeholder="+998 90 123 45 67" disabled={band || sozlanmagan}
              />
            </div>

            <div className="field">
              <label htmlFor="parol">Parol</label>
              <div className="pw-wrap">
                <input
                  id="parol" type={korsat ? 'text' : 'password'} autoComplete="current-password"
                  value={parol} onChange={(e) => setParol(e.target.value)}
                  placeholder="••••••••" disabled={band || sozlanmagan}
                />
                <button type="button" onClick={() => setKorsat(!korsat)} tabIndex={-1}>
                  {korsat ? 'Yashirish' : 'Koʻrsatish'}
                </button>
              </div>
            </div>

            <button className="btn pri block" type="submit" disabled={band || sozlanmagan}>
              {band ? 'Kirilmoqda…' : 'Kirish'}
            </button>
          </form>

          <div className="foot">
            Parolni unutdingizmi yoki hisob yoʻqmi — adminga murojaat qiling.
            Hisoblar tizim ichida ochiladi.
          </div>
        </div>
      </main>
    </div>
  )
}
