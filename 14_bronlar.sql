-- ============================================================
--  14_bronlar.sql — oldindan joy band qilish
--  01, 03, 05, 06, 08..13 dan KEYIN. Idempotent.
--
--  Mijoz qoidasi: xonaga joylashmagan bemor QARZDOR BO'LMAYDI.
--  Kelishi rejalashtirilgan odam bemor emas — u BRON.
--  Bron hech qanday pul hisoblamaydi; bemor kelib xonaga
--  joylashganda qarz shundan boshlanadi.
--
--  Nima qo'shiladi:
--   1. bronlar ga jins va yotqizish_id (qabul qilingach bog'lanadi)
--   2. v_bronlar — ro'yxat uchun, holati hisoblangan holda
--   3. bron_bosh_joylar() — tanlangan sanalarda qaysi xonada joy bor
--   4. bron_qosh() / bron_holat() / bron_qabul_belgila()
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'tolov_qosh' AND p.pronargs = 5) THEN
    RAISE EXCEPTION 'Avval 13_chek.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. JADVALGA QO'SHIMCHA USTUNLAR
--    jins        — xona taklifini jinsga qarab filtrlash uchun
--    yotqizish_id — bron qabul qilingach qaysi yozuvga aylangani
-- ------------------------------------------------------------
ALTER TABLE bronlar ADD COLUMN IF NOT EXISTS jins jins_turi;
ALTER TABLE bronlar ADD COLUMN IF NOT EXISTS yotqizish_id integer
  REFERENCES yotqizishlar(id);
ALTER TABLE bronlar ADD COLUMN IF NOT EXISTS kim text;

CREATE INDEX IF NOT EXISTS idx_bronlar_holat ON bronlar (holat, kirish);

-- Bron davri — kesishishni tekshirishda ishlatiladi
CREATE OR REPLACE FUNCTION bron_davri(p bronlar) RETURNS daterange
LANGUAGE sql IMMUTABLE AS $$
  SELECT daterange(p.kirish, GREATEST(p.kirish + 1, p.chiqish), '[)')
$$;

-- ------------------------------------------------------------
-- 2. BRONLAR RO'YXATI
--    holat_matn — ekranda ko'rinadigan holat. "kutilmoqda" ning
--    o'zi yetarli emas: kelishi kerak bo'lgan kun o'tib ketgan
--    bron alohida ko'rinishi kerak, aks holda ro'yxat ifloslanadi.
-- ------------------------------------------------------------
-- DIQQAT: 16_tashxis.sql bu ko'rinishga "tashxis" ustunini qo'shadi.
-- U ishga tushgan bazada bu yerdagi variant uni bosib ketmasin.
DO $blokb$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='bronlar'
              AND column_name='tashxis') THEN
  RAISE NOTICE '16_tashxis.sql ishga tushgan — v_bronlar o''zgartirilmaydi.';
  RETURN;
END IF;
DROP VIEW IF EXISTS v_bronlar CASCADE;
EXECUTE $v$
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
  -- Band qilingan xona bron kuniga bo'shaydimi?
  (SELECT count(*) FROM yotqizishlar y
     JOIN koykalar k ON k.id = y.koyka_id
    WHERE br.xona_id IS NOT NULL
      AND k.xona_id = br.xona_id
      AND y.holat = 'yotmoqda'
      AND y.band_davri && daterange(br.kirish,
            GREATEST(br.kirish + 1, br.chiqish), '[)'))  AS toqnashuv
FROM bronlar br
  LEFT JOIN bolimlar bo ON bo.id = br.bolim_id
  LEFT JOIN xonalar x   ON x.id = br.xona_id
$v$;
END $blokb$;

-- ------------------------------------------------------------
-- 3. TANLANGAN SANALARDA BO'SH JOYLAR
--    Kelajakdagi sana uchun "hozir bo'sh" degani yetarli emas —
--    o'sha oraliqda kim yotishi va boshqa bronlar ham hisobga
--    olinadi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bron_bosh_joylar(
  p_kirish date, p_chiqish date, p_jins jins_turi DEFAULT NULL,
  p_bron int DEFAULT NULL          -- tahrirlanayotgan bron o'zini band qilmasin
) RETURNS TABLE (
  xona_id int, xona text, turi text, narx numeric,
  bolim_id int, bolim text, bolim_jinsi bolim_jinsi,
  sigim bigint, band bigint, bron_band bigint, bosh bigint
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  WITH oraliq AS (
    SELECT daterange(p_kirish, GREATEST(p_kirish + 1, p_chiqish), '[)') AS d
  )
  SELECT
    x.id, x.raqam, x.turi, COALESCE(t.narx, x.narx, 0),
    bo.id, bo.nomi, bo.jins,
    count(DISTINCT k.id)                                   AS sigim,
    (SELECT count(DISTINCT y.koyka_id)
       FROM yotqizishlar y JOIN koykalar k2 ON k2.id = y.koyka_id, oraliq o
      WHERE k2.xona_id = x.id AND y.holat = 'yotmoqda'
        AND y.band_davri && o.d)                           AS band,
    COALESCE((SELECT sum(br.kishi)
       FROM bronlar br, oraliq o
      WHERE br.xona_id = x.id AND br.holat = 'kutilmoqda'
        AND (p_bron IS NULL OR br.id <> p_bron)
        AND daterange(br.kirish, GREATEST(br.kirish + 1, br.chiqish), '[)') && o.d), 0)
                                                           AS bron_band,
    GREATEST(0, count(DISTINCT k.id)
      - (SELECT count(DISTINCT y.koyka_id)
           FROM yotqizishlar y JOIN koykalar k2 ON k2.id = y.koyka_id, oraliq o
          WHERE k2.xona_id = x.id AND y.holat = 'yotmoqda'
            AND y.band_davri && o.d)
      - COALESCE((SELECT sum(br.kishi)
           FROM bronlar br, oraliq o
          WHERE br.xona_id = x.id AND br.holat = 'kutilmoqda'
            AND (p_bron IS NULL OR br.id <> p_bron)
            AND daterange(br.kirish, GREATEST(br.kirish + 1, br.chiqish), '[)') && o.d), 0)
    )                                                      AS bosh
  FROM xonalar x
    JOIN bolimlar bo ON bo.id = x.bolim_id
    LEFT JOIN xona_turlari t ON t.nomi = x.turi
    LEFT JOIN koykalar k ON k.xona_id = x.id
  WHERE NOT x.tamirlashda
    AND (p_jins IS NULL OR bo.jins = 'aralash' OR bo.jins::text = p_jins::text)
  GROUP BY x.id, x.raqam, x.turi, t.narx, x.narx, bo.id, bo.nomi, bo.jins, bo.tartib
  ORDER BY bo.tartib, x.raqam;
$$;

-- ------------------------------------------------------------
-- 4. BRON QO'SHISH
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bron_qosh(text, text, jins_turi, date, date, int, int, int, text);

CREATE FUNCTION bron_qosh(
  p_ismi     text,
  p_telefon  text,
  p_jins     jins_turi,
  p_kirish   date,
  p_chiqish  date,
  p_kishi    int  DEFAULT 1,
  p_bolim_id int  DEFAULT NULL,
  p_xona_id  int  DEFAULT NULL,
  p_izoh     text DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_id int; v_bosh bigint; v_raqam text; v_bolim_jinsi bolim_jinsi;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bron qoʻshish');

  IF COALESCE(trim(p_ismi), '') = '' THEN
    RAISE EXCEPTION 'Ism-familiyani kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(regexp_replace(COALESCE(p_telefon,''), '\D', '', 'g')) < 9 THEN
    RAISE EXCEPTION 'Telefon raqamini toʻliq kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_kirish IS NULL OR p_chiqish IS NULL OR p_chiqish <= p_kirish THEN
    RAISE EXCEPTION 'Chiqish sanasi kirish sanasidan keyin boʻlishi kerak.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_kirish < current_date THEN
    RAISE EXCEPTION 'Bron oʻtgan sanaga qoʻyilmaydi.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_kishi IS NULL OR p_kishi < 1 OR p_kishi > 20 THEN
    RAISE EXCEPTION 'Kishilar soni 1 dan 20 gacha boʻlishi kerak.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Xona tanlangan bo'lsa: jinsi mos keladimi va joy yetadimi
  IF p_xona_id IS NOT NULL THEN
    SELECT x.raqam, bo.jins INTO v_raqam, v_bolim_jinsi
    FROM xonalar x JOIN bolimlar bo ON bo.id = x.bolim_id
    WHERE x.id = p_xona_id;

    IF v_raqam IS NULL THEN
      RAISE EXCEPTION 'Xona topilmadi.' USING ERRCODE = 'check_violation';
    END IF;
    IF p_jins IS NOT NULL AND v_bolim_jinsi <> 'aralash'
       AND v_bolim_jinsi::text <> p_jins::text THEN
      RAISE EXCEPTION '%-xona boshqa jins boʻlimida — bu bemorga mos kelmaydi.', v_raqam
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT bosh INTO v_bosh
    FROM bron_bosh_joylar(p_kirish, p_chiqish, NULL) WHERE xona_id = p_xona_id;

    IF COALESCE(v_bosh, 0) < p_kishi THEN
      RAISE EXCEPTION '%-xonada % kuni % ta joy yoʻq (boʻsh: %). Boshqa xona tanlang yoki xonasiz bron qoʻying.',
        v_raqam, to_char(p_kirish, 'DD.MM.YYYY'), p_kishi, COALESCE(v_bosh, 0)
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  INSERT INTO bronlar (ismi, telefon, jins, bolim_id, xona_id,
                       kirish, chiqish, kishi, izoh, kim)
  VALUES (trim(p_ismi), trim(p_telefon), p_jins, p_bolim_id, p_xona_id,
          p_kirish, p_chiqish, p_kishi, NULLIF(trim(COALESCE(p_izoh,'')), ''),
          joriy_fish())
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

-- ------------------------------------------------------------
-- 5. BRON HOLATINI O'ZGARTIRISH — bekor qilish / kelmadi
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bron_holat(
  p_bron int, p_holat bron_holati, p_sabab text DEFAULT NULL
) RETURNS bron_holati LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_eski bron_holati;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bron holatini oʻzgartirish');

  SELECT holat INTO v_eski FROM bronlar WHERE id = p_bron;
  IF v_eski IS NULL THEN
    RAISE EXCEPTION 'Bron topilmadi.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_eski = 'qabul_qilindi' THEN
    RAISE EXCEPTION 'Bu bron allaqachon qabul qilingan — holatini oʻzgartirib boʻlmaydi.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_holat = 'qabul_qilindi' THEN
    RAISE EXCEPTION 'Qabul qilish bemorni roʻyxatga olish orqali boʻladi.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE bronlar
     SET holat = p_holat,
         izoh = COALESCE(izoh || ' | ', '') ||
                format('%s: %s. Kim: %s',
                       CASE p_holat WHEN 'bekor' THEN 'Bekor qilindi'
                                    WHEN 'kelmadi' THEN 'Kelmadi'
                                    ELSE 'Qaytarildi' END,
                       COALESCE(NULLIF(trim(p_sabab), ''), 'sabab yozilmagan'),
                       joriy_fish())
   WHERE id = p_bron;

  RETURN p_holat;
END $$;

-- ------------------------------------------------------------
-- 6. BRON QABUL QILINDI DEB BELGILASH
--    Bemor ro'yxatga olingandan KEYIN chaqiriladi — shunda bron
--    qaysi yotqizishga aylangani bazada qoladi.
-- ------------------------------------------------------------
-- DIQQAT: 16_tashxis.sql bu funksiyani kengaytiradi — bron qabul
-- qilinganda tashxisni bemorga ko'chiradi. U ishga tushgan bazada
-- bu yerdagi qisqa variant uni bosib ketmasin.
DO $blokq$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='bronlar'
              AND column_name='tashxis') THEN
  RAISE NOTICE '16_tashxis.sql ishga tushgan — bron_qabul_belgila() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION bron_qabul_belgila(p_bron int, p_yotqizish int)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_bemor int;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bronni qabul qilish');

  SELECT bemor_id INTO v_bemor FROM yotqizishlar WHERE id = p_yotqizish;
  IF v_bemor IS NULL THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE bronlar
     SET holat = 'qabul_qilindi',
         bemor_id = v_bemor,
         yotqizish_id = p_yotqizish,
         izoh = COALESCE(izoh || ' | ', '') ||
                format('Qabul qilindi %s. Kim: %s',
                       to_char(current_date, 'DD.MM.YYYY'), joriy_fish())
   WHERE id = p_bron AND holat <> 'qabul_qilindi';

  RETURN FOUND;
END $$
$f$;
END $blokq$;

-- ------------------------------------------------------------
-- 7. v_umumiy ga TEGILMAYDI
--    "Bugun kutilmoqda" va "kechikkan" sonlari Bronlar ekranida
--    v_bronlar dan sanaladi. Sababi: CREATE OR REPLACE VIEW
--    ustunni faqat oxiriga qo'sha oladi, o'rtaga emas — va agar
--    bu yerda o'zgartirsak, 06/10/12 fayllari qayta ishga
--    tushirilganda "cannot drop columns from view" xatosi chiqadi.
-- ------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;
