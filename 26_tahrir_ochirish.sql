-- ============================================================
--  26_tahrir_ochirish.sql — BEMORNI O'CHIRISH VA XONANI TAHRIRLASH
--  01, 03, 05, 06, 08..25 dan KEYIN. Idempotent.
--
--  1. BEMORNI O'CHIRISH — bemor_ochir()
--     Xato yozuv har qanday tizimda bo'ladi: ism noto'g'ri
--     yozilgan, bir odam ikki marta kiritilgan, boshqa bemor
--     tanlangan. Shuni tuzatish kerak, lekin kassa hisobini
--     buzmasdan. Shuning uchun IKKI XIL YO'L:
--
--       TO'LOV YO'Q   -> yozuv butunlay o'chadi. Bu shunchaki
--                        xato kiritilgan qator edi, hech kimga
--                        hech narsa to'lanmagan.
--       TO'LOV BOR    -> yozuv O'CHMAYDI. U "bekor" deb
--                        belgilanadi, sabab yoziladi, koyka
--                        bo'shaydi. Pul esa kassada qanday
--                        bo'lsa shundayligicha qoladi —
--                        hisobot hech qachon yolg'on
--                        ko'rsatmaydi.
--
--     Kim: faqat admin (super_admin).
--
--  2. XONANI TAHRIRLASH — xona_tahrir(), xona_koyka()
--     Xona raqamini to'g'irlash, boshqa bo'limga ko'chirish va
--     koyka sonini o'zgartirish. Xavfsizlik chegaralari:
--       · bemor yotgan xonani boshqa bo'limga ko'chirib
--         bo'lmaydi (bo'lim jinsi mos kelmay qoladi);
--       · yozuvlari bor koykani o'chirib bo'lmaydi (tarix
--         yo'qolmasin).
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='yashirin_ornatildi') THEN
    RAISE EXCEPTION 'Avval 25_yashirin_admin.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 0. BELGI FUNKSIYASI
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION tahrir_ornatildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- 1. BEMORNI O'CHIRISH (yoki bekor qilish)
--
--    p_yotqizish — bemor kartasidagi yozuv.
--    Qarovchi va farzandlar ham shu yozuvga biriktirilgan
--    bo'lsa, ular bilan birga ketadi: bitta oila — bitta amal.
--
--    Qaytaradi: amal ('ochirildi' yoki 'bekor') va xabar.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bemor_ochir(int, text);

CREATE FUNCTION bemor_ochir(p_yotqizish int, p_sabab text DEFAULT NULL)
RETURNS TABLE (amal text, xabar text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_fish    text;
  v_holat   yotqizish_holati;
  v_guruh   int[];
  v_hamroh  int;
  v_tolov   numeric;
  v_bemorlar int[];
  v_ochgan  int;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'bemorni oʻchirish');

  SELECT b.familiya || ' ' || b.ism, y.holat INTO v_fish, v_holat
    FROM yotqizishlar y JOIN bemorlar b ON b.id = y.bemor_id
   WHERE y.id = p_yotqizish;

  IF v_fish IS NULL THEN
    RAISE EXCEPTION 'Bemor yozuvi topilmadi.' USING ERRCODE = 'no_data_found';
  END IF;

  -- Shu yozuv + unga biriktirilgan hamrohlar
  SELECT array_agg(y.id) INTO v_guruh
    FROM yotqizishlar y
   WHERE y.id = p_yotqizish OR y.asosiy_id = p_yotqizish;

  v_hamroh := cardinality(v_guruh) - 1;

  -- Pul tegganmi? Qaytarilgan (manfiy) qatorlar ham pul harakati.
  SELECT COALESCE(sum(abs(t.summa)), 0) INTO v_tolov
    FROM tolovlar t WHERE t.yotqizish_id = ANY(v_guruh);

  -- ---------------------------------------------------------
  -- A. PUL TEGMAGAN — butunlay o'chiramiz
  -- ---------------------------------------------------------
  IF v_tolov = 0 THEN
    -- Bron bu yozuvga bog'langan bo'lsa, u yana ochiq bo'lsin
    UPDATE bronlar
       SET yotqizish_id = NULL,
           holat = CASE WHEN holat = 'qabul_qilindi' THEN 'kutilmoqda'::bron_holati
                        ELSE holat END
     WHERE yotqizish_id = ANY(v_guruh);

    SELECT array_agg(DISTINCT y.bemor_id) INTO v_bemorlar
      FROM yotqizishlar y WHERE y.id = ANY(v_guruh);

    DELETE FROM yotqizishlar WHERE asosiy_id = p_yotqizish;
    DELETE FROM yotqizishlar WHERE id = p_yotqizish;

    -- Boshqa yozuvi qolmagan bemorning o'zini ham o'chiramiz
    DELETE FROM bemorlar b
     WHERE b.id = ANY(v_bemorlar)
       AND NOT EXISTS (SELECT 1 FROM yotqizishlar y WHERE y.bemor_id = b.id)
       AND NOT EXISTS (SELECT 1 FROM bronlar br WHERE br.bemor_id = b.id);
    GET DIAGNOSTICS v_ochgan = ROW_COUNT;

    RETURN QUERY SELECT 'ochirildi'::text,
      format('%s oʻchirildi%s.%s', v_fish,
             CASE WHEN v_hamroh > 0
                  THEN format(' (hamrohlari bilan — %s ta yozuv)', v_hamroh + 1)
                  ELSE '' END,
             CASE WHEN v_ochgan = 0
                  THEN ' Bemor kartasi bazada qoldi — unda boshqa yozuvlar bor.'
                  ELSE '' END);
    RETURN;
  END IF;

  -- ---------------------------------------------------------
  -- B. PUL TEGGAN — o'chirmaymiz, bekor qilamiz
  -- ---------------------------------------------------------
  IF COALESCE(btrim(p_sabab), '') = '' THEN
    RAISE EXCEPTION 'Bu bemorda % soʻmlik toʻlov bor — yozuv oʻchirilmaydi. Bekor qilish uchun sababini yozing.',
      pul_matn(v_tolov) USING ERRCODE = 'check_violation';
  END IF;

  UPDATE yotqizishlar y
     SET holat = 'bekor',
         izoh  = COALESCE(y.izoh || ' | ', '') ||
                 format('BEKOR QILINDI: %s. Kim: %s', btrim(p_sabab), joriy_fish())
   WHERE y.id = ANY(v_guruh);

  UPDATE bronlar
     SET yotqizish_id = NULL, holat = 'kutilmoqda'
   WHERE yotqizish_id = ANY(v_guruh) AND holat = 'qabul_qilindi';

  RETURN QUERY SELECT 'bekor'::text,
    format('%s yozuvi bekor qilindi — koyka boʻshadi. Yozuv oʻchirilmadi, chunki unda %s soʻmlik toʻlov bor: kassa hisoboti oʻzgarishsiz qoladi.',
           v_fish, pul_matn(v_tolov));
END $$;

-- ------------------------------------------------------------
-- 2. XONANI TAHRIRLASH — raqam va bo'lim
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xona_tahrir(int, text, int);

CREATE FUNCTION xona_tahrir(p_xona int, p_raqam text DEFAULT NULL, p_bolim_id int DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_x      xonalar%ROWTYPE;
  v_raqam  text;
  v_bolim  int;
  v_nomi   text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'xonani tahrirlash');

  SELECT * INTO v_x FROM xonalar WHERE id = p_xona;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Xona topilmadi.' USING ERRCODE = 'no_data_found';
  END IF;

  v_raqam := COALESCE(NULLIF(btrim(p_raqam), ''), v_x.raqam);
  v_bolim := COALESCE(p_bolim_id, v_x.bolim_id);

  -- ---------- raqam ----------
  IF v_raqam <> v_x.raqam THEN
    IF EXISTS (SELECT 1 FROM xonalar x WHERE x.raqam = v_raqam AND x.id <> p_xona) THEN
      RAISE EXCEPTION '%-xona allaqachon bor — boshqa raqam tanlang.', v_raqam
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  -- ---------- bo'lim ----------
  IF v_bolim <> v_x.bolim_id THEN
    SELECT nomi INTO v_nomi FROM bolimlar WHERE id = v_bolim;
    IF v_nomi IS NULL THEN
      RAISE EXCEPTION 'Boʻlim topilmadi.' USING ERRCODE = 'check_violation';
    END IF;

    -- Bo'lim jinsi bemorga mos kelishi shart, shuning uchun
    -- band xonani ko'chirib bo'lmaydi.
    IF EXISTS (SELECT 1 FROM yotqizishlar y JOIN koykalar k ON k.id = y.koyka_id
                WHERE k.xona_id = p_xona AND y.holat = 'yotmoqda') THEN
      RAISE EXCEPTION 'Xonada bemor yotibdi — boʻlimni oʻzgartirib boʻlmaydi. Avval bemorlarni koʻchiring yoki chiqaring.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF EXISTS (SELECT 1 FROM bronlar br
                WHERE br.xona_id = p_xona AND br.holat = 'kutilmoqda') THEN
      RAISE EXCEPTION 'Bu xonaga bron qilingan — boʻlimni oʻzgartirib boʻlmaydi. Avval bronning xonasini almashtiring.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  UPDATE xonalar SET raqam = v_raqam, bolim_id = v_bolim WHERE id = p_xona;

  RETURN format('%s-xona saqlandi (%s).', v_raqam,
                (SELECT nomi FROM bolimlar WHERE id = v_bolim));
END $$;

-- ------------------------------------------------------------
-- 3. KOYKA SONINI O'ZGARTIRISH
--    Ko'paytirish — yangi koykalar qo'shiladi.
--    Kamaytirish — oxirgi raqamlilardan boshlab o'chiriladi,
--    lekin yozuvlari bor koykaga tegilmaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xona_koyka(int, int);

CREATE FUNCTION xona_koyka(p_xona int, p_soni int)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_raqam text;
  v_bor   int;
  v_yangi int;
  r       record;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'koyka sonini oʻzgartirish');

  SELECT x.raqam INTO v_raqam FROM xonalar x WHERE x.id = p_xona;
  IF v_raqam IS NULL THEN
    RAISE EXCEPTION 'Xona topilmadi.' USING ERRCODE = 'no_data_found';
  END IF;

  IF p_soni IS NULL OR p_soni < 1 OR p_soni > 20 THEN
    RAISE EXCEPTION 'Koykalar soni 1 dan 20 gacha boʻlsin.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT count(*) INTO v_bor FROM koykalar k WHERE k.xona_id = p_xona;

  IF p_soni > v_bor THEN
    -- bo'sh raqamlarni to'ldiramiz
    INSERT INTO koykalar (xona_id, raqam)
    SELECT p_xona, g FROM generate_series(1, p_soni) g
     WHERE NOT EXISTS (SELECT 1 FROM koykalar k
                        WHERE k.xona_id = p_xona AND k.raqam = g);

  ELSIF p_soni < v_bor THEN
    FOR r IN SELECT k.id, k.raqam FROM koykalar k
              WHERE k.xona_id = p_xona ORDER BY k.raqam DESC
    LOOP
      EXIT WHEN (SELECT count(*) FROM koykalar k WHERE k.xona_id = p_xona) <= p_soni;

      IF EXISTS (SELECT 1 FROM yotqizishlar y WHERE y.koyka_id = r.id) THEN
        RAISE EXCEPTION '%-xonaning %-koykasida bemor yozuvlari bor — uni oʻchirib boʻlmaydi. Tarix saqlanishi kerak.',
          v_raqam, r.raqam USING ERRCODE = 'check_violation';
      END IF;

      DELETE FROM koykalar WHERE id = r.id;
    END LOOP;
  END IF;

  SELECT count(*) INTO v_yangi FROM koykalar k WHERE k.xona_id = p_xona;

  RETURN format('%s-xonada %s koyka%s.', v_raqam, v_yangi,
    CASE WHEN v_yangi > v_bor THEN format(' (%s ta qoʻshildi)', v_yangi - v_bor)
         WHEN v_yangi < v_bor THEN format(' (%s ta olib tashlandi)', v_bor - v_yangi)
         ELSE '' END);
END $$;

-- ------------------------------------------------------------
-- 4. anon hech narsaga tegmasin
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 5. TEKSHIRUV
-- ------------------------------------------------------------
SELECT
  CASE WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public'
                AND p.proname IN ('bemor_ochir','xona_tahrir','xona_koyka')) = 3
       THEN 'toʻgʻri' ELSE 'XATO' END                  AS "3 ta yangi funksiya",
  CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='public' AND p.proname='bemor_ochir'
                       AND pg_get_functiondef(p.oid) LIKE '%BEKOR QILINDI%')
       THEN 'toʻgʻri' ELSE 'XATO' END                  AS "toʻlovli yozuv saqlanadi";
