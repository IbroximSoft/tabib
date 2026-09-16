-- ============================================================
--  27_bemor_malumotlari.sql — BEMORNING QO'SHIMCHA MA'LUMOTLARI
--  01, 03, 05, 06, 08..26 dan KEYIN. Idempotent.
--
--  Mijozning eski tizimida bemor kartasida otasining ismi,
--  manzili (viloyat/tuman/mahalla/ko'cha/uy/kvartira) va
--  tug'ilgan sanasi ham bo'lgan, bizda esa yo'q edi.
--
--  otasining_ismi va tugilgan_sana ustunlari BEMORLAR jadvalida
--  aslida 01_schema.sql dan beri bor edi (bemor_yoshi() ularni
--  hisobga oladi) — lekin hech qaysi ro'yxatga olish funksiyasi
--  ularni to'ldirmasdi va hech bir ko'rinish ularni ko'rsatmasdi.
--  Manzil ustunlari esa umuman yo'q edi — shu yerda qo'shiladi.
--
--  DIQQAT: bemor_qabul() va bemor_joylashtir() imzosiga
--  TEGILMAYDI (16_tashxis.sql dagi qoidaga ko'ra — ularga
--  parametr qo'shsak PostgREST "function is not unique" xatosini
--  beradi). Shuning uchun bu ma'lumotlar TASHXIS kabi alohida
--  funksiya bilan, ro'yxatga olingandan KEYIN yoziladi.
--
--  Xona turi (masalan "Lyuks") ham shu faylda v_yotqizishlar'ga
--  qo'shiladi — bemor kartasida "17-xona Lyuks" ko'rinishida
--  chiqishi uchun.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'bemor_ochir') THEN
    RAISE EXCEPTION 'Avval 26_tahrir_ochirish.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. MANZIL USTUNLARI
--    otasining_ismi va tugilgan_sana ALLAQACHON bor (01_schema.sql).
-- ------------------------------------------------------------
ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS viloyat    text;
ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS tuman      text;
ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS mahalla    text;
ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS kocha      text;
ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS uy_raqami  text;
ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS kvartira   text;

-- ------------------------------------------------------------
-- 2. YOZISH — tashxis_yoz() bilan bir xil qolipda: yotqizish_id
--    orqali chaqiriladi, ichida bemor_id topiladi. Bo'sh
--    qoldirilgan maydon ESKISINI o'chirmaydi (COALESCE+NULLIF) —
--    shu bilan bir necha marta, qisman ham to'ldirish mumkin.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bemor_malumot_yoz(
  p_yotqizish int,
  p_otasining_ismi text DEFAULT NULL,
  p_tugilgan_sana date DEFAULT NULL,
  p_viloyat text DEFAULT NULL,
  p_tuman text DEFAULT NULL,
  p_mahalla text DEFAULT NULL,
  p_kocha text DEFAULT NULL,
  p_uy_raqami text DEFAULT NULL,
  p_kvartira text DEFAULT NULL,
  p_fuqaroligi text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_bemor int;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bemor ma''lumotlarini yozish');

  SELECT bemor_id INTO v_bemor FROM yotqizishlar WHERE id = p_yotqizish;
  IF v_bemor IS NULL THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE bemorlar SET
    otasining_ismi = COALESCE(NULLIF(btrim(p_otasining_ismi), ''), otasining_ismi),
    tugilgan_sana  = COALESCE(p_tugilgan_sana, tugilgan_sana),
    viloyat        = COALESCE(NULLIF(btrim(p_viloyat), ''), viloyat),
    tuman          = COALESCE(NULLIF(btrim(p_tuman), ''), tuman),
    mahalla        = COALESCE(NULLIF(btrim(p_mahalla), ''), mahalla),
    kocha          = COALESCE(NULLIF(btrim(p_kocha), ''), kocha),
    uy_raqami      = COALESCE(NULLIF(btrim(p_uy_raqami), ''), uy_raqami),
    kvartira       = COALESCE(NULLIF(btrim(p_kvartira), ''), kvartira),
    fuqaroligi     = COALESCE(NULLIF(btrim(p_fuqaroligi), ''), fuqaroligi)
  WHERE id = v_bemor;
END $$;

-- ------------------------------------------------------------
-- 3. KO'RINISHGA QO'SHISH
--    v_yotqizishlar'ning yakuniy varianti endi SHU YERDA —
--    16_tashxis.sql dagi variantni bosib o'tadi (ustunlar
--    oxiriga qo'shiladi, eskilari o'zgarmaydi).
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_yotqizishlar;
CREATE VIEW v_yotqizishlar
WITH (security_invoker = on) AS
SELECT
  y.id AS yotqizish_id, b.id AS bemor_id,
  b.familiya, b.ism, b.familiya || ' ' || b.ism AS fish,
  b.jins, b.telefon, b.chet_el, b.fuqaroligi,
  bemor_yoshi(b) AS yosh,
  y.roli, y.holat,
  CASE y.holat WHEN 'yotmoqda' THEN 'Yotmoqda' WHEN 'chiqdi' THEN 'Chiqdi'
               ELSE 'Bekor qilingan' END AS holat_matn,
  bo.id AS bolim_id, bo.nomi AS bolim,
  x.id AS xona_id, x.raqam AS xona, x.turi AS xona_turi, k.raqam AS koyka,
  (y.koyka_id IS NOT NULL) AS xonada,
  y.kirish_sana, y.kirish_vaqt, y.reja_chiqish,
  (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date AS haqiqiy_chiqish,
  y.haqiqiy_chiqish AS haqiqiy_chiqish_vaqt,
  (COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, current_date)
     - y.kirish_sana + 1) AS yotgan_kun,
  CASE WHEN y.haqiqiy_chiqish IS NOT NULL
       THEN (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date - y.reja_chiqish
  END AS reja_farqi,
  y.summa AS bemor_summa,
  y.xona_summa,
  y.summa + y.xona_summa AS kurs_summa,
  hisob(y.id)            AS umumiy,
  tolangan(y.id)         AS tolangan,
  qarz(y.id)             AS qarz,
  (qarz(y.id) > 0)       AS qarzdor,
  y.band_davri, y.izoh,
  y.asosiy_id,
  ab.familiya || ' ' || ab.ism AS asosiy_fish,
  (SELECT count(*) FROM yotqizishlar h
    WHERE h.asosiy_id = y.id AND h.holat <> 'bekor') AS hamroh_soni,
  y.tashxis,
  -- ⭐ yangi — 27_bemor_malumotlari.sql
  b.otasining_ismi, b.tugilgan_sana,
  b.viloyat, b.tuman, b.mahalla, b.kocha, b.uy_raqami, b.kvartira
FROM yotqizishlar y
  JOIN bemorlar b        ON b.id = y.bemor_id
  LEFT JOIN koykalar k   ON k.id = y.koyka_id
  LEFT JOIN xonalar x    ON x.id = k.xona_id
  LEFT JOIN bolimlar bo  ON bo.id = x.bolim_id
  LEFT JOIN yotqizishlar ay ON ay.id = y.asosiy_id
  LEFT JOIN bemorlar ab  ON ab.id = ay.bemor_id;

CREATE OR REPLACE FUNCTION bemor_malumotlari_ornatildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 4. TEKSHIRUV
-- ------------------------------------------------------------
SELECT
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='bemorlar'
                        AND column_name='viloyat')
       THEN 'toʻgʻri' ELSE 'XATO' END AS "manzil ustunlari qoʻshildi",
  CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname='bemor_malumot_yoz')
       THEN 'toʻgʻri' ELSE 'XATO' END AS "bemor_malumot_yoz yaratildi",
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='v_yotqizishlar'
                        AND column_name='xona_turi')
       THEN 'toʻgʻri' ELSE 'XATO' END AS "v_yotqizishlar yangilandi";
