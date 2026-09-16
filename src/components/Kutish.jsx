export function Kutish({ matn = 'Yuklanmoqda…' }) {
  return (
    <div className="center-note">
      <div>
        <div className="spinner" style={{ margin: '0 auto 12px' }} />
        <div className="muted">{matn}</div>
      </div>
    </div>
  )
}

export function Bosqich({ nom }) {
  return (
    <div className="todo">
      <b style={{ display: 'block', color: 'var(--ink-2)', marginBottom: 6 }}>{nom}</b>
      Bu ekran keyingi bosqichda toʻldiriladi.
    </div>
  )
}
