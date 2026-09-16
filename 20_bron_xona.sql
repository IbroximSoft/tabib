-- ============================================================
--  20_bron_xona.sql — BRON XONASINI O'ZGARTIRISH
--  01, 03, 05, 06, 08..19 dan KEYIN. Idempotent.
--
--  NEGA KERAK
--    Bron qo'yilganda xona bo'sh edi. Keyin o'sha xonada yotgan
--    bemorning muddati uzaytirildi — endi bron kuniga xona
--    bo'shamaydi. Bronlar ekrani buni ogohlantiradi
--    ("Boshqa xona kerak bo'ladi"), lekin xonani almashtirish
--    imkoni yo'q edi: bronni bekor qilib, qaytadan qo'yishdan
--    boshqa yo'l qolmasdi.
--
--    Endi bitta funksiya bilan almashtiriladi. Bron o'zi
--    o'zgarmaydi — ismi, sanasi, tashxisi joyida qoladi.
--
--  TEKSHIRUVLAR
--    * faqat "kutilmoqda" bronni o'zgartirish mumkin;
--    * xona jinsi bo'limga mos kelsin;
--    * o'sha sanalarda xonada haqiqatan joy bo'lsin —
--      bronning O'ZI band qilgan joy hisobga olinmaydi,
--      aks holda xonani o'ziga almashtirib bo'lmasdi;
--    * xona NULL berilsa — bron "xonasiz" holatga o'tadi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                  WHERE c.relname='yotqizishlar' AND t.tgname='bron_avto_bogla') THEN
    RAISE EXCEPTION 'Avval 19_bron_bogla.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- BRON XONASINI ALMASHTIRISH
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bron_xona(integer, integer);

CREATE FUNCTION bron_xona(p_bron int, p_xona_id int DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_bron   bronlar%ROWTYPE;
  v_raqam  text;
  v_bolim  int;
  v_jinsi  bolim_jinsi;
  v_bosh   bigint;
  v_eski   text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bron xonasini oʻzgartirish');

  SELECT * INTO v_bron FROM bronlar WHERE id = p_bron;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bron topilmadi.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_bron.holat <> 'kutilmoqda' THEN
    RAISE EXCEPTION 'Bu bron allaqachon yopilgan (%) — xonasini oʻzgartirib boʻlmaydi.',
      v_bron.holat USING ERRCODE = 'check_violation';
  END IF;

  SELECT x.raqam INTO v_eski FROM xonalar x WHERE x.id = v_bron.xona_id;

  -- ---------- xonasiz qoldirish ----------
  IF p_xona_id IS NULL THEN
    UPDATE bronlar SET xona_id = NULL WHERE id = p_bron;
    RETURN 'xonasiz';
  END IF;

  -- ---------- yangi xona ----------
  SELECT x.raqam, x.bolim_id, bo.jins
    INTO v_raqam, v_bolim, v_jinsi
    FROM xonalar x JOIN bolimlar bo ON bo.id = x.bolim_id
   WHERE x.id = p_xona_id;

  IF v_raqam IS NULL THEN
    RAISE EXCEPTION 'Xona topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  IF v_bron.jins IS NOT NULL AND v_jinsi <> 'aralash'
     AND v_jinsi::text <> v_bron.jins::text THEN
    RAISE EXCEPTION '%-xona boshqa jins boʻlimida — bu bronga mos kelmaydi.', v_raqam
      USING ERRCODE = 'check_violation';
  END IF;

  -- Joy yetadimi. p_bron berilgani uchun shu bronning o'zi
  -- band qilgan joy hisobdan chiqariladi.
  SELECT bosh INTO v_bosh
    FROM bron_bosh_joylar(v_bron.kirish, v_bron.chiqish, NULL, p_bron)
   WHERE xona_id = p_xona_id;

  IF COALESCE(v_bosh, 0) < v_bron.kishi THEN
    RAISE EXCEPTION '%-xonada % — % kunlari % ta joy yoʻq (boʻsh: %).',
      v_raqam,
      to_char(v_bron.kirish, 'DD.MM.YYYY'), to_char(v_bron.chiqish, 'DD.MM.YYYY'),
      v_bron.kishi, COALESCE(v_bosh, 0)
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE bronlar
     SET xona_id  = p_xona_id,
         bolim_id = v_bolim
   WHERE id = p_bron;

  RETURN v_raqam;
END $$;

-- ------------------------------------------------------------
-- anon hech narsaga tegmasin
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;
