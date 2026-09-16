import { useEffect } from 'react'

/* Umumiy modal oynasi. Sahifalar shuni ishlatadi. */
export default function Modal({ sarlavha, yop, children, amallar, kenglik = 540 }) {
  useEffect(() => {
    const h = (e) => { if (e.key === 'Escape') yop() }
    document.addEventListener('keydown', h)
    const eski = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', h)
      document.body.style.overflow = eski
    }
  }, [yop])

  return (
    <div className="scrim" onMouseDown={(e) => { if (e.target === e.currentTarget) yop() }}>
      <div className="modal" style={{ maxWidth: kenglik }} role="dialog" aria-modal="true">
        <div className="modal-h">
          <h3>{sarlavha}</h3>
          <span className="sp" />
          <button className="btn icon" onClick={yop} aria-label="Yopish">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor"
              strokeWidth="2.2" strokeLinecap="round"><path d="M18 6 6 18M6 6l12 12" /></svg>
          </button>
        </div>
        <div className="modal-b">{children}</div>
        {amallar && <div className="modal-f">{amallar}</div>}
      </div>
    </div>
  )
}

/* Kichik xabar (toast) */
export function Xabar({ matn, tur = 'ok' }) {
  if (!matn) return null
  return <div className={`toast ${tur}`}>{matn}</div>
}
