-- ============================================================
--  16_tashxis.sql — kasallik tashxisi
--  01, 03, 05, 06, 08..15 dan KEYIN. Idempotent.
--
--  Tashxis qog'ozdagi kasallik varaqasida bor edi, lekin tizimda
--  saqlanmasdi — karta chiqarilganda uni qo'lda yozishga to'g'ri
--  kelardi. Endi ro'yxatga olishda ham, bronda ham kiritiladi va
--  kartaga bosib chiqadi.
--
--  DIQQAT: bemor_qabul() va bron_qosh() imzosiga TEGILMAYDI.
--  Ularga parametr qo'shsak, eski imzo bilan birga ikkita bir xil
--  nomli funksiya qolib, PostgREST "function is not unique"
--  xatosini beradi (bu zanjirda allaqachon bir marta bo'lgan).
--  Shuning uchun tashxis alohida funksiya bilan yoziladi —
--  keyinchalik uni tahrirlash uchun ham shu funksiya kerak.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'hisobot_xulosa') THEN
    RAISE EXCEPTION 'Avval 15_hisobotlar.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. USTUNLAR
-- ------------------------------------------------------------
ALTER TABLE yotqizishlar ADD COLUMN IF NOT EXISTS tashxis text;
ALTER TABLE bronlar      ADD COLUMN IF NOT EXISTS tashxis text;

-- ------------------------------------------------------------
-- 2. TASHXISNI YOZISH / TAHRIRLASH
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION tashxis_yoz(p_yotqizish int, p_tashxis text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_yangi text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'tashxis yozish');

  v_yangi := NULLIF(trim(COALESCE(p_tashxis, '')), '');

  UPDATE yotqizishlar SET tashxis = v_yangi WHERE id = p_yotqizish;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_yangi;
END $$;

CREATE OR REPLACE FUNCTION bron_tashxis(p_bron int, p_tashxis text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_yangi text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bronga tashxis yozish');

  v_yangi := NULLIF(trim(COALESCE(p_tashxis, '')), '');

  UPDATE bronlar SET tashxis = v_yangi WHERE id = p_bron;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bron topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_yangi;
END $$;

-- ------------------------------------------------------------
-- 3. KO'RINISHLARGA TASHXIS
--    v_yotqizishlar 10 da, v_bronlar 14 da yaratilgan. Ularning
--    yakuniy varianti endi SHU YERDA — 10 va 14 fayllari bu
--    fayl ishga tushgan bazada o'sha bo'limlarni o'tkazib
--    yuboradi (ichida shartli blok bor).
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
  x.id AS xona_id, x.raqam AS xona, k.raqam AS koyka,
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
  y.tashxis                                          -- ⭐ yangi
FROM yotqizishlar y
  JOIN bemorlar b        ON b.id = y.bemor_id
  LEFT JOIN koykalar k   ON k.id = y.koyka_id
  LEFT JOIN xonalar x    ON x.id = k.xona_id
  LEFT JOIN bolimlar bo  ON bo.id = x.bolim_id
  LEFT JOIN yotqizishlar ay ON ay.id = y.asosiy_id
  LEFT JOIN bemorlar ab  ON ab.id = ay.bemor_id;

DROP VIEW IF EXISTS v_bronlar CASCADE;
CREATE VIEW v_bronlar
WITH (security_invoker = on) AS
SELECT
  br.id                AS bron_id,
  br.ismi, br.telefon, br.jins,
  br.bemor_id,
  br.yotqizish_id,
  br.bolim_id,
  bo.nomi              AS bolim,
  bo.jins              AS bolim_jinsi,
  br.xona_id,
  x.raqam              AS xona,
  x.turi               AS xona_turi,
  br.kirish, br.chiqish,
  (br.chiqish - br.kirish)              AS kun,
  (br.kirish - current_date)            AS qolgan_kun,
  br.kishi, br.guruh, br.izoh, br.kim,
  br.yaratilgan,
  br.holat,
  CASE
    WHEN br.holat = 'qabul_qilindi' THEN 'qabul'
    WHEN br.holat = 'kelmadi'       THEN 'kelmadi'
    WHEN br.holat = 'bekor'         THEN 'bekor'
    WHEN br.kirish <  current_date  THEN 'kechikkan'
    WHEN br.kirish =  current_date  THEN 'bugun'
    ELSE 'kutilmoqda'
  END                                   AS holat_matn,
  (SELECT count(*) FROM yotqizishlar y
     JOIN koykalar k ON k.id = y.koyka_id
    WHERE br.xona_id IS NOT NULL
      AND k.xona_id = br.xona_id
      AND y.holat = 'yotmoqda'
      AND y.band_davri && daterange(br.kirish,
            GREATEST(br.kirish + 1, br.chiqish), '[)'))  AS toqnashuv,
  br.tashxis                                             -- ⭐ yangi
FROM bronlar br
  LEFT JOIN bolimlar bo ON bo.id = br.bolim_id
  LEFT JOIN xonalar x   ON x.id = br.xona_id;

-- ------------------------------------------------------------
-- 4. HISOBOTGA HAM TASHXIS
--    Ustun oxiriga qo'shiladi — CREATE OR REPLACE shunga ruxsat
--    beradi, o'rtaga qo'shishga esa yo'q.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS hisobot_bemorlar(date, date);

CREATE FUNCTION hisobot_bemorlar(p_dan date, p_gacha date)
RETURNS TABLE (
  yotqizish_id int, fish text, telefon text, jins jins_turi,
  roli shaxs_roli, bolim text, xona text,
  kirish_sana date, reja_chiqish date, haqiqiy_chiqish date,
  yotgan_kun int, holat yotqizish_holati,
  kurs_summa numeric, umumiy numeric, tolangan numeric, qarz numeric,
  ortiqcha numeric, tashxis text
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    y.id,
    b.familiya || ' ' || b.ism,
    b.telefon, b.jins, y.roli,
    COALESCE(bo.nomi, '—'),
    COALESCE(x.raqam, '—'),
    y.kirish_sana, y.reja_chiqish,
    (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
    (COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, current_date)
       - y.kirish_sana + 1),
    y.holat,
    y.summa + y.xona_summa,
    hisob(y.id), tolangan(y.id), qarz(y.id),
    -- Ortiqcha to'lov faqat CHIQIB KETGAN bemorda ma'noga ega:
    -- yotgan bemorning oldindan to'lagani "ortiqcha" emas.
    -- (Bu ifoda 24_qaytarish.sql dagi bilan bir xil bo'lishi shart.)
    CASE WHEN y.haqiqiy_chiqish IS NULL THEN 0::numeric ELSE GREATEST(0, tolangan(y.id) - hisob(y.id)) END,
    y.tashxis
  FROM yotqizishlar y
    JOIN bemorlar b       ON b.id = y.bemor_id
    LEFT JOIN koykalar k  ON k.id = y.koyka_id
    LEFT JOIN xonalar x   ON x.id = k.xona_id
    LEFT JOIN bolimlar bo ON bo.id = x.bolim_id
  WHERE y.holat <> 'bekor'
    AND y.kirish_sana <= p_gacha
    AND COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                 y.reja_chiqish) >= p_dan
  ORDER BY y.kirish_sana DESC, b.familiya;
$$;

-- ------------------------------------------------------------
-- 5. BRON QABUL QILINGANDA TASHXIS BEMORGA O'TSIN
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bron_qabul_belgila(p_bron int, p_yotqizish int)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_bemor int; v_tashxis text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bronni qabul qilish');

  SELECT bemor_id INTO v_bemor FROM yotqizishlar WHERE id = p_yotqizish;
  IF v_bemor IS NULL THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT tashxis INTO v_tashxis FROM bronlar WHERE id = p_bron;

  UPDATE bronlar
     SET holat = 'qabul_qilindi',
         bemor_id = v_bemor,
         yotqizish_id = p_yotqizish,
         izoh = COALESCE(izoh || ' | ', '') ||
                format('Qabul qilindi %s. Kim: %s',
                       to_char(current_date, 'DD.MM.YYYY'), joriy_fish())
   WHERE id = p_bron AND holat <> 'qabul_qilindi';

  -- bronda tashxis bo'lsa va bemorda hali yo'q bo'lsa — ko'chiramiz
  IF v_tashxis IS NOT NULL THEN
    UPDATE yotqizishlar SET tashxis = v_tashxis
     WHERE id = p_yotqizish AND tashxis IS NULL;
  END IF;

  RETURN FOUND;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;
