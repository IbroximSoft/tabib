-- ============================================================
--  admin_parol.sql — PAROLNI ALMASHTIRISH
--
--  Kimga kerak: o'zingiz yoki paroli esidan chiqqan xodim.
--  Nega SQL: loginlar soxta pochta manzilidan yasalgani uchun
--  "parolni tiklash" xati hech qayerga yetib bormaydi. Shuning
--  uchun parol to'g'ridan-to'g'ri shu yerdan qo'yiladi.
--
--  QAYERDA: Supabase -> SQL Editor.
--  Bu migratsiya emas — kerak bo'lganda ishlatiladi.
-- ============================================================

-- ------------------------------------------------------------
--  KIM VA QANDAY PAROL — shu ikki qatorni o'zgartiring
-- ------------------------------------------------------------
DO $$
DECLARE
  -- Telefon raqami YOKI to'liq email. Ikkalasi ham bo'ladi.
  v_kim   text := '+998 93 630 55 30';

  -- Yangi parol (kamida 6 ta belgi)
  v_parol text := 'yangiparol123';

  -- Ilovadagi domen bilan bir xil bo'lsin (.env dagi VITE_LOGIN_DOMEN)
  v_domen text := 'muhiddintabib.uz';

  -- ----------------------------------------------------------
  v_login  text;
  v_raqam  text;
  v_schema text;
  v_uid    uuid;
  v_fish   text;
BEGIN
  IF length(v_parol) < 6 THEN
    RAISE EXCEPTION 'Parol juda qisqa — kamida 6 ta belgi bo''lsin.';
  END IF;

  -- Login: "@" bo'lsa email, bo'lmasa telefon raqamidan yasaladi
  IF position('@' in v_kim) > 0 THEN
    v_login := lower(btrim(v_kim));
  ELSE
    v_raqam := regexp_replace(v_kim, '\D', '', 'g');
    IF length(v_raqam) < 9 THEN
      RAISE EXCEPTION 'Telefon raqami juda qisqa: %', v_kim;
    END IF;
    v_login := lower(v_raqam || '@' || v_domen);
  END IF;

  SELECT id INTO v_uid FROM auth.users WHERE lower(email) = v_login;

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Bunday login topilmadi: %. '
                    'Authentication -> Users dagi ro''yxatni tekshiring.', v_login;
  END IF;

  SELECT fish INTO v_fish FROM xodimlar WHERE auth_id = v_uid;

  -- pgcrypto qaysi sxemada turganini topamiz (Supabase'da odatda "extensions")
  SELECT n.nspname INTO v_schema
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.proname = 'crypt'
   ORDER BY (n.nspname = 'extensions') DESC
   LIMIT 1;

  IF v_schema IS NULL THEN
    RAISE EXCEPTION 'pgcrypto o''rnatilmagan. Avval shuni ishga tushiring: '
                    'CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;';
  END IF;

  EXECUTE format(
    'UPDATE auth.users
        SET encrypted_password  = %I.crypt($1, %I.gen_salt(''bf'')),
            email_confirmed_at  = COALESCE(email_confirmed_at, now()),
            updated_at          = now()
      WHERE id = $2', v_schema, v_schema)
  USING v_parol, v_uid;

  RAISE NOTICE 'Parol almashtirildi. Login: %  (%)',
               v_login, COALESCE(v_fish, 'xodim yozuvi topilmadi');
END $$;
