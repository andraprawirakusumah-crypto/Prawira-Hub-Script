-- =================================================================
-- Script  : FLOWER HUB PH - My Flower Shop Auto Farm / Shop / Build Suite
-- Author  : PrawiraXLIV  (UI framework & tema: PRAWIRA HUB 4)
-- Target  : My Flower Shop (Knit v1.7.0 + Madwork ReplicaService)
-- Support : PC, HP, Tablet, Laptop, Monitor, TV (Responsive)
-- =================================================================
-- CATATAN TEKNIS (hasil bedah RSTELITI / SGTELITI / SPSTELITI / WORKSPACETELITI)
--
-- REMOTE: ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"].knit.Services
--            <Service>.RF.<Method>  -> RemoteFunction (InvokeServer)
--            <Service>.RE.<Event>   -> RemoteEvent
--
-- SIGNATURE PENTING (diambil dari controller asli, bukan tebakan):
--   GrowingService.RF.PlantSeed(planter, seedType, slot)
--   GrowingService.RF.Harvest(planter, slot)
--   GrowingService.RF.ApplySupply(planter, slot, namaToolSupply)
--
--   TIGA REMOTE MASSAL - satu panggilan mengurus SATU OBJEK PENUH.
--   Baru ketahuan dari dump V3; sebelumnya hub memakai jalur per-slot
--   dan itu yang bikin panen/tanam/rak terasa lambat.
--     GrowingService.RF.HarvestPlanter(planter)          9 slot -> 1 call
--     GrowingService.RF.PlantPlanter(planter, seedType)  9 slot -> 1 call
--     FlowerDisplayService.RF.BulkStockArrangement(rak)  isi rak -> 1 call
--   Ketiganya tombol milik GAME sendiri ("Harvest Planter" / "Plant
--   Planter" / "Stock All"), call-site di StarterPlayerScriptsV3
--   baris 665, 679, dan 1278.
--
--   SPAWN CUSTOMER: TIDAK ADA. Diukur ulang di V3 - dari 98 remote di
--   seluruh pohon Knit, CustomerService cuma punya ToggleShopOpen.
--   ShopService.RF.GetShopStock(shopId) -> BENTUKNYA TIDAK TERBUKTI.
--       Nol call-site di seluruh dump client, dan terukur di game
--       2026-08-21: balik 9 entri dengan entry[1] nil SEMUANYA. Jadi
--       jangan pakai dia sebagai sumber nama. Yang dipakai hub:
--       SetupShopUI, lalu kartu toko game (lihat TOKO.dariUI).
--   ShopService.RF.BuyItem(shopId, INDEX, qty)   <- pakai index, bukan nama
--   ShopService.RF.BuyItemWithGems(shopId, INDEX)
--   PlacementService.RF.Place(namaItem, CFrame, "Furniture", {warna})
--   PlacementService.RF.Move(model, CFrame, "Furniture")
--   PlacementService.RF.Delete(model)
--   ArrangementService.RF.StartArranging(craftTable) -> ReserveFlower(nama)
--                          -> FinishArranging({container=,preset=,flowers={}})
--   FlowerDisplayService.RF.StockFlower / StockArrangement / UnstockFlowerToPlayer
--   StaffService.RF.HireApplicant(role, index), ToggleRestRole(role)
--   EquipmentService.RF.UpgradeEquipment("CraftTable")
--   UpgradeService.RF.Purchase("Advertising")
--
-- DATA PEMAIN: Replica kelas "DataToken_<UserId>" -> Data.Cash/Gems/Level/Boosts
--
-- PLOT: workspace.Plots.<Nama>Plot   (atribut Owner)
--   .Objects   -> planter + rak display yang sudah dipasang
--   .Building  -> CraftTable, Register, Computer, PlotBase(BuildZone=Farm/Shop)
--   .Customers -> customer; yang custom order punya ProximityPrompt
--                 bernama "CustomOrderPrompt" di HumanoidRootPart  <- AUTO CHECKOUT
--
-- PLANTER (atribut): Slots, Slot_<i>_Seed, Slot_<i>_Ready, Slot_<i>_Stage,
--                    Slot_<i>_PlantedAt, Slot_<i>_Variants, Slot_<i>_Locked
--
-- KATALOG: ReplicatedStorage.Assets.Objects
--   .Planters (20 item, atribut Slots + Price + PlaceZone=Farm)
--   .Displays (20 item, atribut Max   + Price + PlaceZone=Store)
--   .Decor    (109 item)
--   Rotasi pakai kelipatan 45 derajat (lihat PlacementController).
--   Di game ini BELI = PASANG: RF.Place langsung memotong uang.
--
-- RATE LIMIT: RateLimiter.Default = 120 call/detik -> delay 0.1-0.5 dtk aman.
--
-- TIDAK GRATIS: prompt GrowAll & SellAll di plot memanggil
--   MarketplaceService:PromptProductPurchase (produk Robux 3610937789 /
--   3610937817). Jadi TIDAK dipakai di auto farm.
-- =================================================================

local Players           = game:GetService("Players")
local CoreGui           = game:GetService("CoreGui")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local Workspace         = game:GetService("Workspace")
local VirtualUser       = game:GetService("VirtualUser")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local camera      = Workspace.CurrentCamera

-- ============================================================
-- PENANDA BUILD - supaya "ini versi baru atau lama" tidak pernah
-- jadi tebak-tebakan lagi
-- ============================================================
-- Ini lahir dari kesalahan saya yang berulang DUA KALI: melihat
-- screenshot tanpa harga di dropdown, lalu menyimpulkan "kamu belum
-- execute ulang". Sekali itu SALAH (bugnya nyata, di paint()), sekali
-- lagi memang build lama. Dua-duanya tidak bisa dibedakan dari layar.
--
-- Sekarang bisa: angka ini muncul di toast saat execute DAN di kartu
-- STATISTIK PEMAIN tab Info. Cocokkan dengan yang saya sebut di
-- laporan - kalau beda, berarti file yang jalan memang bukan yang
-- barusan diperbaiki.
--
-- SENGAJA global: nol register (batas Luau 200 per fungsi).
HUB_BUILD = "2026.08.23-11"

-- ============================================================
-- ANTI-AFK (langsung aktif saat execute)
-- ============================================================
local scriptConnections = {}
local function track(conn) table.insert(scriptConnections, conn); return conn end

-- SENGAJA TIDAK dibungkus track(). Dulu dibungkus, dan akibatnya
-- cleanupAll() -- yang jalan saat tombol X ditekan -- ikut memutus
-- koneksi ini. Jadi begitu hub ditutup, anti-AFK ikut mati padahal
-- justru saat itulah kamu paling mungkin meninggalkan game.
-- Koneksi ini ringan (cuma bangun saat Roblox mengira kamu idle) dan
-- hilang sendiri waktu kamu keluar game.
LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)


local guiParent = (gethui and gethui()) or CoreGui
if guiParent:FindFirstChild("FlowerHubPHGUI") then guiParent.FlowerHubPHGUI:Destroy() end

-- ============================================================
-- FILE SYSTEM (folder rapih + per-place config)
--   FlowerHubPH/
--     Config/Settings.json
--     TeleportPositionConfig/Place_<PlaceId>.json
-- ============================================================
local hasFS = (typeof(writefile) == "function")
    and (typeof(readfile) == "function")
    and (typeof(isfile) == "function")
    and (typeof(makefolder) == "function")
    and (typeof(isfolder) == "function")

local SETTINGS_FILE = "FlowerHubPH/Config/Settings_" .. tostring(game.PlaceId) .. ".json"

-- HEMAT REGISTER. Main chunk ini SATU fungsi, dan Luau membatasi 200 register
-- lokal per fungsi. Setiap `local` di level teratas HIDUP SAMPAI BARIS
-- TERAKHIR - walau cuma dipakai sekali di awal. Dulu bagian ini punya 8 nama
-- di level teratas (ROOT_DIR, CONFIG_DIR, TPOS_DIR, PLACE_ID, TPOS_FILE,
-- SETTINGS_FILE, hasFS, setupFolders) padahal enam di antaranya cuma dipakai
-- di sini. Dibungkus do...end, register-nya dibebaskan saat blok selesai.
do
    if hasFS then
        local dir = "FlowerHubPH"
        pcall(function()
            if not isfolder(dir)                              then makefolder(dir) end
            if not isfolder(dir .. "/Config")                 then makefolder(dir .. "/Config") end
            if not isfolder(dir .. "/TeleportPositionConfig") then makefolder(dir .. "/TeleportPositionConfig") end
        end)
    end
end


-- ============================================================
-- THEME (colorful / modern)  -- diambil PERSIS dari PrawiraHub.txt
-- ============================================================
local THEME = {
    Bg        = Color3.fromRGB(18, 18, 26),
    BgTrans   = 0.04,
    Panel     = Color3.fromRGB(28, 28, 40),
    Slot      = Color3.fromRGB(38, 38, 54),
    Stroke    = Color3.fromRGB(70, 70, 95),
    Title     = Color3.fromRGB(0, 255, 200),
    Text      = Color3.fromRGB(240, 240, 245),
    SubText   = Color3.fromRGB(160, 160, 180),
    On        = Color3.fromRGB(0, 200, 110),
    Off       = Color3.fromRGB(210, 55, 70),
    Blue      = Color3.fromRGB(40, 130, 230),
    Purple    = Color3.fromRGB(150, 90, 230),
    Cyan      = Color3.fromRGB(50, 220, 255),
    Yellow    = Color3.fromRGB(255, 215, 60),
    Pink      = Color3.fromRGB(255, 105, 180),
    Orange    = Color3.fromRGB(255, 150, 50),
    Red       = Color3.fromRGB(255, 75, 75),
    Green     = Color3.fromRGB(98, 220, 110),
    Font      = Enum.Font.GothamBold,
    FontReg   = Enum.Font.GothamMedium,
}

local tweenBounce = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tweenFast   = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function corner(inst, r)
    local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r or 8); return c
end
local function stroke(inst, col, th)
    local s = Instance.new("UIStroke", inst)
    s.Color = col or THEME.Stroke; s.Thickness = th or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; return s
end
local function gradient(inst, c1, c2, rot)
    local g = Instance.new("UIGradient", inst)
    g.Color = ColorSequence.new(c1, c2); g.Rotation = rot or 90; return g
end

-- RGB NEON BORDER (biru tua neon -> merah neon -> hijau neon) yang BERPUTAR.
-- Ringan: 1 tween linear loop per stroke, tidak ada perhitungan per-frame di Lua.
-- Urutan warnanya dibuat DI DALAM fungsi, bukan sebagai local di level
-- teratas: cuma dipakai di sini, dan tiap nama di level teratas memakan
-- satu register sampai baris terakhir (batas Luau 200 per fungsi).
-- Fungsi ini cuma dipanggil 4x, jadi ongkos membuat ulangnya nol koma.
local function neonStroke(inst, thickness)
    local s = Instance.new("UIStroke", inst)
    s.Thickness = thickness or 2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Transparency = 0
    -- PENTING: warna UIGradient di-KALI dengan UIStroke.Color. Kalau base color
    -- dibiarkan default (HITAM) -> hitam x gradient = HITAM. Set PUTIH supaya
    -- warna neon gradient muncul penuh.
    s.Color = Color3.new(1, 1, 1)
    local g = Instance.new("UIGradient", s)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(0, 40, 255)),    -- biru tua neon
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 25, 45)),   -- merah neon
        ColorSequenceKeypoint.new(0.66, Color3.fromRGB(20, 255, 80)),   -- hijau neon
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(0, 40, 255)),    -- balik ke biru (mulus)
    })
    g.Rotation = 0
    local tw = TweenService:Create(g,
        TweenInfo.new(3.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        {Rotation = 360})
    tw:Play()
    return s, tw
end

-- ============================================================
-- FEATURE STATE
-- ============================================================
local config = {
    -- movement
    flySpeed    = 60,
    walkSpeed   = 28,
    defaultWalk = 16,
    jumpPower   = 50,
    guiScale    = 1,

    -- delay tiap kategori (detik)
    farmDelay   = 0.35,
    shopDelay   = 0.50,
    buildDelay  = 0.45,
    -- 0.50 = MENTOK BAWAH slidernya (rentangnya 0.5 - 10). Bukan 0: kalau
    -- bawaannya di luar rentang slider, angka yang tampil dan angka yang
    -- dipakai jadi beda - dan itu jenis kebohongan yang sama dengan
    -- sakelar yang mengaku mati padahal hidup.
    craftDelay  = 0.50,
    sellDelay   = 0.60,

    -- shop
    -- TARGET JUMLAH yang mau dibeli PER BARANG per sapuan - bukan lagi
    -- "qty dalam satu panggilan". Cara mencapainya beda per toko, dan
    -- itu ATURAN GAME bukan pilihan saya (ShopController 11007):
    --   SeedShop   -> SATU panggilan BuyItem dengan qty = angka ini
    --   Supply/Decor -> server MEMAKSA qty 1, jadi dicapai dengan
    --                   MENGULANG panggilan sebanyak angka ini
    -- Dua-duanya berhenti di penolakan pertama (stok habis / cash kurang).
    buyQty      = 1,
    -- Bibit dan supply punya angkanya SENDIRI. Dulu satu angka untuk
    -- dua toko, dan itu menyusahkan: menaikkan jatah bibit ikut
    -- menaikkan jatah supply yang harganya bisa $50.000 sebiji.
    qtySupply   = 1,
    -- Beli barang yang sama BERULANG sampai stok toko kosong, bukan satu
    -- biji per putaran loop. Stok supply cuma 3-6 biji dan berputar tiap
    -- ~5 menit, jadi satu-per-4-detik sering kehabisan waktu.
    habisStok   = false,

    -- build
    planterRotation = 0,
    displayRotation = 0,
    gridStep        = 8,     -- jarak antar objek saat auto place (stud)

    -- craft
    containerPick = nil,
    -- 25 = MENTOK ATAS slidernya. FinishBatchArranging: bikin N buket
    -- sekaligus. Aman dinaikkan sebesar ini karena COMBO memotongnya
    -- lagi ke SISA SLOT TAS - jadi 25 itu batas ATAS, bukan paksaan.
    craftBatch    = 25,
    autoBestContainer = false, -- pilih wadah ber-priceAdd tertinggi otomatis
    -- NYALA dari awal. Yang dipilih = maxFlowers TERBANYAK yang levelnya
    -- sudah kebuka, dan itu memang "vas terbaik": harga = priceAdd WADAH
    -- + priceBase TIAP BUNGA, jadi yang menaikkan uang adalah BANYAKNYA
    -- bunga. Sakelarnya di kartu MEMAHALKAN HARGA JUAL ikut digambar ON
    -- (lihat pemanggilan `(config.autoBigContainer)` di situ) - kalau
    -- tidak, config bilang nyala sementara tombolnya bilang mati.
    autoBigContainer  = true,
    -- NYALA dari awal juga, atas permintaan. Tapi saya tidak akan
    -- berpura-pura ini menambah uang: rumusnya cuma priceAdd WADAH +
    -- priceBase TIAP BUNGA, accent tidak ikut dijumlah (alasan lengkap
    -- di kartu MEMAHALKAN HARGA JUAL). Ongkosnya nol - accent tidak
    -- dibeli - jadi menyalakannya tidak merugikan apa pun.
    autoAccents       = true,
    -- 5 = MENTOK KANAN slidernya, atas permintaan. Ini AMAN dan bukan
    -- angka nekat: doCraftOnce memotongnya ke accentCap() saat merangkai
    -- (math.min), dan accentCap itu fungsi LEVEL Craft Table - 2 di Lv1,
    -- 3 di Lv5, 4 di Lv10, 5 di Lv20. Jadi 5 di sini artinya "sebanyak
    -- yang DIIZINKAN", bukan "paksa 5".
    --
    -- Justru itu yang lebih benar daripada menyimpan angka cap-nya:
    -- angka tersimpan akan basi begitu kamu meng-upgrade Craft Table,
    -- sementara 5 ikut naik sendiri tanpa disentuh.
    accentCount       = 5,     -- berapa accent per rangkaian (batas: accentCap())

    -- Slider "Max siram / slot" DIHAPUS beserta config-nya. Terukur di
    -- game: siram cuma boleh SEKALI per slot per tahap tumbuh (server
    -- menjawab "Already watered"), jadi batas 30 itu tidak pernah bisa
    -- tercapai - angka yang tidak berpengaruh apa pun.

    -- SATU sakelar untuk kasir DAN pesanan. Dulu dua: `checkoutTeleport`
    -- (pembeli, tab Farm) dan `kasirLompat` (kasir, tab Auto) - dan itu
    -- memang kembar, jadi digabung.
    --
    -- Kenapa kembar: CheckoutPrompt dan CustomOrderPrompt sama-sama DIBUAT
    -- SERVER dengan jarak 10 stud, jadi dua-duanya menuntut badan dekat
    -- karena alasan yang PERSIS SAMA. Sesudah diperbaiki, mesinnya pun
    -- sama: dekatiPrompt() -> badan dipatok tiap frame supaya tidak jatuh
    -- -> tembak -> dipulangkan HANYA kalau berhasil. Tidak ada gunanya
    -- satu nyala dan satunya mati.
    --
    -- MATI = badan dijamin tidak pernah pindah, tapi kasir & pesanan akan
    -- ditolak server karena jarak. Itu satu-satunya pilihan yang masuk akal
    -- di sini, dan sekarang cukup satu tombol untuk keduanya.
    dekatiDulu = true,
    autoDelay   = 0.30,      -- jeda putaran loop tab Auto
    -- Mesin tab Auto memaksa TURBO selama aksi berjalan. Dulu tab Farm punya
    -- loop kembar yang JALAN TANPA turbo, dan itu satu-satunya bedanya. Loop
    -- kembar itu sudah dihapus, jadi pilihannya dipindah ke sini supaya
    -- tidak ada perilaku yang hilang: matikan kalau planter kamu ratusan
    -- dan mulai kena RateLimiter (120 panggilan/detik).
    autoTurbo   = true,

    -- staff
    minStars = 5,            -- hire hanya pelamar bintang >= ini
}

local state = {
    fly = false, noclip = false, speed = false, infJump = false,
    clickTp = false, unlockZoom = false, holdMouse = false,
    autoPlant = false, autoHarvest = false, autoStock = false,
    autoCheckout = false, cropEsp = false,
    autoBuySeed = false, autoBuySupply = false, autoBuyUpgrade = false, autoHire = false,
    autoBuyPlanter = false, autoBuyDisplay = false,
    autoPlacePlanter = false, autoPlaceDisplay = false,
    autoCraft = false, autoCraftStock = false, autoStockArr = false, shopOpen = false,
    turbo = false,
    autoQuest = false, autoDaily = false,
    -- tab AUTO (mesin AUTO di bawah). Sengaja nama sendiri, tidak
    -- menumpang toggle lama, supaya dua-duanya bisa dipakai bersamaan.
    autoKasir = false, aPanen = false, aTanam = false,
    -- DIPISAH LAGI jadi dua. Dulu satu sakelar "Auto Buy" mengurus bibit
    -- DAN supply sekaligus, dan itu memang menyusahkan: untuk beli supply
    -- saja kamu tetap harus mengosongkan "Seeds to Buy" - dan tidak ada
    -- apa pun di layar yang memberitahu keharusan itu.
    aBeliBibit = false, aBeliSupply = false,
    aCraft = false, aRak = false,
    -- SATU MESIN untuk seluruh siklus rangkai: wadah terbaik -> bunga
    -- penuh -> batch -> langsung ke rak. Menggantikan tombol COMBO
    -- sekali-tekan; yang diminta memang SAKELAR AUTO, bukan tombol.
    aCombo = false,
    -- SIRAM & PUPUK ke tanaman, dua-duanya lewat habisSupply(): kaleng /
    -- pupuk yang diambil selalu yang paling PAS, bukan yang terkuat -
    -- yang terkuat itu justru pemborosan (alasannya di habisSupply).
    aSiram = false, aPupuk = false,
    -- Naikkan bintang staff (kartu di tab Shop). Dicatat di sini supaya
    -- tombol massal "MATIKAN SEMUA FITUR AUTO" ikut membalik gambarnya.
    aUpStaff = false,
    -- Perekam di kartu PROMPT SPY. Dicatat di sini, bukan sebagai
    -- variabel lokal di kartunya, supaya samakanSakelar() bisa ikut
    -- membalik tampilannya - loop ini jedanya 0 alias jalan TIAP FRAME,
    -- jadi paling berbahaya kalau tertinggal menyala tanpa disadari.
    tpSpy = false, reSpy = false, promptSpy = false,
}

-- ---- SELEKSI MULTI (dropdown "Various" / "None") ----
local sel = {
    plantSeeds    = {},
    harvestSeeds  = {},
    stockFlowers  = {},
    buySeeds      = {},
    buySupplies   = {},
    -- Kaleng / pupuk mana yang boleh DIPAKAI ke tanaman - beda urusan
    -- dengan buySupplies yang mengatur apa yang DIBELI. Kosong = semua
    -- yang ada di tas. Lihat kartu AUTO SIRAM & PUPUK di tab Farm.
    canSiram      = {},
    pupukPakai    = {},
    buyUpgrades   = {},
    hireRoles     = {},
    -- Bintang mana saja yang boleh direkrut. Kosong = pakai slider
    -- "Minimal Bintang" (perilaku lama). Lihat bintangBoleh().
    hireStars     = {},
    buyPlanters   = {},
    buyDisplays   = {},
    placePlanters = {},
    placeDisplays = {},
}

local function setIsEmpty(t) return next(t) == nil end
local function setList(t)
    local out = {}
    for k, v in pairs(t) do if v then table.insert(out, k) end end
    table.sort(out)
    return out
end
local function setCount(t)
    local n = 0
    for _, v in pairs(t) do if v then n = n + 1 end end
    return n
end
-- filter permisif: kalau tidak ada yang dipilih -> anggap SEMUA boleh
local function setAllows(t, name)
    if setIsEmpty(t) then return true end
    return t[name] == true
end

-- `character` dulu ada di sini tapi TIDAK PERNAH DIBACA di manapun -
-- cuma ditulisi. Dihapus demi register (lihat catatan hemat register di atas).
local humanoid, root

local function bindCharacter(char)
    humanoid = char:WaitForChild("Humanoid")
    root     = char:WaitForChild("HumanoidRootPart")
end
if LocalPlayer.Character then bindCharacter(LocalPlayer.Character) end
track(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    bindCharacter(char)
end))

-- ============================================================
-- ============================================================
-- GAME BRIDGE : jembatan ke remote Knit + data Replica
-- ============================================================
-- ============================================================

-- Cari folder Services milik Knit secara DINAMIS (tidak hardcode versi),
-- supaya tetap jalan kalau developer update Knit.
local KnitServices = nil
local function findKnitServices()
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then return nil end
    local index = packages:FindFirstChild("_Index")
    if not index then return nil end
    for _, pkg in ipairs(index:GetChildren()) do
        if string.find(string.lower(pkg.Name), "knit") then
            local knit = pkg:FindFirstChild("knit")
            local services = knit and knit:FindFirstChild("Services")
            if services then return services end
        end
    end
    return nil
end
KnitServices = findKnitServices()

local function getRemote(serviceName, kind, methodName)
    if not KnitServices then KnitServices = findKnitServices() end
    if not KnitServices then return nil end
    local svc = KnitServices:FindFirstChild(serviceName)
    if not svc then return nil end
    local folder = svc:FindFirstChild(kind)
    if not folder then return nil end
    return folder:FindFirstChild(methodName)
end

-- Panggil RemoteFunction. Balikan: ok(hasil pcall), lalu nilai balik dari server.
local function invokeRF(serviceName, methodName, ...)
    local rf = getRemote(serviceName, "RF", methodName)
    if not rf then
        return false, "RF " .. serviceName .. "." .. methodName .. " tidak ditemukan"
    end
    local packed = table.pack(...)
    local res = table.pack(pcall(function()
        return rf:InvokeServer(table.unpack(packed, 1, packed.n))
    end))
    if not res[1] then return false, tostring(res[2]) end
    return true, table.unpack(res, 2, res.n)
end

local function fireRE(serviceName, eventName, ...)
    local re = getRemote(serviceName, "RE", eventName)
    if not re then return false end
    local packed = table.pack(...)
    return pcall(function() re:FireServer(table.unpack(packed, 1, packed.n)) end)
end

-- ---------- PLOT ----------
local function getMyPlot()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local direct = plots:FindFirstChild(LocalPlayer.Name .. "Plot")
    if direct then return direct end
    for _, p in ipairs(plots:GetChildren()) do
        if p:GetAttribute("Owner") == LocalPlayer.Name then return p end
    end
    return nil
end

-- Cache 1 detik: GetTagged("Planter") menyisir ratusan model, dan panel
-- statistik memanggilnya beberapa kali per detik -> tanpa cache FPS drop.
local getMyPlanters
do
    local cache, cacheAt = nil, 0
    getMyPlanters = function()
        if cache and (os.clock() - cacheAt) < 1 then
            return cache
        end
        local plot = getMyPlot()
        if not plot then cache, cacheAt = {}, os.clock(); return {} end
        local out, seen = {}, {}
        for _, m in ipairs(CollectionService:GetTagged("Planter")) do
            if m:IsDescendantOf(plot) and not seen[m] then
                seen[m] = true; table.insert(out, m)
            end
        end
        local objects = plot:FindFirstChild("Objects")
        if objects then
            for _, m in ipairs(objects:GetChildren()) do
                if m:GetAttribute("Slots") and not seen[m] then
                    seen[m] = true; table.insert(out, m)
                end
            end
        end
        cache, cacheAt = out, os.clock()
        return out
    end
end

local function getTagged(tagName)
    local plot = getMyPlot()
    if not plot then return {} end
    local out = {}
    for _, m in ipairs(CollectionService:GetTagged(tagName)) do
        if m:IsDescendantOf(plot) then table.insert(out, m) end
    end
    return out
end

local function getMyCraftTable()
    local plot = getMyPlot()
    if not plot then return nil end
    local building = plot:FindFirstChild("Building")
    if building then
        local ct = building:FindFirstChild("CraftTable")
        if ct then return ct end
    end
    return getTagged("CraftTable")[1]
end

-- PlotBase punya atribut BuildZone = "Farm" / "Shop".
-- Item Planters PlaceZone="Farm", Displays PlaceZone="Store" -> peta ke Shop.
local function getZoneBase(placeZone)
    local plot = getMyPlot()
    if not plot then return nil end
    local building = plot:FindFirstChild("Building")
    if not building then return nil end
    local want = (placeZone == "Store") and "Shop" or "Farm"
    for _, p in ipairs(building:GetChildren()) do
        if p:IsA("BasePart") and p:GetAttribute("BuildZone") == want then
            return p
        end
    end
    return nil
end

local function displayStock(disp)
    local sum = 0
    for k, v in pairs(disp:GetAttributes()) do
        if string.sub(k, 1, 6) == "Stock_" and type(v) == "number" then
            sum = sum + v
        end
    end
    return sum
end

-- ============================================================
-- ISI RAK RANGKAIAN - dan kenapa atribut Stock_* SALAH untuk ini
-- ============================================================
-- Rak BUNGA menyimpan isinya di atribut Stock_<nama>; rak RANGKAIAN
-- menyimpannya sebagai ANAK folder "_Arrangements". Jadi displayStock()
-- selalu balik 0 untuk rak rangkaian - dan dari situ dulu lahir bug
-- "Arrangement Display (0 stocked)" tapi server tetap bilang penuh.
--
-- Sumbernya controller game sendiri (StarterPlayerScriptsV3 1250-1256,
-- _getArrangementCount):
--     local _Arrangements = p1.Instance:FindFirstChild("_Arrangements")
--     if _Arrangements then return #_Arrangements:GetChildren() end
--
-- BALIKAN KE-2 = APAKAH ANGKANYA BENAR-BENAR TERBACA. Itu yang
-- membedakan "rak ini isi 0" dari "saya tidak tahu isinya", dan dua
-- keadaan itu menuntut keputusan yang berbeda.
--
-- SENGAJA global: dulu fungsi ini ditulis TIGA KALI (di dalam
-- doStockArrangementOnce, di kartu DIAGNOSA RAK, dan di label TOKO &
-- RAK). Tiga salinan = tiga tempat yang harus ikut diperbaiki tiap kali
-- ada temuan baru, dan itu sudah terbukti gampang terlewat.
function rakIsi(disp)
    local folder = disp:FindFirstChild("_Arrangements")
    if folder then return #folder:GetChildren(), true end
    -- displayStock menjumlahkan atribut Stock_*, dan untuk rak RANGKAIAN
    -- itu selalu 0 - jadi ini BUKAN pembacaan, ini menyerah.
    return displayStock(disp), false
end

-- ---------- KATALOG (Assets.Objects) ----------
local function assetFolder(name)
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    return assets and assets:FindFirstChild(name)
end

local function objectsFolder(sub)
    local objs = assetFolder("Objects")
    return objs and objs:FindFirstChild(sub)
end

local function childNames(folder)
    local out = {}
    if folder then
        for _, c in ipairs(folder:GetChildren()) do table.insert(out, c.Name) end
    end
    table.sort(out)
    return out
end

local function seedNames()      return childNames(assetFolder("Seeds")) end
local function supplyNames()    return childNames(assetFolder("Supplies")) end
local function containerNames() return childNames(assetFolder("Arrangements")) end
local function flowerNames()    return childNames(assetFolder("Flowers")) end
local function planterNames()   return childNames(objectsFolder("Planters")) end
local function displayNames()   return childNames(objectsFolder("Displays")) end
local function decorNames()     return childNames(objectsFolder("Decor")) end

-- label enak dibaca: "Big Flower Bed  [9 slot | $1000]"
--
-- ============================================================
-- PENANDA "VIP" - ini kelas bug yang sama dengan "Florist"
-- ============================================================
-- Lima planter dan lima rak punya atribut VIP = true. Angka ini terukur,
-- bukan tebakan: saya bongkar blob AttributesSerialize milik tiap model
-- di RSV2TELITI dan mencetak isinya.
--
--   Planter VIP : Cartwheel Planter, European Planter, Pallet Stack Rack,
--                 Porcelain Pot, Large Tiered Planter
--   Rak VIP     : Glass Cabinet, Oriental Bouquet Shelf, Bouquet Cart,
--                 Arch Bouquet Shelf, European Bouquet Table
--
-- Tanpa VIP, mencentangnya di Auto Buy membuat server menolak terus dan
-- hub diam saja - persis seperti dulu mencentang "Florist" di daftar role.
-- Sekarang ditandai supaya kelihatan SEBELUM dicentang.
local function planterLabels()
    local f = objectsFolder("Planters")
    local out = {}
    if f then
        for _, m in ipairs(f:GetChildren()) do
            table.insert(out, m.Name .. "  [" .. tostring(m:GetAttribute("Slots") or "?") ..
                " slot | $" .. tostring(m:GetAttribute("Price") or "?") ..
                (m:GetAttribute("VIP") and " | VIP" or "") .. "]")
        end
    end
    table.sort(out)
    return out
end
local function displayLabels()
    local f = objectsFolder("Displays")
    local out = {}
    if f then
        for _, m in ipairs(f:GetChildren()) do
            -- "Max" itu kapasitas BUNGA. Untuk rak RANGKAIAN angka itu SALAH
            -- KONTEKS - terukur di game: Tall Bouquet Shelf ber-Max=8 nyatanya
            -- memuat 12 rangkaian. Jadi jangan ditampilkan sebagai batas.
            --
            -- Tag-nya dibaca kalau memang ada di model katalog; kalau tidak
            -- ada, labelnya jatuh ke "max N" seperti semula - tidak ada yang
            -- diklaim tanpa dasar.
            local arr = CollectionService:HasTag(m, "ArrangementDisplay")
            table.insert(out, m.Name .. "  [" ..
                (arr and "RANGKAIAN - kapasitas diukur saat main"
                     or ("max " .. tostring(m:GetAttribute("Max") or "?"))) ..
                " | $" .. tostring(m:GetAttribute("Price") or "?") ..
                (m:GetAttribute("VIP") and " | VIP" or "") .. "]")
        end
    end
    table.sort(out)
    return out
end
-- balikkan nama asli dari label ber-kurung
local function stripLabel(s)
    if not s then return nil end
    return (string.gsub(s, "%s%s%[.*$", ""))
end

-- ============================================================
-- DAFTAR RAK DI PLOT - dengan CADANGAN lewat folder Objects
-- ============================================================
-- getTagged() bersandar SEPENUHNYA pada CollectionService. Itu memang
-- jalur resminya (komponen rak milik game sendiri dibuat dengan
-- Component.new({ Tag = "ArrangementDisplay" }), StarterPlayerScriptsV3
-- baris 1088-1090), TAPI tag itu dipasang server dan bisa BELUM sampai
-- saat hub baru dieksekusi - atau tidak sampai sama sekali untuk objek
-- di lantai 2 yang baru direplikasi.
--
-- Kalau itu terjadi, seluruh fitur rak diam total dengan alasan "tidak
-- ada rak rangkaian di plot" padahal raknya ada puluhan. Itu kegagalan
-- yang sunyi, dan justru jenis yang paling membingungkan.
--
-- CADANGANNYA: folder <plot>.Objects - dan itu memang tempat SEMUA objek
-- terpasang, termasuk lantai 2. Klasifikasinya TIDAK ditebak dari nama:
-- model KATALOG di Assets.Objects.Displays yang membawa tag-nya, jadi
-- nama placed dicocokkan ke katalog lalu tag katalognya yang dibaca.
-- Pola yang sama sudah dipakai displayLabels() sejak lama.
--
-- SENGAJA global: dipakai belasan tempat, dan global tidak memakan
-- register sama sekali (batas Luau 200 per fungsi).
function rakPlot(tag)
    local out = getTagged(tag)
    if #out > 0 then return out end

    local plot = getMyPlot()
    local objects = plot and plot:FindFirstChild("Objects")
    local kat = objectsFolder("Displays")
    if not (objects and kat) then return out end

    for _, m in ipairs(objects:GetChildren()) do
        local c = kat:FindFirstChild(m.Name)
        if c and CollectionService:HasTag(c, tag) then out[#out + 1] = m end
    end
    if #out > 0 then
        addLog("Tag '" .. tag .. "' tidak terbaca - " .. #out ..
               " rak dikenali dari folder Objects lewat katalog", "SELL")
    end
    return out
end

local function findObjectModel(name)
    for _, sub in ipairs({ "Planters", "Displays", "Decor" }) do
        local f = objectsFolder(sub)
        local m = f and f:FindFirstChild(name)
        if m then return m, sub end
    end
    return nil, nil
end

-- ---------- TOOL / INVENTORY ----------
-- WAJIB MENUNGGU EQUIP SAMPAI KE SERVER. Server memutuskan dari tool
-- yang DIPEGANG, dan SEMUA pemeriksanya menyisir Character:
--     _getEquippedSeed (594) / _getEquippedSupply (609) /
--     _getEquippedFlower (877)          -- SPSV2TELITI
-- EquipTool memindahkan tool di CLIENT seketika, server baru tahu
-- setelah replikasi (~1 ping). Equip lalu LANGSUNG menembak = server
-- melihat tangan KOSONG dan menolak diam-diam.
--
-- Paling parah di INSTANT SIRAM: kaleng uses = 1, jadi TIAP siraman
-- memakai tool baru alias equip baru.
--
-- Jalur cepat tidak berubah: kalau tool SUDAH di tangan, nol tunggu.
local function equipToolBy(pred)
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and pred(t) then return t end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and pred(t) then
                pcall(function() hum:EquipTool(t) end)
                local t0 = os.clock()
                while t.Parent ~= char and (os.clock() - t0) < 0.5 do task.wait() end
                if t.Parent == char then
                    task.wait(0.08)   -- jeda replikasi equip -> server
                end
                return t
            end
        end
    end
    return nil
end

local function allTools()
    local out = {}
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then table.insert(out, t) end
        end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then table.insert(out, t) end
        end
    end
    return out
end

-- ============================================================
-- PEGANG TOOL, LALU TUNGGU SAMPAI SERVER TAHU
-- ============================================================
-- Server memutuskan boleh/tidaknya dari tool yang SEDANG DIPEGANG, dan
-- semua pemeriksanya menyisir Character - bukan Backpack:
--     _getEquippedSeed / _getEquippedSupply / _getEquippedFlower /
--     _getEquippedArrangement (SPSv3 1116-1120)
--
-- Humanoid:EquipTool memindahkan tool di CLIENT SEKETIKA, tapi server
-- baru tahu sesudah replikasi (~1 ping). Equip lalu LANGSUNG menembak =
-- server melihat tangan KOSONG dan menolak diam-diam.
--
-- SATU FUNGSI untuk semua pemakai. Dulu isinya ditulis TIGA KALI
-- (holdTool di rak, pegang di stok bunga, pegang di habisSupply) dengan
-- selisih kecil yang tidak disengaja - dan selisih semacam itu justru
-- yang bikin satu jalur diam-diam berbeda perilakunya.
--
-- Balikan false = tool tidak sampai ke tangan; pemanggil WAJIB
-- melewatinya, bukan menembak tanpa tool.
function pegangTool(t)
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum and t and t.Parent) then return false end
    if t.Parent == char then return true end   -- sudah di tangan
    pcall(function() hum:EquipTool(t) end)
    local t0 = os.clock()
    while t.Parent ~= char and (os.clock() - t0) < 0.5 do task.wait() end
    if t.Parent ~= char then return false end
    task.wait(0.08)   -- jeda replikasi equip -> server
    return true
end

local function isFlowerTool(t)
    local flowers = assetFolder("Flowers")
    return flowers ~= nil and flowers:FindFirstChild(t.Name) ~= nil
end

-- ---------- DATA PEMAIN (Replica "DataToken_<UserId>") ----------
local dataReplica = nil
local function grabReplica()
    if dataReplica then return dataReplica end
    local ok, RC = pcall(function()
        return require(ReplicatedStorage:WaitForChild("ReplicaController", 5))
    end)
    if not ok or type(RC) ~= "table" then return nil end
    local class = "DataToken_" .. tostring(LocalPlayer.UserId)
    -- Replika biasanya SUDAH dibuat sebelum script ini jalan, jadi kita sisir
    -- tabel _replicas langsung (ReplicaOfClassCreated hanya untuk yang BARU).
    for _, rep in pairs(RC._replicas or {}) do
        if type(rep) == "table" and rep.Class == class then
            dataReplica = rep
            return rep
        end
    end
    pcall(function()
        RC.ReplicaOfClassCreated(class, function(rep) dataReplica = rep end)
    end)
    return nil
end

local function pdata(key, default)
    local rep = grabReplica()
    if rep and type(rep.Data) == "table" then
        local v = rep.Data[key]
        if v ~= nil then return v end
    end
    return default
end

-- ============================================================
-- ANGKA STAT (Cash / Gems / Level) - DUA SUMBER, BUKAN SATU
-- ============================================================
-- INI JAWABAN "kok Cash TIDAK TERBACA padahal jelas $231 juta".
--
-- Yang saya periksa satu per satu di dump V3, dan SEMUANYA cocok
-- dengan yang dipakai hub - jadi bukan salah nama:
--   * ReplicatedStorage.ReplicaController  -> ADA, anak langsung
--     (ReplicatedStorageV3 baris 12912, bersebelahan dengan RateLimiter)
--   * kelasnya "DataToken_" .. UserId      -> persis, dipakai game
--     sendiri di 5 controller (SPSv3 5688, 6048, 7262, 8128, 8843)
--   * tabelnya RC._replicas                -> ADA sebagai field publik
--     (ReplicatedStorageV3 12097), dan isinya diisi CreateReplicaBranch
--   * tiap entri punya .Class dan .Data    -> 12299-12303
--   * nama fieldnya Data.Cash              -> SPSv3 8844
--
-- Jadi satu-satunya langkah yang TIDAK dilakukan game adalah yang
-- dilakukan hub: memanggil require() sendiri dari thread suntikan.
-- Di sebagian executor require punya CACHE TERPISAH dari cache game,
-- jadi modulnya DIJALANKAN ULANG: kita dapat tabel BARU dengan
-- _replicas KOSONG, dan pendengar RemoteEvent yang baru itu tidak
-- pernah menerima kiriman data awal - karena kiriman itu sudah lewat
-- jauh sebelum hub dieksekusi. Hasilnya persis yang kamu lihat:
-- tidak ada error, tidak ada pesan, cuma "replica gagal" selamanya.
--
-- CADANGANNYA TIDAK BUTUH require SAMA SEKALI: label milik GAME di
-- PlayerGui.ScreenGui.StatsFrame. Game yang menulisnya sendiri dari
-- replica yang BENAR (SPSv3 8867-8869), jadi angkanya tidak mungkin
-- basi selama layarmu menampilkannya.
--
--   Cash  -> StatsFrame.Cash            "$231,094,710"
--   Gems  -> StatsFrame.Gems.TextLabel  "435"
--   Level -> StatsFrame.Level           "Lv. 293"
--
-- Bentuk teksnya TERUKUR, bukan dikira: formatCurrency(v, nil, true)
-- (SPSv3 1520-1540) menghasilkan "$" + angka berkoma TANPA desimal -
-- argumen ketiga `true` memotong ".00" di baris 1532.
--
-- Balikan ke-2 = DARI MANA angkanya. Dipakai kartu Info supaya kamu
-- bisa melihat replica-nya benar-benar jalan atau cuma tertolong
-- cadangan - itu beda yang penting, dan tidak boleh disembunyikan.
--
-- SENGAJA global: dipakai belasan tempat, dan global tidak memakan
-- register sama sekali (batas Luau 200 per fungsi).
function angkaStat(key)
    local rep = grabReplica()
    if rep and type(rep.Data) == "table" then
        local n = tonumber(rep.Data[key])
        if n then return n, "replica" end
    end

    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local sg = pg and pg:FindFirstChild("ScreenGui")
    local sf = sg and sg:FindFirstChild("StatsFrame")
    if not sf then return nil, nil end

    local lbl
    if key == "Cash" then
        lbl = sf:FindFirstChild("Cash")
    elseif key == "Gems" then
        local g = sf:FindFirstChild("Gems")
        lbl = g and g:FindFirstChild("TextLabel")
    elseif key == "Level" then
        lbl = sf:FindFirstChild("Level")
    end
    if not (lbl and lbl:IsA("TextLabel")) then return nil, nil end

    -- Pola WAJIB mulai dari DIGIT. Kalau dibuat "[%d,%.]+" saja, teks
    -- "Lv. 293" cocok di TITIK milik "Lv." dan hasilnya nil - bug sunyi
    -- yang cuma muncul di satu label.
    local s = string.match(tostring(lbl.Text), "%d[%d,%.]*")
    if not s then return nil, nil end
    local n = tonumber((string.gsub(s, ",", "")))
    if n then return n, "label game" end
    return nil, nil
end

local function fmtNum(n)
    n = tonumber(n) or 0
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9  then return string.format("%.2fB", n / 1e9)  end
    if n >= 1e6  then return string.format("%.2fM", n / 1e6)  end
    if n >= 1e3  then return string.format("%.2fK", n / 1e3)  end
    return tostring(math.floor(n))
end

-- ============================================================
-- MAIN SCREEN GUI + RESPONSIVE SCALE
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name          = "FlowerHubPHGUI"
ScreenGui.ResetOnSpawn  = false
ScreenGui.IgnoreGuiInset= true
-- GLOBAL, bukan Sibling. Ini WAJIB untuk dropdown.
--   Dengan Sibling, ZIndex cuma dibandingkan ANTAR-SAUDARA: seluruh isi
--   sebuah dropdown ikut ditumpuk memakai ZIndex INDUKNYA. Jadi daftar
--   pilihan yang sudah di-set ZIndex 50 tetap KALAH oleh baris lain yang
--   ZIndex-nya sama (5) tapi dibuat BELAKANGAN -- itu sebabnya baris
--   "Planter Rotation" / "Display Rotation" menimpa daftar pilihan dan
--   kelihatan seperti kotak melayang yang tumpang tindih.
--   Dengan Global, ZIndex dibandingkan ke SELURUH layar, jadi angka 120+
--   milik dropdown yang sedang terbuka benar-benar menang.
ScreenGui.ZIndexBehavior= Enum.ZIndexBehavior.Global
ScreenGui.Parent        = guiParent

local UIScale = Instance.new("UIScale", ScreenGui)
local function updateScale()
    if not camera then return end
    local v = camera.ViewportSize
    -- 1280x720 = ukuran acuan; GUI diskalakan proporsional ke layar apapun
    local s = math.min(v.X / 1280, v.Y / 720)
    UIScale.Scale = math.clamp(s, 0.45, 1.15)
end
track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale))
updateScale()

-- ============================================================
-- MAIN FRAME
-- ============================================================
local Frame = Instance.new("Frame", ScreenGui)
Frame.Name             = "MainFrame"
Frame.AnchorPoint      = Vector2.new(0.5, 0.5)
Frame.Position         = UDim2.new(0.5, 0, 0.5, 0)
Frame.Size             = UDim2.fromOffset(660, 440)
Frame.BackgroundColor3 = THEME.Bg
Frame.BackgroundTransparency = THEME.BgTrans
Frame.BorderSizePixel  = 0
corner(Frame, 14)
neonStroke(Frame, 2)
local MainScale = Instance.new("UIScale", Frame); MainScale.Scale = 0

local Header = Instance.new("Frame", Frame)
Header.Size = UDim2.new(1, 0, 0, 52)
Header.BackgroundColor3 = THEME.Panel
Header.BorderSizePixel = 0
corner(Header, 14)
gradient(Header, THEME.Purple, THEME.Blue, 0)

-- HeaderFix + Title tidak pernah disentuh lagi sesudah dibuat, jadi
-- dibungkus do...end supaya dua registernya bebas (batas Luau 200).
do
    local HeaderFix = Instance.new("Frame", Header)
    HeaderFix.Size = UDim2.new(1, 0, 0, 14)
    HeaderFix.Position = UDim2.new(0, 0, 1, -14)
    HeaderFix.BackgroundColor3 = THEME.Panel
    HeaderFix.BorderSizePixel = 0
    -- ZIndex 1, BUKAN 0. Sejak ZIndexBehavior dipindah ke Global, ZIndex 0
    -- akan berada DI BAWAH background MainFrame (ZIndex 1) alias tak terlihat.
    -- Dengan nilai 1 dia seri dengan Header lalu diurutkan berdasarkan urutan
    -- pembuatan: di atas background Header, di bawah Title/MinBtn/CloseBtn.
    HeaderFix.ZIndex = 1
    gradient(HeaderFix, THEME.Purple, THEME.Blue, 0)

    local Title = Instance.new("TextLabel", Header)
    Title.Size = UDim2.new(1, 0, 1, 0)
    Title.BackgroundTransparency = 1
    Title.Active = false
    Title.Text = "FLOWER HUB PH"
    Title.TextColor3 = Color3.new(1, 1, 1)
    Title.Font = Enum.Font.GothamBlack
    Title.TextSize = 18
    Title.TextXAlignment = Enum.TextXAlignment.Center
end

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Size = UDim2.new(0, 32, 0, 32)
MinBtn.AnchorPoint = Vector2.new(0, 0.5)
MinBtn.Position = UDim2.new(1, -94, 0.5, 0)
MinBtn.BackgroundColor3 = THEME.Yellow
MinBtn.Text = "–"
MinBtn.TextColor3 = Color3.new(0, 0, 0)
MinBtn.Font = THEME.Font
MinBtn.TextSize = 16
corner(MinBtn, 8)

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.AnchorPoint = Vector2.new(0, 0.5)
CloseBtn.Position = UDim2.new(1, -44, 0.5, 0)
CloseBtn.BackgroundColor3 = THEME.Off
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.Font = THEME.Font
CloseBtn.TextSize = 16
corner(CloseBtn, 8)

-- ============================================================
-- TAB BAR  (ScrollingFrame horizontal supaya muat banyak tab)
-- ============================================================
local TabBar = Instance.new("ScrollingFrame", Frame)
TabBar.Size = UDim2.new(1, -24, 0, 32)
TabBar.Position = UDim2.new(0, 12, 0, 58)
TabBar.BackgroundTransparency = 1
TabBar.BorderSizePixel = 0
TabBar.ScrollBarThickness = 3
TabBar.ScrollBarImageColor3 = THEME.Title
TabBar.ScrollingDirection = Enum.ScrollingDirection.X
TabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
TabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
do
    local tbl = Instance.new("UIListLayout", TabBar)
    tbl.FillDirection = Enum.FillDirection.Horizontal
    tbl.Padding = UDim.new(0, 5)
    tbl.SortOrder = Enum.SortOrder.LayoutOrder
    tbl.VerticalAlignment = Enum.VerticalAlignment.Center
end

local tabButtons = {}
local tabBodies  = {}

local function makeScrollBody()
    local b = Instance.new("ScrollingFrame", Frame)
    b.Size = UDim2.new(1, -24, 1, -110)
    b.Position = UDim2.new(0, 12, 0, 98)
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.ScrollBarThickness = 5
    b.ScrollBarImageColor3 = THEME.Title
    b.AutomaticCanvasSize = Enum.AutomaticSize.Y
    b.CanvasSize = UDim2.new(0, 0, 0, 0)
    b.Visible = false
    local l = Instance.new("UIListLayout", b)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, 10)
    local p = Instance.new("UIPadding", b)
    p.PaddingTop = UDim.new(0, 6)
    p.PaddingBottom = UDim.new(0, 8)
    p.PaddingLeft = UDim.new(0, 6)
    p.PaddingRight = UDim.new(0, 10)  -- ekstra kanan supaya tidak ketutup scrollbar
    return b
end

local function setTabStyle(btn, on)
    btn.BackgroundColor3 = on and THEME.Title or THEME.Slot
    btn.TextColor3 = on and Color3.new(0, 0, 0) or THEME.Text
end

local function showTab(key)
    for k, body in pairs(tabBodies) do body.Visible = (k == key) end
    for k, btn in pairs(tabButtons) do setTabStyle(btn, k == key) end
end

-- tabOrder cuma dipakai addTab, jadi dibungkus do...end: registernya
-- dibebaskan saat blok selesai, dan yang tersisa di level teratas cuma
-- addTab. (Batas Luau: 200 register lokal per fungsi, dan seluruh script
-- ini SATU fungsi -- tiap nama di kolom nol hidup sampai baris terakhir.)
local addTab
do
    local tabOrder = 0
    addTab = function(key, text)
        tabOrder = tabOrder + 1
        local b = Instance.new("TextButton", TabBar)
        b.Size = UDim2.new(0, 96, 1, -4)
        b.BackgroundColor3 = THEME.Slot
        b.Text = text
        b.TextColor3 = THEME.Text
        b.Font = THEME.Font
        b.TextSize = 12
        b.LayoutOrder = tabOrder
        b.AutoButtonColor = true
        corner(b, 8)
        local body = makeScrollBody()
        tabButtons[key] = b
        tabBodies[key]  = body
        b.MouseButton1Click:Connect(function() showTab(key) end)
        return body
    end
end

local InfoBody     = addTab("info",     "i Info")
local AutoBody     = addTab("auto",     "⚡ Auto")
local FarmBody     = addTab("farm",     "🌱 Farm")
local ShopBody     = addTab("shop",     "🛒 Shop")
local BuildBody    = addTab("build",    "🔨 Build")
local CraftBody    = addTab("craft",    "💐 Craft")
local ExtraBody    = addTab("extra",    "🎁 Extra")
local SettingsBody = addTab("settings", "Settings")

-- ============================================================
-- OUTPUT TAB (console: On/Off, Copy, Clear)
-- ============================================================
-- SELURUH isi tab ini dibungkus do...end. Dulu ada 12 nama di level
-- teratas (logEnabled, logLines, tabOutBtn, OutputBody, outCtrl, octl,
-- outToggleBtn, outCopyBtn, outClearBtn, outputScroll, outPad,
-- outputLabel) padahal cuma DUA yang masih dipakai di luar blok ini:
--   logEnabled   -> dinyalakan paksa oleh kartu DEBUG & RE SPY
--   outToggleBtn -> tulisan/warnanya ikut disamakan di situ
-- Sepuluh sisanya tetap hidup sebagai UPVALUE milik addLog dan handler
-- tombolnya, jadi perilakunya persis sama -- cuma registernya dibebaskan
-- saat blok selesai.
local logEnabled, outToggleBtn = false, nil
do
    local logLines = {}

    local tabOutBtn = Instance.new("TextButton", TabBar)
    tabOutBtn.Size = UDim2.new(0, 96, 1, -4)
    tabOutBtn.BackgroundColor3 = THEME.Slot
    tabOutBtn.Text = "📜 Output"
    tabOutBtn.TextColor3 = THEME.Text
    tabOutBtn.Font = THEME.Font
    tabOutBtn.TextSize = 12
    tabOutBtn.LayoutOrder = 9      -- tab terakhir, sesudah 8 tab di atas
    corner(tabOutBtn, 8)

    local OutputBody = Instance.new("Frame", Frame)
    OutputBody.Size = UDim2.new(1, -24, 1, -110)
    OutputBody.Position = UDim2.new(0, 12, 0, 98)
    OutputBody.BackgroundTransparency = 1
    OutputBody.Visible = false
    tabButtons["output"] = tabOutBtn
    tabBodies["output"]  = OutputBody
    tabOutBtn.MouseButton1Click:Connect(function() showTab("output") end)

    local outCtrl = Instance.new("Frame", OutputBody)
    outCtrl.Size = UDim2.new(1, 0, 0, 30)
    outCtrl.BackgroundTransparency = 1
    local octl = Instance.new("UIListLayout", outCtrl)
    octl.FillDirection = Enum.FillDirection.Horizontal
    octl.Padding = UDim.new(0, 6)
    octl.SortOrder = Enum.SortOrder.LayoutOrder

    outToggleBtn = Instance.new("TextButton", outCtrl)
    outToggleBtn.Size = UDim2.new(0, 110, 1, 0)
    outToggleBtn.BackgroundColor3 = THEME.Off
    outToggleBtn.Text = "Output: OFF"
    outToggleBtn.TextColor3 = Color3.new(1, 1, 1)
    outToggleBtn.Font = THEME.Font
    outToggleBtn.TextSize = 12
    outToggleBtn.LayoutOrder = 1
    corner(outToggleBtn, 8)

    local outCopyBtn = Instance.new("TextButton", outCtrl)
    outCopyBtn.Size = UDim2.new(0, 110, 1, 0)
    outCopyBtn.BackgroundColor3 = THEME.Blue
    outCopyBtn.Text = "📋 Copy"
    outCopyBtn.TextColor3 = Color3.new(1, 1, 1)
    outCopyBtn.Font = THEME.Font
    outCopyBtn.TextSize = 12
    outCopyBtn.LayoutOrder = 2
    corner(outCopyBtn, 8)

    local outClearBtn = Instance.new("TextButton", outCtrl)
    outClearBtn.Size = UDim2.new(0, 90, 1, 0)
    outClearBtn.BackgroundColor3 = THEME.Purple
    outClearBtn.Text = "🗑 Clear"
    outClearBtn.TextColor3 = Color3.new(1, 1, 1)
    outClearBtn.Font = THEME.Font
    outClearBtn.TextSize = 12
    outClearBtn.LayoutOrder = 3
    corner(outClearBtn, 8)

    local outputScroll = Instance.new("ScrollingFrame", OutputBody)
    outputScroll.Size = UDim2.new(1, 0, 1, -36)
    outputScroll.Position = UDim2.new(0, 0, 0, 36)
    outputScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    outputScroll.BorderSizePixel = 0
    outputScroll.ScrollBarThickness = 5
    outputScroll.ScrollBarImageColor3 = THEME.Title
    outputScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    outputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    corner(outputScroll, 8)
    stroke(outputScroll, THEME.Stroke, 1)
    local outPad = Instance.new("UIPadding", outputScroll)
    outPad.PaddingLeft = UDim.new(0, 8); outPad.PaddingTop = UDim.new(0, 6)
    outPad.PaddingRight = UDim.new(0, 8); outPad.PaddingBottom = UDim.new(0, 6)

    local outputLabel = Instance.new("TextLabel", outputScroll)
    outputLabel.Size = UDim2.new(1, -8, 0, 0)
    outputLabel.AutomaticSize = Enum.AutomaticSize.Y
    outputLabel.BackgroundTransparency = 1
    outputLabel.Text = "[Output OFF] Tekan tombol 'Output: OFF' untuk mengaktifkan log..."
    outputLabel.TextColor3 = THEME.SubText
    outputLabel.Font = Enum.Font.Code
    outputLabel.TextSize = 12
    outputLabel.TextWrapped = true
    outputLabel.TextXAlignment = Enum.TextXAlignment.Left
    outputLabel.TextYAlignment = Enum.TextYAlignment.Top

    -- Tulisannya sudah berubah tapi belum dicetak ke layar karena tab
    -- Output sedang tidak dibuka. Dicetak sekali saat tabnya dibuka.
    local perluCetak = false
    local function cetakLog()
        perluCetak = false
        if outputLabel then
            outputLabel.Text = table.concat(logLines, "\n")
            outputLabel.TextColor3 = THEME.Text
        end
        if outputScroll then
            outputScroll.CanvasPosition = Vector2.new(0, 1e6)
        end
    end

    -- SENGAJA global (tanpa `local`): dipanggil dari mana-mana, dan
    -- global tidak memakan register sama sekali.
    --
    -- DICATAT SEKARANG, DICETAK NANTI. Menyusun ulang 250 baris jadi satu
    -- string tiap kali ada log masuk memaksa Roblox mengukur ulang teks +
    -- menata ulang ScrollingFrame - padahal addLog dipanggil tiap
    -- panen/tanam/checkout (di TURBO ratusan kali per detik) untuk layar
    -- yang sering tidak dibuka. Jadi pencetakannya ditunda sampai tab
    -- Output benar-benar terlihat. Tidak ada baris yang hilang.
    function addLog(msg, kind)
        if not logEnabled then return end
        local stamp = os.date("%H:%M:%S")
        local tag = kind and ("[" .. kind .. "] ") or ""
        table.insert(logLines, stamp .. " | " .. tag .. tostring(msg))
        if #logLines > 250 then table.remove(logLines, 1) end
        if OutputBody.Visible and Frame.Visible then cetakLog() else perluCetak = true end
    end

    -- Cetak yang tertunda begitu tab Output benar-benar terlihat.
    -- Ditempel ke sinyal Visible, BUKAN ke tombol tabnya: showTab("output")
    -- dipanggil juga dari tombol lain (List Semua Remote, RE SPY, PROMPT
    -- SPY, LIST SEMUA PROMPT), jadi kalau cuma ditempel di tombol tab,
    -- jalur-jalur itu akan membuka tab Output yang isinya masih basi.
    local function cetakKalauTerlihat()
        if perluCetak and OutputBody.Visible and Frame.Visible then cetakLog() end
    end
    track(OutputBody:GetPropertyChangedSignal("Visible"):Connect(cetakKalauTerlihat))
    track(Frame:GetPropertyChangedSignal("Visible"):Connect(cetakKalauTerlihat))

    outToggleBtn.MouseButton1Click:Connect(function()
        logEnabled = not logEnabled
        if logEnabled then
            outToggleBtn.Text = "Output: ON"
            TweenService:Create(outToggleBtn, tweenFast, {BackgroundColor3 = THEME.On}):Play()
            logLines = {}
            outputLabel.Text = ""
            addLog("Output logger ON", "INFO")
            addLog("Knit Services: " .. (KnitServices and "TERBACA" or "TIDAK KETEMU"), "INFO")
        else
            outToggleBtn.Text = "Output: OFF"
            TweenService:Create(outToggleBtn, tweenFast, {BackgroundColor3 = THEME.Off}):Play()
        end
    end)

    outCopyBtn.MouseButton1Click:Connect(function()
        local text = table.concat(logLines or {}, "\n")
        if text == "" then text = outputLabel.Text end
        if setclipboard then
            pcall(setclipboard, text)
            addLog("Output disalin ke clipboard", "INFO")
        else
            addLog("Executor tak support setclipboard", "ERROR")
        end
    end)

    outClearBtn.MouseButton1Click:Connect(function()
        logLines = {}
        outputLabel.Text = "[cleared]"
    end)
end

showTab("info")

-- ============================================================
-- UI HELPERS
-- ============================================================

local nextOrder
do
    local orderCounter = 0
    nextOrder = function() orderCounter = orderCounter + 1; return orderCounter end
end

-- section card container
local function makeCard(titleText, accent, parentOverride)
    local card = Instance.new("Frame", parentOverride or InfoBody)
    card.Size = UDim2.new(1, 0, 0, 40)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = THEME.Panel
    card.BorderSizePixel = 0
    card.LayoutOrder = nextOrder()
    corner(card, 10)
    stroke(card, accent or THEME.Stroke, 1)

    local bar = Instance.new("Frame", card)
    bar.Size = UDim2.new(0, 4, 1, -10)
    bar.Position = UDim2.new(0, 0, 0, 5)
    bar.BackgroundColor3 = accent or THEME.Title
    bar.BorderSizePixel = 0
    corner(bar, 4)

    local head = Instance.new("TextLabel", card)
    head.Size = UDim2.new(1, -28, 0, 26)
    head.Position = UDim2.new(0, 14, 0, 6)
    head.BackgroundTransparency = 1
    head.Text = titleText
    head.TextColor3 = accent or THEME.Title
    head.Font = THEME.Font
    head.TextSize = 13
    head.TextXAlignment = Enum.TextXAlignment.Left

    -- isi card: padding KIRI & KANAN simetris (14px) supaya rapih
    local holder = Instance.new("Frame", card)
    holder.Name = "Holder"
    holder.Size = UDim2.new(1, -28, 0, 0)
    holder.Position = UDim2.new(0, 14, 0, 34)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    local hl = Instance.new("UIListLayout", holder)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Padding = UDim.new(0, 8)
    local hp = Instance.new("UIPadding", holder)
    hp.PaddingBottom = UDim.new(0, 12)

    return holder
end

-- ON/OFF toggle row
--
-- PARAMETER KE-5 `kunci` - obat "dimatikan tapi tombolnya tetap ON".
-- Sakelar menyimpan tampilannya SENDIRI, dan itu cuma berubah kalau
-- DITEKAN. Jadi apa pun yang mematikan fitur lewat jalur lain (tombol
-- massal, MODE UANG MAKSIMUM, loop yang berhenti sendiri) tidak ikut
-- membalik gambarnya.
--
-- `kunci` = nama field di `state` yang digerakkan sakelar ini. Kalau
-- diisi, samakanSakelar() bisa menyamakan SEMUA tampilan dengan isi
-- `state` - satu arah, dari kenyataan ke gambar.
--
-- Sakelar yang menggerakkan `config` (bukan `state`) sengaja TIDAK
-- diberi kunci: itu pilihan tersimpan, bukan fitur yang jalan.
local makeToggle
do
    local daftar = {}

    -- SENGAJA global (tanpa `local`), seperti addLog: dipanggil dari
    -- tombol yang letaknya jauh di bawah, dan global tidak memakan
    -- register sama sekali (batas Luau 200 per fungsi).
    function samakanSakelar()
        for _, e in ipairs(daftar) do
            pcall(e.set, state[e.kunci] == true)
        end
    end

makeToggle = function(parent, label, accent, onChanged, kunci)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = THEME.Slot
    row.BorderSizePixel = 0
    row.LayoutOrder = nextOrder()
    corner(row, 8)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(1, -80, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = THEME.Text
    lbl.Font = THEME.FontReg
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0, 58, 0, 24)
    btn.Position = UDim2.new(1, -66, 0.5, -12)
    btn.BackgroundColor3 = THEME.Off
    btn.Text = "OFF"
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = THEME.Font
    btn.TextSize = 12
    corner(btn, 12)

    local isOn = false
    local function setVisual(v)
        isOn = v
        btn.Text = v and "ON" or "OFF"
        TweenService:Create(btn, tweenFast, {BackgroundColor3 = v and THEME.On or THEME.Off}):Play()
    end
    btn.MouseButton1Click:Connect(function()
        setVisual(not isOn)
        onChanged(isOn)
    end)
    if kunci then daftar[#daftar + 1] = { kunci = kunci, set = setVisual } end
    return setVisual
end
end

-- slider row — angka di KANAN bisa DIKLIK untuk ketik nilai tepat
local function makeSlider(parent, label, val, minv, maxv, accent, onChanged)
    local con = Instance.new("Frame", parent)
    con.Size = UDim2.new(1, 0, 0, 40)
    con.BackgroundColor3 = THEME.Slot
    con.BorderSizePixel = 0
    con.LayoutOrder = nextOrder()
    corner(con, 8)

    local lbl = Instance.new("TextLabel", con)
    lbl.Size = UDim2.new(1, -78, 0, 18)
    lbl.Position = UDim2.new(0, 12, 0, 3)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = THEME.Text
    lbl.Font = THEME.FontReg
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- ============================================================
    -- DESIMAL + SATUAN " s" HANYA UNTUK SLIDER DELAY
    -- ============================================================
    -- Pembedanya BATAS BAWAH, bukan lebar rentang. Aturan lamanya
    -- (maxv - minv) <= 10 dan itu SALAH: slider "Jumlah accent /
    -- rangkaian" (1-5), "Minimal Bintang" (1-5), dan "Pilihan dialog
    -- ke-" (1-6) ikut kena, jadi kotaknya menulis "5.00 s" untuk sesuatu
    -- yang satuannya BUAH. Itu angka 5.00 yang bikin bingung.
    --
    -- Semua slider delay batas bawahnya DI BAWAH 1 (0.05 / 0.1 / 0.5),
    -- dan semua slider hitungan batas bawahnya 1 atau lebih. Jadi minv
    -- membedakannya dengan tepat, tanpa perlu menambah parameter baru.
    local decimals = (minv < 1) and 2 or 0
    local function fmt(v)
        if decimals > 0 then return string.format("%." .. decimals .. "f", v) .. " s" end
        return tostring(math.floor(v))
    end

    local valBox = Instance.new("TextBox", con)
    valBox.Size = UDim2.new(0, 54, 0, 18)
    valBox.Position = UDim2.new(1, -60, 0, 3)
    valBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    valBox.BackgroundTransparency = 0.15
    valBox.Text = fmt(val)
    valBox.PlaceholderText = fmt(val)
    valBox.TextColor3 = THEME.Title
    valBox.Font = THEME.Font
    valBox.TextSize = 12
    valBox.TextXAlignment = Enum.TextXAlignment.Center
    valBox.ClearTextOnFocus = false
    valBox.ZIndex = 4
    corner(valBox, 6)
    stroke(valBox, THEME.Stroke, 1)

    local line = Instance.new("Frame", con)
    line.Size = UDim2.new(1, -24, 0, 6)
    line.Position = UDim2.new(0, 12, 0, 26)
    line.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
    line.BorderSizePixel = 0
    corner(line, 4)

    local pct0 = (val - minv) / (maxv - minv)
    local fill = Instance.new("Frame", line)
    fill.Size = UDim2.new(pct0, 0, 1, 0)
    fill.BackgroundColor3 = accent or THEME.Cyan
    fill.BorderSizePixel = 0
    corner(fill, 4)

    local knob = Instance.new("Frame", line)
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(pct0, -7, 0.5, -7)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    corner(knob, 7)

    local hit = Instance.new("TextButton", con)
    hit.Size = UDim2.new(1, -24, 0, 24)
    hit.Position = UDim2.new(0, 12, 0, 18)
    hit.BackgroundTransparency = 1
    hit.Text = ""

    local current = val
    local function applyVal(newVal)
        newVal = math.clamp(newVal, minv, maxv)
        if decimals == 0 then newVal = math.floor(newVal + 0.5) end
        current = newVal
        local pct = (newVal - minv) / (maxv - minv)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, -7, 0.5, -7)
        valBox.Text = fmt(newVal)
        onChanged(newVal)
    end

    valBox.FocusLost:Connect(function()
        local n = tonumber((string.gsub(valBox.Text, "%s*s$", "")))
        if n then applyVal(n) else valBox.Text = fmt(current) end
    end)

    local dragging = false
    local function upd(px)
        local rel = px - line.AbsolutePosition.X
        local pct = math.clamp(rel / math.max(line.AbsoluteSize.X, 1), 0, 1)
        applyVal(minv + pct * (maxv - minv))
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; upd(i.Position.X)
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            upd(i.Position.X)
        end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return applyVal
end

-- ============================================================
-- KOTAK ANGKA + TOMBOL  -  /  +   (bisa DIKETIK, bisa DIKLIK)
-- ============================================================
-- Kenapa bukan slider seperti kontrol lain di hub ini: slider itu untuk
-- memilih RASA (delay, skala GUI) - digeser sampai "kira-kira pas".
-- Yang ini JUMLAH BARANG, dan biasanya kamu sudah tahu angkanya persis.
-- Menggeser slider sampai berhenti TEPAT di 37 lewat layar sentuh itu
-- menyiksa; mengetik "37" tidak.
--
-- Jadi dua jalur sekaligus: KETIK untuk lompat jauh, tekan +/- untuk
-- mengoreksi satu-satu.
--
-- `kunci` = nama field di `config` yang digerakkan kotak ini. Itu yang
-- membuat samakanAngka() bisa menyamakan SEMUA kotak yang mengatur
-- angka yang SAMA - kotak "Jumlah bibit" di tab Shop dan kembarannya di
-- tab Auto tidak akan pernah menampilkan dua angka berbeda. Ini masalah
-- yang PERSIS sama dengan sakelar ON/OFF kembar yang dulu bisa saling
-- berbohong, jadi obatnya juga sama.
local makeNumber
do
    local daftar = {}

    -- SENGAJA global (tanpa `local`), seperti samakanSakelar: dipanggil
    -- dari loadSettings yang letaknya jauh di bawah, dan global tidak
    -- memakan register sama sekali (batas Luau 200 per fungsi).
    function samakanAngka()
        for _, e in ipairs(daftar) do
            pcall(e.set, config[e.kunci])
        end
    end

makeNumber = function(parent, label, minv, maxv, accent, kunci, onChanged)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = THEME.Slot
    row.BorderSizePixel = 0
    row.LayoutOrder = nextOrder()
    corner(row, 8)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(1, -132, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = THEME.Text
    lbl.Font = THEME.FontReg
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- Dibuat lewat satu pembantu supaya dua tombolnya DIJAMIN sama
    -- ukuran & gayanya - kalau ditulis dua kali, satu perubahan gaya
    -- gampang lupa disalin ke satunya.
    local function tombol(x, teks)
        local b = Instance.new("TextButton", row)
        b.Size = UDim2.new(0, 26, 0, 24)
        b.Position = UDim2.new(1, x, 0.5, -12)
        b.BackgroundColor3 = accent or THEME.Blue
        b.Text = teks
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = THEME.Font
        b.TextSize = 16
        b.BorderSizePixel = 0
        corner(b, 6)
        return b
    end
    local kurang = tombol(-122, "-")
    local tambah = tombol(-32, "+")

    local box = Instance.new("TextBox", row)
    box.Size = UDim2.new(0, 56, 0, 24)
    box.Position = UDim2.new(1, -92, 0.5, -12)
    box.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    box.BackgroundTransparency = 0.15
    box.Text = tostring(math.floor(tonumber(config[kunci]) or minv))
    box.TextColor3 = THEME.Title
    box.Font = THEME.Font
    box.TextSize = 13
    box.TextXAlignment = Enum.TextXAlignment.Center
    box.ClearTextOnFocus = false
    corner(box, 6)
    stroke(box, THEME.Stroke, 1)

    local function setVisual(v)
        box.Text = tostring(math.clamp(math.floor(tonumber(v) or minv), minv, maxv))
    end

    -- SATU PINTU untuk ketik MAUPUN tombol. Ini bukan kerapian: kalau
    -- tiap jalur menulis config sendiri-sendiri, cepat atau lambat ada
    -- jalur yang mengubah angka tanpa memperbarui kotaknya (atau
    -- sebaliknya) - dan kotak yang menampilkan angka lain daripada yang
    -- dipakai itu kebohongan yang sama dengan sakelar mengaku mati.
    local function pakai(v)
        v = math.clamp(math.floor(tonumber(v) or minv), minv, maxv)
        config[kunci] = v
        samakanAngka()   -- kembarannya di tab lain ikut berubah
        if onChanged then onChanged(v) end
    end

    kurang.MouseButton1Click:Connect(function() pakai((tonumber(config[kunci]) or minv) - 1) end)
    tambah.MouseButton1Click:Connect(function() pakai((tonumber(config[kunci]) or minv) + 1) end)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        -- Ketikan ngawur TIDAK diam-diam jadi angka lain: kotaknya
        -- dikembalikan ke nilai yang sebenarnya dipakai.
        if n then pakai(n) else setVisual(config[kunci]) end
    end)

    daftar[#daftar + 1] = { kunci = kunci, set = setVisual }
    return setVisual
end
end

-- generic button
local function makeButton(parent, label, bg, onClick)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(1, 0, 0, 30)
    b.BackgroundColor3 = bg
    b.Text = label
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = THEME.Font
    b.TextSize = 12
    b.LayoutOrder = nextOrder()
    b.BorderSizePixel = 0
    corner(b, 8)
    b.MouseButton1Click:Connect(onClick)
    return b
end

-- label info (read-only)
local function makeInfo(parent, text)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(1, 0, 0, 0)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.BackgroundColor3 = THEME.Slot
    l.BackgroundTransparency = 0.25
    l.Text = text
    l.TextColor3 = THEME.SubText
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = nextOrder()
    corner(l, 6)
    local p = Instance.new("UIPadding", l)
    p.PaddingLeft = UDim.new(0, 8); p.PaddingRight = UDim.new(0, 8)
    p.PaddingTop = UDim.new(0, 6);  p.PaddingBottom = UDim.new(0, 6)
    return l
end

-- ============================================================
-- tampil() - INI YANG MENAHAN LAG PALING BESAR
-- ============================================================
-- Ada 15 label hidup di panel ini, masing-masing loop `while
-- ScreenGui.Parent do ... end`. Syaratnya "SELAMA GUI ADA" - bukan
-- "selama tabnya dibuka" - jadi mematikan semua fitur auto tidak
-- menghentikan satupun. Isinya mahal: farmSummary() menyisir SEMUA
-- planter x SEMUA slot, growSummary() idem, getTagged() menyisir
-- CollectionService, dan satu label memanggil server tiap 6 detik.
--
-- tampil() memotongnya: isi loop cuma jalan kalau panel TERBUKA dan tab
-- pemiliknya AKTIF. Loopnya sendiri tetap hidup (murah: satu task.wait),
-- jadi begitu tabnya dibuka datanya langsung terisi lagi.
--
-- Frame.Visible ikut diperiksa supaya minimize dan [RightShift]
-- benar-benar MENGHENTIKAN kerjanya, bukan menyembunyikan hasilnya.
--
-- SENGAJA global: dipanggil dari 15 blok do...end, dan global tidak
-- memakan register sama sekali (batas Luau 200 per fungsi).
function tampil(body)
    return Frame.Visible and body.Visible
end

-- ------------------------------------------------------------
-- REGISTRY DROPDOWN
--   Tanpa ini DUA dropdown bisa terbuka bersamaan dan daftarnya saling
--   menimpa -- persis "kotak melayang" yang kelihatan di foto. Membuka
--   satu dropdown otomatis menutup semua yang lain.
--   Nilai ZIndex saat terbuka juga dinaikkan ke 120+ supaya menang dari
--   baris manapun (baris biasa ZIndex 1, dropdown tertutup 5, grip 60).
-- ------------------------------------------------------------
--   CATATAN: yang dinaikkan ZIndex-nya HANYA daftar pilihannya (500+),
--   BUKAN frame barisnya. Kalau frame baris (con) yang dinaikkan, dengan
--   mode Global background-nya justru menutupi label/panah miliknya sendiri
--   yang ZIndex-nya cuma 6.
-- DD menampung SEMUA milik dropdown dalam satu nama supaya tidak menambah
-- register lokal di main chunk (batas Luau: 200 per fungsi).
--   DD.closers = { [id] = fungsi penutup }
--   DD.blocker = tombol layar-penuh tak terlihat (lihat dropdownBlocker)
local DD = { closers = {}, blocker = nil }

local function closeOtherDropdowns(exceptId)
    for id, fn in pairs(DD.closers) do
        if id ~= exceptId then pcall(fn) end
    end
end

-- MEMBATALKAN DROPDOWN TANPA MEMILIH.
-- Dulu satu-satunya cara menutup daftar adalah menekan ULANG baris
-- dropdown-nya -- dan baris itu sering ketutup daftarnya sendiri, jadi
-- praktis tidak ada jalan mundur. Sekarang ada lapisan transparan
-- selebar layar yang dipasang TEPAT DI BAWAH daftar (ZIndex 499 vs 500):
-- klik/tap di mana saja di luar daftar = tutup, tidak ada yang terpilih.
-- Dibuat malas, jadi tidak menambah beban saat execute.
local function dropdownBlocker()
    if DD.blocker then return DD.blocker end
    local b = Instance.new("TextButton")
    b.Name = "DropdownBlocker"
    b.Size = UDim2.new(1, 0, 1, 0)
    b.BackgroundTransparency = 1
    b.Text = ""
    b.AutoButtonColor = false
    b.Visible = false
    b.ZIndex = 499
    b.Parent = ScreenGui
    -- exceptId nil -> semua closer dipanggil, jadi apapun yang terbuka tertutup
    b.MouseButton1Click:Connect(function() closeOtherDropdowns(nil) end)
    DD.blocker = b
    return b
end

-- ------------------------------------------------------------
-- DROPDOWN SATU-PILIHAN
-- ------------------------------------------------------------
local function makeDropdown(parent, label, getItems, onSelect, defaultText)
    local con = Instance.new("Frame", parent)
    con.Size = UDim2.new(1, 0, 0, 34)
    con.BackgroundColor3 = THEME.Slot
    con.BorderSizePixel = 0
    con.LayoutOrder = nextOrder()
    con.ZIndex = 5
    corner(con, 8)

    local name = Instance.new("TextLabel", con)
    name.Size = UDim2.new(0.5, -10, 1, 0)
    name.Position = UDim2.new(0, 12, 0, 0)
    name.BackgroundTransparency = 1
    name.Text = label
    name.TextColor3 = THEME.Text
    name.Font = THEME.FontReg
    name.TextSize = 13
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.ZIndex = 6

    local disp = Instance.new("TextLabel", con)
    disp.Size = UDim2.new(0.5, -34, 1, 0)
    disp.Position = UDim2.new(0.5, 0, 0, 0)
    disp.BackgroundTransparency = 1
    disp.Text = defaultText or "None"
    disp.TextColor3 = THEME.SubText
    disp.Font = THEME.FontReg
    disp.TextSize = 12
    disp.TextXAlignment = Enum.TextXAlignment.Right
    disp.TextTruncate = Enum.TextTruncate.AtEnd
    disp.ZIndex = 6

    local arr = Instance.new("TextLabel", con)
    arr.Size = UDim2.new(0, 26, 1, 0)
    arr.Position = UDim2.new(1, -28, 0, 0)
    arr.BackgroundTransparency = 1
    arr.Text = "▼"
    arr.TextColor3 = THEME.Title
    arr.Font = THEME.Font
    arr.TextSize = 12
    arr.ZIndex = 6

    local trig = Instance.new("TextButton", con)
    trig.Size = UDim2.new(1, 0, 1, 0)
    trig.BackgroundTransparency = 1
    trig.Text = ""
    trig.ZIndex = 7

    -- Daftar pilihan diparkir LANGSUNG di ScreenGui, BUKAN di dalam baris.
    -- Alasannya: baris ini tinggal di dalam ScrollingFrame tab, dan
    -- ScrollingFrame SELALU memotong isinya. Daftar yang panjang jadi
    -- terpotong dan sisanya kelihatan seperti kotak-kotak nyangkut di tepi
    -- layar -- ZIndex setinggi apapun tidak menolong, karena pemotongan
    -- terjadi SEBELUM penumpukan. Sebagai anak ScreenGui daftar ini bebas
    -- dari pemotongan; posisinya dihitung manual di listGeom() di bawah.
    --
    -- DIBUAT MALAS (lazy). Ada 32 dropdown di script ini. Kalau semuanya
    -- dibangun saat execute, itu ~190 objek GUI ekstra yang lahir dalam
    -- satu jalan tanpa jeda, DAN 32 anak permanen ScreenGui yang ikut
    -- disortir tiap frame -- ZIndexBehavior.Global menyortir SELURUH pohon
    -- GUI, bukan cuma antar-saudara. Sebagian besar dropdown tidak pernah
    -- disentuh, jadi tidak ada gunanya dibuat di depan.
    local list
    local function getList()
        if list then return list end
        local l = Instance.new("ScrollingFrame")
        l.Size = UDim2.fromOffset(0, 0)
        l.BackgroundColor3 = THEME.Panel
        l.BorderSizePixel = 0
        l.ScrollBarThickness = 4
        l.ScrollBarImageColor3 = THEME.Title
        l.Visible = false
        l.ZIndex = 500          -- 500 = di atas SEMUA (mode ZIndex Global)
        l.ClipsDescendants = true
        corner(l, 8)
        stroke(l, THEME.Title, 1)
        local ll = Instance.new("UIListLayout", l)
        ll.SortOrder = Enum.SortOrder.LayoutOrder
        ll.Padding = UDim.new(0, 2)
        local lp = Instance.new("UIPadding", l)
        lp.PaddingTop = UDim.new(0, 3); lp.PaddingLeft = UDim.new(0, 3); lp.PaddingRight = UDim.new(0, 3)
        -- parent dipasang TERAKHIR: satu kali reflow, bukan sekali per properti
        l.Parent = ScreenGui
        list = l
        return l
    end

    -- Karena daftar ini anak ScreenGui (bukan anak barisnya), lebar & posisinya
    -- HARUS dihitung sendiri dari baris induk. AbsolutePosition/AbsoluteSize
    -- sudah dikali UIScale, jadi dibagi lagi supaya tidak dobel-skala.
    -- Balikan: lebar, x, y  (y = tepat di bawah baris induk).
    local function listGeom()
        local s = math.max(UIScale.Scale, 0.01)
        local ap, as = con.AbsolutePosition, con.AbsoluteSize
        return as.X / s, ap.X / s, (ap.Y + as.Y + 4) / s
    end

    local selectedValue = nil
    local isOpen = false
    local myId = {}   -- identitas unik dropdown ini di registry

    local function closeList()
        isOpen = false
        arr.Text = "▼"
        if DD.blocker then DD.blocker.Visible = false end
        -- Dropdown yang belum pernah dibuka belum punya objek daftar sama
        -- sekali. closeOtherDropdowns() memanggil SEMUA closer, jadi jalur
        -- ini normal dilewati -- bukan kondisi error.
        if not list then return end
        local w = select(1, listGeom())
        TweenService:Create(list, tweenFast, { Size = UDim2.fromOffset(w, 0) }):Play()
        task.delay(0.2, function() if list then list.Visible = false end end)
    end
    DD.closers[myId] = closeList

    local function rebuild()
        local lst = getList()
        for _, c in ipairs(lst:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local items = type(getItems) == "function" and getItems() or getItems

        -- BARIS BATAL: jalan keluar yang KELIHATAN. Tanpa ini pemakai harus
        -- menebak sendiri bahwa menekan ulang baris dropdown akan menutupnya.
        local cancel = Instance.new("TextButton", lst)
        cancel.Size = UDim2.new(1, -6, 0, 24)
        cancel.BackgroundColor3 = THEME.Off
        cancel.Text = "X TUTUP (batal, tidak memilih)"
        cancel.TextColor3 = Color3.new(1, 1, 1)
        cancel.Font = THEME.Font
        cancel.TextSize = 11
        cancel.LayoutOrder = -1
        cancel.ZIndex = 501
        corner(cancel, 6)
        cancel.MouseButton1Click:Connect(function() closeList() end)

        for i, item in ipairs(items) do
            local opt = Instance.new("TextButton", lst)
            opt.Size = UDim2.new(1, -6, 0, 26)
            opt.BackgroundColor3 = THEME.Slot
            opt.Text = "  " .. item
            opt.TextColor3 = THEME.Text
            opt.Font = THEME.FontReg
            opt.TextSize = 12
            opt.TextXAlignment = Enum.TextXAlignment.Left
            opt.TextTruncate = Enum.TextTruncate.AtEnd
            opt.LayoutOrder = i
            opt.ZIndex = 501
            corner(opt, 6)
            opt.MouseButton1Click:Connect(function()
                selectedValue = item
                disp.Text = item
                disp.TextColor3 = THEME.Title
                closeList()
                onSelect(item)
            end)
        end
        lst.CanvasSize = UDim2.new(0, 0, 0, (#items + 1) * 28 + 6)
    end

    trig.MouseButton1Click:Connect(function()
        if isOpen then closeList(); return end
        closeOtherDropdowns(myId)   -- cuma boleh SATU dropdown terbuka
        local lst = getList()       -- baru dibangun di sini kalau ini kali pertama
        rebuild()
        isOpen = true
        local w, x, y = listGeom()
        lst.Position = UDim2.fromOffset(x, y)
        lst.Size     = UDim2.fromOffset(w, 0)
        lst.Visible  = true
        -- dipasang SESUDAH closeOtherDropdowns, karena tiap closeList
        -- menyembunyikan blocker
        dropdownBlocker().Visible = true
        local items = type(getItems) == "function" and getItems() or getItems
        local h = math.min((#items + 1) * 28 + 6, 160)
        TweenService:Create(lst, tweenFast, { Size = UDim2.fromOffset(w, h) }):Play()
        arr.Text = "▲"
    end)

    return function() return selectedValue end
end

-- ------------------------------------------------------------
-- DROPDOWN MULTI-PILIHAN  (tampil "None" / nama / "Various")
--   store    = tabel set { ["Rose Seed"] = true }
--   emptyTxt = teks saat kosong ("None" atau "Semua")
-- ------------------------------------------------------------
local function makeMultiDropdown(parent, label, getItems, store, emptyTxt, mapValue)
    local con = Instance.new("Frame", parent)
    con.Size = UDim2.new(1, 0, 0, 34)
    con.BackgroundColor3 = THEME.Slot
    con.BorderSizePixel = 0
    con.LayoutOrder = nextOrder()
    con.ZIndex = 5
    corner(con, 8)

    local name = Instance.new("TextLabel", con)
    name.Size = UDim2.new(0.55, -10, 1, 0)
    name.Position = UDim2.new(0, 12, 0, 0)
    name.BackgroundTransparency = 1
    name.Text = label
    name.TextColor3 = THEME.Text
    name.Font = THEME.FontReg
    name.TextSize = 13
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.ZIndex = 6

    local disp = Instance.new("TextLabel", con)
    disp.Size = UDim2.new(0.45, -34, 1, 0)
    disp.Position = UDim2.new(0.55, 0, 0, 0)
    disp.BackgroundTransparency = 1
    disp.TextColor3 = THEME.SubText
    disp.Font = THEME.FontReg
    disp.TextSize = 12
    disp.TextXAlignment = Enum.TextXAlignment.Right
    disp.TextTruncate = Enum.TextTruncate.AtEnd
    disp.ZIndex = 6

    local arr = Instance.new("TextLabel", con)
    arr.Size = UDim2.new(0, 26, 1, 0)
    arr.Position = UDim2.new(1, -28, 0, 0)
    arr.BackgroundTransparency = 1
    arr.Text = "▼"
    arr.TextColor3 = THEME.Title
    arr.Font = THEME.Font
    arr.TextSize = 12
    arr.ZIndex = 6

    local trig = Instance.new("TextButton", con)
    trig.Size = UDim2.new(1, 0, 1, 0)
    trig.BackgroundTransparency = 1
    trig.Text = ""
    trig.ZIndex = 7

    -- Daftar pilihan diparkir LANGSUNG di ScreenGui, BUKAN di dalam baris.
    -- Alasannya: baris ini tinggal di dalam ScrollingFrame tab, dan
    -- ScrollingFrame SELALU memotong isinya. Daftar yang panjang jadi
    -- terpotong dan sisanya kelihatan seperti kotak-kotak nyangkut di tepi
    -- layar -- ZIndex setinggi apapun tidak menolong, karena pemotongan
    -- terjadi SEBELUM penumpukan. Sebagai anak ScreenGui daftar ini bebas
    -- dari pemotongan; posisinya dihitung manual di listGeom() di bawah.
    --
    -- DIBUAT MALAS (lazy). Ada 32 dropdown di script ini. Kalau semuanya
    -- dibangun saat execute, itu ~190 objek GUI ekstra yang lahir dalam
    -- satu jalan tanpa jeda, DAN 32 anak permanen ScreenGui yang ikut
    -- disortir tiap frame -- ZIndexBehavior.Global menyortir SELURUH pohon
    -- GUI, bukan cuma antar-saudara. Sebagian besar dropdown tidak pernah
    -- disentuh, jadi tidak ada gunanya dibuat di depan.
    local list
    local function getList()
        if list then return list end
        local l = Instance.new("ScrollingFrame")
        l.Size = UDim2.fromOffset(0, 0)
        l.BackgroundColor3 = THEME.Panel
        l.BorderSizePixel = 0
        l.ScrollBarThickness = 4
        l.ScrollBarImageColor3 = THEME.Title
        l.Visible = false
        l.ZIndex = 500          -- 500 = di atas SEMUA (mode ZIndex Global)
        l.ClipsDescendants = true
        corner(l, 8)
        stroke(l, THEME.Title, 1)
        local ll = Instance.new("UIListLayout", l)
        ll.SortOrder = Enum.SortOrder.LayoutOrder
        ll.Padding = UDim.new(0, 2)
        local lp = Instance.new("UIPadding", l)
        lp.PaddingTop = UDim.new(0, 3); lp.PaddingLeft = UDim.new(0, 3); lp.PaddingRight = UDim.new(0, 3)
        -- parent dipasang TERAKHIR: satu kali reflow, bukan sekali per properti
        l.Parent = ScreenGui
        list = l
        return l
    end

    -- Karena daftar ini anak ScreenGui (bukan anak barisnya), lebar & posisinya
    -- HARUS dihitung sendiri dari baris induk. AbsolutePosition/AbsoluteSize
    -- sudah dikali UIScale, jadi dibagi lagi supaya tidak dobel-skala.
    -- Balikan: lebar, x, y  (y = tepat di bawah baris induk).
    local function listGeom()
        local s = math.max(UIScale.Scale, 0.01)
        local ap, as = con.AbsolutePosition, con.AbsoluteSize
        return as.X / s, ap.X / s, (ap.Y + as.Y + 4) / s
    end

    -- teks ringkas: kosong -> emptyTxt, 1 -> namanya, >1 -> "Various"
    local function refreshDisplay()
        local n = setCount(store)
        if n == 0 then
            disp.Text = emptyTxt or "None"
            disp.TextColor3 = THEME.SubText
        elseif n == 1 then
            disp.Text = setList(store)[1]
            disp.TextColor3 = THEME.Title
        else
            disp.Text = "Various (" .. n .. ")"
            disp.TextColor3 = THEME.Title
        end
    end
    refreshDisplay()

    local isOpen = false
    local myId = {}   -- identitas unik dropdown ini di registry

    local function closeList()
        isOpen = false
        arr.Text = "▼"
        if DD.blocker then DD.blocker.Visible = false end
        -- Dropdown yang belum pernah dibuka belum punya objek daftar sama
        -- sekali. closeOtherDropdowns() memanggil SEMUA closer, jadi jalur
        -- ini normal dilewati -- bukan kondisi error.
        if not list then return end
        local w = select(1, listGeom())
        TweenService:Create(list, tweenFast, { Size = UDim2.fromOffset(w, 0) }):Play()
        task.delay(0.2, function() if list then list.Visible = false end end)
    end
    DD.closers[myId] = closeList

    local function rebuild()
        local lst = getList()
        for _, c in ipairs(lst:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local items = type(getItems) == "function" and getItems() or getItems

        -- BARIS BATAL. Untuk dropdown multi ini justru lebih penting: tiap
        -- centang LANGSUNG tersimpan, jadi yang dibutuhkan pemakai adalah
        -- cara MENUTUP daftarnya -- bukan cara "membatalkan pilihan".
        local cancel = Instance.new("TextButton", lst)
        cancel.Size = UDim2.new(1, -6, 0, 24)
        cancel.BackgroundColor3 = THEME.Off
        cancel.Text = "X TUTUP (selesai)"
        cancel.TextColor3 = Color3.new(1, 1, 1)
        cancel.Font = THEME.Font
        cancel.TextSize = 11
        cancel.LayoutOrder = -1
        cancel.ZIndex = 501
        corner(cancel, 6)
        cancel.MouseButton1Click:Connect(function() closeList() end)

        -- baris cepat: pilih semua / bersihkan
        local quick = Instance.new("TextButton", lst)
        quick.Size = UDim2.new(1, -6, 0, 24)
        quick.BackgroundColor3 = THEME.Purple
        quick.Text = "* Pilih Semua / Bersihkan"
        quick.TextColor3 = Color3.new(1, 1, 1)
        quick.Font = THEME.Font
        quick.TextSize = 11
        quick.LayoutOrder = 0
        quick.ZIndex = 501
        corner(quick, 6)

        -- ============================================================
        -- YANG DITULIS ITU `teks`, BUKAN `key` - INI BUG SAYA
        -- ============================================================
        -- Barisnya DULU berbunyi:
        --     btn.Text = (on and "  [x]  " or "  [ ]  ") .. key
        --
        -- `key` itu hasil mapValue(item), dan untuk hampir semua dropdown
        -- di hub ini mapValue = stripLabel - yang tugasnya MEMBUANG bagian
        -- "  [...]". Jadi labelnya dibangun lengkap dengan harga, level,
        -- PACK, VIP... lalu DIPOTONG lagi tepat sebelum digambar.
        --
        -- Akibatnya SELURUH tanda di dropdown multi tidak pernah kelihatan:
        -- harga bibit, "LEVEL KURANG - butuh Lv150", "TIDAK DIJUAL - dari
        -- Rare Seed Pack", "[VIP]", "-60s | $100", harga hire per bintang.
        -- Semuanya dihitung dengan benar, semuanya dibuang di baris ini.
        --
        -- Ini juga yang bikin saya salah menyimpulkan kemarin: saya kira
        -- kamu belum execute ulang, padahal kotak TOTAL di bawah kotak
        -- JUMLAH sudah menampilkan "$17.00K" dengan benar - bukti bahwa
        -- harganya memang sudah terbaca dan cuma tidak tergambar.
        --
        -- Yang DISIMPAN tetap `key` (nama asli), jadi konfigurasi lama dan
        -- semua pembanding nama di hub ini tidak berubah sama sekali.
        local rows = {}
        local function paint(btn, key, teks)
            local on = store[key] == true
            btn.BackgroundColor3 = on and THEME.On or THEME.Slot
            btn.Text = (on and "  [x]  " or "  [ ]  ") .. (teks or key)
        end

        for i, item in ipairs(items) do
            local key = mapValue and mapValue(item) or item
            local opt = Instance.new("TextButton", lst)
            opt.Size = UDim2.new(1, -6, 0, 26)
            opt.TextColor3 = THEME.Text
            opt.Font = THEME.FontReg
            opt.TextSize = 12
            opt.TextXAlignment = Enum.TextXAlignment.Left
            opt.TextTruncate = Enum.TextTruncate.AtEnd
            opt.LayoutOrder = i
            opt.ZIndex = 501
            corner(opt, 6)
            paint(opt, key, item)
            -- Label ikut disimpan: tombol "Pilih Semua / Bersihkan" di bawah
            -- menggambar ulang SEMUA baris, dan tanpa labelnya dia akan
            -- mengembalikan bug yang barusan diperbaiki.
            rows[key] = { b = opt, l = item }
            opt.MouseButton1Click:Connect(function()
                store[key] = not store[key] or nil
                paint(opt, key, item)
                refreshDisplay()
            end)
        end

        quick.MouseButton1Click:Connect(function()
            if setIsEmpty(store) then
                for _, item in ipairs(items) do
                    local key = mapValue and mapValue(item) or item
                    store[key] = true
                end
            else
                for k in pairs(store) do store[k] = nil end
            end
            for key, r in pairs(rows) do paint(r.b, key, r.l) end
            refreshDisplay()
        end)

        lst.CanvasSize = UDim2.new(0, 0, 0, (#items + 2) * 28 + 6)
    end

    trig.MouseButton1Click:Connect(function()
        if isOpen then closeList(); return end
        closeOtherDropdowns(myId)   -- cuma boleh SATU dropdown terbuka
        local lst = getList()       -- baru dibangun di sini kalau ini kali pertama
        rebuild()
        isOpen = true
        local w, x, y = listGeom()
        lst.Position = UDim2.fromOffset(x, y)
        lst.Size     = UDim2.fromOffset(w, 0)
        lst.Visible  = true
        -- dipasang SESUDAH closeOtherDropdowns, karena tiap closeList
        -- menyembunyikan blocker
        dropdownBlocker().Visible = true
        local items = type(getItems) == "function" and getItems() or getItems
        local h = math.min((#items + 2) * 28 + 6, 170)
        TweenService:Create(lst, tweenFast, { Size = UDim2.fromOffset(w, h) }):Play()
        arr.Text = "▲"
    end)

    return refreshDisplay
end

-- ============================================================
-- DRAG MAIN FRAME
-- ============================================================
do
    local dragging, dragStart, startPos = false, nil, nil
    Header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = Frame.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = (i.Position - dragStart) / UIScale.Scale
            Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ============================================================
-- RESIZE GRIP (pojok kanan-bawah): besarkan / kecilkan GUI
-- ============================================================
do
    local grip = Instance.new("TextButton", Frame)
    grip.Name = "ResizeGrip"
    grip.AnchorPoint = Vector2.new(1, 1)
    grip.Size = UDim2.fromOffset(22, 22)
    grip.Position = UDim2.new(1, -4, 1, -4)
    grip.BackgroundColor3 = THEME.Panel
    grip.Text = "◢"
    grip.TextColor3 = THEME.Title
    grip.Font = THEME.Font
    grip.TextSize = 16
    grip.AutoButtonColor = false
    grip.ZIndex = 60
    corner(grip, 6)
    stroke(grip, THEME.Title, 1)

    local MIN_S, MAX_S = 0.55, 1.8
    local resizing, startDist, startScale, centerPx = false, 1, 1, Vector2.zero

    grip.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            resizing  = true
            centerPx  = Frame.AbsolutePosition + Frame.AbsoluteSize / 2
            startDist = math.max((Vector2.new(i.Position.X, i.Position.Y) - centerPx).Magnitude, 1)
            startScale= config.guiScale
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local cur = (Vector2.new(i.Position.X, i.Position.Y) - centerPx).Magnitude
            local s = math.clamp(startScale * (cur / startDist), MIN_S, MAX_S)
            config.guiScale = s
            MainScale.Scale = s
        end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            resizing = false
        end
    end)
end

-- ============================================================
-- MINIMIZE CIRCLE "PH" (with transition animations)
-- ============================================================
local Circle = Instance.new("TextButton", ScreenGui)
Circle.Name = "MinCircle"
Circle.Size = UDim2.fromOffset(80, 80)
Circle.AnchorPoint = Vector2.new(0.5, 0.5)
Circle.Position = UDim2.new(0.5, 0, 0, 70)
Circle.BackgroundColor3 = THEME.Panel
Circle.Text = "PH"
Circle.Font = Enum.Font.GothamBlack
Circle.TextSize = 30
Circle.TextColor3 = THEME.Title
Circle.AutoButtonColor = false
Circle.Active = true
Circle.Visible = false
corner(Circle, 40)
neonStroke(Circle, 3)
gradient(Circle, THEME.Purple, THEME.Blue, 45)
local CircleScale = Instance.new("UIScale", Circle); CircleScale.Scale = 0

local doMinimize, doRestore
do
local isAnimating = false
doMinimize = function()
    if isAnimating then return end; isAnimating = true
    local t = TweenService:Create(MainScale, tweenFast, {Scale = 0})
    t:Play()
    t.Completed:Connect(function()
        Frame.Visible = false
        Circle.Visible = true
        CircleScale.Scale = 0
        local t2 = TweenService:Create(CircleScale, tweenBounce, {Scale = 1})
        t2:Play()
        t2.Completed:Connect(function() isAnimating = false end)
    end)
end
doRestore = function()
    if isAnimating then return end; isAnimating = true
    local t = TweenService:Create(CircleScale, tweenFast, {Scale = 0})
    t:Play()
    t.Completed:Connect(function()
        Circle.Visible = false
        Frame.Visible = true
        MainScale.Scale = 0
        local t2 = TweenService:Create(MainScale, tweenBounce, {Scale = config.guiScale})
        t2:Play()
        t2.Completed:Connect(function() isAnimating = false end)
    end)
end
end
MinBtn.MouseButton1Click:Connect(doMinimize)

-- circle drag + tap-to-restore
--   * HOLD lalu geser -> hanya MEMINDAHKAN bulatan (tidak membuka)
--   * 1x tap diam     -> baru MEMBUKA dari minimize
do
    local DRAG_THRESHOLD = 8
    local active, moved, startPx, guiStart = false, false, nil, nil

    Circle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            active = true; moved = false
            startPx = i.Position; guiStart = Circle.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if not active then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local d = (i.Position - startPx) / UIScale.Scale
            if d.Magnitude > DRAG_THRESHOLD then moved = true end
            Circle.Position = UDim2.new(
                guiStart.X.Scale, guiStart.X.Offset + d.X,
                guiStart.Y.Scale, guiStart.Y.Offset + d.Y
            )
        end
    end))
    local function release(i)
        if not active then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            active = false
            if not moved then doRestore() end
        end
    end
    Circle.InputEnded:Connect(release)
    track(UserInputService.InputEnded:Connect(release))
end

-- ============================================================
-- NOTIFICATION (toast)
-- ============================================================
local function notify(msg, color)
    if addLog then
        local kind = "INFO"
        if color == THEME.Red or color == THEME.Off then kind = "ERROR"
        elseif color == THEME.Yellow or color == THEME.Orange then kind = "WARN" end
        addLog(msg, kind)
    end
    local toast = Instance.new("TextLabel", ScreenGui)
    toast.Size = UDim2.fromOffset(330, 36)
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.Position = UDim2.new(0.5, 0, 0, -40)
    toast.BackgroundColor3 = THEME.Panel
    toast.Text = msg
    toast.TextColor3 = color or THEME.Title
    toast.Font = THEME.Font
    toast.TextSize = 13
    toast.TextWrapped = true
    corner(toast, 8)
    stroke(toast, color or THEME.Title, 1.5)
    TweenService:Create(toast, tweenBounce, {Position = UDim2.new(0.5, 0, 0, 12)}):Play()
    task.delay(2.2, function()
        local t = TweenService:Create(toast, tweenFast, {Position = UDim2.new(0.5, 0, 0, -50), TextTransparency = 1})
        t:Play(); t.Completed:Connect(function() toast:Destroy() end)
    end)
end

-- ============================================================
-- CONFIRM DIALOG (Are you sure? Yes / No)
-- ============================================================
local function confirmDialog(msg, onYes)
    local overlay = Instance.new("Frame", ScreenGui)
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 1
    overlay.ZIndex = 200
    TweenService:Create(overlay, tweenFast, {BackgroundTransparency = 0.5}):Play()

    local box = Instance.new("Frame", overlay)
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.Position = UDim2.new(0.5, 0, 0.5, 0)
    box.Size = UDim2.fromOffset(320, 155)
    box.BackgroundColor3 = THEME.Bg
    box.BorderSizePixel = 0
    box.ZIndex = 201
    corner(box, 12)
    neonStroke(box, 2)
    local bs = Instance.new("UIScale", box); bs.Scale = 0
    TweenService:Create(bs, tweenBounce, {Scale = 1}):Play()

    local txt = Instance.new("TextLabel", box)
    txt.Size = UDim2.new(1, -20, 0, 85)
    txt.Position = UDim2.new(0, 10, 0, 10)
    txt.BackgroundTransparency = 1
    txt.Text = msg
    txt.TextColor3 = THEME.Text
    txt.Font = THEME.Font
    txt.TextSize = 14
    txt.TextWrapped = true
    txt.ZIndex = 202

    local function closeOverlay()
        local t = TweenService:Create(bs, tweenFast, {Scale = 0})
        t:Play()
        TweenService:Create(overlay, tweenFast, {BackgroundTransparency = 1}):Play()
        t.Completed:Connect(function() overlay:Destroy() end)
    end

    local yesBtn = Instance.new("TextButton", box)
    yesBtn.Size = UDim2.new(0, 128, 0, 38)
    yesBtn.Position = UDim2.new(0, 20, 1, -50)
    yesBtn.BackgroundColor3 = THEME.On
    yesBtn.Text = "Yes"
    yesBtn.TextColor3 = Color3.new(1, 1, 1)
    yesBtn.Font = THEME.Font
    yesBtn.TextSize = 15
    yesBtn.ZIndex = 202
    corner(yesBtn, 8)

    local noBtn = Instance.new("TextButton", box)
    noBtn.Size = UDim2.new(0, 128, 0, 38)
    noBtn.Position = UDim2.new(1, -148, 1, -50)
    noBtn.BackgroundColor3 = THEME.Off
    noBtn.Text = "No"
    noBtn.TextColor3 = Color3.new(1, 1, 1)
    noBtn.Font = THEME.Font
    noBtn.TextSize = 15
    noBtn.ZIndex = 202
    corner(noBtn, 8)

    noBtn.MouseButton1Click:Connect(closeOverlay)
    yesBtn.MouseButton1Click:Connect(function()
        closeOverlay()
        if onYes then onYes() end
    end)
end

-- ============================================================
-- LOOP RUNNER (semua fitur auto pakai ini biar seragam & aman)
-- ============================================================
local loops = {}
local function startLoop(name, fn, getInterval)
    if loops[name] then return end
    loops[name] = true
    task.spawn(function()
        while loops[name] do
            local ok, err = pcall(fn)
            if not ok then addLog("Loop " .. name .. " error: " .. tostring(err), "ERROR") end
            task.wait(getInterval())
        end
    end)
end
local function stopLoop(name) loops[name] = nil end

-- ============================================================
-- MOVEMENT  (semuanya dibungkus tabel MV)
-- ============================================================
-- DIBUNGKUS TABEL, BUKAN PULUHAN `local`. Luau membatasi 200 REGISTER
-- LOKAL per fungsi dan file ini SATU fungsi; pernah 217 `local` di level
-- teratas -> compiler MENOLAK seluruh file ("Out of local registers"),
-- semua tombol diam. Isi blok ini hidup di dalam do...end, jadi
-- register-nya bebas saat blok selesai dan yang tersisa cuma nama MV.
-- Closure tetap memegangnya sebagai UPVALUE - hemat 36 register.
--
-- ISI MV:
--   MV.startFly / stopFly           MV.startUnlockZoom / stopUnlockZoom
--   MV.startNoclip / stopNoclip     MV.startHoldMouse  / stopHoldMouse
--   MV.reconcileNoclip              MV.giveTpTool / removeTpTool
--   MV.startSpeed / stopSpeed       MV.setJumpPowerOn / applyJumpPower
--   MV.setVertical (tombol NAIK/TURUN layar sentuh)
--   MV.flyShortcutKey, MV.rebinding, MV.setFlyVisual, MV.isPC
-- ============================================================
local MV = {}

do
-- ------------------------------------------------------------
-- FLY (terbangkan seluruh MODEL karakter)
--   Diport PERSIS dari PrawiraHub. Bedanya dengan fly biasa:
--     * HARD-PIN CFrame tiap frame -> badan MUSTAHIL anjlok ke void walau
--       map mencabut BodyVelocity, mereset PlatformStand, atau memberi
--       gravitasi sendiri. Gerak digerakkan lewat POSISI, bukan gaya.
--     * RECOVER: pasang ulang BodyVelocity/BodyGyro kalau dicabut map, dan
--       paksa ulang MaxForce (sebagian map cuma me-NOL-kan, bukan destroy).
--     * HP/Tablet: joystick mengikuti arah kamera PENUH (termasuk pitch),
--       jadi arahkan kamera ke atas lalu dorong maju = terbang naik.
--     * flyVertical: tombol NAIK/TURUN untuk layar sentuh.
-- ------------------------------------------------------------
local flyBV, flyBG, flyConn
local flyVertical = 0   -- +1 naik, -1 turun (tombol NAIK/TURUN)

local function startFly()
    if not root then return end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1, 1, 1) * math.huge
    flyBV.Velocity = Vector3.zero
    flyBV.Parent   = root

    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1, 1, 1) * math.huge
    flyBG.P = 9000
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root

    if humanoid then humanoid.PlatformStand = true end

    local flyPos = root.CFrame.Position

    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not root or not root.Parent then return end
        dt = dt or (1 / 60)

        -- RECOVER kalau map mencabut mover / mematikan PlatformStand
        if humanoid and not humanoid.PlatformStand then humanoid.PlatformStand = true end
        if not (flyBV and flyBV.Parent) then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(1, 1, 1) * math.huge
            flyBV.Velocity = Vector3.zero
            flyBV.Parent = root
        end
        if not (flyBG and flyBG.Parent) then
            flyBG = Instance.new("BodyGyro")
            flyBG.MaxTorque = Vector3.new(1, 1, 1) * math.huge
            flyBG.P = 9000
            flyBG.CFrame = root.CFrame
            flyBG.Parent = root
        end

        local camCF = camera.CFrame
        local dir = Vector3.zero
        local hasKeyboardInput = false
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += camCF.LookVector;  hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= camCF.LookVector;  hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= camCF.RightVector; hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += camCF.RightVector; hasKeyboardInput = true end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end

        -- HP/Tablet: MoveDirection itu datar (cuma yaw). Dipecah jadi komponen
        -- maju/samping lalu dibangun ulang pakai LookVector/RightVector 3D.
        if not hasKeyboardInput and humanoid and humanoid.MoveDirection.Magnitude > 0 then
            local md = humanoid.MoveDirection
            local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
            if flatLook.Magnitude > 0.001 then
                flatLook = flatLook.Unit
                local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
                local fwd = md:Dot(flatLook)
                local rgt = md:Dot(flatRight)
                dir += (camCF.LookVector * fwd) + (camCF.RightVector * rgt)
            else
                dir += md
            end
        end

        if flyVertical ~= 0 then dir += Vector3.yAxis * flyVertical end
        if dir.Magnitude > 0 then dir = dir.Unit end

        -- paksa ulang kekuatan mover tiap frame
        flyBV.MaxForce  = Vector3.new(1, 1, 1) * math.huge
        flyBV.Velocity  = Vector3.zero
        flyBG.MaxTorque = Vector3.new(1, 1, 1) * math.huge
        flyBG.CFrame    = camCF

        flyPos = flyPos + dir * config.flySpeed * dt

        root.CFrame = CFrame.new(flyPos) * camCF.Rotation
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    track(flyConn)
end

local function stopFly()
    flyVertical = 0
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    if humanoid then humanoid.PlatformStand = false end
end

-- ============================================================
-- NOCLIP (ringan, tanpa respawn)
--   Versi naif memanggil GetDescendants() TIAP frame -> bikin sampah memori
--   dan patah-patah di HP; dan saat OFF memaksa SEMUA part CanCollide=true
--   (termasuk Handle aksesoris yang aslinya false) -> fisika jadi kacau.
--   Versi ini men-cache daftar part + nilai CanCollide ASLI sekali saja,
--   lalu mengembalikannya TEPAT seperti semula saat dimatikan.
-- ============================================================
local noclipConn, noclipAddedConn
local noclipOrig = {}   -- [part] = CanCollide asli

local function noclipTrackPart(p)
    if p:IsA("BasePart") and noclipOrig[p] == nil then
        noclipOrig[p] = p.CanCollide
        p.CanCollide = false
    end
end

local function noclipBindCharacter(char)
    if not char then return end
    if noclipAddedConn then noclipAddedConn:Disconnect() end
    for _, p in ipairs(char:GetDescendants()) do noclipTrackPart(p) end
    noclipAddedConn = char.DescendantAdded:Connect(noclipTrackPart)
end

local function startNoclip()
    if noclipConn then return end
    noclipOrig = {}
    noclipBindCharacter(LocalPlayer.Character)
    noclipConn = RunService.Stepped:Connect(function()
        for p in pairs(noclipOrig) do
            if p.Parent then
                if p.CanCollide then p.CanCollide = false end
            else
                noclipOrig[p] = nil
            end
        end
    end)
    track(noclipConn)
end

local function stopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if noclipAddedConn then noclipAddedConn:Disconnect(); noclipAddedConn = nil end
    for p, orig in pairs(noclipOrig) do
        if p and p.Parent then
            pcall(function() p.CanCollide = orig end)
        end
    end
    noclipOrig = {}
end

-- Fly SUDAH TERMASUK Noclip. Noclip menyala kalau Noclip mandiri ATAU Fly aktif.
local function reconcileNoclip()
    if state.noclip or state.fly then startNoclip() else stopNoclip() end
end

-- ============================================================
-- SPEED (adaptif - jalan juga di game yang mengunci WalkSpeed)
--   Metode 1: set WalkSpeed (cukup untuk game biasa).
--   Metode 2: kalau game menahan kecepatan nyata di bawah target, tambal
--   lewat AssemblyLinearVelocity (BUKAN geser CFrame - itu sensitif FPS).
--   Deadzone 3 stud/s supaya di game normal tidak jadi dobel-speed.
--   Tidak aktif saat Fly ON supaya tidak bentrok.
-- ============================================================
local speedConn
local function startSpeed()
    if speedConn then speedConn:Disconnect() end
    speedConn = RunService.Heartbeat:Connect(function()
        if state.fly then return end
        local char = LocalPlayer.Character
        local h = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (h and hrp) then return end
        humanoid = h
        if h.WalkSpeed ~= config.walkSpeed then h.WalkSpeed = config.walkSpeed end
        local md = h.MoveDirection
        if md.Magnitude > 0 then
            local vel = hrp.AssemblyLinearVelocity
            local horiz = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if horiz < config.walkSpeed - 3 then
                local target = md.Unit * config.walkSpeed
                hrp.AssemblyLinearVelocity = Vector3.new(target.X, vel.Y, target.Z)
            end
        end
    end)
    track(speedConn)
end
local function stopSpeed()
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    local char = LocalPlayer.Character
    local h = char and char:FindFirstChildOfClass("Humanoid")
    if h then h.WalkSpeed = config.defaultWalk end
end

-- ============================================================
-- INFINITE JUMP + JUMP POWER
-- ============================================================
track(UserInputService.JumpRequest:Connect(function()
    if state.infJump and humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))

-- Jump Power hanya dipasang kalau slider-nya pernah disentuh, supaya
-- tidak mengubah lompatan default game tanpa diminta.
local jumpPowerOn = false
local function applyJumpPower()
    if not jumpPowerOn or not humanoid then return end
    pcall(function()
        if humanoid.UseJumpPower ~= nil then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = config.jumpPower
        else
            humanoid.JumpHeight = config.jumpPower / 10
        end
    end)
end

-- ============================================================
-- CLICK TO TELEPORT (pakai Tool - harus dipegang dulu baru aktif,
-- jadi tidak teleport tiap kali klik UI)
-- ============================================================
local mouse = LocalPlayer:GetMouse()
local tpTool

local function giveTpTool()
    if tpTool and tpTool.Parent then return end
    tpTool = Instance.new("Tool")
    tpTool.Name = "TP Tool"
    tpTool.RequiresHandle = false
    tpTool.CanBeDropped = false
    tpTool.ToolTip = "Pegang lalu klik/tap untuk teleport ke titik"

    tpTool.Activated:Connect(function()
        if not state.clickTp then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local target = mouse.Hit
        if hrp and target then
            hrp.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
            notify("Teleport ke titik klik", THEME.On)
        end
    end)

    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then tpTool.Parent = bp end
end

local function removeTpTool()
    if tpTool then tpTool:Destroy(); tpTool = nil end
    local char = LocalPlayer.Character
    if char then
        local held = char:FindFirstChild("TP Tool")
        if held then held:Destroy() end
    end
end

-- ============================================================
-- UNLOCK ZOOM (paksa bisa zoom-out di game yang mengunci first-person)
--   Pakai listener supaya kalau game men-set balik, langsung ditimpa lagi.
-- ============================================================
local zoomConns = {}
local savedZoom
local function startUnlockZoom()
    if not savedZoom then
        savedZoom = {
            mode = LocalPlayer.CameraMode,
            maxZ = LocalPlayer.CameraMaxZoomDistance,
            minZ = LocalPlayer.CameraMinZoomDistance,
        }
    end
    local applying = false
    local function apply()
        if applying then return end
        applying = true
        pcall(function()
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
            LocalPlayer.CameraMaxZoomDistance = 400
            if LocalPlayer.CameraMinZoomDistance > 1 then
                LocalPlayer.CameraMinZoomDistance = 0.5
            end
        end)
        applying = false
    end
    apply()
    for _, prop in ipairs({ "CameraMode", "CameraMaxZoomDistance", "CameraMinZoomDistance" }) do
        local ok, conn = pcall(function()
            return LocalPlayer:GetPropertyChangedSignal(prop):Connect(apply)
        end)
        if ok and conn then table.insert(zoomConns, conn) end
    end
end
local function stopUnlockZoom()
    for _, cn in ipairs(zoomConns) do pcall(function() cn:Disconnect() end) end
    zoomConns = {}
    if savedZoom then
        pcall(function()
            LocalPlayer.CameraMode = savedZoom.mode
            LocalPlayer.CameraMaxZoomDistance = savedZoom.maxZ
            LocalPlayer.CameraMinZoomDistance = savedZoom.minZ
        end)
        savedZoom = nil
    end
end

-- ============================================================
-- HOLD-M: munculkan mouse SEMENTARA (PC) di game POV terkunci
--   BindToRenderStep prioritas paling akhir supaya menang dari script game.
-- ============================================================
-- `holdMouseEnabled` dulu ada di sini tapi TIDAK PERNAH DIBACA - cuma
-- ditulisi sekali. Dihapus (variabel mati).
local holdMouseActive  = false
local holdMouseSaved   = nil

local function startHoldMouse()
    if holdMouseActive then return end
    holdMouseSaved = { icon = UserInputService.MouseIconEnabled }
    local ok = pcall(function()
        RunService:BindToRenderStep("FHPH_HoldMouse", Enum.RenderPriority.Last.Value + 1, function()
            -- JANGAN paksa saat TOMBOL KANAN sedang DITEKAN.
            -- Kamera bawaan Roblox memutar pandangan dengan MENGUNCI mouse
            -- (MouseBehavior = LockCurrentPosition) selama klik-kanan ditahan.
            -- Kalau kita menimpanya tiap frame di prioritas Last+1, penguncian
            -- itu langsung dibatalkan -> klik-kanan untuk memutar kamera MATI.
            if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                return
            end
            UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end)
    end)
    if ok then holdMouseActive = true else holdMouseSaved = nil end
end

-- Lepaskan kunci mouse apapun penyebabnya. Aman dipanggil kapan saja:
-- kalau memang tidak terkunci, ini tidak mengubah apa-apa.
local function unstickMouse()
    pcall(function()
        if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
        UserInputService.MouseIconEnabled = true
    end)
end

local function stopHoldMouse()
    if not holdMouseActive then return end
    holdMouseActive = false
    pcall(function() RunService:UnbindFromRenderStep("FHPH_HoldMouse") end)
    -- SENGAJA tidak mengembalikan MouseBehavior yang tersimpan.
    -- Kalau fitur ini dinyalakan saat kamera kebetulan sedang mengunci mouse,
    -- nilai tersimpan itu = LockCurrentPosition; mengembalikannya akan
    -- MENGUNCI mouse secara permanen. Default selalu aman: kamera akan
    -- mengunci sendiri lagi begitu kamu tahan klik-kanan.
    unstickMouse()
    if holdMouseSaved then
        pcall(function() UserInputService.MouseIconEnabled = holdMouseSaved.icon end)
        holdMouseSaved = nil
    end
end

-- ------------------------------------------------------------
-- EKSPOR ke MV  (satu-satunya nama yang keluar dari blok ini)
-- ------------------------------------------------------------
MV.isPC           = UserInputService.KeyboardEnabled
-- Bawaannya [C], BUKAN [E]. Alasannya bukan selera:
-- [E] itu tombol ProximityPrompt bawaan Roblox, dan plot ini punya 3080
-- prompt. Jadi tiap kali menyalakan fly, tekanan yang sama juga menembak
-- prompt terdekat - dan di antaranya ada "Grow All" / "Sell All" yang
-- memicu PromptProductPurchase alias MINTA ROBUX. Terlalu mahal untuk
-- sebuah salah pencet.
-- [C] tidak dipakai game ini maupun kontrol bawaan Roblox. Tetap bisa
-- diganti lewat tombolnya di tab Info.
MV.flyShortcutKey = Enum.KeyCode.C   -- shortcut fly PC, bisa di-rebind
MV.rebinding      = false            -- true saat menunggu tombol baru
MV.setFlyVisual   = nil              -- diisi UI: fungsi setVisual toggle Fly

MV.startFly   = startFly
MV.stopFly    = stopFly
MV.setVertical = function(v) flyVertical = v end   -- tombol NAIK / TURUN

MV.startNoclip     = startNoclip
MV.stopNoclip      = stopNoclip
MV.reconcileNoclip = reconcileNoclip

MV.startSpeed = startSpeed
MV.stopSpeed  = stopSpeed

MV.applyJumpPower = applyJumpPower
MV.setJumpPowerOn = function(v) jumpPowerOn = v end

MV.giveTpTool   = giveTpTool
MV.removeTpTool = removeTpTool

MV.startUnlockZoom = startUnlockZoom
MV.stopUnlockZoom  = stopUnlockZoom

MV.startHoldMouse = startHoldMouse
MV.stopHoldMouse  = stopHoldMouse
MV.unstickMouse   = unstickMouse
end
-- ===================== akhir blok MV =========================

local function tpTo(target)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then notify("Karakter belum siap", THEME.Red); return false end
    local cf
    if typeof(target) == "CFrame" then cf = target
    elseif typeof(target) == "Vector3" then cf = CFrame.new(target)
    elseif typeof(target) == "Instance" then
        if target:IsA("BasePart") then cf = target.CFrame
        elseif target:IsA("Model") then cf = target:GetPivot() end
    end
    if not cf then notify("Target teleport tidak valid", THEME.Red); return false end
    hrp.CFrame = cf + Vector3.new(0, 4, 0)
    return true
end

-- ============================================================
-- ============================================================
-- FITUR GAME
-- ============================================================
-- ============================================================

local stats = {
    harvested = 0, planted = 0, supplied = 0, bought = 0,
    crafted = 0, stocked = 0, placed = 0, checkout = 0,
}

-- ============================================================
-- MODE TURBO (instant)
-- ============================================================
-- Kenapa aksi massal terasa lambat walau delay 0? Karena InvokeServer itu
-- YIELDING — tiap panggilan menunggu balasan server dulu. 100 slot x ~150ms
-- ping = 15 detik, delay berapapun tidak menolong.
--
-- TURBO memperbaiki dua hal sekaligus:
--   1. tiap panggilan dibungkus task.spawn -> tidak saling menunggu balasan
--   2. jarak antar panggilan dipangkas ke 0.01 detik
--
-- BATAS AMAN: RateLimiter.Default = NewRateLimiter(120) -> 120 panggilan per
-- detik, dengan toleransi antrean 1 detik (lihat RateLimiter.CheckRate).
-- Jadi 1/120 = 0.0083 dtk adalah lantai teoretisnya. Kalau dilewati, server
-- MENGABAIKAN panggilan berlebih (bukan kick) -> panen bisa ada yang lolos.
local function turboDelay(normal)
    if state.turbo then return 0.01 end   -- 0.01 dtk = 100 panggilan/detik
    return normal
end

-- Panggil RF. Mode normal = tunggu balasan (bisa baca hasil).
-- Mode TURBO = tembak-lalu-lupa lewat task.spawn (jauh lebih cepat, tapi
-- nilai balik server tidak bisa dibaca).
local function callRF(serviceName, methodName, ...)
    if state.turbo then
        local args = table.pack(...)
        task.spawn(function()
            invokeRF(serviceName, methodName, table.unpack(args, 1, args.n))
        end)
        return true
    end
    return invokeRF(serviceName, methodName, ...)
end

-- ---------- FARM ----------
local function doHarvestOnce(manual)
    local planters = getMyPlanters()
    if #planters == 0 then return 0 end

    -- ============================================================
    -- JALUR CEPAT: SATU PANGGILAN MEMANEN SATU PLANTER PENUH
    -- ============================================================
    -- Remote yang juga baru ketahuan dari dump V3:
    --     GrowingService.RF.HarvestPlanter(planter)
    -- (ReplicatedStorageV3 baris 22001-22006)
    --
    -- Call-site aslinya di komponen planter, StarterPlayerScriptsV3
    -- baris 664-667 - tombol "Harvest Planter" milik game:
    --     v7 = function() v1:HarvestPlanter(p1.Instance) end
    --     v4, v5, v6 = "harvest", "Harvest Planter", ...
    --
    -- Planter di plotmu 9 slot. Jalur lama = 9 panggilan per planter;
    -- ini 1. Untuk 100 planter itu 900 panggilan jadi 100.
    --
    -- CUMA DIPAKAI KALAU FILTER PANEN KOSONG, dan ini bukan
    -- kehati-hatian berlebihan: HarvestPlanter memanen SEMUA slot yang
    -- siap di planter itu - dia tidak tahu apa-apa soal dropdown
    -- "Seeds to Harvest". Kalau kamu menyaring bibit tertentu lalu hub
    -- diam-diam memakai jalur ini, bibit yang sengaja kamu lindungi ikut
    -- kepanen. Jadi begitu ada centang, jalurnya turun ke per-slot -
    -- lebih lambat, tapi menuruti pilihanmu.
    if setIsEmpty(sel.harvestSeeds)
       and getRemote("GrowingService", "RF", "HarvestPlanter") then
        local n = 0
        for _, planter in ipairs(planters) do
            if not manual and not state.autoHarvest then break end
            local slots = planter:GetAttribute("Slots") or 1
            local siap = 0
            for i = 1, slots do
                local seed = planter:GetAttribute("Slot_" .. i .. "_Seed")
                if seed and seed ~= ""
                   and planter:GetAttribute("Slot_" .. i .. "_Ready")
                   and not planter:GetAttribute("Slot_" .. i .. "_Locked") then
                    siap = siap + 1
                end
            end
            if siap > 0 then
                callRF("GrowingService", "HarvestPlanter", planter)
                n = n + siap
                stats.harvested = stats.harvested + siap
                addLog("Harvest Planter -> " .. planter.Name .. "  " .. siap ..
                       " slot dalam SATU panggilan", "FARM")
                task.wait(turboDelay(config.farmDelay))
            end
        end
        return n
    end

    local n = 0
    for _, planter in ipairs(planters) do
        if not manual and not state.autoHarvest then break end
        local slots = planter:GetAttribute("Slots") or 1
        for i = 1, slots do
            local seed   = planter:GetAttribute("Slot_" .. i .. "_Seed")
            local ready  = planter:GetAttribute("Slot_" .. i .. "_Ready")
            local locked = planter:GetAttribute("Slot_" .. i .. "_Locked")
            -- filter "Seeds to Harvest": kosong = semua bibit
            if seed and seed ~= "" and ready and not locked and setAllows(sel.harvestSeeds, seed) then
                local ok = callRF("GrowingService", "Harvest", planter, i)
                if ok then
                    n = n + 1
                    stats.harvested = stats.harvested + 1
                    addLog("Harvest " .. tostring(seed) .. " @slot" .. i, "FARM")
                end
                task.wait(turboDelay(config.farmDelay))
            end
        end
    end
    return n
end

-- TANAM MASSAL.
-- Versi lama memanggil equipToolBy() untuk SETIAP slot. equipToolBy
-- menyisir seluruh Character + Backpack; untuk 100 slot itu 100 kali
-- penyisiran penuh. ITU penyebab utama auto-plant terasa berat -- bukan
-- delay-nya, dan bukan pula ping. Versi ini menyapu slot kosong SEKALI,
-- membagi jatahnya per jenis bibit, lalu equip CUKUP SEKALI per jenis.
local function doPlantOnce(manual)
    local wanted = setList(sel.plantSeeds)
    if #wanted == 0 then return 0 end

    -- ============================================================
    -- JALUR CEPAT: SATU PANGGILAN MENANAMI SATU PLANTER PENUH
    -- ============================================================
    --     GrowingService.RF.PlantPlanter(planter, seedType)
    -- (ReplicatedStorageV3 baris 21971-21976)
    --
    -- Argumen keduanya TERBUKTI berupa TEKS jenis bibit, bukan tool.
    -- Call-site aslinya StarterPlayerScriptsV3 baris 678-681:
    --     v7 = function() v1:PlantPlanter(p1.Instance, v2) end
    -- dan v2 datang dari baris 652 `local v2 = p1:_getEquippedSeed()`,
    -- yang isinya (baris 605-618):
    --     if v:IsA("Tool") and v:GetAttribute("SeedType") then
    --         return v:GetAttribute("SeedType")
    -- Jadi persis bentuk yang sama dengan argumen PlantSeed lama.
    --
    -- SATU PERBEDAAN PERILAKU, dan saya sebutkan supaya tidak jadi
    -- kejutan: pembagian bibitnya sekarang PER PLANTER, bukan per slot.
    -- Centang 3 bibit -> planter 1 penuh bibit A, planter 2 penuh B,
    -- planter 3 penuh C, lalu berputar lagi. Jalur lama menyelang-nyeling
    -- di dalam satu planter. Totalnya tetap terbagi rata, dan server
    -- memang cuma menerima SATU jenis per panggilan - jadi menyelang di
    -- dalam planter mustahil dilakukan tanpa kembali ke per-slot.
    --
    -- Tangan tetap WAJIB memegang bibitnya (server membaca tool yang
    -- dipegang), tapi equip-nya sekali per planter - bukan sekali per
    -- slot seperti versi paling awal.
    if getRemote("GrowingService", "RF", "PlantPlanter") then
        local n, giliran = 0, 0
        for _, planter in ipairs(getMyPlanters()) do
            if not manual and not state.autoPlant then break end
            local slots = planter:GetAttribute("Slots") or 1
            local kosong = 0
            for i = 1, slots do
                local cur = planter:GetAttribute("Slot_" .. i .. "_Seed")
                if not cur or cur == "" then kosong = kosong + 1 end
            end

            if kosong > 0 then
                -- Bibit dicoba BERGILIR mulai dari giliran berikutnya.
                -- Kalau yang kebagian ternyata habis di tas, jatahnya
                -- dioper ke bibit berikutnya - bukan planternya yang
                -- dilewati. Itu aturan yang sama dengan jalur lama.
                local tool, seed
                for k = 1, #wanted do
                    local cal = wanted[((giliran + k - 1) % #wanted) + 1]
                    local t = equipToolBy(function(x)
                        return x:GetAttribute("SeedType") == cal
                    end)
                    if t then tool, seed = t, cal; giliran = giliran + k; break end
                end

                if not tool then
                    -- Tidak ada satupun bibit terpilih yang tersisa di tas.
                    -- Planter berikutnya pasti bernasib sama, jadi berhenti.
                    break
                end

                callRF("GrowingService", "PlantPlanter", planter, seed)
                n = n + kosong
                stats.planted = stats.planted + kosong
                addLog("Plant Planter -> " .. planter.Name .. "  " .. kosong ..
                       " slot " .. seed .. " dalam SATU panggilan", "FARM")
                task.wait(turboDelay(config.farmDelay))
            end
        end
        return n
    end

    -- 1) kumpulkan semua slot kosong dalam satu sapuan
    local empties = {}
    for _, planter in ipairs(getMyPlanters()) do
        local slots = planter:GetAttribute("Slots") or 1
        for i = 1, slots do
            local cur = planter:GetAttribute("Slot_" .. i .. "_Seed")
            if not cur or cur == "" then
                empties[#empties + 1] = { p = planter, s = i }
            end
        end
    end
    if #empties == 0 then return 0 end

    -- 2) bagi bergiliran ke tiap bibit terpilih -> hasil akhirnya tetap
    --    CAMPUR seperti versi lama, tapi sudah dikelompokkan per bibit
    local queue = {}
    for _, seed in ipairs(wanted) do queue[seed] = {} end
    for i, e in ipairs(empties) do
        local seed = wanted[((i - 1) % #wanted) + 1]
        table.insert(queue[seed], e)
    end

    -- 3) tanam per bibit; kalau satu bibit habis / tidak punya, jatah
    --    sisanya DIOPER ke bibit berikutnya supaya tidak ada slot terbuang
    local n = 0
    local leftover = {}
    for _, seed in ipairs(wanted) do
        if not manual and not state.autoPlant then break end

        local list = queue[seed]
        for _, e in ipairs(leftover) do list[#list + 1] = e end
        leftover = {}

        if #list > 0 then
            -- server memeriksa tool yang DIPEGANG -> tetap perlu equip,
            -- tapi cukup satu kali untuk seluruh jatah bibit ini
            local tool = equipToolBy(function(t) return t:GetAttribute("SeedType") == seed end)
            if not tool then
                for _, e in ipairs(list) do leftover[#leftover + 1] = e end
            else
                for idx, e in ipairs(list) do
                    if not manual and not state.autoPlant then break end
                    if not tool.Parent then
                        -- bibit habis di tengah jalan -> oper sisanya
                        for k = idx, #list do leftover[#leftover + 1] = list[k] end
                        break
                    end
                    local ok = callRF("GrowingService", "PlantSeed", e.p, seed, e.s)
                    if ok then
                        n = n + 1
                        stats.planted = stats.planted + 1
                        addLog("Plant " .. seed .. " @" .. e.p.Name .. " slot" .. e.s, "FARM")
                    end
                    task.wait(turboDelay(config.farmDelay))
                end
            end
        end
    end
    return n
end

-- `doSupplyOnce` DIHAPUS. Dia memakai SATU merek supply dari dropdown
-- dan menembakkannya ke semua slot tanpa memilih - untuk kaleng itu
-- pemborosan (Godly di slot yang kurang semenit) dan untuk pupuk tidak
-- punya jatah sama sekali. Penggantinya habisSupply() di bawah, dipakai
-- Auto Siram & Auto Pupuk. Satu-satunya hal yang cuma bisa dilakukan
-- versi lama adalah memasang LOCK - dan Lock memang tidak dipakai di hub
-- ini. Kalau suatu saat perlu: KONSOL REMOTE UNIVERSAL di tab Settings,
-- GrowingService.RF.ApplySupply(planter, slot, namaTool).

-- ---------- INSTANT GROW ----------
-- CATATAN JUJUR: di game ini TIDAK ADA remote instant-grow.
-- GrowingService cuma punya PlantSeed / GetPlanterInfo / GetAvailableSeeds /
-- ApplySupply / Harvest. Kesiapan panen dihitung SERVER dari
-- Slot_<i>_PlantedAt + growTime, jadi tidak bisa dipaksa dari client.
-- Satu-satunya cara mempercepat tanpa Robux = MENYIRAM, dan itu SEKALI
-- per slot per tahap tumbuh (server menjawab "Already watered" untuk
-- tembakan kedua - terukur di game). Tiap kaleng memotong waktu TETAP
-- (atribut timeReduction) dan uses = 1:
--   Watering Can -60s | Silver -300s | Golden -900s
--   Diamond -7200s    | Godly -18000s (5 jam)

-- Label supply SATU JENIS berikut angka efeknya. `jenis` = SupplyType:
--   "WateringCan" -> timeReduction (detik yang dipotong)
--   "Fertilizer"  -> bonusYield    (bunga tambahan per panen)
-- Dulu ada dua fungsi terpisah untuk ini; digabung supaya cuma memakan
-- SATU nama di level teratas (batas Luau 200 register per fungsi).
local function supplyLabels(jenis)
    local f = assetFolder("Supplies")
    local out = {}
    if f then
        for _, m in ipairs(f:GetChildren()) do
            if m:GetAttribute("SupplyType") == jenis then
                local red = tonumber(m:GetAttribute("timeReduction"))
                local yld = tonumber(m:GetAttribute("bonusYield"))
                out[#out + 1] = m.Name .. "  [" ..
                    (red and ("-" .. red .. "s")
                         or (yld and ("+" .. yld .. " bunga") or "?")) ..
                    " | $" .. tostring(m:GetAttribute("cost") or "?") .. "]"
            end
        end
    end
    table.sort(out)
    if #out == 0 then out[1] = "(tidak ada " .. jenis .. " di Assets.Supplies)" end
    return out
end

-- sisa waktu tumbuh sebuah slot (detik) + total waktu penuh. nil kalau data kurang.
local function slotRemaining(planter, i)
    local seed = planter:GetAttribute("Slot_" .. i .. "_Seed")
    if not seed or seed == "" then return nil end
    if planter:GetAttribute("Slot_" .. i .. "_Ready") then return 0, 0 end
    local plantedAt = planter:GetAttribute("Slot_" .. i .. "_PlantedAt")
    if not plantedAt then return nil end
    local seedsF = assetFolder("Seeds")
    local sm = seedsF and seedsF:FindFirstChild(seed)
    local growTime = sm and sm:GetAttribute("growTime")
    if not growTime then return nil end
    -- MenuConfig: total = growTime * (#GrowthStages - 1), GrowthStages ada 4
    local total = growTime * 3
    if LocalPlayer:GetAttribute("2XGrowSpeed") then total = total / 2 end
    local elapsed = os.time() - plantedAt
    return math.max(0, total - elapsed), total
end

-- ringkasan seluruh kebun: berapa slot tumbuh, total sisa detik
local function growSummary()
    local slotsGrowing, totalRemain = 0, 0
    for _, planter in ipairs(getMyPlanters()) do
        local slots = planter:GetAttribute("Slots") or 1
        for i = 1, slots do
            local rem = slotRemaining(planter, i)
            if rem and rem > 0 then
                slotsGrowing = slotsGrowing + 1
                totalRemain = totalRemain + rem
            end
        end
    end
    return slotsGrowing, totalRemain
end

local function fmtDur(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return h .. "j " .. m .. "m" end
    if m > 0 then return m .. "m " .. s .. "d" end
    return s .. "d"
end

-- `doInstantGrowOnce` DIHAPUS - digantikan habisSupply("WateringCan").
-- Dia menuntut SATU merek kaleng dan memakai itu terus, jadi kaleng
-- Godly (-18.000 dtk) bisa habis di slot yang cuma kurang semenit.
-- habisSupply memilih kaleng yang paling PAS untuk tiap slot, dan
-- menerima daftar merek yang boleh dipakai kalau kamu mau menyimpan
-- yang mahal.

-- ============================================================
-- HABISKAN SUPPLY - pakai SEMUA yang dimiliki, bukan satu merek
-- ============================================================
-- Satu mesin, dua jenis (SupplyType dibaca dari Assets.Supplies):
--   "WateringCan" -> percepat tumbuh, pakai kaleng apa pun yang ada
--   "Fertilizer"  -> naikkan hasil panen, DISEBAR RATA ke tiap slot
--
-- KALENG DIPILIH, TIDAK DIPAKAI URUT ASAL. Tiap kaleng memotong waktu
-- TETAP (timeReduction) dan uses = 1, jadi slot yang cuma kurang 60 detik
-- lalu disiram Godly (-18.000 dtk) MEMBUANG 17.940 detik. Aturannya:
-- ambil kaleng TERBESAR yang masih di bawah sisa waktu slot; kalau sisa
-- waktunya tidak terbaca, ambil yang TERKECIL - itu yang paling sedikit
-- ruginya kalau tebakannya salah.
--
-- SIRAM ITU SEKALI PER SLOT PER TAHAP TUMBUH. Terukur di game, bukan
-- dugaan: tembakan kedua ke slot yang sama dijawab server "Already
-- watered". Jadi slot yang sudah dilayani DILEWATI - tidak ditembak lalu
-- ditolak. Client game sendiri tidak punya penanda ini (controllernya cuma
-- memeriksa Slot_<i>_Ready, SPSV2TELITI 639-663), jadi ingatannya kita
-- bangun sendiri di slotTandai / slotSudah di bawah.
--
-- PUPUK: jatahnya DIBACA dari server, tidak ditebak. Lihat slotYield().
--
-- SENGAJA global (tanpa `local`), seperti addLog & tampil: dipanggil dari
-- dua kartu do...end yang berbeda, dan global tidak memakan register sama
-- sekali (batas Luau 200 per fungsi).
--
-- `hanya` = set nama yang BOLEH dipakai (kosong / nil = semua yang ada di
-- tas). Gunanya supaya kamu bisa menghabiskan Watering Can biasa sambil
-- MENYIMPAN yang Godly untuk bibit lama.
--
-- Balikan: jumlah terpakai, alasan kalau nol, jumlah slot yang jadi siap.

-- ============================================================
-- INGATAN SLOT - DUA BUG SAYA, DAN INI YANG BIKIN "Already watered"
-- ============================================================
-- Gejalanya: notifikasi game "Already watered (x3)" lalu "(x7)" numpuk
-- di layar, padahal kotak hitungan menulis "belum disiram : 5010".
-- Dua sebabnya berbeda, dan dua-duanya ada di sini.
--
-- BUG 1 - KUNCINYA TIDAK UNIK.
-- Versi lama memakai `tostring(p) .. "#" .. s` sebagai kunci. Di Roblox
-- `tostring(instance)` itu NAMANYA, bukan identitas unik. Plot ini punya
-- puluhan planter BERNAMA SAMA ("Shelf of Pots" dan seterusnya), jadi
-- kunci "Shelf of Pots#3" DIPAKAI BERSAMA oleh semua planter itu. Tiap
-- penandaan menimpa penandaan planter sebelumnya, jadi ingatannya tidak
-- pernah benar-benar menumpuk dan slot yang sudah disiram ditembak lagi.
--
-- BUG 2 - INGATANNYA DIBUANG TOTAL DI 2000 ENTRI.
-- Angka 2000 itu saya pilih waktu plot masih kecil. Kotak hitunganmu
-- sekarang menulis "Slot sedang tumbuh : 6152" - tiga kali lipat batas
-- itu. Jadi ingatannya dihapus habis berkali-kali tiap sapuan, dan
-- sesudah tiap penghapusan SEMUA slot dianggap belum disiram lagi.
--
-- PERBAIKANNYA menghapus dua-duanya sekaligus: tabel BERSARANG yang
-- dikunci OBJEK planter-nya langsung (bukan teks), dengan __mode = "k".
--   * objek itu unik, jadi mustahil bertabrakan walau namanya sama
--   * WEAK KEY berarti planter yang dibongkar/hilang lenyap SENDIRI dari
--     ingatan - jadi tidak perlu penghapusan massal sama sekali, dan
--     tidak ada lagi batas jumlah entri yang bisa dilewati
SUPPLY_MENTOK = {
    WateringCan = setmetatable({}, { __mode = "k" }),
    Fertilizer  = setmetatable({}, { __mode = "k" }),
    bukti = false,
}

-- HASIL PANEN SLOT ITU MENURUT SERVER. Slot_<i>_Variants = daftar bunga
-- dipisah koma, SATU ENTRI SATU BUNGA, jadi jumlahnya = yield SEKARANG -
-- sudah termasuk pupuk yang pernah masuk. Ini catatan server; client game
-- tidak pernah membacanya sama sekali (nol call-site), jadi angkanya tidak
-- bisa basi karena UI.
--
-- Inilah jawaban "deteksi slot yang belum dipupuk": bandingkan dengan
-- maxYield 6. Balikan ke-2 = false kalau atributnya tidak terbaca, supaya
-- pemanggil tahu dia sedang menebak dan wajib menyisakan satu percobaan.
function slotYield(p, s, base)
    local v = p:GetAttribute("Slot_" .. s .. "_Variants")
    if type(v) == "string" and v ~= "" then
        local n = 0
        for _ in string.gmatch(v, "[^,]+") do n = n + 1 end
        if n > 0 then return n, true end
    end
    return tonumber(base) or 0, false
end

-- Apakah slot ini sudah dilayani. Dua hal yang membuat ingatannya
-- KEDALUWARSA SENDIRI, jadi tidak ada slot yang terkunci selamanya:
--   PlantedAt -> TURUN kalau disiram (server memundurkannya sebanyak
--                timeReduction), dan MELOMPAT KE DEPAN kalau ditanam ulang.
--                Jadi PlantedAt yang lebih besar dari yang dicatat = ini
--                penanaman BARU, boleh dilayani lagi.
--   Stage     -> naik seiring tumbuh, jadi tiap tahap dapat satu percobaan
--                lagi. Kalau server ternyata membukanya per tahap, ini yang
--                menangkapnya; kalau tidak, ongkosnya cuma 2-3 panggilan
--                per penanaman - bukan 15 tiap dua detik.
function slotSudah(jenis, p, s)
    local t = SUPPLY_MENTOK[jenis]
    local per = t and t[p]          -- dikunci OBJEK planter, bukan namanya
    local e = per and per[s]
    if not e then return false end
    if e.st ~= p:GetAttribute("Slot_" .. s .. "_Stage") then return false end
    local at = tonumber(p:GetAttribute("Slot_" .. s .. "_PlantedAt"))
    return at ~= nil and e.at ~= nil and at <= e.at
end

function slotTandai(jenis, p, s)
    local t = SUPPLY_MENTOK[jenis]
    if not t then return end
    local per = t[p]
    if not per then per = {}; t[p] = per end
    -- Tidak ada penghitung dan tidak ada penghapusan massal lagi. Tabel
    -- luarnya WEAK-KEY, jadi planter yang dibongkar / hilang dari plot
    -- membawa serta seluruh catatan slotnya tanpa disuruh.
    per[s] = {
        at = tonumber(p:GetAttribute("Slot_" .. s .. "_PlantedAt")),
        st = p:GetAttribute("Slot_" .. s .. "_Stage"),
    }
end

function habisSupply(jenis, running, hanya)
    local supF = assetFolder("Supplies")
    if not supF then return 0, "Assets.Supplies tidak ketemu" end

    -- Katalog dibaca RUNTIME: kaleng / pupuk baru dari developer ikut
    -- terpakai sendiri tanpa mengubah script.
    local kuat = {}
    for _, m in ipairs(supF:GetChildren()) do
        if m:GetAttribute("SupplyType") == jenis
           and (hanya == nil or setAllows(hanya, m.Name)) then
            kuat[m.Name] = tonumber(m:GetAttribute("timeReduction"))
                        or tonumber(m:GetAttribute("bonusYield")) or 1
        end
    end

    -- SUPPLY BERTUMPUK lewat atribut Count (lihat hotbar game: "x6"), jadi
    -- SATU Tool bisa berarti enam pemakaian - bukan satu. Diurut dari yang
    -- TERLEMAH supaya pemilihan di bawah cukup sekali sapuan.
    local tas, total = {}, 0
    for _, t in ipairs(allTools()) do
        if kuat[t.Name] and t.Parent then
            local c = math.max(tonumber(t:GetAttribute("Count")) or 1, 1)
            tas[#tas + 1] = { t = t, sisa = c, k = kuat[t.Name] }
            total = total + c
        end
    end
    if total == 0 then return 0, "tidak ada " .. jenis .. " di inventory" end
    table.sort(tas, function(a, b) return a.k < b.k end)

    -- Server memutuskan dari tool yang SEDANG DIPEGANG (_getEquippedSupply
    -- menyisir Character), dan EquipTool cuma seketika di CLIENT. Jadi
    -- equip WAJIB ditunggu sampai mendarat, lalu satu jeda replikasi.
    local function pegang(t)
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum and t.Parent) then return false end
        if t.Parent == char then return true end
        pcall(function() hum:EquipTool(t) end)
        local t0 = os.clock()
        while t.Parent ~= char and (os.clock() - t0) < 0.5 do task.wait() end
        if t.Parent ~= char then return false end
        task.wait(0.08)
        return true
    end

    -- Yang paling pas. batas = nil -> ambil TERKECIL yang masih ada.
    local function pilih(batas)
        local pas, kecil
        for _, e in ipairs(tas) do
            if e.sisa > 0 and e.t.Parent then
                if kecil == nil then kecil = e end
                if batas and e.k <= batas then pas = e end
            end
        end
        return pas or kecil
    end

    -- Slot yang sedang tumbuh. Filter "Seeds to Harvest" ikut dipakai
    -- supaya bibit yang tidak kamu urus tidak ikut menghabiskan supply.
    local sasaran = {}
    for _, planter in ipairs(getMyPlanters()) do
        local slots = planter:GetAttribute("Slots") or 1
        for i = 1, slots do
            local seed = planter:GetAttribute("Slot_" .. i .. "_Seed")
            if seed and seed ~= ""
               and not planter:GetAttribute("Slot_" .. i .. "_Ready")
               and setAllows(sel.harvestSeeds, seed) then
                sasaran[#sasaran + 1] = { p = planter, s = i, seed = seed }
            end
        end
    end
    if #sasaran == 0 then return 0, "tidak ada slot yang sedang tumbuh" end

    local pakai = 0

    if jenis == "WateringCan" then
        local siap, lewat = 0, 0
        for _, e in ipairs(sasaran) do
            if running and not running() then break end
            -- SATU tembakan per slot, titik. Dulu di sini ada loop sampai
            -- 100x per slot dengan harapan bisa menyiram terus sampai siap;
            -- server menolak yang kedua dengan "Already watered", jadi
            -- sisanya murni panggilan sampah.
            if slotSudah("WateringCan", e.p, e.s) then
                lewat = lewat + 1
            elseif not e.p:GetAttribute("Slot_" .. e.s .. "_Ready") then
                local pick = pilih((slotRemaining(e.p, e.s)))
                if not pick then
                    return pakai, "kaleng HABIS (terpakai " .. pakai .. "x, " ..
                                  siap .. " slot jadi siap)", siap
                end
                if not pegang(pick.t) then
                    pick.sisa = 0
                else
                    local aok, ares, amsg =
                        invokeRF("GrowingService", "ApplySupply", e.p, e.s, pick.t.Name)
                    pick.sisa = pick.sisa - 1
                    task.wait(turboDelay(config.farmDelay))
                    -- Berhasil MAUPUN ditolak, akibatnya sama: slot ini
                    -- tidak bisa disiram lagi sampai tahapnya berganti.
                    -- Ditandai SESUDAH jeda, supaya PlantedAt yang dicatat
                    -- sudah yang baru (siram memundurkannya).
                    slotTandai("WateringCan", e.p, e.s)
                    if aok and ares == false then
                        addLog("Siram ditolak @slot" .. e.s .. " -> " ..
                               tostring(amsg or "tanpa pesan") ..
                               " - slot ini tidak ditembak lagi sampai tahap berganti", "FARM")
                    else
                        pakai = pakai + 1
                        stats.supplied = stats.supplied + 1
                        if e.p:GetAttribute("Slot_" .. e.s .. "_Ready") then
                            siap = siap + 1
                            addLog("Siram: " .. e.seed .. " @slot" .. e.s .. " jadi SIAP", "FARM")
                        end
                    end
                end
            end
        end
        if pakai == 0 and lewat > 0 then
            return 0, lewat .. " slot sudah disiram - tunggu tahap tumbuh berikutnya", siap
        end
        return pakai, nil, siap
    end

    -- PUPUK: SEBAR RATA. Satu putaran = satu pupuk per slot, jadi tidak
    -- ada slot yang ditumpuk sampai mentok sementara slot lain kosong.
    --
    -- JATAHNYA DIBACA, BUKAN DITEBAK. slotYield() menghitung entri
    -- Slot_<i>_Variants - itu daftar bunga yang akan dipanen dari slot itu
    -- menurut SERVER, jadi jumlahnya sudah termasuk pupuk yang pernah
    -- masuk. Jatah = 6 - angka itu (maxYield 6). Slot yang sudah 6 tidak
    -- ditembak sama sekali; tidak perlu menunggu penolakan.
    local seedF = assetFolder("Seeds")
    local jatah, nMentok = {}, 0
    for idx, e in ipairs(sasaran) do
        local sm = seedF and seedF:FindFirstChild(e.seed)
        e.base = tonumber(sm and sm:GetAttribute("yield")) or 0
        local kini, dariServer = slotYield(e.p, e.s, e.base)
        e.kini = kini
        jatah[idx] = 6 - kini
        -- Atribut tidak terbaca = kita sedang menebak. Sisakan SATU
        -- percobaan supaya penolakan server tetap terukur.
        if not dariServer and jatah[idx] <= 0 then jatah[idx] = 1 end
        if jatah[idx] <= 0 or slotSudah("Fertilizer", e.p, e.s) then
            jatah[idx] = 0
            nMentok = nMentok + 1
        end
    end

    for _ = 1, 6 do
        local adaPakai = false
        for idx, e in ipairs(sasaran) do
            if running and not running() then break end
            if jatah[idx] > 0 then
                -- pupuk TERKUAT yang masih masuk jatah: +3 sekali tembak
                -- lebih hemat panggilan daripada +1 tiga kali.
                local pick = pilih(jatah[idx])
                if not pick then
                    return pakai, (pakai == 0) and "pupuk HABIS" or nil
                end
                if not pegang(pick.t) then
                    pick.sisa = 0
                else
                    local aok, ares, amsg =
                        invokeRF("GrowingService", "ApplySupply", e.p, e.s, pick.t.Name)
                    pick.sisa = pick.sisa - 1
                    task.wait(turboDelay(config.farmDelay))
                    if aok and ares == false then
                        jatah[idx] = 0
                        slotTandai("Fertilizer", e.p, e.s)
                        addLog("Pupuk ditolak @slot" .. e.s .. " -> " ..
                               tostring(amsg or "hasil panen sudah mentok"), "FARM")
                    else
                        pakai = pakai + 1
                        adaPakai = true
                        stats.supplied = stats.supplied + 1
                        -- HASILNYA DIUKUR ULANG dari server, bukan dikurangi
                        -- dari angka bonusYield. Kalau Variants ikut naik,
                        -- itu sekaligus BUKTI maxYield 6 adalah batas TOTAL -
                        -- pertanyaan yang sebelumnya tidak bisa dijawab.
                        local sesudah = slotYield(e.p, e.s, e.base)
                        if sesudah > e.kini then
                            if not SUPPLY_MENTOK.bukti then
                                SUPPLY_MENTOK.bukti = true
                                addLog("TERUKUR: pupuk menaikkan Slot_Variants " ..
                                       e.kini .. " -> " .. sesudah ..
                                       ", jadi maxYield 6 itu batas TOTAL. Jatah pupuk" ..
                                       " sekarang dibaca dari server, tidak ditebak.", "FARM")
                            end
                            e.kini = sesudah
                            jatah[idx] = 6 - sesudah
                        else
                            jatah[idx] = jatah[idx] - pick.k
                        end
                        if jatah[idx] <= 0 then
                            slotTandai("Fertilizer", e.p, e.s)
                        end
                    end
                end
            end
        end
        if not adaPakai then break end
    end
    if pakai == 0 and nMentok > 0 then
        return 0, nMentok .. " slot hasil panennya sudah mentok (6 bunga)"
    end
    return pakai, nil
end

-- AUTO LAYANI PEMBELI  (CustomOrderPrompt di badan pembeli)
-- ============================================================
-- Kasir (CheckoutPrompt) ditangani mesin AUTO di bawah, BUKAN fungsi ini.
--
-- Daftar lengkap prompt di plot (semua terukur dari dump V2):
--     CheckoutPrompt     "Checkout"       tahan 0.5  jarak 10  <- kasir (AUTO)
--     CustomOrderPrompt  "Deliver Order"  tahan 0.5  jarak 10  <- INI
--     ProximityPrompt    "Grow All"/"Sell All"  -> ROBUX, jangan disentuh
--     ProximityPrompt    "Arrange"        tahan 0    jarak 5   (CraftSpot)
--     StockPrompt        "Display for Sale"/"Stock Flower"  Enabled=false
--     SlotPrompt_<i>     "Interact"       Enabled=false
--     StaffPrompt        "Manage"         tahan 0    jarak 5
--
-- ObjectText prompt = pesanannya, contoh nyata dari dump:
--     "Antique Vase (Chrysanthemum, Yellow Lily, Sunflower)"
--     "Antique Vase (Iris)"
-- Artinya pesanan itu MINTA rangkaian tertentu. Kalau kamu tidak punya
-- barangnya, server yang menolak - itu di luar jangkauan client.
--
-- Semua pembantunya dibungkus do...end dan cuma DUA nama yang keluar.
-- Main chunk ini satu fungsi, dan Luau membatasi 200 register lokal per
-- fungsi -- tiap nama di level teratas hidup sampai baris terakhir.
local doCheckoutOnce, customOrderList
do

-- Kumpulkan pembeli yang benar-benar sedang menunggu dilayani.
-- Prompt dicari di SELURUH model (argumen kedua = rekursif), bukan cuma di
-- HumanoidRootPart: server menaruhnya di dalam Attachment dan kedalamannya
-- tidak dijamin sama.
local function pendingOrders()
    local plot = getMyPlot()
    local customers = plot and plot:FindFirstChild("Customers")
    local out = {}
    if not customers then return out, false end
    for _, cust in ipairs(customers:GetChildren()) do
        local p = cust:FindFirstChild("CustomOrderPrompt", true)
        if p and p:IsA("ProximityPrompt") and p.Enabled then
            out[#out + 1] = { c = cust, p = p }
        end
    end
    return out, true
end

-- ============================================================
-- KENAPA "KLIK E"-NYA BISA NYASAR KE NPC QUEST
-- ============================================================
-- Sebagian executor menjalankan fireproximityprompt dengan MENIRU
-- TEKANAN E, bukan menyentuh objek prompt yang kita kirim. Roblox lalu
-- mengarahkan E itu ke prompt yang SEDANG DIA PILIH - dan pilihannya
-- cuma SATU untuk seluruh layar (Exclusivity bawaan "OneGlobally").
-- NPC Quest yang berdiri dekat pembeli gampang merebut giliran itu.
--
-- Obatnya di sini: SEMUA prompt lain dimatikan sementara selama kita
-- menembak (properti sisi CLIENT, dikembalikan persis di akhir - juga
-- kalau di tengah jalan error). Obat yang sebenarnya ada di fireOne():
-- untuk prompt milik SERVER, fireproximityprompt tidak dipakai sama
-- sekali. Daftar prompt di-cache (lihat allPrompts).
local promptCache, promptCacheAt = nil, 0

-- Cache 1 detik, BUKAN 5. Dengan 5 detik, prompt yang baru lahir (NPC
-- Quest yang baru muncul, pembeli baru) TIDAK ada di daftar, jadi tidak
-- ikut dimatikan - dan dialah yang lalu merebut E. Ini dipanggil sekali
-- per sapuan pesanan, bukan per pesanan, jadi 1 detik masih murah.
local function allPrompts()
    if promptCache and (os.clock() - promptCacheAt) < 1 then return promptCache end
    local out = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then out[#out + 1] = d end
    end
    promptCache, promptCacheAt = out, os.clock()
    return out
end

-- Matikan semua prompt KECUALI yang ada di tabel `keep`.
-- Balikan: daftar yang dimatikan, untuk dinyalakan lagi nanti.
local function muteOthers(keep)
    local muted = {}
    for _, p in ipairs(allPrompts()) do
        if p.Parent and p.Enabled and not keep[p] then
            muted[#muted + 1] = p
            pcall(function() p.Enabled = false end)
        end
    end
    return muted
end

local function unmute(muted)
    for _, p in ipairs(muted) do
        if p.Parent then pcall(function() p.Enabled = true end) end
    end
end

-- Tembak SATU prompt. SAMA PERSIS dengan AUTO.klik di mesin AUTO --
-- alasan lengkapnya ada di sana. Ringkasnya:
--   * MaxActivationDistance / RequiresLineOfSight / Exclusivity dibuka
--     sebentar lalu DIKEMBALIKAN (semuanya properti sisi client)
--   * HoldDuration ikut dinolkan -> tembakannya INSTAN, tidak ada
--     tahanan 0,5 detik per pesanan
--   * lima cara tembak dicoba sampai ada yang TERBUKTI, lalu diingat
local function fireOne(p, sudahDekat)
    -- klikPrompt itu GLOBAL yang dibuat di blok AUTO (letaknya di bawah
    -- blok ini, tapi baru dipanggil saat runtime jadi sudah ada). Dia yang
    -- MENGUKUR cara tembak mana yang benar-benar memicu Triggered di
    -- executor ini, lalu memakainya terus. Alasan lengkapnya ada di sana.
    --
    -- BUKTI ikut dikirim: pesanan yang benar-benar terkirim membuat
    -- promptnya HILANG (pembelinya pergi) atau mati. Tanpa ini pengukuran
    -- cuma bersandar pada PromptTriggered, dan itu terukur TIDAK selalu
    -- bunyi -- jadi cara yang sebenarnya berhasil pun dilaporkan gagal.
    if type(klikPrompt) == "function" then
        -- CUMA cara 4 & 5. Keduanya memanggil p:InputHoldBegin() LANGSUNG
        -- pada objek promptnya, jadi mustahil nyasar.
        --
        -- Cara 1-3 (fireproximityprompt) SENGAJA DILARANG di sini: sebagian
        -- executor menjalankannya dengan MENIRU TEKANAN E, dan E itu
        -- mendarat di prompt yang sedang DIPILIH Roblox - bukan yang kita
        -- kirim. Karena NPC Quest berdiri dekat pembeli, dialah yang paling
        -- sering kena. Itu persis keluhan "malah ke Quest".
        --
        -- Kalau badan sudah dipindah ke depan pembeli, cara 5 (yang tugasnya
        -- MEMINDAHKAN badan) tidak perlu dicoba lagi.
        local urut = sudahDekat and { 4 } or { 5, 4 }
        return klikPrompt(p, function()
            return (not p.Parent) or (not p.Enabled)
        end, urut)
    end
    return (pcall(function()
        p:InputHoldBegin()
        task.wait(math.max(0.06, p.HoldDuration))
        p:InputHoldEnd()
    end))
end

doCheckoutOnce = function()
    -- Penjaga "executor tidak punya fireproximityprompt" DIHAPUS: jalur
    -- utama sekarang InputHoldBegin/End, yang itu API Roblox biasa dan
    -- tidak butuh executor sama sekali.
    local list, adaFolder = pendingOrders()
    if not adaFolder then return 0, "folder Customers tidak ada di plot" end
    -- Keluar SEBELUM menyisir prompt: kalau tidak ada pesanan, fungsi ini
    -- harus murah -- dia dipanggil tiap 0.5 detik oleh loop jaring pengaman.
    if #list == 0 then return 0, "tidak ada custom order yang aktif" end

    local char   = LocalPlayer.Character
    local hrp    = char and char:FindFirstChild("HumanoidRootPart")
    local pulang = hrp and hrp.CFrame   -- posisi awal, dikembalikan di akhir

    -- prompt sasaran TIDAK ikut dimatikan
    local keep = {}
    for _, e in ipairs(list) do keep[e.p] = true end
    local muted = muteOthers(keep)

    -- JARING PENGAMAN. Baris `unmute` di bawah sudah dijaga pcall, TAPI
    -- itu tidak menolong kalau thread ini MATI di tengah `task.wait`
    -- (GUI ditutup, script dihentikan executor). Kalau itu terjadi,
    -- seluruh prompt di game tinggal mati dan kamu tidak bisa menanam /
    -- memanen / membuka apapun sampai rejoin. Ini menyalakannya ulang
    -- tanpa syarat setelah 15 detik; aman walau unmute sudah jalan
    -- duluan, karena isinya cuma menyetel Enabled = true lagi.
    task.delay(15, function() unmute(muted) end)

    local n = 0
    local ok, err = pcall(function()
        for _, e in ipairs(list) do
            -- Pindah ke depan pembeli dulu, memakai MESIN YANG SAMA dengan
            -- kasir (dekatiPrompt): badan DIPATOK tiap frame selama
            -- menembak, lalu dikembalikan persis ke tempat semula.
            --
            -- Versi lama di sini punya bug yang sama dengan kasir: badan
            -- ditaruh di `posisi prompt + (0,0,3)`. Prompt ini menempel di
            -- HumanoidRootPart pembeli, jadi titik itu MELAYANG setinggi
            -- dada - badan langsung jatuh, dan server melihat kita sudah
            -- menjauh sebelum tembakannya diproses.
            local lepas = nil
            if config.dekatiDulu and type(dekatiPrompt) == "function" then
                lepas = dekatiPrompt(e.p)
            end

            -- Dulu n dinaikkan TANPA memeriksa hasil, jadi laporan
            -- "Instant layani: 1 pesanan" muncul walau tidak ada yang
            -- benar-benar terkirim. Sekarang cuma dihitung kalau terbukti.
            local barang = tostring(e.p.ObjectText)
            local jadi = fireOne(e.p, lepas ~= nil)
            if jadi then
                n = n + 1
                stats.checkout = stats.checkout + 1
                addLog("Deliver Order -> " .. e.c.Name .. "  minta: " .. barang, "FARM")
            else
                addLog("Deliver Order GAGAL -> " .. e.c.Name .. "  minta: " .. barang ..
                       "  (barangnya ada di inventory?)", "FARM")
            end
            -- WAJIB dilepas di sini, bukan di akhir loop: tiap pembeli
            -- posisinya beda, jadi patoknya harus dibongkar sebelum pindah
            -- ke pembeli berikutnya.
            --
            -- Dipulangkan HANYA kalau berhasil (aturan yang sama dengan
            -- kasir). Gagal = tetap berdiri di depan pembeli itu, jadi
            -- percobaan berikutnya sudah dekat.
            if lepas then lepas(jadi) end
            task.wait(turboDelay(config.farmDelay))
        end
    end)

    -- WAJIB dipulihkan apapun yang terjadi. Kalau blok di atas gagal di
    -- tengah jalan dan ini dilewati, SELURUH prompt di game ikut mati dan
    -- kamu tidak bisa menanam / memanen / membuka apapun lagi.
    unmute(muted)

    -- Balik ke tempat semula HANYA kalau ada pesanan yang benar-benar
    -- terkirim. Kalau nol, badan sengaja ditinggal di dekat pembeli -
    -- aturan yang sama dengan kasir.
    if n > 0 and pulang and config.dekatiDulu and hrp and hrp.Parent then
        hrp.CFrame = pulang
    end

    if not ok then return n, "gagal di tengah jalan: " .. tostring(err) end
    return n
end

-- Daftar pesanan yang sedang menunggu, berikut barang yang diminta.
-- Dipakai kartu info supaya kelihatan HARUS merangkai apa.
customOrderList = function()
    local out = {}
    for _, e in ipairs((pendingOrders())) do
        out[#out + 1] = tostring(e.p.ObjectText)
    end
    return out
end

end
-- ============ akhir blok AUTO LAYANI PEMBELI ============

local function farmSummary()
    local planters = getMyPlanters()
    local total, ready, empty, growing, locked = 0, 0, 0, 0, 0
    for _, planter in ipairs(planters) do
        local slots = planter:GetAttribute("Slots") or 1
        for i = 1, slots do
            total = total + 1
            local seed = planter:GetAttribute("Slot_" .. i .. "_Seed")
            if not seed or seed == "" then
                empty = empty + 1
            elseif planter:GetAttribute("Slot_" .. i .. "_Ready") then
                ready = ready + 1
                if planter:GetAttribute("Slot_" .. i .. "_Locked") then locked = locked + 1 end
            else
                growing = growing + 1
            end
        end
    end
    return #planters, total, ready, growing, empty, locked
end

local clearCropEsp, refreshCropEsp
do
local espFolder = nil
clearCropEsp = function()
    if espFolder then espFolder:Destroy(); espFolder = nil end
end
refreshCropEsp = function()
    clearCropEsp()
    espFolder = Instance.new("Folder", ScreenGui)
    espFolder.Name = "CropEsp"
    for _, planter in ipairs(getMyPlanters()) do
        local slots = planter:GetAttribute("Slots") or 1
        local anyReady = false
        for i = 1, slots do
            if planter:GetAttribute("Slot_" .. i .. "_Ready") then anyReady = true; break end
        end
        if anyReady then
            local hl = Instance.new("Highlight")
            hl.Adornee = planter
            hl.FillColor = THEME.Green
            hl.FillTransparency = 0.6
            hl.OutlineColor = Color3.new(1, 1, 1)
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = espFolder
        end
    end
end
end

-- ============================================================
-- STOK ASLI TOKO - INI SEBAB "SUPPLY TIDAK KEBELI PADAHAL ADA"
-- ============================================================
-- Sebuah barang boleh dibeli kalau LOLOS TIGA GERBANG (applyBuyState,
-- SPSV2TELITI 10832-10843): stok > 0, tidak dikunci streak login, dan
-- level cukup. Untuk SUPPLY gerbang levelnya mati sendiri - datanya
-- diambil dari MenuConfig.Seeds yang memang tidak berisi supply.
--
-- MASALAHNYA: GetShopStock cuma mengembalikan { nama, harga } - TIDAK
-- ada Stock, TIDAK ada Locked. Jadi angka stok mustahil didapat dari
-- situ, dan menembak barang berstok nol selalu ditolak diam-diam.
--
-- Sumber yang benar (updateStock, 11079-11101):
--     ShopService.RE.StockRefreshed(shopId, {
--         { Name = "Fertilizer", Stock = 3, Locked = false,
--           RequiredStreak = nil }, ... })
--
-- CADANGAN kalau eventnya belum datang: label StockCount milik game di
-- MainMenu.Main.SuppliesContent.ScrollingFrame (nama kartu = nama
-- barang). Baru ada sesudah panel toko game pernah dibuka sekali.
--
--   TOKO.stok[shopId][nama] = { sisa = n, kunci = bool }
--   TOKO.daftar[shopId]     = { {nama, harga}, ... }  <- SUMBER INDEX
--   TOKO.sumberUI[shopId]   = daftar itu dibaca dari kartu game, bukan server
--   TOKO.dumped[shopId]     = bentuk mentahnya sudah pernah dicetak
--   TOKO.benar[shopId][i]   = nama barang yang TERBUKTI dibeli oleh index i,
--                             diukur dari BARANG YANG MASUK TAS - bukan dari
--                             daftar. Lihat "INDEX BASI" di buyFromShop.
local TOKO = { stok = {}, daftar = {}, sumberUI = {}, dumped = {}, benar = {} }

-- ============================================================
-- INDEX BELI HARUS DARI ARRAY YANG SAMA DENGAN TOMBOL GAME
-- ============================================================
-- BuyItem menuntut INDEX, bukan nama. Index yang SAH adalah posisi di array
-- yang dikirim SetupShopUI - itu yang ditangkap tombol beli milik game:
--     for i = 1, #p3 do ... BuyItem(p2, i, ...)   SPSV2TELITI 10917 & 11007
--
-- GetShopStock NOL call-site di seluruh dump client (cuma namanya yang ada
-- di pohon Services). Jadi urutan array-nya TIDAK TERBUKTI sama dengan
-- SetupShopUI, dan selama hub memakai index dari situ dia bertaruh pada
-- kesamaan yang tidak pernah diukur. Dipakai cuma sebagai CADANGAN.
function TOKO.simpanDaftar(shopId, data)
    if type(shopId) ~= "string" or type(data) ~= "table" then return 0 end
    -- INDEX-nya WAJIB UTUH: itu yang dikirim ke BuyItem. Entri yang
    -- bentuknya aneh diberi placeholder, BUKAN dilewati - kalau dilewati,
    -- arraynya berlubang, ipairs berhenti di lubang itu, dan sisa barangnya
    -- hilang tanpa jejak.
    local out = {}
    for i = 1, #data do
        local e = data[i]
        if type(e) == "table" and e[1] then
            out[i] = { tostring(e[1]), tonumber(e[2]) or 0 }
        else
            out[i] = { "", 0 }
        end
    end
    TOKO.daftar[shopId] = out
    return #out
end

-- Simpan hasil dari StockRefreshed. Dipanggil listener di bawah.
function TOKO.simpan(shopId, data)
    if type(shopId) ~= "string" or type(data) ~= "table" then return 0 end
    TOKO.stok[shopId] = TOKO.stok[shopId] or {}
    local n = 0
    for _, e in ipairs(data) do
        if type(e) == "table" and e.Name then
            TOKO.stok[shopId][tostring(e.Name)] = {
                sisa  = tonumber(e.Stock) or 0,
                kunci = e.Locked == true,
                hari  = tonumber(e.RequiredStreak),
            }
            n = n + 1
        end
    end
    return n
end

-- ============================================================
-- KARTU TOKO GAME = SUMBER TERBAIK YANG ADA DI CLIENT
-- ============================================================
-- Satu tempat memberi TIGA hal sekaligus: NAMA barang, URUTANNYA (itu
-- yang jadi index BuyItem), dan STOK. Dan ketiganya dari UI yang
-- dibangun server lewat SetupShopUI, jadi urutan kartunya memang urutan
-- array yang diterima BuyItem.
--
-- KENAPA INI JADI JALUR UTAMA, bukan cadangan lagi. Terukur di game
-- 2026-08-21: GetShopStock mengembalikan 9 entri dan entry[1] SEMUANYA
-- nil, jadi hub tidak dapat satu nama pun -> dicoba = 0, nol remote
-- ditembak, dan sakelarnya kelihatan "tidak jalan". Bentuk
-- { nama, harga } yang dulu ditulis di kepala file ini ASUMSI - catatan
-- saya sendiri sudah menandai GetShopStock nol call-site di client, jadi
-- memang tidak pernah ada yang membuktikannya.
--
-- Kartu baru ada sesudah panel toko game pernah dibangun sekali.
function TOKO.dariUI(shopId)
    -- DecorShop topLevel = true, dua lainnya di dalam MainMenu.Main
    -- (ShopController baris 10647-10700).
    local isi = ({ SeedShop = "SeedsContent", SupplyShop = "SuppliesContent",
                   DecorShop = "DecorShop" })[shopId]
    if not isi then return 0 end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local sg = pg and pg:FindFirstChild("ScreenGui")
    if not sg then return 0 end
    local wadah = (shopId == "DecorShop") and sg:FindFirstChild(isi)
        or (sg:FindFirstChild("MainMenu") and sg.MainMenu:FindFirstChild("Main")
            and sg.MainMenu.Main:FindFirstChild(isi))
    local scroll = wadah and wadah:FindFirstChild("ScrollingFrame")
    if not scroll then return 0 end

    TOKO.stok[shopId] = TOKO.stok[shopId] or {}

    -- ============================================================
    -- JANGAN PERNAH MENGURUTKAN KARTU. LayoutOrder ITU HARGA.
    -- ============================================================
    -- INI BUG SAYA, DAN INI BUKTINYA - dibaca dari ShopController milik
    -- game sendiri (SPSV2TELITI), bukan tebakan:
    --
    --   _buildCards, baris 10917-10926:
    --       for i = 1, #p3 do
    --           local v10 = p3[i][1]          -- nama barang
    --           local v11 = p3[i][2]          -- HARGA
    --           local v14 = v6:Clone()
    --           v14.Parent = ScrollingFrame   -- ditempel URUT i
    --           v14.Name  = v10               -- kartu DINAMAI barangnya
    --
    --   baris 10944:
    --       v14.LayoutOrder = v11 or 0        -- <<<< HARGA, BUKAN INDEX
    --
    -- Jadi:
    --   * URUTAN ANAK (GetChildren) = urutan i = URUTAN ARRAY SERVER
    --     -> ITU yang jadi index BuyItem. Terbukti di baris 11007:
    --        v2:BuyItem(p2, i, ...)   <- i dari loop for i = 1, #p3
    --   * LayoutOrder = HARGA. UIGridLayout-nya SortOrder = LayoutOrder
    --     (SGV2TELITI, token SortOrder = 2), jadi yang kamu LIHAT di layar
    --     memang urut HARGA - dan itu SAMA SEKALI bukan urutan index.
    --
    -- Versi kemarin menyortir kartu pakai LayoutOrder dengan alasan
    -- "susunan di layar = susunan array server". Alasan itu SALAH TOTAL:
    -- yang saya urutkan ternyata HARGA. Akibatnya index yang dikirim
    -- menunjuk barang lain - persis "saya centang Agapanthus Seed, yang
    -- kebeli Anthurium Seed (server menolak: level requirement 150)".
    --
    -- Kenapa dulu kadang benar: updateStock baris 11095-11096 me-RESET
    -- LayoutOrder jadi RequiredStreak (biasanya 0), TAPI blok itu dijaga
    -- `if v2.lockLabel then` dan field `lock` CUMA ADA DI DecorShop -
    -- SeedShop & SupplyShop tidak punya (lihat tabel t, baris 10648-10682).
    -- Jadi untuk bibit & supply LayoutOrder TETAP harga selamanya, dan
    -- salah urutnya PERMANEN.
    --
    -- KARTU DISARING SECARA STRUKTURAL, bukan cuma :IsA("GuiObject").
    -- UIPadding & UIGridLayout memang bukan GuiObject jadi sudah aman,
    -- tapi panel toko juga punya anak GuiObject yang BUKAN kartu
    -- (Countdown, StatsButton, ProbabilityFrame, BulkPurchase). Satu saja
    -- ikut terhitung = seluruh index bergeser. Kartu asli SELALU punya
    -- tombol beli bernama "BuyButton" - itu nama yang dipakai game untuk
    -- ketiga toko (fields.buyBtn), jadi ini penanda yang paling tepat.
    local kartu = {}
    for _, k in ipairs(scroll:GetChildren()) do
        if k:IsA("GuiObject") and k:FindFirstChild("BuyButton") then
            kartu[#kartu + 1] = k
        end
    end

    local daftar, n = {}, 0
    for i, k in ipairs(kartu) do
        local lbl = k:FindFirstChild("StockCount", true)
        local angka = lbl and tonumber(string.match(tostring(lbl.Text), "(%d+)"))

        -- HARGA dibaca dari label mana pun yang isinya "$angka". Nama
        -- labelnya sengaja TIDAK saya tebak. Kalau tidak ketemu, harganya
        -- 0 - dan 0 MEMATIKAN pemeriksaan cash di buyFromShop, bukan
        -- menolak pembelian. Gagal ke arah yang aman.
        local harga = 0
        for _, d in ipairs(k:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local a = string.match(tostring(d.Text), "^%s*%$([%d,%.]+)")
                if a then
                    harga = tonumber((string.gsub(a, "[,%.]", ""))) or 0
                    if harga > 0 then break end
                end
            end
        end

        -- HARGA 0 = TIDAK KETEMU DI KARTU, bukan gratis. Untuk kartu BIBIT
        -- itu keadaan NORMAL: game MENIMPA label harganya dengan waktu
        -- tumbuh (_buildCards 10946-10947 menulis "\226\143\177 ..." ke
        -- label Price), jadi memang tidak ada "$angka" yang bisa dibaca.
        --
        -- Kalau daftar LAMA sudah punya harga dari SetupShopUI, jangan
        -- dibuang - itu angka resmi dari server, dan menimpanya dengan 0
        -- membuat pemeriksaan cash & tampilan harga kehilangan datanya.
        if harga == 0 then
            local lama = TOKO.daftar[shopId]
            if lama then
                for _, e in ipairs(lama) do
                    if type(e) == "table" and e[1] == k.Name then
                        harga = tonumber(e[2]) or 0
                        break
                    end
                end
            end
        end

        daftar[i] = { k.Name, harga }
        if angka then
            TOKO.stok[shopId][k.Name] = { sisa = angka, kunci = false, ui = true }
            n = n + 1
        end
    end

    -- ============================================================
    -- DAFTAR INI WAJIB DISEGARKAN, BUKAN DIBEKUKAN
    -- ============================================================
    -- Baris ini DULU berbunyi:
    --     if #daftar > 0 and not (TOKO.daftar[shopId] and #... > 0) then
    -- alias "isi HANYA kalau masih kosong". Alasannya waktu itu terdengar
    -- masuk akal (daftar dari server lebih tepat daripada dari kartu),
    -- TAPI akibatnya fatal: begitu terisi sekali, pemetaan NAMA -> INDEX
    -- tidak pernah diperbarui lagi seumur sesi.
    --
    -- Padahal STOK TOKO BERPUTAR tiap ~5 menit. Yang dikirim server saat
    -- berputar cuma StockRefreshed - itu memperbarui JUMLAH (TOKO.stok,
    -- dikunci nama), bukan URUTAN. Jadi daftar index-nya jadi BASI, dan
    -- BuyItem(shopId, index) membeli apa pun yang sekarang duduk di
    -- posisi itu. Itu persis gejala "saya centang bibit A, yang kebeli
    -- malah Orchid dan Hibiscus": namanya cocok di daftar LAMA, tapi
    -- index-nya sudah milik barang lain.
    --
    -- Kartu toko game DIBANGUN ULANG oleh game tiap kali isinya berubah,
    -- jadi dia justru sumber yang paling sinkron dengan keadaan sekarang.
    -- SetupShopUI tetap menang kalau memang baru datang - dia menulis
    -- TOKO.daftar lewat simpanDaftar tanpa syarat.
    if #daftar > 0 then
        TOKO.daftar[shopId] = daftar
        TOKO.sumberUI[shopId] = true
    end
    -- Balikan ke-2 = berapa KARTU yang terbaca. Dipakai pemanggil untuk
    -- membedakan "kartunya kosong" dari "kartunya tidak bisa dibaca".
    return n, #daftar
end

-- Balikan: sisa, terkunci, TAHU.
-- TAHU = false berarti kita memang belum punya datanya -> pemanggil
-- WAJIB tetap mencoba beli. Menebak "kosong" saat tidak tahu justru
-- membuat fitur ini mematikan pembelian yang sebenarnya sah.
function TOKO.info(shopId, nama)
    local t = TOKO.stok[shopId]
    local e = t and t[tostring(nama)]
    if not e then return 0, false, false end
    return e.sisa or 0, e.kunci == true, true
end

-- HARGA SEBUAH BARANG, untuk ditampilkan di dropdown.
--
-- Dua sumber, dan urutannya sengaja: harga YANG SEDANG BERLAKU di toko
-- didahulukan, baru harga katalog. Balikan 0 = tidak ketahuan, dan
-- pemanggil WAJIB menampilkan apa adanya (tidak usah menulis harga)
-- daripada menampilkan angka 0 yang bohong.
--
-- Dipasang sebagai field TOKO, bukan `local function`: nol register di
-- level teratas (batas Luau 200 per fungsi).
function TOKO.harga(shopId, nama, model)
    local d = TOKO.daftar[shopId]
    if d then
        for _, e in ipairs(d) do
            if type(e) == "table" and e[1] == nama then
                local h = tonumber(e[2])
                if h and h > 0 then return h end
                break
            end
        end
    end
    -- Katalog. Nama atributnya dicoba beberapa karena cuma `cost` yang
    -- SUDAH terbukti ada (dipakai supplyLabels sejak lama); untuk bibit
    -- belum pernah saya buktikan, jadi jangan mengarang satu nama saja.
    if model then
        for _, k in ipairs({ "cost", "price", "Price" }) do
            local h = tonumber(model:GetAttribute(k))
            if h and h > 0 then return h end
        end
    end
    return 0
end

-- ============================================================
-- MENGUKUR APA YANG BENAR-BENAR MASUK TAS
-- ============================================================
-- Dipasang sebagai field TOKO, bukan `local function`, supaya nol
-- register di level teratas (batas Luau 200 per fungsi).
--
-- Ini satu-satunya cara MEMBUKTIKAN bahwa BuyItem(shopId, index) benar
-- membeli barang yang kita maksud. Nama & index dua-duanya datang dari
-- daftar yang bisa basi; yang TIDAK bisa berbohong cuma isi tas sesudah
-- uangnya keluar. Pola yang sama dengan kapasitas rak dan batas slot
-- tas: kalau angkanya tidak ada di client, UKUR dari akibatnya.
--
-- Count ikut dijumlah karena bibit & supply BERTUMPUK dalam satu Tool.
function TOKO.isiTas()
    local out = {}
    for _, t in ipairs(allTools()) do
        out[t.Name] = (out[t.Name] or 0) + (tonumber(t:GetAttribute("Count")) or 1)
    end
    return out
end

-- Barang mana yang jumlahnya NAIK paling banyak. Balikan: nama, selisih.
-- nil = tidak ada yang bertambah (pembelian tidak mendarat di tas).
function TOKO.yangNaik(sebelum, sesudah)
    local nama, delta = nil, 0
    for k, v in pairs(sesudah) do
        local d = v - (sebelum[k] or 0)
        if d > delta then nama, delta = k, d end
    end
    return nama, delta
end

-- ---------- SHOP ----------
local function getStock(shopId)
    local ok, stock = invokeRF("ShopService", "GetShopStock", shopId)
    if ok and type(stock) == "table" then return stock end
    return nil
end

local function stockLabels(shopId)
    local stock = getStock(shopId)
    local out = {}
    if stock then
        for i, entry in ipairs(stock) do
            local nm, pr = entry[1], entry[2]
            if nm then table.insert(out, i .. ". " .. tostring(nm) .. " ($" .. fmtNum(pr) .. ")") end
        end
    end
    if #out == 0 then table.insert(out, "(stok kosong / belum termuat)") end
    return out
end

-- beli item terpilih saja (pakai set), atau semua kalau set kosong dan allowAll
-- ============================================================
-- DUA SEBAB "SUPPLY TIDAK KEBELI PADAHAL ADA"
-- ============================================================
-- 1. QTY > 1 CUMA SAH DI SeedShop. ShopController (11007) menulis:
--        v2:BuyItem(p2, i, if p2 == "SeedShop" then v4 or 1 else 1)
--    Jadi qty WAJIB dipaksa 1 untuk SupplyShop & DecorShop, kalau tidak
--    server menolak diam-diam.
-- 2. YANG DICENTANG BELUM TENTU SEDANG DIJUAL. Dropdown mendaftar
--    SELURUH katalog, toko cuma menjual beberapa yang berputar.
--
-- Karena itu fungsi ini mengembalikan ALASAN sebagai nilai kedua kalau
-- hasilnya nol - tanpa itu, "belum dijual" tidak bisa dibedakan dari
-- "rusak".
-- `habiskan` = beli barang yang sama BERULANG sampai stok toko kosong,
-- bukan satu per putaran. Batas atasnya dari stok yang terbaca lewat
-- StockRefreshed; kalau stoknya belum terbaca, dibatasi 20 percobaan dan
-- tetap berhenti di penolakan pertama.
local function buyFromShop(shopId, wantedSet, qty, useGems, allowAll, habiskan)
    -- SUMBER NAMA + INDEX, urut dari yang paling terbukti:
    --   1. SetupShopUI       -> array resmi dari server
    --   2. kartu toko game   -> disusun DARI array itu, jadi urutannya sama
    --   3. GetShopStock      -> bentuknya TIDAK pernah terbukti, dan
    --      TERUKUR salah (9 entri, entry[1] semuanya nil). Cadangan
    --      terakhir, dan namanya dibaca longgar di namaEntri().
    --
    -- DIBACA ULANG TIAP PANGGILAN, bukan sekali lalu disimpan selamanya.
    -- Stok toko berputar tiap ~5 menit dan URUTANNYA ikut berubah; daftar
    -- yang dibekukan membuat index menunjuk barang lain (alasan lengkap di
    -- TOKO.dariUI). Ongkosnya cuma menyisir beberapa kartu GUI lokal -
    -- nol panggilan server - dan loop Auto Buy cuma bangun tiap ~4 detik.
    TOKO.dariUI(shopId)
    local stock = TOKO.daftar[shopId]
    local sumber = TOKO.sumberUI[shopId] and "kartu toko game" or "SetupShopUI"
    if not (stock and #stock > 0) then
        stock, sumber = getStock(shopId), "GetShopStock"
    end
    if not stock then
        return 0, "GetShopStock(" .. shopId .. ") tidak menjawab, dan panel toko" ..
                  " game belum pernah dibuka - buka sekali supaya daftar resminya" ..
                  " terkirim"
    end
    if #stock == 0 then return 0, "stok " .. shopId .. " sedang KOSONG" end

    -- (Pembacaan kartu yang dulu ada di sini sudah dipindah ke ATAS dan
    -- dijalankan tiap panggilan, jadi TOKO.stok juga selalu ikut segar.)

    -- entry[1] SAJA TIDAK CUKUP - itu yang bikin Auto Buy diam total.
    -- Terukur 2026-08-21: GetShopStock mengembalikan 9 entri dengan
    -- entry[1] nil semuanya, jadi tiap nama jatuh jadi "nil", tidak ada
    -- yang cocok, dan nol remote ditembak. Field lain dicoba juga supaya
    -- bentuk apa pun yang dipakai server tetap terbaca.
    local function namaEntri(e)
        if type(e) == "string" then return e end
        if type(e) ~= "table" then return nil end
        for _, k in ipairs({ 1, "Name", "name", "Item", "item", "Type", "type" }) do
            local v = e[k]
            if type(v) == "string" and v ~= "" then return v end
        end
        return nil
    end
    local function hargaEntri(e)
        if type(e) ~= "table" then return 0 end
        for _, k in ipairs({ 2, "Price", "price", "Cost", "cost" }) do
            local v = tonumber(e[k])
            if v then return v end
        end
        return 0
    end

    -- ============================================================
    -- SATU ANGKA "JUMLAH", DUA CARA MENCAPAINYA
    -- ============================================================
    -- `qty` sekarang berarti TARGET: berapa yang mau kamu dapat dari
    -- tiap barang yang dicentang. Cara mencapainya beda per toko, dan
    -- itu ATURAN GAME - lihat SEBAB 1 di atas (ShopController 11007):
    --
    --   SeedShop     -> qty > 1 DITERIMA. Jadi cukup SATU panggilan
    --                   BuyItem(shop, index, N). Satu remote, bukan N.
    --   Supply/Decor -> server MEMAKSA qty = 1. Jadi target dicapai
    --                   dengan MENGULANG panggilan (lihat `ulang`).
    --
    -- Memaksa qty > 1 ke SupplyShop bukan cuma sia-sia: server
    -- menolaknya diam-diam, dan itu dulu membuat supply TIDAK PERNAH
    -- kebeli begitu slider dinaikkan di atas 1.
    --
    -- ============================================================
    -- BATAS 100 PER PANGGILAN ITU ATURAN GAME, BUKAN PILIHAN SAYA
    -- ============================================================
    -- Kotak "BulkPurchase" milik game sendiri MENGUNCI angkanya di 100
    -- (ShopController SPSV2TELITI 11528 & 11538):
    --     v4 = math.min(v4 + 1, 100)
    --     v4 = if v1 and v1 >= 1 then math.min(math.floor(v1), 100) else 1
    -- dan v4 itulah yang dikirim ke BuyItem (11007). Jadi game TIDAK
    -- PERNAH mengirim qty di atas 100, dan apakah server menerimanya
    -- TIDAK TERBUKTI.
    --
    -- Karena itu target di atas 100 TIDAK dipaksakan sekali kirim -
    -- dipecah jadi beberapa panggilan @100. Hasilnya sama, tapi tiap
    -- panggilannya persis bentuk yang sudah terbukti diterima server.
    -- BATAS 50.000, bukan 1000. Angka 1000 itu tebakan saya, dan
    -- TERBUKTI kekecilan: hotbar-mu menunjukkan Camellia menumpuk sampai
    -- x6.000 lalu x11.600 dalam satu Tool. Jadi tas memang sanggup jauh
    -- di atas 1000, dan mematok kotaknya di situ cuma menghalangi tanpa
    -- alasan.
    local target = math.clamp(math.floor(tonumber(qty) or 1), 1, 50000)
    local q = (shopId == "SeedShop") and math.min(target, 100) or 1

    local n, dicoba, adaTahu = 0, 0, false
    local ada, habis, kunci, tolak = {}, {}, {}, nil

    -- ============================================================
    -- NAMA DICOCOKKAN LONGGAR, BUKAN BYTE-PER-BYTE
    -- ============================================================
    -- Dua sumber nama BERBEDA harus dipertemukan di sini:
    --   dropdown  -> nama anak Assets.Supplies / Assets.Seeds
    --   stok toko -> nama yang dikirim server lewat SetupShopUI
    -- Dua-duanya SEHARUSNYA sama - game sendiri memakai nama stok untuk
    -- Assets:FindFirstChild (SPSV2TELITI 10920). Tapi perbandingan TEPAT
    -- gagal total begitu ada selisih satu spasi atau satu huruf besar,
    -- dan gagalnya SUNYI: dicoba = 0, tidak ada satu pun remote ditembak.
    -- Kelas bug yang sama sudah pernah kena di bunga (model "PurpleLily"
    -- vs layar "Purple Lily"). Jadi spasi, garis bawah, tanda hubung, dan
    -- besar-kecil huruf dibuang dulu sebelum dibandingkan.
    local function polos(s)
        return (string.gsub(string.lower(tostring(s)), "[%s_%-]", ""))
    end
    local mau = nil
    if not setIsEmpty(wantedSet) then
        mau = {}
        for k, v in pairs(wantedSet) do
            if v then mau[polos(k)] = k end
        end
    end

    for i, entry in ipairs(stock) do
        -- NAMA TERUKUR MENANG - TAPI CUMA KALAU SUMBERNYA MEMANG RAGU.
        --
        -- Kalau daftarnya dari KARTU TOKO GAME, nama kartu itu OTORITAS:
        -- game sendiri yang menamainya (_buildCards baris 10926,
        -- `v14.Name = v10`) di dalam loop yang sama dengan index BuyItem.
        -- Jadi tidak ada yang perlu dikoreksi, dan menimpanya dengan
        -- tebakan lama justru bisa merusak yang sudah benar.
        --
        -- Koreksi terukur tetap dipakai untuk dua sumber yang memang tidak
        -- terbukti: array SetupShopUI mentah dan GetShopStock.
        local nm = (not TOKO.sumberUI[shopId])
                   and (TOKO.benar[shopId] and TOKO.benar[shopId][i])
                   or namaEntri(entry)
        ada[#ada + 1] = tostring(nm)
        local dicentang = ((mau ~= nil) and nm and mau[polos(nm)]) or nil
        local want = (mau == nil and allowAll) or (dicentang ~= nil)
        if want then
            -- Kalau cocoknya cuma SESUDAH dinormalkan, itu wajib kelihatan:
            -- artinya dropdown dan server memang menulis namanya beda.
            if dicentang and dicentang ~= nm then
                addLog("Nama beda tapi dicocokkan: dicentang '" .. dicentang ..
                       "' vs dijual '" .. tostring(nm) .. "'", "SHOP")
            end
            dicoba = dicoba + 1
            local sisa, terkunci, tahu = TOKO.info(shopId, nm)
            if tahu then adaTahu = true end

            if tahu and terkunci then
                -- Dikunci streak login. Server PASTI menolak, jadi jangan
                -- dibuang percuma jadi panggilan remote.
                kunci[#kunci + 1] = tostring(nm)
            elseif tahu and sisa <= 0 then
                habis[#habis + 1] = tostring(nm)
            else
                -- BALASAN SERVER SEKARANG DIBACA, bukan dibuang.
                -- Versi lama memanggil invokeRF lalu langsung menaikkan n
                -- tanpa melihat hasilnya sama sekali - jadi laporan
                -- "beli 3 item" muncul walau ketiganya ditolak. Ini yang
                -- membuat kegagalan supply sama sekali tidak kelihatan.
                -- HABISKAN STOK, bukan satu per putaran. Batas percobaannya
                -- dari stok yang TERBACA; kalau belum terbaca, 20 percobaan
                -- dan tetap berhenti di penolakan pertama.
                -- INI JUMLAH PANGGILAN, BUKAN JUMLAH BARANG. Tiap
                -- panggilan membawa `q` biji: 100 di SeedShop, 1 di toko
                -- lain (server memaksanya). Jadi target 300 bibit = 3
                -- panggilan @100, sementara 300 supply = 300 panggilan @1.
                local ulang = math.ceil(target / q)
                if habiskan then
                    -- Sakelar "beli sampai stok HABIS" MENANG atas angka
                    -- target - itu memang gunanya.
                    ulang = tahu and math.ceil(math.max(sisa, 1) / q) or 20
                elseif tahu then
                    -- Stok TERBACA -> potong di situ, supaya tidak ada
                    -- panggilan yang sudah pasti ditolak. Ini juga yang
                    -- membuat angka besar TIDAK berbahaya: minta 1000
                    -- sementara stoknya 4, yang dikirim tetap 4.
                    ulang = math.min(ulang, math.ceil(math.max(sisa, 1) / q))
                end
                -- ============================================================
                -- INI BATAS PANGGILAN, BUKAN BATAS JUMLAH BARANG
                -- ============================================================
                -- Kotak JUMLAH sudah dinaikkan ke 50.000, TAPI angka di
                -- sini SENGAJA tetap 1000 - dan bedanya penting.
                --
                -- Yang dibatasi di sini adalah berapa kali remote ditembak
                -- dalam SATU sapuan, bukan berapa biji yang boleh masuk.
                -- Di SeedShop satu panggilan membawa 100 biji, jadi target
                -- 50.000 = 500 panggilan - masih jauh di bawah batas ini.
                -- Di SupplyShop server memaksa 1 biji per panggilan, dan di
                -- situlah batas ini menyelamatkan: tanpa dia, target 50.000
                -- berarti 50.000 panggilan x Shop Delay = berjam-jam thread
                -- tertahan untuk barang yang stoknya cuma 3-6.
                --
                -- Dan ini pun jarang kepakai: dua baris di atas sudah
                -- memotong `ulang` ke STOK yang terbaca, dan loopnya
                -- berhenti di penolakan PERTAMA.
                ulang = math.clamp(ulang, 1, 1000)
                local harga = hargaEntri(entry)
                -- Pemeriksaan "barang yang masuk" cuma untuk pembelian
                -- TERPILIH. Untuk BORONG (allowAll) semua index memang
                -- ditembak, jadi tertukar pun tidak merugikan - dan
                -- memeriksanya cuma menambah kebisingan.
                -- DecorShop dikecualikan: barangnya tidak masuk tas.
                local periksa = (mau ~= nil) and (shopId ~= "DecorShop")

                for _ = 1, ulang do
                    local tas0 = periksa and TOKO.isiTas() or nil
                    local cash0 = angkaStat("Cash")
                    -- Harga ada di daftar toko, jadi pemeriksaan ini GRATIS -
                    -- dan mencegah panggilan yang sudah pasti ditolak.
                    if (not useGems) and cash0 and harga > 0 and cash0 < harga then
                        tolak = "cash kurang untuk " .. tostring(nm) ..
                                " ($" .. fmtNum(cash0) .. " < $" .. fmtNum(harga) .. ")"
                        break
                    end

                    local ok, res, msg
                    if useGems then
                        ok, res, msg = invokeRF("ShopService", "BuyItemWithGems", shopId, i)
                    else
                        ok, res, msg = invokeRF("ShopService", "BuyItem", shopId, i, q)
                    end
                    -- Jeda WAJIB-nya di SINI, sebelum menilai hasil: Replica
                    -- cash datang sebagai pesan terpisah, jadi kalau dibaca di
                    -- baris yang sama nilainya masih yang lama.
                    task.wait(config.shopDelay)

                    -- `res ~= false` BUKAN tanda berhasil: server yang membalas
                    -- NIL ikut terhitung SUKSES, jadi hub melapor "beli 3 item"
                    -- padahal tidak ada yang masuk dan tanpa pesan gagal.
                    -- Sekarang nil = BELUM TAHU, dibuktikan dari cash TURUN.
                    local jadi
                    if not ok or res == false then jadi = false
                    elseif res == true then jadi = true
                    else
                        local cash1 = angkaStat("Cash")
                        jadi = (cash0 ~= nil and cash1 ~= nil and cash1 < cash0)
                    end

                    if jadi then
                        -- ============================================================
                        -- INDEX BASI: "kebeli, tapi barang LAIN"
                        -- ============================================================
                        -- Sampai di sini yang terbukti cuma UANGNYA KELUAR.
                        -- Apa yang masuk masih belum tentu yang kamu centang:
                        -- BuyItem menuntut INDEX, dan index itu berasal dari
                        -- daftar yang bisa TIDAK SEJALAN dengan urutan server.
                        --
                        -- Jadi dibuktikan dari isi TAS - satu-satunya sumber
                        -- yang tidak bisa berbohong. Kalau yang bertambah bukan
                        -- yang diminta: berhenti SEKARANG (jangan diulang 50x),
                        -- dan KUNCI index itu ke nama yang barusan terukur
                        -- supaya sapuan berikutnya tidak salah beli lagi.
                        local naik = tas0 and (TOKO.yangNaik(tas0, TOKO.isiTas()))
                        if naik and polos(naik) ~= polos(nm) then
                            TOKO.benar[shopId] = TOKO.benar[shopId] or {}
                            TOKO.benar[shopId][i] = naik
                            stats.bought = stats.bought + 1
                            tolak = "INDEX SALAH - index " .. i .. " tertulis '" ..
                                    tostring(nm) .. "' di daftar (" .. sumber ..
                                    ") tapi yang MASUK TAS '" .. naik ..
                                    "'. Dihentikan, dan index itu sekarang dikunci" ..
                                    " ke nama terukur - sapuan berikutnya tidak" ..
                                    " salah beli lagi."
                            addLog("Buy SALAH BARANG @" .. shopId .. " index=" .. i ..
                                   " (" .. sumber .. "): minta '" .. tostring(nm) ..
                                   "' -> yang masuk '" .. naik .. "'", "SHOP")
                            break
                        end
                        n = n + 1
                        stats.bought = stats.bought + 1
                        -- stok lokal ikut turun supaya putaran berikutnya
                        -- tidak menembaki barang yang baru saja habis
                        local t = TOKO.stok[shopId]
                        if t and t[tostring(nm)] then
                            t[tostring(nm)].sisa = math.max((t[tostring(nm)].sisa or 1) - 1, 0)
                        end
                        addLog("Buy " .. tostring(nm) .. " x" .. q .. " @" .. shopId, "SHOP")
                    else
                        tolak = (res == false or not ok)
                            and tostring(msg or res or "ditolak tanpa pesan")
                            or ("server DIAM (tidak balas apa-apa) & cash tidak turun" ..
                                " - index " .. i .. " dari " .. sumber)
                        addLog("Buy DITOLAK: " .. tostring(nm) .. " @" .. shopId ..
                               " index=" .. i .. " (" .. sumber .. ") -> " .. tolak, "SHOP")
                        -- Ditolak = stoknya habis / tidak boleh. Mengulang
                        -- cuma menambah panggilan yang pasti ditolak lagi.
                        break
                    end
                end
            end
        end
    end

    if n > 0 then return n end

    if dicoba == 0 then
        -- TIGA sebab yang harus bisa dibedakan, karena tindakannya beda:
        --   (a) NAMA TIDAK TERBACA SAMA SEKALI -> bentuk datanya salah,
        --       bukan pilihanmu. Ini yang kejadian di GetShopStock.
        --   (b) namanya beda tipis -> bug pencocokan, harus dibetulkan
        --   (c) yang kamu centang memang TIDAK sedang dijual -> normal,
        --       toko cuma menjual sebagian katalog dan berputar
        local adaNama = false
        for _, s in ipairs(ada) do
            if s ~= "nil" then adaNama = true; break end
        end

        if not adaNama then
            -- Dicetak APA ADANYA, sekali per toko: kalau bentuknya tidak
            -- sesuai dugaan, satu-satunya jalan maju adalah melihat isi
            -- aslinya - bukan menebak field berikutnya.
            if not TOKO.dumped[shopId] then
                TOKO.dumped[shopId] = true
                addLog("BENTUK MENTAH " .. sumber .. "(" .. shopId ..
                       ") - nama tidak terbaca, ini isi aslinya:", "SHOP")
                for i = 1, math.min(#stock, 12) do
                    local e = stock[i]
                    if type(e) == "table" then
                        local ff = {}
                        for k, v in pairs(e) do
                            ff[#ff + 1] = tostring(k) .. "=" ..
                                (type(v) == "table" and "<table>" or tostring(v))
                        end
                        table.sort(ff)
                        addLog("  [" .. i .. "] {" .. table.concat(ff, ", ") .. "}", "SHOP")
                    else
                        addLog("  [" .. i .. "] " .. type(e) .. " " .. tostring(e), "SHOP")
                    end
                end
            end
            return 0, "nama barang TIDAK TERBACA dari " .. sumber .. " (" ..
                      #stock .. " entri, semuanya kosong) - BUKA PANEL TOKO di" ..
                      " game sekali supaya kartunya bisa dibaca. Bentuk mentahnya" ..
                      " sudah dicetak ke tab Output."
        end

        local dic = {}
        for k, v in pairs(wantedSet) do if v then dic[#dic + 1] = tostring(k) end end
        table.sort(dic)
        return 0, "tidak ada yang cocok di " .. shopId ..
                  "  ||  DICENTANG: " ..
                  (#dic > 0 and table.concat(dic, ", ") or "(kosong)") ..
                  "  ||  DIJUAL sekarang (" .. sumber .. "): " ..
                  table.concat(ada, ", ")
    end
    local sebab = {}
    if #habis > 0 then sebab[#sebab + 1] = "STOK HABIS: " .. table.concat(habis, ", ") end
    if #kunci > 0 then sebab[#sebab + 1] = "DIKUNCI STREAK: " .. table.concat(kunci, ", ") end
    if tolak then sebab[#sebab + 1] = "server menolak: " .. tolak end
    if #sebab == 0 then
        sebab[1] = adaTahu and "server menolak tanpa pesan"
                            or "stok aslinya belum terbaca - buka panel toko game sekali"
    end
    return 0, table.concat(sebab, " | ")
end

-- ============================================================
-- BELI SEKALI - satu sapuan, mengikuti angka di kotak JUMLAH
-- ============================================================
-- Bedanya dengan Auto Buy CUMA SATU: yang ini berhenti sesudah satu
-- sapuan. Toko sama, filter dropdown sama, angka JUMLAH sama.
--
-- `habiskan` sengaja dikirim FALSE - TIDAK ikut sakelar "beli sampai stok
-- HABIS". Tombol ini namanya "beli sekali sebanyak angka di kotak", jadi
-- angka itu yang harus dipatuhi; kalau sakelar itu ikut menang di sini,
-- angkanya jadi hiasan dan tombolnya berbohong.
--
-- SENGAJA global (tanpa `local`), seperti addLog & habisSupply: dipanggil
-- dari dua kartu do...end yang berbeda (tab Auto dan tab Shop), dan global
-- tidak memakan register sama sekali (batas Luau 200 per fungsi).
function beliSekali(shopId, pilihan, label, jumlah)
    if setIsEmpty(pilihan) then
        notify("Centang dulu barangnya di dropdown " .. label, THEME.Yellow)
        return 0
    end
    -- SATU SAPUAN PADA SATU WAKTU. Tanpa ini, dua tekanan beruntun - atau
    -- menekan tombol saat loop Auto Buy kebetulan sedang menyapu - mengirim
    -- dua sapuan yang saling menimpa. Yang dipertaruhkan UANG, bukan cuma
    -- waktu, jadi ini bukan kehati-hatian berlebihan.
    if TOKO.sibuk then
        notify("Pembelian lain sedang jalan - tunggu sebentar", THEME.Yellow)
        return 0
    end
    TOKO.sibuk = true
    local ok, n, why = pcall(buyFromShop, shopId, pilihan, jumlah, false, false, false)
    TOKO.sibuk = nil

    if not ok then
        notify("Gagal: " .. tostring(n), THEME.Red)
        addLog("BELI SEKALI " .. label .. " error: " .. tostring(n), "SHOP")
        return 0
    end
    n = tonumber(n) or 0
    if n > 0 then
        notify("Beli " .. label .. " sekali: " .. n .. " pembelian berhasil", THEME.On)
        addLog("BELI SEKALI " .. label .. " (target " .. tostring(jumlah) ..
               "/barang): " .. n .. " pembelian berhasil", "SHOP")
    else
        -- Alasan LENGKAPNYA tidak muat di toast 330x36 piksel - itu sudah
        -- terbukti memotong pesan tepat di bagian yang paling dicari. Jadi
        -- toast cuma menunjuk arah, teks utuhnya ke Output + kartu STOK ASLI.
        notify("Tidak ada yang dibeli - baca kartu 'STOK ASLI' di tab Shop",
               THEME.Yellow)
        addLog("BELI SEKALI " .. label .. ": " .. tostring(why), "SHOP")
    end
    return n
end

-- ============================================================
-- TOTAL YANG HARUS DIBAYAR untuk angka JUMLAH sekarang
-- ============================================================
-- Dipasang tepat di bawah tiap kotak JUMLAH. DUA angka, dan dua-duanya
-- perlu - menampilkan salah satunya saja itu menyesatkan:
--
--   BATAS ATAS -> harga x JUMLAH, dijumlah untuk semua yang dicentang.
--                 Ini yang keluar KALAU semuanya benar-benar terbeli.
--   REALISTIS  -> dipotong ke STOK yang TERBACA. Toko cuma menyetok 3-6
--                 biji per barang dan berputar tiap ~5 menit, jadi inilah
--                 yang biasanya benar-benar keluar dari kantongmu.
--
-- Kalau cuma batas atas yang ditampilkan, angkanya bisa 100x lipat dari
-- kenyataan dan kamu akan mengira hub mau menghabiskan seluruh uangmu.
-- Kalau cuma yang realistis, kamu kehilangan gambaran "kalau stoknya
-- kebetulan banyak, segini yang akan terjadi".
--
-- BARANG YANG HARGANYA BELUM TERBACA TIDAK IKUT DIJUMLAH, dan itu
-- disebutkan apa adanya - menganggapnya $0 sama saja berbohong tentang
-- total yang harus kamu bayar.
--
-- SENGAJA global (tanpa `local`), seperti beliSekali: dipanggil dari dua
-- kartu do...end yang berbeda (tab Auto dan tab Shop), dan global tidak
-- memakan register sama sekali (batas Luau 200 per fungsi).
function totalBelanja(shopId, pilihan, jumlah, folder)
    if setIsEmpty(pilihan) then
        return "TOTAL BIAYA: belum ada yang dicentang di dropdown."
    end
    jumlah = math.clamp(math.floor(tonumber(jumlah) or 1), 1, 50000)

    local f = assetFolder(folder)
    local baris = { "TOTAL kalau JUMLAH = " .. jumlah .. " per barang:" }
    local atas, nyata, buta, n = 0, 0, 0, 0

    for _, nama in ipairs(setList(pilihan)) do
        n = n + 1
        local m = f and f:FindFirstChild(nama)
        local h = TOKO.harga(shopId, nama, m)
        local sisa, kunci, tahu = TOKO.info(shopId, nama)
        -- Stok belum terbaca = JANGAN menebak nol. Pakai jumlah penuh;
        -- kalau salah, salahnya ke arah "terlalu hati-hati soal uang".
        local bisa = jumlah
        if tahu then bisa = kunci and 0 or math.min(jumlah, sisa) end

        if h > 0 then
            atas  = atas + h * jumlah
            nyata = nyata + h * bisa
        else
            buta = buta + 1
        end

        if n <= 8 then
            baris[#baris + 1] = string.format("  %-20s %9s x%-4d = %10s  %s",
                string.sub(nama, 1, 20),
                (h > 0) and ("$" .. fmtNum(h)) or "harga?",
                jumlah,
                (h > 0) and ("$" .. fmtNum(h * jumlah)) or "?",
                tahu and (kunci and "stok TERKUNCI" or ("stok " .. sisa))
                      or "stok belum terbaca")
        end
    end
    if n > 8 then baris[#baris + 1] = "  ... (+" .. (n - 8) .. " barang lagi)" end

    local cash, sumberCash = angkaStat("Cash")
    baris[#baris + 1] = ""
    baris[#baris + 1] = "BATAS ATAS (kalau semuanya kebeli) : $" .. fmtNum(atas)
    baris[#baris + 1] = "REALISTIS  (dipotong stok terbaca) : $" .. fmtNum(nyata)
    baris[#baris + 1] = "Cash kamu                          : " ..
        (cash and ("$" .. fmtNum(cash) ..
            (sumberCash == "label game" and "  (dari label game)" or ""))
         or "TIDAK TERBACA (replica DAN label game dua-duanya gagal)")

    if cash then
        if cash >= atas then
            baris[#baris + 1] = "  -> CUKUP, bahkan untuk batas atasnya"
        elseif cash >= nyata then
            baris[#baris + 1] = "  -> cukup untuk yang REALISTIS; batas atasnya" ..
                                " kurang $" .. fmtNum(atas - cash)
        else
            baris[#baris + 1] = "  -> KURANG $" .. fmtNum(nyata - cash) ..
                                " bahkan untuk yang realistis"
        end
    end
    if buta > 0 then
        baris[#baris + 1] = buta .. " barang harganya belum terbaca -" ..
                            " TIDAK ikut dijumlah (bukan dianggap gratis)."
    end
    return table.concat(baris, "\n")
end

-- ---------- BUILD (Place = beli + pasang) ----------
-- Cari titik kosong di atas PlotBase zona yang sesuai.
local function findFreeSpot(placeZone, minDist)
    local base = getZoneBase(placeZone)
    if not base then return nil end
    local plot = getMyPlot()
    local objects = plot and plot:FindFirstChild("Objects")

    -- kumpulkan posisi objek yang sudah ada (XZ saja)
    local taken = {}
    if objects then
        for _, m in ipairs(objects:GetChildren()) do
            local ok, piv = pcall(function() return m:GetPivot().Position end)
            if ok then table.insert(taken, Vector2.new(piv.X, piv.Z)) end
        end
    end

    -- WAJIB dijaga > 0. Dua while di bawah maju dengan `x = x + step`;
    -- kalau step 0 atau minus, loop itu TIDAK PERNAH berhenti dan tidak
    -- punya yield sama sekali -> Roblox membeku total (bukan error, tapi
    -- hang). Slider memang dibatasi 4..24, TAPI loadSettings() menyalin
    -- nilai mentah dari file JSON tanpa memeriksa, jadi file konfigurasi
    -- lama / rusak bisa menyuntikkan 0 ke sini.
    local step   = tonumber(config.gridStep) or 8
    if step < 1 then step = 8; config.gridStep = 8 end
    local size   = base.Size
    local cf     = base.CFrame
    local topY   = base.Position.Y + size.Y / 2
    local halfX  = size.X / 2 - step
    local halfZ  = size.Z / 2 - step

    local x = -halfX
    while x <= halfX do
        local z = -halfZ
        while z <= halfZ do
            local world = cf * CFrame.new(x, size.Y / 2, z)
            local p2 = Vector2.new(world.Position.X, world.Position.Z)
            local free = true
            for _, t in ipairs(taken) do
                if (t - p2).Magnitude < (minDist or step) then free = false; break end
            end
            if free then
                return Vector3.new(world.Position.X, topY, world.Position.Z)
            end
            z = z + step
        end
        x = x + step
    end
    return nil
end

-- Place(namaItem, CFrame, "Furniture", {warna})
local function placeItem(itemName, rotationDeg)
    local model, sub = findObjectModel(itemName)
    if not model then return false, "item '" .. tostring(itemName) .. "' tidak ada di Assets.Objects" end
    local placeZone = model:GetAttribute("PlaceZone") or "Farm"
    local pos = findFreeSpot(placeZone, config.gridStep)
    if not pos then return false, "tidak ada tempat kosong di zona " .. placeZone end

    local cframe = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotationDeg or 0), 0)
    local ok, res, err = invokeRF("PlacementService", "Place", itemName, cframe, "Furniture", {})
    if not ok then return false, "remote error: " .. tostring(res) end
    if res == false then return false, tostring(err or "server menolak") end
    stats.placed = stats.placed + 1
    addLog("Place " .. itemName .. " (" .. sub .. ") @" .. placeZone, "BUILD")
    return true
end

-- pasang semua item yang dicentang, 1 unit per item per putaran
local function placeSelected(wantedSet, rotationDeg, running)
    local list = setList(wantedSet)
    if #list == 0 then return 0 end
    local n = 0
    for _, nm in ipairs(list) do
        if running and not running() then break end
        local ok, err = placeItem(nm, rotationDeg)
        if ok then n = n + 1 else addLog("Place gagal (" .. nm .. "): " .. tostring(err), "BUILD") end
        task.wait(turboDelay(config.buildDelay))
    end
    return n
end

-- ---------- CRAFT / SELL ----------
local function flowerInventory()
    local out, order = {}, {}
    for _, t in ipairs(allTools()) do
        if isFlowerTool(t) then
            if not out[t.Name] then out[t.Name] = 0; table.insert(order, t.Name) end
            out[t.Name] = out[t.Name] + (t:GetAttribute("Count") or 1)
        end
    end
    table.sort(order)
    return out, order
end

-- ---------- MEMAHALKAN HARGA JUAL ----------
-- TIDAK ADA remote untuk mengetik harga sendiri: CustomerService cuma
-- punya SATU remote (ToggleShopOpen). Harga dihitung SERVER, tapi
-- rumusnya kelihatan di client (RSV2TELITI 1466176-1466190):
--
--     harga = priceAdd WADAH + priceBase TIAP BUNGA
--
-- ACCENT tidak ikut dijumlah. Jadi yang benar-benar menaikkan uang cuma
-- dua: BANYAKNYA bunga per rangkaian, dan priceBase bunga yang dipakai -
-- selisih antar bunga ratusan kali lipat (Orchid 12.119, PinkTulip 2).
--
-- Batas accent = fungsi LEVEL CraftTable, bukan atribut (lihat
-- accentCap()). Tabel wadah & accent lengkapnya sengaja cuma ada di
-- kartu UI-nya, supaya tidak ada dua salinan yang harus ikut diperbarui.

-- LEVEL PEMAIN - dan kenapa ini butuh dua sumber.
--
-- Sumber utama: Replica Data.Level. Itu SUDAH benar (dikonfirmasi di dump
-- client: `p1.Data.Level`, dipakai StatsFrame & shop UI). MASALAHNYA,
-- pdata("Level", 1) mengembalikan DEFAULT 1 kalau ReplicaController gagal
-- dibaca -- dan pemanggil tidak bisa membedakan "level 1 beneran" dari
-- "gagal baca". Akibatnya filter requiredLevel <= 1 cuma meloloskan
-- Small Bouquet, walau pemainnya sudah level tinggi. ITU sebabnya
-- "wadah termahal otomatis" malah memilih Small Bouquet.
--
-- Cadangan: label milik GAME SENDIRI di
-- PlayerGui.ScreenGui.StatsFrame.Level yang isinya "Lv. 57"
-- (dump client baris 8672). Kalau replica gagal, ini tetap benar.
--
-- Balikan nil = benar-benar TIDAK TAHU -> pemanggil harus BERHENTI
-- menyaring, bukan menganggapnya level 1.
local function myLevel()
    local rep = grabReplica()
    if rep and type(rep.Data) == "table" then
        local n = tonumber(rep.Data.Level)
        if n then return n end
    end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local sg = pg and pg:FindFirstChild("ScreenGui")
    local sf = sg and sg:FindFirstChild("StatsFrame")
    local lb = sf and sf:FindFirstChild("Level")
    if lb then
        local n = tonumber(string.match(tostring(lb.Text), "(%d+)"))
        if n then return n end
    end
    return nil
end

-- wadah dengan priceAdd TERTINGGI yang levelnya sudah kebuka
local function bestContainer()
    local f = assetFolder("Arrangements")
    if not f then return nil end
    local myLvl = myLevel()   -- nil = tidak diketahui
    local best, bestAdd = nil, -1
    for _, m in ipairs(f:GetChildren()) do
        local need = tonumber(m:GetAttribute("requiredLevel")) or 1
        local add  = tonumber(m:GetAttribute("priceAdd")) or 0
        -- Level tidak diketahui -> JANGAN menyaring. Lebih baik server yang
        -- menolak sekali daripada terkunci selamanya di Small Bouquet.
        if (myLvl == nil or need <= myLvl) and add > bestAdd then
            best, bestAdd = m.Name, add
        end
    end
    return best, bestAdd
end

-- Wadah dengan maxFlowers TERBANYAK yang levelnya sudah kebuka.
-- SENGAJA dibaca runtime dari Assets.Arrangements, tidak di-hardcode:
-- katalog game bisa bertambah (Spring Basket, dsb) dan angka pastinya
-- cuma developer yang tahu. Balikan: nama, kapasitas bunga, priceAdd.
local function biggestContainer()
    local f = assetFolder("Arrangements")
    if not f then return nil end
    local myLvl = myLevel()   -- nil = tidak diketahui, jangan menyaring
    local best, bestMax, bestAdd = nil, -1, 0
    for _, m in ipairs(f:GetChildren()) do
        local need = tonumber(m:GetAttribute("requiredLevel")) or 1
        local mx   = tonumber(m:GetAttribute("maxFlowers")) or 0
        if (myLvl == nil or need <= myLvl) and mx > bestMax then
            best, bestMax = m.Name, mx
            bestAdd = tonumber(m:GetAttribute("priceAdd")) or 0
        end
    end
    return best, bestMax, bestAdd
end

-- daftar accent terbaik (priceAdd tertinggi) yang levelnya sudah kebuka
local function bestAccents(howMany)
    local f = assetFolder("Accents")
    if not f then return {} end
    local myLvl = myLevel()   -- nil = tidak diketahui, jangan menyaring
    local pool = {}
    for _, m in ipairs(f:GetChildren()) do
        local need = tonumber(m:GetAttribute("requiredLevel")) or 1
        if myLvl == nil or need <= myLvl then
            pool[#pool + 1] = { name = m.Name, add = tonumber(m:GetAttribute("priceAdd")) or 0 }
        end
    end
    table.sort(pool, function(a, b) return a.add > b.add end)
    local out = {}
    for i = 1, math.min(howMany or 1, #pool) do out[i] = pool[i].name end
    return out
end

-- ============================================================
-- "maxAccents" BUKAN ATRIBUT - jangan pernah GetAttribute("maxAccents")
-- ============================================================
-- Nol kemunculan di seluruh dump workspace (335 MB). Yang benar: dia
-- FUNGSI dari LEVEL CraftTable (EquipmentConfig, RSV2TELITI
-- 1466260-1466274) -> 5 di Lv20, 4 di Lv10, 3 di Lv5, selain itu 2.
-- Levelnya dari EquipmentService.GetEquipmentLevel.
local function accentCap()
    local ok, lvl = invokeRF("EquipmentService", "GetEquipmentLevel", "CraftTable")
    lvl = (ok and tonumber(lvl)) or 1
    if lvl >= 20 then return 5, lvl end
    if lvl >= 10 then return 4, lvl end
    if lvl >= 5  then return 3, lvl end
    return 2, lvl
end

-- Rak bunga dengan KAPASITAS terbesar yang MASIH TERBELI dengan cash
-- sekarang. Dipakai saat semua rak penuh: nambah rak adalah satu-satunya
-- cara menaikkan daya tampung (Max tiap rak dikunci server).
local function bestAffordableDisplay()
    local f = objectsFolder("Displays")
    if not f then return nil end
    local cash = angkaStat("Cash") or 0
    local best, bestMax, bestPrice = nil, -1, 0
    for _, m in ipairs(f:GetChildren()) do
        local mx = tonumber(m:GetAttribute("Max")) or 0
        local pr = tonumber(m:GetAttribute("Price")) or 0
        -- Rak ber-atribut VIP DILEWATI. Tombol ini MEMASANG langsung
        -- (Place = beli), jadi kalau kamu bukan VIP dia cuma akan ditolak
        -- server berulang kali. Kebetulan rak VIP semuanya Max <= 12
        -- sementara yang bebas ada yang Max 30, jadi tidak ada yang hilang.
        if not m:GetAttribute("VIP") and pr <= cash and mx > bestMax then
            best, bestMax, bestPrice = m.Name, mx, pr
        end
    end
    return best, bestMax, bestPrice
end

-- Daftar rak diurut dari kapasitas-per-rupiah TERBAIK (Max / Price).
local function displayValueTable(topN)
    local f = objectsFolder("Displays")
    local rows = {}
    if f then
        for _, m in ipairs(f:GetChildren()) do
            local mx = tonumber(m:GetAttribute("Max")) or 0
            local pr = tonumber(m:GetAttribute("Price")) or 0
            if mx > 0 then
                rows[#rows + 1] = { name = m.Name, max = mx, price = pr,
                                    vip = m:GetAttribute("VIP") == true,
                                    per = (pr > 0) and (pr / mx) or 0 }
            end
        end
    end
    table.sort(rows, function(a, b) return a.per < b.per end)
    local out = {}
    for i = 1, math.min(topN or 6, #rows) do
        local r = rows[i]
        out[#out + 1] = string.format("  %-22s max %-3d  $%-9s  $%.0f/slot%s",
            r.name, r.max, fmtNum(r.price), r.per, r.vip and "   [VIP]" or "")
    end
    return out
end

-- `wadahPaksa` / `batchPaksa` = dipakai tombol COMBO di bawah supaya dia
-- tidak perlu menyalin seluruh mesin ini. Kalau nil, perilakunya persis
-- seperti semula: wadah dari sakelar/dropdown, batch dari slider.
local function doCraftOnce(batchPaksa, wadahPaksa)
    -- Urutan prioritas pemilihan wadah:
    --   0. paksaan dari pemanggil (tombol COMBO)
    --   1. "wadah KAPASITAS terbesar" -> paling banyak bunga per rangkaian
    --      (ini yang memilih Spring Basket kalau dia yang termuat)
    --   2. "wadah TERMAHAL"           -> priceAdd tertinggi
    --   3. pilihan manual di dropdown Container
    local container = wadahPaksa
    if not container then
        container = config.containerPick
        if config.autoBigContainer then
            container = biggestContainer() or container
        elseif config.autoBestContainer then
            container = bestContainer() or container
        end
    end
    if not container or container == "" then return false, "container belum dipilih" end

    local ct = getMyCraftTable()
    if not ct then return false, "CraftTable tidak ketemu di plot" end

    local arrFolder = assetFolder("Arrangements")
    local arrModel = arrFolder and arrFolder:FindFirstChild(container)
    local maxFlowers = (arrModel and arrModel:GetAttribute("maxFlowers")) or 3

    -- invokeRF -> ok(pcall), lalu nilai balik server: StartArranging = (berhasil, pesan)
    local ok, started, err = invokeRF("ArrangementService", "StartArranging", ct)
    if not ok then return false, "remote error: " .. tostring(started) end
    if started == false then return false, "StartArranging ditolak: " .. tostring(err or "tanpa pesan") end

    -- ISI SAMPAI KAPASITAS WADAH, bukan sampai jenis bunga habis.
    -- Versi lama menyisir `order` -- itu daftar NAMA UNIK -- dan reserve
    -- SEKALI per nama. Jadi kalau punya 30 Rose + 1 Tulip, yang masuk cuma
    -- 2 BUNGA walau wadahnya muat 12. Itu membuat wadah besar (Spring
    -- Basket dll) sama sekali tidak terasa gunanya. Sekarang tiap jenis
    -- di-reserve sebanyak stoknya sampai wadahnya penuh.
    local inv, order = flowerInventory()

    -- URUTKAN DARI priceBase TERTINGGI. JANGAN pakai urutan
    -- flowerInventory() apa adanya - itu urut ABJAD, jadi wadah 12-slot
    -- terisi "Anemone" sampai penuh dan "Delphinium" tidak kebagian.
    --
    -- Rumus harga = priceAdd WADAH + priceBase TIAP BUNGA, dan priceBase
    -- antar bunga bedanya ratusan kali lipat (terukur dari atributnya):
    --     Delphinium 903   GreenHydrangea 799   PinkHydrangea 703
    --     Hydrangea  639   PurplePeony    301   Rose 4   PinkTulip 2
    -- Spring Basket isi Delphinium ~10.936, isi Rose ~148 - 70x lipat,
    -- cuma karena huruf pertama namanya. Seri = urut abjad, biar ketebak.
    do
        local fl = assetFolder("Flowers")
        local harga = {}
        for _, nm in ipairs(order) do
            local m = fl and fl:FindFirstChild(nm)
            harga[nm] = tonumber(m and m:GetAttribute("priceBase")) or 0
        end
        table.sort(order, function(a, b)
            if harga[a] ~= harga[b] then return harga[a] > harga[b] end
            return a < b
        end)
    end

    local picked = {}
    for _, name in ipairs(order) do
        if #picked >= maxFlowers then break end
        for _ = 1, (inv[name] or 0) do
            if #picked >= maxFlowers then break end
            local rok, reserved = invokeRF("ArrangementService", "ReserveFlower", name)
            if not rok or reserved == false then break end   -- ditolak: pindah jenis
            picked[#picked + 1] = name
            task.wait(turboDelay(0.06))
        end
    end

    if #picked == 0 then
        invokeRF("ArrangementService", "CancelArranging")
        return false, "tidak ada bunga di inventory"
    end

    -- ============================================================
    -- ACCENT BELUM TERBUKTI MENAMBAH UANG - jangan dijual sebagai fitur
    -- ============================================================
    -- Tiga fakta terukur yang menunjuk ke arah yang sama:
    --   1. ReserveAccent NOL call-site di seluruh dump client
    --   2. UI craft game tidak punya pemilih accent; tabel muatannya
    --      lahir dengan accents = {} dan tidak pernah diisi client
    --      (SPSV2TELITI 6516-6520)
    --   3. rumus harga cuma priceAdd WADAH + priceBase TIAP BUNGA
    --      (RSV2TELITI 1466176-1466190) - accent tidak ikut dijumlah
    --
    -- Yang TERBUKTI menaikkan harga: BANYAKNYA BUNGA per rangkaian.
    -- Karena itu bawaan MODE UANG MAKSIMUM adalah "wadah kapasitas
    -- terbesar", bukan "wadah termahal".
    local accents = {}
    if config.autoAccents then
        local want = math.min(math.floor(config.accentCount), (accentCap()))
        for _, a in ipairs(bestAccents(want)) do
            accents[#accents + 1] = a
            invokeRF("ArrangementService", "ReserveAccent", a)
            task.wait(0.05)
        end
    end

    -- `accents` WAJIB ADA di tabelnya, walau kosong. Game SELALU
    -- mengirimnya - tabel muatannya lahir dengan accents = {} dan tidak
    -- pernah dihapus (SPSV2TELITI 6516-6520), lalu tabel itu juga yang
    -- dipakai FinishArranging maupun FinishBatchArranging (6724, 6728).
    -- Versi lama hub ini mengirim tanpa field itu sama sekali; kalau
    -- server melakukan #payload.accents, itu error di sisi sana.
    local payload = {
        container = container,
        preset    = nil,
        flowers   = picked,
        accents   = accents,
    }

    -- Batch: persis alur game (ArrangementController 817-829) - resep
    -- di-reserve sekali, lalu FinishBatchArranging(payload, jumlah).
    --
    -- WAJIB MEMBACA BALASAN SERVER. invokeRF balik (okPcall, jadi, pesan)
    -- dan okPcall SELALU true selama remote-nya ada. Menangkap nilai
    -- pertama saja = rangkaian yang DITOLAK server dilaporkan berhasil,
    -- dan tombol CRAFT MASSAL ikut menghitungnya - "400 buket" fiktif.
    -- Bentuknya terbukti; game sendiri membaca keduanya (6728-6733):
    --     FinishArranging(t):andThen(function(p1, p2)
    --         if p1 then return end ; SendNotification(p2) end)
    local batch = math.max(1, math.floor(tonumber(batchPaksa or config.craftBatch) or 1))
    local fok, jadi, pesan
    if batch > 1 then
        fok, jadi, pesan = invokeRF("ArrangementService", "FinishBatchArranging", payload, batch)
    else
        fok, jadi, pesan = invokeRF("ArrangementService", "FinishArranging", payload)
    end

    if not fok then return false, "remote error: " .. tostring(jadi) end
    if jadi == false then
        return false, "server menolak: " .. tostring(pesan or "tanpa pesan")
    end

    stats.crafted = stats.crafted + batch
    addLog("Craft " .. container .. " x" .. batch ..
           " (" .. table.concat(picked, ", ") .. ")", "CRAFT")
    return true
end

-- Kalau SEMUA rak penuh, server melempar bunga ke backpack ("No display space").
-- Tanpa penjaga ini loop-nya terus jalan sia-sia dan bikin console spam,
-- jadi kita berhenti + kasih tahu SEKALI saja sampai ada rak yang lowong lagi.
--
-- SATU TABEL, bukan tiga variabel terpisah: main chunk ini sudah dekat batas
-- 200 register lokal Luau, jadi setiap nama baru di level teratas mahal.
--   _stockWarn.flower = alasan terakhir yang sudah diberitahukan (rak bunga)
--   _stockWarn.arr    = idem untuk rak rangkaian
--   _stockWarn.cap    = BATAS BAWAH kapasitas rak rangkaian: isi terbanyak
--                       yang pernah benar-benar masuk. Dikunci per NAMA
--                       MODEL rak: { ["Tall Bouquet Shelf"] = 12 }
--   _stockWarn.penuh  = kapasitas PASTI, dipelajari dari PENOLAKAN server:
--                       kalau rak berisi K menolak, kapasitasnya TEPAT K.
--
-- KENAPA KAPASITAS RANGKAIAN HARUS DIUKUR, TIDAK BISA DIBACA:
--   * PLANTER   -> atribut "Slots".  terbaca, dipakai
--   * RAK BUNGA -> atribut "Max".    terbaca, dipakai
--   * RAK RANGKAIAN -> TIDAK ADA angkanya di client sama sekali.
--     ArrangementDisplay tidak pernah membaca kapasitas apa pun
--     (prompt-nya cuma "(N stocked)"), dan pencarian maxArrangements /
--     arrangementCapacity / perTier di seluruh RS = NOL hasil.
--
-- Jadi angkanya cuma ada di SERVER, dan pengukuran paling tepat adalah
-- PENOLAKAN: rak yang menolak saat berisi K berarti kapasitasnya TEPAT K.
--
--   _stockWarn.inst   = RAK MANA yang sudah bilang PENUH, dikunci per
--                       OBJEK RAK - bukan per nama model. Ini yang
--                       menutup lubang terakhir: `penuh` cuma tahu
--                       "Tall Bouquet Shelf muat 12", dia TIDAK tahu rak
--                       nomor 37 sudah berisi 12. Isi tiap rak memang
--                       dibaca ulang dari folder _Arrangements, TAPI
--                       kalau folder itu tidak terbaca (belum
--                       direplikasi, strukturnya beda) rak itu SELALU
--                       terlihat kosong dan ditembaki terus - persis
--                       gejala "spam taro ke rak".
--                       [rak] = { isi = saat ditolak, t = os.clock() }
--                       Tabel WEAK-KEY: rak yang dibongkar hilang sendiri.
local _stockWarn = { cap = {}, penuh = {},
                     inst = setmetatable({}, { __mode = "k" }) }

-- ============================================================
-- APAKAH PENOLAKAN SERVER ITU BENAR-BENAR "RAKNYA PENUH"
-- ============================================================
-- Dipasang sebagai FIELD, bukan `local function`: nol register (batas
-- Luau 200 per fungsi).
--
-- INI OBAT DARI BUG YANG SAYA BUAT SENDIRI. Versi kemarin memperlakukan
-- SETIAP penolakan sebagai "rak ini penuh", lalu mengunci rak itu 45
-- detik. Padahal penolakan bisa lahir dari sebab yang sama sekali lain -
-- tangan belum memegang rangkaian saat permintaan tiba, RateLimiter,
-- atau plot yang belum selesai direplikasi. Kalau itu yang terjadi,
-- SEMUA rak ditolak, SEMUA dikunci 45 detik, dan fitur yang tadinya
-- jalan jadi diam total - persis keluhan "sebelumnya berfungsi".
--
-- Kata kuncinya longgar dan saya TIDAK mengklaim lengkap: teks
-- penolakan StockArrangement tidak pernah muncul di dump client. Yang
-- dikenali cuma dipakai untuk MENAMBAH keyakinan; kalau pesannya tidak
-- dikenali, keputusannya jatuh ke syarat yang lebih keras di bawah -
-- isi rak harus benar-benar TERBACA dulu.
_stockWarn.katakanPenuh = function(msg)
    local s = string.lower(tostring(msg or ""))
    for _, k in ipairs({ "full", "penuh", "space", "room", "capacity",
                         "kapasitas", "no display" }) do
        if string.find(s, k, 1, true) then return true end
    end
    return false
end

-- ============================================================
-- ISI SATU RAK SAMPAI MENTOK - dipakai DUA jalur, satu mesin
-- ============================================================
-- Dipisah jadi fungsi sendiri karena sekarang ada DUA pemanggil:
--   1. sapuan berkala doStockArrangementOnce (semua rak)
--   2. PEMICU INSTAN saat pembeli mengambil dari rak (satu rak saja)
--
-- Kalau dua jalur itu punya salinan kodenya masing-masing, cepat atau
-- lambat salah satu ketinggalan perbaikan - dan itu persis kelas bug
-- yang sudah tiga kali kena di file ini (arrStock ditulis 3x, holdTool
-- ditulis 3x). Jadi satu mesin, dua pemanggil.
--
-- Balikan: berapa yang MASUK, lalu alasan kalau nol.
--
-- SENGAJA global: nol register (batas Luau 200 per fungsi).
function isiRakSekali(disp)
    if not (disp and disp.Parent) then return 0, "rak sudah tidak ada" end
    if not getRemote("FlowerDisplayService", "RF", "BulkStockArrangement") then
        return 0, "BulkStockArrangement tidak ada di game ini"
    end

    local masuk, alasan = 0, nil

    -- Diulang UNTUK RAK YANG SAMA, dan itu bukan pemborosan: label quick-key
    -- milik game berbunyi "bulk:" .. Container (SPSv3 1275), jadi ada
    -- kemungkinan satu panggilan cuma menghabiskan wadah SEJENIS. Kalau
    -- ternyata server menghabiskan semuanya sekaligus, putaran kedua
    -- langsung berhenti karena tas kosong - jadi tidak ada yang terbuang.
    for _ = 1, 6 do
        -- Tool dicari ULANG tiap putaran: satu panggilan bulk bisa
        -- menghabiskan belasan tool sekaligus, jadi acuan lama pasti basi.
        local pegang = nil
        for _, t in ipairs(allTools()) do
            if t.Parent and t:GetAttribute("IsArrangement") then pegang = t; break end
        end
        if not pegang then
            if masuk == 0 then alasan = "tidak ada rangkaian di inventory" end
            break
        end
        if not pegangTool(pegang) then
            if masuk == 0 then alasan = "rangkaian tidak bisa dipegang" end
            break
        end

        local isiA = rakIsi(disp)
        local ok, res, pesan =
            invokeRF("FlowerDisplayService", "BulkStockArrangement", disp)
        -- Jeda pendek supaya isi folder _Arrangements sempat direplikasi
        -- sebelum dihitung. SATU jeda per panggilan bulk, bukan per
        -- rangkaian - itu bedanya dengan jalur lama.
        task.wait(0.1)
        local isiB, baca = rakIsi(disp)
        local naik = isiB - isiA

        if naik > 0 then
            masuk = masuk + naik
            stats.stocked = stats.stocked + naik
            -- Rak ini TERBUKTI masih menerima, jadi catatan "penuh"
            -- miliknya dibuang - kalau tidak, catatan basi membuatnya
            -- dilewati 45 detik padahal jelas-jelas lowong.
            _stockWarn.inst[disp] = nil
            _stockWarn.rem = nil
            addLog("Stock All -> " .. disp.Name .. "  +" .. naik ..
                   " rangkaian (isi " .. isiA .. " -> " .. isiB ..
                   ")  SATU panggilan", "SELL")
        else
            -- TIGA syarat sebelum mencap PENUH, dan ketiganya perlu:
            --   ok    -> pcall remote-nya BERHASIL. Kalau panggilannya
            --            sendiri error, "tidak bertambah" itu bukti tentang
            --            ERROR-nya - sama sekali bukan bukti raknya penuh.
            --   baca  -> folder _Arrangements benar-benar terbaca; kalau
            --            tidak, isiB itu 0 palsu.
            --   isiB>0-> rak berisi NOL jelas bukan ditolak karena penuh.
            if ok and baca and isiB > 0 then
                local lama = _stockWarn.penuh[disp.Name]
                if lama == nil or isiB < lama then
                    _stockWarn.penuh[disp.Name] = isiB
                    addLog("KAPASITAS TERUKUR (Stock All): " .. disp.Name ..
                           " = " .. isiB .. " rangkaian - server berhenti" ..
                           " di angka ini", "SELL")
                end
                _stockWarn.inst[disp] = { isi = isiB, t = os.clock() }
                if masuk == 0 then alasan = "PENUH" end
            elseif masuk == 0 then
                alasan = tostring(pesan or res or
                    "tidak bertambah, dan isi rak tidak terbaca")
            end
            break
        end
    end

    return masuk, alasan
end

-- STOK BUNGA KE RAK.
-- TIDAK ADA cara memaksa melewati Max: server menolak dan melempar bunga
-- balik ke backpack ("No display space"). Jadi strateginya bukan memaksa,
-- tapi (a) LEWATI rak penuh sepenuhnya, (b) dahulukan rak paling lowong,
-- (c) isi tiap rak sampai PENUH sekali jalan, bukan satu-satu per putaran.
local function doStockFlowerOnce()
    local displays = rakPlot("FlowerDisplay")
    if #displays == 0 then return 0 end

    -- (1) SATU sapuan inventory di depan - alasan lengkapnya ada di
    -- doStockArrangementOnce() di bawah. Singkatnya: equipToolBy() dulu
    -- dipanggil per bunga dan menyisir ulang Character + Backpack tiap
    -- kali. Filter "Flowers to Stock" ikut diterapkan di sapuan ini,
    -- jadi tidak perlu diperiksa lagi per item.
    local bag = {}
    for _, t in ipairs(allTools()) do
        if isFlowerTool(t) and setAllows(sel.stockFlowers, t.Name) then
            bag[#bag + 1] = t
        end
    end
    if #bag == 0 then return 0 end   -- tidak ada bunga yang cocok: berhenti CEPAT

    -- Sama seperti rangkaian: server memeriksa bunga yang DIPEGANG
    -- (_getEquippedFlower menyisir Character, SPSV2TELITI 877-892), jadi
    -- equip HARUS ditunggu sampai benar-benar mendarat. Tanpa ini tombol
    -- melapor "stok 40 kali" tanpa rak bertambah seisi pun - dan di
    -- TURBO penolakannya tidak terbaca sama sekali.
    local function pegang(t)
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum) then return false end
        if t.Parent == char then return true end   -- sudah di tangan
        pcall(function() hum:EquipTool(t) end)
        local t0 = os.clock()
        while t.Parent ~= char and (os.clock() - t0) < 0.5 do task.wait() end
        if t.Parent ~= char then return false end
        task.wait(0.08)   -- jeda replikasi equip -> server
        return true
    end

    local bi = 1
    local function nextTool()
        while bag[bi] do
            local t = bag[bi]
            if t.Parent and pegang(t) then return t end
            bi = bi + 1
        end
        return nil
    end

    -- (2) daftar rak yang MASIH punya ruang, diurut dari yang paling lowong
    local open, totalFree = {}, 0
    for _, disp in ipairs(displays) do
        local free = (disp:GetAttribute("Max") or 8) - displayStock(disp)
        if free > 0 then
            open[#open + 1] = { d = disp, free = free }
            totalFree = totalFree + free
        end
    end

    if #open == 0 then
        if not _stockWarn.flower then
            _stockWarn.flower = true
            notify("Semua rak PENUH - buka kartu 'RAK PENUH' di tab Craft", THEME.Yellow)
            addLog("Semua " .. #displays .. " rak penuh, auto-stock idle", "SELL")
        end
        return 0
    end
    _stockWarn.flower = nil
    table.sort(open, function(a, b) return a.free > b.free end)

    -- (3) berhenti tepat saat bunga habis ATAU ruang habis
    local budget = math.min(#bag, totalFree)

    local n = 0
    for _, entry in ipairs(open) do
        -- isi sampai penuh; 'free' dihitung dari snapshot sebelum menembak,
        -- jadi tetap benar walau mode TURBO tidak menunggu balasan server
        for _ = 1, entry.free do
            if n >= budget then return n end
            local tool = nextTool()
            if not tool then return n end   -- bunga habis
            local ok, res = callRF("FlowerDisplayService", "StockFlower", entry.d)
            if ok and res ~= false then
                n = n + 1
                stats.stocked = stats.stocked + 1
                addLog("Stock " .. tool.Name .. " -> " .. entry.d.Name, "SELL")
            end
            if state.turbo then bi = bi + 1 end
            task.wait(turboDelay(config.sellDelay))
        end
    end
    return n
end

-- STOK RANGKAIAN KE RAK.
-- Versi lama menembak SEMUA rak rangkaian tanpa memeriksa kapasitas sama
-- sekali - termasuk yang sudah penuh. Itu sebabnya pesan "display full"
-- muncul terus-menerus: tiap putaran rak penuh tetap dicoba lagi.
-- Sekarang sama seperti rak bunga: rak penuh DILEWATI, rak paling lowong
-- didahulukan, dan tiap rak diisi sampai penuh sekali jalan.
local function doStockArrangementOnce()
    local displays = rakPlot("ArrangementDisplay")
    if #displays == 0 then return 0, "tidak ada rak rangkaian di plot" end

    -- (1) SATU sapuan inventory di depan.
    -- Versi lama memanggil equipToolBy() untuk SETIAP rangkaian yang
    -- ditaruh, dan tiap panggilan menyisir ULANG seluruh Character +
    -- Backpack dari awal. 50 rangkaian = 50 penyisiran penuh. ITU sumber
    -- lambatnya -- bukan pencarian raknya (rak sudah disaring sejak awal).
    -- Sekarang: satu sapuan, hasilnya dipakai ulang.
    --
    -- Atribut "IsArrangement" BUKAN tebakan: controller game sendiri yang
    -- memakainya (SPSTELITI baris 1116-1120, _getEquippedArrangement):
    --     if v:IsA("Tool") and v:GetAttribute("IsArrangement") then
    local bag = {}
    for _, t in ipairs(allTools()) do
        if t:GetAttribute("IsArrangement") then bag[#bag + 1] = t end
    end
    if #bag == 0 then return 0, "tidak ada rangkaian di inventory" end

    -- ============================================================
    -- REM GLOBAL - menggantikan "cap penuh" untuk penolakan tak terbukti
    -- ============================================================
    -- INI PERBAIKAN RANCANGAN, bukan tambalan lagi. Dua keluhan yang
    -- bergantian muncul - "spam display full" dan "rak kosong didiamkan" -
    -- lahir dari SATU kesalahan yang sama: penolakan yang sebabnya TIDAK
    -- diketahui saya jadikan VONIS atas rak itu, lalu raknya dikunci.
    --
    -- Akibatnya bolak-balik:
    --   kunci lama  -> rak yang sebenarnya lowong ikut mati -> DIEM
    --   kunci pendek/tidak ada -> ditembaki tiap 0,6 detik -> SPAM
    --
    -- Yang benar: penolakan tak terbukti itu BUKAN informasi tentang RAK,
    -- melainkan tentang KEADAAN SESAAT (tangan belum memegang rangkaian,
    -- RateLimiter, plot belum direplikasi). Jadi yang direm SELURUH
    -- fungsinya sebentar - bukan raknya. Begitu remnya lepas, SEMUA rak
    -- dicoba lagi termasuk yang kosong, jadi mustahil ada rak yang
    -- terlantar.
    if _stockWarn.rem and os.clock() < _stockWarn.rem then
        return 0, "jeda " .. math.ceil(_stockWarn.rem - os.clock()) ..
                  " dtk sesudah penolakan yang sebabnya belum terbukti" ..
                  " (bukan vonis rak penuh - semua rak dicoba lagi" ..
                  " begitu jeda ini lewat)"
    end

    -- ============================================================
    -- INI SEBAB "RAK KOSONG TAPI TIDAK DIISI"
    -- ============================================================
    -- Server menentukan boleh/tidaknya dari tool yang SEDANG DIPEGANG --
    -- lihat _getEquippedArrangement di atas: dia menyisir Character,
    -- bukan Backpack. Humanoid:EquipTool memindahkan tool di CLIENT
    -- SEKETIKA, tapi server baru tahu setelah replikasi (~1 ping).
    --
    -- Versi lama memanggil StockArrangement di FRAME YANG SAMA dengan
    -- equip, jadi saat permintaan itu tiba server masih melihat tangan
    -- KOSONG -> ditolak. Dan penolakannya tidak dicatat sama sekali,
    -- makanya kelihatan seperti script diam saja.
    --
    -- Di mode TURBO ini kena SETIAP tool (bi selalu maju), jadi tidak ada
    -- satupun rangkaian yang masuk walau raknya jelas-jelas lowong.
    --
    -- Perbaikannya: equip, TUNGGU tool benar-benar pindah ke Character,
    -- lalu beri satu jeda pendek supaya equip-nya sempat sampai ke server.
    -- Ongkosnya cuma sekali per tool, bukan per percobaan.
    --
    -- SEKARANG CUMA ALIAS. Isinya sudah pindah ke global pegangTool() dan
    -- rakIsi() supaya tidak ada tiga salinan yang bisa saling menyimpang -
    -- alasan lengkapnya di komentar dua fungsi itu. Nama lokalnya dibiarkan
    -- supaya seluruh jalur lama di bawah tidak perlu disentuh sama sekali.
    local arrStock, holdTool = rakIsi, pegangTool

    -- Ambil tool berikutnya dari hasil sapuan tadi. Tool yang sudah
    -- terpakai hilang dari game (Parent jadi nil), jadi cukup dilewati.
    local bi = 1
    local function nextTool()
        while bag[bi] do
            local t = bag[bi]
            if t.Parent and holdTool(t) then return t end
            bi = bi + 1
        end
        return nil
    end

    -- (2) Rak lowong SAJA, diurut dari yang paling banyak ruangnya.
    --
    -- ISI RAK RANGKAIAN TIDAK PAKAI ATRIBUT "Stock_*".
    -- Ini penyebab bug "Arrangement Display (0 stocked)" tapi server tetap
    -- balas "Display is full". displayStock() menjumlahkan atribut Stock_*;
    -- itu benar untuk rak BUNGA, tapi rak rangkaian menyimpan isinya sebagai
    -- ANAK folder "_Arrangements". Jadi displayStock() selalu balik 0 ->
    -- SEMUA rak rangkaian terlihat kosong, termasuk yang penuh -> script
    -- menembak rak penuh dan server menolak berulang-ulang.
    --
    -- Sumber yang benar, disalin dari controller game sendiri
    -- (SPSTELITI baris 1133-1141):
    --     local _Arrangements = p1.Instance:FindFirstChild("_Arrangements")
    --     if _Arrangements then return #_Arrangements:GetChildren() end
    --
    -- BALIKAN KE-2 = APAKAH ANGKANYA BENAR-BENAR TERBACA. Ini yang
    -- membedakan "rak ini isi 0" dari "saya tidak tahu isinya". Dua-duanya
    -- dulu jatuh jadi angka 0 yang sama, dan dari situ lahir keputusan
    -- salah: rak yang isinya tidak terbaca ikut dicap PENUH begitu server
    -- menolak sekali - padahal penolakannya bisa karena hal lain.
    -- ============================================================
    -- JALUR CEPAT: SATU PANGGILAN MENGISI SATU RAK SAMPAI PENUH
    -- ============================================================
    -- INI JAWABAN "kok sekarang lambat". Dan penyebabnya bukan cuma
    -- setelan - saya memang melewatkan sebuah remote.
    --
    -- Dump V3 punya remote yang TIDAK ADA di catatan saya sebelumnya:
    --     FlowerDisplayService.RF.BulkStockArrangement(rak)
    -- (ReplicatedStorageV3 baris 22041-22046, RemoteFunction pertama di
    -- folder RF milik FlowerDisplayService)
    --
    -- Itu tombol "Stock All" milik game sendiri. Call-site aslinya ada di
    -- komponen rak, StarterPlayerScriptsV3 baris 1277-1282:
    --     v5 = function()
    --         local _, _2 = v1:BulkStockArrangement(p1.Instance)
    --         p1:_updateState()
    --     end
    --     v2, v3, v4 = "bulk:" .. v7, "Stock All", Color3.fromRGB(...)
    --
    -- Bedanya besar sekali. Jalur lama: SATU panggilan per rangkaian,
    -- masing-masing menunggu Sell Delay (bawaan 0,6 dtk). Isi 12 rangkaian
    -- = 12 panggilan = ~7 detik PER RAK. Jalur ini: SATU panggilan per
    -- rak, server yang mengisi sebanyak yang muat.
    --
    -- DAN INI MENGHAPUS SELURUH URUSAN "UKUR KAPASITAS DARI PENOLAKAN".
    -- Kapasitas rak rangkaian memang tidak ada di client (sudah saya cari
    -- lagi di V3: maxArrangements / arrangementCapacity / MaxStock = NOL
    -- hasil). Tapi sekarang tidak perlu ditebak sama sekali - server
    -- mengisi sampai mentok, lalu kita BACA isinya. Angka yang terbaca itu
    -- kapasitasnya, bukan dugaan.
    --
    -- Karena itu jalur ini juga TIDAK peduli sakelar TURBO: dia memakai
    -- invokeRF langsung supaya isinya bisa diukur, dan toh cuma satu
    -- panggilan per rak.
    if getRemote("FlowerDisplayService", "RF", "BulkStockArrangement") then
        -- ============================================================
        -- SATU PENGISI PADA SATU WAKTU
        -- ============================================================
        -- Sejak ada PEMICU INSTAN (lihat AUTO.pantauObjek), DUA jalur bisa
        -- mengisi rak pada saat yang sama - dan dua-duanya MENGGANTI tool
        -- di tangan. Kalau bertabrakan: panggilan bulk milik jalur A
        -- terkirim sementara tangan sudah direbut jalur B, lalu kenaikan
        -- yang terukur dikaitkan ke rak yang SALAH - dan rak lowong bisa
        -- dicap PENUH selama 45 detik gara-gara itu.
        --
        -- Yang dilewati di sini tidak hilang: sapuan berkala bangun lagi
        -- tiap Sell Delay, dan pemicu instan punya percobaan ulangnya
        -- sendiri.
        if _stockWarn.rakSibuk then
            return 0, "pengisian rak lain sedang jalan - dilewati, sapuan" ..
                      " berikutnya yang menangkapnya"
        end
        _stockWarn.rakSibuk = true

        local masuk, lewat, nolak, pesanAkhir = 0, 0, 0, nil

        -- Dibungkus pcall supaya kuncinya PASTI dilepas. Tanpa itu, satu
        -- error di tengah jalan mengunci seluruh pengisian rak sampai hub
        -- di-execute ulang - dan penyebabnya mustahil ditebak dari layar.
        local ok, err = pcall(function()
            for _, disp in ipairs(displays) do
                -- MURAH untuk rak yang dilewati: cuma FindFirstChild +
                -- GetChildren. Versi lama memanggil allTools() DULU untuk
                -- TIAP rak - satu penyisiran penuh Character + Backpack per
                -- rak, jadi 81 rak = 81 penyisiran tiap 0,6 detik walau
                -- delapan puluh di antaranya langsung dilewati.
                local isi0 = rakIsi(disp)
                local pasti = _stockWarn.penuh[disp.Name]
                local ing = _stockWarn.inst[disp]

                if pasti and isi0 >= pasti then
                    lewat = lewat + 1
                elseif ing and isi0 >= ing.isi and (os.clock() - ing.t) < 45 then
                    lewat = lewat + 1
                else
                    local n, why = isiRakSekali(disp)
                    masuk = masuk + n
                    if n == 0 and why then
                        if why == "tidak ada rangkaian di inventory" then
                            break          -- tas habis, rak sisanya percuma
                        elseif why ~= "PENUH" then
                            nolak = nolak + 1
                            pesanAkhir = why
                        end
                    end
                end
            end
        end)

        _stockWarn.rakSibuk = nil
        if not ok then
            return masuk, "gagal di tengah jalan: " .. tostring(err)
        end

        if masuk > 0 then return masuk end
        -- PENOLAKAN TAK TERJELASKAN DULUAN, bukan "penuh". Ini aturan yang
        -- sama dengan jalur lama di bawah (lihat `buta`), dan alasannya
        -- sama: "penuh" itu keadaan SEHAT yang tidak menuntut apa pun
        -- darimu, sementara penolakan yang sebabnya tidak terbaca justru
        -- satu-satunya yang perlu kamu tindak. Melaporkan "penuh" padahal
        -- yang terjadi penolakan tak terbukti = menyembunyikan masalah di
        -- balik kalimat yang terdengar wajar.
        if nolak > 0 then
            return 0, "BulkStockArrangement tidak menambah apa pun dan isi rak" ..
                      " tidak terbaca (" .. tostring(pesanAkhir) .. ")"
        end
        if lewat > 0 then
            return 0, lewat .. " dari " .. #displays .. " rak sudah PENUH dan" ..
                      " dilewati tanpa ditembak - pasang rak baru, atau tunggu" ..
                      " ada yang terjual"
        end
        return 0, "semua " .. #displays .. " rak rangkaian penuh"
    end

    -- ============================================================
    -- ATRIBUT "Max" TIDAK BOLEH DIPAKAI SEBAGAI BATAS RAK RANGKAIAN
    -- ============================================================
    -- Terukur di game: Tall Bouquet Shelf ber-Max=8 NYATANYA memuat 12
    -- rangkaian. "Max" itu kapasitas BUNGA, bukan rangkaian - memakainya
    -- sebagai batas membuat SEMUA rak berhitung penuh dan tidak ada
    -- satupun rangkaian yang masuk (81 rak, nol terisi).
    --
    -- Penggantinya: BUKTI NYATA, dan DIKUNCI PER NAMA MODEL - tiap jenis
    -- rak daya tampungnya beda. Satu angka untuk semua bikin rak kecil
    -- dikira sebesar rak terbesar, lalu ditembaki padahal sudah penuh.
    local racks = {}
    for _, disp in ipairs(displays) do
        local isi, baca = arrStock(disp)
        local model = disp.Name
        if isi > (_stockWarn.cap[model] or 0) then _stockWarn.cap[model] = isi end
        racks[#racks + 1] = { d = disp, isi = isi, m = model, baca = baca }
    end
    -- paling SEDIKIT isinya didahulukan
    table.sort(racks, function(a, b) return a.isi < b.isi end)

    -- `buta` = penolakan yang TIDAK bisa dibuktikan sebagai "raknya penuh"
    -- (isi rak tidak terbaca DAN pesannya tidak menyebut penuh). Dihitung
    -- terpisah supaya laporannya jujur: itu keadaan yang beda dari rak
    -- yang memang sudah penuh, dan tindakanmu juga beda.
    local n, lastErr, tolakBeruntun, lewat, buta = 0, nil, 0, 0, 0

    for _, entry in ipairs(racks) do
        if n >= #bag then return n end
        -- Rak sudah urut dari yang paling lowong. Kalau beberapa rak
        -- berturut-turut menolak, sisanya hampir pasti penuh juga --
        -- ini yang menjaga 81 rak tidak ditembak satu per satu sia-sia.
        if tolakBeruntun >= 5 then break end

        -- ============================================================
        -- KAPASITAS TERUKUR DIPAKAI DI KEDUA MODE - INI SEBAB "DISPLAY
        -- FULL" BERULANG-ULANG
        -- ============================================================
        -- Barisnya dulu:
        --     room = state.turbo and (batas - isi) or #bag
        -- Jadi di mode NORMAL angka yang sudah terukur DIABAIKAN TOTAL.
        -- Rak yang jelas-jelas penuh tetap ditembak, tetap ditolak, dan
        -- tetap mencatat "Rak penuh" - tiap putaran, selamanya. Ukurannya
        -- sudah benar; yang salah cuma tidak dipakai.
        --
        -- Kapasitas rak rangkaian TIDAK ADA di client (lihat catatan
        -- _stockWarn), jadi tiga keadaan yang berbeda butuh tiga aturan:
        -- ============================================================
        -- RAK INI SENDIRI SUDAH BILANG PENUH? LEWATI, JANGAN DITEMBAK
        -- ============================================================
        -- Ini yang menutup "spam taro ke rak". Dua ingatan yang berbeda,
        -- dan dua-duanya perlu:
        --
        --   _stockWarn.penuh[model] = KAPASITAS jenis rak itu (mis. 12)
        --   _stockWarn.inst[rak]    = RAK INI sudah menolak saat berisi N
        --
        -- Yang pertama saja TIDAK CUKUP, karena dia masih butuh isi rak
        -- yang benar untuk menghitung sisanya. Isi itu dibaca dari folder
        -- _Arrangements - dan kalau folder itu tidak terbaca, arrStock
        -- balik 0, rak penuh terlihat KOSONG, lalu ditembaki tiap sapuan.
        --
        -- INGATANNYA KEDALUWARSA SENDIRI dari dua arah, pola yang sama
        -- dengan siram (slotSudah):
        --   isi TURUN  -> ada yang terjual, langsung dicoba lagi DETIK ITU
        --   45 detik    -> dicoba sekali lagi walau isinya tidak terbaca
        -- Jadi tidak ada rak yang terkunci selamanya, dan ongkos terburuk
        -- kalau isinya memang tidak bisa dibaca cuma SATU tembakan per rak
        -- per 45 detik - bukan per sapuan.
        -- CUMA rak yang TERBUKTI penuh yang punya catatan di sini.
        -- Penolakan tak terbukti TIDAK lagi mengunci rak sama sekali -
        -- dia merem seluruh fungsi sebentar (lihat REM GLOBAL di atas).
        -- Itu yang menjamin rak kosong tidak pernah terlantar.
        local ing = _stockWarn.inst[entry.d]
        if ing and entry.isi >= ing.isi and (os.clock() - ing.t) < 45 then
            lewat = lewat + 1
            continue
        end

        local pasti = _stockWarn.penuh[entry.m]
        local room
        if pasti then
            -- SUDAH TERBUKTI dari penolakan server -> berhenti TEPAT di
            -- angka itu. Nol tembakan sia-sia, nol pesan penuh.
            room = math.max(pasti - entry.isi, 0)
            if room == 0 then lewat = lewat + 1 end
        elseif state.turbo then
            -- Balasan server tidak terbaca, jadi pakai batas bawah (isi
            -- terbanyak yang pernah masuk) + SATU tembakan percobaan.
            -- Tanpa percobaan itu dia macet permanen: semua rak sama
            -- penuhnya -> cap = isi -> room 0 -> tidak ada penolakan ->
            -- kapasitas tidak pernah terukur -> cap tidak pernah naik.
            room = math.max((_stockWarn.cap[entry.m] or 0) - entry.isi, 0)
            if room == 0 then room = 1 end
        else
            -- BELUM terukur dan balasan TERBACA: biarkan SERVER yang
            -- mengukur. Penolakan pertama itu memang pengukurannya, dan
            -- ongkosnya satu per JENIS rak - bukan per rak, bukan per
            -- putaran. Sesudah itu cabang pertama yang jalan.
            room = #bag
        end

        local masuk = 0
        while masuk < room and n < #bag do
            local tool = nextTool()
            if not tool then
                return n, (n == 0) and "rangkaian tidak bisa dipegang" or nil
            end
            -- PESANNYA IKUT DITANGKAP (nilai KETIGA). Ini yang kemarin
            -- terlewat, dan akibatnya besar: `res` cuma boolean `false`,
            -- jadi pencocok kata "penuh" selalu gagal dan satu-satunya
            -- dasar yang tersisa adalah isi rak - yang justru sering
            -- TIDAK terbaca. Server sendiri mengirim "Display is full";
            -- kalimat itu bukti yang tidak butuh isi rak sama sekali.
            local ok, res, pesan = callRF("FlowerDisplayService", "StockArrangement", entry.d)
            if ok and res ~= false then
                n = n + 1
                masuk = masuk + 1
                tolakBeruntun = 0
                -- Rak ini TERBUKTI masih menerima, jadi catatan "penuh"
                -- miliknya dibuang. Tanpa ini, catatan basi (mis. dari
                -- sebelum pelanggan membeli isinya) tetap membuatnya
                -- dilewati selama 45 detik padahal sudah lowong.
                _stockWarn.inst[entry.d] = nil
                -- Ada yang MASUK, jadi keadaan sesaat yang tadi bermasalah
                -- sudah beres - remnya dibuang, bukan ditunggu habis.
                _stockWarn.rem = nil
                stats.stocked = stats.stocked + 1
                addLog("Stock arrangement -> " .. entry.d.Name ..
                       "  (isi awal " .. entry.isi .. ")", "SELL")
                -- Mode TURBO tidak menunggu balasan server, jadi Parent tool
                -- belum tentu sudah nil di frame ini -> majukan manual supaya
                -- tidak menembakkan tool yang sama dua kali.
                if state.turbo then bi = bi + 1 end
            else
                -- Rak ini penuh menurut SERVER. Rangkaiannya MASIH di
                -- tangan (bi sengaja tidak dimajukan), jadi langsung
                -- dicoba ke rak berikutnya tanpa ada yang terbuang.
                --
                -- INI PENGUKURAN KAPASITAS YANG PALING TEPAT. Rak yang
                -- menolak sementara isinya (entry.isi + masuk) berarti
                -- kapasitasnya PERSIS segitu - bukan tebakan, bukan "isi
                -- terbanyak yang pernah dilihat".
                local isiSaatTolak = entry.isi + masuk
                -- Pesan server didahulukan; `res` cuma boolean, tidak
                -- memberi tahu apa-apa di log.
                lastErr = tostring(pesan or res)

                -- ============================================================
                -- PENOLAKAN BELUM TENTU BERARTI "PENUH" - ini bug saya kemarin
                -- ============================================================
                -- Versi kemarin mencap rak PENUH dari penolakan APA PUN, lalu
                -- menguncinya 45 detik. Kalau penolakannya ternyata lahir dari
                -- sebab lain - tangan belum memegang rangkaian saat permintaan
                -- tiba, RateLimiter, plot belum selesai direplikasi - maka
                -- SEMUA rak ditolak, SEMUA dikunci, dan fitur yang tadinya
                -- jalan jadi diam total sambil melapor "semua rak penuh".
                -- Itu dua kesalahan sekaligus: berhenti bekerja, DAN
                -- menyebut alasan yang tidak pernah dibuktikan.
                --
                -- Sekarang cap PENUH cuma dipasang kalau ADA DASARNYA:
                --   isi rak TERBACA dari _Arrangements  (angkanya nyata), ATAU
                --   pesan server memang menyebut penuh / tidak ada tempat
                -- Kalau dua-duanya tidak ada, penolakannya dicatat sebagai
                -- BUTA: rak berikutnya tetap dicoba, dan rak ini TIDAK
                -- dikunci - jadi hiccup sesaat tidak lagi mematikan fitur.
                -- SYARAT `isiSaatTolak > 0` ITU WAJIB, dan ini yang kemarin
                -- terlewat: rak KOSONG yang ditolak jelas BUKAN ditolak
                -- karena penuh. Versi kemarin cuma memeriksa `entry.baca`,
                -- jadi rak berisi 0 yang folder-nya kebetulan terbaca ikut
                -- dicap PENUH - lalu dikunci 45 detik. Itu persis "rak
                -- kosong kok didiamkan".
                local yakinPenuh = _stockWarn.katakanPenuh(pesan or res)
                                   or (entry.baca and isiSaatTolak > 0)

                if yakinPenuh then
                    -- INI PENGUKURAN KAPASITAS YANG PALING TEPAT, dan cuma
                    -- sah kalau isinya memang terbaca. Rak yang menolak saat
                    -- berisi K berarti kapasitasnya PERSIS K.
                    local lama = _stockWarn.penuh[entry.m]
                    if entry.baca and isiSaatTolak > 0
                       and (lama == nil or isiSaatTolak < lama) then
                        _stockWarn.penuh[entry.m] = isiSaatTolak
                        addLog("KAPASITAS TERUKUR: " .. entry.m .. " = " ..
                               isiSaatTolak .. " rangkaian (server menolak di angka ini)", "SELL")
                    end
                    -- Ditandai per OBJEK rak. Sapuan berikutnya melewatinya
                    -- tanpa satu tembakan pun, sampai isinya TURUN (ada yang
                    -- terjual) atau 45 detik lewat. Inilah yang menghentikan
                    -- "spam taro ke rak".
                    _stockWarn.inst[entry.d] = { isi = isiSaatTolak, t = os.clock() }
                    addLog("Rak penuh: " .. entry.d.Name .. " (isi " .. isiSaatTolak ..
                           ") -> " .. lastErr, "SELL")
                else
                    -- TIDAK TERBUKTI PENUH -> RAKNYA TIDAK DISENTUH SAMA
                    -- SEKALI. Yang direm seluruh fungsinya, 4 detik.
                    --
                    -- Kenapa begitu: penolakan macam ini bukan informasi
                    -- tentang RAK, melainkan tentang KEADAAN SESAAT
                    -- (tangan belum memegang rangkaian saat permintaan
                    -- tiba, RateLimiter, plot belum direplikasi). Kalau
                    -- keadaannya yang salah, menembaki 80 rak berikutnya
                    -- tidak akan menolong - jadi sapuan dihentikan.
                    --
                    -- Ini yang memutus lingkaran "diem <-> spam": tidak
                    -- ada rak yang dicap apa pun, jadi tidak ada rak yang
                    -- bisa terlantar; dan karena seluruh fungsi direm,
                    -- pesan penolakannya paling banyak sekali per 4 detik
                    -- - bukan tiap 0,6 detik dikali jumlah rak.
                    buta = buta + 1
                    _stockWarn.rem = os.clock() + 4
                    addLog("Rak MENOLAK tapi sebabnya TIDAK TERBUKTI penuh: " ..
                           entry.d.Name .. " (isi " .. isiSaatTolak ..
                           ", pesan '" .. lastErr .. "') - RAKNYA TIDAK dicap" ..
                           " apa pun; seluruh sapuan dijeda 4 detik", "SELL")
                    -- Hentikan sapuan lewat penjaga yang sudah ada di atas
                    -- (tolakBeruntun >= 5), supaya tidak perlu nama baru.
                    tolakBeruntun = 5
                end

                tolakBeruntun = tolakBeruntun + 1
                break
            end
            task.wait(turboDelay(config.sellDelay))
        end
    end

    if n == 0 then
        -- Alasannya DIBEDAKAN, karena tindakanmu beda. "dilewati" berarti
        -- hub memang sudah tahu rak itu penuh dan TIDAK menembaknya sama
        -- sekali - itu keadaan sehat, bukan kegagalan.
        -- BUTA DULUAN, karena ini satu-satunya keadaan yang butuh
        -- tindakanmu dan paling gampang disalahartikan sebagai "rak
        -- penuh". Menyebutnya penuh padahal tidak terbukti itu persis
        -- kesalahan yang bikin fitur ini kelihatan rusak kemarin.
        if buta > 0 then
            return 0, "ditolak TAPI sebabnya tidak terbukti penuh (pesan: " ..
                      tostring(lastErr) .. "). TIDAK ADA rak yang dicap apa" ..
                      " pun - yang dijeda seluruh sapuan, 4 detik. Sesudah" ..
                      " itu SEMUA rak dicoba lagi, termasuk yang kosong." ..
                      " Kalau terus begini: matikan TURBO sebentar supaya" ..
                      " pesan asli server terbaca di tab Output."
        end
        if lewat > 0 and not lastErr then
            return 0, lewat .. " dari " .. #displays ..
                      " rak sudah PENUH dan dilewati tanpa ditembak" ..
                      " - pasang rak baru, atau tunggu ada yang terjual"
        end
        return 0, lastErr and ("semua rak menolak - " .. lastErr)
                           or ("semua " .. #displays .. " rak rangkaian penuh")
    end
    return n
end

-- ============================================================
-- COMBO: RANGKAI MASSAL LANGSUNG KE RAK (sekali tekan)
-- ============================================================
-- Satu tekan = satu siklus penuh, tanpa perlu menyalakan dua sakelar:
--   1. WADAH TERBAIK yang levelnya sudah kebuka. Yang dipakai
--      biggestContainer() = maxFlowers TERBANYAK, bukan priceAdd
--      tertinggi. Alasannya terukur: harga = priceAdd WADAH + priceBase
--      TIAP BUNGA, jadi yang menaikkan uang adalah BANYAKNYA bunga.
--   2. bunga diisi sampai KAPASITAS PENUH wadah itu, didahulukan yang
--      priceBase-nya tertinggi (dua-duanya sudah ada di doCraftOnce)
--   3. FinishBatchArranging(payload, N) - SATU panggilan untuk N buket,
--      persis alur game: resep di-reserve sekali lalu minta N
--   4. hasilnya LANGSUNG didorong ke rak, diulang sampai bunga habis
--      atau raknya penuh
--
-- TURBO DIPERLAKUKAN BEDA DI DUA TAHAP, dan ini bukan detail kecil:
--   tahap CRAFT  -> turbo NYALA. Yang dipangkas cuma jeda antar
--                   ReserveFlower; balasannya tetap dibaca (invokeRF
--                   langsung), jadi tidak ada yang hilang - cuma cepat.
--   tahap KE RAK -> NYALA kalau kapasitas TIAP jenis rak sudah terukur,
--                   MATI kalau masih ada yang belum. Kapasitas rak
--                   rangkaian cuma bisa diukur dari PENOLAKAN server, dan
--                   di turbo penolakan itu tidak terbaca - di situlah
--                   "display full" berulang lahir. Tapi sesudah angkanya
--                   PASTI, balasan server tidak dibutuhkan lagi, jadi
--                   tidak ada alasan memperlambatnya.
-- Sakelar TURBO-mu DIKEMBALIKAN persis seperti semula di akhir - termasuk
-- kalau ada error di tengah jalan.
--
-- BERAPA YANG BENAR-BENAR JADI itu DIHITUNG dari inventory, bukan
-- diasumsikan dari angka batch. Jadi kalau server memberi kurang dari
-- yang diminta, laporannya jujur - bukan "25 buket" fiktif.
--
-- SENGAJA global, seperti addLog & habisSupply: dipanggil dari kartu
-- do...end di tab Craft, dan global tidak memakan register sama sekali.
function comboCraftRak(batch, running)
    -- SATU SIKLUS SAJA PADA SATU WAKTU, dan ini bukan kehati-hatian
    -- berlebihan: craft itu SESI di server (StartArranging ->
    -- ReserveFlower... -> Finish). Dua pemanggil yang membuka sesi di
    -- meja yang SAMA akan saling mengambil bunga reserve satu sama lain,
    -- dan hasilnya rangkaian yang GAGAL JADI - bukan cuma lambat.
    if _stockWarn.comboSibuk then
        return 0, 0, "siklus sebelumnya masih jalan"
    end

    local wadah, muat = biggestContainer()
    if not wadah then return 0, 0, "Assets.Arrangements tidak terbaca" end

    batch = math.max(1, math.floor(tonumber(batch) or 25))

    local function nRangkai()
        local n = 0
        for _, t in ipairs(allTools()) do
            if t:GetAttribute("IsArrangement") then n = n + 1 end
        end
        return n
    end

    local was = state.turbo
    local jadi, masuk, alasan = 0, 0, nil
    _stockWarn.comboSibuk = true

    local ok, err = pcall(function()
        -- Batas 8 putaran: satu tekan tidak boleh menahan thread
        -- selamanya. Kalau bunga masih banyak, tekan lagi.
        for _ = 1, 8 do
            if running and not running() then break end

            -- ============================================================
            -- JANGAN CRAFT LEBIH BANYAK DARIPADA SISA SLOT TAS
            -- ============================================================
            -- Kalau tas cuma sisa 5 slot dan kita minta 25, bunga untuk 20
            -- buket HANGUS - server sudah memotong bahannya tapi barangnya
            -- tidak bisa masuk. Itu kerugian paling mahal di fitur ini.
            --
            -- Batas slot tas TIDAK ADA di client (BackpackService 0 RF /
            -- 0 RE, dan maxBackpack / backpackSize / carryLimit nol hasil
            -- di seluruh dump). Jadi angkanya DIUKUR, pola yang sama
            -- dengan kapasitas rak rangkaian: kalau yang jadi lebih
            -- SEDIKIT daripada yang diminta, jumlah slot SAAT ITU adalah
            -- batasnya - persis, bukan tebakan.
            --
            -- Selama belum terukur, batchnya DIKECILKAN jadi percobaan
            -- (`PROBE`). Jadi kerugian paling parah = satu probe, bukan
            -- satu batch 25. Sesudah terukur sekali, langsung penuh 25 -
            -- dan angkanya ikut tersimpan ke file.
            local dipakai = #allTools()
            local minta = batch
            if _stockWarn.tas then
                minta = math.min(batch, math.max(_stockWarn.tas - dipakai, 0))
                if minta <= 0 then
                    alasan = "tas PENUH (" .. dipakai .. "/" .. _stockWarn.tas ..
                             " slot) - dorong isinya ke rak dulu"
                    break
                end
            else
                minta = math.min(batch, 5)   -- PROBE: rugi paling banter 5
            end

            local sebelum = nRangkai()
            state.turbo = true
            local cok, cerr = doCraftOnce(minta, wadah)
            state.turbo = false
            if not cok then alasan = tostring(cerr); break end

            local dapat = math.max(nRangkai() - sebelum, 0)
            jadi = jadi + dapat

            -- KURANG DARI YANG DIMINTA = tas mentok di angka ini.
            if dapat < minta then
                local ukur = #allTools()
                if _stockWarn.tas == nil or ukur < _stockWarn.tas then
                    _stockWarn.tas = ukur
                    addLog("TERUKUR: batas slot TAS = " .. ukur ..
                           " (minta " .. minta .. " buket, cuma " .. dapat ..
                           " yang masuk). Mulai sekarang batch dipotong" ..
                           " otomatis supaya bahan tidak terbuang.", "CRAFT")
                end
            end

            -- ============================================================
            -- KE RAK: INSTAN KALAU KAPASITASNYA SUDAH TERUKUR
            -- ============================================================
            -- Versi pertama memaksa turbo MATI di seluruh tahap ini, dan
            -- ITULAH yang bikin "ke rak tidak instan lagi". Alasannya
            -- benar, tapi cuma berlaku SELAMA kapasitas rak belum
            -- terukur: pengukurannya memang dari PENOLAKAN server, dan di
            -- turbo penolakan itu tidak terbaca sama sekali.
            --
            -- Begitu SEMUA jenis rak yang terpasang punya angka PASTI di
            -- _stockWarn.penuh, balasan server tidak dibutuhkan lagi -
            -- doStockArrangementOnce berhenti tepat di angka itu sendiri
            -- (cabang `pasti` di sana). Jadi turbo aman, dan bedanya
            -- besar: ~0,09 dtk per buket dibanding ~0,68 dtk.
            --
            -- Jadi tahap ini MENGUKUR sekali dengan hati-hati, lalu
            -- instan selamanya - dan angka pastinya ikut tersimpan ke
            -- file, jadi execute berikutnya langsung instan.
            local semuaTerukur = true
            for _, d in ipairs(rakPlot("ArrangementDisplay")) do
                if not _stockWarn.penuh[d.Name] then
                    semuaTerukur = false
                    break
                end
            end
            state.turbo = semuaTerukur

            -- Satu batch bisa 25 buket sementara satu sapuan
            -- doStockArrangementOnce berhenti begitu 5 rak berturut-turut
            -- menolak - jadi sekali panggil tidak cukup.
            for _ = 1, 6 do
                local n = tonumber((doStockArrangementOnce())) or 0
                masuk = masuk + n
                if n == 0 then break end
            end
            state.turbo = false
        end
    end)

    state.turbo = was
    _stockWarn.comboSibuk = nil
    if not ok then return jadi, masuk, "gagal di tengah: " .. tostring(err) end
    if jadi == 0 and not alasan then
        alasan = "tidak ada rangkaian yang jadi - bunga di tas cukup untuk " ..
                 tostring(muat) .. " bunga per buket?"
    end
    return jadi, masuk, alasan
end

-- ---------- UPGRADE / STAFF ----------
local function doUpgradeOnce()
    local list = setList(sel.buyUpgrades)
    if #list == 0 then return 0 end
    local n = 0
    for _, up in ipairs(list) do
        if up == "Advertising" then
            invokeRF("UpgradeService", "Purchase", "Advertising")
        elseif up == "Craft Table" then
            invokeRF("EquipmentService", "UpgradeEquipment", "CraftTable")
        elseif up == "Decor Limit" then
            invokeRF("PlacementService", "PurchaseDecorLimit")
        elseif up == "Expansion" then
            -- DUA JEBAKAN (UpgradeUIController, SPSV2TELITI 12140-12363):
            --   * GetExpansionData itu tabel BIAYA, BUKAN level. Levelnya
            --     dari Replica Data.Upgrades[levelKey].
            --   * yang dikirim ke server level BERIKUTNYA: lvl + 1.
            -- Pemetaannya:  zone "Shop" -> "BuildingLevel"
            --               zone "Farm" -> "FarmLevel"
            local up2 = pdata("Upgrades", nil)
            local plot2 = getMyPlot()
            for _, z in ipairs({ { "Shop", "BuildingLevel" }, { "Farm", "FarmLevel" } }) do
                -- Replica dulu (itu yang dipakai game). Atribut plot cuma
                -- cadangan kalau replica belum terbaca.
                local lvl = tonumber(type(up2) == "table" and up2[z[2]])
                    or tonumber(plot2 and plot2:GetAttribute(z[2])) or 1
                local ok2, res, msg = invokeRF("PlacementService",
                    "PurchaseExpansion", z[1], lvl + 1)
                addLog("PurchaseExpansion('" .. z[1] .. "', " .. (lvl + 1) ..
                       ")  [sekarang " .. lvl .. "] -> " .. tostring(res) ..
                       " " .. tostring(msg), "EXTRA")
                task.wait(0.2)
            end
        end
        n = n + 1
        addLog("Upgrade: " .. up, "EXTRA")
        task.wait(config.shopDelay)
    end
    return n
end

-- ============================================================
-- HARGA UPGRADE PADA POSISI SEKARANG
-- ============================================================
-- Empat upgrade, EMPAT sumber harga yang berbeda - semuanya disalin dari
-- controller milik game (SPSV2TELITI), bukan ditebak:
--
--   Advertising -> Shared.UpgradeConfig.Advertising.cost(levelSekarang)
--                  (12262:  local v7 = v2.cost and v2.cost(v4))
--   Craft Table -> Shared.EquipmentConfig.GetUpgradeCostForEquipment(
--                     "CraftTable", levelSekarang)                (5788)
--   Expansion   -> PlacementService.GetExpansionData()[zone][lvl+1].cost
--                  (renderExpansionCard 12176-12187)
--   Decor Limit -> PlacementService.NextDecorLimitCost(), nilai KE-5 =
--                  harga GEMS. Upgrade ini memang tidak pakai cash, dan
--                  itu harus kelihatan supaya tidak dikira gratis.
--
-- LEVELNYA dari Replica Data.Upgrades - itu yang dipakai game sendiri
-- (12353-12368), BUKAN atribut plot. Untuk Expansion kuncinya
-- "BuildingLevel" (zone Shop) dan "FarmLevel" (zone Farm).
--
-- DI-CACHE 10 DETIK. Dropdown memanggil getItems DUA KALI tiap dibuka
-- (sekali untuk isinya, sekali untuk menghitung tingginya), dan isinya
-- tiga panggilan server - tanpa cache, satu kali buka = enam panggilan.
--
-- SENGAJA global: dipanggil dari kartu do...end di tab Shop, dan global
-- tidak memakan register sama sekali. Dua nama cache-nya hidup di dalam
-- do...end, jadi register-nya bebas begitu blok selesai.
do
    local cache, cacheAt = nil, 0

    local function modul(nama)
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local m = shared and shared:FindFirstChild(nama)
        if not m then return nil end
        local ok, hasil = pcall(require, m)
        return ok and hasil or nil
    end

    function labelUpgrade()
        if cache and (os.clock() - cacheAt) < 10 then return cache end

        local up = pdata("Upgrades", nil)
        if type(up) ~= "table" then up = {} end

        local adv = "harga belum terbaca"
        do
            local cfg = modul("UpgradeConfig")
            local c = (type(cfg) == "table") and cfg.Advertising
            if type(c) == "table" then
                local lvl = tonumber(up.Advertising) or tonumber(c.default) or 0
                local maks = tonumber(c.maxLevel)
                if maks and lvl >= maks then
                    adv = "Lv " .. lvl .. " MAX"
                elseif type(c.cost) == "function" then
                    local ok, h = pcall(c.cost, lvl)
                    if ok and tonumber(h) then
                        adv = "Lv " .. lvl .. " -> " .. (lvl + 1) .. " = $" .. fmtNum(h)
                    end
                end
            end
        end

        local ct
        do
            local ok, lvl = invokeRF("EquipmentService", "GetEquipmentLevel", "CraftTable")
            lvl = (ok and tonumber(lvl)) or 1
            local eq = modul("EquipmentConfig")
            local h
            if type(eq) == "table" and type(eq.GetUpgradeCostForEquipment) == "function" then
                local ok2, v = pcall(eq.GetUpgradeCostForEquipment, "CraftTable", lvl)
                if ok2 then h = tonumber(v) end
            end
            -- Rumus cadangan yang sudah dipakai kartu STAFF & UPGRADE sejak
            -- lama. Dipakai HANYA kalau modulnya tidak terbaca.
            ct = "Lv " .. lvl .. " -> " .. (lvl + 1) .. " = $" ..
                 fmtNum(h or math.floor(50 * lvl ^ 1.4))
        end

        local exp = "harga belum terbaca"
        do
            local ok, data = invokeRF("PlacementService", "GetExpansionData")
            if ok and type(data) == "table" then
                local bagian = {}
                for _, z in ipairs({ { "Shop", "BuildingLevel" }, { "Farm", "FarmLevel" } }) do
                    local lvl = tonumber(up[z[2]]) or 1
                    local arr = data[z[1]]
                    local e = (type(arr) == "table") and arr[lvl + 1]
                    local h = (type(e) == "table") and tonumber(e.cost)
                    bagian[#bagian + 1] = z[1] .. " Lv" .. lvl ..
                        (h and (" -> " .. (lvl + 1) .. " $" .. fmtNum(h)) or " MAX")
                end
                exp = table.concat(bagian, " | ")
            end
        end

        local dec = "harga belum terbaca"
        do
            local ok, _, _, kini, lanjut, gem =
                invokeRF("PlacementService", "NextDecorLimitCost")
            if ok then
                dec = "batas " .. tostring(kini or "?") .. " -> " ..
                      tostring(lanjut or "?") .. " = " .. tostring(gem or "?") .. " GEM"
            end
        end

        -- Urutannya DIJAGA sama seperti sebelumnya, dan nama aslinya tetap
        -- di depan - stripLabel memotong mulai dari dua spasi + kurung,
        -- jadi yang tersimpan di sel.buyUpgrades tidak berubah sama sekali
        -- (konfigurasi lama tetap kebaca).
        cache = {
            "Advertising  [" .. adv .. "]",
            "Craft Table  [" .. ct .. "]",
            "Decor Limit  [" .. dec .. "]",
            "Expansion  [" .. exp .. "]",
        }
        cacheAt = os.clock()
        return cache
    end
end

-- GetApplicants() -> { [role] = { {level=1..5, name=..., Color=..., Hair=...}, ... } }
--   level = JUMLAH BINTANG pelamar (StaffController baris 383-391).
--   Biaya hire = ceil(baseCost + (level-1)^3 * costPerLevel)
--     Gardener: base 1500 / per 1500   |   Cashier: base 2000 / per 2000
--   -> bintang 5 Gardener = 1500 + 64*1500 = 97.500
--      bintang 4          = 1500 + 27*1500 = 42.000
-- Tabel biayanya dibuat DI DALAM fungsi supaya tidak memakan satu nama di
-- level teratas (batas Luau: 200 register lokal per fungsi, dan main chunk
-- ini SATU fungsi -- tiap nama di kolom nol hidup sampai baris terakhir).
--
-- CUMA ADA DUA ROLE: Gardener & Cashier (SPSV2TELITI 10023-10034).
-- "Florist" BUKAN role - itu nama model 3D yang dipakai Gardener
-- (10135). Mencentangnya membuat GetApplicants["Florist"] = nil dan
-- role itu dilewati diam-diam tanpa pesan apa pun.
local function hireCost(role, level)
    local c = ({
        Gardener = { base = 1500, per = 1500 },
        Cashier  = { base = 2000, per = 2000 },
    })[role]
    if not c or not level then return nil end
    return math.ceil(c.base + (level - 1) ^ 3 * c.per)
end

-- baca daftar pelamar + bintangnya
local function getApplicants()
    local ok, apps = invokeRF("StaffService", "GetApplicants")
    if ok and type(apps) == "table" then return apps end
    return nil
end

-- ============================================================
-- BINTANG MANA SAJA YANG BOLEH DIREKRUT
-- ============================================================
-- Dua mode, dan yang menentukan adalah centang di dropdown
-- "Bintang yang boleh di-hire":
--
--   KOSONG  -> pakai slider "Minimal Bintang" (>= n). Ini perilaku lama,
--              dan sifatnya "n ke atas": minimal 4 ikut mengambil 5.
--   TERISI  -> HANYA yang dicentang, titik. Centang bintang 5 saja =
--              bintang 4 DILEWATI, bukan diambil sebagai "lumayan".
--
-- Bedanya penting karena hire itu MEMBAYAR, dan biayanya meledak di
-- bintang tinggi: ceil(base + (lvl-1)^3 * per). Gardener bintang 4 =
-- $42.000, bintang 5 = $97.500. Jadi "cuma mau bintang 5" dan "minimal
-- bintang 4" itu dua keputusan uang yang sama sekali berbeda.
--
-- Kunci di set-nya berupa teks "⭐ 5 bintang" supaya daftar centangnya
-- enak dibaca; angkanya dicabut dari teks itu.
local function bintangBoleh(lvl)
    lvl = tonumber(lvl) or 0
    if setIsEmpty(sel.hireStars) then return lvl >= config.minStars end
    for k, on in pairs(sel.hireStars) do
        if on and tonumber(string.match(k, "%d+")) == lvl then return true end
    end
    return false
end

-- Keterangan singkat filter yang sedang berlaku, untuk pesan & laporan.
local function bintangTeks()
    if setIsEmpty(sel.hireStars) then
        return "minimal " .. config.minStars .. " (dari slider)"
    end
    local ang = {}
    for k, on in pairs(sel.hireStars) do
        if on then ang[#ang + 1] = tonumber(string.match(k, "%d+")) or 0 end
    end
    table.sort(ang)
    for i, a in ipairs(ang) do ang[i] = tostring(a) end
    return "hanya bintang " .. table.concat(ang, " / ")
end

-- Hire pelamar dengan BINTANG TERTINGGI di antara yang BOLEH.
--
-- CEK DULU, BARU BAYAR. Pelamar disaring lebih dulu; kalau tidak ada
-- satupun yang bintangnya dicentang, role itu DILEWATI - tidak ada yang
-- direkrut dan tidak ada uang keluar. Jadi "cek dulu ada bintang 5 atau
-- tidak; kalau tidak ada ya tidak usah dibeli" memang itu yang terjadi,
-- bukan efek samping.
--
-- Pelamar berganti sendiri seiring RefreshCountdown milik game - tidak ada
-- remote untuk memaksa refresh staff, jadi caranya memang menunggu.
local function doHireOnce()
    local roles = setList(sel.hireRoles)
    if #roles == 0 then return 0, "role belum dipilih" end

    local apps = getApplicants()
    if not apps then return 0, "GetApplicants gagal" end

    local n, adaRole = 0, false
    for _, role in ipairs(roles) do
        local list = apps[role]
        if type(list) == "table" then
            adaRole = true
            local bestIdx, bestLvl = nil, -1
            for idx, a in ipairs(list) do
                local lvl = tonumber(a and a.level) or 0
                if bintangBoleh(lvl) and lvl > bestLvl then
                    bestIdx, bestLvl = idx, lvl
                end
            end
            if bestIdx then
                invokeRF("StaffService", "HireApplicant", role, bestIdx)
                n = n + 1
                addLog("Hire " .. role .. " #" .. bestIdx .. " ⭐" .. bestLvl ..
                       " (~$" .. tostring(hireCost(role, bestLvl) or "?") .. ")", "STAFF")
                task.wait(config.shopDelay)
            else
                addLog("Skip " .. role .. ": tidak ada pelamar yang cocok - filter " ..
                       bintangTeks(), "STAFF")
            end
        end
    end
    if n == 0 then
        if not adaRole then return 0, "server tidak mengirim daftar pelamar untuk role itu" end
        return 0, "belum ada pelamar yang cocok - filter " .. bintangTeks()
    end
    return n
end

-- ---------- REST / WORK ----------
-- PENTING: label tombol REST/WORK di UI Staff bawaan game HANYA di-update di
-- dalam callback tombolnya sendiri (StaffController baris 535-548). Jadi kalau
-- kita panggil ToggleRestRole langsung, state di SERVER berubah tapi tulisan di
-- layar tidak ikut ganti -> kelihatan seperti "gagal". Di bawah ini kita
-- menyegarkan labelnya sendiri supaya sinkron.
--
--   GetRestingRoles() -> { Gardener = bool, Cashier = bool }
--     true  = role itu sedang ISTIRAHAT -> tombol menampilkan "WORK"  (hijau)
--     false = role itu sedang BEKERJA   -> tombol menampilkan "REST"  (biru)
local function getRestButton(role)
    -- nama holder-nya ditaruh DI DALAM fungsi: hemat satu register di level
    -- teratas, dan memang tidak dipakai di tempat lain
    local holderName = ({ Gardener = "CooksLabel", Cashier = "WaiterLabel" })[role]
    if not holderName then return nil end
    local pg   = LocalPlayer:FindFirstChild("PlayerGui")
    local sg   = pg and pg:FindFirstChild("ScreenGui")
    local menu = sg and sg:FindFirstChild("MainMenu")
    local main = menu and menu:FindFirstChild("Main")
    local cont = main and main:FindFirstChild("StaffContent")
    local hold = cont and cont:FindFirstChild(holderName)
    return hold and hold:FindFirstChild("Rest")
end

local function paintRestButton(role, isResting)
    local btn = getRestButton(role)
    if not btn then return false end
    local col = isResting and Color3.fromRGB(119, 188, 103) or Color3.fromRGB(67, 152, 255)
    local tl = btn:FindFirstChild("TextLabel")
    if tl then tl.Text = isResting and "WORK" or "REST" end
    pcall(function()
        btn.BackgroundColor3 = col
        local st = btn:FindFirstChild("UIStroke2")
        if st then st.Color = col end
    end)
    return true
end

local function getRestingRoles()
    local ok, roles = invokeRF("StaffService", "GetRestingRoles")
    if ok and type(roles) == "table" then return roles end
    return nil
end

-- baca status asli dari server lalu samakan tampilan tombol game
local function syncRestUI()
    local roles = getRestingRoles()
    if not roles then return nil end
    paintRestButton("Gardener", roles.Gardener == true)
    paintRestButton("Cashier",  roles.Cashier  == true)
    return roles
end

-- toggle + langsung samakan tampilannya. Balikan RF = status BARU.
local function toggleRest(role)
    local ok, nowResting = invokeRF("StaffService", "ToggleRestRole", role)
    if not ok then return false, tostring(nowResting) end
    paintRestButton(role, nowResting == true)
    addLog("ToggleRestRole(" .. role .. ") -> " ..
        (nowResting == true and "ISTIRAHAT" or "BEKERJA"), "STAFF")
    return true, nowResting == true
end

-- ============================================================
-- ============================================================
-- MESIN "AUTO"  (semua isi tab Auto lewat SATU nama: AUTO)
-- ============================================================
-- ============================================================
-- SIAPA PEMILIK PROMPTNYA menentukan apakah kita perlu mendekat.
--
--   DIBUAT CLIENT -> Triggered jalan di CLIENT, jadi TIDAK ADA
--   pemeriksaan jarak di server. Cukup naikkan MaxActivationDistance
--   lokal lalu tembak. (Terbukti: dibuat pakai Instance.new di
--   controller client sendiri.)
--       StaffPrompt  (Computer)    SlotPrompt_i (planter)
--       CraftSpot    (CraftTable)  StockPrompt  (rak)
--
--   DIBUAT SERVER -> Roblox memeriksa jarak memakai posisi karakter yang
--   TERAKHIR DIREPLIKASI ke server.
--       CheckoutPrompt (Register.ItemHolder)  jarak 10, tahan 0.5
--       CustomOrderPrompt (badan pembeli)     jarak 10, tahan 0.5
--
-- Panen / tanam / beli / craft / stok rak semuanya lewat RemoteFunction,
-- dan RemoteFunction TIDAK punya pemeriksaan jarak sama sekali - instan
-- dari mana saja. Yang MEMANG harus didekati cuma dua prompt server di
-- atas: teleport SEKALI, badan dipatok, seluruh antrean dilayani, baru
-- dikembalikan.
local AUTO = {}

do

local function building()
    local plot = getMyPlot()
    return plot and plot:FindFirstChild("Building")
end

-- Pencari prompt: cari wadahnya di Building, lalu prompt di dalamnya.
-- Argumen kedua FindFirstChild = rekursif; kedalamannya beda-beda
-- (Register.ItemHolder.CheckoutPrompt vs Computer.Attachment.StaffPrompt).
--
-- `nama` boleh menunjuk promptnya langsung ATAU wadahnya. CraftTable
-- memberi nama promptnya "ProximityPrompt" polos dan yang khas justru
-- nama Attachment induknya ("CraftSpot"), jadi kalau yang ketemu bukan
-- ProximityPrompt kita turun satu tingkat lagi.
local function ambilPrompt(hit)
    if not hit then return nil end
    if hit:IsA("ProximityPrompt") then return hit end
    return hit:FindFirstChildWhichIsA("ProximityPrompt", true)
end

-- EMPAT LAPIS pencarian, dari yang termurah ke yang paling menyeluruh -
-- nama & kedalaman wadah bisa beda antar plot dan antar update.
--
-- LAPIS 3 & 4 MAHAL: dua-duanya menyisir SELURUH plot, dan plot ini
-- punya 3080 ProximityPrompt saja. Jebakannya: CheckoutPrompt DIBUAT
-- SERVER PER BARANG, jadi saat meja kasir kosong prompt itu memang
-- TIDAK ADA - lapis 1 & 2 gagal lalu lapis 3+4 dua-duanya jalan. Justru
-- saat tidak ada kerjaan, biayanya paling mahal. Padahal pemanggilnya
-- label diagnosa (tiap 1,5 dtk) dan loop kasir (tiap 0,5 dtk).
--
-- Dua rem:
--   1. hasil yang ketemu DIINGAT selama objeknya masih hidup
--      (p.Parent ada). Prompt yang ada = nol pencarian.
--   2. penyisiran penuh dijatah sekali per 10 detik. Lapis 1 & 2 tetap
--      dicoba tiap kali karena cuma melihat ke dalam Building, jadi
--      CheckoutPrompt baru tetap ketemu SEKETIKA.
local ingatPrompt, ingatKapan = {}, {}

-- `murah` = BERHENTI SESUDAH LAPIS 2. Ini yang memperbaiki "pindah ke
-- tab Auto langsung nge-lag", dan sebabnya halus:
--
-- CheckoutPrompt DIBUAT SERVER PER BARANG. Waktu meja kasir kosong -
-- yaitu keadaan NORMAL - prompt itu memang TIDAK ADA. Jadi lapis 1 & 2
-- selalu gagal, lalu lapis 3 & 4 dua-duanya jalan:
--
--     plot:FindFirstChild(nama, true)   -> telusur REKURSIF seluruh plot
--     plot:GetDescendants()             -> ALOKASI TABEL berisi SEMUA
--                                          keturunan plot, lalu diulang
--
-- Di kebun ribuan slot itu puluhan sampai ratusan ribu instance dalam
-- SATU frame. Jatah 10 detik memang membatasi seberapa sering, tapi
-- tidak membuat sekalinya jadi murah - dan itu tetap terasa sebagai
-- patahan.
--
-- Yang memanggilnya tiap 1,5 detik: LABEL DIAGNOSA di tab Auto. Cuma
-- kotak teks. Jadi tab Auto membayar penyisiran seluruh plot 3x per 10
-- detik untuk sesuatu yang tidak melakukan apa pun.
--
-- Sekarang label memakai `murah = true`: dia cuma melihat Building dan
-- ingatan. Yang benar-benar BEKERJA (checkout, buka komputer, buka
-- craft) tetap boleh menyisir dalam - di situ ongkosnya memang dibayar
-- untuk sesuatu.
local function cari(namaWadah, nama, aksi, murah)
    -- Hasil lama masih sah? Objek prompt yang sudah dihapus server
    -- Parent-nya jadi nil, jadi ini pemeriksaan yang tepat dan gratis.
    local lama = ingatPrompt[nama]
    if lama and lama.Parent then return lama end
    ingatPrompt[nama] = nil

    local b = building()
    local host = b and b:FindFirstChild(namaWadah)
    local hit = host and ambilPrompt(host:FindFirstChild(nama, true))
    if hit then ingatPrompt[nama] = hit; return hit end

    hit = b and ambilPrompt(b:FindFirstChild(nama, true))
    if hit then ingatPrompt[nama] = hit; return hit end

    -- Mulai dari sini MAHAL. Dijatah sekali per 10 detik, dan pemanggil
    -- yang cuma mau MELAPORKAN keadaan tidak boleh masuk sama sekali.
    if murah then return nil end
    if (os.clock() - (ingatKapan[nama] or -1e9)) < 10 then return nil end
    ingatKapan[nama] = os.clock()

    local plot = getMyPlot()
    hit = plot and ambilPrompt(plot:FindFirstChild(nama, true))
    if hit then ingatPrompt[nama] = hit; return hit end

    -- Lapis terakhir: cocokkan ActionText. Nama instance boleh berubah,
    -- tulisan yang muncul di layar jarang ikut berubah.
    if aksi and plot then
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.ActionText == aksi then
                ingatPrompt[nama] = d
                return d
            end
        end
    end
    return nil
end

-- `murah` diteruskan apa adanya. Yang mengirim true cuma label diagnosa
-- di tab Auto - alasan lengkapnya di komentar besar `cari` di atas.
function AUTO.promptKasir(murah) return cari("Register",   "CheckoutPrompt", "Checkout", murah) end
function AUTO.promptStaff(murah) return cari("Computer",   "StaffPrompt",    "Manage",   murah) end
function AUTO.promptCraft(murah) return cari("CraftTable", "CraftSpot",      "Arrange",  murah) end

-- Daftar prompt di plot berikut jalur lengkapnya. Dipakai tombol diagnosa.
--
-- WAJIB DIRINGKAS. Pengukuran nyata: plot ini punya 3080 ProximityPrompt
-- (tiap planter menyumbang 9 SlotPrompt, tiap rak satu StockPrompt).
-- Versi pertama mencetak semuanya satu per satu, dan karena addLog cuma
-- menyimpan 250 baris terakhir, justru baris yang PALING dicari
-- (Building.Register...CheckoutPrompt) yang terbuang duluan -- terkubur
-- ribuan baris SlotPrompt yang isinya sama persis.
--
-- Sekarang jalur yang identik digabung jadi satu baris + jumlahnya, dan
-- yang di Building didahulukan karena di situlah prompt yang kita cari.
function AUTO.daftarPrompt()
    local plot = getMyPlot()
    local out = {}
    if not plot then return out end

    local hitung, kunci = {}, {}
    for _, d in ipairs(plot:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local jalur, node = d.Name, d.Parent
            while node and node ~= plot do
                jalur = node.Name .. "." .. jalur
                node = node.Parent
            end
            local k = string.format("%s  [%s] hold=%s jarak=%s %s",
                jalur, tostring(d.ActionText), tostring(d.HoldDuration),
                tostring(d.MaxActivationDistance), d.Enabled and "AKTIF" or "mati")
            if hitung[k] == nil then kunci[#kunci + 1] = k; hitung[k] = 0 end
            hitung[k] = hitung[k] + 1
        end
    end

    -- Building duluan, sisanya menyusul, masing-masing urut abjad.
    table.sort(kunci, function(a, b)
        local ba = (string.sub(a, 1, 9) == "Building.") and 0 or 1
        local bb = (string.sub(b, 1, 9) == "Building.") and 0 or 1
        if ba ~= bb then return ba < bb end
        return a < b
    end)

    for _, k in ipairs(kunci) do
        out[#out + 1] = string.format("%4dx  %s", hitung[k], k)
    end
    return out
end

-- Berapa barang yang masih menunggu di meja kasir.
-- Dipakai sebagai BUKTI: kalau angkanya turun, checkout benar diproses.
local function antre()
    local b = building()
    local reg = b and b:FindFirstChild("Register")
    local f = reg and reg:FindFirstChild("_CounterItems", true)
    if f then return #f:GetChildren() end
    return -1   -- strukturnya tidak ketemu: pakai bukti lain
end

-- Posisi dunia sebuah prompt.
--
-- INI SEBAB "KADANG TIDAK MAU TELEPORT" di versi paling awal. Dulu isinya
-- cuma memeriksa Attachment dan BasePart, lalu menyerah (balik nil) kalau
-- induk langsungnya bukan salah satu itu. CheckoutPrompt kadang menempel
-- pada Model / Folder perantara -- begitu itu terjadi, posisinya tidak
-- ketemu, teleportnya batal diam-diam, dan checkout gagal tanpa pesan.
--
-- Sekarang dia MEMANJAT ke atas sampai ketemu sesuatu yang punya posisi:
-- Attachment -> BasePart -> Model (pakai GetPivot). Praktis tidak mungkin
-- gagal selama prompt-nya masih menempel di dalam plot.
local function posisi(p)
    local node = p and p.Parent
    while node do
        if node:IsA("Attachment") then return node.WorldPosition end
        if node:IsA("BasePart")   then return node.Position end
        if node:IsA("Model") then
            local ok, piv = pcall(function() return node:GetPivot().Position end)
            if ok and piv then return piv end
        end
        node = node.Parent
    end
    return nil
end

-- ============================================================
-- TUJUAN TELEPORT KASIR = MODEL REGISTER, BUKAN PROMPT-NYA
-- ============================================================
-- Diminta begitu ("pakai Teleport to Register aja"), dan memang lebih
-- masuk akal daripada memakai posisi promptnya:
--
--   CheckoutPrompt menempel di Register.ItemHolder - itu titik di dalam
--   / di atas MEJA, jadi tujuan yang dihitung dari situ gampang jatuh ke
--   dalam meja atau melayang di atasnya. Pivot Register sendiri titik
--   yang sudah TERBUKTI dipakai tombol "Teleport ke Register" di tab
--   Info, dan tombol itu tidak pernah bermasalah.
--
-- Yang TIDAK saya tiru dari tombol itu: dia menaruh badan di pivot + 4
-- stud KE ATAS, alias melayang di atas mesin kasir. Untuk sekali tekan
-- itu tidak masalah, tapi untuk checkout badan HARUS bertahan di tempat
-- selama server memproses - kalau melayang lalu jatuh, server melihat
-- kita menjauh dan menolaknya. Jadi titik ini diserahkan ke dekati(),
-- yang menaruh badan 4 stud DI SAMPING (sisi tempatmu berdiri tadi) lalu
-- MEMATOKNYA tiap frame. Tujuannya sama - Register - cuma tidak melayang.
local function titikRegister()
    local b = building()
    local reg = b and b:FindFirstChild("Register")
    if not reg then return nil end
    if reg:IsA("BasePart") then return reg.Position end
    local ok, piv = pcall(function() return reg:GetPivot().Position end)
    if ok and piv then return piv end
    return nil
end

-- ------------------------------------------------------------
-- TEMBAK PROMPT TANPA MENGGESER KARAKTER
-- ------------------------------------------------------------
-- Jalur utamanya InputHoldBegin/InputHoldEnd -- API Roblox biasa, BUKAN
-- fungsi executor. Ini PERSIS yang dipakai ProximityController milik
-- game sendiri, jadi untuk prompt milik client ini jalur resminya.
--
-- TIGA ATURAN WAJIB. Dilanggar = tembakan hilang tanpa error:
--   1. HARUS ADA JEDA antara InputHoldBegin dan InputHoldEnd. Engine
--      mengukur lama tahan; melepas di baris berikutnya = tahanan 0
--      detik, dan Roblox MEMBATALKANNYA.
--   2. MaxActivationDistance + RequiresLineOfSight HARUS dibuka dulu.
--      InputHoldBegin bukan pintu belakang - Roblox cuma menerima input
--      untuk prompt yang SEDANG dianggap "in range" di client.
--   3. Argumen kedua fireproximityprompt TIDAK SERAGAM antar executor:
--      ada yang mengartikan "lama tahan", ada yang "berapa kali". Pada
--      prompt ber-HoldDuration 0 itu berarti ditembak NOL KALI.
--
-- Karena (3) tidak bisa ditebak dari sini, lima cara dicoba satu per
-- satu dan yang menang DIINGAT. Buktinya dua lapis: PromptTriggered
-- DITAMBAH pemeriksaan domain (uang naik / antrean turun / ObjectText
-- berganti) - PromptTriggered sendirian terukur tidak selalu bunyi.
local trigAt = setmetatable({}, { __mode = "k" })
AUTO.adaTrigger = false   -- apakah PromptTriggered PERNAH bunyi di client ini
do
    local ok, PPS = pcall(function()
        return game:GetService("ProximityPromptService")
    end)
    if ok and PPS then
        track(PPS.PromptTriggered:Connect(function(p)
            trigAt[p] = os.clock()
            AUTO.adaTrigger = true
        end))
    end
end

AUTO.cara     = nil               -- nomor cara yang TERBUKTI jalan
AUTO.caraNama = "belum diukur"
-- Apakah cara tembak itu PERNAH benar-benar berhasil di sesi ini.
-- Dipakai sebagai rem untuk jeda 30 detik di bawah: jeda itu hanya masuk
-- akal kalau memang belum pernah ada yang jalan. Kalau sudah pernah, satu
-- kali meleset itu cuma server telat - bukan alasan mematikan fitur 30
-- detik. Tanpa penjaga ini, satu miss di tengah antrean membuat SELURUH
-- checkout berikutnya balik `false` seketika selama 30 detik.
AUTO.pernahSukses = false
local gagalUkur, ukurLagi = 0, 0  -- pengaman supaya tidak mengukur terus-terusan

local NAMA_CARA = {
    "fireproximityprompt(p)",
    "fireproximityprompt(p, 1)",
    "fireproximityprompt(p, HoldDuration)",
    "InputHoldBegin + InputHoldEnd (langsung ke objek)",
    "teleport ke prompt + InputHoldBegin/End",
}

-- Cara 1-3 memakai fireproximityprompt, dan SEBAGIAN EXECUTOR
-- menjalankannya dengan MENIRU TEKANAN TOMBOL E - bukan menyentuh objek
-- prompt yang kita kirim. Roblox lalu mengarahkan E itu ke prompt yang
-- SEDANG DIA PILIH, dan itu bisa prompt lain (paling sering NPC Quest,
-- karena dia berdiri dekat pembeli).
--
-- Cara 4 & 5 memanggil p:InputHoldBegin() LANGSUNG pada objeknya, jadi
-- mustahil nyasar. Untuk prompt milik SERVER (kasir & pesanan) cuma dua
-- cara ini yang diizinkan - lebih baik gagal jujur daripada menekan E di
-- tempat yang salah.
local AMAN = { 5, 4 }
local AMAN_DEKAT = { 4 }

-- Semua yang dibuka buka() itu properti SISI CLIENT (server tidak pernah
-- melihat perubahannya) dan DIKEMBALIKAN persis sesudahnya, supaya
-- prompt milik game tidak tertinggal menyala dari seberang map.
--
-- MaxActivationDistance WAJIB dibuka - InputHoldBegin BUKAN pintu
-- belakang: Roblox cuma menerima input untuk prompt yang SEDANG dianggap
-- "in range" di client. Terukur di game: tanpa ini, keempat cara tembak
-- dijalankan dan PromptTriggered tidak bunyi sama sekali.
local asli = setmetatable({}, { __mode = "k" })

-- Exclusivity ikut dibuka. Bawaannya "OneGlobally": Roblox cuma
-- MENAMPILKAN satu prompt untuk seluruh layar, dan cuma yang itu yang
-- menerima InputHoldBegin. Dengan 3080 prompt di plot, sasaran kita
-- nyaris tidak pernah terpilih. AlwaysShow mengeluarkannya dari
-- perebutan itu.
--
-- HoldDuration IKUT DINOLKAN - ini yang bikin kasir instan. Lama tahan
-- dihitung di CLIENT, jadi HoldDuration = 0 memicu Triggered SEKETIKA
-- di InputHoldBegin. Server tidak ikut memeriksa lama tahan (cuma
-- jarak), jadi 30 barang selesai sekejap, bukan 30 x 0,5 = 15 detik.
local function buka(p)
    if asli[p] == nil then
        asli[p] = {
            d = p.MaxActivationDistance,
            l = p.RequiresLineOfSight,
            x = p.Exclusivity,
            h = p.HoldDuration,
        }
    end
    pcall(function()
        p.MaxActivationDistance = 5000
        p.RequiresLineOfSight = false
        p.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
        p.HoldDuration = 0
    end)
    -- WAJIB menunggu. Sistem ProximityPrompt Roblox menghitung ulang prompt
    -- mana yang "in range" pada siklus update berikutnya, BUKAN saat
    -- propertinya diubah. Menembak di baris yang sama = engine masih pakai
    -- keadaan lama (jarak 10, belum terpilih) -> tembakan hilang.
    task.wait()
    task.wait()
end

local function tutup(p)
    local a = asli[p]
    if not a then return end
    pcall(function()
        p.MaxActivationDistance = a.d
        p.RequiresLineOfSight = a.l
        p.Exclusivity = a.x
        p.HoldDuration = a.h
    end)
end

-- HoldDuration ASLI milik prompt, bukan yang sudah dinolkan buka().
-- Dipakai cara 3, yang argumen keduanya memang berarti "lama tahan" di
-- sebagian executor -- kalau diberi 0 dia menembak NOL KALI.
local function holdAsli(p)
    local a = asli[p]
    if a and a.h then return a.h end
    return p.HoldDuration
end

-- ============================================================
-- PINDAH KE DEPAN PROMPT LALU PATOK DI SITU
-- ============================================================
-- Dipakai cara 5 (satu tembakan) DAN AUTO.checkout (pindah SEKALI untuk
-- seluruh antrean - 30 barang tidak perlu 30 teleport bolak-balik).
--
-- TIGA ATURAN. Melanggar salah satu = badan jatuh sebelum tahanan
-- selesai, server melihat kita menjauh, Triggered ditolak:
--   1. tujuan diambil 4 stud dari prompt KE ARAH tempat kita berdiri
--      tadi - sisi itu hampir pasti ruang terbuka. (JANGAN pakai
--      posisi prompt + offset: prompt kasir menempel di meja, jadi
--      titiknya melayang / nyangkut di dalam meja.)
--   2. badan DIPATOK tiap frame -> mustahil jatuh / terdorong fisika
--   3. jeda 0,15 dtk sebelum menembak supaya posisi barunya sempat
--      direplikasi ke server
--
-- Balikan: `lepas(pulang)`.
--   lepas(true)  -> lepas patok DAN pulangkan badan
--   lepas(false) -> lepas patok, badan DIBIARKAN di depan prompt
-- Gagal = jangan dipulangkan, supaya percobaan berikutnya sudah dekat
-- dan tidak ada celah "kita menjauh persis saat server memproses".
-- `paksaTitik` = titik tujuan yang DIPAKSA pemanggil, menggantikan posisi
-- prompt. Dipakai kasir supaya tujuannya model Register (lihat
-- titikRegister di atas). Kalau nil, perilakunya persis seperti semula.
local function dekati(p, paksaTitik)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local pos  = paksaTitik or posisi(p)
    if not (hrp and pos) then return nil end

    local balik = hrp.CFrame
    local arah = balik.Position - pos
    arah = Vector3.new(arah.X, 0, arah.Z)
    arah = (arah.Magnitude > 0.1) and arah.Unit or Vector3.new(0, 0, 1)
    local tujuan = CFrame.new(pos + arah * 4 + Vector3.new(0, 1, 0), pos)

    local patok = RunService.Heartbeat:Connect(function()
        if hrp.Parent then
            hrp.CFrame = tujuan
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    -- JARING PENGAMAN. Kalau thread yang memanggil ini MATI di tengah
    -- task.wait (GUI ditutup, script dihentikan executor), fungsi pelepas
    -- di bawah tidak pernah dipanggil dan badanmu terpatok di depan kasir
    -- SELAMANYA sampai rejoin. Ini memutusnya tanpa syarat setelah 10
    -- detik; aman walau pelepasnya sudah jalan duluan.
    -- SENGAJA tidak pakai track(): itu menumpuk satu entri tiap checkout
    -- dan tidak pernah dibersihkan sampai GUI ditutup.
    task.delay(20, function() pcall(function() patok:Disconnect() end) end)

    task.wait(0.15)   -- posisi baru sampai ke server dulu

    return function(pulang)
        pcall(function() patok:Disconnect() end)
        if pulang and hrp.Parent then
            hrp.CFrame = balik
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
end
AUTO.dekati = dekati
-- SENGAJA global juga, persis seperti klikPrompt: blok AUTO LAYANI PEMBELI
-- letaknya DI ATAS blok ini, jadi dia tidak bisa melihat nama lokal `AUTO`.
-- Sebagai global dia sudah ada saat runtime, dan global tidak memakan
-- register sama sekali (batas Luau 200 per fungsi).
dekatiPrompt = dekati

-- Tahan-lalu-lepas. Karena buka() sudah menolkan HoldDuration, ini INSTAN:
-- engine memicu Triggered begitu InputHoldBegin dipanggil, tidak ada
-- penghitung 0,5 detik yang harus ditunggu. Jeda 1 frame di bawah cuma
-- supaya urutan Begin -> End tidak menumpuk di frame yang sama.
local function tahan(p)
    return pcall(function()
        p:InputHoldBegin()
        if p.HoldDuration > 0 then
            task.wait(math.max(0.06, p.HoldDuration))
        else
            task.wait()
        end
        p:InputHoldEnd()
    end)
end

-- Tunggu sampai `cek()` benar, paling lama `batas` detik. Diperiksa TIAP
-- FRAME, jadi begitu buktinya muncul dia langsung lanjut - tidak menunggu
-- sisa waktunya. Balikan: true kalau terbukti.
local function tunggu(cek, batas)
    if cek() then return true end
    local mulai = os.clock()
    while (os.clock() - mulai) < batas do
        task.wait()
        if cek() then return true end
    end
    return false
end

local function tembak(i, p)
    if i <= 3 then
        if typeof(fireproximityprompt) ~= "function" then return false end
        if i == 1 then return pcall(fireproximityprompt, p) end
        if i == 2 then return pcall(fireproximityprompt, p, 1) end
        -- HoldDuration ASLI, bukan yang sudah dinolkan buka(): di sebagian
        -- executor argumen kedua berarti "berapa kali ditembak", dan 0 =
        -- tidak ditembak sama sekali.
        local h = holdAsli(p)
        if not h or h <= 0 then return false end
        return pcall(fireproximityprompt, p, h)
    end

    -- Jalur RESMI Roblox, sama persis dengan ProximityController milik game.
    if i == 4 then return tahan(p) end

    -- CARA 5: pindah ke depan prompt dulu, tembak, lalu balik.
    -- Badan cuma dipulangkan kalau tembakannya SUKSES. Gagal = tetap di
    -- situ, supaya percobaan berikutnya tidak perlu teleport lagi.
    if not config.dekatiDulu then return false end
    local lepas = dekati(p)
    if not lepas then return false end
    local ok = tahan(p)
    task.wait(0.05)   -- beri server sedikit waktu memproses Triggered
    lepas(ok)
    return ok
end

-- SENGAJA global (tanpa `local`), seperti addLog: dipanggil juga dari blok
-- AUTO LAYANI PEMBELI yang letaknya DI ATAS blok ini, dan global tidak
-- memakan register sama sekali (batas Luau 200 per fungsi).
--
-- `bukti` = fungsi opsional yang balik true kalau aksinya SUDAH TERBUKTI
-- jalan (mis. uang bertambah). Ini penting: PromptTriggered ternyata tidak
-- selalu bunyi di client, jadi kalau cuma mengandalkan dia, cara yang
-- SEBENARNYA berhasil pun dianggap gagal.
-- `urut` = urutan cara yang dicoba. Kasir mengirim {5,1,2,3,4} karena
-- SUDAH TERBUKTI (dan dikonfirmasi dari perilaku hub lain) bahwa checkout
-- memang menuntut badan dekat -- jadi buang-buang waktu kalau cara 1-4
-- dicoba duluan tiap kali. Prompt milik client tetap pakai urutan biasa.
function klikPrompt(p, bukti, urut)
    if not (p and p.Parent) then return false end

    -- 0,30 dtk, BUKAN 0,12. Tanpa `bukti`, satu-satunya tanda adalah
    -- PromptTriggered - dan itu dipicu sistem ProximityPrompt pada siklus
    -- update BERIKUTNYA, bukan seketika. Di plot ini (3080 prompt) frame
    -- bisa panjang, dan `sabar` cuma bisa memeriksa sekali per frame:
    -- pada 20 fps, 0,12 detik itu CUMA dua kali pemeriksaan. Terlalu
    -- sempit, dan yang meleset dilaporkan "gagal" padahal berhasil.
    local jendela = bukti and 0.5 or 0.30
    local function kena(t0)
        if bukti and bukti() then return true end
        local t = trigAt[p]
        return t ~= nil and t >= t0
    end
    local function sabar(t0)
        local mulai = os.clock()
        while (os.clock() - mulai) < jendela do
            task.wait()
            if kena(t0) then return true end
        end
        return kena(t0)
    end

    buka(p)

    -- Cara yang sudah terbukti dipakai langsung, tanpa mengukur ulang --
    -- TAPI cuma kalau dia termasuk dalam `urut` yang diminta pemanggil.
    --
    -- INI YANG BIKIN "E"-NYA MENDARAT DI NPC QUEST. Tombol Komputer /
    -- Craft boleh memakai cara 1-3 (fireproximityprompt), dan begitu
    -- salah satunya menang dia DIINGAT untuk seluruh sesi. Lalu kasir &
    -- pesanan ikut memakai cara yang sama padahal mereka MELARANGNYA,
    -- dan cara 1-3 itulah yang bisa nyasar ke prompt lain.
    local bolehIngat = (AUTO.cara ~= nil)
    if bolehIngat and urut then
        bolehIngat = false
        for _, i in ipairs(urut) do
            if i == AUTO.cara then bolehIngat = true end
        end
    end

    if bolehIngat then
        local t0 = os.clock()
        tembak(AUTO.cara, p)
        local ok = sabar(t0)
        if ok then AUTO.pernahSukses = true; tutup(p); return true end
        -- Di client yang PromptTriggered-nya memang tidak pernah bunyi DAN
        -- tanpa bukti lain, kita tidak bisa membedakan "gagal" dari "tidak
        -- kelihatan". Jangan buang cara yang sudah terbukti di tempat lain.
        if not AUTO.adaTrigger and not bukti then tutup(p); return true end

        -- SEKALI LAGI sebelum menyerah. Ini yang memperbaiki "3x instan,
        -- yang ke-4 meleset": penyebab paling sering bukan cara tembaknya
        -- salah, tapi balasan server telat melewati jendela tunggu. Menembak
        -- ulang jauh lebih murah daripada mengukur ulang lima cara.
        -- `urut ~= nil` WAJIB ADA DI SINI. Dulu barisnya
        --     if #(urut or {}) <= 1 then
        -- dan itu SALAH: kalau pemanggil tidak mengirim `urut` sama
        -- sekali (tombol BUKA GUI KOMPUTER & BUKA FRAME CRAFT), `urut or
        -- {}` jadi tabel kosong, panjangnya 0, dan 0 <= 1 itu BENAR -
        -- jadi dua tombol itu ikut masuk cabang "cuma satu cara yang
        -- diizinkan" lalu MENYERAH sesudah dua tembakan, padahal
        -- semestinya boleh mengukur ulang kelima cara.
        --
        -- Itu persis gejala "kadang tidak kebuka, tapi kalau di-spam
        -- bisa": tiap klik cuma dua tembakan dengan cara yang sama, dan
        -- yang berhasil itu kebetulan salah satunya masuk jendela tunggu.
        if urut ~= nil and #urut <= 1 then
            local t1 = os.clock()
            tembak(AUTO.cara, p)
            if sabar(t1) then AUTO.pernahSukses = true; tutup(p); return true end
            -- Cuma satu cara yang diizinkan (kasir & pesanan). Tidak ada
            -- yang bisa diukur ulang, jadi JANGAN buang cara yang sudah
            -- terbukti - laporkan gagal apa adanya.
            tutup(p)
            return false
        end

        tutup(p)
        AUTO.cara, AUTO.caraNama = nil, "diukur ulang"
        buka(p)
    end

    if os.clock() < ukurLagi then tutup(p); return false end

    for _, i in ipairs(urut or { 1, 2, 3, 4, 5 }) do
        local t0 = os.clock()
        if tembak(i, p) then
            if sabar(t0) then
                AUTO.cara, AUTO.caraNama = i, NAMA_CARA[i]
                AUTO.pernahSukses = true
                gagalUkur = 0
                tutup(p)
                addLog("Cara tembak yang TERBUKTI jalan: " .. NAMA_CARA[i], "AUTO")
                notify("Cara tembak ketemu: " .. NAMA_CARA[i], THEME.On)
                return true
            end
        end
    end
    tutup(p)

    -- Semua cara gagal. Jangan mengulang tiap 0,5 detik - itu bikin banyak
    -- tembakan per putaran dan tetap sia-sia. Diam 30 detik dulu.
    --
    -- TAPI cuma kalau memang BELUM PERNAH ada yang berhasil. Kalau sudah
    -- pernah, ini bukan "fiturnya tidak jalan" melainkan sekali meleset,
    -- dan memasang jeda 30 detik di situ justru mematikan auto kasir
    -- padahal barangnya menumpuk. Itu persis gejala "yang ke-4 dan ke-5
    -- tidak instan lagi".
    gagalUkur = gagalUkur + 1
    if not AUTO.pernahSukses then
        ukurLagi = os.clock() + 30
        AUTO.caraNama = "GAGAL semua (" .. gagalUkur .. "x) - lihat catatan di kartu ini"
    end
    addLog("Lima cara tembak dicoba, tidak satupun terbukti. " ..
           "fireproximityprompt=" ..
           (typeof(fireproximityprompt) == "function" and "ADA" or "TIDAK ADA") ..
           ", PromptTriggered pernah bunyi=" .. tostring(AUTO.adaTrigger), "AUTO")
    return false
end

AUTO.klik = klikPrompt

-- Bersihkan hasil pengukuran DAN jeda 30 detiknya. Tanpa membersihkan
-- ukurLagi, tombol "Ukur ulang" tidak berefek apa-apa selama jeda itu.
--
-- `pernahSukses` IKUT dibersihkan. Tombolnya berjanji "diukur ulang dari
-- nol", jadi ingatan bahwa dulu pernah berhasil pun harus dibuang -
-- kalau tidak, laporan "GAGAL semua" tidak akan pernah muncul lagi dan
-- kartu STATUS ikut menampilkan keterangan basi.
function AUTO.resetUkur()
    AUTO.cara, AUTO.caraNama = nil, "belum diukur"
    AUTO.jauh = nil
    AUTO.pernahSukses = false
    gagalUkur, ukurLagi = 0, 0
    -- Ingatan letak prompt ikut dibuang, DAN jatah 10 detiknya. Tombolnya
    -- berjanji "diukur ulang dari nol", jadi pencarian penuh harus boleh
    -- jalan detik itu juga - bukan menunggu sisa jatah.
    ingatPrompt, ingatKapan = {}, {}
end

-- ------------------------------------------------------------
-- KASIR
-- ------------------------------------------------------------
-- AUTO.jauh:  nil = belum diukur, true = boleh dari jauh,
--             false = server memeriksa jarak, perlu lompatan mikro
AUTO.jauh = nil

-- Potret keadaan SEBELUM menembak, dipakai sebagai pembanding.
local function potret(p)
    return {
        cash  = angkaStat("Cash") or 0,
        antre = antre(),
        teks  = tostring(p.ObjectText),
    }
end

-- EMPAT tanda, cukup salah satu. Dulu cuma tiga, dan itu terlalu ketat:
-- kalau _CounterItems tidak ketemu (antre = -1) DAN masih ada barang
-- berikutnya di meja (prompt tetap Enabled), satu-satunya sisa bukti
-- adalah kenaikan Cash - padahal replica bisa telat / gagal terbaca.
-- Akibatnya checkout yang SUKSES dilaporkan gagal, lalu script lompat
-- ke kasir tanpa perlu. Tanda keempat (ObjectText berubah = barang di
-- meja berganti) menutup celah itu.
local function terbukti(p, b4)
    if (angkaStat("Cash") or 0) > b4.cash then return true end
    if b4.antre >= 0 and antre() < b4.antre then return true end
    if not (p.Parent and p.Enabled) then return true end
    if tostring(p.ObjectText) ~= b4.teks then return true end
    return false
end

-- Satu barang. Buktinya diserahkan ke klikPrompt supaya PENGUKURAN cara
-- tembak ikut memakai bukti nyata (uang naik / antrean turun / barang di
-- meja berganti), bukan cuma PromptTriggered yang ternyata tidak selalu
-- bunyi di client.
local function sekali(p, sudahDekat)
    local b4 = potret(p)
    -- Kalau badan SUDAH dipatok di depan kasir (lihat AUTO.checkout), cara 5
    -- tidak ada gunanya lagi - dia cuma akan teleport ke titik yang sama.
    -- Yang didahulukan cara 4: tahan-lepas biasa, dan itu sudah INSTAN
    -- karena HoldDuration-nya dinolkan di buka().
    --
    -- Kalau BELUM dekat, cara 5 yang didahulukan. Alasannya bukan tebakan:
    -- hub lain yang terbukti jalan pun teleport ke kasir dulu baru menekan
    -- E, dan di sini cara tanpa pindah memang selalu ditolak.
    --
    -- Cara 1-3 SENGAJA TIDAK ADA di sini - lihat catatan AMAN di atas.
    return AUTO.klik(p, function() return terbukti(p, b4) end,
                     sudahDekat and AMAN_DEKAT or AMAN)
end

-- Layani SELURUH antrean di meja kasir.
function AUTO.checkout()
    local p = AUTO.promptKasir()
    if not p then
        -- Pesan lama "Register belum terpasang?" MENYESATKAN. Terukur di
        -- game: jam 21:48 promptnya KETEMU, jam 22:05 hilang -- padahal
        -- Register-nya jelas tidak dibongkar. Sebabnya CheckoutPrompt itu
        -- dibuat server PER BARANG: begitu meja kasir kosong, promptnya
        -- ikut dihapus, bukan sekadar Enabled = false.
        --
        -- Jadi bedakan dua hal itu, kalau tidak kamu akan mengira scriptnya
        -- rusak padahal cuma belum ada pembeli yang membayar.
        local b = building()
        if b and b:FindFirstChild("Register") then
            return 0, "meja kasir masih KOSONG (prompt baru dibuat server saat ada barang)"
        end
        return 0, "Register tidak ketemu di Building - plot belum termuat?"
    end
    if not p.Enabled then return 0, "belum ada barang di meja kasir" end

    -- ============================================================
    -- TELEPORT SEKALI, LALU INSTAN BERKALI-KALI
    -- ============================================================
    -- Ini bentuk yang sama dengan hub lain yang terbukti jalan: pindah ke
    -- kasir, lalu tekan E berulang - BUKAN bolak-balik tiap barang.
    -- Dua hal yang membuatnya instan:
    --   * badan DIPATOK di depan kasir selama seluruh antrean dilayani,
    --     jadi server tidak pernah melihat kita menjauh di tengah jalan
    --   * HoldDuration dinolkan di buka(), jadi tiap tembakan memicu
    --     Triggered SEKETIKA - tidak ada tahanan 0,5 detik per barang
    -- 30 barang jadi hitungan detik, bukan 15 detik.
    --
    -- TUJUANNYA MODEL REGISTER, bukan posisi promptnya - sama dengan
    -- tombol "Teleport ke Register" di tab Info. Alasannya di
    -- titikRegister(). Kalau Register-nya tidak terbaca, dekati() jatuh
    -- sendiri ke posisi prompt seperti semula.
    local lepas = config.dekatiDulu and dekati(p, titikRegister()) or nil

    local n = 0
    local ok, err = pcall(function()
        -- BARANG PERTAMA lewat jalur pengukuran, supaya cara tembaknya
        -- terbukti dulu (dan kalau di server ini ternyata butuh cara lain,
        -- ketahuannya di sini).
        local awal = tostring(p.ObjectText)
        if not sekali(p, lepas ~= nil) then return end
        n = 1
        stats.checkout = stats.checkout + 1
        addLog("Checkout: " .. awal, "AUTO")

        -- ============================================================
        -- SISA ANTREAN: PROMPT DIBIARKAN TERBUKA
        -- ============================================================
        -- Ini yang memperbaiki "3x instan lalu meleset". Versi sebelumnya
        -- memanggil buka() + tutup() untuk SETIAP barang, dan buka() wajib
        -- menunggu 2 frame supaya sistem ProximityPrompt sempat menghitung
        -- ulang "in range". Jadi tiap barang membayar ongkos buka-tutup,
        -- dan di antara dua barang prompt-nya sempat KEMBALI ke jarak 10 /
        -- HoldDuration 0,5 - kalau barang berikutnya datang tepat di celah
        -- itu, tembakannya jatuh ke keadaan lama dan meleset.
        --
        -- Sekarang prompt dibuka SEKALI untuk seluruh antrean dan baru
        -- ditutup di akhir. Tidak ada celah, tidak ada ongkos 2 frame per
        -- barang.
        buka(p)
        for _ = 2, 30 do
            if not (p.Parent and p.Enabled) then break end
            local b4 = potret(p)
            local barang = tostring(p.ObjectText)
            tahan(p)
            -- 0,8 detik: cukup longgar untuk ping jelek, dan tetap keluar
            -- SEKETIKA begitu buktinya muncul.
            if not tunggu(function() return terbukti(p, b4) end, 0.8) then break end
            n = n + 1
            stats.checkout = stats.checkout + 1
            addLog("Checkout: " .. barang, "AUTO")
        end
        tutup(p)
    end)

    -- ATURAN POSISI: pulang HANYA kalau ada yang benar-benar berhasil.
    -- Kalau nol, badan DIBIARKAN berdiri di depan kasir - percobaan
    -- berikutnya jadi tidak perlu teleport lagi, dan tidak ada lagi celah
    -- "kita sudah menjauh saat server baru memproses".
    if lepas then lepas(n > 0) end

    if not ok then return n, "gagal di tengah: " .. tostring(err) end

    if n == 0 then
        return 0, "ditolak - badan sengaja DITINGGAL di kasir (cara=" ..
                  tostring(AUTO.caraNama) .. ")"
    end
    AUTO.jauh = (lepas == nil)
    return n
end

-- PEMICU INSTAN: begitu server menaruh barang di meja kasir, langsung
-- dilayani -- tidak menunggu putaran loop berikutnya.
local kasirConn, kasirBusy = nil, false

local function layaniSekarang()
    if kasirBusy then return end
    kasirBusy = true
    local ok, n, why = pcall(AUTO.checkout)
    kasirBusy = false
    if ok and n and n > 0 then
        notify("Kasir: " .. n .. " barang dilayani", THEME.On)
    elseif ok and why and why ~= "belum ada barang di meja kasir" then
        addLog("Kasir: " .. tostring(why), "AUTO")
    end
end
AUTO.layaniSekarang = layaniSekarang

function AUTO.pantau(on)
    if not on then
        if kasirConn then pcall(function() kasirConn:Disconnect() end); kasirConn = nil end
        return
    end
    -- Loop jaring pengaman memanggil ini tiap putaran. Kalau koneksinya
    -- masih hidup JANGAN dipasang ulang -- memutus lalu menyambung tiap
    -- 0,5 detik justru membuka celah kehilangan event.
    if kasirConn and kasirConn.Connected then return end
    if kasirConn then pcall(function() kasirConn:Disconnect() end); kasirConn = nil end

    local b = building()
    local reg = b and b:FindFirstChild("Register")
    local holder = reg and reg:FindFirstChild("_CounterItems", true)
    if holder then
        -- sinyal paling tepat: barang benar-benar ditaruh di meja
        kasirConn = holder.ChildAdded:Connect(function()
            if not state.autoKasir then return end
            task.wait(0.1)   -- beri server waktu mengisi ObjectText
            layaniSekarang()
        end)
    else
        local p = AUTO.promptKasir()
        if not p then return end
        kasirConn = p:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not state.autoKasir then return end
            if not p.Enabled then return end
            task.wait(0.1)
            layaniSekarang()
        end)
    end
    track(kasirConn)
end

-- ============================================================
-- PEMICU INSTAN: PEMBELI AMBIL DARI RAK -> RAK ITU LANGSUNG DIISI
-- ============================================================
-- SINYALNYA TERBUKTI, dan ini bukan tebakan: komponen ArrangementDisplay
-- milik GAME SENDIRI memakai persis dua sinyal ini (SPSv3 1204 & 1212):
--     _Arrangements.ChildAdded:Connect(f1)     -> _updateState()
--     _Arrangements.ChildRemoved:Connect(f2)   -> _updateState()
--
-- Jadi isi rak rangkaian memang ANAK folder "_Arrangements", dan begitu
-- pembeli mengambil satu, anaknya HILANG - itu detik yang kita tunggu.
--
-- FOLDERNYA BISA LAHIR BELAKANGAN, dan game pun menanganinya (1216-1222):
-- rak yang belum pernah diisi belum punya folder itu sama sekali. Jadi
-- ChildAdded milik RAK ikut dipantau, dan begitu "_Arrangements" muncul
-- barulah pendengarnya dipasang. Tanpa ini, rak yang baru dipasang tidak
-- akan pernah punya pemicu seumur sesi.
--
-- KENAPA INI BERGUNA padahal sapuan berkala sudah jalan tiap Sell Delay:
--   * cepat - ~0,25 dtk sesudah barang terjual, bukan menunggu giliran
--   * MURAH - yang disentuh CUMA rak yang berubah. Sapuan berkala harus
--     memeriksa semua rak; di plot 81 rak itu bedanya besar.
--
-- Yang TIDAK saya klaim: ini bukan pengganti sapuan berkala. Sapuan tetap
-- jalan sebagai jaring pengaman - kalau satu event meleset (rak baru,
-- koneksi putus, plot dimuat ulang), sapuan berikutnya tetap menangkapnya.
--
-- ============================================================
-- TIGA JENIS OBJEK, TIGA SINYAL YANG BERBEDA - dan itu bukan pilihan
-- gaya, itu memang bentuk datanya
-- ============================================================
--   ArrangementDisplay : isinya ANAK folder "_Arrangements"
--                        -> sinyalnya ChildRemoved  (SPSv3 1204/1212)
--   FlowerDisplay      : isinya ATRIBUT Stock_<nama>
--                        -> sinyalnya AttributeChanged  (SPSv3 974)
--   Planter            : isinya ATRIBUT Slot_<i>_Seed
--                        -> sinyalnya AttributeChanged  (SPSv3 591)
--
-- Dua yang terakhir memakai sinyal yang SAMA tapi tidak boleh diperlakukan
-- sama: AttributeChanged menyala untuk SETIAP atribut, dan planter punya
-- banyak atribut yang berdetak sendiri (Stage, Ready, PlantedAt). Kalau
-- tidak disaring, satu planter yang tanamannya sedang tumbuh membanjiri
-- pemicu ini terus-menerus. Untungnya AttributeChanged MENGIRIM NAMA
-- atributnya, jadi saringannya satu perbandingan teks:
--     planter -> cuma "Slot_<i>_Seed"   (berubah tepat saat ditanam
--                atau dipanen - persis kondisi kosong di SPSv3 550
--                dan di doPlantOnce baris 3159-3162)
--     rak bunga -> cuma "Stock_<nama>"  (persis yang dijumlah
--                  displayStock, baris 567-575)
--
-- YANG PERLU KAMU TAHU SOAL BATASNYA: ChildRemoved dan AttributeChanged
-- menyala untuk SEMUA sebab isi berkurang, bukan cuma "dibeli pembeli".
-- Kamu sendiri mengambil barang dari rak juga memicunya. Untuk tujuan kita
-- itu justru benar - yang kita mau "berkurang, isi lagi", bukan menebak
-- siapa yang mengambil. Hub TIDAK bisa membedakan keduanya dan saya tidak
-- akan menulis seolah-olah bisa.
--
-- GAME SENDIRI PUN TIDAK CUMA MENGANDALKAN EVENT: komponen Planter
-- memasang AttributeChanged (591) DAN loop `while ... task.wait(1)`
-- (SPSv3 598-603). Itu alasan paling kuat kenapa sapuan berkala di hub ini
-- tetap dipertahankan, bukan diganti.
local rakConn, rakTunda, rakUlang = {}, {}, false

-- Peredam GLOBAL, bukan per objek. Sengaja: doPlantOnce dan
-- doStockFlowerOnce itu mesin SE-KEBUN sekali jalan, jadi sepuluh planter
-- yang panen berbarengan tetap cukup dilayani SATU panggilan. (Rak
-- rangkaian beda - mesinnya per rak, jadi peredamnya per rak di rakTunda.)
PICU = { tanam = false, bunga = false }

-- Satu-satunya sumber kebenaran "pemicu perlu hidup atau tidak". Dipanggil
-- SESUDAH state diubah, oleh tiap sakelar yang terlibat. Tanpa ini tiap
-- sakelar harus mengingat sakelar lain mana yang juga memakai pemicu -
-- dan itu persis jenis kembaran yang dulu bikin dua tampilan beda isi.
function AUTO.picuPerlu()
    return state.aRak == true or state.aCombo == true
        or state.aTanam == true or state.autoStock == true
end

function AUTO.pantauObjek(on)
    for _, cn in ipairs(rakConn) do
        pcall(function() if cn.Connected then cn:Disconnect() end end)
    end
    rakConn = {}
    if not on then return end

    local plot = getMyPlot()
    if not plot then return end

    -- Satu rak, satu antrean. Pembeli bisa mengambil beberapa rangkaian
    -- beruntun, dan tiap pengambilan memicu ChildRemoved sendiri-sendiri -
    -- tanpa peredam ini satu pembelian bisa jadi lima pengisian.
    local function isiNanti(disp)
        if rakTunda[disp] then return end
        rakTunda[disp] = true
        task.delay(0.25, function()
            rakTunda[disp] = nil
            if not (state.aRak or state.aCombo) then return end
            if not (disp and disp.Parent) then return end
            -- Sapuan berkala sedang memegang tangan. Jangan berebut -
            -- alasan lengkapnya di kunci `rakSibuk`. Dilewati aman:
            -- sapuan itu sendiri akan mengisi rak ini.
            if _stockWarn.rakSibuk then return end

            -- Ada yang TERJUAL, jadi rak ini PASTI lowong sekarang.
            -- Cap "penuh" miliknya dibuang tanpa syarat - kalau tidak,
            -- catatan dari sebelum pembelian tetap membuatnya dilewati.
            _stockWarn.inst[disp] = nil

            _stockWarn.rakSibuk = true
            local ok, n, why = pcall(isiRakSekali, disp)
            _stockWarn.rakSibuk = nil

            if ok and (tonumber(n) or 0) > 0 then
                addLog("PEMBELI AMBIL -> " .. disp.Name .. " diisi ulang " ..
                       n .. " rangkaian (pemicu instan, bukan sapuan)", "SELL")
            elseif ok and why and why ~= "PENUH"
                   and why ~= "tidak ada rangkaian di inventory" then
                addLog("Isi ulang instan " .. disp.Name .. " gagal: " ..
                       tostring(why), "SELL")
            end
        end)
    end

    local function pasang(disp)
        local sudah = false
        local function watchFolder()
            if sudah then return end
            local f = disp:FindFirstChild("_Arrangements")
            if not f then return end
            sudah = true
            rakConn[#rakConn + 1] = f.ChildRemoved:Connect(function()
                isiNanti(disp)
            end)
        end
        watchFolder()
        -- Folder belum ada -> tunggu dia lahir. Persis SPSv3 1216-1222.
        rakConn[#rakConn + 1] = disp.ChildAdded:Connect(function(anak)
            if anak.Name == "_Arrangements" then watchFolder() end
        end)
    end

    if state.aRak or state.aCombo then
        for _, disp in ipairs(rakPlot("ArrangementDisplay")) do pasang(disp) end
    end

    -- ------------------------------------------------------------
    -- (2) PLANTER : slot jadi kosong -> tanam lagi
    -- ------------------------------------------------------------
    -- Perlakuan TURBO-nya ditiru dari `instan` di kartu MESIN INSTAN tab
    -- Auto, TIDAK dipanggil: fungsi itu local di dalam blok `do` milik tab
    -- Auto dan tidak kelihatan dari sini. Disalin seadanya, bukan
    -- disimpulkan. Kalau `instan` di sana diubah, ubah yang ini juga.
    local function sekebun(fn, apa)
        local was = state.turbo
        if config.autoTurbo then state.turbo = true end
        local ok, n = pcall(fn)
        state.turbo = was
        if not ok then
            addLog("Pemicu instan (" .. apa .. ") error: " .. tostring(n), "AUTO")
        elseif (tonumber(n) or 0) > 0 then
            addLog(apa .. " -> " .. n .. " (pemicu instan, bukan sapuan)", "AUTO")
        end
    end

    if state.aTanam then
        for _, p in ipairs(getMyPlanters()) do
            rakConn[#rakConn + 1] = p.AttributeChanged:Connect(function(nama)
                if not state.aTanam then return end
                -- Saringan nama: lihat blok komentar besar di atas fungsi.
                if string.sub(nama, 1, 5) ~= "Slot_" then return end
                if string.sub(nama, -5) ~= "_Seed" then return end
                if PICU.tanam then return end

                -- Baru dipanggil SESUDAH saringan nama lolos, jadi ongkos
                -- perulangan ini nyaris tidak pernah terbayar percuma.
                local slots = tonumber(p:GetAttribute("Slots")) or 1
                local kosong = false
                for i = 1, slots do
                    local s = p:GetAttribute("Slot_" .. i .. "_Seed")
                    if s == nil or s == "" then kosong = true; break end
                end
                if not kosong then return end

                -- Bendera ini DIPEGANG SAMPAI MESINNYA SELESAI, bukan cuma
                -- selama 0,3 detik jedanya. Bedanya besar: doPlantOnce bisa
                -- makan waktu beberapa detik, dan kalau bendera sudah lepas
                -- duluan, sapuan kedua berangkat saat yang pertama masih
                -- jalan - dua-duanya berebut tangan, persis penyakit yang
                -- sudah dibayar mahal di rak rangkaian (lihat rakSibuk).
                -- Sakelar berkalanya memegang bendera yang SAMA, jadi
                -- pemicu dan sapuan pun tidak bisa bertabrakan.
                PICU.tanam = true
                task.delay(0.3, function()
                    if state.aTanam and not setIsEmpty(sel.plantSeeds) then
                        sekebun(function() return doPlantOnce(true) end,
                                "SLOT KOSONG ditanami")
                    end
                    PICU.tanam = false
                end)
            end)
        end
    end

    -- ------------------------------------------------------------
    -- (3) RAK BUNGA : stok berkurang -> isi lagi
    -- ------------------------------------------------------------
    if state.autoStock then
        for _, disp in ipairs(rakPlot("FlowerDisplay")) do
            rakConn[#rakConn + 1] = disp.AttributeChanged:Connect(function(nama)
                if not state.autoStock then return end
                if string.sub(nama, 1, 6) ~= "Stock_" then return end
                if PICU.bunga then return end
                -- Cuma bertindak kalau rak ini memang masih punya ruang.
                -- Atribut Stock_* juga berubah saat rak DIISI, dan tanpa
                -- gerbang ini pengisian sendiri akan memicu dirinya lagi.
                if displayStock(disp) >= ((disp:GetAttribute("Max") or 8)) then
                    return
                end
                -- Dipegang sampai selesai - alasan lengkapnya di planter
                -- tepat di atas.
                PICU.bunga = true
                task.delay(0.3, function()
                    if state.autoStock then
                        sekebun(doStockFlowerOnce, "RAK BUNGA berkurang, diisi")
                    end
                    PICU.bunga = false
                end)
            end)
        end
    end

    -- RAK BARU yang kamu pasang saat main tidak punya pendengar apa pun.
    -- Daripada menebak jenisnya dari nama, seluruh pemasangan diulang -
    -- itu sekalian menyapu rak yang DIBONGKAR. Memasang rak jarang, jadi
    -- ongkosnya nol koma; peredamnya supaya pemasangan beruntun tidak
    -- memicu pembangunan ulang berkali-kali.
    local objects = plot:FindFirstChild("Objects")
    if objects then
        rakConn[#rakConn + 1] = objects.ChildAdded:Connect(function()
            if rakUlang then return end
            rakUlang = true
            task.delay(1.5, function()
                rakUlang = false
                if AUTO.picuPerlu() then AUTO.pantauObjek(true) end
            end)
        end)
    end

    addLog("Pemicu instan AKTIF - " .. #rakConn .. " pendengar (rak" ..
           " rangkaian: ChildRemoved, planter & rak bunga:" ..
           " AttributeChanged)", "SELL")
end

-- ------------------------------------------------------------
-- BUKA GUI lewat prompt milik CLIENT (dari jarak berapa pun)
-- ------------------------------------------------------------
-- CARA 5 SENGAJA TIDAK DIPAKAI di dua tombol ini. Cara 5 itu "teleport
-- ke prompt lalu tekan" - dan dua prompt ini milik CLIENT, tidak ada
-- server yang memeriksa jarak, jadi memindahkan badanmu murni mubazir.
-- Cara 4 (InputHoldBegin langsung ke objek) didahulukan karena dia
-- mustahil nyasar ke prompt lain; 1-3 disisakan sebagai cadangan kalau
-- di executor-mu cara 4 ternyata tidak memicu apa-apa.
--
-- Ini juga yang memutus warisan dari kasir: kasir bisa menetapkan
-- AUTO.cara = 5, dan dulu tombol ini ikut memakainya - jadi menekan
-- "BUKA GUI KOMPUTER" malah menyeret badanmu ke depan Computer.
local BUKA_URUT = { 4, 1, 2, 3 }

function AUTO.bukaKomputer()
    local p = AUTO.promptStaff()
    if not p then return false, "StaffPrompt tidak ketemu (Computer belum ada?)" end

    -- BUKTI NYATA, bukan cuma PromptTriggered: panel MainMenu milik game
    -- BERUBAH tampil/tidak. StaffPrompt memanggil ToggleUI, jadi yang
    -- membuktikan berhasil memang PERUBAHANNYA - bukan "sekarang
    -- terlihat" (kalau tadi memang sudah terbuka, itu bukan hasil kerja
    -- tombol ini).
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local sg = pg and pg:FindFirstChild("ScreenGui")
    local mm = sg and sg:FindFirstChild("MainMenu")
    local awal = mm and mm.Visible
    local bukti = mm and function() return mm.Visible ~= awal end or nil

    -- Hasilnya DIKEMBALIKAN apa adanya. Dulu fungsi ini selalu `true`,
    -- jadi toast bilang "GUI komputer terbuka" walau tidak ada yang
    -- terbuka - kebohongan yang membuat bug di atas sulit dikenali.
    local ok = AUTO.klik(p, bukti, BUKA_URUT)
    if ok then return true end
    return false, "prompt ditembak tapi panel tidak berubah - coba lagi" ..
                  " (cara tembak: " .. tostring(AUTO.caraNama) .. ")"
end

function AUTO.bukaCraft()
    local p = AUTO.promptCraft()
    if not p then return false, "prompt Arrange tidak ketemu (CraftTable belum ada?)" end
    -- Tanpa `bukti`: yang berubah waktu craft terbuka adalah KAMERA
    -- (enterCraftCamera), dan saya belum punya penanda yang terbukti
    -- untuk itu - jadi tidak saya karang. Sandarannya PromptTriggered,
    -- dengan jendela tunggu yang sudah dilebarkan.
    local ok = AUTO.klik(p, nil, BUKA_URUT)
    if ok then return true end
    return false, "prompt Arrange ditembak tapi Triggered tidak terbaca" ..
                  " (cara tembak: " .. tostring(AUTO.caraNama) .. ")"
end

end
-- ================== akhir mesin AUTO ==================

-- ============================================================
-- QUEST DIKUNCI NAMA, BUKAN ANGKA - jangan pernah menembak id 1..30
-- ============================================================
-- Dari QuestController (SPSV2TELITI 9457-9619):
--   * daftarnya SATU-SATUNYA dari RE.UpdateQuestUI(tabelQuest, ...)
--   * tabelnya dikunci NAMA quest (k), dan ClaimReward(k) juga pakai k
--   * tombol CLAIM hidup kalau: belum v.Claimed DAN semua v.Tasks
--     punya CurrentStep >= TotalStep
--
-- Bentuk satu entri (9480-9496):
--     [nama] = {
--         Tasks   = { { Task=, Object=, CurrentStep=, TotalStep= }, ... },
--         Reward  = { ikon, jumlah },
--         Claimed = bool,
--         Type    = ...   -- nil berarti boleh di-TrackQuest
--     }
local QUEST = { data = nil }

function QUEST.simpan(tabel)
    if type(tabel) ~= "table" then return 0 end
    QUEST.data = tabel
    local n = 0
    for _ in pairs(tabel) do n = n + 1 end
    return n
end

-- Salinan PERSIS gerbang klaim milik game. Sengaja ditiru apa adanya
-- supaya hub tidak pernah mengirim klaim yang pasti ditolak.
function QUEST.bisaKlaim(q)
    if type(q) ~= "table" or q.Claimed then return false end
    if type(q.Tasks) ~= "table" then return false end
    for _, t in ipairs(q.Tasks) do
        if (tonumber(t.CurrentStep) or 0) < (tonumber(t.TotalStep) or 1) then
            return false
        end
    end
    return true
end

function QUEST.daftar()
    local out = {}
    for nama, q in pairs(QUEST.data or {}) do
        local jadi, total = 0, 0
        for _, t in ipairs((type(q) == "table" and q.Tasks) or {}) do
            total = total + 1
            if (tonumber(t.CurrentStep) or 0) >= (tonumber(t.TotalStep) or 1) then
                jadi = jadi + 1
            end
        end
        out[#out + 1] = {
            nama  = tostring(nama),
            klaim = QUEST.bisaKlaim(q),
            sudah = (type(q) == "table" and q.Claimed) == true,
            jadi  = jadi,
            total = total,
        }
    end
    table.sort(out, function(a, b) return a.nama < b.nama end)
    return out
end

function QUEST.klaimSemua()
    if not QUEST.data then
        return 0, "daftar quest belum dikirim server - buka panel Quest di game sekali"
    end
    local n, siap = 0, 0
    for nama, q in pairs(QUEST.data) do
        if QUEST.bisaKlaim(q) then
            siap = siap + 1
            local ok, res, msg = invokeRF("QuestService", "ClaimReward", nama)
            if ok and res ~= false then
                n = n + 1
                addLog("Quest diklaim: " .. tostring(nama), "QUEST")
            else
                addLog("Quest DITOLAK: " .. tostring(nama) .. " -> " ..
                       tostring(msg or res), "QUEST")
            end
            task.wait(0.25)
        end
    end
    if n > 0 then return n end
    if siap == 0 then return 0, "belum ada quest yang semua tugasnya selesai" end
    return 0, "ada " .. siap .. " quest siap, tapi server menolak semuanya"
end

-- ============================================================
-- LISTENER SERVER -> log otomatis
-- ============================================================
do
    local pr = getRemote("ShopService", "RE", "PurchaseResult")
    if pr then
        track(pr.OnClientEvent:Connect(function(...)
            local parts = {}
            for _, v in ipairs({...}) do table.insert(parts, tostring(v)) end
            addLog("PurchaseResult: " .. table.concat(parts, " | "), "SHOP")
        end))
    end
    local sn = getRemote("NotificationService", "RE", "SendNotification")
    if sn then
        track(sn.OnClientEvent:Connect(function(msg)
            addLog("Notif: " .. tostring(msg), "GAME")
        end))
    end

    -- ============================================================
    -- INI MATA HUB KE STOK ASLI TOKO
    -- ============================================================
    -- Server mengirim angka stok yang SEBENARNYA lewat sini, dan cuma
    -- lewat sini. GetShopStock tidak memuatnya (lihat catatan panjang
    -- di TOKO). Tanpa pendengar ini, hub menembak barang berstok NOL
    -- dan ditolak diam-diam - persis keluhan "supply gak kebeli".
    --
    -- Bentuk datanya dari updateStock milik game (SPSV2TELITI 11079):
    --     { { Name = "Fertilizer", Stock = 3, Locked = false,
    --         RequiredStreak = nil }, ... }
    local sr = getRemote("ShopService", "RE", "StockRefreshed")
    if sr then
        track(sr.OnClientEvent:Connect(function(shopId, data)
            local n = TOKO.simpan(shopId, data)
            if n > 0 then
                addLog("Stok " .. tostring(shopId) .. " diperbarui server: " ..
                       n .. " barang", "SHOP")
            end
        end))
    end

    -- SetupShopUI dikirim saat panel toko dibangun. Isinya cuma
    -- { nama, harga } - sama miskinnya dengan GetShopStock - tapi
    -- kedatangannya menandakan kartu game SUDAH ada, jadi label
    -- StockCount-nya sudah bisa dibaca sebagai cadangan.
    local su = getRemote("ShopService", "RE", "SetupShopUI")
    if su then
        track(su.OnClientEvent:Connect(function(shopId, data)
            -- MUATANNYA DISIMPAN, bukan dibuang. Ini array yang index-nya
            -- terbukti diterima server (lihat TOKO.simpanDaftar).
            local n = TOKO.simpanDaftar(shopId, data)
            if n > 0 then
                addLog("Daftar " .. tostring(shopId) .. " diterima server: " ..
                       n .. " barang (index resmi)", "SHOP")
            end
            task.wait(0.2)
            TOKO.dariUI(shopId)
        end))
    end

    -- ============================================================
    -- INI MATA HUB KE DAFTAR QUEST
    -- ============================================================
    -- Satu-satunya sumber nama quest. Tanpa pendengar ini, Auto Quest
    -- cuma bisa menebak angka - dan angka memang selalu salah, karena
    -- kuncinya TEKS. Lihat catatan panjang di QUEST.
    local uq = getRemote("QuestService", "RE", "UpdateQuestUI")
    if uq then
        track(uq.OnClientEvent:Connect(function(data)
            local n = QUEST.simpan(data)
            if n > 0 then
                addLog("Daftar quest diterima server: " .. n .. " quest", "QUEST")
            end
        end))
    end
end

-- ============================================================
-- BUILD UI : TAB INFO
-- ============================================================
do
    local c = makeCard("📊 STATISTIK PEMAIN", THEME.Cyan, InfoBody)
    local infoLbl = makeInfo(c, "memuat data...")

    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(InfoBody) do task.wait(0.4) end
            local plot = getMyPlot()
            local nPlanter, total, ready, growing, empty, locked = farmSummary()
            infoLbl.Text = table.concat({
                "Build    : " .. HUB_BUILD .. "   <- cocokkan dengan laporan",
                "Player   : " .. LocalPlayer.Name ..
                    "   (Lv " .. tostring(angkaStat("Level") or "?") .. ")",
                -- SUMBERNYA IKUT DITULIS. Tanpa ini kamu tidak bisa
                -- membedakan "replica jalan" dari "replica mati tapi
                -- tertolong label game" - dan bedanya penting: kalau
                -- replica mati, Data.Boosts / Data.Upgrades juga ikut
                -- tidak terbaca, dan itu memengaruhi kartu lain.
                "Cash     : " .. (function()
                    local n, s = angkaStat("Cash")
                    if not n then return "TIDAK TERBACA" end
                    return "$" .. fmtNum(n) ..
                        (s == "label game" and "   <- dari LABEL GAME (replica gagal)" or "")
                end)(),
                "Gems     : " .. tostring(angkaStat("Gems") or "TIDAK TERBACA"),
                "Plot     : " .. (plot and plot.Name or "TIDAK KETEMU"),
                "Planter  : " .. nPlanter .. "   Slot: " .. total,
                "  Ready  : " .. ready .. "   (locked " .. locked .. ")",
                "  Tumbuh : " .. growing .. "    Kosong: " .. empty,
            }, "\n")
            task.wait(1)
        end
    end)

    local statLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(InfoBody) do task.wait(0.4) end
            statLbl.Text = table.concat({
                "SESI INI:",
                "  Panen   : " .. stats.harvested .. "     Tanam : " .. stats.planted,
                "  Supply  : " .. stats.supplied  .. "     Beli  : " .. stats.bought,
                "  Craft   : " .. stats.crafted   .. "     Stok  : " .. stats.stocked,
                "  Pasang  : " .. stats.placed    .. "     Checkout: " .. stats.checkout,
            }, "\n")
            task.wait(1)
        end
    end)

    makeButton(c, "🔄 Refresh Data Replica", THEME.Blue, function()
        dataReplica = nil
        local rep = grabReplica()
        notify(rep and "Data replica terbaca OK" or "Replica belum ada", rep and THEME.On or THEME.Red)
    end)
end

do
    local c = makeCard("🏃 MOVEMENT", THEME.Purple, InfoBody)

    -- Fly SUDAH termasuk noclip (reconcileNoclip), jadi tidak perlu
    -- menyalakan dua toggle untuk menembus atap plot.
    local setFlyVisual = makeToggle(c, "Fly (WASD + Space/Shift)", THEME.Purple, function(v)
        state.fly = v
        if v then MV.startFly() else MV.stopFly() end
        MV.reconcileNoclip()
    end, "fly")
    MV.setFlyVisual = setFlyVisual

    makeSlider(c, "Fly Speed", config.flySpeed, 16, 300, THEME.Purple, function(v)
        config.flySpeed = v
    end)

    -- Tombol NAIK / TURUN: untuk HP/tablet yang tidak punya Space & Shift.
    -- Pakai InputBegan/InputEnded (tahan-tekan), bukan Click sekali.
    do
        local upBtn = makeButton(c, "▲ NAIK (tahan)", THEME.Blue, function() end)
        upBtn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then MV.setVertical(1) end
        end)
        upBtn.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then MV.setVertical(0) end
        end)

        local downBtn = makeButton(c, "▼ TURUN (tahan)", THEME.Blue, function() end)
        downBtn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then MV.setVertical(-1) end
        end)
        downBtn.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
               or i.UserInputType == Enum.UserInputType.Touch then MV.setVertical(0) end
        end)
    end

    -- SHORTCUT FLY (PC): tekan [E] untuk nyala/mati tanpa buka GUI.
    if MV.isPC then
        local scBtn
        -- Tulisannya DIBACA dari MV.flyShortcutKey, bukan diketik "[E]"
        -- seperti dulu. Waktu tombol bawaannya diganti, label itu tetap
        -- menulis E - jadi tombolnya berbohong sampai kamu me-rebind.
        scBtn = makeButton(c, "Shortcut Fly: [" .. MV.flyShortcutKey.Name ..
            "]  (klik untuk ganti)", THEME.Purple, function()
            MV.rebinding = true
            scBtn.Text = "Tekan tombol baru..."
            scBtn.BackgroundColor3 = THEME.Yellow
        end)

        track(UserInputService.InputBegan:Connect(function(i, gpe)
            if i.UserInputType ~= Enum.UserInputType.Keyboard then return end

            -- Mode ganti tombol: tangkap tombol apapun kecuali yang dipakai
            -- sistem (Enter/Esc/Backspace/Tab) supaya tidak mengunci diri.
            if MV.rebinding then
                local k = i.KeyCode
                local blocked = (k == Enum.KeyCode.Unknown or k == Enum.KeyCode.Return
                              or k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace
                              or k == Enum.KeyCode.Tab)
                if blocked then
                    MV.rebinding = false
                    scBtn.Text = "Shortcut Fly: [" .. MV.flyShortcutKey.Name .. "]  (klik untuk ganti)"
                    scBtn.BackgroundColor3 = THEME.Purple
                    notify("Tombol itu tidak boleh dipakai", THEME.Yellow)
                    return
                end
                MV.flyShortcutKey = k
                MV.rebinding = false
                scBtn.Text = "Shortcut Fly: [" .. k.Name .. "]  (klik untuk ganti)"
                scBtn.BackgroundColor3 = THEME.Purple
                notify("Shortcut Fly diganti ke [" .. k.Name .. "]", THEME.On)
                return
            end

            -- gpe = true saat user sedang mengetik di TextBox -> jangan terbang
            if gpe then return end
            if i.KeyCode == MV.flyShortcutKey then
                state.fly = not state.fly
                if state.fly then MV.startFly() else MV.stopFly() end
                MV.reconcileNoclip()
                if MV.setFlyVisual then MV.setFlyVisual(state.fly) end
                notify(state.fly and "Fly ON" or "Fly OFF", state.fly and THEME.On or THEME.Off)
            end
        end))
    end

    makeToggle(c, "Noclip (tembus tembok)", THEME.Purple, function(v)
        state.noclip = v
        MV.reconcileNoclip()
    end, "noclip")

    makeToggle(c, "Speed Boost", THEME.Purple, function(v)
        state.speed = v
        if v then MV.startSpeed() else MV.stopSpeed() end
    end, "speed")
    makeSlider(c, "Walk Speed", config.walkSpeed, 16, 200, THEME.Purple, function(v)
        config.walkSpeed = v
    end)

    makeToggle(c, "Infinite Jump", THEME.Purple, function(v) state.infJump = v end, "infJump")

    -- Jump Power baru dipasang setelah slider DISENTUH, supaya lompatan
    -- bawaan game tidak berubah tanpa diminta.
    makeSlider(c, "Jump Power", config.jumpPower, 50, 300, THEME.Purple, function(v)
        config.jumpPower = v
        MV.setJumpPowerOn(true)
        MV.applyJumpPower()
    end)

    -- FOV: bidang pandang kamera. 70 = bawaan Roblox.
    makeSlider(c, "FOV Kamera", 70, 40, 120, THEME.Purple, function(v)
        pcall(function() camera.FieldOfView = v end)
    end)

    makeToggle(c, "Click to Teleport (pegang TP Tool)", THEME.Purple, function(v)
        state.clickTp = v
        if v then
            MV.giveTpTool()
            notify("TP Tool masuk backpack - PEGANG lalu klik titik", THEME.On)
        else
            MV.removeTpTool()
            notify("Click TP OFF", THEME.Off)
        end
    end, "clickTp")

    makeToggle(c, "Unlock Zoom (paksa bisa zoom-out)", THEME.Purple, function(v)
        state.unlockZoom = v
        if v then MV.startUnlockZoom() else MV.stopUnlockZoom() end
    end, "unlockZoom")

    if MV.isPC then
        makeToggle(c, "Munculkan Mouse (POV terkunci)", THEME.Purple, function(v)
            state.holdMouse = v
            if v then MV.startHoldMouse() else MV.stopHoldMouse() end
        end, "holdMouse")
    end

    makeInfo(c, "Fly SUDAH termasuk noclip, jadi cukup nyalakan Fly saja untuk\nmenembus atap/pagar plot.\n\nHP/Tablet: arahkan kamera lalu dorong joystick - arah ikut\nkemiringan kamera. Untuk naik/turun tegak lurus pakai tombol\nNAIK / TURUN di atas (tahan, jangan sekali tekan).\n\nClick to Teleport pakai TOOL supaya tidak teleport tiap kali\nkamu klik tombol GUI - jadi harus dipegang dulu.")
end

-- ============================================================
-- KAMERA: kenapa klik-kanan kadang tidak bisa memutar pandangan
-- ============================================================
do
    local c = makeCard("🎥 KAMERA / KLIK-KANAN", THEME.Cyan, InfoBody)

    makeInfo(c, "KENAPA KADANG BISA, KADANG TIDAK:\n\nKamera bawaan Roblox baru mulai memutar kalau klik-kanan-nya\nTIDAK diserap GUI. Di CameraInput milik Roblox:\n\n   InputBegan:Connect(function(input, SUNK)\n       if input.UserInputType == MouseButton2 and not SUNK then\n           MouseBehavior = LockCurrentPosition   -- baru muter di sini\n\nSetiap TextButton menyerap klik (SUNK = true). Panel ini penuh\ntombol, jadi kalau kursor kebetulan DI ATAS panel saat kamu\ntekan klik-kanan, kameranya tidak pernah mulai berputar.\nGeser kursor ke area kosong -> langsung bisa lagi.\nItu sebabnya terasa 'kadang bisa kadang tidak'.\n\nPenyebab KEDUA (ini bug saya, sudah diperbaiki):\ntoggle 'Munculkan Mouse' dulu memaksa MouseBehavior = Default\nSETIAP FRAME, jadi penguncian kamera langsung dibatalkan.\nSekarang pemaksaan itu dilewati selama klik-kanan ditahan.")

    -- Tombol darurat: kalau mouse terlanjur terkunci oleh sebab apapun.
    makeButton(c, "🔓 LEPAS KUNCI MOUSE (perbaiki kamera macet)", THEME.Green, function()
        MV.unstickMouse()
        notify("MouseBehavior dikembalikan ke Default", THEME.On)
        addLog("unstickMouse: MouseBehavior -> Default", "INFO")
    end)

    -- Sembunyikan panel = tidak ada tombol yang menyerap klik-kanan,
    -- jadi kamera bebas diputar di SELURUH layar.
    local hideBtn
    hideBtn = makeButton(c, "👁 SEMBUNYIKAN PANEL (kamera bebas)", THEME.Blue, function()
        Frame.Visible = not Frame.Visible
        hideBtn.Text = Frame.Visible and "👁 SEMBUNYIKAN PANEL (kamera bebas)"
                                      or "👁 TAMPILKAN PANEL LAGI"
    end)

    -- Shortcut PC: tekan [RightShift] untuk sembunyi/tampil cepat.
    if MV.isPC then
        track(UserInputService.InputBegan:Connect(function(i, gpe)
            if gpe then return end
            if i.KeyCode == Enum.KeyCode.RightShift then
                Frame.Visible = not Frame.Visible
                if hideBtn then
                    hideBtn.Text = Frame.Visible and "👁 SEMBUNYIKAN PANEL (kamera bebas)"
                                                  or "👁 TAMPILKAN PANEL LAGI"
                end
            end
        end))
        makeInfo(c, "Shortcut: [RightShift] = sembunyi / tampilkan panel.\nSaat panel disembunyikan, TIDAK ADA tombol yang menyerap\nklik-kanan, jadi kamera bisa diputar dari titik manapun.\n\nCara lain: kecilkan panel dengan tombol - (minimize) di\npojok kanan atas, atau geser panel ke pinggir layar.")
    end
end

do
    local c = makeCard("📍 TELEPORT CEPAT", THEME.Yellow, InfoBody)

    makeButton(c, "🏡 Teleport ke Plot Saya", THEME.Blue, function()
        local ok = invokeRF("PlacementService", "TeleportToBase", LocalPlayer)
        if not ok then
            local plot = getMyPlot()
            local spawn = plot and plot:FindFirstChild("Spawn")
            local sl = spawn and spawn:FindFirstChildWhichIsA("SpawnLocation")
            if sl then tpTo(sl) else notify("Plot tidak ketemu", THEME.Red); return end
        end
        notify("Teleport ke plot OK", THEME.On)
    end)
    makeButton(c, "🛠 Teleport ke Craft Table", THEME.Blue, function()
        local ct = getMyCraftTable()
        if ct then tpTo(ct); notify("Teleport OK", THEME.On) else notify("Craft Table tidak ketemu", THEME.Red) end
    end)
    makeButton(c, "💻 Teleport ke Computer", THEME.Blue, function()
        local plot = getMyPlot()
        local b = plot and plot:FindFirstChild("Building")
        local comp = b and b:FindFirstChild("Computer")
        if comp then tpTo(comp); notify("Teleport OK", THEME.On) else notify("Computer tidak ketemu", THEME.Red) end
    end)
    makeButton(c, "💰 Teleport ke Register", THEME.Blue, function()
        local plot = getMyPlot()
        local b = plot and plot:FindFirstChild("Building")
        local reg = b and b:FindFirstChild("Register")
        if reg then tpTo(reg); notify("Teleport OK", THEME.On) else notify("Register tidak ketemu", THEME.Red) end
    end)
end

-- ============================================================
-- PEMBANGUNAN BERTAHAP  (anti "Roblox langsung tertutup saat execute")
-- ============================================================
-- Panel ini berisi kira-kira 1.300 objek GUI. Versi sebelumnya membuat
-- SEMUANYA dalam satu jalan tanpa pernah yield sekalipun. Thread yang
-- menahan CPU sepanjang itu dianggap "nyangkut" oleh sebagian executor
-- (paling sering di HP), lalu injeksinya diputus -- dan efek yang kamu
-- lihat adalah Roblox ikut tertutup begitu tombol execute ditekan.
--
-- task.wait() di bawah memecah pembangunan jadi per-tab: satu frame
-- untuk Farm, satu untuk Shop, dan seterusnya. TIDAK ADA fitur yang
-- berubah atau hilang -- yang berubah cuma waktunya, bergeser beberapa
-- milidetik. Panel baru ditampilkan di blok STARTUP paling bawah, jadi
-- tidak terlihat tumbuh sepotong-sepotong.
--
-- Dua penghemat lain yang sudah dipasang:
--   * daftar dropdown dibuat MALAS (getList) -> ~190 objek tidak lagi
--     lahir saat execute, dan ScreenGui tidak menyimpan 32 anak permanen
--   * parent objek dipasang TERAKHIR -> satu reflow, bukan per properti
task.wait()

-- ============================================================
-- BUILD UI : TAB AUTO
-- ============================================================
do
    -- Paksa TURBO selama aksi berlangsung lalu kembalikan ke posisi semula.
    -- Jadi semua yang di tab ini instan walau toggle TURBO sedang OFF,
    -- tanpa mengubah pilihanmu di tab Farm.
    -- Bisa dimatikan lewat config.autoTurbo (sakelarnya di kartu STATUS).
    local function instan(fn)
        local was = state.turbo
        if config.autoTurbo then state.turbo = true end
        local ok, a, b = pcall(fn)
        state.turbo = was
        if not ok then addLog("Auto: " .. tostring(a), "AUTO"); return nil end
        return a, b
    end

    local c = makeCard("⚡ MESIN INSTAN", THEME.Red, AutoBody)

    makeInfo(c, "Kenapa yang ini benar-benar TIDAK perlu jalan ke tempatnya:\n\nPanen / Tanam / Beli / Craft / Rangkaian-ke-Rak semuanya dikirim\nlewat RemoteFunction (GrowingService, ShopService,\nArrangementService, FlowerDisplayService). RemoteFunction TIDAK\npunya pemeriksaan jarak sama sekali - server cuma memeriksa\nkepemilikan plot dan tool yang dipegang. Jadi kamu bisa berdiri\ndi mana saja, bahkan di plot orang lain.\n\nSatu-satunya yang beda: KASIR (CheckoutPrompt). Itu dibuat\nSERVER, jadi Roblox ikut memeriksa jaraknya (10 stud) di sisi\nserver. Lihat kartu di bawah.")

    -- Aksi tiap toggle ditaruh di AUTO.set supaya tombol "MODE UANG
    -- MAKSIMUM" di kartu bawah bisa menyalakan semuanya sekaligus DAN
    -- ikut membalik tampilan sakelarnya. AUTO sudah ada di level teratas,
    -- jadi ini tidak menambah register sama sekali.
    AUTO.set, AUTO.vis = {}, {}

    -- SATU SAKELAR, DUA TEMPAT - dan ini BUKAN kembar.
    -- Tiga sakelar sengaja dipasang dua kali: di tab Auto (terkumpul)
    -- dan di tab asalnya (bersebelahan dengan dropdown filternya).
    --
    -- SYARATNYA: keduanya WAJIB memanggil AUTO.set.<nama> yang SAMA, dan
    -- fungsi ini yang menyambungkan TAMPILANNYA. Kalau tiap sakelar
    -- punya ingatan sendiri padahal loopnya satu, yang di Farm bisa
    -- menampilkan ON sementara yang di Auto OFF - dan tidak ada cara
    -- tahu mana yang benar. Cuma menumpuk fungsi, nol register baru.
    function AUTO.pasangVis(nama, fn)
        local lama = AUTO.vis[nama]
        if lama then
            AUTO.vis[nama] = function(v) lama(v); fn(v) end
        else
            AUTO.vis[nama] = fn
        end
    end

    -- ============================================================
    -- MUNDUR SENDIRI KALAU TIDAK ADA APA-APA - ini soal LAG, bukan gaya
    -- ============================================================
    -- Sapuan panen membaca 3 atribut untuk TIAP SLOT, tiap putaran. Di
    -- kebun 6.000 slot itu ~18.000 GetAttribute sekali sapu, dan dengan
    -- Auto Delay 0,3 detik jadi ~60.000 pembacaan PER DETIK - terus
    -- menerus, walau tidak ada satu slot pun yang siap.
    --
    -- Padahal Camellia matang 12 JAM. Menyapu tiga kali per detik untuk
    -- sesuatu yang berubah tiap dua belas jam itu murni pemborosan.
    --
    -- Jadi: begitu tiga sapuan beruntun tidak memanen apa pun, jedanya
    -- naik ke 3 detik. Begitu ada yang kepanen, langsung balik cepat -
    -- jadi saat panen beruntun (tanaman matang berbarengan) dia tetap
    -- responsif seperti semula.
    --
    -- Yang TIDAK diperbaiki di sini, dan harus jujur: badai
    -- _updateState milik GAME saat panen massal. Tiap atribut slot yang
    -- berubah memanggil ulang _updateState planter itu (SPSv3 591), dan
    -- _updateState menulis 3 properti prompt untuk SETIAP slot planter
    -- (SPSv3 715-800). Itu di luar jangkauan hub - buktinya panen manual
    -- tanpa script pun ikut nge-lag.
    -- KUNCINYA SENGAJA "kPanen"/"kTanam", BUKAN "panen"/"tanam".
    -- PICU.tanam sudah dipakai sebagai BENDERA SIBUK, dan di Lua angka 0
    -- itu TRUTHY - jadi kalau penghitung ini menimpanya dengan 0, baris
    -- `if PICU.tanam then return end` akan mengira sapuan sedang jalan
    -- SELAMANYA dan auto tanam mati total tanpa pesan apa pun.
    local function mundur(kunci, n)
        local dapat = (tonumber(n) or 0) > 0
        PICU[kunci] = dapat and 0 or math.min((PICU[kunci] or 0) + 1, 99)
        return dapat
    end
    local function jeda(kunci)
        if (PICU[kunci] or 0) >= 3 then return math.max(config.autoDelay, 3) end
        return config.autoDelay
    end

    AUTO.set.panen = function(v)
        state.aPanen = v
        if AUTO.vis.panen then AUTO.vis.panen(v) end
        if v then
            startLoop("aPanen", function()
                mundur("kPanen", instan(function() return doHarvestOnce(true) end))
            end, function() return jeda("kPanen") end)
        else stopLoop("aPanen") end
    end

    AUTO.set.tanam = function(v)
        state.aTanam = v
        if AUTO.vis.tanam then AUTO.vis.tanam(v) end
        -- Pemicu instan: slot yang baru dipanen langsung ditanami, tanpa
        -- menunggu giliran sapuan. Dipanggil SESUDAH state.aTanam diisi,
        -- karena AUTO.picuPerlu membacanya.
        AUTO.pantauObjek(AUTO.picuPerlu())
        if v then
            startLoop("aTanam", function()
                -- Bendera yang sama dengan pemicu instan -> sapuan dan
                -- pemicu tidak pernah jalan berbarengan.
                if PICU.tanam then return end
                PICU.tanam = true
                -- Mundur sendiri kalau tidak ada slot kosong - alasan
                -- lengkapnya di AUTO.set.panen tepat di atas. Di sini
                -- lebih aman lagi: slot kosong sudah punya PEMICU INSTAN
                -- sendiri, jadi sapuan ini memang cuma jaring pengaman.
                mundur("kTanam", instan(function() return doPlantOnce(true) end))
                PICU.tanam = false
            end, function() return jeda("kTanam") end)
        else stopLoop("aTanam") end
    end

    -- Isi loop belanja, dipakai DUA sakelar (bibit & supply) dengan
    -- toko + dropdown yang berbeda. Alasan kegagalan dilaporkan, tapi
    -- CUMA SEKALI per alasan: loop ini jalan tiap 4 detik, kalau tiap
    -- putaran menulis log yang sama Output penuh dalam semenit.
    local function belanja(shopId, pilihan, label)
        if setIsEmpty(pilihan) then
            -- Dropdown kosong = tidak ada yang diminta. Dikatakan sekali
            -- saja supaya sakelar yang menyala tanpa centang tidak diam
            -- membisu seperti dulu.
            local w = "belum ada yang dicentang di dropdown " .. label
            if _stockWarn[shopId] ~= w then
                _stockWarn[shopId] = w
                addLog("Auto Buy " .. label .. ": " .. w, "AUTO")
                notify("Auto Buy " .. label .. ": " .. w, THEME.Yellow)
            end
            return
        end
        -- JANGAN MENUMPUK dengan tombol "BELI SEKALI" (lihat beliSekali).
        -- Diam saja tanpa log: ini keadaan normal yang lewat sendiri, dan
        -- loop ini bangun lagi tiap ~4 detik.
        if TOKO.sibuk then return end
        TOKO.sibuk = true
        -- Tiap toko punya angka JUMLAH-nya sendiri. Digabung dulu, dan
        -- itu salah: menaikkan jatah bibit ikut menaikkan jatah supply
        -- yang harganya sampai $50.000 sebiji.
        --
        -- Dibungkus pcall supaya penanda sibuk PASTI dilepas. Tanpa itu,
        -- satu error di tengah jalan mengunci semua pembelian sampai hub
        -- di-execute ulang - dan penyebabnya mustahil ditebak dari layar.
        local ok, n, why = pcall(buyFromShop, shopId, pilihan,
            (shopId == "SeedShop") and config.buyQty or config.qtySupply,
            false, false, config.habisStok)
        TOKO.sibuk = nil
        if not ok then
            addLog("Auto Buy " .. label .. " error: " .. tostring(n), "AUTO")
            return
        end
        if n and n > 0 then
            _stockWarn[shopId] = nil
        elseif why and _stockWarn[shopId] ~= why then
            _stockWarn[shopId] = why
            addLog("Auto Buy " .. label .. ": " .. why, "AUTO")
            -- TOAST-NYA CUMA 330x36 PIKSEL. Alasan yang menyebut daftar
            -- barang PASTI terpotong di tengah kata dan jadi tidak berguna -
            -- itu yang bikin pesan "tidak ada yang cocok di SupplyShop -
            -- yang DIJUAL sekarang" berhenti tepat sebelum bagian yang
            -- justru dicari. Jadi toast cuma menunjuk arah; teks LENGKAPNYA
            -- di kartu 'STOK ASLI' tab Shop, yang labelnya melar sendiri.
            notify("Auto Buy " .. label .. " gagal - baca kartu 'STOK ASLI'" ..
                   " di tab Shop", THEME.Yellow)
        end
    end

    AUTO.set.beliBibit = function(v)
        state.aBeliBibit = v
        if AUTO.vis.beliBibit then AUTO.vis.beliBibit(v) end
        if v then
            startLoop("aBeliBibit", function()
                belanja("SeedShop", sel.buySeeds, "Bibit")
            end, function() return math.max(config.shopDelay * 6, 4) end)
        else stopLoop("aBeliBibit") end
    end

    AUTO.set.beliSupply = function(v)
        state.aBeliSupply = v
        if AUTO.vis.beliSupply then AUTO.vis.beliSupply(v) end
        if v then
            startLoop("aBeliSupply", function()
                belanja("SupplyShop", sel.buySupplies, "Supply")
            end, function() return math.max(config.shopDelay * 6, 4) end)
        else stopLoop("aBeliSupply") end
    end

    AUTO.set.craft = function(v)
        -- SALING MEMATIKAN dengan AUTO RANGKAI -> RAK. Wajib, bukan
        -- kerapian: dua-duanya membuka SESI craft di meja yang sama
        -- (StartArranging -> ReserveFlower... -> Finish), jadi kalau
        -- jalan bersamaan mereka saling mencuri bunga reserve dan
        -- rangkaiannya GAGAL JADI.
        if v and state.aCombo then AUTO.set.combo(false) end
        state.aCraft = v
        if AUTO.vis.craft then AUTO.vis.craft(v) end
        if v then
            startLoop("aCraft", function()
                local ok, err = doCraftOnce()
                if not ok then addLog("Auto Craft: " .. tostring(err), "AUTO") end
            end, function() return config.craftDelay end)
        else stopLoop("aCraft") end
    end

    AUTO.set.rak = function(v)
        -- Idem: AUTO RANGKAI -> RAK sudah mendorong hasilnya ke rak
        -- sendiri. Kalau dua-duanya jalan, keduanya meng-EQUIP tool dan
        -- saling merebut tangan - tembakan yang satu mendarat saat
        -- tangannya sudah dipakai yang lain, lalu ditolak server.
        if v and state.aCombo then AUTO.set.combo(false) end
        state.aRak = v
        if AUTO.vis.rak then AUTO.vis.rak(v) end
        if v then
            -- Pemicu instan DAN sapuan berkala, dua-duanya. Yang instan
            -- untuk kecepatan, yang berkala sebagai jaring pengaman -
            -- alasannya di AUTO.pantauObjek.
            AUTO.pantauObjek(AUTO.picuPerlu())
            startLoop("aRak", function()
                -- TURBO TIDAK dipaksa apa-apa di sini - sakelar TURBO itu
                -- keputusanmu. Yang perlu kamu tahu: di TURBO balasan
                -- server tidak terbaca, dan kapasitas rak rangkaian CUMA
                -- bisa diukur dari PENOLAKAN. Jadi di TURBO raknya terisi
                -- MERANGKAK (satu tembakan percobaan per putaran, lihat
                -- "JALAN BUNTU DI MODE TURBO" di doStockArrangementOnce).
                -- Kalau rak berhenti bertambah, matikan TURBO sebentar.
                local ok, n, why = pcall(doStockArrangementOnce)
                if not ok then addLog("Auto Rak error: " .. tostring(n), "AUTO"); return end
                if n == 0 and why and _stockWarn.arr ~= why then
                    _stockWarn.arr = why
                    addLog("Auto Rak: " .. why, "AUTO")
                elseif n > 0 then _stockWarn.arr = nil end
            end, function() return config.sellDelay end)
        else
            stopLoop("aRak")
            -- Pendengarnya tidak dilepas begitu saja: sakelar LAIN bisa
            -- masih memakainya. AUTO.picuPerlu yang memutuskan.
            AUTO.pantauObjek(AUTO.picuPerlu())
        end
    end

    -- ============================================================
    -- AUTO RANGKAI -> RAK : satu mesin untuk seluruh siklus
    -- ============================================================
    -- Ini pengganti tombol COMBO sekali-tekan. Yang diminta memang
    -- SAKELAR, bukan tombol - tombol sekali-tekan artinya kamu harus
    -- menekannya lagi tiap kali bunga menumpuk, dan itu bukan "auto".
    --
    -- Satu putaran = wadah terbaik yang levelnya kebuka -> bunga diisi
    -- sampai penuh (priceBase tertinggi didahulukan) -> batch sekali
    -- tembak -> hasilnya langsung didorong ke rak. Batchnya dipotong ke
    -- SISA SLOT TAS supaya bahan tidak hangus.
    --
    -- Dia MEMATIKAN Auto Craft & Auto Rangkaian->Rak begitu dinyalakan,
    -- karena pekerjaannya memang sama - alasan lengkapnya di dua fungsi
    -- di atas.
    AUTO.set.combo = function(v)
        state.aCombo = v
        if AUTO.vis.combo then AUTO.vis.combo(v) end
        if v then
            if state.aCraft then AUTO.set.craft(false) end
            if state.aRak   then AUTO.set.rak(false)   end
            -- Combo juga mendorong hasilnya ke rak, jadi dia ikut memakai
            -- pemicu instan yang sama.
            AUTO.pantauObjek(AUTO.picuPerlu())
            startLoop("aCombo", function()
                local jadi, _, why = comboCraftRak(config.craftBatch,
                    function() return state.aCombo end)
                if (tonumber(jadi) or 0) > 0 then
                    _stockWarn.combo = nil
                elseif why and _stockWarn.combo ~= why then
                    -- Alasan dilaporkan CUMA SEKALI per alasan. Loop ini
                    -- bangun tiap craftDelay (bawaan 0,5 dtk), jadi
                    -- "tidak ada bunga di inventory" yang ditulis tiap
                    -- putaran akan memenuhi Output dalam hitungan detik.
                    _stockWarn.combo = why
                    addLog("Auto Rangkai->Rak: " .. why, "AUTO")
                end
            end, function() return config.craftDelay end)
        else
            stopLoop("aCombo")
            AUTO.pantauObjek(AUTO.picuPerlu())
        end
    end

    -- SIRAM & PUPUK ke tanaman. Isi loopnya SATU BADAN untuk dua jenis -
    -- bedanya cuma SupplyType dan daftar merek yang diizinkan.
    --
    -- Alasan kegagalan dilaporkan CUMA SEKALI per alasan: loop ini bangun
    -- tiap beberapa detik, dan "tidak ada kaleng di inventory" yang
    -- ditulis tiap putaran akan memenuhi Output dalam semenit.
    local function pakaiSupply(jenis, hanya, label)
        local n, why = habisSupply(jenis, nil, hanya)
        n = tonumber(n) or 0
        if n > 0 then
            _stockWarn[jenis] = nil
        elseif why and _stockWarn[jenis] ~= why then
            _stockWarn[jenis] = why
            addLog("Auto " .. label .. ": " .. why, "AUTO")
        end
    end

    AUTO.set.siram = function(v)
        state.aSiram = v
        if v then
            startLoop("aSiram", function()
                pakaiSupply("WateringCan", sel.canSiram, "Siram")
            end, function() return math.max(config.farmDelay * 3, 2) end)
        else stopLoop("aSiram") end
    end

    AUTO.set.pupuk = function(v)
        state.aPupuk = v
        if v then
            -- Jedanya PANJANG dan itu memang benar: slot yang hasil
            -- panennya sudah 6 dilewati tanpa ditembak (dibaca dari
            -- Slot_i_Variants), jadi menembak tiap 2 detik tidak menambah
            -- hasil apa pun - cuma menambah panggilan.
            startLoop("aPupuk", function()
                pakaiSupply("Fertilizer", sel.pupukPakai, "Pupuk")
            end, function() return math.max(config.farmDelay * 20, 10) end)
        else stopLoop("aPupuk") end
    end

    AUTO.vis.panen = makeToggle(c, "Auto Panen (instant, dari mana saja)", THEME.Green, function(v)
        AUTO.set.panen(v)
        notify(v and "Auto Panen ON" or "Auto Panen OFF", v and THEME.On or THEME.Off)
    end)

    AUTO.vis.tanam = makeToggle(c, "Auto Tanam Seed (instant)", THEME.Green, function(v)
        if v and setIsEmpty(sel.plantSeeds) then
            notify("Pilih bibit di tab Farm -> 'Seeds to Plant' dulu", THEME.Yellow)
        end
        AUTO.set.tanam(v)
        notify(v and "Auto Tanam ON" or "Auto Tanam OFF", v and THEME.On or THEME.Off)
    end)

    AUTO.vis.beliBibit = makeToggle(c, "Auto Buy BIBIT (SeedShop)", THEME.Yellow, function(v)
        if v and setIsEmpty(sel.buySeeds) then
            notify("Centang dulu di tab Shop -> 'Seeds to Buy'", THEME.Yellow)
        end
        AUTO.set.beliBibit(v)
        notify(v and "Auto Buy Bibit ON" or "Auto Buy Bibit OFF", v and THEME.On or THEME.Off)
    end)
    makeNumber(c, "Jumlah BIBIT per barang", 1, 50000, THEME.Yellow, "buyQty")
    makeButton(c, "🛒 BELI BIBIT SEKALI (pakai angka di atas)", THEME.Green, function()
        task.spawn(function()
            beliSekali("SeedShop", sel.buySeeds, "Bibit", config.buyQty)
        end)
    end)
    local totBibit = makeInfo(c, "-")

    AUTO.vis.beliSupply = makeToggle(c, "Auto Buy SUPPLY (SupplyShop)", THEME.Yellow, function(v)
        if v and setIsEmpty(sel.buySupplies) then
            notify("Centang dulu di tab Shop -> 'Supplies to Buy'", THEME.Yellow)
        end
        AUTO.set.beliSupply(v)
        notify(v and "Auto Buy Supply ON" or "Auto Buy Supply OFF", v and THEME.On or THEME.Off)
    end)
    makeNumber(c, "Jumlah SUPPLY per barang", 1, 50000, THEME.Yellow, "qtySupply")
    makeButton(c, "🛒 BELI SUPPLY SEKALI (pakai angka di atas)", THEME.Green, function()
        task.spawn(function()
            beliSekali("SupplyShop", sel.buySupplies, "Supply", config.qtySupply)
        end)
    end)
    local totSupply = makeInfo(c, "-")

    -- SATU loop untuk DUA label, bukan dua loop. Kartu PEMERIKSA LAG di
    -- tab Settings sudah membuktikan label hidup itu sumber lag paling
    -- besar di panel ini, jadi jangan menambah loop lebih dari perlunya.
    -- Isinya nol panggilan server: harga dari katalog / daftar toko yang
    -- sudah tersimpan, stok dari TOKO.stok, cash dari Replica.
    task.spawn(function()
        while ScreenGui.Parent do
            while ScreenGui.Parent and not tampil(AutoBody) do task.wait(0.4) end
            totBibit.Text  = totalBelanja("SeedShop", sel.buySeeds,
                                          config.buyQty, "Seeds")
            totSupply.Text = totalBelanja("SupplyShop", sel.buySupplies,
                                          config.qtySupply, "Supplies")
            task.wait(2)
        end
    end)

    AUTO.vis.craft = makeToggle(c, "Auto Craft (instant)", THEME.Pink, function(v)
        if v and not (config.containerPick or config.autoBigContainer or config.autoBestContainer) then
            notify("Pilih Container di tab Craft dulu", THEME.Yellow)
        end
        AUTO.set.craft(v)
        notify(v and "Auto Craft ON" or "Auto Craft OFF", v and THEME.On or THEME.Off)
    end)

    AUTO.vis.rak = makeToggle(c, "Auto Rangkaian -> Rak (instant)", THEME.Cyan, function(v)
        AUTO.set.rak(v)
        notify(v and "Auto Rangkaian ke Rak ON - rak yang dibeli langsung diisi"
                  or "Auto Rangkaian ke Rak OFF",
               v and THEME.On or THEME.Off)
    end)

    makeInfo(c, "SAKELAR DI ATAS SEKARANG PUNYA DUA MESIN, bukan satu.\n\n  1. PEMICU INSTAN - begitu PEMBELI mengambil rangkaian dari\n     sebuah rak, rak ITU langsung diisi ulang (~0,25 detik).\n     Tidak menunggu giliran sapuan.\n\n  2. SAPUAN BERKALA tiap Sell Delay - tetap ada sebagai jaring\n     pengaman, untuk hal yang bisa meleset dari pemicu: rak yang\n     baru dipasang, koneksi putus, plot dimuat ulang.\n\nSINYALNYA BUKAN TEBAKAN. Isi rak rangkaian itu ANAK folder\n'_Arrangements', dan komponen ArrangementDisplay milik GAME\nSENDIRI memakai persis dua sinyal ini (SPSv3 1204 & 1212):\n\n   _Arrangements.ChildAdded:Connect(...)   -> _updateState()\n   _Arrangements.ChildRemoved:Connect(...) -> _updateState()\n\nJadi begitu satu rangkaian TERJUAL, anaknya hilang - itu detik\nyang ditunggu hub. Rak yang baru dipasang pun ditangani: folder\nitu belum ada sampai isian pertama masuk, jadi ChildAdded milik\nRAK ikut dipantau (game melakukan hal yang sama, 1216-1222).\n\nYANG IKUT DIPERBAIKI SEKALIAN - ini soal beban, bukan fitur.\nSapuan lama memanggil penyisiran penuh Character + Backpack\nSEBELUM memeriksa apakah raknya perlu disentuh. Di plot 81 rak\nitu 81 penyisiran penuh tiap 0,6 detik, walau delapan puluh di\nantaranya langsung dilewati karena sudah penuh. Sekarang rak yang\ndilewati cuma dibaca isinya (satu FindFirstChild), dan penyisiran\ntas baru terjadi untuk rak yang memang mau diisi.\n\nDUA MESIN ITU TIDAK BOLEH BEREBUT TANGAN, jadi ada kunci: kalau\nsapuan sedang jalan, pemicu instan melewatinya - dan itu aman,\nkarena sapuan itu sendiri yang akan mengisi raknya. Tanpa kunci,\npanggilan bulk milik satu jalur bisa terkirim saat tangannya\nsudah direbut jalur lain, lalu kenaikan yang terukur dikaitkan ke\nrak yang SALAH - dan rak lowong dicap PENUH 45 detik.")
end

do
    local c = makeCard("🧾 AUTO KLIK E DI KASIR (tanpa kasir sewaan)", THEME.Blue, AutoBody)

    makeInfo(c, "CheckoutPrompt ada di Building.Register.ItemHolder.\n  ActionText   = Checkout\n  ObjectText   = barang + harga, mis. 'Small Bouquet (Anthurium)  $15123'\n  HoldDuration = 0.5 detik  -> dinolkan, jadi instan\n  jarak        = 10 stud\n\nNormalnya tombol ini ditekan staf Cashier. Di sini SCRIPT yang\nmenekannya, jadi kamu TIDAK perlu hire Cashier sama sekali.\n\nBegitu server menaruh barang di meja (_CounterItems), script\nlangsung melayaninya detik itu juga - bukan menunggu putaran loop.")

    AUTO.set.kasir = function(v)
        state.autoKasir = v
        if AUTO.vis.kasir then AUTO.vis.kasir(v) end
        if v then
            AUTO.pantau(true)
            task.spawn(AUTO.layaniSekarang)   -- sapu yang sudah menunggu
            -- Loop ini JARING PENGAMAN kalau pemicu instannya meleset
            -- (plot baru dimuat, Register diganti). Saat meja kosong
            -- AUTO.checkout berhenti cepat, jadi murah dipanggil sering.
            startLoop("aKasir", function()
                AUTO.pantau(true)
                AUTO.layaniSekarang()
            end, function() return math.max(config.autoDelay, 0.5) end)
        else
            stopLoop("aKasir")
            AUTO.pantau(false)
        end
    end

    AUTO.vis.kasir = makeToggle(c, "Auto Klik E Kasir (instant)", THEME.Blue, function(v)
        AUTO.set.kasir(v)
        notify(v and "Auto Kasir ON - instan" or "Auto Kasir OFF",
               v and THEME.On or THEME.Off)
    end)

    makeButton(c, "🧾 Layani Kasir Sekarang (1x sapu)", THEME.Green, function()
        task.spawn(function()
            local n, why = AUTO.checkout()
            notify(n > 0 and ("Kasir: " .. n .. " barang dilayani")
                          or ("Tidak ada yang dilayani - " .. tostring(why)),
                   n > 0 and THEME.On or THEME.Yellow)
        end)
    end)

    makeInfo(c, "KESIMPULAN AKHIR: KASIR MEMANG HARUS DIDEKATI.\n\nSaya sempat bolak-balik di titik ini, jadi ini yang sudah TERUJI,\nbukan dugaan lagi:\n\n  * hub lain yang jalan (Ouroboros) TELEPORT ke kasir lalu tekan E\n  * di plot ini cara tanpa pindah (1-4) SELALU ditolak\n  * jadi CheckoutPrompt memang divalidasi jaraknya di sisi SERVER\n\nMakanya urutan cobanya sekarang: 5 dulu (mendekat), baru 1-4.\nKalau di server lain yang tanpa pindah ternyata diterima, urutan\nini tetap menemukannya - cuma dicoba belakangan.\n\nDUA BUG YANG BIKIN TELEPORT ITU SENDIRI GAGAL, sudah diperbaiki:\n\n  1. BADAN JATUH. Titik tujuan dulu diambil di KETINGGIAN PROMPT.\n     Prompt kasir menempel di meja, jadi itu titik melayang -\n     badan jatuh SEBELUM tahanan 0,5 detik selesai, server melihat\n     kita sudah menjauh, Triggered ditolak.\n     Sekarang: tujuannya 4 stud dari prompt KE ARAH tempatmu tadi\n     (sisi terbuka), dan badan DIPATOK tiap frame selama menahan.\n\n  2. KADANG TIDAK MAU TELEPORT. Pencari posisi dulu menyerah kalau\n     induk prompt bukan Attachment / BasePart. Sekarang dia\n     memanjat ke atas sampai ketemu yang punya posisi (termasuk\n     Model lewat GetPivot), jadi praktis tidak pernah gagal lagi.\n\nSESUDAH DEKAT, TIDAK PERLU MENAHAN E - INSTAN.\n\nLama menahan dihitung di CLIENT. Begitu HoldDuration diset 0,\nengine memicu Triggered SEKETIKA saat InputHoldBegin; tidak ada\npenghitung 0,5 detik yang jalan. Server tidak ikut memeriksa\nlama tahan - yang dia periksa cuma jarak.\n\nDan teleportnya SEKALI untuk SELURUH antrean, bukan bolak-balik\ntiap barang: badan dipatok di depan kasir, semua barang dilayani\nberuntun, baru dikembalikan. 30 barang jadi hitungan detik -\nversi sebelumnya butuh 30 x 0,5 = 15 detik hanya untuk menahan.\n\nKalau tetap tidak mau badanmu pindah sama sekali, matikan\nsakelar di bawah - checkout akan gagal, tapi badanmu dijamin\ndiam.")

    -- SATU sakelar untuk kasir DAN pesanan (dulu dua, dan itu kembar).
    -- Nilai awalnya dibaca dari config, BUKAN ditulis `true` di sini:
    -- kalau ditulis dua kali, tulisan di label dan posisi sakelarnya bisa
    -- berbeda dari nilai yang sebenarnya dipakai.
    makeToggle(c, "Dekati dulu sebelum tekan E (kasir + pesanan)", THEME.Blue, function(v)
        config.dekatiDulu = v
        notify(v and "Dekati dulu ON - pindah, layani, lalu balik kalau berhasil"
                  or "Dekati dulu OFF - badan diam, tapi server menolak karena jarak",
               v and THEME.On or THEME.Yellow)
    end)(config.dekatiDulu)

    makeInfo(c, "SATU SAKELAR UNTUK DUA-DUANYA - dulu ada dua, dan itu memang\nkembar.\n\n  di tab Auto  : 'Teleport ke kasir dulu'   -> CheckoutPrompt\n  di tab Farm  : 'Pindah ke pembeli dulu'   -> CustomOrderPrompt\n\nDua prompt itu sama-sama DIBUAT SERVER dengan jarak 10 stud, jadi\nkeduanya menuntut badan dekat karena alasan yang persis sama. Dan\nsesudah diperbaiki, mesinnya juga sama: pindah, badan dipatok tiap\nframe supaya tidak jatuh, tembak, lalu dipulangkan HANYA kalau\nberhasil.\n\nTidak ada gunanya satu nyala dan satunya mati, jadi digabung.")
end

do
    local c = makeCard("🖱 BUKA PROXIMITY (dari jarak berapa pun)", THEME.Purple, AutoBody)

    makeInfo(c, "Dua prompt ini DIBUAT CLIENT - terbukti di SPSV2TELITI, dibikin\npakai Instance.new di controller game sendiri, dan Triggered-nya\njuga jalan di client:\n\n  StaffPrompt (Computer)     -> Triggered: ToggleUI() + OpenMenu()\n  CraftSpot   (CraftTable)   -> Triggered: EnterCraftMode(meja)\n\nKarena tidak ada server yang ikut memeriksa, jaraknya cukup\ndinaikkan di sisi client lalu ditembak. Benar-benar dari mana saja,\ntanpa pindah sedikit pun.")

    makeButton(c, "💻 BUKA GUI KOMPUTER (StaffPrompt)", THEME.Blue, function()
        local ok, err = AUTO.bukaKomputer()
        notify(ok and "StaffPrompt ditembak - GUI komputer terbuka"
                   or ("Gagal: " .. tostring(err)), ok and THEME.On or THEME.Red)
    end)

    makeButton(c, "🛠 BUKA FRAME CRAFT (CraftSpot Arrange)", THEME.Pink, function()
        local ok, err = AUTO.bukaCraft()
        notify(ok and "Prompt Arrange ditembak - frame craft terbuka"
                   or ("Gagal: " .. tostring(err)), ok and THEME.On or THEME.Red)
    end)

    makeInfo(c, "Catatan: frame Craft memindahkan KAMERA ke meja (EnterCraftMode\nmemanggil enterCraftCamera). Itu bawaan game, bukan script ini.\nTekan tombol keluar di UI game untuk mengembalikannya.")
end

-- ============================================================
-- UANG: apa yang benar-benar bisa, dan apa yang tidak
-- ============================================================
do
    local c = makeCard("💰 MODE UANG MAKSIMUM", THEME.Green, AutoBody)

    makeInfo(c, "SOAL '+CASH DI-HACK' - jawaban jujurnya, dan ini sudah dicek\nULANG di dump V2 (RSV2TELITI / SGV2TELITI / SPSV2TELITI):\n\n  TIDAK ADA remote penambah uang. MoneyService cuma punya 7 RF:\n  RedeemCode, OpenMenu, GiftGamepass, GroupReward,\n  ClaimDailyReward, GiftProduct, BuyStarterPack.\n  Nol hasil untuk AddCash / SetCash / GiveCash / Award.\n\n  Cash & Gems hidup di Replica 'DataToken_<UserId>'. Client cuma\n  MENERIMA salinannya - ReplicaController.SetValue di sisi client\n  tidak punya FireServer sama sekali, jadi mengubahnya cuma\n  mengubah angka di layarmu (ada tombolnya di tab Extra, sudah\n  ditandai PALSU).\n\nJadi tidak ada jalan pintas. Yang ADA: menaikkan uang per menit\nsetinggi mungkin, dan itu yang dilakukan tombol di bawah.")

    local rateLbl = makeInfo(c, "-")
    task.spawn(function()
        local awal, t0 = nil, os.clock()
        local puncak = 0
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(AutoBody) do task.wait(0.4) end
            local now = angkaStat("Cash") or 0
            if awal == nil and now > 0 then awal, t0 = now, os.clock() end
            local menit = (os.clock() - t0) / 60
            local rate = (awal and menit > 0.05) and ((now - awal) / menit) or 0
            if rate > puncak then puncak = rate end
            rateLbl.Text = table.concat({
                "Cash sekarang   : " .. fmtNum(now),
                "Naik per menit  : " .. fmtNum(rate) .. "   (puncak sesi: " .. fmtNum(puncak) .. ")",
                "Checkout sesi   : " .. stats.checkout .. "     Craft: " .. stats.crafted,
                "",
                "Diukur sejak script dijalankan. Kalau angkanya 0 padahal",
                "auto menyala: toko belum dibuka, atau rak belum ada isinya.",
            }, "\n")
            task.wait(5)
        end
    end)

    makeButton(c, "💵 NYALAKAN MODE UANG MAKSIMUM", THEME.Green, function()
        task.spawn(function()
            -- 1. wadah paling menguntungkan. Spring Basket menang di DUA
            --    kriteria sekaligus (12 bunga, priceAdd +100), tapi yang
            --    dipakai tetap pembacaan runtime -- bukan hardcode.
            config.autoBigContainer  = true
            config.autoBestContainer = false
            config.autoAccents       = true

            -- 2. accent sebanyak yang diizinkan LEVEL CraftTable.
            -- Dulu baris ini membaca atribut "maxAccents" yang TIDAK ADA,
            -- jadi hasilnya selalu 2 berapapun level mejamu.
            --
            -- Sekarang 5 (mentok slider), BUKAN accentCap(). Dua alasan:
            --   * doCraftOnce sudah memotongnya ke accentCap() saat
            --     merangkai, jadi menyimpan angka cap di sini murni
            --     pengulangan - dan angka itu BASI begitu kamu upgrade
            --     Craft Table, sementara 5 ikut naik sendiri.
            --   * slider di kartu MEMAHALKAN HARGA JUAL tidak ikut
            --     digambar ulang oleh tombol ini. Dengan 5 (sama dengan
            --     bawaannya) slidernya tetap benar; dengan accentCap()
            --     dia akan menampilkan 5 sementara config-nya 2.
            config.accentCount = 5

            -- 3. semua mesin auto
            AUTO.set.panen(true)
            AUTO.set.tanam(true)
            AUTO.set.craft(true)
            AUTO.set.rak(true)
            AUTO.set.kasir(true)

            -- 4. toko HARUS buka, kalau tidak pembeli tidak datang dan
            --    meja kasir tidak pernah terisi. ToggleShopOpen itu
            --    saklar, jadi dibalik HANYA kalau memang masih tutup.
            local plot = getMyPlot()
            if plot and not plot:GetAttribute("ShopOpen") then
                invokeRF("CustomerService", "ToggleShopOpen")
                task.wait(0.3)
            end

            local nm, mx, add = biggestContainer()
            notify("MODE UANG MAKSIMUM aktif", THEME.On)
            addLog("Uang maksimum: wadah=" .. tostring(nm) ..
                   " (max " .. tostring(mx) .. " bunga, +" .. tostring(add) ..
                   "), accent=" .. config.accentCount ..
                   ", toko=" .. tostring(plot and plot:GetAttribute("ShopOpen")), "AUTO")
        end)
    end)

    makeButton(c, "⛔ MATIKAN SEMUA MESIN AUTO", THEME.Red, function()
        AUTO.set.panen(false); AUTO.set.tanam(false)
        AUTO.set.beliBibit(false); AUTO.set.beliSupply(false)
        AUTO.set.craft(false); AUTO.set.rak(false);   AUTO.set.kasir(false)
        AUTO.set.siram(false); AUTO.set.pupuk(false)
        AUTO.set.combo(false)
        -- Sakelar Auto Siram & Auto Pupuk tinggal di tab Farm dan
        -- tampilannya diurus `kunci` di makeToggle, bukan AUTO.vis. Tanpa
        -- baris ini dua-duanya tetap kelihatan ON padahal loopnya mati -
        -- persis kebohongan yang sudah kita berantas di tombol massal
        -- tab Settings.
        samakanSakelar()
        notify("Semua mesin tab Auto dimatikan", THEME.Yellow)
    end)

    makeInfo(c, "Yang dinyalakan tombol di atas:\n  wadah KAPASITAS terbesar  -> Spring Basket (12 bunga, +100)\n  accent termahal otomatis  -> sebanyak maxAccents CraftTable\n  Auto Panen + Auto Tanam   -> bahan tidak pernah habis\n  Auto Craft + Auto ke Rak  -> barang jadi terus masuk etalase\n  Auto Kasir                -> tiap pembeli langsung dilayani\n  Buka Toko                 -> tanpa ini pembeli tidak datang\n\nYang TIDAK dinyalakan otomatis karena MEMBELANJAKAN uangmu:\n\n  Auto Siram & Auto Pupuk (tab Farm) - dua-duanya MENGHABISKAN\n  supply yang harganya $100-$50.000 sebiji. Nyalakan sendiri\n  kalau kamu memang mau mempercepat, dan pasangkan dengan Auto\n  Buy SUPPLY supaya tidak kehabisan di tengah jalan.\n\n  Auto Buy BIBIT / SUPPLY (tab Shop) - jelas memotong cash.\n\n  Advertising (UpgradeService.Purchase) - naikkan sendiri di tab\n  Shop kalau cash sudah tebal; ini yang menambah jumlah &\n  kualitas pembeli, jadi dampaknya paling besar jangka panjang.\n\n  Upgrade Craft Table - menaikkan batas accent (2/3/4/5).")
end

do
    local c = makeCard("📊 STATUS & DIAGNOSA AUTO", THEME.Orange, AutoBody)

    makeSlider(c, "Jeda putaran Auto", config.autoDelay, 0.05, 2, THEME.Orange, function(v)
        config.autoDelay = v
    end)

    makeToggle(c, "Paksa TURBO di mesin Auto", THEME.Orange, function(v)
        config.autoTurbo = v
        notify(v and "Mesin Auto pakai TURBO (0.01 dtk antar panggilan)"
                  or "TURBO mesin Auto OFF - pakai delay normal tiap kategori",
               v and THEME.On or THEME.Off)
    end)(true)

    local diagLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(AutoBody) do task.wait(0.4) end
            -- MURAH (true) - kotak ini cuma MELAPORKAN. Tanpa itu, tiap
            -- 1,5 detik dia bisa memicu penyisiran SELURUH plot tiga kali
            -- (kasir + staff + craft), dan di kebun ribuan slot itulah
            -- yang bikin "pindah ke tab Auto langsung nge-lag".
            -- Alasan lengkapnya di komentar `cari`.
            local pk = AUTO.promptKasir(true)
            local ps = AUTO.promptStaff(true)
            local pc = AUTO.promptCraft(true)
            local mode
            if AUTO.jauh == nil then mode = "belum dipakai sekali pun"
            elseif AUTO.jauh    then mode = "TANPA PINDAH (lompatan mikro dimatikan)"
            else mode = "teleport SEKALI ke kasir, lalu instan, badan dikembalikan" end
            diagLbl.Text = table.concat({
                "PROMPT YANG KETEMU DI PLOT:",
                -- "belum kelihatan" BUKAN "tidak ada". Kotak ini sengaja
                -- cuma melihat Building + ingatan; penyisiran dalam
                -- dilewati karena mahal. Untuk CheckoutPrompt ini malah
                -- keadaan NORMAL - server baru membuatnya saat ada barang.
                "  CheckoutPrompt : " .. (pk and ("ADA  (" .. (pk.Enabled and "siap" or "kosong") .. ")")
                                              or "belum kelihatan (meja kosong = wajar)"),
                "  StaffPrompt    : " .. (ps and "ADA" or "belum kelihatan di Building"),
                "  CraftSpot      : " .. (pc and "ADA" or "belum kelihatan di Building"),
                "  (kotak ini pakai pencarian MURAH - yang dalam cuma jalan",
                "   saat fiturnya benar-benar dipakai, bukan untuk melapor)",
                "",
                "Barang di meja : " .. (pk and tostring(pk.ObjectText) or "-"),
                "Mode kasir     : " .. mode,
                "Cara tembak    : " .. tostring(AUTO.caraNama),
                "Executor       : fireproximityprompt " ..
                    (typeof(fireproximityprompt) == "function" and "ADA" or "TIDAK ADA") ..
                    "   |  PromptTriggered pernah bunyi: " .. tostring(AUTO.adaTrigger),
                "",
                "Loop aktif: " ..
                    ((state.autoKasir and "kasir " or "") ..
                     (state.aPanen and "panen " or "") ..
                     (state.aTanam and "tanam " or "") ..
                     (state.aBeliBibit and "beliBibit " or "") ..
                     (state.aBeliSupply and "beliSupply " or "") ..
                     (state.aSiram and "siram " or "") ..
                     (state.aPupuk and "pupuk " or "") ..
                     (state.aCraft and "craft " or "") ..
                     (state.aRak and "rak " or "") ..
                     (state.aCombo and "rangkai->rak " or "")),
            }, "\n")
            -- 3 detik, bukan 1,5. Isinya status - tidak ada yang berubah
            -- secepat itu, dan tab Auto punya tiga label hidup sekaligus.
            task.wait(3)
        end
    end)

    makeButton(c, "🔁 Ukur ulang cara tembak + mode kasir", THEME.Blue, function()
        AUTO.resetUkur()
        notify("Direset - tembakan berikutnya diukur ulang dari nol", THEME.On)
        addLog("Pengukuran cara tembak direset", "AUTO")
    end)

    -- Kalau prompt tetap "TIDAK ADA", ini yang menunjukkan nama & letak
    -- aslinya. Empat lapis pencarian sudah dicoba; kalau semuanya gagal
    -- berarti strukturnya beda dari dugaan, dan menebak lagi cuma buang
    -- waktu -- lebih cepat dilihat langsung.
    makeButton(c, "🔎 LIST SEMUA PROMPT DI PLOT (ke Output)", THEME.Purple, function()
        task.spawn(function()
            if not logEnabled then
                logEnabled = true
                outToggleBtn.Text = "Output: ON"
                outToggleBtn.BackgroundColor3 = THEME.On
            end
            local list = AUTO.daftarPrompt()
            addLog("=== " .. #list .. " ProximityPrompt di plot ===", "DIAG")
            for _, s in ipairs(list) do addLog("  " .. s, "DIAG") end
            notify(#list .. " prompt didaftar - lihat tab Output",
                   #list > 0 and THEME.On or THEME.Yellow)
            showTab("output")
        end)
    end)
end

task.wait()   -- jeda satu frame (lihat PEMBANGUNAN BERTAHAP di atas)

-- ============================================================
-- BUILD UI : TAB FARM
-- ============================================================
do
    local c = makeCard("MODE TURBO (instant)", THEME.Red, FarmBody)

    makeInfo(c, "Kenapa aksi massal lambat walau delay 0? InvokeServer itu\nYIELDING - tiap panggilan menunggu balasan server dulu.\n100 slot x ~150ms ping = 15 detik; delay berapapun tak menolong.\n\nTURBO memperbaiki dua hal:\n  1. tiap panggilan dikirim lewat task.spawn (tidak saling tunggu)\n  2. jarak antar panggilan dipangkas ke 0.01 detik")

    makeToggle(c, "TURBO - semua aksi jadi instant", THEME.Red, function(v)
        state.turbo = v
        if v then
            notify("TURBO ON - panen/tanam/jual/layani jadi paralel", THEME.On)
            addLog("TURBO ON: callRF pakai task.spawn, delay 0.01s", "INFO")
        else
            notify("TURBO OFF - kembali ke delay normal", THEME.Off)
        end
    end, "turbo")

    makeInfo(c, "BATAS SERVER: RateLimiter.Default = 120 panggilan/detik\n(toleransi antrean 1 detik). TURBO jalan di 0.01 dtk = 100/dtk,\njadi masih di bawah batas.\n\nKalau batas dilewati server MENGABAIKAN panggilan berlebih\n(bukan kick) - jadi bisa ada aksi yang tidak jadi.\nEfek samping lain: nilai balik server tidak dibaca, jadi pesan\nkegagalan per-aksi tidak muncul di Output.")

    makeInfo(c, "SAKELAR TURBO DI ATAS TETAP ADA - dia yang membuat SEMUA aksi\ninstant. Yang dihapus cuma sembilan TOMBOL 'INSTANT' yang dulu\nada di kartu ini, dan itu memang tidak menghilangkan apa pun.\n\nINSTANT itu SEKALI TEKAN SEKALI SAPU: menyisir semua slot satu\nkali lalu berhenti. Tiap-tiapnya sudah punya sakelar AUTO yang\nmengerjakan hal PERSIS SAMA, cuma berulang sendiri:\n\n  INSTANT PANEN            -> Auto Panen            (tab Auto)\n  INSTANT TANAM            -> Auto Tanam Seed       (tab Auto/Farm)\n  INSTANT SIRAM            -> Auto Siram            (kartu di bawah)\n  INSTANT PUPUK            -> Auto Pupuk            (kartu di bawah)\n  INSTANT LAYANI PEMBELI   -> Auto Layani Pesanan   (tab Farm)\n  INSTANT STOK BUNGA       -> Auto Stock Flowers    (tab Farm)\n  INSTANT STOK RANGKAIAN   -> Auto Rangkaian -> Rak (tab Auto)\n  INSTANT CRAFT MASSAL     -> Auto Craft            (tab Auto/Craft)\n  SIKLUS PENUH             -> MODE UANG MAKSIMUM    (tab Auto)")

    makeInfo(c, "SATU HAL YANG HARUS KAMU TAHU SOAL TURBO, dan ini bukan bug -\nini konsekuensi yang memang tidak bisa dihindari.\n\nTURBO = tembak-lalu-lupa (task.spawn), jadi BALASAN SERVER TIDAK\nTERBACA. Untuk panen / tanam / craft / siram / pupuk itu tidak\nmasalah: kalau ada satu yang lolos, putaran berikutnya\nmengerjakannya lagi.\n\nTapi MENGISI RAK RANGKAIAN bersandar penuh pada balasan itu -\nkapasitas rak rangkaian TIDAK ADA angkanya di client sama sekali,\njadi satu-satunya cara mengukurnya adalah PENOLAKAN server. Di\nTURBO penolakan itu tidak terbaca, jadi raknya terisi MERANGKAK:\nsatu tembakan percobaan per putaran (itu sengaja - tanpa itu dia\nmacet total, lihat 'JALAN BUNTU DI MODE TURBO' di kodenya).\n\nJadi: kalau rak rangkaian berhenti bertambah, MATIKAN TURBO\nsebentar sampai kapasitasnya terukur. Sesudah angkanya ketemu\n('PASTI N' di kartu DIAGNOSA RAK, tab Craft), TURBO boleh\ndinyalakan lagi - dia sudah tahu kapan harus berhenti.\n\nSaya TIDAK memaksa TURBO mati sendiri di loop rak: sakelar itu\nkeputusanmu, dan mematikannya diam-diam justru jenis kebohongan\nyang sedang kita berantas di hub ini.")
end

do
    local c = makeCard("🌾 AUTO FARM", THEME.Green, FarmBody)

    makeInfo(c, "'Auto Tanam Seed' ADA DI DUA TEMPAT: di sini, dan di tab ⚡ Auto.\nItu SAKELAR YANG SAMA, bukan kembar - nyalakan di sini, yang di\ntab Auto ikut menyala sendiri (dan sebaliknya).\n\nDulu memang kembar dan itu yang salah: dua sakelar punya ingatan\nsendiri-sendiri padahal loopnya cuma SATU, jadi bisa yang satu\nmenampilkan ON dan satunya OFF - tidak ada cara tahu mana yang\nbenar. Sekarang dua-duanya memanggil mesin yang sama.\n\nDitaruh di sini lagi supaya sakelarnya bersebelahan dengan\n'Seeds to Plant' - filternya. Auto Panen tetap di tab ⚡ Auto.")

    -- SAKELAR YANG SAMA dengan yang di tab Auto - lihat AUTO.pasangVis.
    -- Dia memanggil AUTO.set.tanam, jadi loopnya cuma satu dan tampilan
    -- kedua sakelar selalu ikut. Ditaruh persis di atas dropdown
    -- filternya, sesuai pola kartu-kartu lain di script ini.
    AUTO.pasangVis("tanam", makeToggle(c, "Auto Tanam Seed (instant)", THEME.Green, function(v)
        if v and setIsEmpty(sel.plantSeeds) then
            notify("Centang bibitnya dulu di 'Seeds to Plant' tepat di bawah", THEME.Yellow)
        end
        AUTO.set.tanam(v)
        notify(v and "Auto Tanam ON" or "Auto Tanam OFF", v and THEME.On or THEME.Off)
    end))

    makeMultiDropdown(c, "Seeds to Plant", seedNames, sel.plantSeeds, "None")
    makeMultiDropdown(c, "Seeds to Harvest", seedNames, sel.harvestSeeds, "Semua")

    makeToggle(c, "Auto Stock Flowers", THEME.Green, function(v)
        state.autoStock = v
        -- Sama seperti Auto Tanam: dipanggil sesudah state diisi.
        AUTO.pantauObjek(AUTO.picuPerlu())
        if v then
            startLoop("stockflower", function()
                -- Bendera yang sama dengan pemicu instan - lihat
                -- AUTO.pantauObjek.
                if PICU.bunga then return end
                PICU.bunga = true
                pcall(doStockFlowerOnce)
                PICU.bunga = false
            end, function() return config.sellDelay end)
            notify("Auto Stock Flowers ON - rak yang berkurang langsung diisi", THEME.On)
        else
            stopLoop("stockflower"); notify("Auto Stock Flowers OFF", THEME.Off)
        end
    end, "autoStock")

    makeInfo(c, "DUA SAKELAR DI ATAS SEKARANG PUNYA PEMICU INSTAN, sama seperti\nAuto Rangkaian -> Rak. Selain sapuan berkala:\n\n  Auto Tanam Seed    - begitu satu slot JADI KOSONG (dipanen),\n                       penanaman langsung berangkat ~0,3 detik\n                       kemudian, tidak menunggu Auto Delay.\n  Auto Stock Flowers - begitu stok satu rak bunga BERKURANG,\n                       pengisian langsung berangkat.\n\nSINYALNYA MILIK GAME, bukan tebakan. Komponen Planter memakai\nInstance.AttributeChanged (SPSv3 591) dan komponen FlowerDisplay\nmemakai yang sama (SPSv3 974), dua-duanya -> _updateState().\n\nBEDANYA dengan rak rangkaian: rak rangkaian menyimpan isinya\nsebagai ANAK folder, jadi sinyalnya ChildRemoved. Planter dan rak\nbunga menyimpannya sebagai ATRIBUT, jadi sinyalnya\nAttributeChanged. Tiga jenis objek, tiga bentuk data, dan hub\nmengikuti bentuk aslinya masing-masing - tidak dipaksa seragam.\n\nAttributeChanged menyala untuk SETIAP atribut, dan planter punya\natribut yang berdetak sendiri saat tanaman tumbuh (Stage, Ready,\nPlantedAt). Kalau tidak disaring, satu kebun yang sedang tumbuh\nmembanjiri pemicu ini nonstop. Jadi disaring dari NAMA atributnya:\nplanter cuma bereaksi ke 'Slot_<i>_Seed', rak bunga cuma ke\n'Stock_<nama>'. Dua-duanya berubah TEPAT saat isinya berubah.\n\nSAPUAN BERKALA TIDAK DIGANTI, dan ini bukan kehati-hatian\nberlebihan: komponen Planter milik game sendiri pun memasang\nAttributeChanged DAN loop task.wait(1) berdampingan (SPSv3\n598-603). Event bisa meleset; sapuan yang menangkapnya.\n\nYANG TIDAK SAYA KLAIM: hub tidak bisa membedakan 'diambil\npembeli' dari 'kamu sendiri yang ambil'. Sinyalnya sama persis.\nYang dikejar memang 'berkurang -> isi lagi', bukan menebak siapa.")
    -- Nama MODEL didahulukan, nama layar di dalam kurung. Sengaja begitu:
    -- yang disimpan sebagai kunci HARUS nama model (itu yang dipakai
    -- MenuConfig.Flowers maupun rumus harga), sementara yang kamu lihat di
    -- game dan di teks pesanan pelanggan adalah displayName. Contoh:
    -- model "PurpleLily" tampil sebagai "Purple Lily". stripLabel
    -- mengembalikan bagian sebelum kurung, jadi kuncinya tetap benar.
    makeMultiDropdown(c, "Flowers to Stock", function()
        local f = assetFolder("Flowers")
        local out = {}
        if f then
            for _, m in ipairs(f:GetChildren()) do
                local dn = m:GetAttribute("displayName")
                out[#out + 1] = m.Name ..
                    ((dn and tostring(dn) ~= m.Name) and ("  [" .. tostring(dn) .. "]") or "")
            end
        end
        table.sort(out)
        return out
    end, sel.stockFlowers, "Semua", stripLabel)

    -- PENJAGA: pemicu instan dan loop jaring-pengaman bisa jalan bersamaan.
    -- Tanpa ini dua-duanya bisa melompat ke pembeli berbarengan dan saling
    -- menimpa posisi. Semua yang mau melayani lewat serveNow().
    local busy = false
    local function serveNow()
        if busy then return end
        busy = true
        local ok, n, why = pcall(doCheckoutOnce)
        busy = false
        if ok and n and n > 0 then
            notify("Dilayani " .. n .. " pesanan", THEME.On)
        elseif ok and why and why ~= "tidak ada custom order yang aktif" then
            addLog("Auto layani: " .. tostring(why), "FARM")
        end
    end

    -- PEMICU INSTAN. Server memasang CustomOrderPrompt begitu pembeli minta
    -- pesanan; kita menempel ke DescendantAdded folder Customers, jadi
    -- dilayani DETIK ITU JUGA - tidak menunggu putaran loop berikutnya.
    local orderConn
    local function watchOrders()
        if orderConn and orderConn.Connected then return end
        local plot = getMyPlot()
        local customers = plot and plot:FindFirstChild("Customers")
        if not customers then return end
        orderConn = customers.DescendantAdded:Connect(function(d)
            if not state.autoCheckout then return end
            if d.Name ~= "CustomOrderPrompt" then return end
            task.wait(0.15)   -- beri server waktu mengisi ObjectText + Enabled
            serveNow()
        end)
        track(orderConn)
    end

    makeToggle(c, "Auto Layani Pesanan (Deliver Order)", THEME.Green, function(v)
        state.autoCheckout = v
        if v then
            -- Peringatan "executor tidak punya fireproximityprompt" DIHAPUS:
            -- jalur utamanya sekarang InputHoldBegin/End (API Roblox biasa),
            -- jadi fitur ini tidak lagi bergantung pada executor.
            watchOrders()
            serveNow()   -- sapu yang sudah menunggu sekarang
            -- Loop ini JARING PENGAMAN, bukan mesin utamanya: kalau pemicu
            -- instan meleset (plot baru dimuat, folder Customers diganti),
            -- ini yang menangkap. Saat tidak ada pesanan doCheckoutOnce
            -- berhenti cepat dan TIDAK melompat, jadi murah dipanggil sering.
            startLoop("checkout", function()
                watchOrders()   -- pasang ulang kalau koneksinya putus
                serveNow()
            end, function() return math.max(config.farmDelay, 0.5) end)
            notify("Auto Layani Pesanan ON - instan 🧾", THEME.On)
        else
            stopLoop("checkout")
            if orderConn then pcall(function() orderConn:Disconnect() end); orderConn = nil end
            notify("Auto Layani Pesanan OFF", THEME.Off)
        end
    end, "autoCheckout")

    -- Sakelar "Pindah ke pembeli dulu" DIHAPUS dari sini: KEMBAR dengan
    -- "Dekati dulu sebelum tekan E" di tab Auto. Dua-duanya menyalakan hal
    -- yang sama (config.dekatiDulu), memanggil mesin yang sama
    -- (dekatiPrompt), dan ada karena alasan yang sama - CheckoutPrompt dan
    -- CustomOrderPrompt sama-sama dibuat SERVER dengan jarak 10 stud.
    makeInfo(c, "Sakelar 'Pindah ke pembeli dulu' pindah ke tab ⚡ Auto\n('Dekati dulu sebelum tekan E'). Dulu ada DUA sakelar terpisah -\nsatu untuk pembeli di sini, satu untuk kasir di sana - padahal\nisinya sama persis: dua-duanya memanggil mesin dekati yang sama,\nkarena CustomOrderPrompt dan CheckoutPrompt sama-sama dibuat\nSERVER dengan jarak 10 stud. Jadi yang kembar dibuang, dan\nsekarang satu sakelar mengurus keduanya.")

    local orderLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(FarmBody) do task.wait(0.4) end
            local list = customOrderList()
            local lines
            if #list == 0 then
                lines = { "PESANAN AKTIF: (tidak ada)", "",
                          "Pesanan muncul sendiri saat toko buka." }
            else
                lines = { "PESANAN AKTIF (" .. #list .. ") - minta barang ini:" }
                for i, o in ipairs(list) do
                    if i > 8 then
                        lines[#lines + 1] = "  ... (+" .. (#list - 8) .. " lagi)"
                        break
                    end
                    lines[#lines + 1] = "  " .. i .. ". " .. o
                end
            end
            orderLbl.Text = table.concat(lines, "\n")
            task.wait(2)
        end
    end)

    makeInfo(c, "RALAT PENTING. Versi lama kartu ini menulis 'tidak ada prompt di\nkasir'. ITU SALAH - dump workspace yang dipakai waktu itu memang\nbelum memuatnya. Dump V2 membuktikan kasirnya ADA:\n\n  Building.Register.ItemHolder.CheckoutPrompt\n     ActionText 'Checkout', jarak 10, tahan 0.5\n\nKasir itu ditangani di tab AUTO (kartu 'AUTO KLIK E DI KASIR').\nKartu INI mengurus yang lain: CustomOrderPrompt, yang menempel di\nPEMBELI-nya sendiri:\n  ActionText  = Deliver Order\n  HoldDuration= 0.5 detik  -> dinolkan dulu, jadi INSTAN\n  jarak       = 10 stud\n\nDua-duanya beda urusan, jadi boleh dinyalakan bersamaan.")

    makeInfo(c, "'E'-NYA NYASAR KE NPC QUEST - ini sebabnya, dan sekarang ditutup\ndi AKARNYA, bukan ditambal.\n\nSebagian executor menjalankan fireproximityprompt bukan dengan\nmenyentuh prompt yang kita kirim, tapi dengan MENIRU TEKANAN\nTOMBOL E. Roblox lalu mengarahkan E itu ke prompt yang SEDANG DIA\nPILIH - dan pilihannya cuma SATU untuk seluruh layar (Exclusivity\nbawaannya OneGlobally). Begitu kita pindah ke sebelah pembeli,\nNPC Quest yang kebetulan berdiri dekat situ bisa MEREBUT giliran\nitu, dan E-nya mendarat di dia.\n\nDUA TAMBALAN LAMA yang ternyata TIDAK CUKUP:\n  * mematikan semua prompt lain selama menembak - bocor, karena\n    daftarnya di-cache 5 detik jadi prompt yang BARU LAHIR tidak\n    ikut dimatikan. Sekarang cache-nya 1 detik.\n  * Exclusivity = AlwaysShow pada sasaran - tetap tidak menjamin\n    dialah yang dipilih Roblox.\n\nYANG SEKARANG DIPAKAI: untuk kasir & pesanan, fireproximityprompt\nTIDAK DIPAKAI SAMA SEKALI. Cuma p:InputHoldBegin() / InputHoldEnd()\nyang dipanggil LANGSUNG pada objek promptnya - itu tidak bisa\ndibelokkan ke prompt lain, apapun executornya.\n\nJadi jangan dihapus: fiturnya sudah tidak bisa nyasar lagi. Kalau\nprompt-nya memang tidak mau menerima, laporannya GAGAL jujur -\nbukan menekan E entah di mana.")

    makeInfo(c, "YANG TIDAK BISA DIJANJIKAN: pesanan minta BARANG tertentu\n(lihat daftar di atas, mis. 'Big Bouquet (Lily Of The Valley,\nPurple Calla Lily)'). Kalau barangnya tidak ada di inventory,\nserver yang menolak - itu di luar jangkauan client. Rangkai\ndulu yang diminta.")

    makeSlider(c, "Farm Delay", config.farmDelay, 0.05, 2, THEME.Green, function(v) config.farmDelay = v end)
end

-- ============================================================
-- AUTO SIRAM & AUTO PUPUK - dua kartu lama digabung jadi satu
-- ============================================================
-- Dulu ada DUA kartu yang mengurus hal yang sama lewat jalur berbeda,
-- dan dua-duanya memakai SATU merek dari dropdown tanpa memilih:
--     "SUPPLY (Siram / Pupuk / Lock)"  -> doSupplyOnce
--     "INSTANT GROW (spam siram)"      -> doInstantGrowOnce
-- Keduanya dibuang. Mesinnya sekarang habisSupply(), dan arti dropdown-
-- nya BERUBAH: dari "pakai yang ini" jadi "yang BOLEH dipakai" - kosong
-- berarti semua yang ada di tas.
do
    local c = makeCard("💧 AUTO SIRAM & AUTO PUPUK (ke tanaman)", THEME.Cyan, FarmBody)

    makeToggle(c, "AUTO SIRAM ke tanaman", THEME.Cyan, function(v)
        AUTO.set.siram(v)
        notify(v and "Auto Siram ON - kaleng dipilih yang paling PAS per slot"
                  or "Auto Siram OFF", v and THEME.On or THEME.Off)
    end, "aSiram")

    makeMultiDropdown(c, "Kaleng yang BOLEH dipakai",
        function() return supplyLabels("WateringCan") end,
        sel.canSiram, "semua", stripLabel)

    makeToggle(c, "AUTO PUPUK ke tanaman", THEME.Green, function(v)
        AUTO.set.pupuk(v)
        notify(v and "Auto Pupuk ON - disebar RATA, ada jatah per penanaman"
                  or "Auto Pupuk OFF", v and THEME.On or THEME.Off)
    end, "aPupuk")

    makeMultiDropdown(c, "Pupuk yang BOLEH dipakai",
        function() return supplyLabels("Fertilizer") end,
        sel.pupukPakai, "semua", stripLabel)

    -- Kotak hitungan. Yang ditampilkan sekarang: mana yang BELUM dilayani
    -- dan mana yang sudah - itu pertanyaan aslinya, dan sekarang bisa
    -- dijawab tanpa menebak.
    local siramLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan (lihat tampil()).
            while ScreenGui.Parent and not tampil(FarmBody) do task.wait(0.4) end

            local nGrow, remain = growSummary()
            local supF = assetFolder("Supplies")

            -- INI JAWABAN "deteksi slot yang belum disiram / dipupuk".
            -- Dua sumber yang berbeda, dan bedanya penting:
            --   siram -> tidak ada atributnya, jadi dari INGATAN hub
            --            (slotSudah, kedaluwarsa sendiri per tahap)
            --   pupuk -> dari CATATAN SERVER (Slot_i_Variants), jadi
            --            benar walau hub baru saja dijalankan
            local seedF = assetFolder("Seeds")
            local belumAir, sudahAir, belumPupuk, mentokPupuk = 0, 0, 0, 0
            for _, planter in ipairs(getMyPlanters()) do
                local slots = planter:GetAttribute("Slots") or 1
                for i = 1, slots do
                    local seed = planter:GetAttribute("Slot_" .. i .. "_Seed")
                    if seed and seed ~= ""
                       and not planter:GetAttribute("Slot_" .. i .. "_Ready") then
                        if slotSudah("WateringCan", planter, i) then
                            sudahAir = sudahAir + 1
                        else
                            belumAir = belumAir + 1
                        end
                        local sm = seedF and seedF:FindFirstChild(seed)
                        local kini = slotYield(planter, i,
                            tonumber(sm and sm:GetAttribute("yield")) or 0)
                        if kini >= 6 then mentokPupuk = mentokPupuk + 1
                        else belumPupuk = belumPupuk + 1 end
                    end
                end
            end

            local baris = {
                "Slot sedang tumbuh : " .. nGrow,
                "Total sisa waktu   : " .. fmtDur(remain),
                "",
                "SIRAM  - belum disiram  : " .. belumAir ..
                    "   (bisa disiram SEKARANG)",
                "         sudah disiram  : " .. sudahAir ..
                    "   (tunggu tahap tumbuh berikutnya)",
                "PUPUK  - belum mentok   : " .. belumPupuk ..
                    "   (hasil panennya masih di bawah 6)",
                "         sudah mentok   : " .. mentokPupuk ..
                    "   (6 bunga, tidak ditembak lagi)",
                "",
                "KALENG DI TAS (yang boleh dipakai):",
            }

            -- SATU sapuan tas, dikelompokkan per merek. Count ikut
            -- dijumlah: supply BERTUMPUK, jadi satu Tool bisa berarti
            -- enam pemakaian (lihat hotbar game: "x6").
            local punya, potong, adaKaleng = {}, 0, false
            local nPupuk = 0
            for _, t in ipairs(allTools()) do
                local m = supF and supF:FindFirstChild(t.Name)
                local jenis = m and m:GetAttribute("SupplyType")
                local cnt = math.max(tonumber(t:GetAttribute("Count")) or 1, 1)
                if jenis == "WateringCan" and setAllows(sel.canSiram, t.Name) then
                    punya[t.Name] = (punya[t.Name] or 0) + cnt
                    potong = potong + cnt * (tonumber(m:GetAttribute("timeReduction")) or 0)
                elseif jenis == "Fertilizer" and setAllows(sel.pupukPakai, t.Name) then
                    nPupuk = nPupuk + cnt
                end
            end
            local nKaleng = 0
            for nm, cnt in pairs(punya) do
                adaKaleng = true
                nKaleng = nKaleng + cnt
                local m = supF and supF:FindFirstChild(nm)
                baris[#baris + 1] = string.format("  %-22s x%-4d  -%s dtk/biji",
                    nm, cnt, tostring(m and m:GetAttribute("timeReduction") or "?"))
            end
            if not adaKaleng then baris[#baris + 1] = "  (tidak ada)" end

            baris[#baris + 1] = ""
            -- YANG DIBANDINGKAN: kaleng vs SLOT yang boleh disiram sekarang.
            -- BUKAN "total potong vs total sisa waktu" seperti versi lama -
            -- angka itu menyesatkan, karena satu slot cuma boleh disiram
            -- SEKALI per tahap, jadi seluruh kalengmu memang TIDAK BISA
            -- dipakai sekaligus walau totalnya kelihatan cukup.
            baris[#baris + 1] = "Kaleng di tas : " .. nKaleng ..
                "   untuk " .. belumAir .. " slot yang boleh disiram sekarang"
            baris[#baris + 1] = (nKaleng >= belumAir)
                and "  -> CUKUP untuk giliran ini"
                or ("  -> kurang " .. (belumAir - nKaleng) .. " kaleng untuk giliran ini")
            baris[#baris + 1] = "Total potong kalau semuanya terpakai : " ..
                fmtDur(potong) .. "   (dari sisa " .. fmtDur(remain) .. ")"
            baris[#baris + 1] = "  itu BATAS ATAS lintas beberapa tahap, bukan sekali jalan"
            baris[#baris + 1] = ""
            baris[#baris + 1] = "Pupuk di tas : " .. nPupuk ..
                "   untuk " .. belumPupuk .. " slot yang belum mentok"
            siramLbl.Text = table.concat(baris, "\n")
            task.wait(3)
        end
    end)

    makeInfo(c, "KENAPA BUKAN 'PAKAI YANG TERKUAT' - ini pemborosan terbesar di\nfitur siram, dan tombol lama justru melakukannya.\n\nTiap kaleng memotong waktu TETAP dan uses = 1. Jadi slot yang cuma\nkurang 60 detik lalu disiram Godly (-18.000 dtk) MEMBUANG 17.940\ndetik - hangus, tidak ada kembalian.\n\nAturan Auto Siram sekarang: ambil kaleng TERBESAR yang masih DI\nBAWAH sisa waktu slot. Kalau tidak ada yang cukup kecil, ambil yang\nTERKECIL - itu yang paling sedikit ruginya. Kalau sisa waktunya\ntidak terbaca (PlantedAt / growTime tidak ada), juga ambil yang\nterkecil.\n\nDropdown 'Kaleng yang BOLEH dipakai' untuk kalau kamu mau lebih\nketat lagi: centang Watering Can biasa saja, maka Godly & Diamond\nDISIMPAN walaupun ada di tas.")

    makeInfo(c, "SIRAM ITU SEKALI PER SLOT - INI YANG TERUKUR DARI LOG-MU.\n\nTembakan kedua ke slot yang sama dijawab server 'Already watered'.\nJadi harapan lama 'siram terus sampai matang' memang TIDAK BISA -\ndan slider 'Max siram / slot' yang dulu ada di kartu ini SUDAH\nDIHAPUS, karena angka 30 atau 100 di situ tidak pernah bisa\ntercapai. Kontrol yang tidak berpengaruh apa pun itu bohong.\n\nAKIBATNYA DULU: tiap slot dapat 1 siraman BERHASIL + 1 tembakan\nDITOLAK, lalu putaran berikutnya (2 detik) SEMUANYA ditolak lagi.\n15 slot = 15 panggilan sampah tiap dua detik, selamanya.\n\nSEKARANG slot yang sudah dilayani DILEWATI, persis seperti rak\npenuh dilewati. Ingatannya kedaluwarsa sendiri dari DUA arah:\n\n  Slot_i_PlantedAt -> siram MEMUNDURKANNYA, tanam ulang\n                      MELOMPATKANNYA ke depan. PlantedAt yang lebih\n                      besar dari yang dicatat = penanaman BARU.\n  Slot_i_Stage     -> naik seiring tumbuh, jadi tiap tahap dapat\n                      satu percobaan lagi.\n\nJadi kalau ternyata server membuka siram per TAHAP, hub otomatis\nmenyiram lagi di tahap berikutnya - tanpa perlu diberitahu. Kalau\nternyata sekali per penanaman, ongkosnya cuma 2-3 panggilan per\ntanaman, bukan 15 tiap dua detik.\n\nClient game sendiri TIDAK punya penanda ini: controllernya cuma\nmemeriksa Slot_i_Ready (SPSV2TELITI 639-663). Itu sebabnya di game\npun kamu bisa menekan Water lalu dapat 'Already watered'.")

    makeInfo(c, "AUTO PUPUK: JATAHNYA SEKARANG DIBACA, BUKAN DITEBAK LAGI.\n\nSaya ketemu atribut yang selama ini terlewat: Slot_i_Variants.\nIsinya daftar bunga yang akan DIPANEN dari slot itu, dipisah koma,\nsatu entri satu bunga - jadi JUMLAHNYA = hasil panen slot itu\nSEKARANG, sudah termasuk pupuk yang pernah masuk.\n\nContoh nyata dari dump: Slot_1_Variants = 'Orchid,Orchid,Orchid,\nOrchid' pada Orchid Seed yang yield-nya 4. Cocok persis.\n\nDan ini catatan SERVER, bukan hitungan kita: client game TIDAK\nPERNAH membacanya (nol call-site), jadi angkanya tidak mungkin\nbasi karena UI belum dibuka.\n\nJadi jatah pupuk = 6 - angka itu (maxYield 6). Slot yang sudah 6\nDILEWATI tanpa ditembak sama sekali - tidak perlu menunggu\npenolakan server dulu. Versi sebelumnya memakai '6 - yield BIBIT',\nyang berarti slot yang sudah dipupuk tetap dihitung dari nol.\n\nSatu putaran tetap = satu pupuk per slot (disebar RATA), supaya\ntidak ada slot yang ditumpuk sampai mentok sementara slot lain\nbelum kebagian.\n\nBONUSNYA: pertanyaan lama 'maxYield 6 itu batas TOTAL atau batas\nBONUS?' sekarang TERJAWAB SENDIRI. Sesudah tiap pupuk berhasil,\nhub membaca ulang Variants. Kalau angkanya naik, itu bukti batas\nitu TOTAL - dan sekali terbukti, catatannya muncul di Output:\n'TERUKUR: pupuk menaikkan Slot_Variants 4 -> 5'.")

    makeInfo(c, "SEMBILAN SUPPLY YANG ADA, LENGKAP DENGAN ANGKANYA. Ini terukur -\nsaya bongkar blob atribut tiap model di dump, bukan dikira-kira.\n\nPOTONG WAKTU TUMBUH (uses 1x, sekali pakai habis):\n  Watering Can           -60 dtk      $100    5 gem\n  Silver Watering Can    -300 dtk     $500    15 gem\n  Golden Watering Can    -900 dtk     $2.500  30 gem\n  Diamond Watering Can   -7.200 dtk   $10.000 50 gem\n  Godly Watering Can     -18.000 dtk  $50.000 100 gem\n\nTAMBAH HASIL PANEN (ini TIGA barang berbeda, bukan satu):\n  Fertilizer          bonusYield 1   $500     15 gem\n  Quality Fertilizer  bonusYield 2   $2.000   25 gem\n  Premium Fertilizer  bonusYield 3   $5.000   40 gem\n  Ketiganya maxYield = 6.\n\nLOCK: $250, 10 gem, uses = 20. TIDAK dipakai hub ini sama sekali -\ndia melindungi bunga dari panen, dan itu justru kebalikan dari yang\nkita mau. Kalau suatu saat perlu, pakai KONSOL REMOTE UNIVERSAL di\ntab Settings.\n\nSupply BERTUMPUK lewat atribut Count (lihat hotbar game: 'x6'),\njadi satu Tool bisa berarti enam pemakaian - bukan satu. Kotak\nhitungan di atas sudah memakai Count, bukan jumlah Tool.")
end

do
    local c = makeCard("🔬 DIAGNOSA FARM (baca data server)", THEME.Blue, FarmBody)

    makeInfo(c, "KARTU 'INSTANT GROW' DIHAPUS, isinya pindah ke kartu AUTO SIRAM\n& AUTO PUPUK di atas - lengkap dengan kotak hitungan 'butuh berapa\nvs punya berapa'.\n\nYang tersisa di sini cuma dua tombol BACA DATA: keduanya tidak\nmengubah apa pun di game, cuma mencetak balasan server ke tab\nOutput.\n\nSATU HAL YANG TETAP BENAR dan tidak berubah: TIDAK ADA remote\ninstant-grow di game ini. GrowingService cuma punya PlantSeed /\nHarvest / ApplySupply / GetPlanterInfo / GetAvailableSeeds.\nKesiapan panen dihitung SERVER dari Slot_i_PlantedAt + growTime,\njadi satu-satunya cara mempercepat tanpa Robux memang MENYIRAM.\n\nRALAT: kartu ini dulu menulis 'SIRAM BERULANG'. Itu SALAH, dan\nsekarang terukur: tembakan kedua ke slot yang sama dijawab server\n'Already watered'. Jadi satu slot cuma boleh disiram SEKALI (per\ntahap tumbuh) - bukan berulang sampai matang. Alasan lengkapnya\ndi kartu AUTO SIRAM & AUTO PUPUK di atas.")

    makeButton(c, "📊 Info Planter (GetPlanterInfo)", THEME.Blue, function()
        task.spawn(function()
            local list = getMyPlanters()
            if #list == 0 then notify("Tidak ada planter", THEME.Yellow); return end
            local ok, info = invokeRF("GrowingService", "GetPlanterInfo", list[1])
            addLog("GetPlanterInfo(" .. list[1].Name .. ") -> " .. tostring(ok) .. " " ..
                   (type(info) == "table" and "table" or tostring(info)), "FARM")
            if type(info) == "table" then
                for k, v in pairs(info) do addLog("   " .. tostring(k) .. " = " .. tostring(v), "FARM") end
            end
            notify("Info planter dikirim ke Output", THEME.On)
        end)
    end)

    makeButton(c, "🌱 Bibit Tersedia (GetAvailableSeeds)", THEME.Blue, function()
        task.spawn(function()
            local ok, seeds = invokeRF("GrowingService", "GetAvailableSeeds")
            if ok and type(seeds) == "table" then
                local n = 0
                for k, v in pairs(seeds) do
                    n = n + 1
                    addLog("   " .. tostring(k) .. " = " .. tostring(v), "FARM")
                end
                notify("GetAvailableSeeds: " .. n .. " entri (lihat Output)", THEME.On)
            else
                notify("Gagal baca GetAvailableSeeds", THEME.Red)
            end
        end)
    end)
end

-- ============================================================
-- BIBIT MANA YANG SEBENARNYA PALING UNTUNG
-- ============================================================
-- Kartu ini lahir dari satu penemuan: harga jual dihitung
--     harga = priceAdd WADAH + priceBase TIAP BUNGA
-- (RSV2TELITI 1466176-1466190), dan priceBase antar bunga bedanya
-- ratusan kali lipat. Jadi "bibit mahal" belum tentu "bibit untung" -
-- yang menentukan adalah priceBase bunganya, yield bibitnya, dan
-- berapa lama dia tumbuh.
--
-- SEMUA angkanya dibaca RUNTIME dari atribut aset, tidak ada yang
-- di-hardcode - jadi kalau developer menambah bibit baru atau mengubah
-- harganya, tabel ini ikut benar dengan sendirinya.
--
-- Dua kolom, dan keduanya perlu karena menjawab pertanyaan berbeda:
--   $/detik  -> kalau kamu SERING panen (auto panen + auto tanam nyala,
--               kamu menonton). Bibit murah-cepat menang di sini.
--   $/panen  -> kalau kamu DITINGGAL lama. Slot cuma matang sekali,
--               jadi yang penting nilai satu kali panennya.
--
-- Rumus waktu tumbuh = growTime x 3 (MenuConfig: growTime x
-- (#GrowthStages - 1), dan GrowthStages ada 4: Seed, Sprout, Leaf,
-- Bloom). Kalau kamu punya 2XGrowSpeed, $/detik-nya jadi dua kali.
do
    local c = makeCard("💹 BIBIT PALING UNTUNG (terukur)", THEME.Green, FarmBody)

    makeInfo(c, "Ini BUKAN daftar bibit termahal - ini daftar bibit paling\nMENGUNTUNGKAN, dihitung dari tiga atribut asli:\n\n   nilai satu panen = priceBase BUNGA x yield BIBIT\n   waktu satu panen = growTime x 3\n\nKenapa perlu dua kolom:\n  $/detik = untuk kamu yang sering panen (auto nyala, ditunggu)\n  $/panen = untuk kamu yang ditinggal lama (slot matang sekali)\n\nBibit ber-tanda [PACK] tidak dijual di toko - cuma keluar dari\npaket bibit, jadi jangan diandalkan untuk auto-buy.")

    local untungLbl = makeInfo(c, "menghitung...")

    -- Peringkat dihitung ULANG tiap kali tab Farm dibuka, bukan sekali
    -- di awal: levelmu naik, dan bibit yang kebuka ikut berubah.
    task.spawn(function()
        while ScreenGui.Parent do
            while ScreenGui.Parent and not tampil(FarmBody) do task.wait(0.4) end

            local seedF, flowF = assetFolder("Seeds"), assetFolder("Flowers")
            local myLvl = myLevel()
            local rows = {}
            if seedF and flowF then
                for _, s in ipairs(seedF:GetChildren()) do
                    local need  = tonumber(s:GetAttribute("requiredLevel")) or 1
                    local grow  = tonumber(s:GetAttribute("growTime")) or 0
                    local yield = tonumber(s:GetAttribute("yield")) or 1
                    local fnm   = s:GetAttribute("flower")
                    local fm    = fnm and flowF:FindFirstChild(tostring(fnm))
                    local base  = tonumber(fm and fm:GetAttribute("priceBase")) or 0
                    if grow > 0 and base > 0 then
                        local perPanen = base * yield
                        rows[#rows + 1] = {
                            nm    = s.Name,
                            panen = perPanen,
                            detik = perPanen / (grow * 3),
                            lvl   = need,
                            buka  = (myLvl == nil) or (need <= myLvl),
                            pack  = s:GetAttribute("seedPack"),
                        }
                    end
                end
            end

            if #rows == 0 then
                untungLbl.Text = "Assets.Seeds / Assets.Flowers belum termuat."
            else
                -- ============================================================
                -- DIURUT $/PANEN, BUKAN $/DETIK - dan ini keputusan sadar
                -- ============================================================
                -- Kalau diurut $/detik, yang menang justru bibit paling
                -- murah: Rose Seed tumbuh 15 detik (growTime 5 x 3) dengan
                -- yield 6, jadi ~1,6 per detik. Orchid Seed 38.880 detik
                -- (10,8 jam) cuma ~1,25 per detik.
                --
                -- TAPI angka itu menyesatkan di game ini, karena yang JADI
                -- REBUTAN bukan waktu - melainkan SLOT dan RAK. Satu panen
                -- Rose menghasilkan 6 bunga senilai 24; satu panen Orchid
                -- menghasilkan 4 bunga senilai 48.476. Dua ribu kali lipat,
                -- memakai LEBIH SEDIKIT slot.
                --
                -- Jadi selama rak & backpack yang jadi batas (dan di plot
                -- ini memang begitu), yang benar adalah $/panen. Kolom
                -- $/detik tetap ditampilkan supaya kamu bisa menilai
                -- sendiri kalau suatu saat batasnya berubah jadi waktu.
                table.sort(rows, function(a, b)
                    if a.buka ~= b.buka then return a.buka end
                    return a.panen > b.panen
                end)
                local baris = {
                    "Level kamu: " .. (myLvl or "tidak terbaca") ..
                        "    (" .. #rows .. " bibit punya angka lengkap)",
                    "",
                    string.format("%-24s %9s %10s %6s", "bibit", "$/detik", "$/panen", "Lv"),
                }
                for i = 1, math.min(12, #rows) do
                    local r = rows[i]
                    baris[#baris + 1] = string.format("%-24s %9.2f %10s %6d%s%s",
                        r.nm, r.detik, fmtNum(r.panen), r.lvl,
                        r.buka and "" or "  TERKUNCI",
                        r.pack and "  [PACK]" or "")
                end
                baris[#baris + 1] = ""
                baris[#baris + 1] = "Dibaca langsung dari atribut aset: growTime, yield,"
                baris[#baris + 1] = "requiredLevel, seedPack (bibit) + priceBase (bunga)."
                untungLbl.Text = table.concat(baris, "\n")
            end
            task.wait(6)
        end
    end)

    makeInfo(c, "CARA PAKAI PALING SEDERHANA:\n\n  1. lihat baris teratas yang TIDAK bertanda TERKUNCI / [PACK]\n  2. centang bibit itu di 'Seeds to Plant' DAN 'Seeds to Buy'\n  3. nyalakan Auto Tanam + Auto Buy Bibit + Auto Panen\n\nKENAPA DIURUT $/PANEN, BUKAN $/DETIK - ini bukan selera.\n\nKalau diurut per detik, pemenangnya Rose Seed: tumbuh 15 detik,\nyield 6, jadi ~1,6 per detik. Orchid Seed butuh 10,8 JAM dan cuma\n~1,25 per detik. Sekilas Rose menang.\n\nTapi hitung isinya: satu panen Rose = 6 bunga senilai 24. Satu\npanen Orchid = 4 bunga senilai 48.476. DUA RIBU kali lipat, dan\nmemakai LEBIH SEDIKIT slot.\n\nDi game ini yang jadi rebutan bukan waktu - tapi SLOT planter,\nSLOT backpack, dan RAK. Selama itu batasnya, $/panen yang benar.\nKolom $/detik tetap ada supaya kamu bisa menilai sendiri kalau\nsuatu saat batasnya berubah.")
end

do
    local c = makeCard("⚡ AKSI CEPAT", THEME.Orange, FarmBody)

    -- Tiga tombol sekali-jalan DIHAPUS dari sini (Panen Sekarang, Tanam
    -- Sekarang, Layani Pesanan Sekarang). Ketiganya memanggil fungsi yang
    -- PERSIS SAMA dengan tombol INSTANT di kartu MODE TURBO tab ini juga
    -- - cuma beda TURBO dipaksa atau tidak. Pakai yang INSTANT di atas.
    makeInfo(c, "Tombol sekali-jalan (panen / tanam / layani pesanan) ada di\nkartu MODE TURBO paling atas tab ini - versi INSTANT. Yang dulu\nkembar di kartu ini sudah dibuang.")

    makeToggle(c, "Crop ESP (highlight siap panen)", THEME.Orange, function(v)
        state.cropEsp = v
        if v then startLoop("cropesp", refreshCropEsp, function() return 2 end)
        else stopLoop("cropesp"); clearCropEsp() end
    end, "cropEsp")

    local lbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(FarmBody) do task.wait(0.4) end
            local nP, total, ready, growing, empty, locked = farmSummary()
            lbl.Text = string.format(
                "Planter: %d   Slot total: %d\nSiap panen: %d   (locked %d)\nSedang tumbuh: %d   Kosong: %d",
                nP, total, ready, locked, growing, empty)
            task.wait(1.5)
        end
    end)
end

task.wait()   -- jeda satu frame (lihat PEMBANGUNAN BERTAHAP di atas)

-- ============================================================
-- BUILD UI : TAB SHOP
-- ============================================================
do
    local c = makeCard("🛒 AUTO SHOP", THEME.Yellow, ShopBody)

    makeInfo(c, "DIPISAH LAGI JADI DUA, dan ini alasannya - bukan cuma selera.\n\nWaktu digabung, satu sakelar mengurus dua toko sekaligus. Untuk\nbeli SUPPLY saja kamu tetap harus mengosongkan 'Seeds to Buy',\ndan tidak ada apa pun di layar yang memberitahu keharusan itu.\nSekarang tiap toko punya sakelarnya sendiri, bersebelahan dengan\ndropdown filternya.\n\nKeduanya juga ada di tab ⚡ Auto - itu SAKELAR YANG SAMA, bukan\nkembar: nyalakan di sini, yang di sana ikut menyala.\n\nCatatan jujur: yang ini TIDAK memakai TURBO. buyFromShop selalu\nmemakai Shop Delay (bawaannya 0,5 dtk per item) supaya balasan\nserver TERBACA - dan balasan itu sekarang benar-benar dibaca,\nlihat kartu di bawah.")

    -- SAKELAR YANG SAMA dengan yang di tab Auto - lihat AUTO.pasangVis.
    AUTO.pasangVis("beliBibit", makeToggle(c, "Auto Buy BIBIT (SeedShop)", THEME.Yellow, function(v)
        if v and setIsEmpty(sel.buySeeds) then
            notify("Centang bibitnya dulu di dropdown tepat di bawah", THEME.Yellow)
        end
        AUTO.set.beliBibit(v)
        notify(v and "Auto Buy Bibit ON" or "Auto Buy Bibit OFF", v and THEME.On or THEME.Off)
    end))
    -- ============================================================
    -- TUJUH BIBIT INI TIDAK PERNAH DIJUAL DI TOKO
    -- ============================================================
    -- Assets.Seeds berisi 35 bibit, tapi yang bisa MASUK STOK toko cuma
    -- yang atribut seedPack-nya kosong. Aturannya di MenuConfig sendiri
    -- (RSV2TELITI 1466134-1466137):
    --     for k, v in pairs(t.Seeds) do
    --         if (v.requiredLevel or 1) <= p1 and v.seedPack == nil then
    --
    -- Yang punya seedPack cuma keluar dari PAKET BIBIT, bukan dari toko:
    --     Legendary Seed Pack -> Ranunculus, Flame Lily, Lotus,
    --                            Bird of Paradise
    --     Rare Seed Pack      -> Ixora, Echium, Queen of the Night
    --
    -- Dulu dropdown ini mendaftar ke-35-nya rata tanpa penanda. Centang
    -- salah satu dari tujuh itu = Auto Buy menunggu selamanya untuk barang
    -- yang memang tidak akan pernah muncul, dan hub diam saja. Sekarang
    -- ditandai, jadi kelihatan SEBELUM dicentang.
    makeMultiDropdown(c, "Seeds to Buy", function()
        local f = assetFolder("Seeds")
        local out = {}
        -- Dibaca SEKALI di luar loop: myLevel() menyentuh Replica, dan
        -- katalog bibitnya 35 entri.
        local lvl = myLevel()
        if f then
            for _, m in ipairs(f:GetChildren()) do
                local pack = m:GetAttribute("seedPack")
                local need = tonumber(m:GetAttribute("requiredLevel")) or 1
                -- LEVEL IKUT DITANDAI, kelas yang sama dengan [PACK] /
                -- [VIP]: barang yang kalau dicentang cuma dijawab server
                -- "level requirement N", dan itu harus kelihatan SEBELUM
                -- dicentang - bukan sesudah uangnya percuma dicoba.
                -- HARGA didahulukan dari toko yang SEDANG berjalan, baru
                -- katalog - lihat TOKO.harga. Kalau nol berarti memang
                -- tidak ketahuan, dan tidak ditulis sama sekali; menulis
                -- "$0" untuk sesuatu yang harganya belum terbaca itu
                -- kebohongan yang sama dengan sakelar mengaku mati.
                local harga = TOKO.harga("SeedShop", m.Name, m)
                local isi = {}
                if harga > 0 then isi[#isi + 1] = "$" .. fmtNum(harga) end
                -- ============================================================
                -- WAKTU TUMBUH = growTime x 3, dan itu RUMUS GAME SENDIRI
                -- ============================================================
                -- Bukan tebakan. Dua tempat di client memakai pengali yang
                -- sama, dan saya salin dua-duanya:
                --
                --   PlanterDisplay (StarterPlayerScriptsV3 8989):
                --       local v5 = v2.growTime * (#MenuConfig.GrowthStages - 1)
                --   kartu toko (_buildCards 10946-10966):
                --       v16.Text = "\226\143\177 " .. formatTime(v13.growTime * 3)
                --
                -- GrowthStages ada 4 (Seed, Sprout, Leaf, Bloom), jadi
                -- (#GrowthStages - 1) = 3. Persis angka yang ditulis kartu
                -- toko, jadi dua sumber itu sepakat.
                --
                -- TERUKUR: Camellia Seed growTime = 14.400 -> x3 = 43.200
                -- detik = 12 jam, dan kartu game-nya memang menulis "12h".
                -- Harganya 20.000, juga cocok dengan kartu.
                --
                -- 2XGrowSpeed SENGAJA tidak dipotong di sini: label ini
                -- angka KATALOG, sementara boost itu bisa habis di tengah
                -- jalan. Yang memotongnya slotRemaining(), dan di situ
                -- memang tepat karena dia menghitung tanaman yang SEDANG
                -- tumbuh - bukan calon pembelian.
                local grow = tonumber(m:GetAttribute("growTime"))
                if grow and grow > 0 then
                    isi[#isi + 1] = "tumbuh " .. fmtDur(grow * 3)
                end
                if pack then
                    isi[#isi + 1] = "TIDAK DIJUAL - dari " .. tostring(pack)
                elseif lvl and need > lvl then
                    isi[#isi + 1] = "LEVEL KURANG - butuh Lv" .. need ..
                                    ", kamu Lv" .. lvl
                elseif need > 1 then
                    isi[#isi + 1] = "Lv" .. need
                end
                out[#out + 1] = m.Name ..
                    ((#isi > 0) and ("  [" .. table.concat(isi, " | ") .. "]") or "")
            end
        end
        table.sort(out)
        return out
    end, sel.buySeeds, "None", stripLabel)

    -- KOTAK ANGKA YANG SAMA dengan yang di tab Auto - satu config, dua
    -- kotak, dan samakanAngka() menjaga keduanya tidak pernah beda.
    makeNumber(c, "Jumlah BIBIT per barang", 1, 50000, THEME.Yellow, "buyQty")
    makeButton(c, "🛒 BELI BIBIT SEKALI (pakai angka di atas)", THEME.Green, function()
        task.spawn(function()
            beliSekali("SeedShop", sel.buySeeds, "Bibit", config.buyQty)
        end)
    end)
    local totBibit = makeInfo(c, "-")

    AUTO.pasangVis("beliSupply", makeToggle(c, "Auto Buy SUPPLY (SupplyShop)", THEME.Yellow, function(v)
        if v and setIsEmpty(sel.buySupplies) then
            notify("Centang supply-nya dulu di dropdown tepat di bawah", THEME.Yellow)
        end
        AUTO.set.beliSupply(v)
        notify(v and "Auto Buy Supply ON" or "Auto Buy Supply OFF", v and THEME.On or THEME.Off)
    end))
    -- LOCK DITANDAI, kelas yang sama dengan [PACK] di bibit dan [VIP] di
    -- planter: barang yang kalau dicentang cuma membuang uang, dan itu
    -- harus kelihatan SEBELUM dicentang.
    --
    -- Kenapa penting justru di sini: baris "Pilih Semua" di dropdown ini
    -- mencentang KESEMBILAN supply, termasuk Lock. Lock $250 sebiji dan
    -- gunanya MELINDUNGI bunga dari panen - kebalikan dari yang kita mau,
    -- dan hub ini tidak pernah memakainya. Jadi "Pilih Semua" tanpa
    -- penanda = beli barang yang dijamin tidak terpakai.
    --
    -- Penandanya cuma LABEL: yang disimpan tetap nama aslinya (stripLabel),
    -- dan kalau kamu memang mau Lock, tinggal dicentang. Saya tidak
    -- membuangnya diam-diam dari daftar.
    makeMultiDropdown(c, "Supplies to Buy", function()
        local f = assetFolder("Supplies")
        local out = {}
        if f then
            for _, m in ipairs(f:GetChildren()) do
                local jenis = m:GetAttribute("SupplyType")
                local harga = TOKO.harga("SupplyShop", m.Name, m)
                local isi = {}
                if harga > 0 then isi[#isi + 1] = "$" .. fmtNum(harga) end
                if jenis == "Lock" then
                    isi[#isi + 1] = "TIDAK DIPAKAI HUB - lindungi dari panen"
                end
                out[#out + 1] = m.Name ..
                    ((#isi > 0) and ("  [" .. table.concat(isi, " | ") .. "]") or "")
            end
        end
        table.sort(out)
        return out
    end, sel.buySupplies, "None", stripLabel)

    makeNumber(c, "Jumlah SUPPLY per barang", 1, 50000, THEME.Yellow, "qtySupply")
    makeButton(c, "🛒 BELI SUPPLY SEKALI (pakai angka di atas)", THEME.Green, function()
        task.spawn(function()
            beliSekali("SupplyShop", sel.buySupplies, "Supply", config.qtySupply)
        end)
    end)
    local totSupply = makeInfo(c, "-")

    -- SATU loop untuk DUA label - alasan sama dengan kembarannya di tab
    -- Auto: label hidup itu beban paling besar di panel ini, jadi jangan
    -- bikin dua loop untuk pekerjaan yang bisa diselesaikan satu.
    task.spawn(function()
        while ScreenGui.Parent do
            while ScreenGui.Parent and not tampil(ShopBody) do task.wait(0.4) end
            totBibit.Text  = totalBelanja("SeedShop", sel.buySeeds,
                                          config.buyQty, "Seeds")
            totSupply.Text = totalBelanja("SupplyShop", sel.buySupplies,
                                          config.qtySupply, "Supplies")
            task.wait(2)
        end
    end)

    makeInfo(c, "ANGKA 'Jumlah' DI ATAS = TARGET PER BARANG, bukan total.\nCentang 3 bibit lalu isi 10 -> yang diminta 10 BIJI TIAP bibit.\nBatasnya sekarang 50.000 (dulu 1000, dan sebelumnya 50). Bisa\ndiketik langsung untuk lompat ke 300, atau ditekan +/- untuk\nmengoreksi satu-satu.\n\nKENAPA 50.000, bukan 1000: angka 1000 itu tebakan saya dan\nTERBUKTI kekecilan - hotbar-mu menunjukkan Camellia menumpuk\nsampai x6.000 lalu x11.600 dalam SATU Tool. Jadi tas memang\nsanggup jauh di atas 1000.\n\nKotak yang sama ada di tab ⚡ Auto dan di kartu STOK TOKO di\nbawah - itu ANGKA YANG SAMA, jadi mengubah di satu tempat\nlangsung ikut di tempat lain.\n\nDUA TOMBOL, DUA PERILAKU:\n\n  BELI ... SEKALI  -> satu sapuan lalu BERHENTI. Toko sama,\n                      centang sama, angka sama.\n  Auto Buy         -> sapuan yang sama, tapi DIULANG terus tiap\n                      ~4 detik selama sakelarnya ON.\n\nCARANYA BEDA PER TOKO, dan itu aturan game bukan pilihan saya:\n\n  SeedShop     -> qty > 1 DITERIMA server. Tapi kotak bulk milik\n                  game sendiri DIKUNCI di 100 (ShopController\n                  11528 & 11538), jadi game TIDAK PERNAH mengirim\n                  lebih dari itu. Target 300 karena itu dipecah\n                  jadi 3 panggilan @100 - bentuk yang sudah\n                  terbukti diterima, bukan taruhan.\n\n  SupplyShop   -> server MEMAKSA qty = 1 (ShopController 11007\n  DecorShop       menulisnya sendiri). Jadi target dicapai dengan\n                  MENGULANG panggilan, satu per Shop Delay.\n\nYANG BENAR-BENAR MEMBATASI ITU STOK TOKO, BUKAN ANGKA INI.\nTiap barang cuma distok 3-6 biji dan berputar tiap ~5 menit.\nJadi mengisi 1000 TIDAK membuat 1000 biji masuk - yang dikirim\ndipotong ke stok yang TERBACA, dan sisanya berhenti di penolakan\nPERTAMA. Mengisi 1000 saat stoknya 4 = 4 panggilan, bukan 1000.\n\nKalau kamu memang mau 300 bibit: biarkan Auto Buy menyala dan\nangkanya besar - dia memanen tiap kali toko berputar. Satu\nsapuan mustahil melewati stok yang ada.\n\nSakelar 'Beli sampai stok toko HABIS' di bawah MENANG atas angka\nini - TAPI cuma untuk Auto Buy. Tombol BELI SEKALI selalu\nmematuhi angka di kotak, kalau tidak angkanya jadi hiasan.")

    -- SENGAJA tanpa `kunci`: ini pilihan tersimpan (config), bukan fitur
    -- yang jalan sendiri - lihat catatan parameter ke-5 di makeToggle.
    makeToggle(c, "Beli sampai stok toko HABIS (bukan 1 per putaran)", THEME.Orange, function(v)
        config.habisStok = v
        notify(v and "Auto Buy menghabiskan stok tiap barang yang dicentang"
                  or "Auto Buy kembali beli 1 biji per putaran",
               v and THEME.On or THEME.Off)
    end)(config.habisStok)

    makeInfo(c, "STOK TOKO ITU 3-6 BIJI DAN BERPUTAR TIAP ~5 MENIT.\n\nBawaan Auto Buy beli SATU biji per putaran (tiap ~4 detik), jadi\nuntuk menghabiskan Watering Can x6 butuh 24 detik - dan kalau\ntokonya kebetulan refresh di tengah jalan, sisanya hilang.\n\nSakelar di atas mengubahnya jadi: tembak barang yang sama\nBERULANG sampai stoknya nol, baru lanjut ke barang berikutnya.\nBatas percobaannya dari angka stok yang dikirim server\n(StockRefreshed), jadi tidak ada tembakan berlebih; kalau stoknya\nbelum terbaca, dibatasi 20 percobaan dan tetap berhenti di\npenolakan pertama.\n\nHarga tiap barang ikut diperiksa SEBELUM menembak - harganya\nmemang ada di daftar toko, jadi pemeriksaan itu gratis dan\npembelian yang sudah pasti gagal karena cash kurang tidak\ndikirim sama sekali.")

    makeToggle(c, "Auto Buy Upgrades", THEME.Yellow, function(v)
        state.autoBuyUpgrade = v
        if v then
            if setIsEmpty(sel.buyUpgrades) then notify("Pilih upgrade dulu!", THEME.Yellow) end
            startLoop("upgrade", function() doUpgradeOnce() end, function() return 10 end)
            notify("Auto Buy Upgrades ON", THEME.On)
        else
            stopLoop("upgrade"); notify("Auto Buy Upgrades OFF", THEME.Off)
        end
    end, "autoBuyUpgrade")
    -- HARGA DI POSISI SEKARANG, bukan harga dasar. Tiap upgrade sumbernya
    -- beda-beda dan levelnya dibaca dari Replica - lihat labelUpgrade().
    -- stripLabel mengembalikan nama aslinya, jadi doUpgradeOnce tetap
    -- membandingkan "Advertising" / "Craft Table" / dst seperti semula.
    makeMultiDropdown(c, "Upgrades to Buy", labelUpgrade,
        sel.buyUpgrades, "None", stripLabel)

    -- Dideklarasi DULU supaya loop Auto Hire di bawah bisa ikut
    -- menyegarkan daftar pelamarnya tiap kali dia mengecek. Dua-duanya
    -- lokal di dalam do...end kartu ini, jadi tidak menambah register di
    -- level teratas (batas Luau 200 per fungsi).
    local appLbl, refreshApplicants

    makeToggle(c, "Auto Hire Staff", THEME.Yellow, function(v)
        state.autoHire = v
        if v then
            if setIsEmpty(sel.hireRoles) then notify("Pilih role staff dulu!", THEME.Yellow) end
            -- Tiap 25 detik: BACA pelamar, saring bintangnya, hire cuma
            -- kalau ada yang cocok. Daftarnya ikut disegarkan supaya kotak
            -- di bawah tidak menampilkan pelamar yang sudah berganti.
            startLoop("hire", function()
                doHireOnce()
                -- Penyegaran daftarnya cuma kalau tab Shop memang sedang
                -- dilihat: isinya panggilan GetApplicants ke server, dan
                -- percuma membayar itu untuk kotak yang tidak terlihat.
                if refreshApplicants and tampil(ShopBody) then refreshApplicants() end
            end, function() return 25 end)
            notify("Auto Hire Staff ON - " .. bintangTeks(), THEME.On)
        else
            stopLoop("hire"); notify("Auto Hire Staff OFF", THEME.Off)
        end
    end, "autoHire")
    -- CUMA DUA ROLE. "Florist" sudah dibuang dari sini: itu nama MODEL
    -- milik role Gardener, bukan role - lihat catatan panjang di
    -- hireCost(). Mencentangnya dulu membuat role itu dilewati diam-diam.
    -- Harga hire = ceil(base + (bintang-1)^3 x per), jadi rentangnya jauh:
    -- Gardener 1.500 di bintang 1 tapi 97.500 di bintang 5. Dua ujungnya
    -- ditampilkan supaya kelihatan seberapa mahal role itu bisa jadi.
    makeMultiDropdown(c, "Staff Roles to Hire", function()
        local out = {}
        for _, role in ipairs({ "Gardener", "Cashier" }) do
            out[#out + 1] = role .. "  [⭐1 $" .. fmtNum(hireCost(role, 1) or 0) ..
                            "  ..  ⭐5 $" .. fmtNum(hireCost(role, 5) or 0) .. "]"
        end
        return out
    end, sel.hireRoles, "None", stripLabel)

    -- ---- FILTER BINTANG ----
    -- Centang bintang yang BOLEH dibeli. Kosongkan kalau mau pakai cara
    -- lama (slider "minimal sekian ke atas") - lihat bintangBoleh().
    -- Harga TIAP bintang untuk KEDUA role, karena inilah keputusan uang
    -- yang sebenarnya: mencentang bintang 5 itu $97.500 (Gardener) atau
    -- $130.000 (Cashier) per orang, sementara bintang 4 cuma separuhnya.
    --
    -- Kunci yang DISIMPAN tetap "⭐ 5 bintang" (stripLabel memotong mulai
    -- dua spasi + kurung), jadi bintangBoleh() yang mencabut angka lewat
    -- string.match(k, "%d+") tetap benar dan konfigurasi lama tetap kebaca.
    makeMultiDropdown(c, "Bintang yang boleh di-hire", function()
        local out = {}
        for i = 1, 5 do
            out[#out + 1] = "⭐ " .. i .. " bintang  [Gardener $" ..
                fmtNum(hireCost("Gardener", i) or 0) .. " | Cashier $" ..
                fmtNum(hireCost("Cashier", i) or 0) .. "]"
        end
        return out
    end, sel.hireStars, "pakai slider", stripLabel)

    makeInfo(c, "CENTANG = HANYA ITU YANG DIBELI.\n\nCentang '⭐ 5 bintang' saja -> tiap putaran Auto Hire membaca\ndaftar pelamar dulu; kalau tidak ada yang bintang 5, TIDAK ADA\nyang direkrut dan tidak ada uang keluar. Bintang 4 pun dilewati,\nbukan diambil sebagai 'lumayan'.\n\nBoleh centang lebih dari satu (mis. 4 dan 5) - yang diambil tetap\nyang TERTINGGI di antara yang dicentang.\n\nKalau tidak ada yang dicentang, dipakai slider di bawahnya:\nartinya berubah jadi 'sekian KE ATAS'.\n\nKenapa bedanya penting: biaya hire meledak di bintang tinggi,\nrumusnya ceil(base + (bintang-1)^3 x per).\n  Gardener  ⭐4 = $42.000    ⭐5 = $97.500\n  Cashier   ⭐4 = $56.000    ⭐5 = $130.000\nJadi 'cuma mau bintang 5' dan 'minimal bintang 4' itu dua\nkeputusan uang yang sama sekali berbeda.")

    makeSlider(c, "Minimal Bintang ⭐ (dipakai kalau tidak ada centang)",
        config.minStars, 1, 5, THEME.Yellow, function(v)
        config.minStars = math.floor(v)
    end)

    appLbl = makeInfo(c, "Pelamar: tekan 'Lihat Pelamar + Bintang'")

    refreshApplicants = function()
        local apps = getApplicants()
        if not apps then appLbl.Text = "GetApplicants gagal - cek Output."; return end
        local lines = { "PELAMAR SEKARANG (⭐ = level):" }
        local adaCocok = 0
        for role, list in pairs(apps) do
            if type(list) == "table" then
                lines[#lines + 1] = "  " .. tostring(role) .. ":"
                for idx, a in ipairs(list) do
                    local lvl = tonumber(a and a.level) or 0
                    local cost = hireCost(role, lvl)
                    local boleh = bintangBoleh(lvl)
                    if boleh then adaCocok = adaCocok + 1 end
                    lines[#lines + 1] = string.format("    #%d  %s  %s  $%s%s",
                        idx,
                        string.rep("⭐", math.clamp(lvl, 0, 5)),
                        tostring(a and a.name or "?"),
                        cost and fmtNum(cost) or "?",
                        boleh and "   << DIBELI" or "")
                end
                if #list == 0 then lines[#lines + 1] = "    (kosong)" end
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Filter sekarang : " .. bintangTeks()
        lines[#lines + 1] = "Yang cocok      : " .. adaCocok ..
            (adaCocok == 0 and "  -> TIDAK ADA yang dibeli" or "  -> diambil yang TERTINGGI")
        appLbl.Text = table.concat(lines, "\n")
    end

    makeButton(c, "⭐ Lihat Pelamar + Bintang", THEME.Blue, function()
        task.spawn(refreshApplicants)
    end)

    makeButton(c, "⭐ Hire Sekarang (sesuai centang bintang)", THEME.Green, function()
        task.spawn(function()
            local n, err = doHireOnce()
            if n > 0 then
                notify("Hire " .. n .. " staff OK", THEME.On)
            else
                notify("Tidak jadi hire - " .. tostring(err), THEME.Yellow)
            end
            refreshApplicants()
        end)
    end)

    makeInfo(c, "Pelamar berganti sendiri lewat RefreshCountdown milik game -\nTIDAK ada remote untuk memaksa refresh staff. Jadi biarkan\nAuto Hire menyala; tiap 25 detik dia mengecek ulang, dan bintang\nyang kamu centang disamber begitu muncul.\n\nKotak di atas ikut disegarkan tiap pengecekan itu, jadi tidak\nperlu menekan 'Lihat Pelamar' berulang-ulang.")

    makeSlider(c, "Shop Delay", config.shopDelay, 0.1, 5, THEME.Yellow, function(v) config.shopDelay = v end)
end

-- ============================================================
-- NAIKKAN BINTANG STAFF (tukar yang terendah dengan pelamar lebih tinggi)
-- ============================================================
-- ATURANNYA SATU KALIMAT: kalau pelamar terbaik LEBIH TINGGI daripada
-- staff TERENDAH yang kamu punya, staff terendah itu diganti. Diulang
-- terus sampai tidak ada lagi pelamar yang lebih tinggi - ujungnya
-- semua bintang 5, karena 5 itu batas atasnya.
--
-- Yang dibandingkan SELALU seluruh staff role itu, bukan satu-satu:
-- punyaku() mengurutkan dari bintang terkecil, jadi staf[1] memang yang
-- paling rendah dari semuanya.
--
-- TIDAK ADA UANG KEMBALI. FireStaff cuma menghapus - pencarian refund /
-- sellStaff / sellPrice di seluruh dump client = NOL hasil. Jadi tiap
-- tukar itu bayar penuh hire baru, dan yang lama hangus:
--     hireCost = ceil(base + (bintang-1)^3 * per)
--     Gardener bintang 5 = 97.500     Cashier bintang 5 = 130.000
--
-- URUTANNYA SENGAJA DIBALIK: HIRE DULU, PECAT BELAKANGAN.
-- Memecat tidak bisa dibatalkan. Kalau server ternyata mengizinkan hire
-- saat slot penuh, staff barunya sudah di tangan SEBELUM ada yang
-- dipecat - nol risiko. Jalur pecat-dulu cuma dipakai kalau server
-- menolak, dan hasil pengukurannya diingat (SU.lebih) supaya tidak
-- diuji ulang tiap putaran.
--
-- KALAU BATAS SLOT TIDAK TERBACA, fitur ini TIDAK AKAN MEMECAT siapa
-- pun - dia turun jadi "hire kalau masih ada tempat". Itu kegagalan
-- yang benar: lebih baik tidak naik daripada memecat tanpa dasar.
--
-- ATURAN YANG SAMA BERLAKU UNTUK UANG, dan ini yang paling mahal kalau
-- salah. Tiga gerbang, semuanya SEBELUM satu orang pun dipecat:
--   1. pemilihan   -> ambil bintang TERTINGGI yang harganya terjangkau
--   2. probe       -> penolakan yang bunyinya soal UANG tidak boleh
--                     disalahartikan sebagai "slot penuh" (lihat
--                     SU.uangKurang; itu lubang yang dulu menghabiskan
--                     satu staf tanpa dapat pengganti)
--   3. tepat sebelum FireStaff -> cash DIBACA ULANG, karena Auto Buy di
--                     loop lain bisa memotongnya di antara langkah 1 dan 3
-- Dan kalau cash TIDAK TERBACA sementara slot penuh: tidak ada yang
-- dipecat, titik.
do
    local c = makeCard("⭐ NAIKKAN BINTANG STAFF (tukar yang terendah)", THEME.Green, ShopBody)

    makeInfo(c, "Tujuannya: semua Gardener dan Cashier jadi bintang 5.\n\nCARA KERJANYA, persis contohmu. Misal slot Gardener 4, terisi\n1*, 2*, 2*, 4*:\n  ketemu pelamar 3*  -> yang 1* dipecat, 3* masuk   -> 2*,2*,3*,4*\n  ketemu 3* lagi     -> salah satu 2* dipecat        -> 2*,3*,3*,4*\n  ketemu 4*          -> 2* yang tersisa dipecat      -> 3*,3*,4*,4*\n\nYANG SELALU DIPECAT ADALAH YANG PALING RENDAH DARI SEMUANYA.\nDi langkah ketiga contohmu menyebut 3* yang dipecat; saya pakai\n2*, karena saat itu 2* masih ada dan dialah yang terendah.\nHasilnya lebih baik: 3*,3*,4*,4* (jumlah 14) dibanding\n2*,3*,4*,4* (jumlah 13). Kalau kamu memang mau aturan lain,\nbilang saja.\n\nTidak akan pernah menukar dengan yang SAMA atau LEBIH RENDAH,\njadi tidak ada uang terbuang untuk pertukaran sia-sia.")

    -- SU menampung semua milik fitur ini dalam SATU nama. Isi blok
    -- do...end ini bebas saat blok selesai, jadi nol register permanen
    -- (batas Luau: 200 register lokal per fungsi, file ini SATU fungsi).
    --   SU.lebih = hasil ukur "server izinkan hire saat slot penuh?"
    --   SU.jeda  = detik menuju pergantian pelamar berikutnya
    --   SU.sibuk = sapuan sedang jalan (loop & event tidak boleh dobel)
    --   SU.usai  = os.clock() sapuan terakhir selesai
    local SU = { lebih = nil, jeda = 30, sibuk = false, usai = 0 }
    local ROLES = { "Gardener", "Cashier" }

    -- ============================================================
    -- APAKAH PENOLAKAN SERVER ITU SOAL UANG
    -- ============================================================
    -- Dipasang sebagai FIELD SU, bukan `local function`, supaya tidak
    -- menambah satu register pun di blok ini (batas Luau 200 per fungsi).
    --
    -- Kata kuncinya LONGGAR, dan saya TIDAK mengklaim daftarnya lengkap:
    -- teks penolakan HireApplicant tidak pernah muncul di dump client, jadi
    -- kalimat aslinya memang belum terukur. Yang saya tahu pasti cuma satu
    -- hal, dan itu sudah cukup untuk keputusan di sini: kalau pesannya
    -- menyebut uang, itu BUKAN alasan untuk memecat siapa pun.
    --
    -- Pesan yang TIDAK dikenali sengaja tidak dianggap aman - dia jatuh ke
    -- GERBANG UANG TERAKHIR di bawah, yang menuntut cash TERBACA dan CUKUP
    -- sebelum satu orang pun dipecat.
    SU.uangKurang = function(msg)
        local s = string.lower(tostring(msg or ""))
        for _, k in ipairs({ "cash", "money", "afford", "enough", "fund",
                             "uang", "insufficient", "broke", "coin",
                             "price", "cost" }) do
            if string.find(s, k, 1, true) then return true end
        end
        return false
    end

    -- Staff satu role, diurut bintang NAIK -> [1] selalu yang terendah.
    local function punyaku(mine, role)
        local out = {}
        for i, s in ipairs((type(mine) == "table" and mine[role]) or {}) do
            if type(s) == "table" then
                out[#out + 1] = { id = s.id or i, nama = tostring(s.name or "?"),
                                  lvl = tonumber(s.level) or 0 }
            end
        end
        table.sort(out, function(a, b) return a.lvl < b.lvl end)
        return out
    end

    -- Pelamar satu role, diurut bintang TURUN -> [1] selalu yang terbaik.
    -- idx = posisi ASLI di array; itu yang diminta HireApplicant
    -- (SPSV2TELITI 10380-10383 membuat index dari ipairs, 10429 mengirimnya).
    local function pelamar(apps, role)
        local out = {}
        for i, a in ipairs((type(apps) == "table" and apps[role]) or {}) do
            if type(a) == "table" then
                out[#out + 1] = { idx = i, nama = tostring(a.name or "?"),
                                  lvl = tonumber(a.level) or 0 }
            end
        end
        table.sort(out, function(a, b) return a.lvl > b.lvl end)
        return out
    end

    -- CASH YANG BENAR-BENAR TERBACA. nil = replica gagal dibaca.
    --
    -- JANGAN pakai pdata("Cash", 0) di sini. pdata memberi DEFAULT kalau
    -- ReplicaController gagal, dan default 0 berarti "cash kurang" untuk
    -- SETIAP pelamar - fitur ini akan diam total tanpa pernah menembak
    -- sekali pun, dan alasannya terdengar masuk akal padahal palsu.
    -- Ini jebakan yang PERSIS SAMA dengan yang sudah dicatat di myLevel().
    -- Tidak tahu = JANGAN menyaring; biar server yang menolak sekali,
    -- daripada hub menolak selamanya.
    -- Sekarang lewat angkaStat(): replica dulu, lalu LABEL GAME. Itu
    -- penting justru di kartu INI - kalau replica gagal, gerbang
    -- "slot penuh + cash tidak terbaca = jangan pecat siapa pun" di
    -- bawah akan membekukan fitur ini SELAMANYA, padahal cash-nya
    -- jelas terbaca di layar. Balikan nil tetap berarti benar-benar
    -- tidak tahu, dan aturannya tidak berubah sedikit pun.
    local function cashKu()
        return (angkaStat("Cash"))
    end

    -- Satu role sampai mentok. Balikan: jumlah tukar, alasan kalau nol,
    -- dan GAWAT=true kalau slot sampai tertinggal kosong.
    local function naikkanRole(role)
        local jadi = 0
        for _ = 1, 6 do        -- batas per panggilan, biar tidak menahan thread
            local aok, apps = invokeRF("StaffService", "GetApplicants")
            if not aok or type(apps) ~= "table" then return jadi, "GetApplicants gagal" end

            -- KAPAN PELAMAR BERGANTI, dikirim server bersama daftarnya:
            --   startCountdown(p1.nextRefresh, p1.serverTime)  SPSV2TELITI 10443
            -- Dipakai supaya loop TIDUR sampai daftarnya benar-benar baru.
            -- Polling lebih cepat dari ini murni sia-sia: isinya tidak
            -- berubah sedetik pun sebelum servernya menggilir.
            -- Kalau dua angka itu TIDAK dikirim, jangan jatuh ke jeda
            -- terpendek - itu justru bikin loop menembaki server tiap 10
            -- detik untuk daftar yang belum tentu berubah. Pakai 30 detik,
            -- setara Auto Hire biasa.
            local nr, st = tonumber(apps.nextRefresh), tonumber(apps.serverTime)
            SU.jeda = (nr and st) and math.clamp((nr - st) + 2, 10, 300) or 30

            local mok, mine = invokeRF("StaffService", "GetMyStaff")
            if not mok or type(mine) ~= "table" then return jadi, "GetMyStaff gagal" end

            -- Angka batasnya BERSARANG di .limits, bukan di akar
            -- (SPSV2TELITI 10172: local v12 = p12.limits or {...}).
            local lok, lim = invokeRF("StaffService", "GetStaffLimits")
            local batas = tonumber(lok and type(lim) == "table"
                and type(lim.limits) == "table" and lim.limits[role]) or 0

            local staf  = punyaku(mine, role)
            local calon = pelamar(apps, role)
            local rendah = staf[1]
            local penuh  = (batas > 0) and (#staf >= batas)
            local cash   = cashKu()

            -- BALIKAN KE-4 = "kembali cepat". Slot yang masih KOSONG itu
            -- alasan sah untuk bangun lagi sebentar walau daftar pelamar
            -- belum berganti: cash bisa naik dari checkout kapan saja, dan
            -- slot kosong itu nol hasil. Kalau slotnya penuh dan tidak ada
            -- yang lebih tinggi, tidur penuh sampai pelamar berganti.
            if #calon == 0 then
                return jadi, "tidak ada pelamar " .. role, false, not penuh
            end

            -- ============================================================
            -- SLOT PENUH + CASH TIDAK TERBACA = JANGAN PECAT SIAPA PUN
            -- ============================================================
            -- Aturan yang PERSIS SAMA dengan "batas slot tidak terbaca":
            -- lebih baik tidak naik daripada memecat tanpa dasar.
            --
            -- Kenapa ini wajib. Kalau cash tidak terbaca, pemilihan di bawah
            -- TIDAK menyaring harga sama sekali (itu memang benar untuk slot
            -- KOSONG - biar server menolak sekali, tidak ada yang
            -- dikorbankan). Tapi kalau slot PENUH, jalurnya berlanjut ke
            -- pecat-dulu, dan di situ "tidak tahu harga" berubah dari
            -- kehati-hatian jadi kerugian: staf terendah dipecat, hire
            -- penggantinya ditolak karena uang, jaring darurat juga ditolak,
            -- dan kamu kehilangan satu staf tanpa dapat apa pun.
            --
            -- Sesudah gerbang ini, `cash` PASTI sebuah angka setiap kali
            -- `penuh` benar. Itu yang membuat gerbang-gerbang di bawah bisa
            -- membandingkan harga dengan yakin.
            if penuh and cash == nil then
                return jadi, "slot " .. role .. " penuh tapi CASH TIDAK TERBACA" ..
                       " (replica gagal) - tidak ada yang dipecat. Tekan" ..
                       " 'Refresh Data Replica' di tab Info, lalu coba lagi.",
                       false, true
            end

            -- AMBIL YANG TERBAIK YANG BENAR-BENAR MAMPU DIBELI.
            --
            -- Versi pertama cuma melihat calon[1]. Jadi kalau pelamar
            -- teratas bintang 5 dan cash-mu belum $97.500, fungsi ini
            -- LANGSUNG menyerah - padahal slotnya kosong dan ada bintang 3
            -- yang terjangkau. Slot kosong itu nol hasil, jadi mengambil
            -- yang terbaik-yang-mampu selalu lebih baik daripada diam.
            -- `calon` sudah urut bintang TURUN, jadi yang pertama lolos
            -- memang yang tertinggi.
            --
            -- Syarat "naik" cuma berlaku kalau slot PENUH. Slot kosong =
            -- tidak ada yang dibandingkan, jadi ambil saja yang terbaik.
            local best, biaya
            for _, cd in ipairs(calon) do
                local h = hireCost(role, cd.lvl) or 0
                local naik = (not penuh) or (rendah == nil) or (cd.lvl > rendah.lvl)
                -- `cash == nil` di sini cuma mungkin saat slot masih KOSONG -
                -- gerbang di atas sudah memulangkan yang penuh. Slot kosong
                -- tidak mengorbankan siapa pun, jadi biar server menolak
                -- sekali daripada hub menolak selamanya.
                if naik and (cash == nil or cash >= h) then
                    best, biaya = cd, h
                    break
                end
            end

            if not best then
                if penuh and rendah and calon[1].lvl <= rendah.lvl then
                    return jadi, "pelamar terbaik " .. role .. " cuma " .. calon[1].lvl ..
                                 "*, staf terendahmu sudah " .. rendah.lvl .. "*"
                end
                -- Ada yang layak, tapi tidak satupun terjangkau. Sebutkan
                -- angka TERMURAH yang layak, bukan yang teratas - itu yang
                -- benar-benar perlu kamu kumpulkan.
                local murah = math.huge
                for _, cd in ipairs(calon) do
                    if (not penuh) or (rendah == nil) or (cd.lvl > rendah.lvl) then
                        murah = math.min(murah, hireCost(role, cd.lvl) or 0)
                    end
                end
                -- Angkanya ditulis LENGKAP: cash sekarang, harga termurah
                -- yang layak, dan SELISIHNYA. Itu satu-satunya angka yang
                -- benar-benar perlu kamu kumpulkan, dan tanpa menyebutnya
                -- pesan "cash kurang" tidak bisa ditindaklanjuti.
                -- `cash` tidak pernah ditulis 0 kalau sebenarnya tidak
                -- terbaca - itu jenis kebohongan yang sama dengan sakelar
                -- yang mengaku mati padahal hidup.
                return jadi, "cash kurang untuk " .. role .. " - butuh $" ..
                       fmtNum(murah) .. " (pelamar termurah yang layak), cash kamu " ..
                       (cash and ("$" .. fmtNum(cash)) or "TIDAK TERBACA") ..
                       (cash and ("  -> kurang $" .. fmtNum(math.max(murah - cash, 0))) or "") ..
                       ". TIDAK ada yang dipecat, tidak ada uang keluar.", false, true
            end

            if not penuh then
                -- Masih ada tempat: cukup hire, TIDAK ADA yang dipecat.
                local hok, hres, hmsg = invokeRF("StaffService", "HireApplicant", role, best.idx)
                if not (hok and hres ~= false) then
                    return jadi, "hire " .. role .. " ditolak: " .. tostring(hmsg or hres) ..
                        (batas <= 0 and "  (batas slot tidak terbaca - kemungkinan sudah penuh;"
                                     .. " tidak ada yang dipecat)" or ""), false, true
                end
                jadi = jadi + 1
                addLog("Hire " .. role .. " " .. best.nama .. " " .. best.lvl ..
                       "* (slot kosong, $" .. fmtNum(biaya) .. ")", "STAFF")
                task.wait(0.35)
            else
                -- PENUH. Coba hire DULU: kalau server mengizinkan, staff
                -- barunya masuk sebelum ada yang dipecat -> nol risiko.
                local dapat = false
                -- Siapa yang BENAR-BENAR masuk. Jalur darurat di bawah bisa
                -- mengambil pelamar lain, dan laporan tidak boleh menyebut
                -- orang yang tidak jadi direkrut.
                local masukNama, masukLvl = best.nama, best.lvl
                if SU.lebih ~= false then
                    local hok, hres, hmsg =
                        invokeRF("StaffService", "HireApplicant", role, best.idx)
                    dapat = (hok and hres ~= false) and true or false
                    -- ============================================================
                    -- PENOLAKAN SOAL UANG JANGAN DIANGGAP "SLOT PENUH"
                    -- ============================================================
                    -- Ini lubang paling mahal di fitur ini, dan bentuknya halus:
                    -- probe di atas bisa ditolak karena DUA sebab yang dari sini
                    -- kelihatan SAMA PERSIS -
                    --   (a) server tidak mengizinkan hire saat slot penuh
                    --   (b) uangmu tidak cukup
                    --
                    -- Versi lama mencatat dua-duanya sebagai (a), lalu lanjut ke
                    -- jalur PECAT-DULU. Untuk (b) akibatnya berantai: staf
                    -- terendah dipecat, hire penggantinya ditolak lagi (uangnya
                    -- memang tetap kurang), jaring darurat juga ditolak dengan
                    -- alasan yang sama -> SLOT KOSONG, uang tetap kurang, dan
                    -- satu staf hilang tanpa dapat apa pun.
                    --
                    -- Lebih parah: `SU.lebih = false` itu dikenang SELURUH SESI,
                    -- jadi satu kali salah baca membuat SEMUA pertukaran
                    -- berikutnya memakai jalur berisiko itu - walau uangnya
                    -- sudah tebal lagi.
                    if not dapat and SU.uangKurang(hmsg) then
                        return jadi, "server menolak hire " .. role ..
                               " karena UANG: " .. tostring(hmsg) ..
                               "  (cash $" .. fmtNum(cash) .. ", biaya $" ..
                               fmtNum(biaya) .. ") - TIDAK ADA yang dipecat", false, true
                    end
                    SU.lebih = dapat
                    if dapat then
                        addLog("Server MENGIZINKAN hire saat penuh - jalur tanpa risiko dipakai", "STAFF")
                    end
                end

                if dapat then
                    task.wait(0.35)
                    -- Hasilnya ikut diperiksa. Kalau pecatnya gagal di sini
                    -- kamu cuma KELEBIHAN satu staff, bukan kekurangan -
                    -- itu kegagalan yang aman, tapi tetap harus kelihatan.
                    local fok, fres = invokeRF("StaffService", "FireStaff", role, rendah.id)
                    if not fok or fres == false then
                        addLog("Staff baru sudah masuk tapi " .. rendah.nama ..
                               " gagal dipecat -> slot " .. role .. " kelebihan 1", "STAFF")
                    end
                else
                    -- ============================================================
                    -- GERBANG UANG TERAKHIR - satu baris sebelum ada yang dipecat
                    -- ============================================================
                    -- Cash dibaca ULANG di sini, bukan dipakai yang tadi. Antara
                    -- pemeriksaan di atas dan baris ini sudah ada satu panggilan
                    -- server penuh (probe hire) plus jedanya, dan selama itu
                    -- cash-mu bisa TURUN tanpa ada hubungannya dengan fitur ini -
                    -- Auto Buy Bibit / Supply, Auto Buy Upgrades, atau tombol
                    -- BORONG jalan di loop lain dan memotong cash yang sama.
                    --
                    -- TIDAK TERBACA juga dihentikan di sini, bukan diteruskan:
                    -- memecat itu tidak bisa dibatalkan, jadi ini satu-satunya
                    -- tempat yang boleh memutuskannya, dan cuma dengan angka yang
                    -- benar-benar ada di tangan.
                    local kini = cashKu()
                    if kini == nil or kini < biaya then
                        return jadi, "cash " ..
                               (kini and ("$" .. fmtNum(kini)) or "TIDAK TERBACA") ..
                               " tidak cukup untuk pengganti " .. role .. " ($" ..
                               fmtNum(biaya) .. ") - " .. rendah.nama .. " " ..
                               rendah.lvl .. "* TIDAK dipecat", false, true
                    end
                    -- Server menolak, jadi terpaksa pecat dulu.
                    local fok, fres, fmsg = invokeRF("StaffService", "FireStaff", role, rendah.id)
                    if not fok or fres == false then
                        return jadi, "pecat " .. role .. " gagal: " .. tostring(fmsg or fres)
                    end
                    task.wait(0.3)

                    -- Dicoba dua kali: penyebab meleset yang paling sering
                    -- bukan index salah, tapi server belum selesai memproses
                    -- pemecatannya.
                    local masuk = false
                    for _ = 1, 2 do
                        local hok, hres = invokeRF("StaffService", "HireApplicant", role, best.idx)
                        if hok and hres ~= false then masuk = true; break end
                        task.wait(0.4)
                    end

                    -- JARING PENGAMAN. Slot terlanjur kosong -> isi dengan
                    -- pelamar terbaik yang levelnya MASIH >= yang tadi
                    -- dipecat, supaya keadaanmu tidak pernah lebih buruk
                    -- daripada sebelum tombol ini ditekan.
                    if not masuk then
                        local rok, ulang = invokeRF("StaffService", "GetApplicants")
                        -- Cash dibaca sekali lagi: yang sudah PASTI di luar
                        -- jangkauan tidak perlu ditembak, dan di jalur darurat
                        -- tiap panggilan sia-sia itu menunda pemulihan slot.
                        -- nil = jangan menyaring - jaring pengaman tidak boleh
                        -- ikut mati cuma karena replica sedang gagal dibaca.
                        local cash2 = cashKu()
                        for _, cd in ipairs((rok and pelamar(ulang, role)) or {}) do
                            -- SENGAJA `ongkos`, bukan h2: dua baris di bawah
                            -- sudah ada `local h2` milik invokeRF, dan nama
                            -- yang menaungi nama lain di blok yang sama itu
                            -- bibit bug walau compiler-nya menerima.
                            local ongkos = hireCost(role, cd.lvl) or 0
                            if cd.lvl >= rendah.lvl and (cash2 == nil or cash2 >= ongkos) then
                                local h2, r2 = invokeRF("StaffService", "HireApplicant", role, cd.idx)
                                if h2 and r2 ~= false then
                                    masuk = true
                                    masukNama, masukLvl = cd.nama, cd.lvl
                                    addLog("Pengganti darurat " .. role .. ": " .. cd.nama ..
                                           " " .. cd.lvl .. "*", "STAFF")
                                    break
                                end
                                task.wait(0.3)
                            end
                        end
                    end

                    if not masuk then
                        return jadi, "SLOT " .. role .. " KOSONG - " .. rendah.nama .. " " ..
                               rendah.lvl .. "* sudah dipecat tapi tidak ada pengganti yang" ..
                               " bisa masuk. Hire manual lewat panel game.", true
                    end
                end

                jadi = jadi + 1
                addLog("Tukar " .. role .. ": " .. rendah.nama .. " " .. rendah.lvl ..
                       "* -> " .. masukNama .. " " .. masukLvl ..
                       "*  ($" .. fmtNum(hireCost(role, masukLvl) or biaya) .. ")", "STAFF")
                task.wait(0.35)
            end
        end
        -- Enam iterasi HABIS terpakai, artinya enam aksi benar-benar jadi
        -- dan mungkin masih ada sisa. Minta bangun cepat.
        return jadi, nil, false, true
    end

    local sLbl = makeInfo(c, "Tekan salah satu tombol di bawah - dua-duanya mengisi kotak ini.")

    -- SENGAJA tanpa loop tampilan. Isinya tiga panggilan server, dan kartu
    -- lain di hub ini sudah membuktikan label hidup itu sumber lag paling
    -- besar. Jadi digambar hanya saat diminta / sesudah ada pertukaran.
    local function gambar()
        local mok, mine = invokeRF("StaffService", "GetMyStaff")
        local aok, apps = invokeRF("StaffService", "GetApplicants")
        local lok, lim  = invokeRF("StaffService", "GetStaffLimits")
        local batas = (lok and type(lim) == "table" and lim.limits) or {}
        -- Cash dibaca DI SINI, sebelum loop role - bukan di baris terakhir
        -- seperti dulu. Angkanya bukan cuma untuk dicetak: dia yang menentukan
        -- baris "BISA NAIK" di bawah jujur atau tidak.
        local ck = cashKu()
        local baris = {}
        for _, role in ipairs(ROLES) do
            local staf  = (mok and punyaku(mine, role)) or {}
            local calon = (aok and pelamar(apps, role)) or {}
            local a, b = {}, {}
            for _, s in ipairs(staf)  do a[#a + 1] = s.lvl .. "*" .. s.nama end
            for _, d in ipairs(calon) do b[#b + 1] = d.lvl .. "*" .. d.nama end
            baris[#baris + 1] = role .. "   (" .. #staf .. " / " ..
                tostring(tonumber(batas[role]) or "?") .. " slot)"
            baris[#baris + 1] = "  punya   : " .. (#a > 0 and table.concat(a, ", ") or "(kosong)")
            baris[#baris + 1] = "  pelamar : " .. (#b > 0 and table.concat(b, ", ") or "(kosong)")
            -- ============================================================
            -- BARIS INI HARUS SAMA JUJURNYA DENGAN MESINNYA
            -- ============================================================
            -- Versi lama cuma melihat calon[1] dan langsung menulis
            -- "BISA NAIK $97.500". Padahal yang benar-benar diambil hub
            -- adalah bintang TERTINGGI yang HARGANYA TERJANGKAU, dan kalau
            -- tidak ada yang terjangkau dia tidak mengambil apa pun.
            -- Jadi kotak ini dulu bisa menjanjikan pertukaran yang mustahil
            -- terjadi - dan itu persis pertanyaan "kok tombolnya diam".
            local lim2  = tonumber(batas[role])
            local penuh2 = (lim2 ~= nil and lim2 > 0) and (#staf >= lim2) or false
            if staf[1] and calon[1] then
                if calon[1].lvl <= staf[1].lvl then
                    baris[#baris + 1] = "  -> tidak ada pelamar yang lebih tinggi"
                elseif penuh2 and ck == nil then
                    -- Sama dengan gerbang di naikkanRole: slot penuh + cash
                    -- tidak terbaca = tidak ada yang dipecat, titik.
                    baris[#baris + 1] = "  -> CASH TIDAK TERBACA & slot penuh" ..
                        "  (tidak ada yang dipecat - tekan 'Refresh Data Replica')"
                else
                    local pilih, harga
                    for _, cd in ipairs(calon) do
                        local h = hireCost(role, cd.lvl) or 0
                        if cd.lvl > staf[1].lvl and (ck == nil or ck >= h) then
                            pilih, harga = cd, h
                            break
                        end
                    end
                    if pilih then
                        baris[#baris + 1] = "  -> BISA NAIK: " .. staf[1].lvl .. "*" ..
                            staf[1].nama .. " diganti " .. pilih.lvl .. "*" ..
                            pilih.nama .. "   $" .. fmtNum(harga)
                        -- Kalau yang tertinggi DILEWATI karena harga, itu
                        -- wajib kelihatan - kalau tidak, kamu akan mengira
                        -- hub tidak melihat bintang 5 yang jelas ada di layar.
                        if pilih ~= calon[1] then
                            baris[#baris + 1] = "     (bintang " .. calon[1].lvl ..
                                " ada tapi butuh $" ..
                                fmtNum(hireCost(role, calon[1].lvl) or 0) ..
                                " - dilewati, uang belum cukup)"
                        end
                    else
                        local h1 = hireCost(role, calon[1].lvl) or 0
                        baris[#baris + 1] = "  -> BELUM MAMPU: " .. calon[1].lvl .. "*" ..
                            calon[1].nama .. " butuh $" .. fmtNum(h1) .. ", cash $" ..
                            fmtNum(ck or 0) .. "  -> kurang $" ..
                            fmtNum(math.max(h1 - (ck or 0), 0)) ..
                            (penuh2 and "   (TIDAK ada yang dipecat)" or "")
                    end
                end
            end
            baris[#baris + 1] = ""
        end
        local sisa = (aok and type(apps) == "table")
            and ((tonumber(apps.nextRefresh) or 0) - (tonumber(apps.serverTime) or 0)) or nil
        baris[#baris + 1] = "Pelamar berganti dalam : " ..
            (sisa and (math.max(0, math.floor(sisa)) .. " detik") or "?")
        baris[#baris + 1] = "Cash                   : " ..
            (ck and ("$" .. fmtNum(ck)) or "TIDAK TERBACA (replica gagal)")
        -- Alasan terakhir ditulis PERMANEN di sini, bukan cuma lewat toast
        -- 2 detik. Kalau tombolnya "tidak melakukan apa-apa", inilah yang
        -- memberitahu kenapa - dan tetap terbaca sesudah kamu selesai
        -- membacanya pelan-pelan.
        if SU.pesan then
            baris[#baris + 1] = ""
            baris[#baris + 1] = "ALASAN TERAKHIR:"
            baris[#baris + 1] = "  " .. SU.pesan
        end
        sLbl.Text = table.concat(baris, "\n")
    end

    -- Dipakai tombol DAN loop. Balikan: total tukar, alasan, gawat.
    --
    -- ALASAN TIAP ROLE DIKUMPULKAN, BUKAN DITIMPA. Versi pertama menulis
    -- `pesan = w` di dalam loop, jadi yang sampai ke layar cuma alasan
    -- role TERAKHIR - Cashier. Kalau Gardener yang gagal, alasannya
    -- hilang dan kamu cuma melihat pesan soal Cashier, seolah Gardener
    -- tidak diperiksa sama sekali.
    local function sapu()
        local total, gawat, pesan = 0, false, {}
        local adaRole, lagi = false, false
        for _, role in ipairs(ROLES) do
            if setAllows(sel.hireRoles, role) then
                adaRole = true
                local n, w, g, l = naikkanRole(role)
                total = total + n
                if g then gawat = true end
                if l then lagi = true end
                if n == 0 and w then pesan[#pesan + 1] = w end
            end
        end
        if not adaRole then
            pesan[1] = "dropdown 'Staff Roles to Hire' tidak mencentang" ..
                       " Gardener maupun Cashier"
        end
        -- naikkanRole menyetel SU.jeda dari nextRefresh - itu waktu bangun
        -- yang benar untuk "pelamar baru". TAPI ada pekerjaan yang tidak
        -- bergantung pelamar baru sama sekali: slot kosong yang cuma
        -- kekurangan cash. Untuk itu tidurnya dipotong, kalau tidak dia
        -- bisa diam sampai 300 detik dengan slot menganggur.
        if lagi then SU.jeda = math.min(SU.jeda, 30) end
        SU.pesan = (#pesan > 0) and table.concat(pesan, "  |  ") or nil
        return total, SU.pesan, gawat
    end

    -- SATU BADAN KERJA untuk DUA pemicu: loop berjadwal DAN event
    -- StaffHired/StaffFired. Dijaga supaya tidak pernah jalan dobel -
    -- sapu() itu belasan panggilan server dengan jeda di dalamnya, dan
    -- pemecatan kita sendiri ikut memicu StaffFired.
    local function putaran()
        if SU.sibuk then return end
        SU.sibuk = true
        local ok, total, pesan, gawat = pcall(sapu)
        SU.sibuk = false
        SU.usai  = os.clock()
        if not ok then
            addLog("Naik bintang error: " .. tostring(total), "STAFF")
            return
        end
        if gawat then
            -- Slot tertinggal kosong. Berhenti total: fitur ini memakai
            -- uang, jadi tidak boleh terus jalan saat keadaannya sudah di
            -- luar rencana.
            state.aUpStaff = false
            stopLoop("upStaff")
            samakanSakelar()
            notify("BAHAYA: " .. tostring(pesan), THEME.Red)
            addLog("Auto naik bintang DIMATIKAN: " .. tostring(pesan), "STAFF")
        elseif total > 0 then
            notify("Naik bintang: " .. total .. " staff ditukar", THEME.On)
            if tampil(ShopBody) then gambar() end
        elseif pesan then
            addLog("Naik bintang: " .. pesan, "STAFF")
            -- Kotak status ikut disegarkan walau tidak ada yang ditukar.
            -- Tanpa ini alasannya cuma masuk addLog, dan addLog DIAM TOTAL
            -- kalau tab Output belum dinyalakan - jadi loopnya kelihatan
            -- seperti tidak mengerjakan apa-apa.
            if tampil(ShopBody) then gambar() end
        end
    end

    -- ============================================================
    -- PEMICU INSTAN SAAT SUSUNAN STAFF BERUBAH
    -- ============================================================
    -- Loop di bawah tidur sampai PELAMAR berganti (bisa 300 detik). Tapi
    -- memecat staff TIDAK mengubah daftar pelamar sama sekali - jadi
    -- kalau kamu memecat manual dari panel game, tidak ada apa pun yang
    -- membangunkan loopnya, dan slot itu menganggur sampai pergantian
    -- pelamar berikutnya.
    --
    -- Server mengirim dua event ini tiap kali susunan staff berubah, dan
    -- UI game sendiri memakainya untuk hal yang sama (StaffController
    -- 10604-10609 -> RefreshIfVisible). Jadi ini jalur resminya, bukan
    -- tebakan.
    for _, ev in ipairs({ "StaffHired", "StaffFired" }) do
        local re = getRemote("StaffService", "RE", ev)
        if re then
            track(re.OnClientEvent:Connect(function()
                if not state.aUpStaff then return end
                -- Pemecatan & perekrutan KITA SENDIRI juga memicu event
                -- ini. SU.sibuk menyaring yang datang di tengah sapuan;
                -- jeda 2 detik menyaring yang datang persis sesudahnya,
                -- supaya satu pertukaran tidak memantul jadi dua sapuan.
                if SU.sibuk or (os.clock() - SU.usai) < 2 then return end
                task.wait(0.3)   -- beri server waktu menyelesaikan datanya
                putaran()
            end))
        end
    end

    -- Tombol CEK ini sengaja DIPERTAHANKAN walau tombol NAIKKAN sudah
    -- menggambar sendiri: yang ini TIDAK MEMBELI apa pun. Sebelum
    -- mengeluarkan puluhan ribu, wajar kalau kamu mau melihat dulu tanpa
    -- risiko salah pencet.
    makeButton(c, "🔍 CEK SAJA (tidak beli apa-apa)", THEME.Blue, function()
        task.spawn(gambar)
    end)

    makeButton(c, "⬆ NAIKKAN SEKARANG (cek + langsung kerjakan)", THEME.Green, function()
        task.spawn(function()
            -- DIGAMBAR DULU, SEBELUM APA-APA DIKERJAKAN.
            -- Dulu gambar() cuma dipanggil SESUDAH sapu(), dan sapu() itu
            -- makan beberapa detik (banyak panggilan server + jeda). Jadi
            -- selama itu kotak di atas masih menampilkan teks "tekan
            -- tombol dulu", dan kamu terpaksa menekan DUA tombol untuk
            -- satu pekerjaan. Sekarang tombol ini sudah cukup sendiri.
            -- Loop / event bisa sedang menyapu saat kamu menekan ini.
            -- Menumpuknya berarti dua sapuan berebut slot yang sama.
            if SU.sibuk then
                notify("Sapuan otomatis sedang jalan - tunggu sebentar", THEME.Yellow)
                return
            end
            gambar()
            SU.sibuk = true
            local ok, total, pesan, gawat = pcall(sapu)
            SU.sibuk = false
            SU.usai  = os.clock()
            if not ok then
                notify("Gagal: " .. tostring(total), THEME.Red)
                return
            end
            gambar()   -- gambar ULANG: isinya berubah sesudah ada pertukaran
            if gawat then
                notify("BAHAYA: " .. tostring(pesan), THEME.Red)
            else
                notify(total > 0 and ("Naik bintang: " .. total .. " staff ditukar")
                                  or ("Tidak ada yang ditukar - " .. tostring(pesan)),
                       total > 0 and THEME.On or THEME.Yellow)
            end
        end)
    end)

    makeToggle(c, "AUTO naikkan bintang staff", THEME.Green, function(v)
        state.aUpStaff = v
        if v then
            startLoop("upStaff", putaran, function() return SU.jeda end)
            notify("Auto naik bintang ON - bangun tiap staff/pelamar berubah", THEME.On)
        else
            stopLoop("upStaff")
            notify("Auto naik bintang OFF", THEME.Off)
        end
    end, "aUpStaff")

    makeInfo(c, "KAPAN DIA BANGUN - tiga sumber, dan tidak ada polling di antaranya.\n\n  1. EVENT DARI SERVER: StaffService.RE.StaffHired / StaffFired.\n     Tiap kali susunan staffmu berubah - TERMASUK kamu memecat\n     sendiri dari panel game - dia bangun detik itu juga. Ini jalur\n     resmi, bukan tebakan: UI game sendiri memakai dua event yang\n     sama (StaffController 10604-10609 -> RefreshIfVisible).\n\n  2. PELAMAR BERGANTI. Server mengirim sisa waktunya bersama\n     daftarnya (nextRefresh & serverTime), jadi dia tidur TEPAT\n     sampai daftarnya benar-benar baru.\n\n  3. SLOT MASIH KOSONG (cash kurang / pelamar habis) -> tidurnya\n     dipotong jadi 30 detik. Cash bisa naik dari checkout kapan\n     saja, dan slot kosong itu nol hasil.\n\nKalau slot penuh dan tidak ada pelamar yang lebih tinggi, dia\ntidur penuh sampai pergantian pelamar - nol panggilan server di\nantaranya. Bandingkan Auto Hire biasa yang menembak tiap 25 detik\nwalau isinya belum berubah sedetik pun.\n\nKotak status di atas sengaja TIDAK punya loop - digambar cuma saat\nkamu menekan tombolnya atau sesudah ada perubahan.\n\nFilter role ikut dropdown 'Staff Roles to Hire' di kartu atas:\nkosong = dua-duanya (Gardener + Cashier).")

    makeInfo(c, "SLOT MASIH KOSONG? TIDAK ADA YANG DIPECAT.\n\nSelama jumlah staff masih di bawah Limit, hub cuma HIRE pelamar\nber-bintang TERTINGGI yang ada - tidak ada yang dikorbankan.\nPemecatan baru terjadi kalau slotnya sudah penuh DAN ada pelamar\nyang lebih tinggi daripada staff terendahmu.\n\nAngka Limit-nya dibaca dari server (GetStaffLimits), jadi ikut\nnaik sendiri kalau kamu meng-upgrade-nya di game.\n\nTIDAK ADA UANG KEMBALI dari memecat - pencarian refund /\nsellStaff / sellPrice di seluruh dump client = nol hasil. Jadi\ntiap tukar itu bayar penuh, dan yang lama hangus:\n\n  bintang     1        2         3         4         5\n  Gardener   1.500    3.000    13.500    42.000    97.500\n  Cashier    2.000    4.000    18.000    56.000   130.000\n\nPerhatikan lompatannya: dari 4 ke 5 itu lebih dari dua kali\nlipat, karena rumusnya ceil(base + (bintang-1)^3 x per).\n\nHub tidak akan menukar dengan bintang yang SAMA atau lebih rendah.\n\nUANG DIPERIKSA TIGA KALI, DAN SEMUANYA SEBELUM ADA YANG DIPECAT.\nDulu cuma satu, dan itu bocor - kejadiannya begini: probe 'coba\nhire walau slot penuh' ditolak server karena UANG, tapi hub\nmembacanya sebagai 'server tidak izinkan hire saat penuh', lalu\nlanjut ke jalur pecat-dulu. Hasilnya staf terendah DIPECAT, hire\npenggantinya ditolak lagi (uangnya memang tetap kurang), dan\nkamu kehilangan satu staf tanpa dapat apa pun. Lebih parah,\ncatatan salah itu dikenang SELURUH SESI.\n\nSekarang:\n\n  1. SAAT MEMILIH. Yang diambil pelamar bintang TERTINGGI yang\n     harganya MASIH TERJANGKAU. Kalau tidak ada satupun yang\n     terjangkau, hub berhenti dan menyebut angkanya: butuh $X,\n     cash kamu $Y, kurang $Z. Nol pemecatan, nol uang keluar.\n\n  2. SAAT PROBE DITOLAK. Kalau pesan penolakan server menyebut\n     uang, itu TIDAK lagi dianggap 'slot penuh' - hub berhenti di\n     situ, tidak memecat, dan tidak mencatat apa-apa.\n\n  3. SATU BARIS SEBELUM MEMECAT. Cash dibaca ULANG. Antara\n     pemeriksaan pertama dan titik ini sudah ada satu panggilan\n     server penuh, dan selama itu cash-mu bisa turun tanpa ada\n     hubungannya dengan fitur ini - Auto Buy Bibit / Supply /\n     Upgrades jalan di loop lain dan memotong cash yang sama.\n\nDan kalau CASH TIDAK TERBACA sama sekali (replica gagal) sementara\nslotnya penuh, hub TIDAK memecat siapa pun - dia turun jadi 'hire\nkalau masih ada tempat'. Aturannya sama dengan 'batas slot tidak\nterbaca': lebih baik tidak naik daripada memecat tanpa dasar.")

end

do
    local c = makeCard("📦 STOK TOKO (manual)", THEME.Blue, ShopBody)

    local shopPick = "SeedShop"
    makeDropdown(c, "Shop", { "SeedShop", "SupplyShop", "DecorShop" }, function(item)
        shopPick = item
        notify("Shop: " .. item, THEME.Blue)
    end, "SeedShop")

    local stockLbl = makeInfo(c, "tekan 'Lihat Stok' untuk memuat...")

    makeButton(c, "📦 Lihat Stok Sekarang", THEME.Blue, function()
        task.spawn(function()
            local lines = stockLabels(shopPick)
            local ok, secs = invokeRF("ShopService", "GetTimeUntilRefresh", shopPick)
            local head = "STOK " .. shopPick
            if ok and type(secs) == "number" then head = head .. "  (refresh " .. math.floor(secs) .. "s)" end
            stockLbl.Text = head .. "\n" .. table.concat(lines, "\n")
            addLog(head, "SHOP")
        end)
    end)

    -- ANGKA YANG SAMA dengan kotak "Jumlah BIBIT per barang" di kartu
    -- AUTO SHOP dan di tab Auto - satu config, tiga kotak, disamakan
    -- samakanAngka(). Dulu di sini SLIDER; diganti kotak angka supaya
    -- bisa diketik, dan supaya tidak ada dua bentuk kontrol untuk satu
    -- angka yang sama.
    makeNumber(c, "Jumlah BIBIT per barang", 1, 50000, THEME.Blue, "buyQty")

    makeInfo(c, "Angka di atas cuma untuk SeedShop. Untuk SupplyShop dan\nDecorShop server SELALU menerima 1 per pembelian - itu bukan\nbatasan script, tapi aturan game: ShopController-nya sendiri\nmenulis\n   BuyItem(shop, index, if shop == \"SeedShop\" then qty else 1)\n\nJadi untuk dua toko itu jumlahnya dicapai dengan MENGULANG\npanggilan, dan angkanya ada di kotak 'Jumlah SUPPLY per barang'\ndi kartu AUTO SHOP - bukan di sini.\n\nDULU script ini mengirim angka yang sama ke SEMUA toko, dan\nbegitu kamu menaikkannya di atas 1 supply jadi TIDAK PERNAH\nKEBELI sementara bibit tetap jalan.\n\nCATATAN untuk DUA TOMBOL BORONG di bawah: keduanya SELALU\nmenghabiskan stok, jadi angka di atas TIDAK membatasi mereka -\ndia cuma dipakai sebagai qty per panggilan di SeedShop. Kalau\nkamu mau berhenti di angka tertentu, pakai Auto Buy di kartu\nAUTO SHOP, bukan tombol BORONG.")

    -- Dua tombol ini SELALU menghabiskan stok, tidak ikut sakelar
    -- config.habisStok. Namanya BORONG dan ada konfirmasinya, jadi
    -- "beli 1 biji tiap barang" memang bukan yang kamu minta di sini.
    makeButton(c, "🛍 BORONG SEMUA STOK (Cash, sampai habis)", THEME.Orange, function()
        confirmDialog("Borong " .. shopPick .. " sampai STOKNYA HABIS?\n" ..
                      "Tiap barang dibeli berulang, bukan 1 biji.", function()
            task.spawn(function()
                local n, why = buyFromShop(shopPick, {}, config.buyQty, false, true, true)
                notify(n > 0 and ("Borong " .. n .. " item OK")
                              or ("Tidak ada yang dibeli - " .. tostring(why)),
                       n > 0 and THEME.On or THEME.Yellow)
            end)
        end)
    end)

    makeButton(c, "💎 BORONG SEMUA (Gems, sampai habis)", THEME.Purple, function()
        confirmDialog("Borong " .. shopPick .. " sampai STOKNYA HABIS pakai GEMS?", function()
            task.spawn(function()
                local n, why = buyFromShop(shopPick, {}, 1, true, true, true)
                notify(n > 0 and ("Borong (gems) " .. n .. " item OK")
                              or ("Tidak ada yang dibeli - " .. tostring(why)),
                       n > 0 and THEME.On or THEME.Yellow)
            end)
        end)
    end)

    makeButton(c, "🔄 Refresh Toko", THEME.Blue, function()
        local ok = invokeRF("ShopService", "RefreshStore", shopPick)
        notify(ok and "RefreshStore dikirim OK" or "Gagal refresh", ok and THEME.On or THEME.Red)
    end)

    makeButton(c, "🆔 GetAllShopIds + GetShopInfo", THEME.Purple, function()
        task.spawn(function()
            local ok, ids = invokeRF("ShopService", "GetAllShopIds")
            if ok and type(ids) == "table" then
                for _, id in pairs(ids) do
                    addLog("ShopId: " .. tostring(id), "SHOP")
                    local iok, info = invokeRF("ShopService", "GetShopInfo", id)
                    if iok and type(info) == "table" then
                        for k, v in pairs(info) do
                            addLog("   " .. tostring(k) .. " = " .. tostring(v), "SHOP")
                        end
                    end
                    task.wait(0.15)
                end
                notify("Daftar shop dikirim ke Output OK", THEME.On)
            else
                notify("GetAllShopIds gagal", THEME.Red)
            end
        end)
    end)
end

-- ============================================================
-- STOK ASLI - kartu yang menjawab "kenapa gak kebeli"
-- ============================================================
do
    local c = makeCard("🔍 STOK ASLI (kenapa tidak kebeli)", THEME.Red, ShopBody)

    makeInfo(c, "INI JAWABAN 'SUPPLY-NYA ADA KOK TAPI GAK KEBELI', dan sudah\ndicek langsung di kode game - bukan dikira-kira.\n\nSyarat sebuah barang boleh dibeli, disalin apa adanya dari\nShopController milik game (fungsi applyBuyState):\n\n   v3 = if (lastStock or 0) > 0\n        then not streakLocked and not levelKurang\n        else false\n   buyBtn.Active = v3\n\nJadi ada TIGA gerbang: STOK > 0, tidak dikunci streak login, dan\nlevel cukup. Untuk SUPPLY gerbang levelnya tidak berlaku (game\nmengambil requiredLevel dari MenuConfig.Seeds, yang memang tidak\nberisi supply). Sisanya: STOK dan KUNCI STREAK.\n\nMASALAHNYA, GetShopStock - satu-satunya cara hub membaca toko -\ncuma mengembalikan { nama, harga }. TIDAK ADA stok, TIDAK ADA\nkunci. Jadi selama ini hub menembak barang berstok NOL, server\nmenolak, dan penolakannya dibuang tanpa dicatat.\n\nItu persis kenapa dulu kebeli dan sekarang tidak: dulu stoknya\nmemang masih ada.")

    makeInfo(c, "SEKARANG hub ikut mendengarkan RemoteEvent yang membawa angka\naslinya:\n\n   ShopService.RE.StockRefreshed(shopId, {\n       { Name = \"Fertilizer\", Stock = 3, Locked = false }, ...\n   })\n\nItu event yang sama yang dipakai game untuk menulis 'x3 stock' di\nkartunya. Barang berstok 0 sekarang DILEWATI (tidak dibuang jadi\npanggilan sia-sia), dan alasannya dilaporkan apa adanya.\n\nKalau tabelnya masih kosong: buka panel toko di GAME sekali saja.\nServer baru mengirim StockRefreshed sesudah itu. Sesudah sekali\nterbuka, hub terus menerima pembaruannya sendiri.")

    makeInfo(c, "SEBAB KEDUA, DAN INI YANG BIKIN AUTO BUY DIAM TOTAL - terukur\n21/08/2026 dari log-mu, bukan dugaan:\n\n   DIJUAL sekarang (GetShopStock): nil, nil, nil, nil, nil, nil,\n                                   nil, nil, nil\n\nSembilan entri, KESEMBILAN namanya nil. Jadi bukan stok, bukan\ncash, bukan Lock - hub tidak dapat SATU nama pun, jadi tidak ada\nyang cocok dan NOL remote ditembak. Sakelarnya kelihatan mati\npadahal dia bekerja dengan daftar kosong.\n\nAkarnya kesalahan SAYA: bentuk { nama, harga } untuk GetShopStock\nitu ASUMSI yang saya tulis di kepala file, dan catatan saya\nsendiri sudah menandai remote itu NOL call-site di client - jadi\nmemang tidak pernah ada yang membuktikannya. Sekarang terukur\nbahwa bentuknya bukan itu.\n\nYANG DIPAKAI SEKARANG, urut dari yang paling terbukti:\n  1. SetupShopUI      - array resmi dari server\n  2. KARTU TOKO GAME  - yang tulisannya 'x3 stock' di layarmu.\n     Kartu itu disusun DARI array yang sama, jadi urutannya =\n     index yang diterima BuyItem. Satu tempat memberi nama,\n     urutan, DAN stok sekaligus.\n  3. GetShopStock     - cadangan terakhir, namanya dibaca longgar\n     (dicoba entry[1], Name, name, Item, Type)\n\nKENAPA nomor 1 bisa terlewat: SetupShopUI dikirim saat panel toko\nDIBANGUN. Kalau panelnya sudah terbuka SEBELUM hub dieksekusi,\neventnya sudah lewat dan tidak datang lagi. Nomor 2 yang menutup\ncelah itu - dan di screenshot-mu panelnya memang sedang terbuka.\n\nKalau nama tetap tidak terbaca, hub mencetak BENTUK MENTAHNYA ke\ntab Output sekali - lengkap dengan nama field-nya. Jadi lain kali\ntidak ada yang perlu ditebak lagi.")

    local stokLbl = makeInfo(c, "-")

    local function gambarStok()
        local baris = {}
        for _, shopId in ipairs({ "SeedShop", "SupplyShop", "DecorShop" }) do
            local tabel = TOKO.stok[shopId]
            baris[#baris + 1] = shopId .. ":"
            if not tabel or next(tabel) == nil then
                baris[#baris + 1] = "  (belum terbaca - buka panel toko di game sekali)"
            else
                -- urut abjad supaya tidak lompat-lompat tiap detik
                local nama = {}
                for k in pairs(tabel) do nama[#nama + 1] = k end
                table.sort(nama)
                for _, k in ipairs(nama) do
                    local e = tabel[k]
                    local tanda
                    if e.kunci then
                        tanda = "TERKUNCI streak" .. (e.hari and (" " .. e.hari .. " hari") or "")
                    elseif (e.sisa or 0) <= 0 then
                        tanda = "HABIS"
                    else
                        tanda = "bisa dibeli"
                    end
                    baris[#baris + 1] = string.format("  %-24s x%-3s %s%s",
                        k, tostring(e.sisa or 0), tanda, e.ui and "  (dari label game)" or "")
                end
            end
            baris[#baris + 1] = ""
        end
        -- ALASAN TERAKHIR AUTO BUY, ditulis PERMANEN di sini. Sebelum ini
        -- alasannya cuma lewat toast 2 detik + addLog, dan addLog DIAM kalau
        -- tab Output belum dinyalakan - jadi "sakelar ON tapi tidak kebeli"
        -- tidak punya jejak apa pun di layar.
        local ada = false
        for _, shopId in ipairs({ "SeedShop", "SupplyShop", "DecorShop" }) do
            if type(_stockWarn[shopId]) == "string" then
                if not ada then
                    baris[#baris + 1] = "ALASAN TERAKHIR AUTO BUY:"
                    ada = true
                end
                baris[#baris + 1] = "  " .. shopId .. ": " .. _stockWarn[shopId]
            end
        end
        if not ada then
            baris[#baris + 1] = "ALASAN TERAKHIR AUTO BUY: (belum ada kegagalan)"
        end
        stokLbl.Text = table.concat(baris, "\n")
    end

    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan (lihat tampil()).
            while ScreenGui.Parent and not tampil(ShopBody) do task.wait(0.4) end
            gambarStok()
            task.wait(2)
        end
    end)

    makeButton(c, "🔄 BACA STOK ASLI SEKARANG (dari label game)", THEME.Blue, function()
        task.spawn(function()
            local n = 0
            for _, s in ipairs({ "SeedShop", "SupplyShop", "DecorShop" }) do
                n = n + TOKO.dariUI(s)
            end
            gambarStok()
            notify(n > 0 and (n .. " barang terbaca dari kartu toko game")
                          or "Kartu toko game belum ada - buka panel tokonya sekali",
                   n > 0 and THEME.On or THEME.Yellow)
        end)
    end)

    makeButton(c, "🧪 UJI BELI 1x (lihat balasan mentah server)", THEME.Orange, function()
        task.spawn(function()
            -- Menembak SATU barang supply yang dicentang, lalu mencetak
            -- balasan server APA ADANYA. Ini alat pamungkas kalau stok
            -- sudah jelas ada tapi tetap tidak kebeli: kita berhenti
            -- menebak dan membaca alasan server langsung.
            local stock = getStock("SupplyShop")
            if not stock then notify("GetShopStock(SupplyShop) tidak menjawab", THEME.Red); return end
            if not logEnabled then
                logEnabled = true
                outToggleBtn.Text = "Output: ON"
                outToggleBtn.BackgroundColor3 = THEME.On
            end
            addLog("=== UJI BELI SupplyShop ===", "SHOP")
            for i, e in ipairs(stock) do
                addLog(string.format("  [%d] %s  $%s", i, tostring(e[1]), tostring(e[2])), "SHOP")
            end
            local target, idx
            for i, e in ipairs(stock) do
                if sel.buySupplies[e[1]] then target, idx = e[1], i; break end
            end
            if not target then target, idx = stock[1] and stock[1][1], 1 end
            if not target then notify("Stok SupplyShop kosong", THEME.Yellow); return end

            local sisa, kunci, tahu = TOKO.info("SupplyShop", target)
            addLog("Sasaran: " .. tostring(target) .. " (index " .. idx .. ")  " ..
                   (tahu and ("stok terbaca=" .. sisa .. " terkunci=" .. tostring(kunci))
                          or "stok BELUM terbaca"), "SHOP")

            local ok, res, msg = invokeRF("ShopService", "BuyItem", "SupplyShop", idx, 1)
            addLog("BuyItem('SupplyShop', " .. idx .. ", 1) -> pcall=" .. tostring(ok) ..
                   "  hasil=" .. tostring(res) .. "  pesan=" .. tostring(msg), "SHOP")
            notify("Hasil mentah dikirim ke Output", THEME.On)
            showTab("output")
        end)
    end)

    makeInfo(c, "Tombol UJI BELI menembak SATU supply yang kamu centang lalu\nmencetak balasan server APA ADANYA ke tab Output - termasuk\npesan penolakannya. Kalau stok jelas ada tapi tetap ditolak,\nkalimat dari server itu yang akan memberitahu alasannya, dan\nkita berhenti menebak.")
end

-- IngredientService SENGAJA tidak dibuatkan kartu: sudah diukur, dan
-- GetInventory balik { SideDishes, Toppings } - bahan RAMEN, bukan
-- bunga. Tidak ada bibit / bunga / rangkaian yang lewat situ. Kalau
-- suatu saat perlu dipanggil lagi, pakai KONSOL REMOTE UNIVERSAL.

task.wait()   -- jeda satu frame (lihat PEMBANGUNAN BERTAHAP di atas)

-- ============================================================
-- BUILD UI : TAB BUILD
-- ============================================================
do
    -- kelipatan 45 derajat, sesuai PlacementController. Dideklarasi DI DALAM
    -- blok ini supaya registernya dibebaskan saat blok selesai.
    local ROTATIONS = { "0", "45", "90", "135", "180", "225", "270", "315" }

    local c = makeCard("🔨 AUTO BUILD", THEME.Orange, BuildBody)

    makeInfo(c, "Di game ini BELI = PASANG.\nPlacementService.RF.Place() langsung memotong uang dan\nmenaruh objek di plot. Titik kosong dicari otomatis di atas\nPlotBase (zona Farm untuk planter, Shop untuk display).")

    makeToggle(c, "Auto Buy Planters", THEME.Orange, function(v)
        state.autoBuyPlanter = v
        if v then
            if setIsEmpty(sel.buyPlanters) then notify("Pilih planter dulu!", THEME.Yellow) end
            startLoop("buyplanter", function()
                placeSelected(sel.buyPlanters, config.planterRotation, function() return state.autoBuyPlanter end)
            end, function() return math.max(config.buildDelay * 4, 3) end)
            notify("Auto Buy Planters ON", THEME.On)
        else
            stopLoop("buyplanter"); notify("Auto Buy Planters OFF", THEME.Off)
        end
    end, "autoBuyPlanter")
    makeMultiDropdown(c, "Planters to Buy", planterLabels, sel.buyPlanters, "None", stripLabel)

    makeToggle(c, "Auto Buy Displays", THEME.Orange, function(v)
        state.autoBuyDisplay = v
        if v then
            if setIsEmpty(sel.buyDisplays) then notify("Pilih display dulu!", THEME.Yellow) end
            startLoop("buydisplay", function()
                placeSelected(sel.buyDisplays, config.displayRotation, function() return state.autoBuyDisplay end)
            end, function() return math.max(config.buildDelay * 4, 3) end)
            notify("Auto Buy Displays ON", THEME.On)
        else
            stopLoop("buydisplay"); notify("Auto Buy Displays OFF", THEME.Off)
        end
    end, "autoBuyDisplay")
    makeMultiDropdown(c, "Displays to Buy", displayLabels, sel.buyDisplays, "None", stripLabel)

    makeToggle(c, "Auto Place Planters", THEME.Orange, function(v)
        state.autoPlacePlanter = v
        if v then
            if setIsEmpty(sel.placePlanters) then notify("Pilih planter dulu!", THEME.Yellow) end
            startLoop("placeplanter", function()
                placeSelected(sel.placePlanters, config.planterRotation, function() return state.autoPlacePlanter end)
            end, function() return config.buildDelay end)
            notify("Auto Place Planters ON", THEME.On)
        else
            stopLoop("placeplanter"); notify("Auto Place Planters OFF", THEME.Off)
        end
    end, "autoPlacePlanter")
    makeMultiDropdown(c, "Planters to Place", planterLabels, sel.placePlanters, "None", stripLabel)

    makeToggle(c, "Auto Place Displays", THEME.Orange, function(v)
        state.autoPlaceDisplay = v
        if v then
            if setIsEmpty(sel.placeDisplays) then notify("Pilih display dulu!", THEME.Yellow) end
            startLoop("placedisplay", function()
                placeSelected(sel.placeDisplays, config.displayRotation, function() return state.autoPlaceDisplay end)
            end, function() return config.buildDelay end)
            notify("Auto Place Displays ON", THEME.On)
        else
            stopLoop("placedisplay"); notify("Auto Place Displays OFF", THEME.Off)
        end
    end, "autoPlaceDisplay")
    makeMultiDropdown(c, "Displays to Place", displayLabels, sel.placeDisplays, "None", stripLabel)

    makeDropdown(c, "Planter Rotation", ROTATIONS, function(item)
        config.planterRotation = tonumber(item) or 0
    end, "0")

    makeDropdown(c, "Display Rotation", ROTATIONS, function(item)
        config.displayRotation = tonumber(item) or 0
    end, "0")

    makeSlider(c, "Build Delay", config.buildDelay, 0.1, 3, THEME.Orange, function(v) config.buildDelay = v end)
    makeSlider(c, "Jarak Grid (stud)", config.gridStep, 4, 24, THEME.Orange, function(v) config.gridStep = v end)
end

do
    local c = makeCard("🧱 AKSI BUILD MANUAL", THEME.Blue, BuildBody)

    local getPlanter = makeDropdown(c, "Planter", planterLabels, function() end, "None")
    makeButton(c, "➕ Pasang 1 Planter", THEME.Green, function()
        task.spawn(function()
            local nm = stripLabel(getPlanter())
            if not nm then notify("Pilih planter dulu", THEME.Yellow); return end
            local ok, err = placeItem(nm, config.planterRotation)
            notify(ok and ("Pasang " .. nm .. " OK") or ("Gagal: " .. tostring(err)), ok and THEME.On or THEME.Red)
        end)
    end)

    local getDisplay = makeDropdown(c, "Display", displayLabels, function() end, "None")
    makeButton(c, "➕ Pasang 1 Display", THEME.Green, function()
        task.spawn(function()
            local nm = stripLabel(getDisplay())
            if not nm then notify("Pilih display dulu", THEME.Yellow); return end
            local ok, err = placeItem(nm, config.displayRotation)
            notify(ok and ("Pasang " .. nm .. " OK") or ("Gagal: " .. tostring(err)), ok and THEME.On or THEME.Red)
        end)
    end)

    local getDecor = makeDropdown(c, "Decor", decorNames, function() end, "None")
    makeButton(c, "➕ Pasang 1 Decor", THEME.Purple, function()
        task.spawn(function()
            local nm = getDecor()
            if not nm then notify("Pilih decor dulu", THEME.Yellow); return end
            local ok, err = placeItem(nm, config.planterRotation)
            notify(ok and ("Pasang " .. nm .. " OK") or ("Gagal: " .. tostring(err)), ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "🗺 Cek Zona Build", THEME.Blue, function()
        local farm = getZoneBase("Farm")
        local shop = getZoneBase("Store")
        local msg = "Farm base: " .. (farm and (math.floor(farm.Size.X) .. "x" .. math.floor(farm.Size.Z)) or "?") ..
                    "  |  Shop base: " .. (shop and (math.floor(shop.Size.X) .. "x" .. math.floor(shop.Size.Z)) or "?")
        notify(msg, (farm and shop) and THEME.On or THEME.Yellow)
        addLog(msg, "BUILD")
    end)

    local buildLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(BuildBody) do task.wait(0.4) end
            local plot = getMyPlot()
            local objects = plot and plot:FindFirstChild("Objects")
            buildLbl.Text = table.concat({
                "Objek terpasang : " .. (objects and #objects:GetChildren() or 0),
                "Planter         : " .. #getMyPlanters(),
                "Rak bunga       : " .. #rakPlot("FlowerDisplay"),
                "Rak rangkaian   : " .. #rakPlot("ArrangementDisplay"),
                "Katalog         : " .. #planterNames() .. " planter, " ..
                                        #displayNames() .. " display, " .. #decorNames() .. " decor",
            }, "\n")
            task.wait(3)
        end
    end)
end

-- Sisa remote PlacementService yang belum terpakai:
--   Delete(model), Move(model, CFrame, "Furniture"), EnterBuild(),
--   SkipConstruction(), NextDecorLimitCost(), PurchaseBuildingStyle(nama),
--   SwapBuildingStyle(nama), ChangeColor(model, {warna})
do
    local c = makeCard("🧹 KELOLA OBJEK TERPASANG", THEME.Red, BuildBody)

    -- daftar objek yang sudah dipasang di plot
    local function placedLabels()
        local plot = getMyPlot()
        local objects = plot and plot:FindFirstChild("Objects")
        local out = {}
        if objects then
            for i, m in ipairs(objects:GetChildren()) do
                out[#out + 1] = i .. ". " .. m.Name ..
                    "  [" .. tostring(m:GetAttribute("Id") or "?") .. "]"
            end
        end
        if #out == 0 then out[1] = "(belum ada objek terpasang)" end
        return out
    end

    local function placedByLabel(label)
        if not label then return nil end
        local idx = tonumber(string.match(label, "^(%d+)%."))
        if not idx then return nil end
        local plot = getMyPlot()
        local objects = plot and plot:FindFirstChild("Objects")
        return objects and objects:GetChildren()[idx]
    end

    local getPlaced = makeDropdown(c, "Objek", placedLabels, function() end, "None")

    makeButton(c, "🗑 HAPUS objek terpilih", THEME.Red, function()
        local m = placedByLabel(getPlaced())
        if not m then notify("Pilih objek dulu", THEME.Yellow); return end
        confirmDialog("Hapus '" .. m.Name .. "' dari plot?", function()
            task.spawn(function()
                local ok, res, err = invokeRF("PlacementService", "Delete", m)
                addLog("Delete(" .. m.Name .. ") -> " .. tostring(res) .. " " .. tostring(err), "BUILD")
                notify(ok and "Delete dikirim" or "Gagal hapus", ok and THEME.On or THEME.Red)
            end)
        end)
    end)

    makeButton(c, "📦 Pindah objek ke titik kosong", THEME.Blue, function()
        task.spawn(function()
            local m = placedByLabel(getPlaced())
            if not m then notify("Pilih objek dulu", THEME.Yellow); return end
            local zone = m:GetAttribute("PlaceZone") or "Farm"
            local pos = findFreeSpot(zone, config.gridStep)
            if not pos then notify("Tidak ada tempat kosong di " .. zone, THEME.Yellow); return end
            local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(config.planterRotation), 0)
            local ok, res, err = invokeRF("PlacementService", "Move", m, cf, "Furniture")
            addLog("Move(" .. m.Name .. ") -> " .. tostring(res) .. " " .. tostring(err), "BUILD")
            notify(ok and "Move dikirim" or "Gagal pindah", ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "🗑 HAPUS SEMUA objek (hati-hati!)", THEME.Red, function()
        local plot = getMyPlot()
        local objects = plot and plot:FindFirstChild("Objects")
        local n = objects and #objects:GetChildren() or 0
        if n == 0 then notify("Tidak ada objek", THEME.Yellow); return end
        confirmDialog("HAPUS SEMUA " .. n .. " objek di plot?\nIni TIDAK bisa dibatalkan.", function()
            task.spawn(function()
                local done = 0
                for _, m in ipairs(objects:GetChildren()) do
                    invokeRF("PlacementService", "Delete", m)
                    done = done + 1
                    task.wait(turboDelay(config.buildDelay))
                end
                notify("Delete dikirim untuk " .. done .. " objek", THEME.On)
            end)
        end)
    end)

    -- ChangeColor(model, {PrimaryColor=Color3, SecondaryColor=Color3})
    -- Bentuk tabel warnanya diambil dari PlacementController baris 532-538.
    local COLORS = {
        ["Putih"]  = Color3.fromRGB(255, 255, 255),
        ["Hitam"]  = Color3.fromRGB(30, 30, 30),
        ["Merah"]  = Color3.fromRGB(220, 60, 60),
        ["Pink"]   = Color3.fromRGB(255, 130, 190),
        ["Kuning"] = Color3.fromRGB(255, 215, 80),
        ["Hijau"]  = Color3.fromRGB(110, 200, 110),
        ["Biru"]   = Color3.fromRGB(80, 150, 235),
        ["Ungu"]   = Color3.fromRGB(160, 110, 220),
        ["Coklat"] = Color3.fromRGB(130, 90, 60),
    }
    local colorOrder = { "Putih", "Hitam", "Merah", "Pink", "Kuning", "Hijau", "Biru", "Ungu", "Coklat" }

    local primaryPick, secondaryPick = "Putih", "Putih"
    makeDropdown(c, "Warna Utama", colorOrder, function(i) primaryPick = i end, "Putih")
    makeDropdown(c, "Warna Kedua", colorOrder, function(i) secondaryPick = i end, "Putih")

    makeButton(c, "🎨 ChangeColor objek terpilih", THEME.Pink, function()
        task.spawn(function()
            local m = placedByLabel(getPlaced())
            if not m then notify("Pilih objek dulu", THEME.Yellow); return end
            local payload = {
                PrimaryColor   = COLORS[primaryPick]   or Color3.new(1, 1, 1),
                SecondaryColor = COLORS[secondaryPick] or Color3.new(1, 1, 1),
            }
            local ok, res, err = invokeRF("PlacementService", "ChangeColor", m, payload)
            addLog("ChangeColor(" .. m.Name .. ", " .. primaryPick .. "/" .. secondaryPick ..
                   ") -> " .. tostring(res) .. " " .. tostring(err), "BUILD")
            notify(ok and ("Warna " .. m.Name .. " diubah") or "Gagal ubah warna",
                   ok and THEME.On or THEME.Red)
        end)
    end)
end

do
    local c = makeCard("🏛 BANGUNAN & GAYA", THEME.Purple, BuildBody)

    -- nama gaya dibaca runtime dari Assets.StyleFolder (Zen Harmony, dll)
    local function styleNames()
        local f = assetFolder("StyleFolder") or assetFolder("Styles")
        local out = childNames(f)
        if #out == 0 then out[1] = "(StyleFolder tidak ketemu)" end
        return out
    end

    local getStyle = makeDropdown(c, "Gaya Bangunan", styleNames, function() end, "None")

    makeButton(c, "🎨 SwapBuildingStyle (pakai gaya)", THEME.Purple, function()
        task.spawn(function()
            local s = getStyle()
            if not s then notify("Pilih gaya dulu", THEME.Yellow); return end
            local ok, res, err = invokeRF("PlacementService", "SwapBuildingStyle", s)
            addLog("SwapBuildingStyle('" .. s .. "') -> " .. tostring(res) .. " " .. tostring(err), "BUILD")
            notify(ok and ("Swap ke " .. s) or "Gagal swap", ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "💳 PurchaseBuildingStyle (beli gaya)", THEME.Green, function()
        task.spawn(function()
            local s = getStyle()
            if not s then notify("Pilih gaya dulu", THEME.Yellow); return end
            local ok, res, err = invokeRF("PlacementService", "PurchaseBuildingStyle", s)
            addLog("PurchaseBuildingStyle('" .. s .. "') -> " .. tostring(res) .. " " .. tostring(err), "BUILD")
            notify(ok and ("Beli gaya " .. s .. " dikirim") or "Gagal beli", ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "🏗 SkipConstruction (lewati bangun)", THEME.Orange, function()
        task.spawn(function()
            local ok, res, err = invokeRF("PlacementService", "SkipConstruction")
            addLog("SkipConstruction() -> " .. tostring(res) .. " " .. tostring(err), "BUILD")
            notify(ok and ("SkipConstruction: " .. tostring(err or res)) or "Gagal",
                   ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "🔨 EnterBuild (masuk mode bangun)", THEME.Blue, function()
        local ok = invokeRF("PlacementService", "EnterBuild")
        notify(ok and "EnterBuild dikirim" or "Gagal", ok and THEME.On or THEME.Red)
    end)

    local limitLbl = makeInfo(c, "Batas decor: tekan 'Cek Batas Decor'")

    makeButton(c, "📐 Cek Batas Decor (NextDecorLimitCost)", THEME.Blue, function()
        task.spawn(function()
            -- BuildUIController: andThen(p1, p2, p3, p4, p5)
            --   p2 = sekarang?, p3 = batas, p4 = batas berikutnya, p5 = harga gems
            local ok, a, b2, c3, d, e = invokeRF("PlacementService", "NextDecorLimitCost")
            if ok then
                limitLbl.Text = table.concat({
                    "NextDecorLimitCost balikan mentah:",
                    -- Arti tiap posisi dibaca dari BuildUIController milik
                    -- game (SPSV2TELITI 7587-7597), bukan ditebak:
                    --     if p2 <= p3 then  DecorLimit.Text = p3 .. " (MAX)"
                    --     else              DecorLimit.Text = p3 .. " -> " .. p4
                    --     Gems.TextLabel.Text = tostring(p5)
                    "  1 = " .. tostring(a),
                    "  2 = " .. tostring(b2) .. "   (batas MAKSIMUM; kalau <= no.3 berarti sudah mentok)",
                    "  3 = " .. tostring(c3) .. "   (batas sekarang)",
                    "  4 = " .. tostring(d)  .. "   (batas berikutnya)",
                    "  5 = " .. tostring(e)  .. "   (harga gems)",
                }, "\n")
                addLog("NextDecorLimitCost: " .. tostring(a) .. " " .. tostring(b2) .. " " ..
                       tostring(c3) .. " " .. tostring(d) .. " " .. tostring(e), "BUILD")
            else
                limitLbl.Text = "Gagal: " .. tostring(a)
            end
        end)
    end)

    makeButton(c, "💎 PurchaseDecorLimit (naikkan batas)", THEME.Green, function()
        task.spawn(function()
            local ok, res = invokeRF("PlacementService", "PurchaseDecorLimit")
            notify(ok and "PurchaseDecorLimit dikirim" or "Gagal", ok and THEME.On or THEME.Red)
            addLog("PurchaseDecorLimit -> " .. tostring(res), "BUILD")
        end)
    end)
end

task.wait()   -- jeda satu frame (lihat PEMBANGUNAN BERTAHAP di atas)

-- ============================================================
-- BUILD UI : TAB CRAFT
-- ============================================================
do
    local c = makeCard("💐 AUTO RANGKAI", THEME.Pink, CraftBody)

    makeDropdown(c, "Container", containerNames, function(item)
        config.containerPick = item
        local arrF = assetFolder("Arrangements")
        local arr = arrF and arrF:FindFirstChild(item)
        local mx = arr and arr:GetAttribute("maxFlowers") or "?"
        local lv = arr and arr:GetAttribute("requiredLevel") or "?"
        notify(item .. "  (max " .. tostring(mx) .. " bunga, Lv " .. tostring(lv) .. ")", THEME.Pink)
    end, "None")

    -- SAKELAR YANG SAMA dengan yang di tab Auto - lihat AUTO.pasangVis.
    -- Ditaruh di sini lagi supaya bersebelahan dengan dropdown Container
    -- yang menentukan wadahnya.
    --
    -- "Auto Craft -> LANGSUNG ke Rak" TIDAK dihidupkan lagi: itu cuma
    -- craft + stok yang dijalankan berurutan, dan hasilnya sama persis
    -- dengan menyalakan Auto Craft + "Auto Rangkaian -> Rak" bersamaan.
    AUTO.pasangVis("craft", makeToggle(c, "Auto Craft (instant)", THEME.Pink, function(v)
        if v and not (config.containerPick or config.autoBigContainer or config.autoBestContainer) then
            notify("Pilih Container di dropdown tepat di atas dulu", THEME.Yellow)
        end
        AUTO.set.craft(v)
        notify(v and "Auto Craft ON" or "Auto Craft OFF", v and THEME.On or THEME.Off)
    end))

    makeInfo(c, "'Auto Craft' ADA DI DUA TEMPAT: di sini, dan di tab ⚡ Auto.\nItu SAKELAR YANG SAMA, bukan kembar - nyalakan di sini, yang di\ntab Auto ikut menyala sendiri (dan sebaliknya).\n\nUntuk hasil jadi LANGSUNG masuk etalase, nyalakan juga\n'Auto Rangkaian -> Rak' di tab ⚡ Auto. Dua sakelar itu bersamaan\n= mode gabungan 'Auto Craft ke Rak' yang lama, tanpa perlu\nsakelar ketiga.\n\nCatatan jujur: yang ini TIDAK memakai TURBO walau tulisannya\n'instant'. doCraftOnce memanggil invokeRF langsung dan menunggu\nbalasan server tiap langkah - StartArranging, tiap ReserveFlower,\nlalu FinishArranging - karena urutannya WAJIB benar. Menembak\nbuta di sini malah membuat rangkaian gagal jadi.")

    makeSlider(c, "Craft Delay", config.craftDelay, 0.5, 10, THEME.Pink, function(v) config.craftDelay = v end)

    makeSlider(c, "Jumlah per Craft (batch)", config.craftBatch, 1, 25, THEME.Pink, function(v)
        config.craftBatch = math.floor(v)
    end)
    makeInfo(c, "Batch > 1 memakai FinishBatchArranging(payload, jumlah) -\nsama seperti tombol batch di UI game. Bawaannya sekarang 25\n(mentok atas), dan Craft Delay bawaannya 0,50 dtk (mentok bawah).\n\nAngka ini juga yang dipakai sakelar AUTO RANGKAI -> RAK di bawah,\ndan tetap dipotong ke SISA SLOT TAS - jadi 25 itu batas ATAS.")

    -- SAKELAR, BUKAN TOMBOL. Tombol sekali-tekan berarti kamu harus
    -- menekannya lagi tiap kali bunga menumpuk, dan itu bukan "auto".
    -- Mesinnya di AUTO.set.combo (tab Auto), jadi loopnya cuma SATU
    -- walau sakelarnya nanti dipasang di tempat lain juga.
    AUTO.vis.combo = makeToggle(c, "AUTO RANGKAI -> RAK (siklus penuh)", THEME.Green, function(v)
        AUTO.set.combo(v)
        notify(v and "Auto Rangkai->Rak ON - wadah terbaik, batch penuh, langsung ke rak"
                  or "Auto Rangkai->Rak OFF",
               v and THEME.On or THEME.Off)
    end)

    makeInfo(c, "SAKELAR DI ATAS = SATU MESIN UNTUK SELURUH SIKLUS, dan dia\nBAWAANNYA MATI. Dulu memang dinyalakan sendiri saat execute;\nitu sudah DIBATALKAN - sakelar yang menyala tanpa ditekan bikin\nseluruh panel sulit dipercaya. Sekarang SEMUA sakelar auto mulai\ndari OFF.\n\nTombol COMBO sekali-tekan yang dulu di sini sudah dibuang -\nyang kamu minta memang sakelar auto.\n\nSatu putaran:\n  1. WADAH TERBAIK yang levelnya sudah kebuka. Yang dipakai\n     maxFlowers TERBANYAK, bukan priceAdd tertinggi - alasannya\n     terukur: harga = priceAdd WADAH + priceBase TIAP BUNGA, jadi\n     yang menaikkan uang adalah BANYAKNYA bunga per buket.\n  2. BUNGA DIISI SAMPAI PENUH kapasitas wadah itu, didahulukan\n     yang priceBase-nya tertinggi.\n  3. BATCH SEKALI TEMBAK lewat FinishBatchArranging(payload, N) -\n     persis alur game: resep di-reserve sekali, lalu minta N.\n  4. hasilnya LANGSUNG didorong ke rak. Maksimal 8 putaran per\n     panggilan, lalu loopnya bangun lagi - jadi tidak ada thread\n     yang ditahan selamanya.\n\nDIA MEMATIKAN 'Auto Craft' DAN 'Auto Rangkaian -> Rak' begitu\ndinyalakan, dan itu WAJIB - bukan kerapian. Craft itu SESI di\nserver (StartArranging -> ReserveFlower... -> Finish); dua mesin\nyang membuka sesi di meja yang sama saling mencuri bunga reserve,\ndan hasilnya rangkaian GAGAL JADI. Menyalakan salah satu dari dua\nsakelar itu juga otomatis mematikan yang ini.\n\nSOAL 'KE RAK KOK TIDAK INSTAN' - sudah diperbaiki, dan ini\nsebabnya. Tahap ke-rak dulu DIPAKSA tanpa turbo, karena kapasitas\nrak rangkaian cuma bisa diukur dari PENOLAKAN server dan di turbo\npenolakan itu tidak terbaca. Sekarang: turbo MATI hanya selama\nmasih ada jenis rak yang belum terukur, dan NYALA begitu semuanya\nsudah punya angka PASTI - karena sesudah itu balasan server tidak\ndibutuhkan lagi (hub berhenti tepat di angka itu sendiri).\n~0,09 dtk per buket dibanding ~0,68 dtk. Angka pastinya ikut\ntersimpan ke file, jadi execute berikutnya langsung instan.\n\nSakelar TURBO-mu DIKEMBALIKAN persis seperti semula di akhir -\ntermasuk kalau ada error di tengah jalan.\n\nBATCH DIPOTONG KE SISA SLOT TAS. Lihat kartu KAPASITAS BACKPACK\ndi bawah: kalau tas cuma sisa 5 slot, yang dikirim 5 - bukan 25.\nTanpa itu bunga untuk 20 buket HANGUS, karena server sudah\nmemotong bahannya tapi barangnya tidak bisa masuk.\n\nYANG DILAPORKAN = HASIL NYATA. Jumlah buket dihitung dari isi\ninventory sebelum vs sesudah, bukan dari angka batch. Jadi kalau\nserver cuma memberi 3 dari 25, laporannya 3.\n\nSATU HAL YANG BELUM TERBUKTI, dan saya tidak akan mengarang:\napakah FinishBatchArranging(payload, 25) memotong bunga 1x atau\n25x. Hub melakukan PERSIS yang dilakukan controller game sendiri\n(reserve sekali, lalu minta N), dan karena hasilnya dihitung dari\ninventory, laporannya tidak bisa membesar-besarkan.")

    makeButton(c, "💐 Rangkai 1x Sekarang", THEME.Pink, function()
        task.spawn(function()
            local ok, err = doCraftOnce()
            notify(ok and "Rangkai berhasil OK" or ("Gagal: " .. tostring(err)), ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "💐->🏪 Rangkai 1x + Langsung Stok", THEME.Green, function()
        task.spawn(function()
            local ok, err = doCraftOnce()
            if not ok then
                notify("Gagal rangkai: " .. tostring(err), THEME.Red)
                return
            end
            task.wait(0.35)
            local n, why = doStockArrangementOnce()
            notify(n > 0 and ("Rangkai + masuk " .. n .. " rak OK")
                          or ("Rangkai OK, tapi tidak masuk rak - " .. tostring(why)),
                   n > 0 and THEME.On or THEME.Yellow)
        end)
    end)

    makeButton(c, "X Batalkan Rangkai (stuck fix)", THEME.Red, function()
        invokeRF("ArrangementService", "CancelArranging")
        notify("CancelArranging dikirim", THEME.Yellow)
    end)

    local invLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(CraftBody) do task.wait(0.4) end
            local inv, order = flowerInventory()
            local lines = { "BUNGA DI INVENTORY:" }
            local shown = 0
            for _, nm in ipairs(order) do
                if shown >= 12 then table.insert(lines, "  ... (+" .. (#order - shown) .. " lagi)"); break end
                table.insert(lines, "  " .. nm .. " x" .. inv[nm])
                shown = shown + 1
            end
            if #order == 0 then lines = { "BUNGA DI INVENTORY: (kosong)" } end
            invLbl.Text = table.concat(lines, "\n")
            task.wait(2)
        end
    end)
end

-- ============================================================
-- KAPASITAS BACKPACK
-- ============================================================
do
    local c = makeCard("🎒 KAPASITAS BACKPACK", THEME.Orange, CraftBody)

    makeInfo(c, "BISA DIBESARKAN DARI SCRIPT? TIDAK BISA. Ini sudah saya telusuri\nsampai habis, bukan dikira-kira:\n\n  1. 'Bigger Backpack' itu GAMEPASS ROBUX, id 1917897745\n     (RobuxController: name = \"Bigger Backpack\",\n      description = \"Carry more items at once!\").\n\n  2. Kepemilikan gamepass di game ini muncul sebagai ATRIBUT\n     PEMAIN yang DISETEL SERVER - polanya sama dengan 2XCash,\n     2XGrowSpeed, VIP, Customize. Atribut Player yang ditulis dari\n     client TIDAK direplikasi ke server, jadi menyetelnya sendiri\n     cuma menipu layarmu. Persis kasus Cash palsu yang sudah kita\n     buang dari tab Extra.\n\n  3. BackpackService ADA di daftar service, tapi ISINYA KOSONG:\n     0 RemoteFunction, 0 RemoteEvent. Tidak ada satupun pintu yang\n     bisa dipanggil client. Batasnya murni diputuskan server saat\n     dia mencoba memberimu barang.\n\n  4. Di seluruh dump client tidak ada satupun angka batas backpack\n     (maxBackpack / backpackSize / carryLimit / maxItems = nol\n     hasil). Jadi angkanya memang tidak pernah dikirim ke client.\n\nYang BISA dilakukan: menjaga isinya tidak menumpuk. Ukurannya ada\ndi bawah supaya kelihatan APA yang sebenarnya memenuhi tasmu.")

    local bagLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan (lihat tampil()).
            while ScreenGui.Parent and not tampil(CraftBody) do task.wait(0.4) end

            -- SATU sapuan untuk semuanya. Penanda jenisnya diambil dari
            -- kode game sendiri, bukan tebakan: atribut SeedType
            -- (baris 602), SupplyType (617), IsArrangement (1117), dan
            -- bunga dikenali dari namanya di Assets.Flowers.
            local nTool, nBunga, nRangkai, nBibit, nSupply, nLain = 0, 0, 0, 0, 0, 0
            local isi, jenis = 0, {}
            for _, t in ipairs(allTools()) do
                nTool = nTool + 1
                local cnt = tonumber(t:GetAttribute("Count")) or 1
                isi = isi + cnt
                if isFlowerTool(t) then
                    nBunga = nBunga + 1
                    jenis[t.Name] = true
                elseif t:GetAttribute("IsArrangement") then nRangkai = nRangkai + 1
                elseif t:GetAttribute("SeedType")      then nBibit   = nBibit + 1
                elseif t:GetAttribute("SupplyType")    then nSupply  = nSupply + 1
                else nLain = nLain + 1 end
            end
            local nJenis = 0
            for _ in pairs(jenis) do nJenis = nJenis + 1 end

            -- SISA SLOT - inilah angka yang dipakai COMBO untuk memotong
            -- batch. Batasnya tidak ada di client (alasan lengkapnya di
            -- kotak atas), jadi dia DIUKUR dari craft yang hasilnya kurang
            -- dari yang diminta. Sebelum terukur, jangan mengarang angka:
            -- tulis apa adanya bahwa belum diketahui.
            local sisaSlot = _stockWarn.tas and math.max(_stockWarn.tas - nTool, 0)

            bagLbl.Text = table.concat({
                "ISI TAS SEKARANG:",
                "  Slot tool terpakai : " .. nTool ..
                    (_stockWarn.tas and (" / " .. _stockWarn.tas .. "  (TERUKUR)") or ""),
                "  SISA SLOT KOSONG   : " ..
                    (sisaSlot and tostring(sisaSlot)
                              or "belum terukur - craft pertama yang mengukurnya"),
                "     bunga     : " .. nBunga .. "   (" .. nJenis .. " jenis berbeda)",
                "     rangkaian : " .. nRangkai,
                "     bibit     : " .. nBibit .. "     supply : " .. nSupply,
                "     lain-lain : " .. nLain,
                "  Total barang (Count) : " .. isi,
                "",
                "COMBO CRAFT MEMOTONG BATCH KE ANGKA 'SISA SLOT' DI ATAS.",
                "Jadi minta 25 sementara sisa 5 -> yang dikirim 5, bukan 25.",
                "Tanpa itu bunga untuk 20 buket HANGUS: server sudah memotong",
                "bahannya, tapi barangnya tidak bisa masuk tas.",
                "",
                "Selama batasnya BELUM terukur, batch dikecilkan jadi 5 dulu",
                "(percobaan). Begitu ada craft yang hasilnya kurang dari yang",
                "diminta, jumlah slot saat itu = batasnya, dan sesudah itu",
                "batch penuh dipakai lagi. Angkanya ikut tersimpan ke file.",
                "",
                "BACA ANGKA INI BEGINI: yang memenuhi tas itu JUMLAH SLOT",
                "(baris pertama), bukan Total barang. Bunga sejenis menumpuk",
                "jadi satu tool ber-atribut Count - itu dipakai game sendiri",
                "maupun script ini. Jadi 500 Rose jauh lebih ringan daripada",
                "50 jenis bunga berbeda.",
                "",
                "Kalau slot mepet: kurangi JENIS bibit yang ditanam, dan",
                "biarkan Auto Craft + Auto Rangkaian -> Rak jalan supaya",
                "isinya terus mengalir keluar ke etalase.",
            }, "\n")
            task.wait(3)
        end
    end)

    makeButton(c, "📤 KOSONGKAN TAS SEKARANG (bunga + rangkaian ke rak)", THEME.Green, function()
        task.spawn(function()
            local was = state.turbo
            state.turbo = true
            local a = doStockArrangementOnce()
            local b = doStockFlowerOnce()
            state.turbo = was
            notify("Ke rak: " .. tostring(a) .. " rangkaian, " .. tostring(b) .. " bunga",
                   ((tonumber(a) or 0) + (tonumber(b) or 0)) > 0 and THEME.On or THEME.Yellow)
        end)
    end)

    makeInfo(c, "Tombol di atas mendorong isi tas ke etalase - itu satu-satunya\ncara menurunkan tekanan backpack tanpa membuang barang.\n\nKalau raknya sendiri sudah penuh, lihat kartu 'RAK PENUH' di\nbawah: rangkai jadi buket dulu (rak rangkaian wadah TERPISAH dari\nrak bunga), atau pasang rak baru.")
end

-- ============================================================
-- MEMAHALKAN HARGA JUAL
-- ============================================================
do
    local c = makeCard("💵 MEMAHALKAN HARGA JUAL", THEME.Green, CraftBody)

    makeInfo(c, "YANG TIDAK BISA: mengetik harga sendiri. CustomerService cuma\npunya SATU remote (ToggleShopOpen) - tidak ada SetPrice / SellFor.\n\nRALAT: kartu ini dulu menulis \"atribut priceAdd TIDAK PERNAH\ndibaca script client manapun\". ITU SALAH. MenuConfig membacanya\n(RSV2TELITI 1465950-1465956) dan menyusun tabel Containers dari\nsitu. Yang benar: harga AKHIR dihitung server, tapi rumusnya\nkelihatan di client dan sudah saya salin di bawah.\n\nRUMUS ASLINYA (RSV2TELITI 1466176-1466190):\n\n   harga = priceAdd WADAH  +  priceBase TIAP BUNGA\n\nDua hal penting yang keluar dari rumus itu:\n  1. ACCENT tidak ikut dijumlah sama sekali\n  2. yang menentukan bukan cuma wadahnya, tapi BUNGA APA yang\n     kamu masukkan - dan selisih antar bunga ratusan kali lipat")

    makeInfo(c, "SEMUA WADAH (dibaca dari dump RSTELITI, bukan tebakan):\n\n  wadah            bunga  priceAdd  level\n  Small Bouquet        1        +5      1\n  Glass Vase           2       +10      5\n  Big Bouquet          3       +20     10\n  Simple Pot           5       +30     15\n  Vase                 6       +50     20\n  Tall Vase            7       +70     30\n  Antique Vase         9       +80     40\n  Spring Basket       12      +100     50   <== TERBAIK\n\nSpring Basket menang di DUA-DUANYA: paling banyak bunga DAN\npriceAdd tertinggi. Jadi 'termahal' dan 'kapasitas terbesar'\nsama-sama memilih dia begitu levelmu 50.\n\npriceAdd ACCENT (Assets.Accents):\n  Gold Leaf      +5    Lv15\n  Satin Ribbon   +3    Lv3\n  Dried Lavender +3    Lv5\n  Baby's Breath  +2    Lv1\n  Greenery       +1    Lv1")

    -- ============================================================
    -- DUA SAKELAR INI SALING MEMATIKAN - DAN SEKARANG GAMBARNYA IKUT
    -- ============================================================
    -- Di foto punyamu DUA-DUANYA menyala. Itu bohong, dan ini sebabnya:
    -- menyalakan yang satu men-set config yang lain jadi false, TAPI
    -- tombolnya tidak ikut dibalik - jadi kelihatan dua-duanya aktif
    -- padahal cuma satu yang dipakai. Yang menang KAPASITAS TERBESAR,
    -- karena doCraftOnce memeriksa autoBigContainer DULU (if ... elseif).
    --
    -- Kenapa tidak digabung saja jadi satu sakelar: untuk katalog
    -- sekarang hasilnya memang sama (Spring Basket menang di dua
    -- kriteria), tapi dipisah supaya tetap benar kalau developer nanti
    -- menambah wadah yang mahal tapi kecil, atau besar tapi murah.
    local visMahal, visBesar

    visMahal = makeToggle(c, "Pakai wadah TERMAHAL otomatis (priceAdd)", THEME.Green, function(v)
        config.autoBestContainer = v
        if v then
            config.autoBigContainer = false
            if visBesar then visBesar(false) end
            local nm, add = bestContainer()
            notify(nm and ("Wadah otomatis: " .. nm .. " (+" .. add .. ")")
                       or "Assets.Arrangements tidak ketemu",
                   nm and THEME.On or THEME.Red)
        else
            notify("Kembali pakai Container pilihan manual", THEME.Off)
        end
    end)

    visBesar = makeToggle(c, "Pakai wadah KAPASITAS TERBESAR (Spring Basket)", THEME.Green, function(v)
        config.autoBigContainer = v
        if v then
            config.autoBestContainer = false
            if visMahal then visMahal(false) end
            local nm, mx, add = biggestContainer()
            notify(nm and ("Wadah otomatis: " .. nm .. " (max " .. mx ..
                           " bunga, +" .. add .. ")")
                       or "Assets.Arrangements tidak ketemu",
                   nm and THEME.On or THEME.Red)
        else
            notify("Kembali pakai Container pilihan manual", THEME.Off)
        end
    end)

    -- Gambar awal dipasang SESUDAH keduanya ada, supaya tidak ada yang
    -- memanggil pasangan yang belum lahir.
    visMahal(config.autoBestContainer)
    visBesar(config.autoBigContainer)

    makeToggle(c, "Tempel ACCENT termahal otomatis", THEME.Green, function(v)
        config.autoAccents = v
        notify(v and "Accent otomatis ON" or "Accent otomatis OFF",
               v and THEME.On or THEME.Off)
    end)(config.autoAccents)

    makeSlider(c, "Jumlah accent / rangkaian", config.accentCount, 1, 5, THEME.Green, function(v)
        config.accentCount = math.floor(v)
    end)

    local priceLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(CraftBody) do task.wait(0.4) end
            local myLvl = myLevel()
            local nm, add = bestContainer()
            local cap, ctLvl = accentCap()
            -- DIPOTONG cap, sama seperti doCraftOnce. Dulu baris ini memakai
            -- config.accentCount apa adanya, jadi begitu slidernya di 5
            -- sementara Craft Table masih Lv1 (cap 2), label ini mendaftar
            -- LIMA accent padahal yang benar-benar dikirim cuma DUA - kartu
            -- ini jadi berbohong tentang mesinnya sendiri.
            local acc = bestAccents(math.min(config.accentCount, cap))
            local accF = assetFolder("Accents")
            local accAdd = 0
            for _, a in ipairs(acc) do
                local m = accF and accF:FindFirstChild(a)
                accAdd = accAdd + (tonumber(m and m:GetAttribute("priceAdd")) or 0)
            end
            local mx = select(2, biggestContainer())
            priceLbl.Text = table.concat({
                "Level kamu       : " .. (myLvl or "TIDAK TERBACA (filter level dimatikan)"),
                "Wadah terbaik    : " .. (nm or "?") .. "   (+" .. (add or 0) .. ")",
                "Batas accent     : " .. cap .. "   (dari Craft Table Lv " .. ctLvl ..
                    ", BUKAN dari atribut)",
                "Slider accent    : " .. config.accentCount .. "  ->  YANG DIPAKAI " ..
                    math.min(config.accentCount, cap) ..
                    (config.accentCount > cap
                        and "   (dipotong batas Craft Table, bukan diabaikan)"
                        or "   (slider masih di bawah batas)"),
                "Accent terpakai  : " .. (#acc > 0 and table.concat(acc, ", ") or "(tidak ada)"),
                "priceAdd accent  : +" .. accAdd .. "   <- BELUM TERBUKTI DIPAKAI SERVER",
                "",
                "YANG TERBUKTI menaikkan harga, rumus asli dari game",
                "(RSV2TELITI 1466176-1466190):",
                "   harga = priceAdd WADAH + priceBase TIAP BUNGA",
                "Accent tidak ikut dijumlah di rumus itu. Jadi yang benar-benar",
                "menaikkan uang adalah BANYAKNYA BUNGA per rangkaian.",
                "",
                "Wadah kapasitas terbesar : " .. (select(1, biggestContainer()) or "?") ..
                    "   (" .. tostring(mx or "?") .. " bunga)",
                "",
                "Naikkan lagi dengan: naik Level (membuka wadah lebih besar),",
                "Advertising (menaikkan jumlah + kualitas pembeli), dan",
                "Upgrade Craft Table (stat 'quality' = 1 + (Lv-1)/29, jadi",
                "Lv 30 = 2x lipat).",
            }, "\n")
            task.wait(4)
        end
    end)

    makeButton(c, "🔎 Cek wadah & accent terbaik sekarang", THEME.Blue, function()
        task.spawn(function()
            local nm, add = bestContainer()
            local acc = bestAccents(config.accentCount)
            addLog("Wadah terbaik: " .. tostring(nm) .. " (+" .. tostring(add) .. ")", "CRAFT")
            for _, a in ipairs(acc) do addLog("  accent: " .. a, "CRAFT") end
            notify(nm and (nm .. " +" .. add .. ", " .. #acc .. " accent") or "Gagal baca aset",
                   nm and THEME.On or THEME.Red)
        end)
    end)
end

-- Sisa remote ArrangementService yang MEMANG untuk bunga: ReserveAccent,
-- CollectFloral, ClearFloral. Keluarga *Cooking / *Food sudah dibuang dari
-- sini - alasan lengkapnya ada di catatan di bawah kartu ini.
do
    local c = makeCard("🎀 ACCENT & KONTROL RANGKAI", THEME.Pink, CraftBody)

    local function accentNames()
        local out = childNames(assetFolder("Accents"))
        if #out == 0 then out[1] = "(Assets.Accents kosong)" end
        return out
    end

    local getAccent = makeDropdown(c, "Accent", accentNames, function() end, "None")

    makeButton(c, "🎀 ReserveAccent (tambah hiasan)", THEME.Pink, function()
        task.spawn(function()
            local a = getAccent()
            if not a then notify("Pilih accent dulu", THEME.Yellow); return end
            local ok, res, err = invokeRF("ArrangementService", "ReserveAccent", a)
            addLog("ReserveAccent('" .. a .. "') -> " .. tostring(res) .. " " .. tostring(err), "CRAFT")
            notify(ok and ("Accent: " .. tostring(err or res)) or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeInfo(c, "JUJUR SOAL TOMBOL INI: ReserveAccent TIDAK PERNAH dipanggil\ncontroller manapun - nol call-site di seluruh dump client. Yang\nada cuma namanya di daftar remote. Jadi bentuk argumennya DUGAAN\n(diisi nama accent, mengikuti pola ReserveFlower yang terbukti).\n\nLebih jauh lagi: UI craft milik game sendiri tidak punya pemilih\naccent sama sekali. Tombolnya cuma tiga - wadah, preset, bunga.\nTabel muatan yang dikirim ke server lahir dengan accents = {}\nkosong dan tidak ada satu baris pun yang mengisinya; yang pernah\nberisi accent cuma pesanan pelanggan yang MASUK, bukan yang kita\nkirim.\n\nDan rumus harganya tidak menjumlahkan accent sama sekali:\n   harga = priceAdd WADAH + priceBase TIAP BUNGA\n\nBatas jumlahnya sendiri = fungsi LEVEL Craft Table, bukan atribut:\n2 di Lv1, 3 di Lv5, 4 di Lv10, 5 di Lv20.\n\nSilakan dicoba - kalau server menolak, pesannya muncul di tab\nOutput. Saya tidak akan menjanjikan ini menambah uang.")

    makeButton(c, "🧺 CollectFloral (ambil hasil)", THEME.Green, function()
        task.spawn(function()
            local ok, res, err = invokeRF("ArrangementService", "CollectFloral")
            addLog("CollectFloral -> " .. tostring(res) .. " " .. tostring(err), "CRAFT")
            notify(ok and ("CollectFloral: " .. tostring(err or res)) or "Gagal",
                   ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "🧽 ClearFloral (kosongkan meja)", THEME.Yellow, function()
        task.spawn(function()
            local ok, res, err = invokeRF("ArrangementService", "ClearFloral")
            addLog("ClearFloral -> " .. tostring(res) .. " " .. tostring(err), "CRAFT")
            notify(ok and "ClearFloral dikirim" or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeInfo(c, "Dari tiga tombol di kartu ini, cuma ClearFloral yang benar-benar\ndipakai game (SPSV2TELITI 7199). ReserveAccent dan CollectFloral\nnol call-site - tidak ada controller yang pernah memanggilnya,\njadi keduanya dikirim tanpa argumen / dengan argumen dugaan.\n\nYang TERBUKTI di jalur craft, lengkap dengan urutannya:\n   StartArranging(mejaCraft)\n   ReserveFlower(namaBunga)     <- diulang per bunga\n   FinishArranging(muatan)\n   FinishBatchArranging(muatan, jumlah)\n   CancelArranging()\nMuatannya: { container, preset, flowers, accents }")

    -- JANGAN tambahkan tombol *Cooking / *Food di sini. Itu BUKAN alias
    -- *Arranging: CookingController masih hidup di client (SPSV2TELITI
    -- 3953) sebagai sistem RAMEN, dan FinishCooking menuntut payload
    -- { soup, noodle, toppings } - bukan { container, preset, flowers }.
    -- Menekannya bisa mengacak sesi craft yang sedang jalan.
end

do
    local c = makeCard("🏪 TOKO & RAK", THEME.Blue, CraftBody)

    -- "Auto Stok Rangkaian ke Rak" DIHAPUS: kembar persis dengan
    -- "Auto Rangkaian -> Rak" di tab Auto (loop doStockArrangementOnce
    -- tiap sellDelay, penjaga _stockWarn.arr pun sama).
    makeInfo(c, "Sakelar Auto Stok Rangkaian pindah ke tab ⚡ Auto\n('Auto Rangkaian -> Rak'). Slider Sell Delay di bawah tetap\ndipakai oleh loop itu.")

    -- DIAGNOSA: satu tombol untuk menjawab "raknya kosong kok tidak diisi?"
    -- Aturan PENUH diputuskan SERVER, dan ServerScriptService tidak ada di
    -- dump manapun (yang ada cuma client, ReplicatedStorage, Workspace).
    -- Jadi satu-satunya cara tahu adalah MENGUKUR saat main, bukan menebak.
    makeInfo(c, "KENAPA ANGKA 'Max=8' DIHAPUS DARI SINI.\n\nItu pertanyaan yang benar, dan jawabannya sudah saya cek di kode\ngame sendiri - bukan dikira-kira:\n\n  PLANTER      -> atribut 'Slots'.  TERBACA, dipakai.\n  RAK BUNGA    -> atribut 'Max'.    TERBACA, dipakai.\n     Controller FlowerDisplay milik game menulis persis:\n         local max = Instance:GetAttribute(\"Max\") or 8\n     jadi untuk rak BUNGA angka itu memang batas sebenarnya.\n\n  RAK RANGKAIAN -> TIDAK ADA angkanya di client. Sama sekali.\n     Controller ArrangementDisplay milik game tidak pernah membaca\n     kapasitas apa pun - prompt-nya cuma menulis '(N stocked)',\n     tanpa batas. Atribut rak yang terpasang cuma:\n         Id, Max, Owner, PlaceZone, Price\n     dan 'Max' di situ adalah kapasitas BUNGA yang menempel di model\n     yang sama. Pencarian di seluruh ReplicatedStorage untuk\n     maxArrangements / arrangementCapacity / perTier dll = NOL hasil.\n\nJadi menampilkan 'Max=8' di daftar rak rangkaian itu SALAH KONTEKS -\nsudah dibuang. Yang ditampilkan sekarang angka yang benar-benar\nterukur.")

    makeInfo(c, "CARA ANGKANYA DIDAPAT SEKARANG - dua tingkat kepastian:\n\n  'minimal N'  = isi terbanyak yang PERNAH benar-benar masuk ke rak\n                 jenis itu. Artinya kapasitasnya PALING SEDIKIT N,\n                 bisa lebih - belum ketahuan batas atasnya.\n\n  'PASTI N'    = server pernah MENOLAK saat rak itu berisi N.\n                 Penolakan itu pengukuran paling tepat yang ada:\n                 kalau ditolak di angka N, kapasitasnya persis N.\n\nJadi kalau raknya memang muat 12, angkanya akan naik sendiri jadi\n'PASTI 12' begitu Auto Rangkaian -> Rak mengisi sampai mentok sekali\nsaja. Tidak perlu diketik manual, dan tidak akan salah.\n\nAngka PASTI itu juga yang dipakai mode TURBO untuk berhenti tepat\nwaktu, jadi tidak ada lagi rangkaian yang ditembakkan ke rak penuh.")

    local diagLbl = makeInfo(c, "Diagnosa rak rangkaian: tekan tombol di bawah.")

    makeButton(c, "📊 DIAGNOSA RAK RANGKAIAN", THEME.Orange, function()
        task.spawn(function()
            local displays = rakPlot("ArrangementDisplay")
            local bag = 0
            for _, t in ipairs(allTools()) do
                if t:GetAttribute("IsArrangement") then bag = bag + 1 end
            end
            local lines = {
                "Rangkaian di inventory : " .. bag,
                "Rak bertag Arrangement : " .. #displays,
                "",
            }
            if #displays == 0 then
                lines[#lines + 1] = "TIDAK ADA rak bertag 'ArrangementDisplay'."
                lines[#lines + 1] = "Rak rangkaian belum dipasang, atau tag-nya beda."
            end
            -- Batas bawah: isi terbanyak yang memang sudah masuk, per model.
            local bawah = {}
            for _, d in ipairs(displays) do
                local f = d:FindFirstChild("_Arrangements")
                local isi = f and #f:GetChildren() or 0
                if isi > (bawah[d.Name] or 0) then bawah[d.Name] = isi end
            end

            lines[#lines + 1] = "KAPASITAS RANGKAIAN PER JENIS RAK:"
            local adaJenis = false
            for model, isi in pairs(bawah) do
                adaJenis = true
                local pasti = _stockWarn.penuh[model]
                lines[#lines + 1] = "  " .. model .. "  ->  " ..
                    (pasti and (tostring(pasti) .. "  (PASTI, server menolak di angka ini)")
                           or ("minimal " .. isi .. "  (belum pernah ditolak, jadi bisa lebih)"))
            end
            if not adaJenis then lines[#lines + 1] = "  (belum ada data)" end
            lines[#lines + 1] = ""

            local penuh = 0
            for i, d in ipairs(displays) do
                local folder = d:FindFirstChild("_Arrangements")
                local isi = folder and #folder:GetChildren() or 0
                local lim = _stockWarn.penuh[d.Name]
                if lim and isi >= lim then penuh = penuh + 1 end
                if i <= 12 then
                    lines[#lines + 1] = i .. ". " .. d.Name .. "   isi=" .. isi ..
                        (lim and ("  sisa=" .. math.max(lim - isi, 0)) or "  sisa=?")
                end
                addLog("RAK " .. d.Name .. " isi=" .. isi ..
                       " MaxBunga=" .. tostring(d:GetAttribute("Max")), "DIAG")
            end
            if #displays > 12 then
                lines[#lines + 1] = "   ... (+" .. (#displays - 12) .. " rak lagi, lihat Output)"
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "Rak yang sudah mentok : " ..
                (next(_stockWarn.penuh) and (penuh .. " / " .. #displays)
                                         or "belum bisa dihitung (kapasitas belum terukur)")
            diagLbl.Text = table.concat(lines, "\n")
            notify("Diagnosa " .. #displays .. " rak selesai", THEME.On)
        end)
    end)

    -- ============================================================
    -- LUPAKAN SEMUA CAP "PENUH" - jalan keluar kalau angkanya terlanjur salah
    -- ============================================================
    -- Kapasitas rak diukur dari PENOLAKAN server, dan angka itu IKUT
    -- TERSIMPAN ke file. Bagus selama pengukurannya benar - tapi kalau
    -- satu penolakan pernah salah dibaca (mis. tangan belum memegang
    -- rangkaian saat permintaan tiba), angka yang kekecilan itu menempel
    -- SELAMANYA dan membuat rak yang jelas lowong dilewati terus.
    --
    -- Tombol ini membuang dua ingatan sekaligus: kapasitas per JENIS rak
    -- dan cap penuh per RAK. Tidak ada yang hilang permanen - sapuan
    -- berikutnya mengukurnya lagi dari server.
    makeButton(c, "♻ LUPAKAN CAP 'PENUH' (ukur ulang kapasitas rak)", THEME.Yellow, function()
        local n = 0
        for k in pairs(_stockWarn.penuh) do _stockWarn.penuh[k] = nil; n = n + 1 end
        _stockWarn.cap = {}
        _stockWarn.inst = setmetatable({}, { __mode = "k" })
        _stockWarn.arr = nil
        _stockWarn.rem = nil   -- rem 4 detik ikut dilepas, jadi langsung jalan
        notify(n .. " kapasitas rak dilupakan - akan diukur ulang", THEME.On)
        addLog("Cap PENUH direset: " .. n .. " jenis rak, semua cap per-rak" ..
               " ikut dibuang. Simpan konfigurasi kalau mau reset ini permanen.", "SELL")
    end)

    makeInfo(c, "KAPAN TOMBOL DI ATAS DIPAKAI: kalau rak jelas-jelas lowong tapi\nAuto Rangkaian -> Rak melapor 'penuh' terus.\n\nSebabnya satu: kapasitas diukur dari PENOLAKAN server, jadi kalau\nada satu penolakan yang sebenarnya BUKAN karena penuh (tangan\nbelum memegang rangkaian saat permintaan tiba, RateLimiter), angka\nkekecilan itu ikut tersimpan ke file dan menempel terus.\n\nSekarang itu jauh lebih sulit terjadi - cap PENUH cuma dipasang\nkalau isi raknya BENAR-BENAR terbaca dari _Arrangements, atau\npesan servernya memang menyebut penuh. Penolakan yang tidak bisa\ndibuktikan dicatat apa adanya ('menolak tapi sebabnya tidak\nterbukti penuh') dan raknya TIDAK dikunci.\n\nTombol ini untuk membersihkan angka lama yang terlanjur salah\nsebelum perbaikan itu ada. Sesudah ditekan, tekan juga 'Simpan\nKonfigurasi' di tab Settings kalau mau resetnya permanen -\nkalau tidak, angka lama dari file akan kembali saat dimuat.")

    makeSlider(c, "Sell Delay", config.sellDelay, 0.1, 3, THEME.Blue, function(v) config.sellDelay = v end)

    makeToggle(c, "Buka Toko (terima customer)", THEME.Blue, function(v)
        state.shopOpen = v
        invokeRF("CustomerService", "ToggleShopOpen")
        notify(v and "Toko DIBUKA" or "Toko DITUTUP", v and THEME.On or THEME.Off)
    end, "shopOpen")

    -- Tombol unstock DIHAPUS dari sini: isinya sama persis dengan
    -- "KOSONGKAN SEMUA RAK" di kartu RAK PENUH (loop yang sama, remote
    -- yang sama). Yang di sana lebih aman karena pakai konfirmasi dulu.
    makeInfo(c, "Tombol 'Ambil Bunga dari Rak' ada di kartu RAK PENUH di bawah\n('KOSONGKAN SEMUA RAK') - dulu ada dua tombol yang isinya sama,\nyang kembar sudah dibuang.")

    local rakLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(CraftBody) do task.wait(0.4) end
            local fd = rakPlot("FlowerDisplay")
            local ad = rakPlot("ArrangementDisplay")
            local filled, cap = 0, 0
            for _, d in ipairs(fd) do
                filled = filled + displayStock(d)
                cap = cap + (d:GetAttribute("Max") or 8)
            end

            -- ============================================================
            -- HITUNGAN RAK RANGKAIAN, HIDUP - tanpa tekan tombol apa pun
            -- ============================================================
            -- Ini jawaban "berapa rak yang kita punya, isi tiap rak berapa,
            -- max-nya berapa". Dikelompokkan PER JENIS RAK, karena
            -- kapasitasnya memang per jenis - dan angka max cuma ditulis
            -- kalau memang sudah TERUKUR dari penolakan server. Kalau
            -- belum, ditulis "?" apa adanya, bukan angka karangan.
            local jenis, urut = {}, {}
            local isiAll, capAll, penuhAll = 0, 0, 0
            for _, d in ipairs(ad) do
                local f = d:FindFirstChild("_Arrangements")
                local isi = f and #f:GetChildren() or 0
                local mx  = _stockWarn.penuh[d.Name]
                if not jenis[d.Name] then
                    jenis[d.Name] = { n = 0, isi = 0, mx = mx, penuh = 0 }
                    urut[#urut + 1] = d.Name
                end
                local e = jenis[d.Name]
                e.n, e.isi = e.n + 1, e.isi + isi
                isiAll = isiAll + isi
                if mx then
                    capAll = capAll + mx
                    if isi >= mx then e.penuh = e.penuh + 1; penuhAll = penuhAll + 1 end
                elseif _stockWarn.inst[d] then
                    -- Kapasitas jenisnya belum terukur, TAPI rak ini
                    -- sendiri sudah pernah menolak. Tetap dihitung penuh.
                    e.penuh = e.penuh + 1
                    penuhAll = penuhAll + 1
                end
            end
            table.sort(urut)

            local plot = getMyPlot()
            local baris = {
                string.format("Rak bunga     : %d  (isi %d / %d)", #fd, filled, cap),
                string.format("Rak rangkaian : %d  (isi %d / %s, PENUH %d)",
                    #ad, isiAll, (capAll > 0 and tostring(capAll) or "?"), penuhAll),
                "Toko          : " ..
                    ((plot and plot:GetAttribute("ShopOpen")) and "BUKA" or "TUTUP"),
            }
            if #urut > 0 then
                baris[#baris + 1] = ""
                baris[#baris + 1] = "PER JENIS RAK RANGKAIAN (isi / max per rak):"
                for i, nm in ipairs(urut) do
                    if i > 8 then
                        baris[#baris + 1] = "  ... (+" .. (#urut - 8) .. " jenis lagi)"
                        break
                    end
                    local e = jenis[nm]
                    baris[#baris + 1] = string.format("  %-24s %dx  isi %d  max %s  penuh %d",
                        nm, e.n, e.isi,
                        e.mx and tostring(e.mx) or "? (belum terukur)", e.penuh)
                end
                baris[#baris + 1] = ""
                baris[#baris + 1] = "Rak yang PENUH dilewati tanpa ditembak sama sekali."
                baris[#baris + 1] = "Begitu ada yang terjual, isinya turun dan rak itu"
                baris[#baris + 1] = "langsung diisi lagi - tidak perlu tekan apa pun."
            end
            rakLbl.Text = table.concat(baris, "\n")
            task.wait(2)
        end
    end)
end

-- ============================================================
-- RAK PENUH : apa yang bisa dilakukan
-- ============================================================
do
    local c = makeCard("📦 RAK PENUH (display full)", THEME.Orange, CraftBody)

    makeInfo(c, "MEMAKSA MASUK RAK PENUH: TIDAK BISA.\nKapasitas tiap rak = atribut 'Max' yang dibaca SERVER. Kalau\nsudah penuh, StockFlower ditolak dan bunganya dilempar balik\nke backpack ('No display space'). Tidak ada remote untuk\nmenaikkan Max sebuah rak.\n\nYANG SUDAH OTOMATIS DILAKUKAN script ini:\n  1. rak penuh DILEWATI, tidak dicoba sama sekali\n  2. rak paling LOWONG didahulukan\n  3. tiap rak diisi sampai penuh sekali jalan\n\nEMPAT jalan keluar saat semuanya penuh - urut dari terbaik:")

    makeInfo(c, "  A. RANGKAI jadi buket.\n     Rak rangkaian (ArrangementDisplay) adalah WADAH TERPISAH\n     dari rak bunga, jadi ini menambah daya tampung TANPA\n     beli rak baru - sekaligus menaikkan harga jual\n     (lihat kartu MEMAHALKAN HARGA JUAL).\n\n  B. PASANG rak baru berkapasitas besar (tombol di bawah).\n\n  C. Buka toko + Advertising supaya stok cepat terjual.\n\n  D. Unstock bunga murah, sisakan tempat untuk yang mahal.")

    local rakFullLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(CraftBody) do task.wait(0.4) end
            local fd = rakPlot("FlowerDisplay")
            local filled, cap, fullCount = 0, 0, 0
            for _, d in ipairs(fd) do
                local mx = d:GetAttribute("Max") or 8
                local st = displayStock(d)
                filled, cap = filled + st, cap + mx
                if st >= mx then fullCount = fullCount + 1 end
            end
            local nm, mx, pr = bestAffordableDisplay()
            local lines = {
                string.format("Rak bunga : %d   (penuh %d)", #fd, fullCount),
                string.format("Terisi    : %d / %d slot", filled, cap),
                "Rak rangkaian : " .. #rakPlot("ArrangementDisplay"),
                "",
                "Rak terbaik yang MAMPU dibeli sekarang:",
                nm and ("  " .. nm .. "   max " .. mx .. "   $" .. fmtNum(pr))
                    or "  (cash belum cukup untuk rak apapun)",
                "",
                "PALING HEMAT per slot (dari Assets.Objects.Displays):",
            }
            for _, row in ipairs(displayValueTable(6)) do lines[#lines + 1] = row end
            rakFullLbl.Text = table.concat(lines, "\n")
            task.wait(4)
        end
    end)

    makeButton(c, "➕ PASANG RAK TERBAIK YANG MAMPU DIBELI", THEME.Green, function()
        task.spawn(function()
            local nm, mx, pr = bestAffordableDisplay()
            if not nm then notify("Cash belum cukup untuk rak apapun", THEME.Yellow); return end
            local ok, err = placeItem(nm, config.displayRotation)
            if ok then
                notify("Pasang " .. nm .. " (max " .. mx .. ", $" .. fmtNum(pr) .. ")", THEME.On)
            else
                notify("Gagal pasang: " .. tostring(err), THEME.Red)
            end
        end)
    end)

    makeButton(c, "📥 KOSONGKAN SEMUA RAK (unstock)", THEME.Yellow, function()
        confirmDialog("Tarik SEMUA bunga dari rak kembali ke backpack?", function()
            task.spawn(function()
                local n = 0
                for _, disp in ipairs(rakPlot("FlowerDisplay")) do
                    if displayStock(disp) > 0 then
                        invokeRF("FlowerDisplayService", "UnstockFlowerToPlayer", disp)
                        n = n + 1
                        task.wait(turboDelay(config.sellDelay))
                    end
                end
                notify("Unstock dari " .. n .. " rak", n > 0 and THEME.On or THEME.Yellow)
            end)
        end)
    end)

    makeInfo(c, "Catatan: UnstockFlowerToPlayer(rak) menarik dari SATU rak,\ntidak bisa memilih bunga tertentu - jadi pakai ini saat mau\nmengosongkan rak berisi bunga murah, lalu isi ulang dengan\nfilter 'Flowers to Stock' yang cuma mencentang bunga mahal.")
end

task.wait()   -- jeda satu frame (lihat PEMBANGUNAN BERTAHAP di atas)

-- ============================================================
-- BUILD UI : TAB EXTRA
-- ============================================================
do
    local c = makeCard("🎟 KODE & HADIAH", THEME.Yellow, ExtraBody)

    -- Kotak kode SATU-BARIS + tombolnya DIHAPUS: kartu "BOOST & MATA UANG"
    -- di bawah punya kotak MULTI-BARIS yang memanggil RedeemCode yang sama
    -- dan juga menerima satu kode saja (pemisahnya koma / baris baru).
    makeInfo(c, "Redeem kode ada di kartu 'BOOST & MATA UANG' di bawah - satu\nkotak untuk satu kode maupun banyak kode sekaligus (pisahkan\npakai koma atau baris baru). Kotak kembar di sini sudah dibuang.")

    makeButton(c, "📅 Klaim Daily Reward", THEME.Green, function()
        local ok = invokeRF("MoneyService", "ClaimDailyReward")
        notify(ok and "Daily reward diklaim OK" or "Gagal klaim", ok and THEME.On or THEME.Red)
    end)
    makeButton(c, "👥 Klaim Group Reward", THEME.Green, function()
        local ok = invokeRF("MoneyService", "GroupReward")
        notify(ok and "Group reward diklaim OK" or "Gagal klaim", ok and THEME.On or THEME.Red)
    end)

    makeToggle(c, "Auto Klaim Daily (5 menit)", THEME.Green, function(v)
        state.autoDaily = v
        if v then
            startLoop("daily", function()
                invokeRF("MoneyService", "ClaimDailyReward")
                invokeRF("MoneyService", "GroupReward")
            end, function() return 300 end)
            notify("Auto Daily ON", THEME.On)
        else
            stopLoop("daily"); notify("Auto Daily OFF", THEME.Off)
        end
    end, "autoDaily")
end

-- ============================================================
-- BOOST & MATA UANG - apa yang mungkin dan apa yang tidak
-- ============================================================
do
    local c = makeCard("💰 BOOST & MATA UANG", THEME.Green, ExtraBody)

    makeInfo(c, "YANG TIDAK BISA (sudah saya cek satu per satu di 146 remote):\n\n  Cash / Gems langsung  -> TIDAK ADA remote AddCash/SetCash.\n     Nilainya ada di Replica 'DataToken_<UserId>' yang otoritasnya\n     100% di server. Client cuma menerima.\n\n  2x Cash / 2x Grow Speed -> atribut yang di-SET SERVER\n     (LocalPlayer 2XGrowSpeed / PlaytimeBoost, dan Data.Boosts).\n     MoneyService.RE.UpdatePlaytimeBoost itu server->client saja.\n\nJalur GRATIS yang benar-benar ada: kode, daily reward,\ngroup reward, quest reward, playtime boost, premium, teman.")

    local boostLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(ExtraBody) do task.wait(0.4) end
            local lines = { "STATUS BOOST (dibaca dari server):" }
            lines[#lines + 1] = "  2XGrowSpeed   : " ..
                tostring(LocalPlayer:GetAttribute("2XGrowSpeed") or false)
            lines[#lines + 1] = "  PlaytimeBoost : " ..
                tostring(LocalPlayer:GetAttribute("PlaytimeBoost") or 0)
            lines[#lines + 1] = "  VIP           : " ..
                tostring(LocalPlayer:GetAttribute("VIP") or false)
            lines[#lines + 1] = "  Premium       : " ..
                tostring(LocalPlayer.MembershipType == Enum.MembershipType.Premium) .. "  (+5% cash)"
            local fc = LocalPlayer:FindFirstChild("FriendsCount")
            lines[#lines + 1] = "  Teman di server: " .. tostring(fc and fc.Value or 0) ..
                "  (+5% cash per teman)"
            local b = pdata("Boosts", nil)
            if type(b) == "table" then
                lines[#lines + 1] = "  Data.Boosts:"
                local n = 0
                for k, v in pairs(b) do
                    n = n + 1
                    if n <= 8 then lines[#lines + 1] = "     " .. tostring(k) .. " = " .. tostring(v) end
                end
                if n == 0 then lines[#lines + 1] = "     (kosong)" end
            end
            boostLbl.Text = table.concat(lines, "\n")
            task.wait(3)
        end
    end)

    -- Redeem banyak kode sekaligus: ini SATU-SATUNYA jalur gratis
    -- untuk dapat cash/gems/boost lewat remote.
    local codesBox = Instance.new("TextBox", c)
    codesBox.Size = UDim2.new(1, 0, 0, 60)
    codesBox.BackgroundColor3 = THEME.Slot
    codesBox.PlaceholderText = "tempel banyak kode, pisahkan koma atau baris baru"
    codesBox.Text = ""
    codesBox.TextColor3 = THEME.Text
    codesBox.Font = THEME.FontReg
    codesBox.TextSize = 12
    codesBox.TextWrapped = true
    codesBox.MultiLine = true
    codesBox.ClearTextOnFocus = false
    codesBox.TextXAlignment = Enum.TextXAlignment.Left
    codesBox.TextYAlignment = Enum.TextYAlignment.Top
    codesBox.LayoutOrder = nextOrder()
    corner(codesBox, 8)
    stroke(codesBox, THEME.Stroke, 1)

    makeButton(c, "🎟 REDEEM SEMUA KODE SEKALIGUS", THEME.Green, function()
        task.spawn(function()
            local raw = codesBox.Text
            if raw == "" then notify("Tempel kodenya dulu", THEME.Yellow); return end
            local n, okCount = 0, 0
            for code in string.gmatch(raw, "[^,\n\r]+") do
                code = string.match(code, "^%s*(.-)%s*$")
                if code ~= "" then
                    n = n + 1
                    local ok, res, msg = invokeRF("MoneyService", "RedeemCode", code)
                    if ok and res ~= false then okCount = okCount + 1 end
                    addLog("RedeemCode('" .. code .. "') -> " .. tostring(res) ..
                           " " .. tostring(msg), "EXTRA")
                    task.wait(0.4)
                end
            end
            notify("Coba " .. n .. " kode, " .. okCount .. " diterima (lihat Output)",
                   okCount > 0 and THEME.On or THEME.Yellow)
        end)
    end)

    makeInfo(c, "Tiap hasil kode dicetak ke tab Output supaya kelihatan mana\nyang valid dan apa hadiahnya.")

    -- TOMBOL "Ubah TAMPILAN Cash/Gems" DIHAPUS - atas permintaanmu, dan
    -- alasannya benar: kalau hasilnya palsu, adanya tombol itu cuma
    -- bikin bingung. Yang dia lakukan cuma menulis rep.Data.Cash di
    -- tabel LOKAL; ReplicaController.SetValue di sisi client tidak punya
    -- FireServer sama sekali (ReplicaController baris 689-694), jadi
    -- server tidak pernah tahu dan angkanya ketimpa lagi begitu update
    -- berikutnya datang. Tidak bisa dibelanjakan, tidak menaikkan level,
    -- tidak ada gunanya untuk apa pun.
    --
    -- Kalau suatu saat ada yang menyuruh "pakai fitur ubah cash", ini
    -- catatannya: fitur seperti itu di game ber-Replica SELALU palsu.
end

do
    local c = makeCard("📜 QUEST", THEME.Purple, ExtraBody)

    makeInfo(c, "RALAT BESAR - VERSI LAMA TIDAK PERNAH MENGKLAIM APA PUN.\n\nDulu tombolnya menembak ClaimReward(1), ClaimReward(2), ...\nsampai 30, dengan alasan 'id quest tidak tersimpan di client'.\nAlasan itu SALAH, dan akibatnya Auto Quest cuma mengirim 30\npanggilan sampah tiap 20 detik - tidak ada satu pun yang jadi.\n\nYang benar, dari QuestController milik game:\n\n  * daftarnya dikirim server lewat\n       QuestService.RE.UpdateQuestUI(tabelQuest, ...)\n  * tabel itu dikunci NAMA QUEST, bukan angka:\n       for k, v in pairs(p1) do  v3.QuestName.Text = k\n  * dan yang dikirim balik ke server juga teks itu:\n       v2:ClaimReward(k)\n\nSekarang hub ikut mendengarkan event itu dan mengklaim PAKAI\nNAMA - persis seperti tombol CLAIM di panel game.")

    local questLbl = makeInfo(c, "-")

    local function gambarQuest()
        local list = QUEST.daftar()
        if #list == 0 then
            questLbl.Text = "DAFTAR QUEST: belum dikirim server.\n\n" ..
                "Buka panel Quest di GAME sekali saja - sesudah itu hub\n" ..
                "terus menerima pembaruannya sendiri."
            return
        end
        local baris = { "DAFTAR QUEST (" .. #list .. "):" }
        local siap = 0
        for _, q in ipairs(list) do
            local tanda
            if q.sudah then tanda = "SUDAH DIKLAIM"
            elseif q.klaim then tanda = "SIAP DIKLAIM"; siap = siap + 1
            else tanda = "jalan " .. q.jadi .. "/" .. q.total .. " tugas" end
            baris[#baris + 1] = string.format("  %-28s %s", q.nama, tanda)
        end
        baris[#baris + 1] = ""
        baris[#baris + 1] = "Siap diklaim sekarang: " .. siap
        questLbl.Text = table.concat(baris, "\n")
    end

    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan (lihat tampil()).
            while ScreenGui.Parent and not tampil(ExtraBody) do task.wait(0.4) end
            gambarQuest()
            task.wait(3)
        end
    end)

    makeToggle(c, "Auto Claim Quest (pakai NAMA, bukan angka)", THEME.Purple, function(v)
        state.autoQuest = v
        if v then
            if not QUEST.data then
                notify("Buka panel Quest di game sekali dulu supaya daftarnya terkirim", THEME.Yellow)
            end
            startLoop("quest", function()
                -- Cuma quest yang SEMUA tugasnya selesai dan belum
                -- diklaim yang ditembak. Gerbangnya sama persis dengan
                -- tombol CLAIM milik game, jadi tidak ada panggilan yang
                -- pasti ditolak.
                local n, why = QUEST.klaimSemua()
                if n > 0 then
                    notify("Quest diklaim: " .. n, THEME.On)
                elseif why and why ~= "belum ada quest yang semua tugasnya selesai" then
                    addLog("Auto Quest: " .. why, "QUEST")
                end
            end, function() return 20 end)
            notify("Auto Quest ON 📜", THEME.On)
        else
            stopLoop("quest"); notify("Auto Quest OFF", THEME.Off)
        end
    end, "autoQuest")

    makeButton(c, "✅ Claim Semua Quest yang SIAP", THEME.Purple, function()
        task.spawn(function()
            local n, why = QUEST.klaimSemua()
            gambarQuest()
            notify(n > 0 and ("Quest diklaim: " .. n) or ("Tidak ada - " .. tostring(why)),
                   n > 0 and THEME.On or THEME.Yellow)
        end)
    end)

    makeButton(c, "🔄 Refresh Quest", THEME.Blue, function()
        local ok, res, msg = invokeRF("QuestService", "RefreshQuest")
        addLog("RefreshQuest() -> " .. tostring(res) .. " " .. tostring(msg), "QUEST")
        notify(ok and "RefreshQuest dikirim OK" or "Gagal", ok and THEME.On or THEME.Red)
    end)

    makeInfo(c, "RefreshQuest TIDAK PERNAH dipanggil controller manapun - nol\ncall-site di seluruh dump client. Jadi di sini dikirim tanpa\nargumen, mengikuti namanya. Kalau server menuntut argumen,\npenolakannya muncul di tab Output dan itu jawabannya.\n\nYang SUDAH terbukti dan dipakai game: ClaimReward(nama) dan\nTrackQuest(nama), dua-duanya memakai NAMA quest.")
end

do
    local c = makeCard("👷 STAFF & UPGRADE (manual)", THEME.Cyan, ExtraBody)

    -- Tombol "Lihat Pelamar" DIHAPUS dari sini: tab Shop sudah punya
    -- "Lihat Pelamar + Bintang" yang memanggil GetApplicants yang SAMA
    -- tapi menampilkan lebih lengkap (bintang + perkiraan biaya hire).
    -- Yang di sini cuma menghitung jumlah orang, jadi murni bagian kecil
    -- dari yang itu.
    makeInfo(c, "Daftar pelamar ada di tab 🛒 Shop -> 'Lihat Pelamar + Bintang'\n(lengkap dengan bintang & perkiraan biaya). Yang kembar di sini\nsudah dibuang.")

    -- ---- REST / WORK (status asli dari server, label game ikut disegarkan) ----
    local restLbl = makeInfo(c, "Status Rest/Work: tekan 'Cek Status' untuk memuat...")

    local function refreshRestLbl()
        local roles = syncRestUI()
        if roles then
            restLbl.Text = table.concat({
                "STATUS STAFF (dibaca dari server):",
                "  Gardener : " .. (roles.Gardener == true and "ISTIRAHAT 😴" or "BEKERJA ✅"),
                "  Cashier  : " .. (roles.Cashier  == true and "ISTIRAHAT 😴" or "BEKERJA ✅"),
                "",
                "Tombol di UI game menampilkan AKSI berikutnya:",
                "  tulisan WORK (hijau) = sekarang lagi istirahat",
                "  tulisan REST (biru)  = sekarang lagi bekerja",
            }, "\n")
        else
            restLbl.Text = "Gagal baca GetRestingRoles() — cek tab Output."
        end
    end

    -- Tombol ini SEKALIGUS menyamakan label UI game. refreshRestLbl
    -- memanggil syncRestUI(), dan syncRestUI itulah yang mengecat ulang
    -- tombol REST/WORK bawaan game. Jadi satu tekan = baca status server
    -- + samakan tampilan game + perbarui kotak di bawah.
    makeButton(c, "🔄 Cek Status + Samakan Label UI Game", THEME.Blue, function()
        task.spawn(refreshRestLbl)
    end)

    makeButton(c, "😴 Toggle Gardener (Rest <-> Work)", THEME.Yellow, function()
        task.spawn(function()
            local ok, res = toggleRest("Gardener")
            if ok then
                notify("Gardener sekarang " .. (res and "ISTIRAHAT" or "BEKERJA"), THEME.On)
            else
                notify("Gagal toggle Gardener: " .. tostring(res), THEME.Red)
            end
            refreshRestLbl()
        end)
    end)

    makeButton(c, "😴 Toggle Cashier (Rest <-> Work)", THEME.Yellow, function()
        task.spawn(function()
            local ok, res = toggleRest("Cashier")
            if ok then
                notify("Cashier sekarang " .. (res and "ISTIRAHAT" or "BEKERJA"), THEME.On)
            else
                notify("Gagal toggle Cashier: " .. tostring(res), THEME.Red)
            end
            refreshRestLbl()
        end)
    end)

    -- Tombol "🔁 Samakan Label UI Game" DIHAPUS - kembar PERSIS dengan
    -- "Cek Status" di atas. Isinya dulu: syncRestUI(), notify, lalu
    -- refreshRestLbl() - padahal refreshRestLbl SUDAH memanggil
    -- syncRestUI() di baris pertamanya. Jadi dia menjalankan hal yang
    -- sama DUA KALI, dan satu-satunya bedanya cuma toast notifikasi.
    --
    -- KENAPA fungsi menyamakan label itu ada sama sekali: StaffController
    -- milik game HANYA memperbarui tulisan REST/WORK di dalam callback
    -- tombolnya sendiri (baris 535-548). Jadi kalau ToggleRestRole
    -- dipanggil dari script, status di SERVER berubah tapi tulisan di
    -- layar tidak ikut - kelihatan seperti "gagal" padahal berhasil.
    -- syncRestUI() yang membetulkannya, dan sekarang dia ikut jalan di
    -- tombol Cek Status maupun tiap kali Toggle ditekan.

    local upLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(ExtraBody) do task.wait(0.4) end
            local plot = getMyPlot()
            local ok, lvl = invokeRF("EquipmentService", "GetEquipmentLevel", "CraftTable")

            -- BATAS CRAFT TABLE = 30, dan itu angka yang dipakai UI game
            -- sendiri (maxLevel, SPSV2TELITI 5741). EquipmentConfig juga
            -- punya BuildingLevelCaps.CraftTable = {5,10,20,30,30,30}
            -- (RSV2TELITI 1466230-1466242), TAPI GetLevelCap nol call-site
            -- di client - jadi angka apa yang jadi `tier` TIDAK terbukti.
            -- Jangan tampilkan tabel itu sebagai fakta.
            local bl = tonumber(plot and plot:GetAttribute("BuildingLevel")) or 1

            upLbl.Text = table.concat({
                "Craft Table Lv : " .. (ok and tostring(lvl) or "?") ..
                    " / 30   (maxLevel, angka yang dipakai UI game)",
                "Biaya naik 1x  : $" .. ((ok and tonumber(lvl))
                    and tostring(math.floor(50 * (tonumber(lvl)) ^ 1.4)) or "?") ..
                    "   (rumus asli: floor(50 x Lv^1.4))",
                "Batas accent   : " .. (accentCap()) .. "   (2/3/4/5 di Lv 1/5/10/20)",
                "Building Lv    : " .. bl,
                "Farm Lv        : " .. tostring(plot and plot:GetAttribute("FarmLevel") or "?"),
                "Customer Limit : " .. tostring(plot and plot:GetAttribute("CustomerLimit") or "?"),
                "Advertising    : " .. tostring(plot and plot:GetAttribute("AdvertisingBonus") or "?"),
                "",
                "KALAU UPGRADE DITOLAK PADAHAL UANG CUKUP: di EquipmentConfig",
                "ada tabel BuildingLevelCaps.CraftTable = {5,10,20,30,30,30}",
                "yang membatasi bertingkat. Tabel itu NYATA, tapi fungsi",
                "pemakainya tidak pernah dipanggil client, jadi saya TIDAK",
                "bisa membuktikan angka mana yang jadi tingkatnya. Kalau",
                "kamu mentok, coba naikkan Building lewat Expansion (zone",
                "Shop) - itu dugaan yang paling masuk akal, bukan janji.",
            }, "\n")
            task.wait(6)
        end
    end)

    makeButton(c, "🔧 Upgrade Craft Table (1x)", THEME.Orange, function()
        local ok, res, msg = invokeRF("EquipmentService", "UpgradeEquipment", "CraftTable")
        addLog("UpgradeEquipment(CraftTable) -> " .. tostring(res) .. " " .. tostring(msg), "EXTRA")
        notify(ok and "Upgrade dikirim OK" or "Gagal upgrade", ok and THEME.On or THEME.Red)
    end)
end

-- Sisa remote StaffService: GetMyStaff, HireStaff, FireStaff,
-- GetStaffLimits, GetStaffConfig, GetSkinColors
do
    local c = makeCard("👥 STAFF LENGKAP", THEME.Cyan, ExtraBody)

    local myStaffLbl = makeInfo(c, "tekan 'Staff Saya' untuk memuat...")
    local myStaffList = {}   -- {role=..., id=..., label=...}

    makeButton(c, "👥 Staff Saya (GetMyStaff)", THEME.Blue, function()
        task.spawn(function()
            local ok, mine = invokeRF("StaffService", "GetMyStaff")
            if not ok or type(mine) ~= "table" then
                myStaffLbl.Text = "GetMyStaff gagal - cek Output."
                addLog("GetMyStaff gagal: " .. tostring(mine), "STAFF")
                return
            end
            myStaffList = {}
            local lines = { "STAFF SAYA:" }
            for role, list in pairs(mine) do
                if type(list) == "table" then
                    lines[#lines + 1] = "  " .. tostring(role) .. ":"
                    -- ID STAFF ADA DI FIELD .id, BUKAN DI KUNCI TABELNYA.
                    -- GetMyStaff mengembalikan ARRAY - game sendiri memakai
                    -- ipairs(v4) dan #v4 (SPSV2TELITI 10198 & 10241) - jadi
                    -- kunci pairs itu 1,2,3,4, sementara FireStaff menuntut
                    -- StaffId asli seperti 1786970287 (terbaca di atribut NPC
                    -- Gardener di plot). Versi lama mengirim kunci itu, jadi
                    -- tombol pecatnya tidak pernah kena satu pun.
                    --     for i, v10 in ipairs(v4) do local id = v10.id
                    --     ... v1:FireStaff(k, id)          -- SPSV2TELITI 10231
                    for i, s in ipairs(list) do
                        local lvl = tonumber(type(s) == "table" and s.level) or 0
                        local nm  = (type(s) == "table" and s.name) or "?"
                        local sid = (type(s) == "table" and s.id) or i
                        lines[#lines + 1] = "    " .. string.rep("⭐", math.clamp(lvl, 0, 5)) ..
                                            "  " .. tostring(nm) .. "   id=" .. tostring(sid)
                        myStaffList[#myStaffList + 1] = {
                            role = role, id = sid,
                            label = #myStaffList + 1 .. ". " .. tostring(role) ..
                                    " " .. tostring(nm) .. " (" .. lvl .. "*)",
                        }
                        addLog("MyStaff " .. tostring(role) .. " id=" .. tostring(sid) ..
                               " lvl=" .. lvl .. " " .. tostring(nm), "STAFF")
                    end
                end
            end
            if #myStaffList == 0 then lines[#lines + 1] = "  (belum punya staff)" end
            myStaffLbl.Text = table.concat(lines, "\n")
        end)
    end)

    local getMyStaffSel = makeDropdown(c, "Staff", function()
        local out = {}
        for _, s in ipairs(myStaffList) do out[#out + 1] = s.label end
        if #out == 0 then out[1] = "(tekan 'Staff Saya' dulu)" end
        return out
    end, function() end, "None")

    makeButton(c, "🔥 FireStaff (pecat terpilih)", THEME.Red, function()
        local lbl = getMyStaffSel()
        local idx = lbl and tonumber(string.match(lbl, "^(%d+)%."))
        local s = idx and myStaffList[idx]
        if not s then notify("Pilih staff dulu (tekan 'Staff Saya')", THEME.Yellow); return end
        confirmDialog("Pecat " .. tostring(s.role) .. " id=" .. tostring(s.id) .. " ?", function()
            task.spawn(function()
                -- StaffController baris 234: v1:FireStaff(role, id)
                local ok, res, err = invokeRF("StaffService", "FireStaff", s.role, s.id)
                addLog("FireStaff(" .. tostring(s.role) .. ", " .. tostring(s.id) .. ") -> " ..
                       tostring(res) .. " " .. tostring(err), "STAFF")
                notify(ok and "FireStaff dikirim" or "Gagal pecat", ok and THEME.On or THEME.Red)
            end)
        end)
    end)

    makeButton(c, "📋 GetStaffLimits + GetStaffConfig", THEME.Purple, function()
        task.spawn(function()
            local ok1, lim = invokeRF("StaffService", "GetStaffLimits")
            local ok2, cfg = invokeRF("StaffService", "GetStaffConfig")
            local lines = {}
            if ok1 and type(lim) == "table" then
                lines[#lines + 1] = "LIMITS:"
                for k, v in pairs(lim) do
                    lines[#lines + 1] = "  " .. tostring(k) .. " = " ..
                        (type(v) == "table" and "<table>" or tostring(v))
                    addLog("StaffLimit " .. tostring(k) .. " = " .. tostring(v), "STAFF")
                end
            else
                lines[#lines + 1] = "LIMITS: gagal"
            end
            if ok2 and type(cfg) == "table" then
                lines[#lines + 1] = "CONFIG:"
                for k, v in pairs(cfg) do
                    lines[#lines + 1] = "  " .. tostring(k) .. " = " ..
                        (type(v) == "table" and "<table>" or tostring(v))
                    addLog("StaffConfig " .. tostring(k), "STAFF")
                end
            else
                lines[#lines + 1] = "CONFIG: gagal"
            end
            myStaffLbl.Text = table.concat(lines, "\n")
        end)
    end)

    makeButton(c, "🎨 GetSkinColors", THEME.Blue, function()
        task.spawn(function()
            local ok, cols = invokeRF("StaffService", "GetSkinColors")
            local n = 0
            if ok and type(cols) == "table" then
                for k, v in pairs(cols) do n = n + 1; addLog("Skin " .. tostring(k) .. " = " .. tostring(v), "STAFF") end
            end
            notify(ok and ("GetSkinColors: " .. n .. " entri (Output)") or "Gagal",
                   ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "➕ HireStaff mentah (role, index)", THEME.Green, function()
        task.spawn(function()
            local roles = setList(sel.hireRoles)
            local role = roles[1] or "Gardener"
            local ok, res, err = invokeRF("StaffService", "HireStaff", role, 1)
            addLog("HireStaff('" .. role .. "', 1) -> " .. tostring(res) .. " " .. tostring(err), "STAFF")
            notify(ok and ("HireStaff " .. role .. " dikirim") or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeInfo(c, "HireStaff vs HireApplicant: yang dipakai UI game adalah\nHireApplicant(role, index). HireStaff ada di daftar remote tapi\ntidak dipanggil controller manapun - kemungkinan versi lama.")
end

-- NPCService: InteractWithNPC, SelectDialogueOption, CloseDialogue
do
    local c = makeCard("🗣 NPC & DIALOG", THEME.Green, ExtraBody)

    makeInfo(c, "PERINGATAN JUJUR: SIGNATURE DI KARTU INI BELUM TERBUKTI.\n\nSaya sisir seluruh dump client dan hasilnya NOL: tidak ada satu\npun controller yang memanggil NPCService. Ketiga remote-nya\n(InteractWithNPC, SelectDialogueOption, CloseDialogue) memang ADA\ndi daftar, tapi bentuk argumennya cuma dugaan dari namanya.\n\nBandingkan dengan kartu lain di hub ini: Panen, Tanam, Craft,\nHire, Beli - semuanya dicocokkan ke baris pemanggilan asli di\ncontroller, lengkap dengan nomor barisnya. Yang ini tidak bisa,\nkarena memang tidak ada barisnya.\n\nJadi kalau ditolak server, itu WAJAR - dan pesannya di tab Output\nyang akan memberitahu bentuk yang benar. Saya tidak akan menebak\nlebih jauh dari ini.")

    local npcList = {}
    local npcLbl = makeInfo(c, "tekan 'Cari NPC' untuk memindai workspace...")

    makeButton(c, "🔎 Cari NPC di sekitar", THEME.Blue, function()
        task.spawn(function()
            npcList = {}
            local lines = { "NPC KETEMU:" }
            -- NPC = model ber-Humanoid yang bukan pemain & bukan customer plot
            for _, m in ipairs(Workspace:GetDescendants()) do
                if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")
                   and not Players:GetPlayerFromCharacter(m) then
                    local par = m.Parent
                    local isCustomer = par and par.Name == "Customers"
                    if not isCustomer then
                        npcList[#npcList + 1] = m
                        if #npcList <= 25 then
                            lines[#lines + 1] = "  " .. #npcList .. ". " .. m.Name ..
                                                "  (" .. tostring(par and par.Name) .. ")"
                        end
                    end
                end
            end
            if #npcList > 25 then lines[#lines + 1] = "  ... (+" .. (#npcList - 25) .. " lagi)" end
            if #npcList == 0 then lines[#lines + 1] = "  (tidak ada)" end
            npcLbl.Text = table.concat(lines, "\n")
            notify("NPC ketemu: " .. #npcList, THEME.On)
        end)
    end)

    local getNpc = makeDropdown(c, "NPC", function()
        local out = {}
        for i, m in ipairs(npcList) do out[#out + 1] = i .. ". " .. m.Name end
        if #out == 0 then out[1] = "(tekan 'Cari NPC' dulu)" end
        return out
    end, function() end, "None")

    makeButton(c, "💬 InteractWithNPC", THEME.Green, function()
        task.spawn(function()
            local lbl = getNpc()
            local idx = lbl and tonumber(string.match(lbl, "^(%d+)%."))
            local npc = idx and npcList[idx]
            if not npc then notify("Pilih NPC dulu", THEME.Yellow); return end
            local ok, res, err = invokeRF("NPCService", "InteractWithNPC", npc)
            addLog("InteractWithNPC(" .. npc.Name .. ") -> " .. tostring(res) .. " " .. tostring(err), "NPC")
            notify(ok and ("Interact: " .. tostring(err or res)) or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    local dlgOpt = 1
    makeSlider(c, "Pilihan dialog ke-", 1, 1, 6, THEME.Green, function(v) dlgOpt = math.floor(v) end)

    makeButton(c, "✅ SelectDialogueOption", THEME.Green, function()
        task.spawn(function()
            local ok, res, err = invokeRF("NPCService", "SelectDialogueOption", dlgOpt)
            addLog("SelectDialogueOption(" .. dlgOpt .. ") -> " .. tostring(res) .. " " .. tostring(err), "NPC")
            notify(ok and ("Pilih opsi " .. dlgOpt) or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "❌ CloseDialogue", THEME.Yellow, function()
        invokeRF("NPCService", "CloseDialogue")
        notify("CloseDialogue dikirim", THEME.Yellow)
    end)
end

-- Sisa: QuestService(TrackQuest/ClaimRewardTimed), EquipmentService(info),
-- UpgradeService(GetLevel), AnimationService, MoneyService(OpenMenu)
do
    local c = makeCard("🧩 REMOTE SISA (lengkap)", THEME.Orange, ExtraBody)

    -- ANGKA 1..30 DIBUANG DARI SINI JUGA. Quest dikunci NAMA, dan
    -- TrackQuest pun dipanggil dengan nama itu (QuestController baris
    -- 9525: v2:TrackQuest(k)). Slider angka di sini dulu sama salahnya
    -- dengan Auto Quest yang lama.
    local getQuest = makeDropdown(c, "Quest", function()
        local out = {}
        for _, q in ipairs(QUEST.daftar()) do out[#out + 1] = q.nama end
        if #out == 0 then out[1] = "(buka panel Quest di game dulu)" end
        return out
    end, function() end, "None")

    makeButton(c, "🎯 TrackQuest (lacak quest)", THEME.Purple, function()
        task.spawn(function()
            local q = getQuest()
            if not q or not QUEST.data or not QUEST.data[q] then
                notify("Pilih quest dulu (daftarnya dari server)", THEME.Yellow); return
            end
            local ok, res = invokeRF("QuestService", "TrackQuest", q)
            addLog("TrackQuest('" .. q .. "') -> " .. tostring(res), "QUEST")
            notify(ok and ("TrackQuest " .. q) or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "⏱ ClaimRewardTimed (quest berwaktu)", THEME.Purple, function()
        task.spawn(function()
            local q = getQuest()
            if not q or not QUEST.data or not QUEST.data[q] then
                notify("Pilih quest dulu (daftarnya dari server)", THEME.Yellow); return
            end
            local ok, res, msg = invokeRF("QuestService", "ClaimRewardTimed", q)
            addLog("ClaimRewardTimed('" .. q .. "') -> " .. tostring(res) ..
                   " " .. tostring(msg), "QUEST")
            notify(ok and ("ClaimRewardTimed " .. q) or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeInfo(c, "ClaimRewardTimed TIDAK PERNAH dipanggil controller manapun, jadi\nbentuk argumennya belum terbukti. Di sini dikirim NAMA quest -\nmengikuti pola ClaimReward & TrackQuest yang sudah terbukti pakai\nnama. Kalau server menolak, pesannya muncul di tab Output dan\nitu jawabannya; saya tidak akan mengarang tebakan kedua.")

    local eqLbl = makeInfo(c, "-")

    makeButton(c, "🔧 GetAllEquipmentLevels + GetEquipmentInfo", THEME.Blue, function()
        task.spawn(function()
            local ok1, lv = invokeRF("EquipmentService", "GetAllEquipmentLevels")
            local ok2, info = invokeRF("EquipmentService", "GetEquipmentInfo", "CraftTable")
            local lines = {}
            if ok1 and type(lv) == "table" then
                lines[#lines + 1] = "SEMUA LEVEL EQUIPMENT:"
                for k, v in pairs(lv) do
                    lines[#lines + 1] = "  " .. tostring(k) .. " = " .. tostring(v)
                    addLog("EquipLevel " .. tostring(k) .. " = " .. tostring(v), "EXTRA")
                end
            else lines[#lines + 1] = "GetAllEquipmentLevels gagal" end
            if ok2 and type(info) == "table" then
                lines[#lines + 1] = "INFO CraftTable:"
                for k, v in pairs(info) do
                    lines[#lines + 1] = "  " .. tostring(k) .. " = " ..
                        (type(v) == "table" and "<table>" or tostring(v))
                end
            else lines[#lines + 1] = "GetEquipmentInfo gagal" end
            eqLbl.Text = table.concat(lines, "\n")
        end)
    end)

    makeButton(c, "📈 UpgradeService.GetLevel(Advertising)", THEME.Blue, function()
        task.spawn(function()
            local ok, lvl = invokeRF("UpgradeService", "GetLevel", "Advertising")
            notify(ok and ("Advertising level = " .. tostring(lvl)) or "Gagal",
                   ok and THEME.On or THEME.Red)
            addLog("UpgradeService.GetLevel(Advertising) = " .. tostring(lvl), "EXTRA")
        end)
    end)

    makeButton(c, "🖐 AnimationService: Unequip semua tool", THEME.Yellow, function()
        task.spawn(function()
            local ok = invokeRF("AnimationService", "UnequipTool")
            notify(ok and "UnequipTool dikirim" or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeButton(c, "🖐 AnimationService: EquipTool (tool dipegang)", THEME.Yellow, function()
        task.spawn(function()
            local char = LocalPlayer.Character
            local t = char and char:FindFirstChildOfClass("Tool")
            if not t then notify("Tidak ada tool yang dipegang", THEME.Yellow); return end
            local ok, res = invokeRF("AnimationService", "EquipTool", t)
            addLog("EquipTool(" .. t.Name .. ") -> " .. tostring(res), "EXTRA")
            notify(ok and ("EquipTool " .. t.Name) or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    local animBox = Instance.new("TextBox", c)
    animBox.Size = UDim2.new(1, 0, 0, 32)
    animBox.BackgroundColor3 = THEME.Slot
    animBox.PlaceholderText = "nama animasi (Sprint / HoldBouquet / Walk / Admiring)"
    animBox.Text = ""
    animBox.TextColor3 = THEME.Text
    animBox.Font = THEME.FontReg
    animBox.TextSize = 12
    animBox.ClearTextOnFocus = false
    animBox.LayoutOrder = nextOrder()
    corner(animBox, 8)
    stroke(animBox, THEME.Stroke, 1)

    makeButton(c, "🕺 PlayAnimation", THEME.Pink, function()
        task.spawn(function()
            local a = animBox.Text
            if a == "" then notify("Isi nama animasi dulu", THEME.Yellow); return end
            local ok, res = invokeRF("AnimationService", "PlayAnimation", a)
            addLog("PlayAnimation('" .. a .. "') -> " .. tostring(res), "EXTRA")
            notify(ok and ("PlayAnimation " .. a) or "Gagal", ok and THEME.On or THEME.Red)
        end)
    end)

    makeInfo(c, "Nama animasi yang ADA di Assets.Animation - ini terverifikasi,\ndibaca dari pohon aset: Sprint, HoldBouquet, Walk, Admiring.\n\nTAPI signature remote-nya BELUM terbukti. Sama seperti NPCService,\ntidak ada satu pun controller yang memanggil AnimationService.\nYang dipakai game justru jalur LOKAL: AnimationController punya\nfungsinya sendiri (SPSV2TELITI baris 3168) yang memuat animasi\nlangsung dari Assets.Animation dan memainkannya di client -\ntanpa remote sama sekali. Urutan argumennya di situ:\n   PlayAnimation(self, karakter, namaAnimasi, ..., kecepatan)\njadi RF-nya bisa saja menuntut KARAKTER dulu, bukan nama.\n\nUnequip juga begitu: game memakai Humanoid:UnequipTools() biasa\n(baris 2458), bukan remote.\n\nDua tombol ini dibiarkan sebagai alat uji. Kalau ditolak, lihat\npesannya di tab Output.")

    makeButton(c, "🪟 MoneyService.OpenMenu", THEME.Blue, function()
        local ok = invokeRF("MoneyService", "OpenMenu")
        notify(ok and "OpenMenu dikirim" or "Gagal", ok and THEME.On or THEME.Red)
    end)

    makeButton(c, "🧪 TemplateService (uji coba dev)", THEME.Purple, function()
        task.spawn(function()
            local ok, res = invokeRF("TemplateService", "TemplateFunction")
            addLog("TemplateFunction -> " .. tostring(res), "EXTRA")
            notify(ok and ("TemplateFunction: " .. tostring(res)) or "Gagal",
                   ok and THEME.On or THEME.Red)
        end)
    end)

    makeInfo(c, "GIFT CASH / GIFT GEMS: TIDAK ADA.\nMoneyService cuma punya 7 RF: RedeemCode, OpenMenu, GiftGamepass,\nGroupReward, ClaimDailyReward, GiftProduct, BuyStarterPack.\nTidak ada AddCash / AddGems / GiftCash / GiftGems.\n\nGiftGamepass(player, nama) & GiftProduct(player, nama) itu\nBUKAN kirim uang - itu 'belikan gamepass/produk untuk teman',\ndan yang BAYAR ROBUX tetap kamu (RobuxController baris 213:\ntombol Gift memanggil RF ini, servernya lalu memicu\nPromptProductPurchase ke pembeli).\n\nSama juga: BuyStarterPack, GrowAll (produk 3610937789),\nSellAll (3610937817) - semuanya Robux.\nSengaja tidak dibuatkan tombol supaya tidak salah pencet.")
end

task.wait()   -- jeda satu frame (lihat PEMBANGUNAN BERTAHAP di atas)

-- ============================================================
-- BUILD UI : TAB SETTINGS
-- ============================================================
local saveSettings, loadSettings

do
    local c = makeCard("PENGATURAN GUI", THEME.Cyan, SettingsBody)

    makeSlider(c, "Skala GUI", config.guiScale * 100, 55, 180, THEME.Cyan, function(v)
        config.guiScale = v / 100
        MainScale.Scale = config.guiScale
    end)

    makeButton(c, "🎯 Reset Posisi GUI ke Tengah", THEME.Blue, function()
        Frame.Position = UDim2.new(0.5, 0, 0.5, 0)
        Circle.Position = UDim2.new(0.5, 0, 0, 70)
        notify("Posisi GUI direset", THEME.On)
    end)

    makeInfo(c, "Grip ◢ di pojok kanan-bawah frame juga bisa dipakai untuk\nmembesarkan / mengecilkan GUI dengan menyeret.")
end

do
    local c = makeCard("💾 SIMPAN / MUAT KONFIGURASI", THEME.Green, SettingsBody)

    makeInfo(c, hasFS and ("File: " .. SETTINGS_FILE) or
        "Executor kamu tidak punya writefile/readfile,\njadi simpan konfigurasi TIDAK tersedia.")

    saveSettings = function()
        if not hasFS then notify("Executor tak support writefile", THEME.Red); return end
        local payload = {
            config = {
                flySpeed = config.flySpeed, walkSpeed = config.walkSpeed,
                jumpPower = config.jumpPower, guiScale = config.guiScale,
                farmDelay = config.farmDelay, shopDelay = config.shopDelay,
                buildDelay = config.buildDelay, craftDelay = config.craftDelay,
                sellDelay = config.sellDelay,
                -- Dua angka JUMLAH beli. Rugi kalau harus disetel ulang
                -- tiap masuk game, dan dua-duanya menentukan seberapa
                -- banyak uangmu keluar per sapuan.
                buyQty = config.buyQty, qtySupply = config.qtySupply,
                planterRotation = config.planterRotation,
                displayRotation = config.displayRotation,
                gridStep = config.gridStep, containerPick = config.containerPick,
                -- Ikut disimpan sejak filter bintang hire bisa dipilih:
                -- kalau dropdown bintangnya dikosongkan, angka INI yang
                -- menentukan siapa yang direkrut, jadi rugi kalau hilang.
                minStars = config.minStars,
                -- Dua ini menentukan seberapa banyak yang DIHABISKAN, jadi
                -- rugi kalau harus disetel ulang tiap masuk game.
                habisStok = config.habisStok,
                -- Kapasitas rak rangkaian yang sudah TERUKUR dari penolakan
                -- server. Tanpa ini tiap execute ulang harus mengukur dari
                -- nol lagi - dan di TURBO pengukuran itu MERANGKAK, satu
                -- percobaan per putaran. Sekali terukur, selamanya tahu.
                rakPenuh = _stockWarn.penuh,
                -- Batas slot TAS yang sudah terukur dari craft yang
                -- hasilnya kurang dari yang diminta. Alasannya sama dengan
                -- rakPenuh: tanpa ini tiap execute ulang harus mengukur
                -- dari nol, dan pengukurannya MEMBUANG satu probe.
                tasMax = _stockWarn.tas,
            },
            sel = {},
        }
        for k, v in pairs(sel) do payload.sel[k] = setList(v) end
        local ok, err = pcall(function()
            writefile(SETTINGS_FILE, HttpService:JSONEncode(payload))
        end)
        notify(ok and "Konfigurasi disimpan OK" or ("Gagal simpan: " .. tostring(err)),
               ok and THEME.On or THEME.Red)
    end

    loadSettings = function()
        if not hasFS then notify("Executor tak support readfile", THEME.Red); return end
        if not isfile(SETTINGS_FILE) then notify("Belum ada file konfigurasi", THEME.Yellow); return end
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(SETTINGS_FILE))
        end)
        if not ok or type(data) ~= "table" then
            notify("File konfigurasi rusak", THEME.Red); return
        end
        if type(data.config) == "table" then
            -- Kapasitas rak yang terukur BUKAN milik config - dia tinggal di
            -- _stockWarn.penuh. Kalau ikut disalin ke config dia jadi nama
            -- mati yang tidak pernah dibaca siapa pun, dan pengukurannya
            -- tetap hilang tiap execute ulang.
            local rp = data.config.rakPenuh
            data.config.rakPenuh = nil
            -- Sama seperti rakPenuh: tempatnya di _stockWarn, BUKAN di
            -- config. Kalau dibiarkan masuk config dia jadi nama mati.
            local tm = tonumber(data.config.tasMax)
            data.config.tasMax = nil
            if tm and tm > 0 then
                _stockWarn.tas = tm
                addLog("Batas slot tas dimuat dari file: " .. tm ..
                       " - batch craft langsung dipotong tepat, tanpa probe", "CRAFT")
            end
            if type(rp) == "table" then
                local n = 0
                for model, angka in pairs(rp) do
                    -- Nama model TIDAK diperiksa terhadap katalog: rak yang
                    -- kamu jual / belum dipasang tetap boleh diingat, dan
                    -- angkanya baru dipakai kalau rak itu memang ada.
                    if type(model) == "string" and tonumber(angka) then
                        _stockWarn.penuh[model] = tonumber(angka)
                        n = n + 1
                    end
                end
                if n > 0 then
                    addLog("Kapasitas rak dimuat dari file: " .. n ..
                           " jenis rak - tidak perlu diukur ulang", "SELL")
                end
            end
            for k, v in pairs(data.config) do config[k] = v end
            MainScale.Scale = config.guiScale
            -- Kotak angka ikut digambar ulang. Tanpa ini "Jumlah BIBIT"
            -- di layar tetap menampilkan angka lama sementara yang
            -- dipakai sudah yang dari file - persis jenis kebohongan
            -- yang sedang kita berantas di seluruh hub ini.
            samakanAngka()
        end
        if type(data.sel) == "table" then
            for k, list in pairs(data.sel) do
                if sel[k] and type(list) == "table" then
                    for key in pairs(sel[k]) do sel[k][key] = nil end
                    for _, name in ipairs(list) do sel[k][name] = true end
                end
            end
        end
        notify("Konfigurasi dimuat OK (buka ulang GUI biar tampilan ikut)", THEME.On)
    end

    makeButton(c, "💾 Simpan Konfigurasi", THEME.Green, function() saveSettings() end)
    makeButton(c, "📂 Muat Konfigurasi", THEME.Blue, function() loadSettings() end)
end

do
    local c = makeCard("🛑 KONTROL MASSAL", THEME.Red, SettingsBody)

    makeButton(c, "⛔ MATIKAN SEMUA FITUR AUTO", THEME.Red, function()
        for name in pairs(loops) do loops[name] = nil end

        -- SENGAJA TIDAK DISENTUH: fitur GERAK & TAMPILAN. Namanya
        -- "matikan semua fitur AUTO", dan mematikan Fly waktu kamu
        -- melayang itu menjatuhkanmu ke tanah.
        --
        -- clickTp / unlockZoom / holdMouse JANGAN ikut di-false-kan di
        -- sini kalau fungsi penghentiannya tidak dipanggil - itu bikin
        -- `state` bilang MATI sementara fiturnya tetap JALAN.
        local jangan = {
            fly = true, noclip = true, speed = true, infJump = true,
            clickTp = true, unlockZoom = true, holdMouse = true,
        }
        for k in pairs(state) do
            if not jangan[k] then state[k] = false end
        end
        clearCropEsp()

        -- Sakelar di tab Auto punya tampilannya sendiri; tanpa ini dia
        -- tetap kelihatan ON padahal loopnya sudah mati.
        if AUTO.set then
            for _, fn in pairs(AUTO.set) do pcall(fn, false) end
        end
        AUTO.pantau(false)

        -- Yang tidak bisa dimatikan lewat `loops` maupun AUTO.set: RE SPY
        -- dan PROMPT SPY. Keduanya cuma kumpulan koneksi, dan sebelum ini
        -- SELAMAT dari tombol ini - tetap merekam, tetap memaksa Output
        -- menyala. Sekarang mereka mendaftarkan fungsi matinya sendiri.
        for _, fn in ipairs(AUTO.mati or {}) do pcall(fn) end

        -- Toko: `state.shopOpen` cuma CATATAN lokal, yang sebenarnya ada
        -- di atribut ShopOpen milik plot - dan tombol ini tidak menutup
        -- toko. Jadi kalau state-nya dipaksa false, sakelarnya akan
        -- berbohong ke arah sebaliknya. Dibaca ulang dari plot supaya
        -- yang tampil memang keadaan asli.
        local plot = getMyPlot()
        state.shopOpen = (plot and plot:GetAttribute("ShopOpen")) == true

        -- Ini yang dulu tidak ada: menyamakan SEMUA gambar sakelar dengan
        -- isi `state` yang sebenarnya. Tanpa ini, sakelar di tab Farm /
        -- Shop / Build / Craft / Extra tetap menampilkan ON walau loopnya
        -- sudah mati - dan tidak ada cara tahu mana yang benar.
        samakanSakelar()

        notify("Semua fitur auto dimatikan - sakelarnya ikut disamakan", THEME.Yellow)
    end)

    local loopLbl = makeInfo(c, "-")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan. Lihat catatan panjang di
            -- tampil(): 15 loop label ini dulu jalan terus walau semua fitur
            -- auto sudah dimatikan, dan itu sumber lag yang paling besar.
            while ScreenGui.Parent and not tampil(SettingsBody) do task.wait(0.4) end
            local names = {}
            for k, v in pairs(loops) do if v then table.insert(names, k) end end
            table.sort(names)
            loopLbl.Text = "LOOP AKTIF (" .. #names .. "):\n  " ..
                (#names > 0 and table.concat(names, ", ") or "(tidak ada)")
            task.wait(1)
        end
    end)

    makeButton(c, "🔁 Rejoin Server", THEME.Orange, function()
        confirmDialog("Rejoin ke server yang sama?", function()
            pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
        end)
    end)
end

-- ============================================================
-- PEMERIKSA LAG
-- ============================================================
-- Kartu ini ada karena satu pertanyaan yang tidak bisa dijawab dengan
-- menebak: "sudah saya matikan semua auto, kok masih berat - ada yang
-- masih nyala?". Daripada saya mengarang, ini alat ukurnya.
do
    local c = makeCard("🩺 PEMERIKSA LAG", THEME.Red, SettingsBody)

    makeInfo(c, "CARA MEMBUKTIKAN PANEL INI PENYEBABNYA ATAU BUKAN:\n\n  1. lihat angka FPS di bawah, catat\n  2. tekan [RightShift] (PC) atau tombol - untuk minimize\n  3. tunggu 5 detik, buka lagi, lihat FPS-nya waktu tertutup tadi\n\nSaat panel disembunyikan SEMUA label berhenti bekerja - itu\nmemang sengaja. Kalau FPS naik banyak berarti panelnya yang\nberat; kalau tidak berubah, berarti bebannya dari game / plot\nkamu sendiri (planter & rak yang banyak memang berat).")

    local lagLbl = makeInfo(c, "mengukur...")
    task.spawn(function()
        while ScreenGui.Parent do
            -- Tidur selama tab ini tidak kelihatan (lihat tampil()).
            while ScreenGui.Parent and not tampil(SettingsBody) do task.wait(0.4) end

            -- FPS diukur dengan MENUNGGU 10 frame, bukan dengan
            -- menyambung ke RenderStepped. Sambungan permanen justru
            -- menambah beban tiap frame - dan itu persis hal yang sedang
            -- kita cari, jadi tidak boleh alatnya sendiri yang mengotori
            -- ukurannya.
            local t0 = os.clock()
            for _ = 1, 10 do RunService.RenderStepped:Wait() end
            local fps = 10 / math.max(os.clock() - t0, 1e-6)

            local nLoop, namaLoop = 0, {}
            for k, v in pairs(loops) do
                if v then nLoop = nLoop + 1; namaLoop[#namaLoop + 1] = k end
            end
            table.sort(namaLoop)

            local berat = {}
            if state.tpSpy then
                berat[#berat + 1] = "  * Rekam LOMPATAN badan  -> jalan TIAP FRAME (jeda 0)"
            end
            if state.reSpy then
                berat[#berat + 1] = "  * RE Spy  -> menempel di 65 RemoteEvent sekaligus"
            end
            if state.promptSpy then
                berat[#berat + 1] = "  * Prompt Spy  -> mencatat tiap prompt yang tertembak"
            end
            if logEnabled then
                berat[#berat + 1] = "  * Output ON  -> tiap aksi ditulis ke log"
            end
            if state.holdMouse then
                berat[#berat + 1] = "  * Munculkan Mouse  -> BindToRenderStep tiap frame"
            end
            if state.turbo then
                berat[#berat + 1] = "  * TURBO  -> panggilan server tanpa jeda"
            end
            if #berat == 0 then berat[1] = "  (tidak ada)" end

            local lines = {
                string.format("FPS sekarang : %.0f", fps),
                "",
                "LOOP AKTIF (" .. nLoop .. "):",
                "  " .. (nLoop > 0 and table.concat(namaLoop, ", ") or "(tidak ada)"),
                "",
                "YANG MEMANG BERAT DAN SEDANG NYALA:",
            }
            for _, b in ipairs(berat) do lines[#lines + 1] = b end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "BEBAN DARI PLOT KAMU (ini bukan salah panel):"
            lines[#lines + 1] = "  Planter       : " .. #getMyPlanters()
            lines[#lines + 1] = "  Rak bunga     : " .. #rakPlot("FlowerDisplay")
            lines[#lines + 1] = "  Rak rangkaian : " .. #rakPlot("ArrangementDisplay")
            lagLbl.Text = table.concat(lines, "\n")
            task.wait(2)
        end
    end)

    makeButton(c, "🪶 RINGANKAN SEKARANG (matikan semua yang berat)", THEME.Green, function()
        for name in pairs(loops) do loops[name] = nil end
        -- Perekam, pengintai, dan log dimatikan juga. Ini yang TIDAK
        -- dilakukan tombol "MATIKAN SEMUA FITUR AUTO" sebelum ini: RE Spy
        -- dan Prompt Spy bukan "fitur auto", jadi dia lolos terus.
        for _, fn in ipairs(AUTO.mati or {}) do pcall(fn) end
        state.tpSpy = false
        if AUTO.set then for _, fn in pairs(AUTO.set) do pcall(fn, false) end end
        AUTO.pantau(false)
        clearCropEsp()
        state.cropEsp, state.turbo = false, false
        for k in pairs(state) do
            if string.sub(k, 1, 4) == "auto" then state[k] = false end
        end
        -- Toko TIDAK ditutup tombol ini (menutupnya menghentikan pemasukan,
        -- itu keputusanmu bukan keputusan tombol "ringankan"). Karena itu
        -- statusnya dibaca ulang dari plot, supaya sakelarnya menampilkan
        -- keadaan asli - bukan tebakan.
        local plot = getMyPlot()
        state.shopOpen = (plot and plot:GetAttribute("ShopOpen")) == true
        if logEnabled then
            logEnabled = false
            outToggleBtn.Text = "Output: OFF"
            outToggleBtn.BackgroundColor3 = THEME.Off
        end
        samakanSakelar()
        notify("Semua yang berat dimatikan - lihat FPS di kotak atas", THEME.On)
    end)

    makeInfo(c, "APA YANG SUDAH DIPERBAIKI DI VERSI INI - tiga hal, dan semuanya\njalan terus walau kamu sudah mematikan semua auto:\n\n  1. 15 LABEL HIDUP di panel ini dulu bekerja terus-menerus,\n     tiap 1-6 detik, walau tabnya tidak dibuka dan walau panelnya\n     sedang diminimize. Yang paling mahal menyisir SEMUA planter x\n     SEMUA slot, dan satu lagi memanggil server tiap 6 detik.\n     Sekarang isinya cuma jalan kalau tabnya benar-benar terlihat.\n\n  2. PENCARI PROMPT KASIR memindai SELURUH plot tiap 1,5 detik.\n     Parahnya justru saat meja kasir KOSONG: promptnya memang\n     belum dibuat server, jadi dua pencarian penuh dijalankan\n     dua-duanya - di plot yang isinya 3080 prompt. Sekarang\n     hasilnya diingat, dan pencarian penuh dijatah 10 detik sekali.\n\n  3. PENULIS LOG menyusun ulang 250 baris jadi satu string SETIAP\n     kali ada satu baris masuk, walau tab Output tidak dibuka.\n     Di mode TURBO itu ratusan kali per detik. Sekarang barisnya\n     tetap dicatat tapi baru dicetak saat tab Output dibuka.\n\nDan yang menjawab 'ada tombol yang dimatikan tapi tetap nyala?':\nada, dan itu ADA DUA JENIS.\n\n  * BOHONG ARAH SATU - fiturnya mati, tombolnya tetap ON. Semua\n    sakelar di tab Farm/Shop/Build/Craft/Extra begitu: tombol\n    'MATIKAN SEMUA FITUR AUTO' mematikan loopnya tapi tidak\n    membalik gambarnya. Sekarang gambarnya ikut disamakan.\n\n  * BOHONG ARAH DUA - ini yang berbahaya. 'Munculkan Mouse',\n    'Click to Teleport', dan 'Unlock Zoom' dulu ditandai MATI di\n    dalam, tapi fungsi penghentiannya tidak pernah dipanggil, jadi\n    fiturnya TETAP JALAN. 'Munculkan Mouse' bahkan menyetel mouse\n    tiap frame lewat BindToRenderStep. Sekarang ketiganya tidak\n    lagi disentuh tombol massal, jadi tidak ada lagi yang mengaku\n    mati padahal hidup.\n\n  * RE Spy & Prompt Spy dulu SELAMAT dari tombol massal karena dia\n    cuma kumpulan koneksi, bukan loop. Sekarang mereka ikut\n    dimatikan tombol massal maupun tombol RINGANKAN di atas.")
end

do
    local c = makeCard("🧰 DEBUG / REMOTE", THEME.Purple, SettingsBody)

    makeButton(c, "📄 List Semua Service & Remote", THEME.Blue, function()
        if not KnitServices then notify("Knit Services tidak ketemu", THEME.Red); return end
        if not logEnabled then
            logEnabled = true
            outToggleBtn.Text = "Output: ON"
            outToggleBtn.BackgroundColor3 = THEME.On
        end
        local nS, nR = 0, 0
        for _, svc in ipairs(KnitServices:GetChildren()) do
            nS = nS + 1
            addLog("SERVICE " .. svc.Name, "DUMP")
            for _, kind in ipairs({ "RF", "RE" }) do
                local f = svc:FindFirstChild(kind)
                if f then
                    for _, r in ipairs(f:GetChildren()) do
                        nR = nR + 1
                        addLog("   " .. kind .. "." .. r.Name, "DUMP")
                    end
                end
            end
        end
        notify(nS .. " service, " .. nR .. " remote (lihat Output)", THEME.On)
        showTab("output")
    end)

    makeButton(c, "📋 Copy Daftar Remote ke Clipboard", THEME.Purple, function()
        if not KnitServices then notify("Knit Services tidak ketemu", THEME.Red); return end
        local lines = {}
        for _, svc in ipairs(KnitServices:GetChildren()) do
            for _, kind in ipairs({ "RF", "RE" }) do
                local f = svc:FindFirstChild(kind)
                if f then
                    for _, r in ipairs(f:GetChildren()) do
                        table.insert(lines, svc.Name .. "." .. kind .. "." .. r.Name)
                    end
                end
            end
        end
        if setclipboard then
            pcall(setclipboard, table.concat(lines, "\n"))
            notify(#lines .. " remote disalin OK", THEME.On)
        else
            notify("Executor tak support setclipboard", THEME.Red)
        end
    end)

    makeInfo(c, "GrowAll & SellAll di plot BUKAN gratis: keduanya memicu\nPromptProductPurchase (Robux 3610937789 / 3610937817).\nJadi TIDAK dipakai di auto farm.")
end

-- ============================================================
-- KONSOL REMOTE UNIVERSAL
-- Menutup 100% remote (146 buah) termasuk yang belum punya tombol khusus,
-- dan tetap jalan kalau developer menambah remote baru nanti.
-- ============================================================
do
    local c = makeCard("🎛 KONSOL REMOTE UNIVERSAL", THEME.Cyan, SettingsBody)

    makeInfo(c, "Panggil remote APAPUN secara manual. Berguna untuk remote yang\nargumennya belum diketahui - hasil mentahnya dicetak ke Output.")

    local svcPick, kindPick, methodPick = nil, "RF", nil

    local function serviceNames()
        local out = {}
        if KnitServices then
            for _, s in ipairs(KnitServices:GetChildren()) do out[#out + 1] = s.Name end
        end
        table.sort(out)
        if #out == 0 then out[1] = "(Knit tidak ketemu)" end
        return out
    end

    local function methodNames()
        local out = {}
        if KnitServices and svcPick then
            local svc = KnitServices:FindFirstChild(svcPick)
            local folder = svc and svc:FindFirstChild(kindPick)
            if folder then
                for _, r in ipairs(folder:GetChildren()) do out[#out + 1] = r.Name end
            end
        end
        table.sort(out)
        if #out == 0 then out[1] = "(pilih service dulu)" end
        return out
    end

    makeDropdown(c, "Service", serviceNames, function(item)
        svcPick = item; methodPick = nil
        notify("Service: " .. item, THEME.Cyan)
    end, "None")

    makeDropdown(c, "Jenis", { "RF", "RE" }, function(item)
        kindPick = item; methodPick = nil
    end, "RF")

    makeDropdown(c, "Method", methodNames, function(item)
        methodPick = item
    end, "None")

    local argBox = Instance.new("TextBox", c)
    argBox.Size = UDim2.new(1, 0, 0, 32)
    argBox.BackgroundColor3 = THEME.Slot
    argBox.PlaceholderText = "argumen dipisah koma (kosongkan kalau tidak ada)"
    argBox.Text = ""
    argBox.TextColor3 = THEME.Text
    argBox.Font = THEME.FontReg
    argBox.TextSize = 12
    argBox.ClearTextOnFocus = false
    argBox.LayoutOrder = nextOrder()
    corner(argBox, 8)
    stroke(argBox, THEME.Stroke, 1)

    makeInfo(c, "Kata kunci khusus di argumen:\n  me         -> objek Player kamu\n  plot       -> model plot kamu\n  crafttable -> CraftTable di plot\n  planter1   -> planter ke-1 (planter2, dst)\n  display1   -> rak bunga ke-1\nAngka jadi number, true/false jadi boolean, nil jadi nil,\nselain itu dianggap teks.")

    -- ubah teks argumen jadi nilai Lua sungguhan
    local function parseArgs(s)
        local out, n = {}, 0
        if not s or s == "" then return out, 0 end
        for piece in string.gmatch(s, "[^,]+") do
            piece = string.match(piece, "^%s*(.-)%s*$")
            n = n + 1
            local low = string.lower(piece)
            if low == "nil" then out[n] = nil
            elseif low == "true" then out[n] = true
            elseif low == "false" then out[n] = false
            elseif low == "me" then out[n] = LocalPlayer
            elseif low == "plot" then out[n] = getMyPlot()
            elseif low == "crafttable" then out[n] = getMyCraftTable()
            elseif string.match(low, "^planter%d+$") then
                out[n] = getMyPlanters()[tonumber(string.match(low, "%d+"))]
            elseif string.match(low, "^display%d+$") then
                out[n] = rakPlot("FlowerDisplay")[tonumber(string.match(low, "%d+"))]
            elseif tonumber(piece) then out[n] = tonumber(piece)
            else out[n] = piece end
        end
        return out, n
    end

    local resLbl = makeInfo(c, "hasil akan muncul di sini...")

    makeButton(c, "▶ PANGGIL REMOTE", THEME.Green, function()
        task.spawn(function()
            if not svcPick or not methodPick then
                notify("Pilih Service + Method dulu", THEME.Yellow); return
            end
            local args, n = parseArgs(argBox.Text)
            local head = svcPick .. "." .. kindPick .. "." .. methodPick ..
                         "(" .. (argBox.Text ~= "" and argBox.Text or "") .. ")"

            if kindPick == "RE" then
                local ok = fireRE(svcPick, methodPick, table.unpack(args, 1, n))
                resLbl.Text = head .. "\n-> RemoteEvent dikirim: " .. tostring(ok)
                addLog(head .. " (RE) -> " .. tostring(ok), "CONSOLE")
                notify(ok and "RE dikirim" or "RE gagal", ok and THEME.On or THEME.Red)
                return
            end

            local packed = table.pack(invokeRF(svcPick, methodPick, table.unpack(args, 1, n)))
            local lines = { head }
            for i = 1, packed.n do
                local v = packed[i]
                if type(v) == "table" then
                    lines[#lines + 1] = "  [" .. i .. "] <table>:"
                    local cnt = 0
                    for k, vv in pairs(v) do
                        cnt = cnt + 1
                        if cnt <= 12 then
                            lines[#lines + 1] = "        " .. tostring(k) .. " = " ..
                                (type(vv) == "table" and "<table>" or tostring(vv))
                        end
                        addLog("   " .. tostring(k) .. " = " ..
                            (type(vv) == "table" and "<table>" or tostring(vv)), "CONSOLE")
                    end
                    if cnt > 12 then lines[#lines + 1] = "        ... (+" .. (cnt - 12) .. ", lihat Output)" end
                    if cnt == 0 then lines[#lines + 1] = "        (kosong)" end
                else
                    lines[#lines + 1] = "  [" .. i .. "] " .. tostring(v)
                    addLog("  [" .. i .. "] " .. tostring(v), "CONSOLE")
                end
            end
            resLbl.Text = table.concat(lines, "\n")
            notify("Remote dipanggil - lihat hasil", THEME.On)
        end)
    end)
end

-- RE SPY: dengarkan SEMUA RemoteEvent dari server, cetak ke Output.
-- Berguna untuk tahu bentuk data yang dikirim server (mis. UpdateQuestUI).
do
    local c = makeCard("🕵 RE SPY (intip data server)", THEME.Purple, SettingsBody)

    makeInfo(c, "Menghubungkan diri ke SEMUA RemoteEvent milik Knit, lalu\nmencetak apapun yang dikirim server ke tab Output.\nDipakai untuk membongkar bentuk data yang belum diketahui\n(mis. UpdateQuestUI, SetupShopUI, InventoryUpdated).")

    -- `spyOn` dulu ada di sini tapi cuma ditulisi, tidak pernah dibaca -
    -- statusnya sudah tergambar dari #spyConns. Dihapus (variabel mati).
    local spyConns = {}

    -- Dulu 65 koneksi ini SATU-SATUNYA cara mematikannya adalah menekan
    -- ulang sakelarnya sendiri. Tombol "MATIKAN SEMUA FITUR AUTO" tidak
    -- menyentuhnya sama sekali, jadi dia tetap merekam tiap event server
    -- dan tetap memaksa Output menyala - salah satu sebab "sudah
    -- dimatikan semua tapi masih berat". Sekarang fungsinya didaftarkan
    -- ke AUTO.mati supaya tombol massal benar-benar sampai ke sini.
    local function matikanReSpy()
        for _, conn in ipairs(spyConns) do
            pcall(function() if conn.Connected then conn:Disconnect() end end)
        end
        spyConns = {}
        state.reSpy = false
    end
    AUTO.mati = AUTO.mati or {}
    table.insert(AUTO.mati, matikanReSpy)

    makeToggle(c, "RE Spy - rekam semua event server", THEME.Purple, function(v)
        state.reSpy = v
        if v then
            if not logEnabled then
                logEnabled = true
                outToggleBtn.Text = "Output: ON"
                outToggleBtn.BackgroundColor3 = THEME.On
            end
            local n = 0
            if KnitServices then
                for _, svc in ipairs(KnitServices:GetChildren()) do
                    local folder = svc:FindFirstChild("RE")
                    if folder then
                        for _, re in ipairs(folder:GetChildren()) do
                            if re:IsA("RemoteEvent") then
                                n = n + 1
                                local tag = svc.Name .. "." .. re.Name
                                spyConns[#spyConns + 1] = re.OnClientEvent:Connect(function(...)
                                    local parts = {}
                                    for i = 1, select("#", ...) do
                                        local v2 = select(i, ...)
                                        parts[#parts + 1] = (type(v2) == "table") and "<table>" or tostring(v2)
                                    end
                                    addLog(tag .. "(" .. table.concat(parts, ", ") .. ")", "SPY")
                                end)
                            end
                        end
                    end
                end
            end
            notify("RE Spy ON - " .. n .. " event dipantau", THEME.On)
            showTab("output")
        else
            matikanReSpy()
            notify("RE Spy OFF", THEME.Off)
        end
    end, "reSpy")
end

-- ============================================================
-- PROMPT SPY : membongkar cara script LAIN melakukan auto-nya
-- ============================================================
-- RE SPY di atas TIDAK bisa menangkap auto-kasir hub lain: menembak
-- ProximityPrompt tidak lewat RemoteEvent Knit sama sekali.
--
-- Yang menangkapnya ProximityPromptService.PromptTriggered - jalan di
-- CLIENT untuk tiap prompt yang tertembak dari client ini, oleh siapa
-- pun. Yang dicatat: nama, ActionText, JARAK badan ke prompt saat itu,
-- MaxActivationDistance, HoldDuration. Kolom jarak itu jawabannya:
-- besar = menembak dari jauh, kecil = memang mendekat.
--
-- Pengintai kedua memantau lompatan badan, untuk menangkap script yang
-- memindahkanmu diam-diam lalu mengembalikan.
do
    local c = makeCard("🔬 PROMPT SPY (bongkar cara script lain)", THEME.Cyan, SettingsBody)

    makeInfo(c, "RE SPY di atas TIDAK bisa menangkap auto-kasir hub lain -\nmenembak ProximityPrompt tidak lewat RemoteEvent Knit sama sekali,\njadi tidak ada yang muncul di sana.\n\nYang menangkapnya: ProximityPromptService.PromptTriggered.\nKartu ini mencatat tiap prompt yang tertembak dari client ini -\noleh kamu, oleh game, ATAU oleh script lain yang kamu jalankan\nbarengan.\n\nCARA PAKAI untuk membongkar hub lain:\n  1. nyalakan dua sakelar di bawah\n  2. jalankan hub itu, nyalakan auto kasirnya\n  3. buka tab Output\n\nBaca kolom 'jarak': itu jarak badanmu ke prompt PADA DETIK dia\nditembak. Kalau besar (mis. 80 stud) -> dia menembak dari jauh,\ntidak mendekat. Kalau selalu kecil (< 10) -> dia memang mendekat.\nSakelar kedua memastikannya: dia mencatat kalau badanmu tiba-tiba\npindah jauh dalam satu frame - itu tanda lompatan diam-diam.")

    local ppConns = {}

    -- Alasannya sama dengan RE SPY: sebelum ini, satu-satunya cara
    -- mematikannya adalah menekan ulang sakelarnya sendiri, jadi dia
    -- selamat dari tombol "MATIKAN SEMUA FITUR AUTO". Padahal isinya
    -- memanggil addLog untuk SETIAP prompt yang tertembak di client ini -
    -- di plot dengan 3080 prompt itu tidak sedikit.
    local function matikanPromptSpy()
        for _, cn in ipairs(ppConns) do
            pcall(function() if cn.Connected then cn:Disconnect() end end)
        end
        ppConns = {}
        state.promptSpy = false
    end
    AUTO.mati = AUTO.mati or {}
    table.insert(AUTO.mati, matikanPromptSpy)

    makeToggle(c, "Rekam tiap PROMPT yang tertembak", THEME.Cyan, function(v)
        state.promptSpy = v
        if v then
            if not logEnabled then
                logEnabled = true
                outToggleBtn.Text = "Output: ON"
                outToggleBtn.BackgroundColor3 = THEME.On
            end
            local ok, PPS = pcall(function()
                return game:GetService("ProximityPromptService")
            end)
            if not (ok and PPS) then
                -- Gagal sebelum satupun koneksi terpasang. Tanpa dua baris
                -- ini sakelarnya tetap menampilkan ON padahal tidak ada
                -- yang direkam - persis jenis kebohongan yang sedang kita
                -- berantas di versi ini.
                state.promptSpy = false
                samakanSakelar()
                notify("ProximityPromptService tidak terbaca", THEME.Red); return
            end
            ppConns[#ppConns + 1] = PPS.PromptTriggered:Connect(function(p, plr)
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                local par  = p.Parent
                local pos
                if par and par:IsA("Attachment")   then pos = par.WorldPosition
                elseif par and par:IsA("BasePart") then pos = par.Position end
                local jarak = (hrp and pos)
                    and tostring(math.floor((hrp.Position - pos).Magnitude))
                    or "?"
                addLog(string.format(
                    "TRIGGER %s [%s]  jarak=%s  Max=%s  hold=%s  oleh=%s",
                    p.Name, tostring(p.ActionText), jarak,
                    tostring(p.MaxActivationDistance), tostring(p.HoldDuration),
                    tostring(plr and plr.Name or "?")), "PSPY")
            end)
            track(ppConns[#ppConns])
            notify("Prompt Spy ON - buka tab Output", THEME.On)
            showTab("output")
        else
            matikanPromptSpy()
            notify("Prompt Spy OFF", THEME.Off)
        end
    end, "promptSpy")

    makeToggle(c, "Rekam LOMPATAN badan (deteksi tele diam-diam)", THEME.Orange, function(v)
        -- Dicatat di `state` supaya samakanSakelar() bisa membalik
        -- gambarnya waktu loopnya dimatikan dari tempat lain. Loop ini
        -- jalan TIAP FRAME (jedanya 0), jadi dia yang paling tidak boleh
        -- ketinggalan menyala tanpa disadari.
        state.tpSpy = v
        if v then
            startLoop("tpspy", function()
                -- Dibandingkan tiap frame. Lompatan > 25 stud dalam satu
                -- frame mustahil dari jalan kaki biasa (WalkSpeed 16-200
                -- = paling banter ~3 stud per frame), jadi itu pasti
                -- CFrame yang diset paksa - entah oleh script ini, hub
                -- lain, atau teleport milik game.
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then return end
                local last = hrp:GetAttribute("_FHPH_lastPos")
                local now  = hrp.Position
                if last then
                    local d = (now - last).Magnitude
                    if d > 25 then
                        addLog(string.format("LOMPAT %d stud  -> %d, %d, %d",
                            math.floor(d), math.floor(now.X),
                            math.floor(now.Y), math.floor(now.Z)), "PSPY")
                    end
                end
                hrp:SetAttribute("_FHPH_lastPos", now)
            end, function() return 0 end)
            notify("Perekam lompatan ON", THEME.On)
        else
            stopLoop("tpspy")
            notify("Perekam lompatan OFF", THEME.Off)
        end
    end, "tpSpy")

    makeInfo(c, "Hasil sisir saya di hub Ouroboros (games/flowershop.lua, 186 KB,\ndi-obfuscate tapi nama propertinya masih teks polos):\n\n  fireproximityprompt   ADA (4x)     InvokeServer   NOL\n  InputHoldBegin/End    ADA (2x)     FireServer     NOL\n  OnClientEvent         NOL\n\nSatu kesimpulan yang BERTAHAN: dia TIDAK memanggil remote sama\nsekali - untuk fitur APA PUN. Yang dia lakukan: menembak prompt\nmilik GAME, lalu controller game sendiri yang memanggil remote-\nnya. Itu sebabnya dia tidak perlu tahu satu pun nama remote.\n\nDUA KESIMPULAN SAYA YANG TERNYATA SALAH - dikoreksi oleh\npengamatan langsung, dan ini pelajarannya:\n\n  * Saya sempat menyimpulkan 'dia tidak teleport' karena tidak\n    menemukan CFrame di jalur kasirnya. SALAH. Ternyata dia\n    memang teleport ke kasir dulu baru menekan E. Pencarian teks\n    di file yang di-obfuscate TIDAK BISA dijadikan bukti negatif:\n    properti bisa diambil lewat nama yang disamarkan.\n\n  * Saya juga sempat menyimpulkan MaxActivationDistance tidak\n    perlu disentuh karena dia tidak menyentuhnya. SALAH juga,\n    dengan sebab yang sama.\n\nAturan yang saya pakai sekarang: 'tidak ketemu di file' bukan\nbukti 'tidak ada'. Yang jadi bukti cuma pengukuran di game.")
end

-- ============================================================
-- CLEANUP / CLOSE (matikan & bersihkan SEMUA fitur)
-- ============================================================
local function cleanupAll()
    for name in pairs(loops) do loops[name] = nil end
    -- WAJIB. Pendengar _Arrangements.ChildRemoved TIDAK lewat track(),
    -- jadi dia tidak ikut terputus oleh baris scriptConnections di bawah.
    -- Tanpa baris ini, menutup hub meninggalkan pemicu yang tetap hidup:
    -- tiap pembeli mengambil rangkaian, rak masih diisi ulang - padahal
    -- panelnya sudah tidak ada dan kamu tidak punya cara mematikannya
    -- selain rejoin.
    pcall(AUTO.pantauObjek, false)
    AUTO.pantau(false)
    MV.stopFly(); MV.stopNoclip(); MV.stopSpeed()
    MV.stopUnlockZoom(); MV.stopHoldMouse(); MV.removeTpTool()
    MV.unstickMouse()   -- jangan tinggalkan mouse terkunci saat GUI ditutup
    clearCropEsp()
    for _, c in ipairs(scriptConnections) do
        pcall(function() if c and c.Connected then c:Disconnect() end end)
    end
    scriptConnections = {}
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = config.defaultWalk end
end

CloseBtn.MouseButton1Click:Connect(function()
    confirmDialog("Tutup FLOWER HUB PH?\nSemua fitur otomatis akan dimatikan.", function()
        cleanupAll()
        local t = TweenService:Create(MainScale, tweenFast, {Scale = 0})
        t:Play()
        t.Completed:Connect(function() ScreenGui:Destroy() end)
    end)
end)

-- ============================================================
-- RE-APPLY saat RESPAWN: fitur aktif menempel lagi ke karakter baru
-- ============================================================
track(LocalPlayer.CharacterAdded:Connect(function(char)
    char:WaitForChild("HumanoidRootPart", 10)
    task.wait(0.6)
    bindCharacter(char)
    if state.fly then MV.stopFly(); MV.startFly() end
    MV.stopNoclip(); MV.reconcileNoclip()          -- pasang ulang ke part BARU
    if state.speed then MV.stopSpeed(); MV.startSpeed() end
    if state.clickTp then MV.giveTpTool() end      -- Tool ikut hilang saat respawn
    MV.applyJumpPower()
    addLog("Respawn: fitur aktif dipasang ulang", "INFO")
end))

-- ============================================================
-- STARTUP
-- ============================================================
TweenService:Create(MainScale, tweenBounce, {Scale = config.guiScale}):Play()

task.spawn(function()
    task.wait(0.5)
    grabReplica()
    local plot = getMyPlot()
    if not KnitServices then
        notify("! Knit Services tidak ketemu!", THEME.Red)
    elseif not plot then
        notify("! Plot kamu belum ketemu — klaim plot dulu", THEME.Yellow)
    else
        local nP, _, ready = farmSummary()
        notify("FLOWER HUB PH " .. HUB_BUILD .. " siap! " .. nP ..
               " planter, " .. ready .. " siap panen", THEME.On)
    end

    -- ============================================================
    -- TIDAK ADA SAKELAR YANG DINYALAKAN SENDIRI SAAT EXECUTE
    -- ============================================================
    -- Dulu di sini ada `AUTO.set.combo(true)` yang menyalakan AUTO
    -- RANGKAI -> RAK begitu hub dijalankan. Itu memang pernah diminta
    -- ("auto on semua buttonnya defaultnya"), tapi sekarang DIBATALKAN
    -- atas permintaan - dan memang lebih benar begitu.
    --
    -- Alasannya bukan cuma selera: sakelar yang menyala tanpa ditekan
    -- membuat SELURUH panel sulit dipercaya. Kamu tidak bisa lagi
    -- membedakan "ini menyala karena saya yang menyalakan" dari "ini
    -- menyala sendiri", dan begitu satu sakelar boleh begitu, tiap
    -- sakelar lain jadi patut dicurigai.
    --
    -- Jadi sekarang: SEMUA sakelar auto mulai dari OFF. Kalau mau
    -- menyalakan banyak sekaligus, tombol MODE UANG MAKSIMUM di tab
    -- Auto masih ada - dan itu satu tekanan yang KAMU lakukan.
end)

