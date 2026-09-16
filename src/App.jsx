import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth, sahifaOchiq } from './lib/auth'
import Layout from './components/Layout'
import { Kutish } from './components/Kutish'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Bemorlar from './pages/Bemorlar'
import Sozlamalar from './pages/Sozlamalar'
import Xonalar from './pages/Xonalar'
import Bronlar from './pages/Bronlar'
import Tolovlar from './pages/Tolovlar'
import Hisobotlar from './pages/Hisobotlar'

/* Rol berilmagan xodim uchun */
function HuquqYoq() {
  const { xodim, chiqish } = useAuth()
  return (
    <div className="center-note">
      <div style={{ maxWidth: 380 }}>
        <h2 style={{ fontSize: 19, marginBottom: 8 }}>Hisobingizga rol berilmagan</h2>
        <p className="muted" style={{ marginBottom: 18 }}>
          {xodim?.fish} hisobi tizimda bor, lekin unga hali rol biriktirilmagan
          yoki hisob faol emas. Adminga murojaat qiling.
        </p>
        <button className="btn" onClick={chiqish}>Chiqish</button>
      </div>
    </div>
  )
}

function Himoyalangan() {
  const { session, rol, yuklanmoqda } = useAuth()
  if (yuklanmoqda) return <Kutish />
  if (!session) return <Navigate to="/login" replace />
  if (!rol) return <HuquqYoq />
  return <Layout />
}

/* Sahifa roliga ochiqmi. Manzilni qo'lda yozib kirishning oldini
   oladi — menyuda ko'rinmagan sahifa ochilmaydi ham. */
function Sahifa({ yol, children }) {
  const { rol, can } = useAuth()
  return sahifaOchiq(rol, yol, can) ? children : <Navigate to="/" replace />
}

function Kirilgan({ children }) {
  const { session, yuklanmoqda } = useAuth()
  if (yuklanmoqda) return <Kutish />
  if (session) return <Navigate to="/" replace />
  return children
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Kirilgan><Login /></Kirilgan>} />
          <Route element={<Himoyalangan />}>
            <Route index element={<Sahifa yol="/"><Dashboard /></Sahifa>} />
            <Route path="bemorlar"
              element={<Sahifa yol="/bemorlar"><Bemorlar /></Sahifa>} />
            <Route path="xonalar"
              element={<Sahifa yol="/xonalar"><Xonalar /></Sahifa>} />
            <Route path="bronlar"
              element={<Sahifa yol="/bronlar"><Bronlar /></Sahifa>} />
            <Route path="tolovlar"
              element={<Sahifa yol="/tolovlar"><Tolovlar /></Sahifa>} />
            <Route path="hisobot"
              element={<Sahifa yol="/hisobot"><Hisobotlar /></Sahifa>} />
            <Route path="sozlama"
              element={<Sahifa yol="/sozlama"><Sozlamalar /></Sahifa>} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}
