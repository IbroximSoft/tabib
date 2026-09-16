-- ============================================================
--  admin_login_raqam.sql
--  SUPER ADMIN LOGINI EMAILDAN TELEFON RAQAMIGA O'TKAZISH
--
--  Nima uchun kerak: qolgan xodimlar telefon raqami bilan
--  kirishadi, super admin esa eski @gmail.com bilan qolgan.
--  Bu skript uni ham bir xil ko'rinishga keltiradi.
--
--  Bu MIGRATSIYA EMAS — bir martalik ish. Faylni raqamli
--  fayllar (01..17) qatoriga qo'shmang.
--
--  QAYERDA ISHLATILADI: Supabase -> SQL Editor.
--  U yerda so'rov "postgres" huquqi bilan ketadi, shuning uchun
--  auth jadvallariga tegish mumkin.
--
--  BAJARGACH: eski email bilan kirib bo'lmaydi, faqat yangi
--  telefon raqami bilan. Paroling o'zgarmaydi.
-- ============================================================

-- ------------------------------------------------------------
--  1. SHU IKKI QATORNI O'ZGARTIRING
-- ------------------------------------------------------------
DO $$
DECLARE
  -- Hozirgi login (Supabase -> Authentication -> Users da ko'ringan email)
  v_eski_email text := '936305530@gmail.com';

  -- Yangi login uchun telefon raqami
  v_telefon    text := '+998 93 630 55 30';

  -- Ilovadagi domen bilan bir xil bo'lsin!
  -- (.env dagi VITE_LOGIN_DOMEN, ko'rsatilmagan bo'lsa — muhiddintabib.uz)
  v_domen      text := 'muhiddintabib.uz';

  -- ----------------------------------------------------------
  v_raqam text;
  v_yangi text;
  v_uid   uuid;
  v_xodim int;
BEGIN
  v_raqam := regexp_replace(v_telefon, '\D', '', 'g');

  IF length(v_raqam) < 9 THEN
    RAISE EXCEPTION 'Telefon raqami juda qisqa: % (raqamlari: %)', v_telefon, v_raqam;
  END IF;

  v_yangi := lower(v_raqam || '@' || v_domen);

  -- Hisobni topamiz
  SELECT id INTO v_uid
    FROM auth.users
   WHERE lower(email) = lower(btrim(v_eski_email));

  IF v_uid IS NULL THEN
    -- Skript ikkinchi marta ishga tushirilgan bo'lishi mumkin
    IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = v_yangi) THEN
      RAISE NOTICE 'Bu ish allaqachon bajarilgan — login: %. Hech narsa o''zgartirilmadi.',
                   v_yangi;
      RETURN;
    END IF;
    RAISE EXCEPTION 'Bunday email bilan hisob topilmadi: %. '
                    'Authentication -> Users dagi yozuvni aynan ko''chiring.',
                    v_eski_email;
  END IF;

  -- Yangi manzil boshqa birovda bo'lmasin
  IF EXISTS (SELECT 1 FROM auth.users
              WHERE lower(email) = v_yangi AND id <> v_uid) THEN
    RAISE EXCEPTION 'Bu raqam bilan boshqa hisob bor: %', v_yangi;
  END IF;

  -- Xodimlar jadvalida bu raqam boshqa odamda bo'lmasin
  SELECT id INTO v_xodim FROM xodimlar WHERE auth_id = v_uid;

  IF EXISTS (SELECT 1 FROM xodimlar
              WHERE telefon IS NOT NULL
                AND regexp_replace(telefon, '\D', '', 'g') = v_raqam
                AND id IS DISTINCT FROM v_xodim) THEN
    RAISE EXCEPTION 'Bu telefon raqami boshqa xodimga yozilgan: %', v_telefon;
  END IF;

  -- ----------------------------------------------------------
  --  2. AUTH HISOBI
  -- ----------------------------------------------------------
  UPDATE auth.users
     SET email               = v_yangi,
         -- tasdiqlanmagan bo'lsa tasdiqlab qo'yamiz, aks holda
         -- yangi manzil bilan kira olmay qoladi
         email_confirmed_at  = COALESCE(email_confirmed_at, now()),
         raw_user_meta_data  = COALESCE(raw_user_meta_data, '{}'::jsonb)
                               || jsonb_build_object('email', v_yangi,
                                                     'email_verified', true),
         updated_at          = now()
   WHERE id = v_uid;

  -- GoTrue "identities" jadvalida ham email yozib qo'yiladi.
  -- Uni yangilamasak, ba'zi oynalarda eski manzil ko'rinib turadi.
  UPDATE auth.identities
     SET identity_data = COALESCE(identity_data, '{}'::jsonb)
                         || jsonb_build_object('email', v_yangi),
         updated_at    = now()
   WHERE user_id = v_uid
     AND provider = 'email';

  -- ----------------------------------------------------------
  --  3. XODIM PROFILI — ro'yxatda raqam ko'rinib tursin
  -- ----------------------------------------------------------
  IF v_xodim IS NOT NULL THEN
    UPDATE xodimlar SET telefon = btrim(v_telefon) WHERE id = v_xodim;
  ELSE
    RAISE NOTICE 'Diqqat: bu auth hisobiga bog''langan xodim yozuvi topilmadi.';
  END IF;

  RAISE NOTICE 'Tayyor. Yangi login: %  (parol o''zgarmadi)', v_yangi;
END $$;

-- ------------------------------------------------------------
--  4. TEKSHIRUV — natijani ko'rish
-- ------------------------------------------------------------
SELECT u.email          AS "auth login",
       i.identity_data ->> 'email' AS "identity email",
       x.fish           AS "xodim",
       x.telefon        AS "telefon",
       x.rol            AS "rol"
FROM auth.users u
  LEFT JOIN auth.identities i ON i.user_id = u.id AND i.provider = 'email'
  LEFT JOIN xodimlar x        ON x.auth_id = u.id
ORDER BY u.created_at;
