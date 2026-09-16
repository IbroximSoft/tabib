-- ============================================================
--  tozalash.sql — SINOV MA'LUMOTLARINI O'CHIRISH
--
--  ⚠️  DIQQAT: BU FAYL MA'LUMOTLARNI QAYTARIB BO'LMAYDIGAN
--      QILIB O'CHIRADI. Faqat tizimni haqiqiy ishga
--      tushirishdan OLDIN, sinov yozuvlarini tozalash uchun.
--
--  O'CHIRILADI
--    · to'lovlar (cheklar va qaytarishlar bilan birga)
--    · bronlar
--    · yotqizishlar (kim qachon yotgani)
--    · bemorlar
--    · narx o'zgarishlari tarixi
--
--  QOLADI
--    · xodimlar va ularning login/parollari
--    · bo'limlar, xonalar, koykalar
--    · xona turlari va narxlar, kurs narxlari (tariflar)
--
--  Raqamlar ham noldan boshlanadi: keyingi bemor №1,
--  keyingi chek CHK-000001 bo'ladi.
--
--  QANDAY ISHGA TUSHIRILADI
--    Pastdagi SET qatoridagi izohni (--) olib tashlang va
--    butun faylni Supabase SQL Editor'da ishga tushiring.
--    Izoh olinmasa fayl ishlamaydi — tasodifan bosib
--    yuborilmasligi uchun shunday qilingan.
-- ============================================================

-- ⬇️  Tasdiq. Shu qatorning boshidagi "--" ni olib tashlang:
-- SET app.tozalash_tasdiq = 'HA_OCHIRAMAN';

-- ------------------------------------------------------------
-- 0. TASDIQ TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF COALESCE(current_setting('app.tozalash_tasdiq', true), '') <> 'HA_OCHIRAMAN' THEN
    RAISE EXCEPTION
      'Tasdiqlanmadi. Fayl boshidagi "SET app.tozalash_tasdiq = ''HA_OCHIRAMAN'';" qatorini oching va qaytadan ishga tushiring.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. O'CHIRISHDAN OLDINGI HOLAT
-- ------------------------------------------------------------
SELECT 'OLDIN'                AS "holat",
       (SELECT count(*) FROM bemorlar)     AS "bemorlar",
       (SELECT count(*) FROM yotqizishlar) AS "yotqizishlar",
       (SELECT count(*) FROM tolovlar)     AS "tolovlar",
       (SELECT count(*) FROM bronlar)      AS "bronlar",
       (SELECT count(*) FROM narx_tarixi)  AS "narx tarixi";

-- ------------------------------------------------------------
-- 2. O'CHIRISH
--    Tartib muhim: avval bola jadval, keyin ota — aks holda
--    tashqi kalit (foreign key) yo'l bermaydi.
-- ------------------------------------------------------------
DELETE FROM tolovlar;
DELETE FROM bronlar;
DELETE FROM yotqizishlar;
DELETE FROM bemorlar;
DELETE FROM narx_tarixi;

-- ------------------------------------------------------------
-- 3. RAQAMLARNI NOLDAN BOSHLASH
--    Keyingi bemor №1, keyingi chek CHK-000001.
--    Xodimlar, xonalar va bo'limlar raqamlariga tegilmaydi.
-- ------------------------------------------------------------
ALTER SEQUENCE bemorlar_id_seq     RESTART WITH 1;
ALTER SEQUENCE yotqizishlar_id_seq RESTART WITH 1;
ALTER SEQUENCE tolovlar_id_seq     RESTART WITH 1;
ALTER SEQUENCE bronlar_id_seq      RESTART WITH 1;
ALTER SEQUENCE narx_tarixi_id_seq  RESTART WITH 1;

-- ------------------------------------------------------------
-- 4. NATIJA — hammasi nol bo'lishi kerak
-- ------------------------------------------------------------
SELECT 'KEYIN'                AS "holat",
       (SELECT count(*) FROM bemorlar)     AS "bemorlar",
       (SELECT count(*) FROM yotqizishlar) AS "yotqizishlar",
       (SELECT count(*) FROM tolovlar)     AS "tolovlar",
       (SELECT count(*) FROM bronlar)      AS "bronlar",
       (SELECT count(*) FROM narx_tarixi)  AS "narx tarixi";

-- ------------------------------------------------------------
-- 5. SAQLANGANLAR — joyidami?
-- ------------------------------------------------------------
SELECT (SELECT count(*) FROM xodimlar) AS "xodimlar",
       (SELECT count(*) FROM bolimlar) AS "bo'limlar",
       (SELECT count(*) FROM xonalar)  AS "xonalar",
       (SELECT count(*) FROM koykalar) AS "koykalar",
       (SELECT count(*) FROM tariflar) AS "tariflar";

-- ------------------------------------------------------------
-- 6. TASDIQNI YOPAMIZ — tasodifan qayta ishlatilmasin
-- ------------------------------------------------------------
SET app.tozalash_tasdiq = '';
