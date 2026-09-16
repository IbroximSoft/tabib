-- ============================================================
--  22_xodim_login.sql — XODIMNING LOGINI VA PAROLINI
--                       TIZIM ICHIDAN O'ZGARTIRISH
--  01, 03, 05, 06, 08..21 dan KEYIN. Idempotent.
--
--  MUAMMO
--    Parol Supabase Auth'da yotadi. Uni brauzerdagi ilovadan
--    o'zgartirib bo'lmaydi — buning uchun "service_role" kaliti
--    kerak, uni esa ilovaga qo'yish xavfli (kalitni har qanday
--    foydalanuvchi ko'rib, butun bazani ochib olardi).
--    Shuning uchun shu paytgacha parolni Supabase panelidan,
--    telefon raqamini esa umuman o'zgartirib bo'lmasdi.
--
--  YECHIM
--    Ikkita SECURITY DEFINER funksiya. Ular baza egasi nomidan
--    ishlaydi, shuning uchun auth jadvallariga yoza oladi.
--    Ilovaga hech qanday maxfiy kalit berilmaydi.
--
--  KIM CHAQIRA OLADI
--    Faqat super_admin. Boshqa rol chaqirsa — xato. anon esa
--    umuman chaqira olmaydi (quyida REVOKE bor).
--
--  DIQQAT — TELEFON = LOGIN
--    Raqam o'zgarsa, Auth'dagi login manzili ham o'zgaradi.
--    Ilova yangi manzilni o'zi hisoblab, p_login orqali uzatadi;
--    funksiya uning raqamga mos kelishini tekshiradi. Shunda
--    ilova va baza bir xil qoidadan foydalanadi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='registrator_toraytirildi') THEN
    RAISE EXCEPTION 'Avval 21_registrator.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- pgcrypto qayerda?
--   Supabase'da odatda "extensions" sxemasida. Boshqa joyda
--   bo'lsa ham topib olamiz.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pgcrypto_sxemasi() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT n.nspname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.proname = 'crypt'
   ORDER BY (n.nspname = 'extensions') DESC
   LIMIT 1;
$$;

-- ------------------------------------------------------------
-- 1. PAROLNI O'ZGARTIRISH
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xodim_parol(integer, text);

CREATE FUNCTION xodim_parol(p_id int, p_parol text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_xodim  xodimlar%ROWTYPE;
  v_sxema  text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'parolni oʻzgartirish');

  IF p_parol IS NULL OR length(p_parol) < 6 THEN
    RAISE EXCEPTION 'Parol kamida 6 ta belgidan iborat boʻlsin.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_xodim FROM xodimlar WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Xodim topilmadi.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_xodim.auth_id IS NULL THEN
    RAISE EXCEPTION '% uchun hisob ochilmagan — avval hisobni bogʻlang.', v_xodim.fish
      USING ERRCODE = 'check_violation';
  END IF;

  v_sxema := pgcrypto_sxemasi();
  IF v_sxema IS NULL THEN
    RAISE EXCEPTION 'pgcrypto oʻrnatilmagan. SQL Editorʼda shuni ishga tushiring: '
                    'CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;';
  END IF;

  EXECUTE format(
    'UPDATE auth.users
        SET encrypted_password = %I.crypt($1, %I.gen_salt(''bf'')),
            email_confirmed_at = COALESCE(email_confirmed_at, now()),
            updated_at         = now()
      WHERE id = $2', v_sxema, v_sxema)
  USING p_parol, v_xodim.auth_id;

  RETURN v_xodim.fish;
END $$;

-- ------------------------------------------------------------
-- 2. TELEFON RAQAMINI (LOGINNI) O'ZGARTIRISH
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xodim_telefon(integer, text, text);

CREATE FUNCTION xodim_telefon(p_id int, p_telefon text, p_login text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_xodim xodimlar%ROWTYPE;
  v_raqam text := tel_raqam(COALESCE(p_telefon, ''));
  v_login text := lower(btrim(COALESCE(p_login, '')));
  v_domen text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'loginni oʻzgartirish');

  SELECT * INTO v_xodim FROM xodimlar WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Xodim topilmadi.' USING ERRCODE = 'no_data_found';
  END IF;

  IF length(v_raqam) < 9 THEN
    RAISE EXCEPTION 'Telefon raqamini toʻliq kiriting.' USING ERRCODE = 'check_violation';
  END IF;

  -- Ilova yuborgan login manzili rostdan shu raqamdanmi?
  v_domen := split_part(v_login, '@', 2);
  IF v_domen = '' OR v_login <> v_raqam || '@' || v_domen THEN
    RAISE EXCEPTION 'Login manzili raqamga mos kelmadi (% / %). Ilovani yangilang.',
      v_login, v_raqam USING ERRCODE = 'check_violation';
  END IF;

  -- Raqam boshqa xodimda bo'lmasin
  IF EXISTS (SELECT 1 FROM xodimlar
              WHERE id <> p_id AND telefon IS NOT NULL
                AND tel_raqam(telefon) = v_raqam) THEN
    RAISE EXCEPTION 'Bu telefon raqami boshqa xodimga yozilgan.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Login manzili boshqa hisobda bo'lmasin
  IF v_xodim.auth_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users
                  WHERE lower(email) = v_login AND id <> v_xodim.auth_id) THEN
    RAISE EXCEPTION 'Bu raqam bilan boshqa hisob bor: %', v_login
      USING ERRCODE = 'unique_violation';
  END IF;

  UPDATE xodimlar SET telefon = btrim(p_telefon) WHERE id = p_id;

  IF v_xodim.auth_id IS NOT NULL THEN
    UPDATE auth.users
       SET email              = v_login,
           email_confirmed_at = COALESCE(email_confirmed_at, now()),
           raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                                || jsonb_build_object('email', v_login,
                                                      'email_verified', true),
           updated_at         = now()
     WHERE id = v_xodim.auth_id;

    -- GoTrue "identities" da ham manzil yozilgan — u ham yangilansin
    UPDATE auth.identities
       SET identity_data = COALESCE(identity_data, '{}'::jsonb)
                           || jsonb_build_object('email', v_login),
           updated_at    = now()
     WHERE user_id = v_xodim.auth_id AND provider = 'email';
  END IF;

  RETURN v_login;
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

-- ------------------------------------------------------------
-- YASHIRIN HISOB HIMOYASI
--   25_yashirin_admin.sql ishga tushgan bo'lsa, u yuqoridagi
--   ikki funksiyaga "yashirin xodimga tegmaslik" tekshiruvini
--   qo'shgan edi. Bu fayl funksiyalarni qayta yaratgani uchun
--   tekshiruvni ham qaytarib qo'yamiz.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname='public' AND p.proname='yashirin_himoyasini_qosh') THEN
    PERFORM yashirin_himoyasini_qosh();
  END IF;
END $$;
