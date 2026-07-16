-- Auctionator 1.12.1 backport compatibility shim.
-- Must load before every other Lua file in the addon.
--
-- Assumes the ClassicAPI DLL is present (provides C_Item.*, C_Container.*,
-- C_Timer.*, hooksecurefunc, GetItemIcon, UnitGUID, table.wipe, etc.).
--
-- WoW 1.12.1's Lua 5.0 has no vararg syntax (the `...` token is rejected by
-- the parser) and no `#` length operator. All polyfills below use positional
-- arguments only. `#tbl` is replaced project-wide with `table.getn(tbl)`
-- in the source files, not patched here.
--
-- Design rule: this file only adds NEW names (Atr_*, AuctionatorPrivate,
-- polyfills for missing globals). It does NOT override existing Blizzard
-- API functions — call sites in the addon are updated to use the helpers
-- below instead.

-- Shared addon-table the 3.0+ loader would have passed in via the per-file
-- vararg. Every Atr_* file uses `local addonTable = AuctionatorPrivate` in
-- place of the per-file `...` shim.
AuctionatorPrivate = AuctionatorPrivate or {}

-- strsplit(): added by Blizzard in 2.x. Returns up to 8 substrings.
if not strsplit then
	function strsplit(sep, str)
		if str == nil then return end
		local result = {}
		local pattern = "([^" .. sep .. "]+)"
		for word in string.gfind(str, pattern) do
			table.insert(result, word)
		end
		return result[1], result[2], result[3], result[4],
		       result[5], result[6], result[7], result[8]
	end
end

-- bit library polyfill (zcUtils uses bit.band / bit.rshift for UTF-8 decode).
if not bit then
	bit = {}
	function bit.band(a, b)
		local r, p = 0, 1
		while a > 0 and b > 0 do
			local x, y = math.mod(a, 2), math.mod(b, 2)
			if x == 1 and y == 1 then r = r + p end
			a = (a - x) / 2
			b = (b - y) / 2
			p = p * 2
		end
		return r
	end
	function bit.bor(a, b)
		local r, p = 0, 1
		while a > 0 or b > 0 do
			local x, y = math.mod(a, 2), math.mod(b, 2)
			if x == 1 or y == 1 then r = r + p end
			a = (a - x) / 2
			b = (b - y) / 2
			p = p * 2
		end
		return r
	end
	function bit.rshift(a, n) return math.floor(a / (2 ^ n)) end
	function bit.lshift(a, n) return a * (2 ^ n) end
end

-- hooksecurefunc: ClassicAPI provides this. Defensive positional fallback.
if not hooksecurefunc then
	function hooksecurefunc(arg1, arg2, arg3)
		local tbl, name, fn
		if type(arg1) == "string" then
			tbl, name, fn = getfenv(0), arg1, arg2
		else
			tbl, name, fn = arg1, arg2, arg3
		end
		local orig = tbl[name]
		tbl[name] = function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
			orig(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
			fn(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
		end
	end
end

-- table.wipe: ClassicAPI provides; defensive fallback.
if not table.wipe then
	function table.wipe(t)
		for k in pairs(t) do t[k] = nil end
		return t
	end
end

-- Atr_SelectionHighlight: in 1.12 the Lock/UnlockHighlight pair doesn't
-- always refresh the highlight texture correctly when toggled programmatically
-- (previously-clicked rows remain visually "stuck"). Sidestep the engine's
-- highlight machinery by stamping a custom overlay texture on the button
-- which we Show/Hide explicitly. The Blizzard HighlightTexture stays intact
-- so the mouseover effect continues to work.
function Atr_SelectionHighlight(btn, isSelected)
	if (not btn) then return end
	if (not btn.atr_selTex) then
		local tex = btn:CreateTexture(nil, "OVERLAY")
		tex:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
		tex:SetTexCoord(0.035, 0.04, 0.2, 0.25)
		tex:SetBlendMode("ADD")
		tex:SetAllPoints(btn)
		tex:Hide()
		btn.atr_selTex = tex
	end
	if (isSelected) then
		btn.atr_selTex:Show()
		btn.atr_selTex:SetAlpha(1)
	else
		btn.atr_selTex:Hide()
		btn.atr_selTex:SetAlpha(0)
	end
	-- Temporary debug
	if (DEFAULT_CHAT_FRAME and Atr_DebugHL) then
		DEFAULT_CHAT_FRAME:AddMessage("SelHL " .. (btn:GetName() or "?") .. " id=" .. tostring(btn:GetID()) .. " sel=" .. tostring(isSelected))
	end
end

-- IsInIMECompositionMode: 2.x+ EditBox method. 1.12 frames use a __index
-- function (not a table) so the method can't be patched onto the metatable.
-- The three call sites (Auctionator.lua:4183/:4204, Auctionator.xml:408) have
-- been simplified instead to drop the IME branch entirely — there is no IME
-- pipeline in 1.12.

-- SortAuctionClearSort: 2.x+ AH "clear-the-sort" call. Vanilla only has
-- SortAuctionItems(type, sort), which APPLIES a named sort and toggles
-- direction on repeat calls — no true clear API exists. Auctionator uses
-- SortAuctionClearSort right before issuing a scan query to ensure the
-- result list arrives in a predictable order. Mapping to SortAuctionItems
-- with a stable default ("quality") gives the same downstream guarantee:
-- the scan loop sees results in a consistent order.
if not SortAuctionClearSort then
	function SortAuctionClearSort(listType)
		if SortAuctionItems then
			SortAuctionItems(listType, "quality")
		end
	end
end

-- ---------------------------------------------------------------------------
-- Addon-private helpers. Auctionator call sites use these instead of the
-- vanilla globals when the shape needs to differ from what 1.12 provides.
-- ---------------------------------------------------------------------------

-- Atr_GetItemInfo: returns the Wrath 11-tuple shape Auctionator was written
-- against, by augmenting vanilla's 7-tuple with ClassicAPI lookups.
--
--   vanilla 1.12:  name, link, rarity, minLevel, type, subtype, stack
--   Wrath/3.3.5:   name, link, rarity, ilvl, minLevel, type, subtype, stack,
--                  equipLoc, texture, sellPrice
--
-- ilvl is left nil (vanilla has no per-instance scaling); equipLoc/texture
-- come from C_Item.GetItemInfoInstant; sellPrice from
-- C_Item.GetItemSellPriceByID. Callers that only need fields 1-3 can keep
-- using the vanilla `GetItemInfo` directly.
do
	local C_Item_GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
	local C_Item_GetItemSellPriceByID = C_Item and C_Item.GetItemSellPriceByID

	function Atr_GetItemInfo(item)
		if item == nil then return nil end

		-- This client's GetItemInfo resolves by numeric itemID or name, NOT by
		-- hyperlink -- GetItemInfo(link) returns nil here. (Blizzard's own
		-- ContainerFrame.lua extracts the id from the link before calling it.)
		-- If handed a link/itemString, pull the itemID out so the lookup works.
		-- Lua 5.0 has no string.match; use string.find with a capture.
		local query = item
		if type(item) == "string" then
			local _, _, id = string.find(item, "item:(%d+)")
			if id then
				query = tonumber(id)
			end
		end

		local name, link, rarity, minLevel, itype, isubtype, stack = GetItemInfo(query)
		if not name then return nil end

		local equipLoc, texture, sellPrice
		local key = link or item
		if C_Item_GetItemInfoInstant then
			local _, _, _, _equip, _icon = C_Item_GetItemInfoInstant(key)
			equipLoc, texture = _equip, _icon
		end
		if C_Item_GetItemSellPriceByID then
			sellPrice = C_Item_GetItemSellPriceByID(key)
		end
		return name, link, rarity, nil, minLevel, itype, isubtype, stack, equipLoc, texture, sellPrice
	end
end

-- MoneyInputFrame_SetOnValueChangedFunc: added in 2.x. This Octo 1.12 client
-- already has the same mechanism natively, only spelled with a lowercase 'v':
-- MoneyInputFrame_SetOnvalueChangedFunc stores frame.onvalueChangedFunc, and the
-- template's OnTextChanged fires it -- honouring the expectChanges guard that
-- suppresses programmatic SetCopper changes (avoids feedback loops). So just
-- expose the native impl under the name Auctionator calls; do NOT hand-roll a
-- replacement that would re-fire on every programmatic change.
--
-- Auctionator uses this to wire Atr_StackPriceChangedFunc / Atr_ItemPriceChangedFunc,
-- which fill the hidden Starting Price. Without it, `start` stays 0 and the Create
-- Auction button never satisfies pricesOK, so it never lights up.
if not MoneyInputFrame_SetOnValueChangedFunc then
	if type(MoneyInputFrame_SetOnvalueChangedFunc) == "function" then
		MoneyInputFrame_SetOnValueChangedFunc = MoneyInputFrame_SetOnvalueChangedFunc
	else
		-- Fallback for clients lacking any native callback: post-hook the
		-- Gold/Silver/Copper sub-EditBox OnTextChanged scripts.
		local SUFFIXES = {"Gold", "Silver", "Copper"}
		function MoneyInputFrame_SetOnValueChangedFunc(frame, func)
			if not frame or not func then return end
			frame.onValueChangedFunc = func
			local fname = frame:GetName()
			if not fname then return end
			local i
			for i = 1, 3 do
				local box = getglobal(fname .. SUFFIXES[i])
				if box and box.GetScript then
					local orig = box:GetScript("OnTextChanged")
					box:SetScript("OnTextChanged", function()
						if orig then orig() end
						if frame.onValueChangedFunc then frame.onValueChangedFunc() end
					end)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Standalone Auctionator options window (InterfaceOptions* polyfill).
--
-- 3.0 introduced InterfaceOptions_AddCategory / InterfaceOptionsFrame; vanilla
-- has neither. Auctionator registers 6 sub-panels via InterfaceOptions and
-- opens them with InterfaceOptionsFrame_OpenToCategory("Auctionator"). We
-- replicate that flow with a small tabbed window: panels are pushed into a
-- registry at OnLoad time, and the first OpenToCategory call lazily builds
-- the window and reparents the active panel into its content area.
-- ---------------------------------------------------------------------------

local Atr_OptCategories = {}   -- list of registered panels in registration order
local Atr_OptWindow            -- standalone window, built lazily
local Atr_OptionsBuild, Atr_OptionsSelect, Atr_OptionsAddTab   -- forward decls

function Atr_OptionsSelect(panel)
	if not panel or not Atr_OptWindow then return end
	if Atr_OptWindow.activePanel == panel then return end

	if Atr_OptWindow.activePanel then
		Atr_OptWindow.activePanel:Hide()
	end

	-- Reparent so the panel and its children share our window's frame strata
	-- via inheritance (explicit SetFrameStrata on the panel does NOT propagate
	-- to existing children in 1.12 — they stay at their creation strata).
	--
	-- Hide before reparenting and re-anchor + Show afterwards to force WoW
	-- to rebuild the hit-test tree at the new screen position. Without the
	-- Hide/Show cycle, 1.12 leaves the children's mouse hit regions at
	-- their original UIParent-relative coordinates and the checkboxes
	-- become un-clickable (visible but inert).
	panel:Hide()
	panel:SetParent(Atr_OptWindow.content)
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", Atr_OptWindow.content, "TOPLEFT", 0, 0)
	panel:SetPoint("BOTTOMRIGHT", Atr_OptWindow.content, "BOTTOMRIGHT", 0, 0)
	panel:Show()

	Atr_OptWindow.activePanel = panel
end

function Atr_OptionsAddTab(panel)
	if not Atr_OptWindow then return end
	local n = table.getn(Atr_OptWindow.tabs) + 1
	local btn = CreateFrame("Button", nil, Atr_OptWindow.tabHost, "UIPanelButtonTemplate")
	btn:SetWidth(160)
	btn:SetHeight(22)
	-- 1.12 SetPoint doesn't accept the (point, offsetX, offsetY) shortcut; need
	-- the full (point, region, relativePoint, offsetX, offsetY) form.
	btn:SetPoint("TOPLEFT", Atr_OptWindow.tabHost, "TOPLEFT", 0, -((n - 1) * 24))
	btn:SetText(panel.name or panel:GetName() or "?")
	btn:SetScript("OnClick", function() Atr_OptionsSelect(panel) end)
	table.insert(Atr_OptWindow.tabs, btn)
end

function Atr_OptionsBuild()
	if Atr_OptWindow then return Atr_OptWindow end

	local f = CreateFrame("Frame", "Atr_StandaloneOptions", UIParent)
	f:SetWidth(820)
	f:SetHeight(560)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("HIGH")
	-- Don't EnableMouse / SetMovable on the outer window — capturing mouse on
	-- the outer frame interferes with child checkboxes/dropdowns receiving
	-- their own clicks in 1.12. The window stays centered (non-draggable).
	f:SetBackdrop({
		bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = {left = 11, right = 12, top = 12, bottom = 11},
	})

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", f, "TOP", 0, -14)
	title:SetText("Auctionator Options")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

	f.tabHost = CreateFrame("Frame", nil, f)
	f.tabHost:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -42)
	f.tabHost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
	f.tabHost:SetWidth(160)

	f.content = CreateFrame("Frame", nil, f)
	f.content:SetPoint("TOPLEFT", f, "TOPLEFT", 180, -42)
	f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)

	f.tabs = {}
	f.activePanel = nil
	f:Hide()
	Atr_OptWindow = f

	-- Build tabs for every panel registered before the window came up.
	for i = 1, table.getn(Atr_OptCategories) do
		Atr_OptionsAddTab(Atr_OptCategories[i])
	end

	return f
end

if not InterfaceOptions_AddCategory then
	function InterfaceOptions_AddCategory(panel)
		if not panel then return end
		-- Skip the top-level "Auctionator" redirect frame — it isn't a real
		-- options panel, only existed to nest the rest under in 3.x.
		if panel.name == "Auctionator" and not panel.parent then
			return
		end
		table.insert(Atr_OptCategories, panel)
		panel:Hide()
		if Atr_OptWindow then
			Atr_OptionsAddTab(panel)
		end
	end
end

if not InterfaceOptionsFrame_OpenToCategory then
	function InterfaceOptionsFrame_OpenToCategory(target)
		local f = Atr_OptionsBuild()
		f:Show()
		local panel
		if type(target) == "table" then
			panel = target
		elseif type(target) == "string" then
			for i = 1, table.getn(Atr_OptCategories) do
				if Atr_OptCategories[i]:GetName() == target
				   or Atr_OptCategories[i].name == target then
					panel = Atr_OptCategories[i]
					break
				end
			end
		end
		Atr_OptionsSelect(panel or Atr_OptCategories[1])
	end
end

-- Stub the legacy globals other code may probe (none of the existing call
-- sites actually rely on real behaviour — Atr_MakeOptionsFrameOpaque is
-- commented out, and the mask helpers check for nil before showing).
if not InterfaceOptionsFrame then
	InterfaceOptionsFrame = CreateFrame("Frame", "InterfaceOptionsFrame", UIParent)
	InterfaceOptionsFrame:Hide()
end
if not InterfaceOptionsFrameAddOns then
	InterfaceOptionsFrameAddOns = CreateFrame("Frame", "InterfaceOptionsFrameAddOns", InterfaceOptionsFrame)
end
if not InterfaceOptionsFrameCategories then
	InterfaceOptionsFrameCategories = CreateFrame("Frame", "InterfaceOptionsFrameCategories", InterfaceOptionsFrame)
end

-- MoneyTypeInfo.AUCTION: Wrath/3.x ships an "AUCTION" entry in MoneyTypeInfo
-- that Auctionator's money frames use via MoneyFrame_SetType. Vanilla only
-- has "PLAYER" and "STATIC". Defined as a STATIC clone so MoneyFrame_Update
-- displays whatever value the addon explicitly writes via MoneyFrame_Update.
if MoneyTypeInfo and not MoneyTypeInfo["AUCTION"] then
	MoneyTypeInfo["AUCTION"] = {
		UpdateFunc = function() return this.staticMoney; end,
		collapse = 1,
		showSmallerCoins = "Backpack",
	}
end

-- Other backport notes (no helper needed, just call-site edits in the addon):
--  * GetItemIcon — ClassicAPI ships this natively in 1.12.
--  * OpenAllBags(frame) — Auctionator.lua:918 was changed to OpenAllBags()
--    (vanilla takes no arg; passing a truthy value is unsafe).
--  * CanSendAuctionQuery — vanilla returns one boolean (no getAll/canQueryAll
--    2nd value). The full scan is page-based, so its call sites in
--    AuctionatorScan.lua gate on this single boolean; do NOT gate the full-scan
--    UI on a 2nd (canQueryAll) value -- it is always nil here and would leave
--    the Start Scanning button permanently disabled.
--  * MoneyFrame_SetType — vanilla is 1-arg (uses `this`); Auctionator.lua:3265
--    was changed accordingly.
--  * XML scripts in 1.12 expose `this` and `arg1..argN` as globals; `self`
--    and named args (`elapsed`) don't exist. self->this and elapsed->arg1
--    rewrites done in the .xml files.
