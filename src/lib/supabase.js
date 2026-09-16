import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const sozlanmagan = !url || !key || url.includes('xxxxxxxx')

export const supabase = sozlanmagan
  ? null
  : createClient(url, key, {
      auth: { persistSession: true, autoRefreshToken: true }
    })

/* ============================================================
   Bazadagi xatolarni foydalanuvchi tiliga o'giramiz.
   Postgres trigger'lari o'zbekcha matn qaytaradi, shuning uchun
   ko'p hollarda xabarni to'g'ridan-to'g'ri ko'rsatamiz.
   ============================================================ */
export function xatoMatni(e) {
  if (!e) return 'Nomaʼlum xato.'
  const m = e.message || String(e)

  if (m.includes('koyka_band_emas'))
    return 'Bu koyka tanlangan sanalarda allaqachon band.'
  if (m.includes('bemorlar_telefon_uniq'))
    return 'Bu telefon raqami bilan bemor allaqachon roʻyxatda bor.'
  if (m.includes('insufficient_privilege') || m.includes('huquqi yoʻq'))
    return m.replace(/^.*?:\s*/, '')
  if (m.includes('Failed to fetch') || m.includes('NetworkError'))
    return 'Serverga ulanib boʻlmadi. Internetni tekshiring.'
  if (m.includes('Invalid login credentials'))
    return 'Telefon raqami yoki parol notoʻgʻri.'
  if (m.includes('Email not confirmed'))
    return 'Hisob tasdiqlanmagan. Supabase → Authentication → Providers → Email da '
         + '“Confirm email” ni oʻchiring.'

  /* xodim profili ochishdagi xatolar */
  if (m.includes('xodim_telefon_uniq'))
    return 'Bu telefon raqami bilan xodim allaqachon bor.'
  if (m.includes('User already registered') || m.includes('already been registered'))
    return 'Bu raqam bilan hisob allaqachon ochilgan. Boshqa raqam kiriting yoki '
         + 'mavjud profilni tahrirlang.'
  if (m.includes('Password should be at least'))
    return 'Parol juda qisqa — kamida 6 ta belgi boʻlsin.'
  if (m.includes('Signups not allowed') || m.includes('signup_disabled'))
    return 'Supabase’da yangi hisob ochish oʻchirilgan. Authentication → Providers → '
         + 'Email da “Allow new users to sign up” ni yoqing.'
  if (/is invalid/i.test(m) && /email|address/i.test(m))
    return 'Supabase bu login manzilini qabul qilmadi: ' + (m.match(/"([^"]+)"/) || [])[1]
         + '. Sabab — domen. Loyiha papkasidagi .env faylida '
         + 'VITE_LOGIN_DOMEN ni haqiqiy domenga oʻzgartiring '
         + '(masalan muhiddintabib.uz) va serverni qayta ishga tushiring. '
         + 'DIQQAT: domen bir marta tanlanadi — keyin oʻzgartirilsa, '
         + 'eski xodimlar tizimga kira olmay qoladi.'
  /* Baza yangilanmagan bo'lsa — qaysi faylni ishga tushirish kerakligini aytamiz */
  if (/Could not find the function/i.test(m) || m.includes('PGRST202')) {
    if (/tolov_qaytar|qaytariladi|bemor_chiqar_qaytarib|ortiqcha_hisobga|bemor_chiqar_ortiqcha_bilan/.test(m))
      return 'Pul qaytarish funksiyasi bazada hali yoʻq. Supabase → SQL Editor da '
           + '24_qaytarish.sql faylini ishga tushiring.'
    if (/xodim_yashir|yashirin_bormi/.test(m))
      return 'Bu imkoniyat bazada hali yoʻq. Supabase → SQL Editor da '
           + '25_yashirin_admin.sql faylini ishga tushiring.'
    if (/bemor_ochir|xona_tahrir|xona_koyka/.test(m))
      return 'Oʻchirish va tahrirlash funksiyalari bazada hali yoʻq. Supabase → SQL '
           + 'Editor da 26_tahrir_ochirish.sql faylini ishga tushiring.'
    return 'Bu amal bazada hali oʻrnatilmagan. SQL fayllarini tartib bilan ishga '
         + 'tushiring (07_tekshirish.sql qaysi fayl kerakligini koʻrsatadi).'
  }
  if (m.includes('For security purposes') || m.includes('rate limit')
      || m.includes('Too many requests'))
    return 'Juda tez-tez soʻralmoqda. Bir necha daqiqadan soʻng qayta urinib koʻring.'
  return m
}

/* ============================================================
   MA'LUMOT O'QISH — barchasi VIEW lardan
   ============================================================ */
export const db = {
  umumiy: () =>
    supabase.from('v_umumiy').select('*').single(),

  yotganlar: () =>
    supabase.from('v_hozir_yotganlar').select('*').order('xona'),

  yotqizishlar: (f = {}) => {
    let q = supabase.from('v_yotqizishlar').select('*')
    if (f.holat) q = q.eq('holat', f.holat)
    if (f.bolim_id) q = q.eq('bolim_id', f.bolim_id)
    if (f.roli) q = q.eq('roli', f.roli)
    if (f.jins) q = q.eq('jins', f.jins)
    if (f.qarzdor === true) q = q.eq('qarzdor', true)
    if (f.qarzdor === false) q = q.eq('qarzdor', false)
    if (f.dan) q = q.gte('kirish_sana', f.dan)
    if (f.gacha) q = q.lte('kirish_sana', f.gacha)
    if (f.q) q = q.or(`fish.ilike.%${f.q}%,telefon.ilike.%${f.q}%`)
    return q.order('kirish_sana', { ascending: false })
  },

  qarzdorlar: () => supabase.from('v_qarzdorlar').select('*'),

  xonalar: () => supabase.from('v_xona_holati').select('*').order('raqam'),

  /* Har bir koyka bo'yicha bitta qator — Xonalar ekrani (12_xonalar_korinishi.sql) */
  koykaHolati: () => supabase.from('v_koykalar').select('*'),

  bolimlar: () => supabase.from('bolimlar').select('*').order('tartib'),

  koykalar: () =>
    supabase.from('koykalar').select('id, raqam, xona_id, xonalar(raqam, bolim_id, tamirlashda)'),

  /* Bronlar — holat ekranda hisoblangan holda keladi (14_bronlar.sql) */
  bronlar: (f = {}) => {
    let q = supabase.from('v_bronlar').select('*')
    if (f.holat) q = q.eq('holat', f.holat)
    return q.order('kirish')
  },

  /* Tanlangan sanalarda qaysi xonada joy bor (14_bronlar.sql) */
  bronBoshJoylar: (kirish, chiqish, jins = null, bron = null) =>
    supabase.rpc('bron_bosh_joylar', {
      p_kirish: kirish,
      p_chiqish: chiqish,
      ...(jins ? { p_jins: jins } : {}),
      ...(bron ? { p_bron: bron } : {})
    }),

  bronKonfliktlari: () => supabase.from('v_bron_konfliktlari').select('*'),

  tolovlar: (f = {}) => {
    let q = supabase.from('v_tolovlar').select('*')
    if (f.yotqizish_id) q = q.eq('yotqizish_id', f.yotqizish_id)
    if (f.dan) q = q.gte('sana', f.dan)
    if (f.gacha) q = q.lte('sana', f.gacha)
    if (f.usuli) q = q.eq('usuli', f.usuli)
    return q.order('tolov_id', { ascending: false })
  },

  tariflar: () => supabase.from('tariflar').select('*'),

  bolimHisoboti: () => supabase.from('v_bolim_hisoboti').select('*'),

  /* Muddati o'tgan, chiqarilmagan bemorlar (06_tuzatishlar.sql) */
  tasdiqlanmagan: () =>
    supabase.from('v_tasdiqlanmagan').select('*').order('kechikkan_kun', { ascending: false }),

  /* Ovqat hisobi — mahal bo'yicha (06_tuzatishlar.sql) */
  ovqatHisobi: (sana = null) =>
    supabase.rpc('ovqat_hisobi', sana ? { p_sana: sana } : {}),

  /* Mavjud bemorni telefon yoki ism bo'yicha topish — dublikatni oldini olish */
  bemorQidir: (matn) => supabase.rpc('bemor_qidir', { p_matn: matn }),

  /* Shu raqamga ochiq bron bormi (19_bron_bogla.sql) —
     "Yangi bemor" formasi ogohlantirish uchun chaqiradi */
  bronQidir: (telefon) => supabase.rpc('bron_qidir', { p_telefon: telefon }),

  /* Bemorga biriktirilgan farzand va qarovchilar (08_hamrohlar.sql) */
  hamrohlar: (yotqizishId) => supabase.rpc('hamrohlar', { p_yotqizish: yotqizishId }),

  /* Sozlamalar — xona turlari va narxlari (11_xona_turlari.sql) */
  xonaNarxlari: () => supabase.from('v_xona_narxlari').select('*'),

  /* Xodim profillari (17_xodimlar.sql) */
  xodimlar: () => supabase.from('v_xodimlar').select('*'),

  narxTarixi: (limit = 30) =>
    supabase.from('narx_tarixi').select('*').order('vaqt', { ascending: false }).limit(limit),

  hisobotKunlik: (dan, gacha) =>
    supabase.rpc('hisobot_kunlik', { p_dan: dan, p_gacha: gacha }),

  hisobotMoliya: (dan, gacha) =>
    supabase.rpc('hisobot_moliya', { p_dan: dan, p_gacha: gacha }),

  hisobotKassir: (dan, gacha) =>
    supabase.rpc('hisobot_kassir', { p_dan: dan, p_gacha: gacha }),

  /* ---- 15_hisobotlar.sql ---- */
  hisobotXulosa: (dan, gacha) =>
    supabase.rpc('hisobot_xulosa', { p_dan: dan, p_gacha: gacha }),

  hisobotBemorlar: (dan, gacha) =>
    supabase.rpc('hisobot_bemorlar', { p_dan: dan, p_gacha: gacha }),

  /* Ovqat hisobi — haqiqiy chiqish sanasi bo'yicha */
  hisobotOvqat: (dan, gacha) =>
    supabase.rpc('hisobot_ovqat', { p_dan: dan, p_gacha: gacha }),

  hisobotBron: (dan, gacha) =>
    supabase.rpc('hisobot_bron', { p_dan: dan, p_gacha: gacha }),

  boshXonalar: (sana, bolim = null) =>
    supabase.rpc('bosh_xonalar', { p_sana: sana, p_bolim: bolim }),

  chek: (tolovId) => supabase.rpc('chek', { p_tolov: tolovId })
}

/* ============================================================
   AMALLAR — hammasi RPC orqali.
   Huquq tekshiruvi baza ichida, bu yerda emas.
   ============================================================ */
export const amal = {
  /* Bemor + farzand/qarovchilari — bitta tranzaksiyada (08_hamrohlar.sql).
     Hamrohlar avtomatik asosiy bemorga biriktiriladi. */
  bemorQabul: (p) =>
    supabase.rpc('bemor_qabul', {
      p_familiya: p.familiya,
      p_ism: p.ism,
      p_jins: p.jins,
      p_telefon: p.telefon,
      p_yosh: p.yosh,
      p_chet_el: p.chet_el,
      p_koyka: p.koyka_id ?? null,
      p_kirish: p.kirish,
      p_reja_chiqish: p.reja_chiqish,
      p_oldindan: p.oldindan ?? 0,
      p_bemor_id: p.bemor_id ?? null,
      p_hamrohlar: p.hamrohlar ?? []
    }),

  bemorJoylashtir: (p) =>
    supabase.rpc('bemor_joylashtir', {
      p_familiya: p.familiya,
      p_ism: p.ism,
      p_jins: p.jins,
      p_telefon: p.telefon,
      p_yosh: p.yosh,
      p_chet_el: p.chet_el,
      p_roli: p.roli,
      p_koyka: p.koyka_id ?? null,
      p_kirish: p.kirish,
      p_reja_chiqish: p.reja_chiqish,
      p_oldindan: p.oldindan ?? 0,
      p_asosiy: p.asosiy ?? null,
      /* qayta kelgan bemor uchun — mavjud yozuv ishlatiladi, dublikat yaratilmaydi */
      p_bemor_id: p.bemor_id ?? null
    }),

  koykaBiriktir: (yotqizishId, koykaId) =>
    supabase.rpc('koyka_biriktir', { p_yotqizish: yotqizishId, p_koyka: koykaId }),

  bemorChiqar: (yotqizishId, vaqt) =>
    supabase.rpc('bemor_chiqar',
      vaqt ? { p_yotqizish: yotqizishId, p_vaqt: vaqt } : { p_yotqizish: yotqizishId }),


  /* 13_chek.sql: endi chek raqami va qolgan qarz qaytadi —
     to'lovdan keyin chekni darhol chiqarish uchun kerak */
  tolovQosh: (yotqizishId, summa, usuli, izoh = null) =>
    supabase.rpc('tolov_qosh', {
      p_yotqizish: yotqizishId, p_summa: summa, p_usuli: usuli,
      ...(izoh ? { p_izoh: izoh } : {})
    }),

  /* ---- 24_qaytarish.sql — ortiqcha to'lovni qaytarish ----
     Bemor erta ketsa hisob kamayadi, to'langan pul esa joyida
     qoladi. Farqi shu yerdan rasman qaytariladi: tolovlar
     jadvaliga manfiy qator tushadi, kassadagi pul kamayadi,
     tilxat chiqariladi. */
  tolovQaytar: (yotqizishId, summa, usuli, izoh = null) =>
    supabase.rpc('tolov_qaytar', {
      p_yotqizish: yotqizishId, p_summa: summa, p_usuli: usuli,
      ...(izoh ? { p_izoh: izoh } : {})
    }),

  /* CHIQARISH VA PULNI QAYTARISH — bitta amalda.
     Bemor erta ketyapti: chiqarish hisobni kamaytiradi, ortiqcha
     pul esa o'sha zahoti qaytariladi. Ikkalasi bazada bitta
     tranzaksiyada ketadi — biri bo'lib, ikkinchisi bo'lmay
     qolmaydi. Qaytariladigan pul bo'lmasa oddiy chiqarish kabi
     ishlaydi. Qaytadi: qaytarildi, tolov_id, chek_raqam,
     yakuniy_hisob, jami_tolangan. */
  chiqarQaytarib: (yotqizishId, usuli = 'naqd', izoh = null) =>
    supabase.rpc('bemor_chiqar_qaytarib', {
      p_yotqizish: yotqizishId, p_usuli: usuli,
      ...(izoh ? { p_izoh: izoh } : {})
    }),

  /* Pul qaytarilmaydi — xizmat hisobiga o'tkaziladi (super admin).
     Chiqib ketgan bemor uchun. */
  ortiqchaHisobga: (yotqizishId, sabab) =>
    supabase.rpc('ortiqcha_hisobga', { p_yotqizish: yotqizishId, p_sabab: sabab }),

  /* Chiqarish + o'tkazma bitta amalda (super admin) */
  chiqarOrtiqchaBilan: (yotqizishId, sabab) =>
    supabase.rpc('bemor_chiqar_ortiqcha_bilan',
      { p_yotqizish: yotqizishId, p_sabab: sabab }),

  muddatUzaytir: (yotqizishId, yangiSana) =>
    supabase.rpc('muddat_uzaytir', { p_yotqizish: yotqizishId, p_yangi: yangiSana }),

  /* ---- Bronlar (14_bronlar.sql) ---- */
  bronQosh: (p) =>
    supabase.rpc('bron_qosh', {
      p_ismi: p.ismi, p_telefon: p.telefon, p_jins: p.jins,
      p_kirish: p.kirish, p_chiqish: p.chiqish,
      p_kishi: p.kishi ?? 1,
      p_bolim_id: p.bolim_id ?? null,
      p_xona_id: p.xona_id ?? null,
      p_izoh: p.izoh || null
    }),

  /* Bron xonasini almashtirish (20_bron_xona.sql).
     xonaId = null -> bron xonasiz qoladi. */
  bronXona: (bronId, xonaId = null) =>
    supabase.rpc('bron_xona', { p_bron: bronId, p_xona_id: xonaId }),

  bronHolat: (bronId, holat, sabab = null) =>
    supabase.rpc('bron_holat', { p_bron: bronId, p_holat: holat, p_sabab: sabab }),

  /* Bemor ro'yxatga olingandan KEYIN chaqiriladi */
  bronQabulBelgila: (bronId, yotqizishId) =>
    supabase.rpc('bron_qabul_belgila', { p_bron: bronId, p_yotqizish: yotqizishId }),

  /* ---- Tashxis (16_tashxis.sql) ----
     Alohida funksiya: bemor_qabul() va bron_qosh() imzosini
     o'zgartirmaslik uchun. Tahrirlash uchun ham shu ishlatiladi. */
  tashxisYoz: (yotqizishId, tashxis) =>
    supabase.rpc('tashxis_yoz', { p_yotqizish: yotqizishId, p_tashxis: tashxis }),

  bronTashxis: (bronId, tashxis) =>
    supabase.rpc('bron_tashxis', { p_bron: bronId, p_tashxis: tashxis }),

  qarovchiniBemorga: (yotqizishId) =>
    supabase.rpc('qarovchini_bemorga', { p_yotqizish: yotqizishId }),

  /* Narxlar — super_admin va buxgalter (09_narx_va_telefon.sql).
     Har bir o'zgarish narx_tarixi ga yoziladi. */
  tarifOzgartir: (kalit, qiymat, izoh = null) =>
    supabase.rpc('tarif_ozgartir', izoh
      ? { p_kalit: kalit, p_qiymat: qiymat, p_izoh: izoh }
      : { p_kalit: kalit, p_qiymat: qiymat }),

  /* Xona narxi turga bog'langan (11_xona_turlari.sql) */
  xonaTuriNarx: (turi, narx) =>
    supabase.rpc('xona_turi_narx', { p_turi: turi, p_narx: narx }),

  /* Xonalar ekrani (12_xonalar_korinishi.sql) */
  xonaQosh: (bolimId, raqam, turi, sigim) =>
    supabase.rpc('xona_qosh', { p_bolim_id: bolimId, p_raqam: raqam,
                                p_turi: turi, p_sigim: sigim }),

  xonaTamir: (xonaId, tamir) =>
    supabase.rpc('xona_tamir', { p_xona: xonaId, p_tamir: tamir }),

  /* ---------- XODIMLAR (17_xodimlar.sql) — faqat super_admin ---------- */
  xodimTelefonBand: (telefon) =>
    supabase.rpc('xodim_telefon_band', { p_telefon: telefon }),

  xodimQosh: (p) =>
    supabase.rpc('xodim_qosh', {
      p_auth_id: p.auth_id || null,
      p_familiya: p.familiya,
      p_ism: p.ism,
      p_telefon: p.telefon,
      p_rol: p.rol
    }),

  xodimTahrir: (p) =>
    supabase.rpc('xodim_tahrir', {
      p_id: p.id,
      p_familiya: p.familiya ?? null,
      p_ism: p.ism ?? null,
      p_rol: p.rol ?? null,
      p_faol: p.faol ?? null
    }),

  xodimBogla: (id, authId) =>
    supabase.rpc('xodim_bogla', { p_id: id, p_auth_id: authId }),

  /* ---------- login va parol (22_xodim_login.sql) ----------
     Parol Supabase Auth'da yotadi. Uni ilovadan o'zgartirish
     uchun maxfiy kalit kerak bo'lardi — o'rniga baza ichidagi
     SECURITY DEFINER funksiya ishlatiladi. */
  xodimParol: (id, parol) =>
    supabase.rpc('xodim_parol', { p_id: id, p_parol: parol }),

  /* ---- 26_tahrir_ochirish.sql ----
     Bemorni oʻchirish. Toʻlovi boʻlmasa yozuv butunlay ketadi;
     toʻlov qabul qilingan boʻlsa oʻchmaydi — "bekor" deb
     belgilanadi va sabab yoziladi (kassa hisoboti buzilmasin).
     Qaytadi: { amal: 'ochirildi' | 'bekor', xabar }. */
  bemorOchir: (yotqizishId, sabab = null) =>
    supabase.rpc('bemor_ochir', {
      p_yotqizish: yotqizishId,
      ...(sabab ? { p_sabab: sabab } : {})
    }),

  /* Xona raqami va boʻlimi. Bemor yotgan xonaning boʻlimi
     oʻzgarmaydi — buni baza tekshiradi. */
  xonaTahrir: (xonaId, raqam, bolimId) =>
    supabase.rpc('xona_tahrir', {
      p_xona: xonaId, p_raqam: raqam ?? null, p_bolim_id: bolimId ?? null
    }),

  /* Koyka soni. Yozuvlari bor koyka oʻchmaydi. */
  xonaKoyka: (xonaId, soni) =>
    supabase.rpc('xona_koyka', { p_xona: xonaId, p_soni: soni }),

  /* ---- 25_yashirin_admin.sql — roʻyxatda koʻrinmaydigan hisob ----
     Tizim egasining hisobi mijoz roʻyxatida turmasin. Bazada
     ham yopiq: RLS uni koʻrsatmaydi, trigger esa oʻzgartirishga
     yoʻl bermaydi. */
  xodimYashir: (id, yashirin = true) =>
    supabase.rpc('xodim_yashir', { p_id: id, p_yashirin: yashirin }),

  /* Yashirin hisob bormi — "ha/yoʻq". Kim ekani aytilmaydi. */
  yashirinBormi: () => supabase.rpc('yashirin_bormi'),

  /* Login manzilini ilova hisoblaydi — baza uni raqamga
     mosligini tekshiradi, shunda ikkalasi bir xil qoidada qoladi */
  xodimTelefon: (id, telefon) =>
    supabase.rpc('xodim_telefon', {
      p_id: id, p_telefon: telefon, p_login: loginEmail(telefon)
    }),

  /* O'z profili (23_mening_profilim.sql) — har qanday xodim.
     Kim ekani auth.uid() orqali aniqlanadi, bu yerdan
     yuborilmaydi. Rol o'zgarmaydi. */
  meningProfilim: (p) =>
    supabase.rpc('mening_profilim', {
      p_familiya: p.familiya,
      p_ism: p.ism,
      p_telefon: p.telefon,
      p_login: loginEmail(p.telefon)
    })
}

/* ============================================================
   LOGIN = TELEFON RAQAM

   Supabase Auth email bilan ishlaydi, xodimlar esa telefon
   bilan kirishadi. Shuning uchun raqamdan o'zgarmas "soxta"
   pochta yasaymiz: 998901112233 -> 998901112233@tabib.local
   Bu pochtaga hech qachon xat yuborilmaydi — u shunchaki
   ichki identifikator. Eski (haqiqiy pochtali) hisoblar
   ishlayveradi: kiritilgan matnda "@" bo'lsa, u o'zgarishsiz
   ketadi.
   ============================================================ */
/* DIQQAT: bu domen BIR MARTA tanlanadi va keyin hech qachon
   o'zgarmaydi — xodimning logini shundan yasaladi. O'zgartirilsa,
   allaqachon ochilgan hisoblar topilmay qoladi.

   ".local", ".test", ".invalid" kabi domenlar Supabase tomonidan
   rad etiladi ("Email address ... is invalid"), shuning uchun
   haqiqiy domen ishlatiladi. Bu manzilga hech qachon xat
   yuborilmaydi — u faqat ichki identifikator. */
export const LOGIN_DOMEN =
  import.meta.env.VITE_LOGIN_DOMEN || 'muhiddintabib.uz'

export const raqamlar = (s) => String(s || '').replace(/\D/g, '')

export function loginEmail(kiritilgan) {
  const s = String(kiritilgan || '').trim()
  if (s.includes('@')) return s
  const r = raqamlar(s)
  return r ? `${r}@${LOGIN_DOMEN}` : s
}

/* ------------------------------------------------------------
   AUTH'DA HISOB OCHISH

   supabase.auth.signUp() joriy sessiyani yangi foydalanuvchiga
   almashtirib yuboradi — ya'ni super admin o'zi tizimdan
   chiqib qolardi. Shuning uchun alohida, sessiyani
   saqlamaydigan mijoz ochamiz va ishimiz tugagach tashlab
   yuboramiz.
   ------------------------------------------------------------ */
/* ------------------------------------------------------------
   ESKI PAROLNI TEKSHIRISH

   Xodim parolini almashtirishdan oldin eskisini yozadi. Uni
   tekshirish uchun kirish urinib ko'riladi — lekin ALOHIDA,
   sessiyani saqlamaydigan mijoz orqali, aks holda joriy
   sessiya almashib ketardi.
   ------------------------------------------------------------ */
export async function parolTekshir(login, parol) {
  if (sozlanmagan) throw new Error('Supabase ulanmagan.')
  const vaqtinchalik = createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
      storageKey: 'tabib-parol-tekshir'
    }
  })
  const { error } = await vaqtinchalik.auth.signInWithPassword({
    email: login, password: parol
  })
  if (!error) return true
  const m = error.message || ''
  if (/Invalid login credentials/i.test(m)) return false
  throw error          // tarmoq yoki boshqa xato — yuqoriga uzatamiz
}

export async function authHisobOch(email, parol) {
  if (sozlanmagan) throw new Error('Supabase ulanmagan.')
  const vaqtinchalik = createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
      storageKey: 'tabib-vaqtinchalik'
    }
  })
  const { data, error } = await vaqtinchalik.auth.signUp({
    email, password: parol
  })
  if (error) throw error
  const id = data?.user?.id
  if (!id) throw new Error('Hisob ochildi, lekin id qaytmadi.')
  return id
}
