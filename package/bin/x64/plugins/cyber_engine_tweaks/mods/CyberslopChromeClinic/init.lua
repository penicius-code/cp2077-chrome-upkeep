-- Cyberslop Chrome Clinic 1.2.2 (2026-11-26; 1.2.1 2026-11-25; 1.1.3 2026-11-23; 1.1.0 - 1.1.2 2026-11-22)
-- 1.2.2: canisters carried come from ChromeWear:NanoCount() (Chrome Upkeep 1.8.2); wear.nanobots read nil on CET 1.38.1.
-- 1.2.1: needs Chrome Upkeep 1.8.1: a row's time is that system's own work, the visit's setup comes on top once
--   (in the totals and in the row's tooltip); components from the bag can be of other qualities.
-- 1.2.0: needs Chrome Upkeep 1.8.0 (nanobots reworked): canister price and carry limit come from the script, a
--   dose shows its duration and whether one canister is enough.
-- 1.1.3: "Hide at this ripper" compares with the ripper name from the light poll (was the full poll's, which stops
--   while the window is hidden, so a dismissal also hid the window at every other ripper); leaving a ripper no
--   longer collapses the window while it is pinned or the overlay is open.
-- 1.1.0: needs Chrome Upkeep 1.6.0. The ripper uses the components in your bag first and only charges for the
--   missing ones: each row shows what comes from the bag, the totals come from the same worst-first plan the
--   repair pays (bag and money shared between systems).
-- The CET window for Cyberslop Chrome Upkeep 1.6.0 (all rules and prices live in its redscript, this only shows
-- and asks): chrome condition per body system, what a ripper charges to bring each back to 100 % (materials at
-- market price + the ripper's fee after Street Cred and Viktor's friend rate), repair at the ripper, nanobot
-- canisters (buy at a ripper, inject anywhere: up to 60 points of repair per canister, systems up to 60 %).
--   Next to a ripperdoc (4 m, or the one whose menu you opened, 6 m): the window opens by itself.
--   With the CET overlay open: the window is always there, with buttons (two clicks for anything that costs).
--   Without the overlay the window only shows; the hotkeys act (press twice within 5 s to confirm).
--   A running nanobot dose shows a small progress window.
-- Hotkeys (CET > Bindings, unbound): show / hide, repair all at the ripper, buy one canister, start a nanobot dose.
-- 1.1.1 (2026-11-22): clinic focus removed (its restore expanded every collapsed CET window); Armor Clinic sits
--   below this window.
-- 1.1.2 (2026-11-22): CET Decluttered: the window expands (and comes on screen if Decluttered hides it) when
--   you reach a ripperdoc, and collapses again (back into Decluttered's hidden spot) when you leave.

local CC = {
  version = "1.2.2",
  overlay = false,
  pinned = false,       -- hotkey "show / hide": window stays up without a ripper
  dismissed = nil,      -- ripper name the window was closed for (opens again at another ripper)
  d = nil,
  near = false,
  nanoActive = false,
  nextPoll = 0,
  nextFull = 0,
  msg = nil,
  msgUntil = 0,
  confirm = nil,
  confirmUntil = 0,
  hkArm = nil,
  hkUntil = 0,
}

local NAMES = { "frontal cortex", "operating system", "optics", "circulatory", "nervous system",
                "subdermal / skin", "immune system", "skeleton", "arms", "hands", "legs" }

local RED = { 1.0, 0.35, 0.3, 1.0 }
local AMBER = { 1.0, 0.75, 0.3, 1.0 }
local GREEN = { 0.5, 0.95, 0.6, 1.0 }
local GREY = { 0.65, 0.65, 0.65, 1.0 }
local CYAN = { 0.45, 0.85, 1.0, 1.0 }

local function sys(name)
  local ok, s = pcall(function() return Game.GetScriptableSystemsContainer():Get(name) end)
  if ok and s then return s end
  return nil
end

local function clinicSys() return sys("CyberslopChromeUpkeep.ChromeClinic") end
local function wearSys() return sys("CyberslopChromeUpkeep.ChromeWear") end

local function num(v)
  local s = tostring(math.floor((v or 0) + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""):gsub("^%-,", "-"))
end

local function clock(min)
  min = math.floor((min or 0) + 0.5)
  if min < 60 then return min .. " min" end
  return string.format("%dh%02d", math.floor(min / 60), min % 60)
end

local function hud(text)
  pcall(function()
    local m = SimpleScreenMessage.new()
    m.message = text
    m.duration = 6.0
    m.isShown = true
    local defs = Game.GetAllBlackboardDefs()
    Game.GetBlackboardSystem():Get(defs.UI_Notifications):SetVariant(defs.UI_Notifications.WarningMessage, ToVariant(m), true)
  end)
end

local function say(text)
  CC.msg = text
  CC.msgUntil = os.clock() + 20
end

local function colored(c, text)
  ImGui.TextColored(c[1], c[2], c[3], c[4], text)
end

-- Light poll (every second, window or not): is a ripper in reach, is a dose running.
local function pollLight()
  local clinic, wear = clinicSys(), wearSys()
  if not clinic or not wear or not Game.GetPlayer() then
    CC.near, CC.nanoActive = false, false
    return false
  end
  pcall(function()
    CC.near = clinic:DeskUpdate() and true or false
    CC.name = CC.near and clinic:DeskName() or nil   -- 1.1.3: kept fresh while the window is hidden
    wear:NanoUpdate()
    CC.nanoActive = wear:NanoActive() and true or false
  end)
  return true
end

-- Full poll (only while the window shows): quotes, nanobot plan. Strings are built here, not per frame.
local function pollFull()
  local clinic, wear = clinicSys(), wearSys()
  if not clinic or not wear or not Game.GetPlayer() then CC.d = nil return end
  local d = { rows = {}, total = 0, afford = 0, minutes = 0, worst = 101 }
  pcall(function()
    d.near = clinic:DeskNear()
    if d.near then
      d.name = clinic:DeskName()
      d.tierName = clinic:DeskTierName()
      d.friend = clinic:DeskFriend()
    end
    d.money = clinic:Money()
    d.cred = clinic:StreetCred()
    d.combat = clinic:InCombat()
    -- 1.2.2: getter (Chrome Upkeep 1.8.2); the raw field reads nil on CET 1.38.1.
    local okN, n = pcall(function() return wear:NanoCount() end)
    if not okN or n == nil then okN, n = pcall(function() return wear.nanobots end) end
    d.nano = (okN and n) or 0
    d.nanoActive = wear:NanoActive()
    d.nanoMin = wear:NanoMinutesLeft()
    d.nanoPrice = clinic:NanoPrice()
    d.nanoCarry = clinic:NanoCarry()
    d.setupMin = clinic:SetupMinutes()
    wear:RefreshCounts()
    -- 1.1.0: components in the bag, and whether the ripper uses them (Mod Settings).
    d.useBag = clinic:UsesBag()
    d.bag = clinic:BagText()
  end)
  local budget = d.money or 0
  local rowTotal, rowMinutes, rowAfford = 0, 0, 0
  for a = 0, 10 do
    pcall(function()
      if wear:HasChrome(a) then
        local q = clinic:Quote(a)
        local r = {
          idx = a, name = NAMES[a + 1], cond = wear:Condition(a), tier = wear:Tier(a), n = wear:PieceCount(a),
          total = q.total or 0, mat = q.mat or 0, fee = q.fee or 0, feeList = q.feeList or 0, cut = q.cut or 0,
          minutes = q.minutes or 0, parts = q.partsText or "", base = q.base or 0, nanoLeft = wear:NanoLeftFor(a) or 0,
          ownN = q.ownN or 0, own = q.ownText or "none", buy = q.buyText or "", ownValue = q.ownValue or 0,
          matList = q.matList or 0,
        }
        r.col = r.tier == 2 and RED or (r.tier == 1 and AMBER or GREEN)
        r.state = r.tier == 2 and "FAILING" or (r.tier == 1 and "worn" or "ok")
        r.bar = string.format("%.1f", r.cond)
        r.label = string.format("%-17s %-7s", r.name, r.state)
        if r.total > 0 then
          local mats
          if r.ownN <= 0 then
            mats = r.parts
          elseif r.buy == "none" then
            mats = r.parts .. ", all from your bag"
          else
            mats = r.parts .. "; from your bag " .. r.own
          end
          r.price = string.format("%s eddies  (%s + fee %s)  %s", num(r.total), mats, num(r.fee), clock(r.minutes))
          local matLine
          if r.ownN > 0 then
            matLine = string.format("Components %s: from your bag %s (worth %s), bought %s at market price = %s (all bought %s).",
              r.parts, r.own, num(r.ownValue), r.buy, num(r.mat), num(r.matList))
          else
            matLine = string.format("Materials %s at market price: %s.", num(r.mat), r.parts)
          end
          r.tip = string.format("Parts worth %s (base price, no cred discount), %d %s.\n%s\nFee %s list, -%d for cred%s = %s.%s",
            num(r.base), r.n, r.n == 1 and "implant" or "implants", matLine, num(r.feeList), r.cut,
            d.friend and " and friend rate" or "", num(r.fee),
            r.ownN > 0 and "\nPriced on your whole bag; Repair all shares it, worst system first." or "")
          r.tip = r.tip .. string.format("\nTime %s for this system + %s setup once per visit.", clock(r.minutes), clock(d.setupMin or 10))
          rowTotal = rowTotal + r.total
          rowMinutes = rowMinutes + r.minutes
          if r.total <= budget then
            budget = budget - r.total
            rowAfford = rowAfford + r.total
          end
        else
          r.price = "100: nothing to do"
        end
        if r.nanoLeft > 0.05 then r.price = r.price .. string.format("   nanobots +%.1f to come", r.nanoLeft) end
        if r.cond < d.worst then d.worst = r.cond end
        table.insert(d.rows, r)
      end
    end)
  end
  -- 1.1.0: totals from the plan the repair pays (worst first, bag and money shared); row sums if that fails.
  d.total, d.minutes, d.afford = rowTotal, rowMinutes + (rowMinutes > 0 and (d.setupMin or 10) or 0), rowAfford
  pcall(function()
    local pa = clinic:PlanAll()
    d.total, d.minutes = pa.total or rowTotal, pa.minutes or rowMinutes
    d.allOwnN, d.allOwn, d.allOwnValue = pa.ownN or 0, pa.ownText or "none", pa.ownValue or 0
    if (d.money or 0) >= d.total then
      d.afford = d.total
    else
      local pf = clinic:PlanAfford()
      d.afford = pf.total or rowAfford
    end
  end)
  if not d.nanoActive then
    pcall(function()
      local p = wear:NanoPlan(false)
      d.plan = { systems = p.systems or 0, total = p.total or 0, short = p.short, text = p.text or "",
                 minutes = p.minutes or 0, spent = p.spent,
                 need = p:NeedText(), have = p:HaveText(), take = p:TakeText() }
    end)
  end
  if d.near then
    local disc = {}
    if (d.cred or 0) > 0 then table.insert(disc, string.format("Street Cred %d: fee -%d", d.cred, math.floor(0.6 * math.min(d.cred, 50) / 50 * 100 + 0.5)) .. "%") end
    if d.friend then table.insert(disc, "friend rate -15%") end
    d.head = string.format("%s (%s)", d.name or "Ripperdoc", d.tierName or "clinic")
    d.disc = table.concat(disc, ", ")
  else
    d.head = "No ripperdoc in reach: prices are a pro clinic's estimate"
  end
  d.money_s = num(d.money)
  if d.bag then
    if d.useBag == false then
      d.bagLine = "Components in your bag: " .. d.bag .. "  (not used: Mod Settings > Repairs use your components)"
    else
      d.bagLine = "Components in your bag: " .. d.bag .. (d.bag ~= "none" and "  (the ripper uses these first)" or "")
    end
  end
  CC.d = d
end

-- Actions (all checks and payments happen in the redscript).
local function doRepair(idx)
  local clinic = clinicSys()
  if not clinic then return end
  local ok, res = pcall(function() return clinic:DeskRepair(idx) end)
  say(ok and res or "Repair failed (see CET log)")
  CC.nextFull = 0
end

local function doBuy(n)
  local clinic = clinicSys()
  if not clinic then return end
  local ok, res = pcall(function() return clinic:BuyNanobots(n) end)
  say(ok and res or "Purchase failed (see CET log)")
  CC.nextFull = 0
end

local function doInject()
  local wear = wearSys()
  if not wear then return end
  local ok, res = pcall(function() return wear:InjectNanobots() end)
  say(ok and res or "Injection failed (see CET log)")
  CC.nextFull = 0
end

-- Two clicks for anything that costs: the first arms the button for 4 s.
local function costButton(key, label, confirmLabel, action)
  local armed = CC.confirm == key and os.clock() < CC.confirmUntil
  if armed then
    ImGui.PushStyleColor(ImGuiCol.Button, 0.7, 0.25, 0.15, 1.0)
    local hit = ImGui.SmallButton(confirmLabel .. "##" .. key)
    ImGui.PopStyleColor(1)
    if hit then
      CC.confirm = nil
      action()
    end
  elseif ImGui.SmallButton(label .. "##" .. key) then
    CC.confirm = key
    CC.confirmUntil = os.clock() + 4
  end
end

-- Hotkeys: first press tells what would happen, a second press within 5 s does it.
local function armed(key, preview)
  if CC.hkArm == key and os.clock() < CC.hkUntil then
    CC.hkArm = nil
    return true
  end
  CC.hkArm = key
  CC.hkUntil = os.clock() + 5
  hud(preview .. "  (press again to confirm)")
  return false
end

registerHotkey("CyberslopChromeClinicToggle", "Chrome Clinic: show / hide window", function()
  if CC.pinned then
    CC.pinned = false
    if CC.near and CC.name then CC.dismissed = CC.name end
  else
    CC.pinned = true
    CC.dismissed = nil
    CC.nextFull = 0
  end
end)

registerHotkey("CyberslopChromeClinicRepairAll", "Chrome Clinic: repair everything at the ripper", function()
  pollLight()
  pollFull()
  local d = CC.d
  if not d or not d.near then hud("Chrome Clinic: no ripperdoc in reach.") return end
  if d.total <= 0 then hud("Chrome Clinic: every system is at 100 %.") return end
  local bagNote = (d.allOwnN or 0) > 0 and (", " .. d.allOwn .. " from your bag") or ""
  if armed("repair", string.format("Repair all at %s: %s eddies (you have %s)%s, %s", d.name or "the ripper", num(d.total), d.money_s, bagNote, clock(d.minutes))) then
    doRepair(-1)
    hud(CC.msg or "")
  end
end)

registerHotkey("CyberslopChromeClinicBuy", "Chrome Clinic: buy one nanobot canister", function()
  pollLight()
  pollFull()
  local d = CC.d
  if not d or not d.near then hud("Chrome Clinic: nanobots are sold by ripperdocs.") return end
  if armed("buy", string.format("Buy one nanobot canister: %s eddies (you carry %d, have %s eddies)", num(d.nanoPrice or 10000), d.nano or 0, d.money_s)) then
    doBuy(1)
    hud(CC.msg or "")
  end
end)

registerHotkey("CyberslopChromeClinicInject", "Chrome Clinic: inject nanobots", function()
  pollLight()
  pollFull()
  local d = CC.d
  if not d then return end
  if d.nanoActive then hud(string.format("Nanobots at work: %s left.", clock(d.nanoMin))) return end
  if (d.nano or 0) <= 0 then hud("No nanobot canister. Ripperdocs sell them.") return end
  local p = d.plan
  if not p or p.systems == 0 then hud("Nothing below 60 %: nanobots only bring worn chrome back to 60 %.") return end
  if armed("inject", string.format("Inject nanobots: %s over %s, eats %s components", p.text, clock(p.minutes), p.take)) then
    doInject()
    hud(CC.msg or "")
  end
end)

registerForEvent("onInit", function()
  print("[CyberslopChromeClinic] " .. CC.version .. " loaded")
end)
registerForEvent("onOverlayOpen", function() CC.overlay = true; CC.nextFull = 0 end)
registerForEvent("onOverlayClose", function() CC.overlay = false end)

------------------------------------------------------------------------ 1.1.1 window position
-- 1.1.1: clinic focus (1.1.0) removed: its restore expanded every collapsed CET window. This window only publishes
-- its rect in CC.win every frame; Armor Clinic sits right below it. New layouts: this window starts at 40,40.
CC.win = { x = 0, y = 0, w = 0, h = 0, t = -10 }

local function focusPre() end
local function focusPost() end
local function focusFooter() end

local function focusBeforeBegin()
  ImGui.SetNextWindowPos(40, 40, ImGuiCond.FirstUseEver)
end

local function focusInside()
  local W = CC.win
  local x, y = ImGui.GetWindowPos()
  if type(x) ~= "number" then return end
  local w, h = ImGui.GetWindowSize()
  W.x, W.y, W.w, W.h, W.t = x, y, w or 0, h or 0, os.clock()
end

local function drawRows(d, controls)
  if d.bagLine then colored(GREY, d.bagLine) end
  for _, r in ipairs(d.rows) do
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r.col[1], r.col[2], r.col[3], 0.85)
    local barOk = pcall(ImGui.ProgressBar, r.cond / 100, 110, 0, r.bar)
    ImGui.PopStyleColor(1)
    if not barOk then colored(r.col, r.bar) end
    if ImGui.IsItemHovered() and r.tip then ImGui.SetTooltip(r.tip) end
    ImGui.SameLine()
    colored(r.col, r.label)
    ImGui.SameLine()
    colored(r.total > 0 and (r.total <= (d.money or 0) and GREY or RED) or GREEN, r.price)
    if controls and d.near and r.total > 0 then
      ImGui.SameLine()
      costButton("r" .. r.idx, "Repair", "Pay " .. num(r.total), function() doRepair(r.idx) end)
    end
  end
end

local function drawNano(d, controls)
  ImGui.Separator()
  if d.nanoActive then
    colored(CYAN, string.format("Nanobots at work: %s left (waiting or sleeping counts).", clock(d.nanoMin)))
  end
  ImGui.Text(string.format("Nanobot canisters: %d of %d carried", d.nano or 0, d.nanoCarry or 5))
  if controls and d.near then
    ImGui.SameLine()
    if (d.nano or 0) < (d.nanoCarry or 5) then
      local np = num(d.nanoPrice or 10000)
      costButton("buy1", "Buy 1 (" .. np .. ")", "Pay " .. np, function() doBuy(1) end)
    end
  end
  local p = d.plan
  if not d.nanoActive and p then
    if p.systems == 0 then
      colored(GREY, "  Nothing below 60: nanobots only bring worn chrome back to 60. The rest is ripper work.")
    else
      colored(p.short and AMBER or GREY, "  A dose now: " .. p.text .. (p.total >= 0.5 and ("  (" .. clock(p.minutes) .. ")") or "")
        .. (p.spent and "  one canister is not enough" or ""))
      colored(p.short and AMBER or GREY, string.format("  feeds on %s components (needs %s or the same value in other qualities; in your bag %s)", p.take, p.need, p.have))
      if controls and (d.nano or 0) > 0 and p.total >= 0.5 then
        costButton("inject", "Inject nanobots", "Inject: 1 canister + " .. p.take, doInject)
      end
    end
  end
end

------------------------------------------------------------------------ 1.1.2 ripper fold (CET Decluttered)
-- At a ripperdoc the window opens expanded and on screen, also when it is collapsed or hidden in CET Decluttered
-- (Decluttered hides a window by collapsing it and parking it off-screen, and parks hidden windows again for 90
-- frames after the overlay opens, so the expand is held for 100 frames). Leaving the ripper (or "Hide at this
-- ripper") collapses it again and parks it back where Decluttered had it. Only this mod's own window is touched.
local FOLD = { name = "Cyberslop Chrome Clinic", homeX = 40, homeY = 40,
               near = false, overlay = false, hold = 0, holding = false, parked = nil, last = nil }

local function foldOffScreen(x, y, w)
  local sw, sh = GetDisplayResolution()
  if type(sw) ~= "number" or sw <= 0 then sw, sh = 1920, 1080 end
  return x > sw - 20 or y > sh - 20 or x + (w or 0) < 20 or y < -40
end

-- Every frame, before anything else in onDraw. nearNow = the window is up because of a ripper.
local function foldPre(nearNow, overlay)
  if nearNow and not FOLD.near then
    FOLD.hold = 100
  elseif not nearNow and FOLD.near then
    FOLD.hold = 0
    -- 1.1.3 (bug hunt): a pinned window, or one shown with the overlay, stays open where it is
    if not overlay and not CC.pinned then
      ImGui.SetWindowCollapsed(FOLD.name, true)
      if FOLD.parked then ImGui.SetWindowPos(FOLD.name, FOLD.parked.x, FOLD.parked.y) end
    end
    FOLD.parked = nil
  end
  if nearNow and overlay and not FOLD.overlay then FOLD.hold = 100 end
  FOLD.near, FOLD.overlay = nearNow, overlay
end

local function foldBeforeBegin()
  FOLD.holding = FOLD.hold > 0
  if FOLD.holding then
    FOLD.hold = FOLD.hold - 1
    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Always)
  end
end

-- Inside Begin: while the hold runs, an off-screen (parked) window comes back to its last on-screen spot.
local function foldInside()
  local x, y = ImGui.GetWindowPos()
  if type(x) ~= "number" then return end
  local w = ImGui.GetWindowSize()
  if foldOffScreen(x, y, w) then
    if FOLD.near and FOLD.holding then
      if not FOLD.parked then FOLD.parked = { x = x, y = y } end
      local hx, hy = FOLD.homeX, FOLD.homeY
      if FOLD.last then hx, hy = FOLD.last.x, FOLD.last.y end
      ImGui.SetWindowPos(hx, hy)
    end
  else
    FOLD.last = { x = x, y = y }
  end
end

registerForEvent("onUpdate", function()
  local t = os.clock()
  if t >= CC.nextPoll then
    CC.nextPoll = t + 1.0
    pollLight()
    if CC.near and CC.name and CC.dismissed and CC.dismissed ~= CC.name then CC.dismissed = nil end
  end
end)

registerForEvent("onDraw", function()
  focusPre()
  local showNear = CC.near and not (CC.dismissed and CC.name == CC.dismissed)
  foldPre(showNear, CC.overlay)
  local full = CC.overlay or CC.pinned or showNear
  if not full and not CC.nanoActive then return end
  local t = os.clock()
  if t >= CC.nextFull then
    CC.nextFull = t + 1.0
    pcall(pollFull)
  end
  local d = CC.d
  if not d then return end

  if not full then
    -- Only a dose running: a small progress window.
    if ImGui.Begin("Chrome Clinic##nano", ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoFocusOnAppearing + ImGuiWindowFlags.NoTitleBar) then
      colored(CYAN, string.format("Nanobots at work: %s left", clock(d.nanoMin)))
    end
    ImGui.End()
    return
  end

  focusBeforeBegin()
  foldBeforeBegin()
  if not ImGui.Begin("Cyberslop Chrome Clinic", ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoFocusOnAppearing) then
    ImGui.End()
    return
  end
  foldInside()
  focusInside()
  local controls = CC.overlay
  colored(d.near and GREEN or GREY, d.head)
  if d.near and d.disc ~= "" then
    ImGui.SameLine()
    colored(GREY, "  " .. d.disc)
  end
  ImGui.Text("Eddies: " .. d.money_s .. (d.combat and "   IN COMBAT: no ripper work, nanobots only" or ""))
  ImGui.Separator()
  if #d.rows == 0 then
    colored(GREY, "No chrome installed.")
  else
    drawRows(d, controls)
    if d.total > 0 then
      ImGui.Separator()
      local line = string.format("Everything to 100: %s eddies, %s in the chair", num(d.total), clock(d.minutes))
      if (d.allOwnN or 0) > 0 then line = line .. string.format(", uses %s from your bag (saves %s)", d.allOwn, num(d.allOwnValue)) end
      if d.afford < d.total then line = line .. string.format("  (you can pay %s of it)", num(d.afford)) end
      colored(d.afford >= d.total and GREY or AMBER, line)
      if controls and d.near and d.afford > 0 then
        ImGui.SameLine()
        costButton("all", "Repair all", "Pay " .. num(d.afford), function() doRepair(-1) end)
      end
    end
  end
  drawNano(d, controls)
  if CC.msg and os.clock() < CC.msgUntil then
    ImGui.Separator()
    ImGui.PushTextWrapPos(560)
    colored(CYAN, CC.msg)
    ImGui.PopTextWrapPos()
  end
  if not controls then
    colored(GREY, "CET overlay for the buttons; hotkeys work without it (press twice).")
  elseif CC.near then
    if ImGui.SmallButton("Hide at this ripper") then
      CC.dismissed = CC.name or d.name
      CC.pinned = false
    end
  end
  focusFooter()
  ImGui.End()
  focusPost()
end)

return CC
