import { createContext, useContext, useEffect, useState } from 'react'
import { supabase, sozlanmagan, loginEmail } from './supabase'

/* Rol -> huquqlar. Bu FAQAT interfeys uchun: tugmalarni yashirish,
   sahifalarni bekitish. Haqiqiy himoya bazada (RLS + funksiyalar). */
/*  'pul' — pulga oid hamma narsani KO'RISH huquqi: qarz ustuni,
    to'lov tarixi, hisob-kitob bloklari, xona narxlari.
    Registratorda yo'q: uning ishi ro'yxat va joylashtirish,
    pulga aralashmaydi. */
export const HUQUQLAR = {
  super_admin:   ['royxat', 'joylash', 'uzaytir', 'chiqar', 'tolov', 'bron', 'sozlama', 'pul', 'dam_olish'],
  /* Registrator — qabul va joylashtirish. Pul ham, chiqarish ham
     unda emas: bemorni chiqarishda qarz tekshiriladi, bu esa
     kassaning ishi. */
  administrator: ['royxat', 'joylash', 'uzaytir', 'bron'],
  /* Buxgalter — kassa. Qarzi yopilgan bemorni chiqara ham oladi
     (pulni u qabul qiladi, demak chiqarishni ham u yopadi).
     Narxlar esa faqat super adminda. */
  buxgalter:     ['tolov', 'chiqar', 'pul', 'dam_olish'],
  /* Kuzatuvchi — hammasini ko'radi, hech narsaga tegmaydi */
  viewer:        ['pul']
}

/* Qaysi rol qaysi sahifani ko'radi.
   Ro'yxatda turmagan rol uchun eski qoida ishlaydi: sahifaning
   o'z huquqi bo'lsa (masalan 'sozlama') shu tekshiriladi, aks
   holda hamma sahifa ochiq.

   Buxgalterga ataylab kamaytirilgan: dashboard, mijozlar
   ro'yxati (u yerdan to'lov qabul qilinadi va to'lov tarixi
   ko'rinadi) va to'lovlar sahifasi.

   Registratorga: dashboard, bemorlar, xonalar holati va
   bronlar. To'lovlar unda yo'q.

   Hisobot sahifasi ikkalasida ham bor, lekin ichida faqat
   ovqat hisobi — pastdagi HISOBOT_TABLARI ga qarang. */
export const ROL_SAHIFALARI = {
  administrator: ['/', '/bemorlar', '/xonalar', '/bronlar', '/hisobot'],
  buxgalter: ['/', '/bemorlar', '/tolovlar', '/hisobot']
}

/* Hisobot sahifasidagi qaysi bo'limni kim ko'radi.
   Ro'yxatda turmagan rol (super admin, kuzatuvchi) hammasini
   ko'radi. Registrator va buxgalterga faqat "Ovqat hisobi" —
   oshxonaga kunlik porsiya sonini aytish uchun shu kerak,
   tushum va qarz raqamlari esa ularga ochilmaydi. */
export const HISOBOT_TABLARI = {
  administrator: ['ovqat'],
  buxgalter: ['ovqat']
}

export function sahifaOchiq(rol, yol, can) {
  const ruxsat = ROL_SAHIFALARI[rol]
  if (ruxsat) return ruxsat.includes(yol)
  if (yol === '/sozlama') return can ? can('sozlama') : false
  return true
}

/* Rol nomlari — ekranda shu ko'rinadi.
   Eng yuqori rol "Admin" deb ataladi: tizimda undan ustun
   yana kimdir borligi bilinib turmasin (25_yashirin_admin.sql).
   Bazadagi nomi o'zgarmagan — u hali ham super_admin. */
export const ROL_NOMI = {
  super_admin: 'Admin',
  administrator: 'Registrator',
  buxgalter: 'Buxgalter',
  viewer: 'Kuzatuvchi'
}

const Ctx = createContext(null)
export const useAuth = () => useContext(Ctx)

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [xodim, setXodim] = useState(null)
  const [yuklanmoqda, setYuklanmoqda] = useState(true)

  useEffect(() => {
    if (sozlanmagan) { setYuklanmoqda(false); return }

    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      if (!data.session) setYuklanmoqda(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSession(s)
      if (!s) { setXodim(null); setYuklanmoqda(false) }
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  /* Sessiya bor — xodim yozuvini va rolini olamiz */
  useEffect(() => {
    if (!session) return
    let bekor = false
    ;(async () => {
      const { data, error } = await supabase
        .from('xodimlar')
        /* DIQQAT: bu yerga yangi ustun qo'shmang. 17_xodimlar.sql
           hali ishga tushmagan bazada so'rov xato beradi va hamma
           tizimdan chiqib qoladi. fish yetarli. */
        .select('id, fish, rol, faol, telefon')
        .eq('auth_id', session.user.id)
        .maybeSingle()
      if (bekor) return
      if (error || !data || !data.faol) {
        setXodim({ yoq: true, fish: session.user.email })
      } else {
        setXodim(data)
      }
      setYuklanmoqda(false)
    })()
    return () => { bekor = true }
  }, [session])

  const rol = xodim && !xodim.yoq ? xodim.rol : null
  const can = (h) => !!rol && HUQUQLAR[rol].includes(h)

  /* Xodimlar telefon raqami bilan kirishadi. Auth esa pochta
     bilan ishlaydi — shuning uchun raqamni ichki pochtaga
     o'giramiz. Kiritilgan matnda "@" bo'lsa (eski hisoblar)
     u o'zgarishsiz ketadi. */
  const kirish = async (login, parol) => {
    const { error } = await supabase.auth.signInWithPassword({
      email: loginEmail(login), password: parol
    })
    if (error) throw error
  }

  const chiqish = async () => {
    await supabase.auth.signOut()
    setXodim(null)
  }

  return (
    <Ctx.Provider value={{ session, xodim, rol, can, kirish, chiqish, yuklanmoqda }}>
      {children}
    </Ctx.Provider>
  )
}
