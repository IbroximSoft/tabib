-- ============================================================
--  23_mening_profilim.sql — XODIM O'Z PROFILINI TAHRIRLASHI
--  01, 03, 05, 06, 08..22 dan KEYIN. Idempotent.
--
--  NEGA KERAK
--    Shu paytgacha ism-familiya va telefon raqamini faqat super
--    admin o'zgartira olardi. Endi har bir xodim o'zinikini
--    o'zi to'g'irlaydi — familiyasi noto'g'ri yozilgan bo'lsa
--    yoki raqami o'zgargan bo'lsa, super adminni kutmaydi.
--
--  KIM CHAQIRA OLADI
--    Tizimga kirgan HAR QANDAY faol xodim — lekin faqat
--    O'ZINING yozuvini. Kimning yozuvi ekani auth.uid() orqali
--    aniqlanadi, ilova yuborgan raqamga ishonilmaydi.
--
--  ROLGA TEGILMAYDI
--    O'z rolini hech kim o'zgartira olmaydi — rol super
--    adminning ishi. Bu funksiya rolni umuman qabul qilmaydi.
--
--  PAROL BU YERDA EMAS
--    Parolni xodim o'zi Supabase Auth orqali almashtiradi
--    (ilova avval eski parolni tekshiradi). Baza aralashmaydi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='xodim_telefon') THEN
    RAISE EXCEPTION 'Avval 22_xodim_login.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- O'Z PROFILINI SAQLASH
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS mening_profilim(text, text, text, text);

CREATE FUNCTION mening_profilim(
  p_familiya text,
  p_ism      text,
  p_telefon  text,
  p_login    text
) RETURNS TABLE (fish text, telefon text, login text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid   uuid;
  v_xodim xodimlar%ROWTYPE;
  v_raqam text := tel_raqam(COALESCE(p_telefon, ''));
  v_login text := lower(btrim(COALESCE(p_login, '')));
  v_domen text;
BEGIN
  IF joriy_rol() IS NULL THEN
    RAISE EXCEPTION 'Tizimga kirilmagan yoki xodim faol emas.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  BEGIN EXECUTE 'SELECT auth.uid()' INTO v_uid;
  EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Hisobingiz aniqlanmadi — qaytadan kiring.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_xodim FROM xodimlar WHERE auth_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sizning xodim yozuvingiz topilmadi.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF btrim(COALESCE(p_familiya, '')) = '' THEN
    RAISE EXCEPTION 'Familiyani kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF btrim(COALESCE(p_ism, '')) = '' THEN
    RAISE EXCEPTION 'Ismni kiriting.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE xodimlar x3
     SET familiya = btrim(p_familiya),
         ism      = btrim(p_ism)
   WHERE x3.id = v_xodim.id;

  -- ---------- telefon (login) ----------
  IF v_raqam IS DISTINCT FROM tel_raqam(COALESCE(v_xodim.telefon, '')) THEN
    IF length(v_raqam) < 9 THEN
      RAISE EXCEPTION 'Telefon raqamini toʻliq kiriting.' USING ERRCODE = 'check_violation';
    END IF;

    v_domen := split_part(v_login, '@', 2);
    IF v_domen = '' OR v_login <> v_raqam || '@' || v_domen THEN
      RAISE EXCEPTION 'Login manzili raqamga mos kelmadi. Ilovani yangilang.'
        USING ERRCODE = 'check_violation';
    END IF;

    -- DIQQAT: RETURNS TABLE dagi "telefon" nomi bilan chalkashmasin,
    -- shuning uchun jadvalga taxallus beriladi.
    IF EXISTS (SELECT 1 FROM xodimlar x2
                WHERE x2.id <> v_xodim.id AND x2.telefon IS NOT NULL
                  AND tel_raqam(x2.telefon) = v_raqam) THEN
      RAISE EXCEPTION 'Bu telefon raqami boshqa xodimga yozilgan.'
        USING ERRCODE = 'unique_violation';
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users u2
                WHERE lower(u2.email) = v_login AND u2.id <> v_uid) THEN
      RAISE EXCEPTION 'Bu raqam bilan boshqa hisob bor.'
        USING ERRCODE = 'unique_violation';
    END IF;

    UPDATE xodimlar x4 SET telefon = btrim(p_telefon) WHERE x4.id = v_xodim.id;

    UPDATE auth.users
       SET email              = v_login,
           email_confirmed_at = COALESCE(email_confirmed_at, now()),
           raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                                || jsonb_build_object('email', v_login,
                                                      'email_verified', true),
           updated_at         = now()
     WHERE id = v_uid;

    UPDATE auth.identities
       SET identity_data = COALESCE(identity_data, '{}'::jsonb)
                           || jsonb_build_object('email', v_login),
           updated_at    = now()
     WHERE user_id = v_uid AND provider = 'email';
  END IF;

  RETURN QUERY
    SELECT x.fish, x.telefon, (SELECT lower(u.email) FROM auth.users u WHERE u.id = v_uid)
      FROM xodimlar x WHERE x.id = v_xodim.id;
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
