-- ============================================================
--  02_ROLLAR.sql — Rollar, huquqlar, xonasiz bemor, chek
--  01_schema.sql dan KEYIN ishga tushiriladi.
-- ============================================================

-- ------------------------------------------------------------
-- 1. XONASIZ BEMOR
--    Bemor doim ham xona band qilmaydi. koyka_id endi ixtiyoriy.
-- ------------------------------------------------------------
ALTER TABLE yotqizishlar ALTER COLUMN koyka_id DROP NOT NULL;

-- Cheklovni qayta yozamiz: koyka biriktirilmagan bemorlar
-- bandlik hisobiga umuman kirmaydi.
ALTER TABLE yotqizishlar DROP CONSTRAINT koyka_band_emas;
ALTER TABLE yotqizishlar ADD CONSTRAINT koyka_band_emas
  EXCLUDE USING gist (koyka_id WITH =, band_davri WITH &&)
  WHERE (holat = 'yotmoqda' AND koyka_id IS NOT NULL);

-- Jins tekshiruvi ham koyka bo'lmasa o'tkazib yuboriladi
CREATE OR REPLACE FUNCTION trg_jins_tekshir() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_jins jins_turi; v_bolim bolim_jinsi; v_xona integer;
  v_raqam text; v_tamir boolean; v_boshqa text;
BEGIN
  IF NEW.koyka_id IS NULL THEN
    RETURN NEW;                      -- xonasiz bemor, tekshiruv shart emas
  END IF;

  SELECT b.jins INTO v_jins FROM bemorlar b WHERE b.id = NEW.bemor_id;
  SELECT x.id, x.raqam, x.tamirlashda, bo.jins
    INTO v_xona, v_raqam, v_tamir, v_bolim
  FROM koykalar k JOIN xonalar x ON x.id = k.xona_id
                  JOIN bolimlar bo ON bo.id = x.bolim_id
  WHERE k.id = NEW.koyka_id;

  IF v_tamir THEN
    RAISE EXCEPTION '%-xona ta''mirlashda, joylashtirish mumkin emas.', v_raqam
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_bolim <> 'aralash' AND v_bolim::text <> v_jins::text THEN
    RAISE EXCEPTION 'Bu xonaga ushbu bemorni joylashtirib bo''lmaydi. Xona bo''limi jinsi bo''yicha mos kelmaydi.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_bolim <> 'aralash' THEN
    SELECT string_agg(bm.familiya || ' ' || bm.ism, ', ') INTO v_boshqa
    FROM yotqizishlar y
      JOIN koykalar k2 ON k2.id = y.koyka_id
      JOIN bemorlar bm ON bm.id = y.bemor_id
    WHERE k2.xona_id = v_xona
      AND y.holat = 'yotmoqda'
      AND y.id <> COALESCE(NEW.id, -1)
      AND bm.jins <> v_jins
      AND y.band_davri && daterange(NEW.kirish_sana,
            GREATEST(NEW.kirish_sana + 1,
              COALESCE((NEW.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                       NEW.reja_chiqish)), '[)');
    IF v_boshqa IS NOT NULL THEN
      RAISE EXCEPTION 'Bu xonaga ushbu bemorni joylashtirib bo''lmaydi. Xona mavjud bemorlar jinsi bo''yicha mos kelmaydi (%).', v_boshqa
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 2. ROLLAR
-- ------------------------------------------------------------
CREATE TYPE rol_turi AS ENUM ('super_admin', 'administrator', 'buxgalter', 'viewer');

CREATE TABLE xodimlar (
  id          serial PRIMARY KEY,
  auth_id     uuid UNIQUE,              -- Supabase auth.users.id
  fish        text NOT NULL,
  rol         rol_turi NOT NULL DEFAULT 'viewer',
  telefon     text,
  faol        boolean NOT NULL DEFAULT true,
  yaratilgan  timestamptz NOT NULL DEFAULT now()
);

-- Joriy foydalanuvchi roli.
-- Supabase'da auth.uid() orqali, mahalliy testda app.rol orqali ishlaydi.
CREATE OR REPLACE FUNCTION joriy_rol() RETURNS rol_turi
LANGUAGE plpgsql STABLE AS $$
DECLARE v_uid uuid; v_rol rol_turi;
BEGIN
  BEGIN
    EXECUTE 'SELECT auth.uid()' INTO v_uid;
  EXCEPTION WHEN OTHERS THEN
    v_uid := NULL;
  END;

  IF v_uid IS NOT NULL THEN
    SELECT rol INTO v_rol FROM xodimlar WHERE auth_id = v_uid AND faol;
    RETURN v_rol;                       -- topilmasa NULL = huquq yo'q
  END IF;

  RETURN NULLIF(current_setting('app.rol', true), '')::rol_turi;
END $$;

CREATE OR REPLACE FUNCTION joriy_fish() RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE v_uid uuid; v_fish text;
BEGIN
  BEGIN EXECUTE 'SELECT auth.uid()' INTO v_uid;
  EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;
  IF v_uid IS NOT NULL THEN
    SELECT fish INTO v_fish FROM xodimlar WHERE auth_id = v_uid;
    RETURN v_fish;
  END IF;
  RETURN COALESCE(NULLIF(current_setting('app.fish', true), ''), 'tizim');
END $$;

-- Huquq tekshiruvi
CREATE OR REPLACE FUNCTION huquq_tekshir(p_ruxsat rol_turi[], p_amal text)
RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE v rol_turi := joriy_rol();
BEGIN
  IF v IS NULL THEN
    RAISE EXCEPTION 'Tizimga kirilmagan yoki xodim faol emas.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT (v = ANY(p_ruxsat)) THEN
    RAISE EXCEPTION 'Sizda "%" amalini bajarish huquqi yo''q (rolingiz: %).', p_amal, v
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

-- ============================================================
--  HUQUQLAR TAQSIMOTI
--    super_admin   — hammasi
--    administrator — ro'yxatga oladi, joylashtiradi, uzaytiradi,
--                    "Chiqdi" qiladi (qarz bo'lmasa). Pulga tegmaydi.
--    buxgalter     — to'lov qabul qiladi, chek chiqaradi,
--                    "Chiqdi" qiladi. Ro'yxatga olmaydi.
--    viewer        — faqat ko'radi.
-- ============================================================

CREATE OR REPLACE FUNCTION bemor_joylashtir(
  p_familiya text, p_ism text, p_jins jins_turi, p_telefon text,
  p_yosh int, p_chet_el boolean, p_roli shaxs_roli,
  p_koyka int, p_kirish date, p_reja_chiqish date,
  p_oldindan numeric DEFAULT 0, p_asosiy int DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_bemor int; v_yotqizish int; v_summa numeric; v_xona_summa numeric := 0;
  v_xona int; v_band int;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bemorni ro''yxatga olish');

  INSERT INTO bemorlar (familiya, ism, jins, telefon, yosh, chet_el, fuqaroligi)
  VALUES (p_familiya, p_ism, p_jins, p_telefon, p_yosh, p_chet_el,
          CASE WHEN p_chet_el THEN 'Chet el fuqarosi' ELSE 'O''zbekiston' END)
  RETURNING id INTO v_bemor;

  v_summa := narx_hisobla(p_yosh, p_chet_el, p_roli);

  -- Xona narxi faqat koyka biriktirilgan va xonaga birinchi kirgan bemorga
  IF p_koyka IS NOT NULL THEN
    SELECT k.xona_id INTO v_xona FROM koykalar k WHERE k.id = p_koyka;
    SELECT count(*) INTO v_band
    FROM yotqizishlar y JOIN koykalar k2 ON k2.id = y.koyka_id
    WHERE k2.xona_id = v_xona AND y.holat = 'yotmoqda';
    IF v_band = 0 AND p_roli = 'bemor' THEN
      SELECT narx INTO v_xona_summa FROM xonalar WHERE id = v_xona;
    END IF;
  END IF;

  INSERT INTO yotqizishlar (bemor_id, koyka_id, roli, asosiy_id,
                            kirish_sana, reja_chiqish, summa, xona_summa)
  VALUES (v_bemor, p_koyka, p_roli, p_asosiy,
          p_kirish, p_reja_chiqish, v_summa, v_xona_summa)
  RETURNING id INTO v_yotqizish;

  -- Oldindan to'lovni faqat pul huquqi borlar kirita oladi
  IF p_oldindan > 0 THEN
    PERFORM huquq_tekshir(ARRAY['super_admin','buxgalter']::rol_turi[],
                          'oldindan to''lovni kiritish');
    INSERT INTO tolovlar (yotqizish_id, summa, sana, izoh, kim)
    VALUES (v_yotqizish, p_oldindan, p_kirish, 'Oldindan to''lov', joriy_fish());
  END IF;

  RETURN v_yotqizish;
END $$;

-- Keyinchalik koyka biriktirish / o'zgartirish (xonasiz kelgan bemorga)
CREATE OR REPLACE FUNCTION koyka_biriktir(p_yotqizish int, p_koyka int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_xona int; v_band int; v_narx numeric;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'xonaga joylashtirish');

  IF p_koyka IS NOT NULL THEN
    SELECT k.xona_id INTO v_xona FROM koykalar k WHERE k.id = p_koyka;
    SELECT count(*) INTO v_band
    FROM yotqizishlar y JOIN koykalar k2 ON k2.id = y.koyka_id
    WHERE k2.xona_id = v_xona AND y.holat = 'yotmoqda' AND y.id <> p_yotqizish;

    IF v_band = 0 THEN
      SELECT narx INTO v_narx FROM xonalar WHERE id = v_xona;
      UPDATE yotqizishlar SET xona_summa = v_narx
       WHERE id = p_yotqizish AND roli = 'bemor' AND xona_summa = 0;
    END IF;
  END IF;

  UPDATE yotqizishlar SET koyka_id = p_koyka
   WHERE id = p_yotqizish AND holat = 'yotmoqda';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi yoki bemor chiqib ketgan.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION bemor_chiqar(
  p_yotqizish int, p_vaqt timestamptz DEFAULT now()
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM huquq_tekshir(
    ARRAY['super_admin','administrator','buxgalter']::rol_turi[],
    'bemorni chiqarish');

  UPDATE yotqizishlar SET haqiqiy_chiqish = p_vaqt
   WHERE id = p_yotqizish AND holat = 'yotmoqda';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi yoki bemor allaqachon chiqarilgan.';
  END IF;
END $$;

-- Eski versiyani o'chiramiz: qaytariladigan tur o'zgardi
-- (avval qolgan qarzni qaytarardi, endi chek uchun to'lov id sini)
DROP FUNCTION IF EXISTS tolov_qosh(int, numeric, tolov_usuli, text);

CREATE OR REPLACE FUNCTION tolov_qosh(
  p_yotqizish int, p_summa numeric, p_usuli tolov_usuli DEFAULT 'naqd',
  p_kim text DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_id integer;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','buxgalter']::rol_turi[],
                        'to''lov qabul qilish');
  IF p_summa <= 0 THEN
    RAISE EXCEPTION 'To''lov summasi noldan katta bo''lishi kerak.';
  END IF;

  INSERT INTO tolovlar (yotqizish_id, summa, usuli, kim)
  VALUES (p_yotqizish, p_summa, p_usuli, COALESCE(p_kim, joriy_fish()))
  RETURNING id INTO v_id;

  RETURN v_id;                  -- chek shu id bo'yicha chiqariladi
END $$;

CREATE OR REPLACE FUNCTION muddat_uzaytir(p_yotqizish int, p_yangi date)
RETURNS TABLE (ogohlantirish text) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_xona int;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'muddatni uzaytirish');

  UPDATE yotqizishlar SET reja_chiqish = p_yangi
   WHERE id = p_yotqizish AND holat = 'yotmoqda';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.';
  END IF;

  SELECT k.xona_id INTO v_xona
  FROM yotqizishlar y JOIN koykalar k ON k.id = y.koyka_id
  WHERE y.id = p_yotqizish;

  RETURN QUERY
  SELECT format('DIQQAT! %s-xona %s kuni %s uchun bron qilingan. Yangi joy topish kerak.',
                x.raqam, to_char(br.kirish, 'DD.MM.YYYY'), br.ismi)
  FROM bronlar br JOIN xonalar x ON x.id = br.xona_id
  WHERE br.xona_id = v_xona AND br.holat = 'kutilmoqda' AND br.kirish < p_yangi;
END $$;

-- ------------------------------------------------------------
-- 3. CHEK
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION chek(p_tolov int)
RETURNS TABLE (
  chek_raqam   text,
  familiya     text,
  ism          text,
  telefon      text,
  xona         text,
  koyka        smallint,
  kelgan       timestamp,
  tolov_vaqti  timestamptz,
  summa        numeric,
  usuli        tolov_usuli,
  umumiy       numeric,
  tolangan     numeric,
  qolgan_qarz  numeric,
  kassir       text
) LANGUAGE sql STABLE AS $$
  SELECT
    'CHK-' || lpad(t.id::text, 6, '0'),
    b.familiya, b.ism, b.telefon,
    COALESCE(x.raqam, '—'),
    k.raqam,
    (y.kirish_sana + y.kirish_vaqt)::timestamp,
    t.yaratilgan,
    t.summa,
    t.usuli,
    y.summa + y.xona_summa,
    tolangan(y.id),
    qarz(y.id),
    COALESCE(t.kim, '—')
  FROM tolovlar t
    JOIN yotqizishlar y ON y.id = t.yotqizish_id
    JOIN bemorlar b     ON b.id = y.bemor_id
    LEFT JOIN koykalar k ON k.id = y.koyka_id
    LEFT JOIN xonalar x  ON x.id = k.xona_id
  WHERE t.id = p_tolov;
$$;

-- ------------------------------------------------------------
-- 4. KO'RINISHLARNI YANGILAYMIZ (xonasiz bemorlar ham chiqsin)
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_hozir_yotganlar CASCADE;
CREATE VIEW v_hozir_yotganlar AS
SELECT y.id AS yotqizish_id, b.id AS bemor_id,
       b.familiya || ' ' || b.ism AS fish,
       b.jins, b.telefon, b.chet_el, y.roli,
       x.raqam AS xona, k.raqam AS koyka, bo.nomi AS bolim,
       (y.koyka_id IS NOT NULL) AS xonada,
       y.kirish_sana, y.kirish_vaqt, y.reja_chiqish,
       (current_date - y.kirish_sana + 1) AS kun,
       y.summa + y.xona_summa AS umumiy,
       tolangan(y.id) AS tolangan,
       qarz(y.id) AS qarz
FROM yotqizishlar y
  JOIN bemorlar b   ON b.id = y.bemor_id
  LEFT JOIN koykalar k  ON k.id = y.koyka_id
  LEFT JOIN xonalar x   ON x.id = k.xona_id
  LEFT JOIN bolimlar bo ON bo.id = x.bolim_id
WHERE y.holat = 'yotmoqda';

DROP VIEW IF EXISTS v_qarzdorlar CASCADE;
CREATE VIEW v_qarzdorlar AS
SELECT y.id AS yotqizish_id, b.familiya || ' ' || b.ism AS fish, b.telefon,
       COALESCE(x.raqam, '—') AS xona,
       y.summa + y.xona_summa AS umumiy,
       tolangan(y.id) AS tolangan, qarz(y.id) AS qarz
FROM yotqizishlar y
  JOIN bemorlar b ON b.id = y.bemor_id
  LEFT JOIN koykalar k ON k.id = y.koyka_id
  LEFT JOIN xonalar x  ON x.id = k.xona_id
WHERE y.holat = 'yotmoqda' AND qarz(y.id) > 0;

-- ------------------------------------------------------------
-- 5. RLS — jadvallarga to'g'ridan-to'g'ri yozish TAQIQLANADI.
--    Barcha o'zgartirishlar yuqoridagi funksiyalar orqali ketadi.
-- ------------------------------------------------------------
ALTER TABLE bemorlar     ENABLE ROW LEVEL SECURITY;
ALTER TABLE yotqizishlar ENABLE ROW LEVEL SECURITY;
ALTER TABLE tolovlar     ENABLE ROW LEVEL SECURITY;
ALTER TABLE bronlar      ENABLE ROW LEVEL SECURITY;
ALTER TABLE xonalar      ENABLE ROW LEVEL SECURITY;
ALTER TABLE koykalar     ENABLE ROW LEVEL SECURITY;
ALTER TABLE bolimlar     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tariflar     ENABLE ROW LEVEL SECURITY;
ALTER TABLE xodimlar     ENABLE ROW LEVEL SECURITY;

-- Ko'rish: barcha faol xodimlar
CREATE POLICY korish ON bemorlar     FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON yotqizishlar FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON tolovlar     FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON bronlar      FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON xonalar      FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON koykalar     FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON bolimlar     FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON tariflar     FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE POLICY korish ON xodimlar     FOR SELECT USING (joriy_rol() IS NOT NULL);

-- Bronlarni administrator boshqaradi
CREATE POLICY bron_yozish ON bronlar FOR ALL
  USING (joriy_rol() IN ('super_admin','administrator'))
  WITH CHECK (joriy_rol() IN ('super_admin','administrator'));

-- Xona, tarif, xodim — faqat super_admin
CREATE POLICY sa_xona  ON xonalar  FOR ALL
  USING (joriy_rol() = 'super_admin') WITH CHECK (joriy_rol() = 'super_admin');
CREATE POLICY sa_koyka ON koykalar FOR ALL
  USING (joriy_rol() = 'super_admin') WITH CHECK (joriy_rol() = 'super_admin');
CREATE POLICY sa_tarif ON tariflar FOR ALL
  USING (joriy_rol() = 'super_admin') WITH CHECK (joriy_rol() = 'super_admin');
CREATE POLICY sa_xodim ON xodimlar FOR ALL
  USING (joriy_rol() = 'super_admin') WITH CHECK (joriy_rol() = 'super_admin');
