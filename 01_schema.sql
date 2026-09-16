-- ============================================================
--  MUHIDDIN TABIB — Bemorlar va xonalarni boshqarish tizimi
--  PostgreSQL sxemasi (Supabase yoki oddiy Postgres uchun)
-- ============================================================
--  Bu faylni bir marta ishga tushiring. Barcha biznes qoidalar
--  BAZA ICHIDA yozilgan — frontend xato qilsa ham baza o'tkazmaydi.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;   -- koyka bandligi cheklovi uchun

-- ------------------------------------------------------------
-- 1. TARIFLAR  (o'zgaruvchan narxlar — kodda emas, bazada)
-- ------------------------------------------------------------
CREATE TABLE tariflar (
  kalit        text PRIMARY KEY,
  qiymat       numeric(12,0) NOT NULL,
  izoh         text
);

INSERT INTO tariflar (kalit, qiymat, izoh) VALUES
  ('yosh_5',     700000,  '5 yoshgacha, 1 kurs'),
  ('yosh_10',   1200000,  '10 yoshgacha, 1 kurs'),
  ('yosh_15',   1500000,  '15 yoshgacha, 1 kurs'),
  ('kattalar',  2000000,  'DIQQAT: TZ da yo''q, mijoz bilan aniqlanadi'),
  ('qarovchi',  1000000,  'Qarovchi, 1 kurs'),
  ('chet_el',    200000,  'Chet el fuqarosi uchun qo''shimcha'),
  ('kurs_kun',       10,  '1 kurs necha kun');

-- ------------------------------------------------------------
-- 2. BO'LIMLAR
-- ------------------------------------------------------------
CREATE TYPE jins_turi AS ENUM ('erkak', 'ayol');
CREATE TYPE bolim_jinsi AS ENUM ('erkak', 'ayol', 'aralash');

CREATE TABLE bolimlar (
  id           smallserial PRIMARY KEY,
  nomi         text NOT NULL UNIQUE,
  jins         bolim_jinsi NOT NULL,
  tartib       smallint DEFAULT 0
);

INSERT INTO bolimlar (nomi, jins, tartib) VALUES
  ('Erkaklar bo''limi', 'erkak',   1),
  ('Ayollar bo''limi',  'ayol',    2),
  ('Oilaviy bo''lim',   'aralash', 3),
  ('Premium bo''lim',   'aralash', 4);

-- ------------------------------------------------------------
-- 3. XONALAR  (bo'limdan tashqarida xona bo'lmaydi — NOT NULL FK)
-- ------------------------------------------------------------
CREATE TABLE xonalar (
  id           serial PRIMARY KEY,
  bolim_id     smallint NOT NULL REFERENCES bolimlar(id),
  raqam        text NOT NULL UNIQUE,
  turi         text NOT NULL DEFAULT 'Standart',
  narx         numeric(12,0) NOT NULL DEFAULT 0,   -- 1 kurs uchun
  tamirlashda  boolean NOT NULL DEFAULT false,
  izoh         text
);

-- ------------------------------------------------------------
-- 4. KOYKALAR  (xonadagi har bir joy alohida yozuv)
--    Sig'im shu yerdan kelib chiqadi: 3 koyka = 3 kishilik xona.
--    Bandlik cheklovi aynan koyka darajasida ishlaydi.
-- ------------------------------------------------------------
CREATE TABLE koykalar (
  id           serial PRIMARY KEY,
  xona_id      integer NOT NULL REFERENCES xonalar(id) ON DELETE CASCADE,
  raqam        smallint NOT NULL,
  UNIQUE (xona_id, raqam)
);

-- Xonaga koykalarni avtomatik yaratish uchun yordamchi
CREATE OR REPLACE FUNCTION xona_yarat(
  p_bolim text, p_raqam text, p_turi text, p_sigim int, p_narx numeric
) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_xona integer; v_bolim smallint;
BEGIN
  SELECT id INTO v_bolim FROM bolimlar WHERE nomi = p_bolim;
  IF v_bolim IS NULL THEN
    RAISE EXCEPTION 'Bo''lim topilmadi: %', p_bolim;
  END IF;
  INSERT INTO xonalar (bolim_id, raqam, turi, narx)
  VALUES (v_bolim, p_raqam, p_turi, p_narx) RETURNING id INTO v_xona;
  INSERT INTO koykalar (xona_id, raqam)
  SELECT v_xona, g FROM generate_series(1, p_sigim) g;
  RETURN v_xona;
END $$;

-- ------------------------------------------------------------
-- 5. BEMORLAR  (shaxs — tashrifdan ALOHIDA)
--    Bir bemor bir necha marta keladi. Shuning uchun
--    bemor va yotqizish ikki xil jadval.
-- ------------------------------------------------------------
CREATE TABLE bemorlar (
  id            serial PRIMARY KEY,
  familiya      text NOT NULL,
  ism           text NOT NULL,
  otasining_ismi text,
  jins          jins_turi NOT NULL,
  telefon       text NOT NULL,
  tugilgan_sana date,
  yosh          smallint,                  -- tug'ilgan sana yo'q bo'lsa
  fuqaroligi    text DEFAULT 'O''zbekiston',
  chet_el       boolean NOT NULL DEFAULT false,
  yaratilgan    timestamptz NOT NULL DEFAULT now(),
  CHECK (tugilgan_sana IS NOT NULL OR yosh IS NOT NULL)
);

-- Telefon unique — LEKIN faqat asosiy bemorlar uchun.
-- Farzand va qarovchi ota-onasining raqamidan foydalanadi,
-- shuning uchun qattiq UNIQUE qo'yib bo'lmaydi. Ogohlantirish
-- frontendda beriladi, baza esa faqat indeks bilan tez qidiradi.
CREATE INDEX ON bemorlar (telefon);
CREATE INDEX ON bemorlar (lower(familiya), lower(ism));

CREATE OR REPLACE FUNCTION bemor_yoshi(b bemorlar) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(
    CASE WHEN b.tugilgan_sana IS NOT NULL
         THEN date_part('year', age(current_date, b.tugilgan_sana))::int END,
    b.yosh)
$$;

-- ------------------------------------------------------------
-- 6. YOTQIZISHLAR  (tashrif / admission — tizimning yuragi)
-- ------------------------------------------------------------
CREATE TYPE shaxs_roli AS ENUM ('bemor', 'farzand', 'qarovchi');
CREATE TYPE yotqizish_holati AS ENUM ('yotmoqda', 'chiqdi', 'bekor');

CREATE TABLE yotqizishlar (
  id               serial PRIMARY KEY,
  bemor_id         integer NOT NULL REFERENCES bemorlar(id),
  koyka_id         integer NOT NULL REFERENCES koykalar(id),
  roli             shaxs_roli NOT NULL DEFAULT 'bemor',
  asosiy_id        integer REFERENCES yotqizishlar(id),  -- farzand/qarovchi kimga biriktirilgan

  kirish_sana      date NOT NULL DEFAULT current_date,
  kirish_vaqt      time NOT NULL DEFAULT localtime,
  reja_chiqish     date NOT NULL,
  haqiqiy_chiqish  timestamptz,            -- NULL = hali yotibdi

  holat            yotqizish_holati NOT NULL DEFAULT 'yotmoqda',
  summa            numeric(12,0) NOT NULL DEFAULT 0,   -- bemor/qarovchi tarifi
  xona_summa       numeric(12,0) NOT NULL DEFAULT 0,   -- xona narxi (birinchi bemorga)
  izoh             text,
  yaratilgan       timestamptz NOT NULL DEFAULT now(),

  CHECK (reja_chiqish > kirish_sana),

  -- Koyka qachon band: haqiqiy chiqish bo'lsa — o'sha kungacha,
  -- bo'lmasa — rejadagi sanagacha. Generated column, doim to'g'ri.
  band_davri daterange GENERATED ALWAYS AS (
    daterange(kirish_sana,
      GREATEST(kirish_sana + 1,
        COALESCE((haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, reja_chiqish)),
      '[)')
  ) STORED
);

-- ⭐ ASOSIY CHEKLOV: bitta koykada bir vaqtda ikki kishi yotolmaydi.
-- Bu baza darajasida ishlaydi — dastur xato qilsa ham o'tmaydi.
--
-- DIQQAT: cheklov faqat FAOL yotqizishlarga qo'llanadi. Sababi —
-- bemor bugun chiqib ketsa, o'sha koykaga bugunoq yangi bemorni
-- joylashtirish mumkin bo'lishi kerak (amalda tez-tez uchraydi).
-- Chiqib ketganlar tarix bo'lib qoladi va yangi joylashtirishga
-- to'sqinlik qilmaydi.
ALTER TABLE yotqizishlar ADD CONSTRAINT koyka_band_emas
  EXCLUDE USING gist (koyka_id WITH =, band_davri WITH &&)
  WHERE (holat = 'yotmoqda');

CREATE INDEX ON yotqizishlar (bemor_id);
CREATE INDEX ON yotqizishlar (holat) WHERE holat = 'yotmoqda';

-- ------------------------------------------------------------
-- 7. TO'LOVLAR  (ledger — hech qachon o'chirilmaydi/o'zgartirilmaydi)
-- ------------------------------------------------------------
CREATE TYPE tolov_usuli AS ENUM ('naqd', 'karta', 'otkazma');

CREATE TABLE tolovlar (
  id            serial PRIMARY KEY,
  yotqizish_id  integer NOT NULL REFERENCES yotqizishlar(id),
  summa         numeric(12,0) NOT NULL CHECK (summa <> 0),
  usuli         tolov_usuli NOT NULL DEFAULT 'naqd',
  sana          date NOT NULL DEFAULT current_date,
  izoh          text,
  kim           text,                       -- kassir
  yaratilgan    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON tolovlar (yotqizish_id);

-- Qarzni HECH QACHON alohida maydonda saqlamaymiz — doim hisoblaymiz.
CREATE OR REPLACE FUNCTION tolangan(p_yotqizish int) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(summa), 0) FROM tolovlar WHERE yotqizish_id = p_yotqizish
$$;

CREATE OR REPLACE FUNCTION qarz(p_yotqizish int) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT GREATEST(0, y.summa + y.xona_summa - tolangan(y.id))
  FROM yotqizishlar y WHERE y.id = p_yotqizish
$$;

-- ------------------------------------------------------------
-- 8. BRONLAR
-- ------------------------------------------------------------
CREATE TYPE bron_holati AS ENUM ('kutilmoqda', 'qabul_qilindi', 'kelmadi', 'bekor');

CREATE TABLE bronlar (
  id          serial PRIMARY KEY,
  ismi        text NOT NULL,
  telefon     text NOT NULL,
  bemor_id    integer REFERENCES bemorlar(id),
  bolim_id    smallint REFERENCES bolimlar(id),
  xona_id     integer REFERENCES xonalar(id),
  kirish      date NOT NULL,
  chiqish     date NOT NULL,
  kishi       smallint NOT NULL DEFAULT 1,
  guruh       text,                        -- oilaviy bron uchun umumiy kod
  holat       bron_holati NOT NULL DEFAULT 'kutilmoqda',
  izoh        text,
  yaratilgan  timestamptz NOT NULL DEFAULT now(),
  CHECK (chiqish > kirish)
);
CREATE INDEX ON bronlar (telefon);
CREATE INDEX ON bronlar (kirish);

-- ============================================================
--  BIZNES QOIDALAR — TRIGGERLAR
-- ============================================================

-- QOIDA 1: jins va bo'lim mosligi + ta'mirlashdagi xona
CREATE OR REPLACE FUNCTION trg_jins_tekshir() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_jins jins_turi; v_bolim bolim_jinsi; v_xona integer;
  v_raqam text; v_tamir boolean; v_boshqa text;
BEGIN
  SELECT b.jins INTO v_jins FROM bemorlar b WHERE b.id = NEW.bemor_id;
  SELECT x.id, x.raqam, x.tamirlashda, bo.jins
    INTO v_xona, v_raqam, v_tamir, v_bolim
  FROM koykalar k JOIN xonalar x ON x.id = k.xona_id
                  JOIN bolimlar bo ON bo.id = x.bolim_id
  WHERE k.id = NEW.koyka_id;

  IF v_tamir THEN
    RAISE EXCEPTION '% -xona ta''mirlashda, joylashtirish mumkin emas.', v_raqam
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_bolim <> 'aralash' AND v_bolim::text <> v_jins::text THEN
    RAISE EXCEPTION 'Bu xonaga ushbu bemorni joylashtirib bo''lmaydi. Xona bo''limi jinsi bo''yicha mos kelmaydi.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Aralash bo'limlarda (oilaviy/premium) xonadagi jins tekshirilmaydi
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

CREATE TRIGGER jins_tekshir
  BEFORE INSERT OR UPDATE OF koyka_id, bemor_id, reja_chiqish ON yotqizishlar
  FOR EACH ROW EXECUTE FUNCTION trg_jins_tekshir();

-- QOIDA 2: qarzdorlik bo'lsa chiqarib bo'lmaydi
CREATE OR REPLACE FUNCTION trg_qarz_tekshir() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_qarz numeric;
BEGIN
  IF NEW.haqiqiy_chiqish IS NOT NULL AND OLD.haqiqiy_chiqish IS NULL THEN
    SELECT GREATEST(0, NEW.summa + NEW.xona_summa - tolangan(NEW.id)) INTO v_qarz;
    IF v_qarz > 0 THEN
      RAISE EXCEPTION 'Bemorni chiqarish mumkin emas. To''lanmagan qarzdorlik mavjud: % so''m.',
        to_char(v_qarz, 'FM999G999G999')
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.holat := 'chiqdi';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER qarz_tekshir
  BEFORE UPDATE ON yotqizishlar
  FOR EACH ROW EXECUTE FUNCTION trg_qarz_tekshir();

-- ============================================================
--  NARX HISOBLASH
-- ============================================================
CREATE OR REPLACE FUNCTION narx_hisobla(p_yosh int, p_chet_el bool, p_roli shaxs_roli)
RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE v numeric;
BEGIN
  IF p_roli = 'qarovchi' THEN
    SELECT qiymat INTO v FROM tariflar WHERE kalit = 'qarovchi';
  ELSIF p_yosh <= 5  THEN SELECT qiymat INTO v FROM tariflar WHERE kalit = 'yosh_5';
  ELSIF p_yosh <= 10 THEN SELECT qiymat INTO v FROM tariflar WHERE kalit = 'yosh_10';
  ELSIF p_yosh <= 15 THEN SELECT qiymat INTO v FROM tariflar WHERE kalit = 'yosh_15';
  ELSE                    SELECT qiymat INTO v FROM tariflar WHERE kalit = 'kattalar';
  END IF;

  IF p_chet_el THEN
    v := v + (SELECT qiymat FROM tariflar WHERE kalit = 'chet_el');
  END IF;
  RETURN v;
END $$;

-- ============================================================
--  KO'RINISHLAR (VIEW) — hisobotlar shu yerdan oladi
-- ============================================================

-- Hozir yotayotganlar (ovqat hisobi ham shu yerdan)
CREATE VIEW v_hozir_yotganlar AS
SELECT y.id AS yotqizish_id, b.id AS bemor_id,
       b.familiya || ' ' || b.ism AS fish,
       b.jins, b.chet_el, y.roli,
       x.raqam AS xona, k.raqam AS koyka, bo.nomi AS bolim,
       y.kirish_sana, y.reja_chiqish,
       (current_date - y.kirish_sana + 1) AS kun,
       y.summa + y.xona_summa AS umumiy,
       tolangan(y.id) AS tolangan,
       qarz(y.id) AS qarz
FROM yotqizishlar y
  JOIN bemorlar b  ON b.id = y.bemor_id
  JOIN koykalar k  ON k.id = y.koyka_id
  JOIN xonalar x   ON x.id = k.xona_id
  JOIN bolimlar bo ON bo.id = x.bolim_id
WHERE y.holat = 'yotmoqda';

-- Xonalar holati
CREATE VIEW v_xona_holati AS
SELECT x.id, x.raqam, bo.nomi AS bolim, x.turi, x.narx,
       count(k.id) AS sigim,
       count(y.id) AS band,
       CASE
         WHEN x.tamirlashda           THEN 'tamir'
         WHEN count(y.id) = 0 AND EXISTS (
              SELECT 1 FROM bronlar br
              WHERE br.xona_id = x.id AND br.holat = 'kutilmoqda')
                                      THEN 'bron'
         WHEN count(y.id) = 0         THEN 'bosh'
         WHEN count(y.id) >= count(k.id) THEN 'toliq'
         ELSE 'qisman'
       END AS holat
FROM xonalar x
  JOIN bolimlar bo ON bo.id = x.bolim_id
  LEFT JOIN koykalar k ON k.xona_id = x.id
  LEFT JOIN yotqizishlar y ON y.koyka_id = k.id AND y.holat = 'yotmoqda'
GROUP BY x.id, x.raqam, bo.nomi, x.turi, x.narx, x.tamirlashda;

-- Qarzdorlar
CREATE VIEW v_qarzdorlar AS
SELECT y.id AS yotqizish_id, b.familiya || ' ' || b.ism AS fish, b.telefon,
       x.raqam AS xona, y.summa + y.xona_summa AS umumiy,
       tolangan(y.id) AS tolangan, qarz(y.id) AS qarz
FROM yotqizishlar y
  JOIN bemorlar b ON b.id = y.bemor_id
  JOIN koykalar k ON k.id = y.koyka_id
  JOIN xonalar x  ON x.id = k.xona_id
WHERE y.holat = 'yotmoqda' AND qarz(y.id) > 0;

-- ⭐ BRON KONFLIKTLARI
-- Bu qattiq cheklov EMAS, ogohlantirish. TZ shuni talab qiladi:
-- tizim aniqlaydi va administratorga xabar beradi.
CREATE VIEW v_bron_konfliktlari AS
SELECT br.id AS bron_id, br.ismi AS bron_bemor, br.kirish AS bron_kirish,
       x.raqam AS xona,
       b.familiya || ' ' || b.ism AS hozirgi_bemor,
       y.reja_chiqish AS hozirgi_chiqish,
       (y.reja_chiqish - br.kirish) AS kun_farq
FROM bronlar br
  JOIN xonalar x ON x.id = br.xona_id
  JOIN koykalar k ON k.xona_id = x.id
  JOIN yotqizishlar y ON y.koyka_id = k.id AND y.holat = 'yotmoqda'
  JOIN bemorlar b ON b.id = y.bemor_id
WHERE br.holat = 'kutilmoqda'
  AND y.reja_chiqish > br.kirish;

-- ⭐ XONA TAVSIYASI: berilgan sanada qaysi xonalar bo'shaydi
CREATE OR REPLACE FUNCTION bosh_xonalar(p_sana date, p_bolim smallint DEFAULT NULL)
RETURNS TABLE (xona_id int, xona text, bolim text, bosh_koyka bigint, bosh_sana date)
LANGUAGE sql STABLE AS $$
  SELECT x.id, x.raqam, bo.nomi,
         count(k.id) FILTER (WHERE y.id IS NULL) AS bosh_koyka,
         max(y.reja_chiqish) AS bosh_sana
  FROM xonalar x
    JOIN bolimlar bo ON bo.id = x.bolim_id
    JOIN koykalar k ON k.xona_id = x.id
    LEFT JOIN yotqizishlar y
      ON y.koyka_id = k.id AND y.holat = 'yotmoqda'
     AND y.band_davri @> p_sana
  WHERE NOT x.tamirlashda
    AND (p_bolim IS NULL OR x.bolim_id = p_bolim)
  GROUP BY x.id, x.raqam, bo.nomi
  HAVING count(k.id) FILTER (WHERE y.id IS NULL) > 0
  ORDER BY bosh_koyka DESC, x.raqam;
$$;

-- ============================================================
--  AMALLAR (RPC) — frontend faqat shularni chaqiradi
-- ============================================================

-- Bemorni qabul qilish va joylashtirish (bitta tranzaksiyada)
CREATE OR REPLACE FUNCTION bemor_joylashtir(
  p_familiya text, p_ism text, p_jins jins_turi, p_telefon text,
  p_yosh int, p_chet_el boolean, p_roli shaxs_roli,
  p_koyka int, p_kirish date, p_reja_chiqish date,
  p_oldindan numeric DEFAULT 0, p_asosiy int DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
  v_bemor int; v_yotqizish int; v_summa numeric; v_xona_summa numeric := 0;
  v_xona int; v_band int;
BEGIN
  INSERT INTO bemorlar (familiya, ism, jins, telefon, yosh, chet_el,
                        fuqaroligi)
  VALUES (p_familiya, p_ism, p_jins, p_telefon, p_yosh, p_chet_el,
          CASE WHEN p_chet_el THEN 'Chet el fuqarosi' ELSE 'O''zbekiston' END)
  RETURNING id INTO v_bemor;

  v_summa := narx_hisobla(p_yosh, p_chet_el, p_roli);

  -- Xona narxi faqat xonaga birinchi kirgan bemorga yoziladi
  SELECT k.xona_id INTO v_xona FROM koykalar k WHERE k.id = p_koyka;
  SELECT count(*) INTO v_band
  FROM yotqizishlar y JOIN koykalar k2 ON k2.id = y.koyka_id
  WHERE k2.xona_id = v_xona AND y.holat = 'yotmoqda';

  IF v_band = 0 AND p_roli = 'bemor' THEN
    SELECT narx INTO v_xona_summa FROM xonalar WHERE id = v_xona;
  END IF;

  INSERT INTO yotqizishlar (bemor_id, koyka_id, roli, asosiy_id,
                            kirish_sana, reja_chiqish, summa, xona_summa)
  VALUES (v_bemor, p_koyka, p_roli, p_asosiy,
          p_kirish, p_reja_chiqish, v_summa, v_xona_summa)
  RETURNING id INTO v_yotqizish;

  IF p_oldindan > 0 THEN
    INSERT INTO tolovlar (yotqizish_id, summa, sana, izoh)
    VALUES (v_yotqizish, p_oldindan, p_kirish, 'Oldindan to''lov');
  END IF;

  RETURN v_yotqizish;
END $$;

-- Bemorni chiqarish (haqiqiy sana bo'yicha)
CREATE OR REPLACE FUNCTION bemor_chiqar(
  p_yotqizish int, p_vaqt timestamptz DEFAULT now()
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE yotqizishlar
     SET haqiqiy_chiqish = p_vaqt
   WHERE id = p_yotqizish AND holat = 'yotmoqda';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi yoki bemor allaqachon chiqarilgan.';
  END IF;
END $$;

-- To'lov qabul qilish
CREATE OR REPLACE FUNCTION tolov_qosh(
  p_yotqizish int, p_summa numeric, p_usuli tolov_usuli DEFAULT 'naqd',
  p_kim text DEFAULT NULL
) RETURNS numeric LANGUAGE plpgsql AS $$
BEGIN
  IF p_summa <= 0 THEN
    RAISE EXCEPTION 'To''lov summasi noldan katta bo''lishi kerak.';
  END IF;
  INSERT INTO tolovlar (yotqizish_id, summa, usuli, kim)
  VALUES (p_yotqizish, p_summa, p_usuli, p_kim);
  RETURN qarz(p_yotqizish);        -- qolgan qarzni qaytaradi
END $$;

-- Muddatni uzaytirish + konflikt ogohlantirishi
CREATE OR REPLACE FUNCTION muddat_uzaytir(p_yotqizish int, p_yangi date)
RETURNS TABLE (ogohlantirish text) LANGUAGE plpgsql AS $$
DECLARE v_xona int;
BEGIN
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

-- Qarovchini bemorga aylantirish
CREATE OR REPLACE FUNCTION qarovchini_bemorga(p_yotqizish int)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE
  v_kun int; v_saqlangan numeric; v_yangi numeric; v_yosh int; v_chet bool;
  v_kurs numeric; v_qarovchi numeric;
BEGIN
  SELECT (current_date - y.kirish_sana + 1), bemor_yoshi(b), b.chet_el
    INTO v_kun, v_yosh, v_chet
  FROM yotqizishlar y JOIN bemorlar b ON b.id = y.bemor_id
  WHERE y.id = p_yotqizish AND y.roli = 'qarovchi';

  IF v_kun IS NULL THEN
    RAISE EXCEPTION 'Bu yotqizish qarovchi emas yoki topilmadi.';
  END IF;

  SELECT qiymat INTO v_kurs     FROM tariflar WHERE kalit = 'kurs_kun';
  SELECT qiymat INTO v_qarovchi FROM tariflar WHERE kalit = 'qarovchi';

  v_saqlangan := round(v_qarovchi / v_kurs * v_kun);
  v_yangi := narx_hisobla(v_yosh, v_chet, 'bemor');

  UPDATE yotqizishlar
     SET roli = 'bemor', summa = v_saqlangan + v_yangi,
         izoh = coalesce(izoh || ' | ', '') ||
                format('Qarovchi → Bemor (%s kunlik qarovchi to''lovi saqlandi)', v_kun)
   WHERE id = p_yotqizish;

  RETURN v_saqlangan + v_yangi;
END $$;
