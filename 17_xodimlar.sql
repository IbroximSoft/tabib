-- ============================================================
--  17_xodimlar.sql — XODIM PROFILLARI (super admin uchun)
--  01, 03, 05, 06, 08..16 dan KEYIN. Idempotent — qayta
--  ishga tushirsa ham hech narsa buzilmaydi.
--
--  Nima qo'shiladi:
--    1. xodimlar.familiya va xodimlar.ism  (fish avtomatik yig'iladi)
--    2. telefon — LOGIN. Raqam bo'yicha takrorlanmaslik kafolati.
--    3. xodim_qosh()     — yangi profil (faqat super_admin)
--    4. xodim_tahrir()   — ism/familiya/rol/faol o'zgartirish
--    5. xodim_telefon_band() — ro'yxatdan oldin tekshirish
--    6. v_xodimlar       — ro'yxat ko'rinishi
--
--  DIQQAT — parol bu yerda saqlanmaydi. Parol Supabase Auth'da
--  yotadi. Ilova avval Auth'da foydalanuvchi ochadi, keyin shu
--  yerga uning auth_id sini yozadi. Shuning uchun Supabase'da
--  Authentication -> Providers -> Email da
--  "Confirm email" O'CHIQ bo'lishi shart, aks holda yangi
--  xodim tasdiqlamaguncha kira olmaydi (xat esa hech qayerga
--  bormaydi — login uchun soxta pochta ishlatiladi).
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='yotqizishlar'
                    AND column_name='tashxis') THEN
    RAISE EXCEPTION 'Avval 16_tashxis.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. FAMILIYA VA ISM
--    Eskisida faqat "fish" bor edi. Uni yo'qotmaymiz: familiya
--    va ism to'ldirilganda fish o'zi yig'iladi, shuning uchun
--    joriy_fish(), narx tarixi va cheklar avvalgidek ishlayveradi.
-- ------------------------------------------------------------
ALTER TABLE xodimlar ADD COLUMN IF NOT EXISTS familiya text;
ALTER TABLE xodimlar ADD COLUMN IF NOT EXISTS ism      text;

-- Bor yozuvlarni bo'lib chiqamiz: birinchi so'z — familiya
UPDATE xodimlar
   SET familiya = COALESCE(familiya, split_part(btrim(fish), ' ', 1)),
       ism      = COALESCE(ism,
                    NULLIF(btrim(substr(btrim(fish),
                          length(split_part(btrim(fish), ' ', 1)) + 1)), ''))
 WHERE familiya IS NULL OR ism IS NULL;

CREATE OR REPLACE FUNCTION trg_xodim_fish() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.familiya IS NOT NULL OR NEW.ism IS NOT NULL THEN
    NEW.fish := btrim(COALESCE(NEW.familiya, '') || ' ' || COALESCE(NEW.ism, ''));
  END IF;
  IF NEW.fish IS NULL OR btrim(NEW.fish) = '' THEN
    RAISE EXCEPTION 'Xodimning familiyasi va ismi bo''sh bo''lmasin.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS xodim_fish ON xodimlar;
CREATE TRIGGER xodim_fish BEFORE INSERT OR UPDATE ON xodimlar
FOR EACH ROW EXECUTE FUNCTION trg_xodim_fish();

-- ------------------------------------------------------------
-- 2. TELEFON = LOGIN
--    "+998 90 123 45 67" va "998901234567" bir xil raqam.
--    Shuning uchun faqat raqamlar bo'yicha taqqoslaymiz.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION tel_raqam(p text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT regexp_replace(p, '\D', '', 'g')
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT tel_raqam(telefon) FROM xodimlar
     WHERE telefon IS NOT NULL AND btrim(telefon) <> ''
     GROUP BY tel_raqam(telefon) HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Bir xil telefon raqamli xodimlar bor — avval ularni tuzating.';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS xodim_telefon_uniq
  ON xodimlar (tel_raqam(telefon))
  WHERE telefon IS NOT NULL AND btrim(telefon) <> '';

-- ------------------------------------------------------------
-- 3. RO'YXAT KO'RINISHI
--    DIQQAT: 25_yashirin_admin.sql shu ko'rinishga "yashirin"
--    ustunini qo'shadi va rolni "Admin" deb yozadi. U ishga
--    tushgan bazada bu yerdagi eski variant uni bosib ketmasin.
-- ------------------------------------------------------------
DO $blokx$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname='yashirin_ornatildi') THEN
  RAISE NOTICE '25_yashirin_admin.sql ishga tushgan — v_xodimlar o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $vx$
CREATE OR REPLACE VIEW v_xodimlar
WITH (security_invoker = on) AS
SELECT
  x.id,
  x.familiya,
  x.ism,
  x.fish,
  x.telefon,
  tel_raqam(x.telefon)                    AS login_raqam,
  x.rol,
  CASE x.rol
    WHEN 'super_admin'   THEN 'Super admin'
    WHEN 'administrator' THEN 'Registrator'
    WHEN 'buxgalter'     THEN 'Buxgalter'
    ELSE 'Kuzatuvchi'
  END                                     AS rol_matn,
  x.faol,
  x.auth_id IS NOT NULL                   AS kira_oladi,
  x.yaratilgan
FROM xodimlar x
ORDER BY x.faol DESC, x.rol, x.familiya, x.ism;
$vx$;
END $blokx$;

-- ------------------------------------------------------------
-- 4. TELEFON BO'SHMI?
--    Auth'da foydalanuvchi ochishdan OLDIN chaqiriladi —
--    shunda bekorga hisob yaratilib qolmaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xodim_telefon_band(text);

CREATE FUNCTION xodim_telefon_band(p_telefon text)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_raqam text := tel_raqam(COALESCE(p_telefon, ''));
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'xodimlarni ko''rish');
  IF length(v_raqam) < 7 THEN
    RAISE EXCEPTION 'Telefon raqami juda qisqa — kamida 7 ta raqam bo''lsin.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN EXISTS (SELECT 1 FROM xodimlar
                  WHERE telefon IS NOT NULL AND tel_raqam(telefon) = v_raqam);
END $$;

-- ------------------------------------------------------------
-- 5. YANGI XODIM
--    p_auth_id — Supabase Auth'da endigina ochilgan hisob id si.
--    NULL bo'lsa profil yaratiladi, lekin u kira olmaydi
--    (ro'yxatda "kira olmaydi" bo'lib turadi).
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xodim_qosh(uuid, text, text, text, text);

CREATE FUNCTION xodim_qosh(
  p_auth_id  uuid,
  p_familiya text,
  p_ism      text,
  p_telefon  text,
  p_rol      text
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_raqam text := tel_raqam(COALESCE(p_telefon, ''));
  v_rol   rol_turi;
  v_id    integer;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'xodim qo''shish');

  IF btrim(COALESCE(p_familiya, '')) = '' THEN
    RAISE EXCEPTION 'Familiyani kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF btrim(COALESCE(p_ism, '')) = '' THEN
    RAISE EXCEPTION 'Ismni kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(v_raqam) < 7 THEN
    RAISE EXCEPTION 'Telefon raqami juda qisqa — kamida 7 ta raqam bo''lsin.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_rol IS NULL OR p_rol NOT IN ('super_admin','administrator','buxgalter','viewer') THEN
    RAISE EXCEPTION 'Rol noto''g''ri: %', COALESCE(p_rol, '(bo''sh)')
      USING ERRCODE = 'check_violation';
  END IF;
  v_rol := p_rol::rol_turi;

  IF EXISTS (SELECT 1 FROM xodimlar
              WHERE telefon IS NOT NULL AND tel_raqam(telefon) = v_raqam) THEN
    RAISE EXCEPTION 'Bu telefon raqami bilan xodim allaqachon bor: %', p_telefon
      USING ERRCODE = 'unique_violation';
  END IF;

  IF p_auth_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM xodimlar WHERE auth_id = p_auth_id) THEN
    RAISE EXCEPTION 'Bu hisob boshqa xodimga biriktirilgan.'
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO xodimlar(auth_id, familiya, ism, fish, telefon, rol, faol)
  VALUES (p_auth_id, btrim(p_familiya), btrim(p_ism),
          btrim(p_familiya) || ' ' || btrim(p_ism),
          btrim(p_telefon), v_rol, true)
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

-- ------------------------------------------------------------
-- 6. XODIMNI TAHRIRLASH
--    Telefon o'zgarmaydi — u login, Auth'dagi hisobga bog'langan.
--    O'zining rolini yoki faolligini o'zgartira olmaydi va
--    oxirgi super admin o'chib qolmaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xodim_tahrir(integer, text, text, text, boolean);

CREATE FUNCTION xodim_tahrir(
  p_id       integer,
  p_familiya text DEFAULT NULL,
  p_ism      text DEFAULT NULL,
  p_rol      text DEFAULT NULL,
  p_faol     boolean DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid   uuid;
  v_eski  xodimlar%ROWTYPE;
  v_rol   rol_turi;
  v_faol  boolean;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'xodimni tahrirlash');

  SELECT * INTO v_eski FROM xodimlar WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Xodim topilmadi (id %).', p_id USING ERRCODE = 'no_data_found';
  END IF;

  BEGIN EXECUTE 'SELECT auth.uid()' INTO v_uid;
  EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;

  v_rol  := COALESCE(NULLIF(p_rol, '')::rol_turi, v_eski.rol);
  v_faol := COALESCE(p_faol, v_eski.faol);

  IF p_rol IS NOT NULL AND p_rol NOT IN
     ('super_admin','administrator','buxgalter','viewer') THEN
    RAISE EXCEPTION 'Rol noto''g''ri: %', p_rol USING ERRCODE = 'check_violation';
  END IF;

  -- o'zini o'chirib yoki pasaytirib qo'ymasin
  IF v_uid IS NOT NULL AND v_eski.auth_id = v_uid
     AND (v_rol <> v_eski.rol OR v_faol <> v_eski.faol) THEN
    RAISE EXCEPTION 'O''z rolingizni yoki faolligingizni o''zgartira olmaysiz.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- oxirgi super admin qolmasin
  IF v_eski.rol = 'super_admin' AND v_eski.faol
     AND (v_rol <> 'super_admin' OR NOT v_faol)
     AND (SELECT count(*) FROM xodimlar
           WHERE rol = 'super_admin' AND faol AND id <> p_id) = 0 THEN
    RAISE EXCEPTION 'Tizimda kamida bitta faol super admin qolishi shart.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE xodimlar
     SET familiya = COALESCE(NULLIF(btrim(p_familiya), ''), familiya),
         ism      = COALESCE(NULLIF(btrim(p_ism), ''), ism),
         rol      = v_rol,
         faol     = v_faol
   WHERE id = p_id;
END $$;

-- ------------------------------------------------------------
-- 7. HISOBNI PROFILGA BOG'LASH
--    Auth'da hisob ochildi-yu, profil yozilmay qoldi — shunday
--    bo'lsa keyin qo'lda bog'lash uchun.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xodim_bogla(integer, uuid);

CREATE FUNCTION xodim_bogla(p_id integer, p_auth_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'hisobni bog''lash');

  IF p_auth_id IS NULL THEN
    RAISE EXCEPTION 'Hisob id si bo''sh.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM xodimlar WHERE auth_id = p_auth_id AND id <> p_id) THEN
    RAISE EXCEPTION 'Bu hisob boshqa xodimga biriktirilgan.'
      USING ERRCODE = 'unique_violation';
  END IF;

  UPDATE xodimlar SET auth_id = p_auth_id WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Xodim topilmadi (id %).', p_id USING ERRCODE = 'no_data_found';
  END IF;
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
