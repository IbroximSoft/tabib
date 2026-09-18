/* ============================================================
   HUDUDLAR — Oʻzbekiston viloyatlari va tumanlari, bemorni
   roʻyxatga olishda manzil tanlash uchun.

   Bemor chet el fuqarosi boʻlsa, shu joyda viloyat oʻrniga
   MDH (SNG) davlatlari roʻyxati koʻrsatiladi — Sozlamalar.jsx
   yoki bemor_qabul() ga tegilmaydi, faqat shu forma ichida
   ishlatiladi.
   ============================================================ */

export const VILOYATLAR = [
  {
    nomi: 'Qoraqalpogʻiston Respublikasi',
    tumanlar: [
      'Amudaryo', 'Beruniy', 'Bozatov', 'Shimbay', 'Ellikqala', 'Kegeyli',
      'Moynoq', 'Nukus tumani', 'Nukus shahri', 'Qanlikoʻl', 'Qoʻngʻirot', 'Qoraoʻzak',
      'Shumanay', 'Taqiyatosh', 'Taxtakoʻpir', 'Toʻrtkoʻl', 'Xoʻjayli'
    ]
  },
  {
    nomi: 'Andijon viloyati',
    tumanlar: [
      'Andijon tumani', 'Andijon shahri', 'Asaka', 'Baliqchi', 'Boʻston', 'Buloqboshi',
      'Izboskan', 'Jalaquduq', 'Xoʻjaobod', 'Qoʻrgʻontepa', 'Marhamat',
      'Oltinkoʻl', 'Paxtaobod', 'Shahrixon', 'Ulugʻnor'
    ]
  },
  {
    nomi: 'Buxoro viloyati',
    tumanlar: [
      'Olot', 'Buxoro tumani', 'Buxoro shahri', 'Gʻijduvon', 'Jondor', 'Kogon', 'Qorakoʻl',
      'Qorovulbozor', 'Peshku', 'Romitan', 'Shofirkon', 'Vobkent'
    ]
  },
  {
    nomi: 'Fargʻona viloyati',
    tumanlar: [
      'Oltiariq', 'Bagʻdod', 'Beshariq', 'Buvayda', 'Dangʻara',
      'Fargʻona tumani', 'Fargʻona shahri', 'Furqat', 'Qoʻshtepa', 'Quva', 'Rishton',
      'Soʻx', 'Toshloq', 'Uchkoʻprik', 'Oʻzbekiston', 'Yozyovon'
    ]
  },
  {
    nomi: 'Jizzax viloyati',
    tumanlar: [
      'Arnasoy', 'Baxmal', 'Doʻstlik', 'Forish', 'Gʻallaorol',
      'Sharof Rashidov', 'Mirzachoʻl', 'Paxtakor', 'Yangiobod', 'Zomin',
      'Zafarobod', 'Zarbdor', 'Jizzax shahri'
    ]
  },
  {
    nomi: 'Xorazm viloyati',
    tumanlar: [
      'Bogʻot', 'Gurlan', 'Qoʻshkoʻpir', 'Urganch tumani', 'Urganch shahri', 'Hazorasp',
      'Xonqa', 'Xiva', 'Shovot', 'Yangibozor', 'Yangiariq', 'Tuproqqalʼa'
    ]
  },
  {
    nomi: 'Namangan viloyati',
    tumanlar: [
      'Chortoq', 'Chust', 'Kosonsoy', 'Mingbuloq', 'Namangan tumani', 'Namangan shahri',
      'Norin', 'Pop', 'Toʻraqoʻrgʻon', 'Uchqoʻrgʻon', 'Uychi',
      'Yangiqoʻrgʻon', 'Yangi Namangan'
    ]
  },
  {
    nomi: 'Navoiy viloyati',
    tumanlar: [
      'Konimex', 'Qiziltepa', 'Xatirchi', 'Navbahor', 'Karmana',
      'Nurota', 'Tomdi', 'Uchquduq', 'Navoiy shahri'
    ]
  },
  {
    nomi: 'Qashqadaryo viloyati',
    tumanlar: [
      'Chiroqchi', 'Dehqonobod', 'Gʻuzor', 'Qamashi', 'Qarshi tumani', 'Qarshi shahri',
      'Koson', 'Kasbi', 'Kitob', 'Koʻkdala', 'Mirishkor', 'Muborak',
      'Nishon', 'Shahrisabz', 'Yakkabogʻ'
    ]
  },
  {
    nomi: 'Samarqand viloyati',
    tumanlar: [
      'Bulungʻur', 'Ishtixon', 'Jomboy', 'Kattaqoʻrgʻon', 'Qoʻshrabot',
      'Narpay', 'Nurobod', 'Oqdaryo', 'Paxtachi', 'Payariq',
      'Pastdargʻom', 'Samarqand tumani', 'Samarqand shahri', 'Toyloq', 'Urgut'
    ]
  },
  {
    nomi: 'Sirdaryo viloyati',
    tumanlar: [
      'Oqoltin', 'Boyovut', 'Guliston shahri', 'Xovos', 'Mirzaobod',
      'Sardoba', 'Sayxunobod', 'Sirdaryo tumani'
    ]
  },
  {
    nomi: 'Surxondaryo viloyati',
    tumanlar: [
      'Angor', 'Bandixon', 'Boysun', 'Denov', 'Jarqoʻrgʻon', 'Qiziriq',
      'Qumqoʻrgʻon', 'Muzrabot', 'Oltinsoy', 'Sariosiyo', 'Sherobod',
      'Shoʻrchi', 'Termiz tumani', 'Termiz shahri', 'Uzun'
    ]
  },
  {
    nomi: 'Toshkent viloyati',
    tumanlar: [
      'Bekobod', 'Boʻstonliq', 'Boʻka', 'Chinoz', 'Qibray', 'Ohangaron',
      'Oqqoʻrgʻon', 'Parkent', 'Piskent', 'Quyichirchiq', 'Zangiota',
      'Oʻrtachirchiq', 'Yangiyoʻl', 'Yuqorichirchiq', 'Toshkent tumani'
    ]
  },
  {
    nomi: 'Toshkent shahri',
    tumanlar: [
      'Bektemir', 'Chilonzor', 'Yashnobod', 'Mirobod', 'Mirzo Ulugʻbek',
      'Sergeli', 'Shayxontohur', 'Olmazor', 'Uchtepa', 'Yakkasaroy',
      'Yunusobod', 'Yangihayot'
    ]
  }
]

/* Chet el fuqarosi tanlaganda — "Viloyat" oʻrniga shu roʻyxat
   chiqadi. "Boshqa" tanlansa mamlakat nomi qoʻlda yoziladi. */
export const SNG_DAVLATLAR = [
  'Rossiya', 'Qozogʻiston', 'Qirgʻiziston', 'Tojikiston', 'Turkmaniston',
  'Belarus', 'Armaniston', 'Ozarbayjon', 'Moldova', 'Boshqa'
]
