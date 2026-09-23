-- =========================================================
-- 1. YARDIMCI FONKSIYONLAR & PROFILLER (profiles)
-- =========================================================
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT,
  occupation TEXT,
  address TEXT,
  bio TEXT,
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('admin', 'customer')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "KullanÄ±cÄ±lar kendi profilini veya admin tÃ¼m profilleri okuyabilir" ON public.profiles;
CREATE POLICY "KullanÄ±cÄ±lar kendi profilini veya admin tÃ¼m profilleri okuyabilir"
  ON public.profiles FOR SELECT USING (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "KullanÄ±cÄ±lar kendi profilini gÃ¼ncelleyebilir veya admin gÃ¼ncelleyebilir" ON public.profiles;
CREATE POLICY "KullanÄ±cÄ±lar kendi profilini gÃ¼ncelleyebilir veya admin gÃ¼ncelleyebilir"
  ON public.profiles FOR UPDATE USING (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "Adminler profil silebilir" ON public.profiles;
CREATE POLICY "Adminler profil silebilir"
  ON public.profiles FOR DELETE USING (public.is_admin());

DROP POLICY IF EXISTS "Sistem ve kullanÄ±cÄ±lar profil ekleyebilir" ON public.profiles;
CREATE POLICY "Sistem ve kullanÄ±cÄ±lar profil ekleyebilir"
  ON public.profiles FOR INSERT WITH CHECK (public.is_admin() OR auth.uid() = id);

-- Otomatik Profil OluÅŸturma Trigger'Ä± (auth.users -> public.profiles)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, occupation, address, bio, role)
  VALUES (
    new.id, new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', ''), COALESCE(new.raw_user_meta_data->>'occupation', ''),
    COALESCE(new.raw_user_meta_data->>'address', ''), COALESCE(new.raw_user_meta_data->>'bio', ''),
    COALESCE(new.raw_user_meta_data->>'role', 'customer')
  )
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, full_name = EXCLUDED.full_name;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =========================================================
-- 2. KATEGORÄ°LER (sections) VE TIKLAMA ANALÄ°TÄ°ÄžÄ°
-- =========================================================
CREATE TABLE IF NOT EXISTS public.sections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "GiriÅŸ yapmÄ±ÅŸ tÃ¼m kullanÄ±cÄ±lar aktif bÃ¶lÃ¼mleri okuyabilir" ON public.sections;
CREATE POLICY "GiriÅŸ yapmÄ±ÅŸ tÃ¼m kullanÄ±cÄ±lar aktif bÃ¶lÃ¼mleri okuyabilir" ON public.sections FOR SELECT USING (auth.role() = 'authenticated' AND (is_active = true OR public.is_admin()));
DROP POLICY IF EXISTS "Sadece adminler bÃ¶lÃ¼m ekleyebilir" ON public.sections;
CREATE POLICY "Sadece adminler bÃ¶lÃ¼m ekleyebilir" ON public.sections FOR INSERT WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Sadece adminler bÃ¶lÃ¼m gÃ¼ncelleyebilir" ON public.sections;
CREATE POLICY "Sadece adminler bÃ¶lÃ¼m gÃ¼ncelleyebilir" ON public.sections FOR UPDATE USING (public.is_admin());
DROP POLICY IF EXISTS "Sadece adminler bÃ¶lÃ¼m silebilir" ON public.sections;
CREATE POLICY "Sadece adminler bÃ¶lÃ¼m silebilir" ON public.sections FOR DELETE USING (public.is_admin());

CREATE TABLE IF NOT EXISTS public.section_clicks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  section_id UUID REFERENCES public.sections(id) ON DELETE SET NULL,
  section_title TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.section_clicks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "GiriÅŸ yapmÄ±ÅŸ kullanÄ±cÄ±lar kendi tÄ±klama kaydÄ±nÄ± oluÅŸturabilir" ON public.section_clicks;
CREATE POLICY "GiriÅŸ yapmÄ±ÅŸ kullanÄ±cÄ±lar kendi tÄ±klama kaydÄ±nÄ± oluÅŸturabilir" ON public.section_clicks FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Sadece adminler tÃ¼m tÄ±klama kayÄ±tlarÄ±nÄ± okuyabilir" ON public.section_clicks;
CREATE POLICY "Sadece adminler tÃ¼m tÄ±klama kayÄ±tlarÄ±nÄ± okuyabilir" ON public.section_clicks FOR SELECT USING (public.is_admin());

-- =========================================================
-- 3. ÃœRÃœNLER (products) VE Ã‡OKLU VÄ°DEOLAR (product_videos)
-- =========================================================
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id UUID REFERENCES public.sections(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  description TEXT,
  specs JSONB NOT NULL DEFAULT '{}'::jsonb,
  video_type TEXT NOT NULL DEFAULT 'youtube' CHECK (video_type IN ('embed', 'upload', 'youtube', 'vimeo')),
  video_url TEXT,
  storage_video_path TEXT,
  thumbnail_url TEXT,
  is_published BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "MÃ¼ÅŸteriler yayÄ±nlanmÄ±ÅŸ Ã¼rÃ¼nleri okuyabilir" ON public.products;
CREATE POLICY "MÃ¼ÅŸteriler yayÄ±nlanmÄ±ÅŸ Ã¼rÃ¼nleri okuyabilir" ON public.products FOR SELECT USING (auth.role() = 'authenticated' AND (is_published = true OR public.is_admin()));
DROP POLICY IF EXISTS "Adminler ekleyebilir" ON public.products;
CREATE POLICY "Adminler ekleyebilir" ON public.products FOR INSERT WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Adminler gÃ¼ncelleyebilir" ON public.products;
CREATE POLICY "Adminler gÃ¼ncelleyebilir" ON public.products FOR UPDATE USING (public.is_admin());
DROP POLICY IF EXISTS "Adminler silebilir" ON public.products;
CREATE POLICY "Adminler silebilir" ON public.products FOR DELETE USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = timezone('utc'::text, now()); RETURN NEW; END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_products_updated_at ON public.products;
CREATE TRIGGER trigger_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ÃœrÃ¼n Ã‡oklu Video Tablosu
CREATE TABLE IF NOT EXISTS public.product_videos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    video_type TEXT NOT NULL,
    video_url TEXT,
    thumbnail_url TEXT,
    storage_video_path TEXT,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.product_videos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read access on product_videos" ON public.product_videos FOR SELECT USING (true);
CREATE POLICY "Allow authenticated full access on product_videos" ON public.product_videos FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- =========================================================
-- 4. SÄ°TE AYARLARI (site_settings) VE DÃ–KÃœMAN LÄ°NKLERÄ°
-- =========================================================
CREATE TABLE IF NOT EXISTS public.site_settings (
  id integer PRIMARY KEY DEFAULT 1,
  hero_title text NOT NULL DEFAULT 'Sidrex Akademi',
  hero_subtitle text NOT NULL DEFAULT 'EÄŸitim ve Sertifikasyon Platformu',
  hero_bg_image text,
  quick_start_title text NOT NULL DEFAULT 'HÄ±zlÄ± BaÅŸlangÄ±Ã§ & Panel Oryantasyonu',
  quick_start_desc text NOT NULL DEFAULT 'Bu bÃ¶lÃ¼m, tarafÄ±mÄ±za ileten iÃ§eriklerin (video, gÃ¶rseller) sistemine pratik, platformun en iyi ÅŸekilde kullanÄ±lmasÄ±nÄ± saÄŸlar.',
  quick_start_video_url text,
  register_guide_url text,
  panel_guide_url text,
  product_catalog_url text,
  contract_center_url text,
  updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
  CONSTRAINT single_row CHECK (id = 1)
);

ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Site settings viewable by everyone." ON public.site_settings FOR SELECT USING (true);
CREATE POLICY "Site settings updatable by admin only." ON public.site_settings FOR UPDATE USING (auth.uid() IN (SELECT id FROM public.profiles WHERE role = 'admin'));
CREATE POLICY "Site settings insertable by admin only." ON public.site_settings FOR INSERT WITH CHECK (auth.uid() IN (SELECT id FROM public.profiles WHERE role = 'admin'));

INSERT INTO public.site_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- =========================================================
-- 5. SIKÃ‡A SORULAN SORULAR (faqs)
-- =========================================================
CREATE TABLE IF NOT EXISTS public.faqs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  question text NOT NULL,
  answer text NOT NULL,
  sort_order integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.faqs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Faqs viewable by everyone." ON public.faqs FOR SELECT USING (true);
CREATE POLICY "Faqs insertable by admin only." ON public.faqs FOR INSERT WITH CHECK (auth.uid() IN (SELECT id FROM public.profiles WHERE role = 'admin'));
CREATE POLICY "Faqs updatable by admin only." ON public.faqs FOR UPDATE USING (auth.uid() IN (SELECT id FROM public.profiles WHERE role = 'admin'));
CREATE POLICY "Faqs deletable by admin only." ON public.faqs FOR DELETE USING (auth.uid() IN (SELECT id FROM public.profiles WHERE role = 'admin'));

-- =========================================================
-- 6. STORAGE BUCKETS (DEPOLAMA ALANLARI) VE Ã–RNEK VERÄ°LER
-- =========================================================
INSERT INTO storage.buckets (id, name, public)
VALUES 
  ('product-thumbnails', 'product-thumbnails', true),
  ('product-videos', 'product-videos', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sections (id, title, slug, sort_order, is_active)
VALUES 
  ('c1000000-0000-0000-0000-000000000001', 'Kolajenler', 'kolajenler', 1, true),
  ('c2000000-0000-0000-0000-000000000002', 'BaÄŸÄ±ÅŸÄ±klÄ±k DesteÄŸi', 'bagisiklik-destegi', 2, true),
  ('c3000000-0000-0000-0000-000000000003', 'Bitkisel ÃœrÃ¼nler', 'bitkisel-urunler', 3, true),
  ('c4000000-0000-0000-0000-000000000004', 'Vitamin ve Mineraller', 'vitamin-ve-mineraller', 4, true),
  ('c5000000-0000-0000-0000-000000000005', 'Ã‡ocuk ÃœrÃ¼nleri', 'cocuk-urunleri', 5, true),
  ('c6000000-0000-0000-0000-000000000006', 'KadÄ±n & Erkek SaÄŸlÄ±ÄŸÄ±', 'kadin-erkek-sagligi', 6, true),
  ('c7000000-0000-0000-0000-000000000007', 'Ã–zel Takviyeler', 'ozel-takviyeler', 7, true),
  ('c8000000-0000-0000-0000-000000000008', 'Fonksiyonel Ä°Ã§ecekler', 'fonksiyonel-icecekler', 8, true)
ON CONFLICT (slug) DO UPDATE SET title = EXCLUDED.title, sort_order = EXCLUDED.sort_order;

-- 9. SIDREX GERÇEK ORÝJÝNAL ÜRÜNLERÝ (SHOPIFY CDN GÖRSELLERÝ ÝLE)
INSERT INTO public.products (section_id, title, slug, description, specs, video_type, video_url, thumbnail_url, is_published)
VALUES 
  -- Özel Takviyeler (Electrolyte Balance & Slm-X)
  (
    'c7000000-0000-0000-0000-000000000007',
    'Electrolyte Balance',
    'electrolyte-balance',
    'Sidrex® Electrolyte Balance; pembe Himalaya deniz tuzu, 5’li elektrolit kompleksi, C, B6 ve B12 vitaminleri ile zenginleþtirildi. Bu özel formül; modern bilimin gücünü lezzetli ve pratik bir içecekle buluþturuyor.',
    '{"Form": "Stick Saþe", "Gramaj": "30 Saþe", "Özellikler": "Þekersiz, Vegan, Glütensiz, Koruyucu Ýçermez", "Fiyat": "549.00 TL", "SKU": "152-SDRX-ELT", "Kullaným Þekli": "Günde 1 stick saþeyi 500 mL su ile karýþtýrarak tüketiniz."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/elektrolit.jpg?v=1787745530',
    true
  ),
  (
    'c7000000-0000-0000-0000-000000000007',
    'Slm-X | Takviye Edici Gýda',
    'slm-x',
    'Sidrex® Slm-X; bromelain, CLA, L-karnitin, inülin ve yeþil çay ekstresi baþta olmak üzere 7 bileþenli formülüyle geliþtirilmiþ, ananas aromalý saþe takviyedir.',
    '{"Form": "Saþe", "Gramaj": "30 Saþe", "Özellikler": "Yapay Boya Yok, Koruyucusuz, Ananas Aromalý", "Fiyat": "1.890.00 TL", "SKU": "153-SDRX-SLMX", "Kullaným Þekli": "Günde 1 saþe suda çözündürülerek tüketilir."}'::jsonb,
    'vimeo',
    'https://vimeo.com/76979871',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/slim-x-1_08bb1613-bf0e-4925-81f3-73158563ac12.png?v=1778613318',
    true
  ),

  -- Vitamin ve Mineraller
  (
    'c4000000-0000-0000-0000-000000000004',
    'B12 Complex B12, B1, B2, B6 ve Folik Asit',
    'b12-complex-b12-b1-b2-b6-ve-folik-asit',
    'B12, B1, B2, B6 vitaminleri ve aktif folik asit içeriðiyle enerji oluþum metabolizmasýna katkýda bulunur, yorgunluk ve bitkinliði azaltmaya yardýmcý olur.',
    '{"Form": "Damla / Sprey", "Gramaj": "30 ml", "Özellikler": "Þekersiz, Yapay Boya Ýçermez", "Fiyat": "500.00 TL", "SKU": "152-SDRX-B12", "Kullaným Þekli": "Günde 1 puff dil altýna püskürtülür."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/b12-complex-2.jpg?v=1781872183',
    true
  ),
  (
    'c4000000-0000-0000-0000-000000000004',
    'Lipo Iron Complex | Takviye Edici Gýda',
    'lipo-iron-complex',
    'Lipozomal mikroenkapsüle Lipofer® demir, C vitamini, aktif folat ve B vitaminleri ile mide hassasiyeti ve kabýzlýk yapmayan yüksek emilimli demir.',
    '{"Form": "Kapsül", "Gramaj": "30 Kapsül", "Özellikler": "Vegan, TiO2 Ýçermez, GÝS Hassasiyeti Yapmaz", "Fiyat": "900.00 TL", "SKU": "153-SDRX-LIPO", "Kullaným Þekli": "Günde 1 kapsül aç karnýna su ile."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/lipo-iron_8e4bbf96-fdd3-4f84-850c-b8f5e7fecb30.jpg?v=1779742716',
    true
  ),

  -- Çocuk Ürünleri
  (
    'c5000000-0000-0000-0000-000000000005',
    'B12 Complex Kids B12, B1, B2, B6 ve Folik Asit',
    'b12-complex-kids',
    'Çocuklarýn zihinsel ve fiziksel geliþimini desteklemek üzere geliþtirilmiþ B12, B1, B2, B6 vitaminleri ve folik asit kompleksi.',
    '{"Form": "Damla", "Gramaj": "30 ml", "Özellikler": "Þekersiz, Çocuklara Özel Dozaj", "Fiyat": "490.00 TL", "SKU": "152-SDRX-B12KIDS", "Kullaným Þekli": "Çocuklar için günde 1 damla/puff."}'::jsonb,
    'vimeo',
    'https://vimeo.com/76979871',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/b12-complex-kids-1_fb9c56a6-360a-43a8-b264-4f646679881b.jpg?v=1782116848',
    true
  ),
  (
    'c5000000-0000-0000-0000-000000000005',
    'Lipo Iron Kids Damla',
    'lipo-iron-kids',
    'Çocuklarýn günlük demir ihtiyacýný karþýlayan, diþ lekelenmesi ve tat rahatsýzlýðý yapmayan lezzetli lipozomal damla formu.',
    '{"Form": "Damla", "Gramaj": "30 ml", "Özellikler": "Diþ Leke Yapmaz, Çocuk Güvenlikli Kapak", "Fiyat": "650.00 TL", "SKU": "152-SDRX-LPKIDS", "Kullaným Þekli": "Günde 1 ml damla doðrudan veya meyve suyuna eklenir."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/lipo-iron-2_d097a81e-9c99-4739-ab9e-f52dd38bec8b.png?v=1786701578',
    true
  ),

  -- Çocuk Setleri
  (
    'c5000000-0000-0000-0000-000000000005',
    'Çocuk Mevsim Geçiþi Seti',
    'cocuk-mevsim-gecis-seti',
    'Mevsim deðiþikliklerinde çocuklarýn direncini korumak için tasarlanmýþ Imuntus Kids ve D3K2 takviye seti.',
    '{"Form": "Set", "Ýçerik": "Imuntus Kids + Vitamin D3K2 Kids", "Özellikler": "Avantajlý Paket, %10 Ýndirimli", "Fiyat": "1.149.00 TL", "SKU": "SET-ALERJISET", "Kullaným Þekli": "Günlük 1 saþe ve 1 damla."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/allergy-set-kids_970fd0c3-9c2d-4da1-acd5-7f61dc38e02d.jpg?v=1778644243',
    true
  ),
  (
    'c5000000-0000-0000-0000-000000000005',
    'Happy Tummies Set',
    'happy-tummies-set',
    'Çocuklarda sindirim ve mide konforu saðlayan probiyotik lif ve multivitamin ikili takviye paketi.',
    '{"Form": "Set", "Ýçerik": "Colovita Kids + B12 Complex Kids", "Özellikler": "Sindirim Dostu, Doðal Tat", "Fiyat": "1.265.00 TL", "SKU": "SET-DIGESTSETKIDS", "Kullaným Þekli": "Günde 1 saþe ve 1 damla."}'::jsonb,
    'vimeo',
    'https://vimeo.com/76979871',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/digest-set-kids_71012669-bdd0-4978-93e6-3495b597fb83.jpg?v=1778644257',
    true
  ),

  -- Baðýþýklýk Desteði
  (
    'c2000000-0000-0000-0000-000000000002',
    'Ýmuntus | Bitkisel Takviye Edici Gýda',
    'imuntus-bitkisel',
    'Zahter, zencefil, ardýç, karabaþ otu, çörek otu yaðý, C vitamini ve Çinko içeren Anadolu bitkileri destekli þurup.',
    '{"Form": "Þurup", "Gramaj": "150 ml", "Özellikler": "Þekersiz, Yapay Boya ve Koruyucu Ýçermez", "Fiyat": "500.00 TL", "SKU": "153-SDRX-IM", "Kullaným Þekli": "Günde 1 ölçek (10 ml) yemekten sonra."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://cdn.shopify.com/s/files/1/0767/8653/2540/files/imuntus-1_6b6dc4ab-345e-4745-a971-b0c1a09a86ac.jpg?v=1778613159',
    true
  ),

  -- Kolajenler
  (
    'c1000000-0000-0000-0000-000000000001',
    'Collagen Glow Complex',
    'collagen-glow-complex',
    'Tip 1 & Tip 3 hidrolize kolajen peptidleri, hyaluronik asit, C vitamini ve biyotin ile cilt parlaklýðý ve esnekliði için özel formül.',
    '{"Form": "Saþe", "Gramaj": "30 Saþe", "Özellikler": "Þekersiz, Glütensiz, Tatlandýrýcý Ýçermez", "Fiyat": "1.450.00 TL", "SKU": "SX-COL-GLOW", "Kullaným Þekli": "Günde 1 saþeyi 200 ml suda çözdürerek tüketiniz."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://images.unsplash.com/photo-1584308666744-24d5c474f2ae?q=80&w=1200&auto=format&fit=crop',
    true
  ),

  -- Bitkisel Ürünler
  (
    'c3000000-0000-0000-0000-000000000003',
    'Milk Thistle Complex',
    'milk-thistle-complex',
    'Devedikeni ekstratý (Silymarin), enginar ve karahindiba kökü ile karaciðer detoksu ve sindirim saðlýðý takviyesi.',
    '{"Form": "Kapsül", "Gramaj": "60 Bitkisel Kapsül", "Özellikler": "Vegan, GDO Ýçermez", "Fiyat": "750.00 TL", "SKU": "SX-MILK-THISTLE", "Kullaným Þekli": "Günde 1-2 kapsül yemeklerden önce."}'::jsonb,
    'youtube',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://images.unsplash.com/photo-1512069772995-ec65ed45afd6?q=80&w=1200&auto=format&fit=crop',
    true
  )
ON CONFLICT (slug) DO UPDATE SET title = EXCLUDED.title, specs = EXCLUDED.specs, description = EXCLUDED.description, thumbnail_url = EXCLUDED.thumbnail_url;

