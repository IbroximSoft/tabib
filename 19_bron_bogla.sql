-- ============================================================
--  19_bron_bogla.sql — BRON VA QABULNI BOG'LASH
--  01, 03, 05, 06, 08..18 dan KEYIN. Idempotent.
--
--  MUAMMO
--    Bron qilingan odam kelganda, xodim "Bronlar" ekraniga
--    o'tmasdan uni "Yangi bemor" qilib yozsa, bron ochiq
--    qolib ketardi. Natijada:
--      * bitta odam IKKI joyni band qilardi (koyka + bron),
--        xona bo'sh bo'la turib "joy yo'q" ko'rinardi;
--      * bron "kutilmoqda" -> "kechikkan" bo'lib qolardi;
--      * hisobot va Dashboard'dagi "bron konflikti"
--        ogohlantirishi odamni o'zi bilan to'qnashtirardi.
--
--  YECHIM
--    1. bron_qidir() — ilova raqam kiritilganda ochiq bronni
--       topib, xodimni ogohlantiradi.
--    2. Trigger — bemor yozilgach, mos keladigan ochiq bron
--       AVTOMATIK yopiladi va yotqizishga bog'lanadi.
--       Xodim ogohlantirishga e'tibor bermasa ham ma'lumot
--       chalkashmaydi.
--
--  MOSLIK QOIDASI — ehtiyotkor
--    Telefon raqami YETARLI EMAS: bu yerda oila a'zolari bitta
--    raqamdan foydalanadi (ota bron qilib, keyin o'g'lini
--    yozdirishi mumkin). Shuning uchun ISM ham tekshiriladi:
--    bron ismining so'zlari bemor ismining so'zlari ichida
--    bo'lishi (yoki aksincha) va kamida IKKI so'z mos kelishi
--    kerak. "Zamirov Karim" va "Zamirov Nozim" bir-biriga
--    bog'lanmaydi.
--
--    Mos kelmasa bron o'z holicha qoladi — xodim uni Bronlar
--    ekranidan qo'lda yopadi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='buxgalter_toraytirildi') THEN
    RAISE EXCEPTION 'Avval 18_buxgalter.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. ISMNI SO'ZLARGA AJRATISH
--    "Testov  Bobur Akmalovich" -> {akmalovich,bobur,testov}
--    Katta-kichik harf, ortiqcha bo'sh joy va tinish belgilari
--    hisobga olinmaydi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION nom_kalit(p text) RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(array_agg(DISTINCT w ORDER BY w), ARRAY[]::text[])
  FROM (
    SELECT regexp_replace(lower(t), '[^[:alnum:]]', '', 'g') AS w
      FROM regexp_split_to_table(COALESCE(p, ''), '\s+') t
  ) s
  WHERE w <> '';
$$;

-- Ikki ism bir odamnikimi?
--   * biri ikkinchisining ichida bo'lsin (ortiqcha otasining
--     ismi qo'shilgan bo'lishi mumkin), VA
--   * kamida ikkita so'z mos kelsin — bitta so'z ("Bobur")
--     yetarli emas, u tasodifan mos kelib qolishi mumkin.
--   Har doim true yoki false qaytaradi, hech qachon NULL emas.
CREATE OR REPLACE FUNCTION nom_mos(p_a text, p_b text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(
           (a <@ b OR b <@ a)
           AND cardinality(ARRAY(SELECT unnest(a) INTERSECT SELECT unnest(b))) >= 2,
           false)
  FROM (SELECT nom_kalit(p_a) AS a, nom_kalit(p_b) AS b) s;
$$;

-- ------------------------------------------------------------
-- 2. RAQAM BO'YICHA OCHIQ BRONNI TOPISH
--    Ilovadagi "Yangi bemor" formasi shuni chaqiradi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bron_qidir(text);

CREATE FUNCTION bron_qidir(p_telefon text)
RETURNS TABLE (
  bron_id int, ismi text, telefon text, jins jins_turi,
  bolim_id smallint, bolim text, xona_id int, xona text,
  kirish date, chiqish date, kun int, kishi smallint,
  izoh text, tashxis text, holat_matn text
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT v.bron_id, v.ismi, v.telefon, v.jins,
         v.bolim_id, v.bolim, v.xona_id, v.xona,
         v.kirish, v.chiqish, v.kun, v.kishi,
         v.izoh, v.tashxis, v.holat_matn
  FROM v_bronlar v
  WHERE v.holat = 'kutilmoqda'
    AND tel_raqam(v.telefon) = tel_raqam(COALESCE(p_telefon, ''))
    AND length(tel_raqam(COALESCE(p_telefon, ''))) >= 7
  ORDER BY v.kirish;
$$;

-- ------------------------------------------------------------
-- 3. AVTOMATIK BOG'LASH
--    yotqizishlar ga yangi qator tushganda ishlaydi — qaysi
--    funksiya orqali yozilganidan qat'i nazar (bemor_qabul,
--    bemor_joylashtir yoki kelajakdagi boshqasi).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_bron_avto_bogla() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_tel   text;
  v_fish  text;
  v_bron  bronlar%ROWTYPE;
BEGIN
  SELECT b.telefon, btrim(b.familiya || ' ' || b.ism)
    INTO v_tel, v_fish
    FROM bemorlar b WHERE b.id = NEW.bemor_id;

  IF v_tel IS NULL OR length(tel_raqam(v_tel)) < 7 THEN
    RETURN NULL;
  END IF;

  -- Raqami va ismi mos keladigan ochiq bronlardan kirish sanasi
  -- eng yaqinini olamiz.
  SELECT br.* INTO v_bron
    FROM bronlar br
   WHERE br.holat = 'kutilmoqda'
     AND br.yotqizish_id IS NULL
     AND tel_raqam(br.telefon) = tel_raqam(v_tel)
     AND nom_mos(br.ismi, v_fish)
   ORDER BY abs(br.kirish - NEW.kirish_sana)
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE bronlar
     SET holat        = 'qabul_qilindi',
         yotqizish_id = NEW.id,
         bemor_id     = COALESCE(bemor_id, NEW.bemor_id),
         izoh         = btrim(COALESCE(izoh || ' ', '')
                        || '(Roʻyxatga olishda avtomatik yopildi '
                        || to_char(now() AT TIME ZONE 'Asia/Tashkent', 'DD.MM.YYYY')
                        || '. Kim: ' || joriy_fish() || ')')
   WHERE id = v_bron.id;

  -- Bronda tashxis bor, yotqizishda yo'q bo'lsa — ko'chiramiz
  IF COALESCE(btrim(v_bron.tashxis), '') <> ''
     AND COALESCE(btrim(NEW.tashxis), '') = '' THEN
    UPDATE yotqizishlar SET tashxis = btrim(v_bron.tashxis) WHERE id = NEW.id;
  END IF;

  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS bron_avto_bogla ON yotqizishlar;
CREATE TRIGGER bron_avto_bogla AFTER INSERT ON yotqizishlar
FOR EACH ROW EXECUTE FUNCTION trg_bron_avto_bogla();

-- ------------------------------------------------------------
-- 4. ESKI CHALKASHLIKNI TOZALASH
--    Bu fayl ishga tushgunga qadar ochiq qolib ketgan bronlar
--    ham yopiladi — xona bandligi rostga chiqsin.
-- ------------------------------------------------------------
DO $$
DECLARE v_soni int;
BEGIN
  WITH mos AS (
    SELECT DISTINCT ON (br.id) br.id AS bron_id, y.id AS yotqizish_id
      FROM bronlar br
      JOIN yotqizishlar y ON y.holat <> 'bekor'
      JOIN bemorlar b     ON b.id = y.bemor_id
     WHERE br.holat = 'kutilmoqda'
       AND br.yotqizish_id IS NULL
       AND b.telefon IS NOT NULL
       AND tel_raqam(br.telefon) = tel_raqam(b.telefon)
       AND nom_mos(br.ismi, btrim(b.familiya || ' ' || b.ism))
     ORDER BY br.id, abs(br.kirish - y.kirish_sana)
  )
  UPDATE bronlar br
     SET holat        = 'qabul_qilindi',
         yotqizish_id = mos.yotqizish_id,
         izoh         = btrim(COALESCE(br.izoh || ' ', '')
                        || '(Keyinchalik topildi: bemor allaqachon roʻyxatda edi)')
    FROM mos WHERE mos.bron_id = br.id;

  GET DIAGNOSTICS v_soni = ROW_COUNT;
  IF v_soni > 0 THEN
    RAISE NOTICE 'Ochiq qolib ketgan % ta bron yotqizishga bogʻlandi.', v_soni;
  ELSE
    RAISE NOTICE 'Bogʻlanmagan bron topilmadi — hammasi joyida.';
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
