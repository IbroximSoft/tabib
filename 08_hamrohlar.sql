-- ============================================================
--  08_hamrohlar.sql — farzand va qarovchini bemorga biriktirish
--  01, 03, 05, 06 dan KEYIN ishga tushiriladi. Idempotent.
--
--  Muammo: farzand va qarovchi alohida-alohida kiritilardi va
--  ular qaysi bemorga tegishli ekani bazada qolmasdi. Aslida
--  yotqizishlar.asosiy_id maydoni bor edi, lekin hech kim uni
--  to'ldirmagan.
--
--  Nima qo'shiladi:
--   1. v_yotqizishlar ga asosiy_id, asosiy_fish, hamroh_soni
--   2. bemor_qabul() — bemor + hamrohlarini BITTA tranzaksiyada
--   3. qarovchini_bemorga() — qarovchi kunlik pulini to'lab,
--      yangi kurs bilan bemorga aylanadi
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
--   Fayllar tartib bilan ishga tushirilishi kerak. Biror
--   oldingisi qolib ketgan bo'lsa, tushunarli xabar beramiz.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.v_tasdiqlanmagan') IS NULL THEN
    RAISE EXCEPTION 'Avval 06_tuzatishlar.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- KEYINGI FAYL TEKSHIRUVI
--   10_kunlik_hisob.sql v_yotqizishlar va bemor_qabul() ni
--   YANGILAB beradi (kunlik hisob + majburiy xona). Agar u
--   allaqachon ishga tushgan bo'lsa, bu faylning eski
--   variantlari ularni bekor qilib qo'ymasligi kerak.
--   Shu sababli 1 va 2 bo'limlar shartli ishlaydi.
-- ------------------------------------------------------------
DO $chk$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='v_yotqizishlar'
                AND column_name='kurs_summa') THEN
    RAISE NOTICE '10_kunlik_hisob.sql allaqachon ishga tushirilgan — v_yotqizishlar va bemor_qabul() o''zgartirilmaydi.';
  END IF;
END $chk$;

-- ------------------------------------------------------------
-- 1. KO'RINISHGA BOG'LANISH USTUNLARI
-- ------------------------------------------------------------
DO $blok1$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='v_yotqizishlar'
              AND column_name='kurs_summa') THEN
  RETURN;   -- 10 yangiroq variantni bergan, tegmaymiz
END IF;

DROP VIEW IF EXISTS v_yotqizishlar;
EXECUTE $v$
CREATE VIEW v_yotqizishlar
WITH (security_invoker = on) AS
SELECT
  y.id                         AS yotqizish_id,
  b.id                         AS bemor_id,
  b.familiya, b.ism,
  b.familiya || ' ' || b.ism   AS fish,
  b.jins, b.telefon, b.chet_el, b.fuqaroligi,
  bemor_yoshi(b)               AS yosh,
  y.roli,
  y.holat,
  CASE y.holat
    WHEN 'yotmoqda' THEN 'Yotmoqda'
    WHEN 'chiqdi'   THEN 'Chiqdi'
    ELSE 'Bekor qilingan'
  END                          AS holat_matn,

  bo.id                        AS bolim_id,
  bo.nomi                      AS bolim,
  x.id                         AS xona_id,
  x.raqam                      AS xona,
  k.raqam                      AS koyka,
  (y.koyka_id IS NOT NULL)     AS xonada,

  y.kirish_sana, y.kirish_vaqt, y.reja_chiqish,
  (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date AS haqiqiy_chiqish,
  y.haqiqiy_chiqish            AS haqiqiy_chiqish_vaqt,
  (COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, current_date)
     - y.kirish_sana + 1)      AS yotgan_kun,
  CASE WHEN y.haqiqiy_chiqish IS NOT NULL
       THEN (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date - y.reja_chiqish
  END                          AS reja_farqi,

  y.summa                      AS bemor_summa,
  y.xona_summa,
  y.summa + y.xona_summa       AS umumiy,
  tolangan(y.id)               AS tolangan,
  qarz(y.id)                   AS qarz,
  (qarz(y.id) > 0)             AS qarzdor,
  y.band_davri,
  y.izoh,

  -- YANGI: kimga biriktirilgan / nechta hamrohi bor
  y.asosiy_id,
  ab.familiya || ' ' || ab.ism AS asosiy_fish,
  (SELECT count(*) FROM yotqizishlar h
    WHERE h.asosiy_id = y.id AND h.holat <> 'bekor') AS hamroh_soni
FROM yotqizishlar y
  JOIN bemorlar b        ON b.id = y.bemor_id
  LEFT JOIN koykalar k   ON k.id = y.koyka_id
  LEFT JOIN xonalar x    ON x.id = k.xona_id
  LEFT JOIN bolimlar bo  ON bo.id = x.bolim_id
  LEFT JOIN yotqizishlar ay ON ay.id = y.asosiy_id
  LEFT JOIN bemorlar ab  ON ab.id = ay.bemor_id
$v$;
END $blok1$;

-- ------------------------------------------------------------
-- 2. BEMOR + HAMROHLAR — bitta amalda
--    p_hamrohlar: [{roli, familiya, ism, jins, yosh, telefon,
--                   chet_el, koyka_id, bemor_id}, ...]
--    Biror hamroh o'tmasa, butun amal bekor bo'ladi —
--    yarim kiritilgan bemor qolmaydi.
-- ------------------------------------------------------------
DO $blok2$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='v_yotqizishlar'
              AND column_name='kurs_summa') THEN
  RETURN;   -- 10 majburiy xona qoidasini qo'shgan, tegmaymiz
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION bemor_qabul(
  p_familiya text, p_ism text, p_jins jins_turi, p_telefon text,
  p_yosh int, p_chet_el boolean,
  p_koyka int, p_kirish date, p_reja_chiqish date,
  p_oldindan numeric DEFAULT 0,
  p_bemor_id int DEFAULT NULL,
  p_hamrohlar jsonb DEFAULT '[]'::jsonb
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_asosiy int;
  h jsonb;
  v_roli shaxs_roli;
BEGIN
  -- asosiy bemor
  v_asosiy := bemor_joylashtir(
    p_familiya, p_ism, p_jins, p_telefon, p_yosh, p_chet_el, 'bemor'::shaxs_roli,
    p_koyka, p_kirish, p_reja_chiqish, p_oldindan, NULL, p_bemor_id);

  -- hamrohlar
  FOR h IN SELECT * FROM jsonb_array_elements(COALESCE(p_hamrohlar, '[]'::jsonb))
  LOOP
    v_roli := (h->>'roli')::shaxs_roli;
    IF v_roli = 'bemor' THEN
      RAISE EXCEPTION 'Hamroh faqat farzand yoki qarovchi boʻlishi mumkin.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF COALESCE(h->>'familiya','') = '' OR COALESCE(h->>'ism','') = '' THEN
      RAISE EXCEPTION 'Hamrohning familiyasi va ismi kiritilmagan.'
        USING ERRCODE = 'check_violation';
    END IF;

    PERFORM bemor_joylashtir(
      h->>'familiya',
      h->>'ism',
      (h->>'jins')::jins_turi,
      COALESCE(NULLIF(h->>'telefon',''), p_telefon),
      NULLIF(h->>'yosh','')::int,
      COALESCE((h->>'chet_el')::boolean, false),
      v_roli,
      NULLIF(h->>'koyka_id','')::int,
      p_kirish,
      p_reja_chiqish,
      0,
      v_asosiy,                       -- ⭐ asosiy bemorga biriktiriladi
      NULLIF(h->>'bemor_id','')::int);
  END LOOP;

  RETURN v_asosiy;
END $$
$f$;
END $blok2$;

-- ------------------------------------------------------------
-- 3. QAROVCHI → BEMOR
--    Qarovchi yotgan kunlari uchun kunlik hisobda to'laydi,
--    so'ng bugundan yangi kurs boshlanadi.
--
--    Eski versiya RLS ostida ishlamasdi (huquq tekshiruvi ham,
--    SECURITY DEFINER ham yo'q edi) va reja sanasini
--    yangilamasdi — ya'ni to'liq kursga to'lab, 2 kun yotib
--    chiqib ketishi mumkin edi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS qarovchini_bemorga(int);
DROP FUNCTION IF EXISTS qarovchini_bemorga(int, date);

CREATE FUNCTION qarovchini_bemorga(p_yotqizish int, p_yangi_chiqish date DEFAULT NULL)
RETURNS TABLE (
  qarovchi_kuni   int,
  qarovchi_puli   numeric,
  bemor_puli      numeric,
  yangi_summa     numeric,
  yangi_reja      date
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_kun int; v_yosh int; v_chet boolean;
  v_kurs numeric; v_qarovchi numeric;
  v_saqlangan numeric; v_yangi numeric; v_reja date;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'qarovchini bemorga aylantirish');

  SELECT (current_date - y.kirish_sana + 1), bemor_yoshi(b), b.chet_el
    INTO v_kun, v_yosh, v_chet
  FROM yotqizishlar y JOIN bemorlar b ON b.id = y.bemor_id
  WHERE y.id = p_yotqizish AND y.roli = 'qarovchi' AND y.holat = 'yotmoqda';

  IF v_kun IS NULL THEN
    RAISE EXCEPTION 'Bu yozuv qarovchi emas yoki allaqachon chiqarilgan.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT qiymat INTO v_kurs     FROM tariflar WHERE kalit = 'kurs_kun';
  SELECT qiymat INTO v_qarovchi FROM tariflar WHERE kalit = 'qarovchi';

  -- qarovchi sifatida yotgan kunlar uchun kunlik to'lov
  v_saqlangan := round(v_qarovchi / NULLIF(v_kurs,0) * v_kun);
  -- bugundan boshlanadigan yangi kurs
  v_yangi := narx_hisobla(v_yosh, v_chet, 'bemor'::shaxs_roli);
  v_reja  := COALESCE(p_yangi_chiqish, current_date + v_kurs::int);

  UPDATE yotqizishlar
     SET roli = 'bemor',
         summa = v_saqlangan + v_yangi,
         reja_chiqish = v_reja,
         izoh = COALESCE(izoh || ' | ', '') ||
                format('Qarovchi → Bemor (%s kun qarovchi: %s soʻm). Kim: %s',
                       v_kun, to_char(v_saqlangan, 'FM999G999G999'), joriy_fish())
   WHERE id = p_yotqizish;

  RETURN QUERY SELECT v_kun, v_saqlangan, v_yangi, v_saqlangan + v_yangi, v_reja;
END $$;

-- ------------------------------------------------------------
-- 4. Bemorning hamrohlari (karta uchun)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION hamrohlar(p_yotqizish int)
RETURNS TABLE (
  yotqizish_id int, fish text, roli shaxs_roli, jins jins_turi,
  yosh int, xona text, koyka smallint, holat yotqizish_holati, summa numeric
) LANGUAGE sql STABLE AS $$
  SELECT y.id, b.familiya || ' ' || b.ism, y.roli, b.jins, bemor_yoshi(b),
         x.raqam, k.raqam, y.holat, y.summa + y.xona_summa
  FROM yotqizishlar y
    JOIN bemorlar b ON b.id = y.bemor_id
    LEFT JOIN koykalar k ON k.id = y.koyka_id
    LEFT JOIN xonalar x  ON x.id = k.xona_id
  WHERE y.asosiy_id = p_yotqizish AND y.holat <> 'bekor'
  ORDER BY y.roli, b.familiya;
$$;

-- anon uchun yopiq qolsin (06 dagi qoida yangi obyektlarga ham)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;
