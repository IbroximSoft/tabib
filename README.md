# Muhiddin Tabib — boshqaruv tizimi

Tabib statsionari uchun boshqaruv tizimi: bemorlarni qabul qilish, xonaga
joylashtirish, to'lov va chek, ovqat hisobi, bronlar va hisobotlar.

**React + Vite + Supabase.** Muhim qoida: barcha biznes mantiq **bazada**
(RLS, triggerlar va `SECURITY DEFINER` funksiyalar). Frontend faqat chaqiradi —
shuning uchun brauzerdagi kodni o'zgartirib hech kim huquqidan ortiqchasini
qila olmaydi.

---

## 1. Bazani tayyorlash

Supabase loyihasida **SQL Editor** ni ochib, fayllarni **shu tartibda** ishga
tushiring. Har bir fayl idempotent — qayta ishga tushirsa ham hech narsa
buzilmaydi.

| # | Fayl | Nima qo'shadi |
|---|---|---|
| 01 | `01_schema.sql` | jadvallar, cheklovlar, triggerlar |
| 03 | `03_rollar.sql` | rollar, huquqlar, chek, xonasiz bemor |
| 05 | `05_hisobotlar.sql` | hisobot va filtr ko'rinishlari |
| 06 | `06_tuzatishlar.sql` | to'plangan tuzatishlar |
| 08 | `08_hamrohlar.sql` | qarovchi va farzand (hamrohlar) |
| 09 | `09_narx_va_telefon.sql` | narxlar boshqaruvi, telefon formati |
| 10 | `10_kunlik_hisob.sql` | erta ketganda kunlik qayta hisob |
| 11 | `11_xona_turlari.sql` | xona turlari va ular bo'yicha narx |
| 12 | `12_xonalar_korinishi.sql` | xonalar/koykalar ekrani uchun ko'rinishlar |
| 13 | `13_chek.sql` | chek raqami va chek ma'lumoti |
| 14 | `14_bronlar.sql` | bronlar, bo'sh joy hisobi |
| 15 | `15_hisobotlar.sql` | xulosa, bemorlar, **ovqat hisobi**, bronlar |
| 16 | `16_tashxis.sql` | tashxis maydoni |
| 17 | `17_xodimlar.sql` | xodim profillari, telefon = login |
| 18 | `18_buxgalter.sql` | buxgalter huquqlarini toraytirish |
| 19 | `19_bron_bogla.sql` | bron bilan yangi bemorni bog'lash |
| 20 | `20_bron_xona.sql` | bronning xonasini almashtirish |
| 21 | `21_registrator.sql` | registratordan pulni yopish |
| 22 | `22_xodim_login.sql` | login va parolni tizim ichidan o'zgartirish |
| 23 | `23_mening_profilim.sql` | xodim o'z profilini tahrirlashi |
| 24 | `24_qaytarish.sql` | **ortiqcha to'lovni qaytarish (vozvrat)** |
| 25 | `25_yashirin_admin.sql` | "Admin" roli va ro'yxatda ko'rinmaydigan hisob |

Tekshirish uchun: **`07_tekshirish.sql`**. U qaysi fayl ishga tushgan-tushmaganini
va tizim holatini ko'rsatadi. Hammasi joyida bo'lsa **22 ta OK** chiqadi.

Supabase'da bir marta bajariladigan ikki sozlama:

```sql
create extension if not exists pgcrypto with schema extensions;
```

va **Authentication → Providers → Email → "Confirm email" O'CHIQ** bo'lishi shart
(login uchun soxta pochta ishlatiladi, tasdiqlash xati hech qayerga bormaydi).

Xonalarni kiritish:

```sql
select xona_yarat('Erkaklar bo''limi', '12', 'Standart', 3, 3000000);
select xona_yarat('Ayollar bo''limi',  '15', 'Standart', 2, 3000000);
```

## 2. Birinchi hisob

Supabase → **Authentication → Users → Add user** orqali foydalanuvchi oching
(email o'rnida `998901234567@muhiddintabib.uz` ko'rinishidagi manzil), so'ng:

```sql
insert into xodimlar (auth_id, familiya, ism, telefon, rol, faol)
values ('<User UID>', 'Karimov', 'Ibrohim', '+998901234567', 'super_admin', true);
```

Keyingi xodimlar ilova ichida ochiladi: **Sozlamalar → Xodimlar → + Yangi profil**.

Rollar: `super_admin` (ekranda **Admin**), `administrator` (**Registrator**),
`buxgalter`, `viewer` (**Kuzatuvchi**).

## 3. Kompyuterda ishga tushirish

```bash
npm install
cp .env.example .env      # keyin .env ichini to'ldiring
npm run dev
```

## 4. Internetga chiqarish (Cloudflare Pages)

1. Repozitoriyni GitHub'ga yuklang.
2. Cloudflare → **Workers & Pages → Create → Pages → Connect to Git** → shu repo.
3. Sozlamalar:
   - Framework preset: **Vite**
   - Build command: `npm run build`
   - Build output directory: `dist`
4. **Settings → Environment variables** ga qo'shing (`.env` git'ga tushmaydi):
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
   - `VITE_LOGIN_DOMEN`
5. Deploy. Shundan keyin har bir `git push` avtomatik yangi versiyani chiqaradi.

`public/_redirects` fayli SPA yo'llari uchun kerak (`/bemorlar` kabi manzil
to'g'ridan-to'g'ri ochilsin) — uni o'chirmang.

## 5. Xavfsizlik va zaxira

- `VITE_SUPABASE_ANON_KEY` ilova ichida bo'lishi **normal** — himoya RLS'da.
  `service_role` kaliti esa **hech qachon** frontendga tushmasligi kerak.
- `VITE_LOGIN_DOMEN` **bir marta** tanlanadi. Keyin o'zgartirilsa, barcha
  xodimlarning login manzili buziladi va hech kim tizimga kira olmaydi.
- Bepul Supabase tarifida avtomatik zaxira nusxa **yo'q**. Bemor va pul
  ma'lumoti uchun zaxirani albatta yo'lga qo'ying (Supabase Pro yoki kunlik
  `pg_dump`).

## Papkalar

```
src/
  lib/supabase.js   baza bilan ishlash: db (o'qish) va amal (yozish)
  lib/auth.jsx      sessiya, rol va huquq tekshiruvi, rol nomlari
  components/       Layout, Modal, Profil, Kutish
  pages/            ekranlar: Dashboard, Bemorlar, Xonalar, Bronlar,
                    To'lovlar, Hisobotlar, Sozlamalar, Login
  print/            chek (80 mm lenta) va kasallik kartasi (A4)
  styles.css        dizayn tizimi — ranglar o'zgaruvchilarda
*.sql               baza migratsiyalari (yuqoridagi jadval)
```

## Kelishilgan qoidalar

- `styles.css` ga faqat **qo'shiladi**, mavjud qoidalar o'zgartirilmaydi.
- Har bir SQL fayl idempotent va o'zidan oldingi faylni tekshiradi.
- Keyingi fayl oldingisining ishini bosib ketmasligi uchun "supersede"
  himoyasi ishlatiladi (masalan 17 → 25, 22 → 25, 10/15 → 24).
