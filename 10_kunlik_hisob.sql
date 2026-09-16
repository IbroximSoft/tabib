-- ============================================================
--  10_kunlik_hisob.sql
--  01, 03, 05, 06, 08, 09 dan KEYIN ishga tushiriladi. Idempotent.
--
--  Mijoz qarorlari:
--   1. Xonaga joylashtirilmagan bemor QARZDOR BO'LMAYDI.
--      Xonasiz oldindan band qilish — bu bronlar boʻlimining ishi.
--   2. Roʻyxatga olishda xona tanlash MAJBURIY.
--   3. Bemor kursni toʻliq yotmasa — faqat yotgan kunlari uchun
--      toʻlaydi. Misol: 1 haftalik kurs 2 000 000, bemor 1 kun
--      yotib ketsa, oʻsha kunning pulini toʻlab qarzsiz chiqadi.
--      Toʻliq kursdan oshmaydi.
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
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='bemor_qabul') THEN
    RAISE EXCEPTION 'Avval 08_hamrohlar.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
  IF to_regclass('public.narx_tarixi') IS NULL THEN
    RAISE EXCEPTION 'Avval 09_narx_va_telefon.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. HAQIQIY HISOB — kunlik, kursdan oshmaydi
--
--    Xonasiz yozuv        -> 0 (qarz yoʻq)
--    Hali yotibdi         -> bugungacha yotgan kunlar boʻyicha
--    Chiqarilgan          -> summa allaqachon muzlatilgan
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION hisob(p_yotqizish int) RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE
  y record; v_kurs numeric; v_kun int; v_jami numeric;
BEGIN
  SELECT koyka_id, kirish_sana, haqiqiy_chiqish, holat, summa, xona_summa
    INTO y FROM yotqizishlar WHERE id = p_yotqizish;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- xonaga joylashtirilmagan bemordan pul olinmaydi
  IF y.koyka_id IS NULL THEN RETURN 0; END IF;

  v_jami := COALESCE(y.summa,0) + COALESCE(y.xona_summa,0);

  -- chiqarilgan bemorda summa yakuniy holatda saqlangan
  IF y.haqiqiy_chiqish IS NOT NULL THEN RETURN v_jami; END IF;

  SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
  IF v_kurs IS NULL OR v_kurs <= 0 THEN RETURN v_jami; END IF;

  v_kun := GREATEST(0, current_date - y.kirish_sana + 1);
  IF v_kun >= v_kurs THEN RETURN v_jami; END IF;

  RETURN round(v_jami * v_kun / v_kurs);
END $$;

-- Qarz endi haqiqiy hisobdan kelib chiqadi
CREATE OR REPLACE FUNCTION qarz(p_yotqizish int) RETURNS numeric
LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  SELECT GREATEST(0, hisob(p_yotqizish) - tolangan(p_yotqizish))
$$;

-- ------------------------------------------------------------
-- 2. CHIQARISHDA SUMMANI MUZLATISH
--    Bemor ketayotganda yotgan kunlari boʻyicha yakuniy summa
--    yoziladi — keyin u oʻzgarmaydi va tarix aniq qoladi.
-- ------------------------------------------------------------
-- DIQQAT: 24_qaytarish.sql bu triggerga ortiqcha to'lov tekshiruvini
-- qo'shadi. U ishga tushgan bazada bu yerdagi eski variant uni
-- bosib ketmasin.
DO $blokq$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname='qaytarish_ornatildi') THEN
  RAISE NOTICE '24_qaytarish.sql ishga tushgan — trg_qarz_tekshir() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION trg_qarz_tekshir() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $t$
DECLARE
  v_qarz numeric; v_kurs numeric; v_kun int; v_ulush numeric; v_jami numeric;
BEGIN
  IF NEW.haqiqiy_chiqish IS NOT NULL AND OLD.haqiqiy_chiqish IS NULL THEN

    IF NEW.koyka_id IS NULL THEN
      -- xonasiz yozuv: pul hisoblanmaydi
      NEW.summa := 0;
      NEW.xona_summa := 0;
    ELSE
      SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
      v_kun := GREATEST(1,
        (NEW.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date - NEW.kirish_sana + 1);

      IF v_kurs IS NOT NULL AND v_kurs > 0 AND v_kun < v_kurs THEN
        -- Jami summa hisob() bilan AYNAN bir xil yaxlitlanadi, aks holda
        -- 1 so'mlik farq bemorni chiqara olmay qoldiradi.
        v_ulush := v_kun::numeric / v_kurs;
        v_jami  := round((COALESCE(NEW.summa,0) + COALESCE(NEW.xona_summa,0)) * v_ulush);
        NEW.xona_summa := round(COALESCE(NEW.xona_summa,0) * v_ulush);
        NEW.summa      := v_jami - NEW.xona_summa;
        NEW.izoh := COALESCE(NEW.izoh || ' | ', '') ||
          format('Kunlik hisob: %s kun / %s kunlik kurs', v_kun, v_kurs::int);
      END IF;
    END IF;

    v_qarz := GREATEST(0, NEW.summa + NEW.xona_summa - tolangan(NEW.id));
    IF v_qarz > 0 THEN
      RAISE EXCEPTION 'Bemorni chiqarish mumkin emas. Toʻlanmagan qarzdorlik: % soʻm. Avval buxgalterdan chek olinadi.',
        to_char(v_qarz, 'FM999G999G999')
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.holat := 'chiqdi';
  END IF;
  RETURN NEW;
END $t$;
$f$;
END $blokq$;

-- ------------------------------------------------------------
-- 3. XONA TANLASH MAJBURIY
--    Roʻyxatga olishda bemor darhol koykaga joylashtiriladi.
--    Xonasiz kutish — bronlar boʻlimida.
-- ------------------------------------------------------------
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
  v_asosiy int; h jsonb; v_roli shaxs_roli; v_koyka int;
BEGIN
  IF p_koyka IS NULL THEN
    RAISE EXCEPTION 'Bemorni xonaga joylashtirish shart. Xonasiz kutish uchun bron oching.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_asosiy := bemor_joylashtir(
    p_familiya, p_ism, p_jins, p_telefon, p_yosh, p_chet_el, 'bemor'::shaxs_roli,
    p_koyka, p_kirish, p_reja_chiqish, p_oldindan, NULL, p_bemor_id);

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

    v_koyka := NULLIF(h->>'koyka_id','')::int;
    IF v_koyka IS NULL THEN
      RAISE EXCEPTION 'Hamroh (%) uchun ham koyka tanlanishi kerak.', h->>'ism'
        USING ERRCODE = 'check_violation';
    END IF;

    PERFORM bemor_joylashtir(
      h->>'familiya', h->>'ism', (h->>'jins')::jins_turi,
      COALESCE(NULLIF(h->>'telefon',''), p_telefon),
      NULLIF(h->>'yosh','')::int,
      COALESCE((h->>'chet_el')::boolean, false),
      v_roli, v_koyka, p_kirish, p_reja_chiqish,
      0, v_asosiy, NULLIF(h->>'bemor_id','')::int);
  END LOOP;

  RETURN v_asosiy;
END $$;

-- ------------------------------------------------------------
-- 4. KO'RINISHLARDA: kurs summasi va hozirgi hisob alohida
--    umumiy = hozirgi hisob, shunda "umumiy - toʻlangan = qarz"
--    arifmetikasi ekranda toʻgʻri chiqadi.
-- ------------------------------------------------------------
-- DIQQAT: 16_tashxis.sql bu ko'rinishga "tashxis" ustunini qo'shadi
-- va yakuniy variantini o'zida saqlaydi. U ishga tushgan bazada
-- bu yerdagi variant uni bosib ketsa, tashxis ekrandan yo'qoladi.
DO $blokv$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='yotqizishlar'
              AND column_name='tashxis') THEN
  RAISE NOTICE '16_tashxis.sql ishga tushgan — v_yotqizishlar o''zgartirilmaydi.';
  RETURN;
END IF;
DROP VIEW IF EXISTS v_yotqizishlar;
EXECUTE $v$
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
  y.summa + y.xona_summa AS kurs_summa,     -- toʻliq kurs boʻyicha
  hisob(y.id)            AS umumiy,          -- hozirgi haqiqiy hisob
  tolangan(y.id)         AS tolangan,
  qarz(y.id)             AS qarz,
  (qarz(y.id) > 0)       AS qarzdor,
  y.band_davri, y.izoh,
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
END $blokv$;

DROP VIEW IF EXISTS v_hozir_yotganlar CASCADE;
CREATE VIEW v_hozir_yotganlar
WITH (security_invoker = on) AS
SELECT y.id AS yotqizish_id, b.id AS bemor_id,
       b.familiya || ' ' || b.ism AS fish,
       b.jins, b.telefon, b.chet_el, y.roli,
       x.raqam AS xona, k.raqam AS koyka, bo.nomi AS bolim,
       (y.koyka_id IS NOT NULL) AS xonada,
       y.kirish_sana, y.kirish_vaqt, y.reja_chiqish,
       (current_date - y.kirish_sana + 1) AS kun,
       y.summa + y.xona_summa AS kurs_summa,
       hisob(y.id)    AS umumiy,
       tolangan(y.id) AS tolangan,
       qarz(y.id)     AS qarz
FROM yotqizishlar y
  JOIN bemorlar b   ON b.id = y.bemor_id
  LEFT JOIN koykalar k  ON k.id = y.koyka_id
  LEFT JOIN xonalar x   ON x.id = k.xona_id
  LEFT JOIN bolimlar bo ON bo.id = x.bolim_id
WHERE y.holat = 'yotmoqda';

DROP VIEW IF EXISTS v_qarzdorlar CASCADE;
CREATE VIEW v_qarzdorlar
WITH (security_invoker = on) AS
SELECT y.id AS yotqizish_id, b.familiya || ' ' || b.ism AS fish, b.telefon,
       COALESCE(x.raqam, '—') AS xona,
       y.summa + y.xona_summa AS kurs_summa,
       hisob(y.id) AS umumiy,
       tolangan(y.id) AS tolangan, qarz(y.id) AS qarz
FROM yotqizishlar y
  JOIN bemorlar b ON b.id = y.bemor_id
  LEFT JOIN koykalar k ON k.id = y.koyka_id
  LEFT JOIN xonalar x  ON x.id = k.xona_id
WHERE y.holat = 'yotmoqda' AND y.koyka_id IS NOT NULL AND qarz(y.id) > 0;

-- v_umumiy CASCADE bilan o'chgan bo'lishi mumkin — tiklaymiz
CREATE OR REPLACE VIEW v_umumiy
WITH (security_invoker = on) AS
SELECT
  (SELECT count(*) FROM bemorlar)                                       AS jami_bemor,
  (SELECT count(*) FROM yotqizishlar WHERE holat='yotmoqda')            AS hozir_yotmoqda,
  (SELECT count(*) FROM yotqizishlar
     WHERE holat='yotmoqda' AND koyka_id IS NULL)                       AS xonasiz,
  (SELECT count(*) FROM yotqizishlar WHERE kirish_sana=current_date)    AS bugun_keldi,
  (SELECT count(*) FROM yotqizishlar
     WHERE holat='yotmoqda' AND reja_chiqish=current_date)              AS bugun_ketishi_kerak,
  (SELECT count(*) FROM yotqizishlar
     WHERE (haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
           = current_date)                                              AS bugun_ketdi,
  (SELECT count(*) FROM v_tasdiqlanmagan)                               AS tasdiqlanmagan,
  (SELECT count(*) FROM v_xona_holati WHERE holat='bosh')               AS bosh_xona,
  (SELECT count(*) FROM v_xona_holati WHERE holat IN ('qisman','toliq'))AS band_xona,
  (SELECT count(*) FROM bronlar WHERE holat='kutilmoqda')               AS bron,
  (SELECT count(*) FROM v_qarzdorlar)                                   AS qarzdor_soni,
  (SELECT COALESCE(sum(qarz),0) FROM v_qarzdorlar)                      AS qarz_jami,
  (SELECT COALESCE(sum(summa),0) FROM tolovlar WHERE sana=current_date) AS bugungi_tushum,
  (SELECT COALESCE(sum(summa),0) FROM tolovlar
     WHERE sana >= date_trunc('month', current_date)::date)             AS oylik_tushum;

-- chek ham hozirgi hisobni koʻrsatsin (ustunlar oʻzgargani uchun avval oʻchiriladi)
--
-- DIQQAT: 13_chek.sql chek() ni ancha kengaytiradi (kunlik narx, kurs kuni,
-- boʻlim, yosh...). U ishga tushgan bazada bu yerdagi qisqa variant uni
-- bosib ketsa, chek qogʻozi buzilib qoladi — shuning uchun shartli.
DO $blokc$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'tolov_qosh' AND p.pronargs = 5) THEN
  RAISE NOTICE '13_chek.sql ishga tushgan — chek() oʻzgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
DROP FUNCTION IF EXISTS chek(int)
$f$;
EXECUTE $f$
CREATE FUNCTION chek(p_tolov int)
RETURNS TABLE (
  chek_raqam text, familiya text, ism text, telefon text,
  xona text, koyka smallint, kelgan timestamp, tolov_vaqti timestamptz,
  summa numeric, usuli tolov_usuli, kurs_summa numeric, umumiy numeric,
  tolangan numeric, qolgan_qarz numeric, kassir text
) LANGUAGE sql STABLE AS $$
  SELECT 'CHK-' || lpad(t.id::text, 6, '0'),
    b.familiya, b.ism, b.telefon,
    COALESCE(x.raqam, '—'), k.raqam,
    (y.kirish_sana + y.kirish_vaqt)::timestamp, t.yaratilgan,
    t.summa, t.usuli,
    y.summa + y.xona_summa, hisob(y.id),
    tolangan(y.id), qarz(y.id),
    COALESCE(t.kim, '—')
  FROM tolovlar t
    JOIN yotqizishlar y ON y.id = t.yotqizish_id
    JOIN bemorlar b     ON b.id = y.bemor_id
    LEFT JOIN koykalar k ON k.id = y.koyka_id
    LEFT JOIN xonalar x  ON x.id = k.xona_id
  WHERE t.id = p_tolov;
$$
$f$;
END $blokc$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;
