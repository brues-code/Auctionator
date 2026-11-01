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

-- UIDropDownMenu_CreateInfo: added in 2.x. 1.12 has no such helper -- you build
-- the info table by hand and pass it to UIDropDownMenu_AddButton (which reads
-- .text/.value/.func/.checked/.owner). Return a fresh table each call.
if not UIDropDownMenu_CreateInfo then
	function UIDropDownMenu_CreateInfo()
		return {}
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

	-- On this 1.12 client a clicked row's PushedTexture stays visibly stuck
	-- after the click -- the button state returns to NORMAL but the texture is
	-- never hidden -- so every row you click keeps a gold press overlay and they
	-- pile up. That texture is not our selection visual (we draw our own overlay
	-- below), so force it (and any locked highlight) off on every redraw.
	local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
	if (pushed) then pushed:Hide() end
	if (btn.UnlockHighlight) then btn:UnlockHighlight() end

	if (not btn.atr_selTex) then
		local tex = btn:CreateTexture(nil, "OVERLAY")
		tex:SetBlendMode("ADD")
		tex:SetAllPoints(btn)
		btn.atr_selTex = tex
	end
	if (isSelected) then
		btn.atr_selTex:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
		btn.atr_selTex:SetTexCoord(0.035, 0.04, 0.2, 0.25)
		btn.atr_selTex:Show()
	else
		-- On this 1.12 client, Hide()/SetAlpha(0) do NOT reliably clear an
		-- ADD-blend overlay -- deselected rows stayed visibly highlighted and
		-- accumulated. Clearing the texture image itself guarantees nothing is
		-- drawn regardless of the region's shown/alpha state.
		btn.atr_selTex:SetTexture(nil)
		btn.atr_selTex:Hide()
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

-- Atr_GetItemInfo: returns the Wrath-shaped tuple Auctionator was written
-- against. C_Item.GetItemInfo (ClassicAPI) returns the full modern 18-tuple
-- directly and its first 11 fields line up exactly with what every caller
-- expects:
--
--   1 name  2 link  3 rarity  4 itemLevel  5 minLevel  6 type  7 subtype
--   8 stack  9 equipLoc  10 texture  11 sellPrice  (12-18: classID, ...)
--
-- The old shim left itemLevel (slot 4) nil, which made disenchant pricing --
-- Atr_CalcDisenchantPrice(type, rarity, itemLevel) -> `itemLevel >= n` --
-- error on equipped gear. C_Item.GetItemInfo fills it in.
do
	local C_Item_GetItemInfo = C_Item and C_Item.GetItemInfo

	function Atr_GetItemInfo(item)
		if item == nil then return nil end

		if C_Item_GetItemInfo then
			-- C_Item.GetItemInfo resolves a numeric itemID, an "item:NNN" string,
			-- or a full chat link -- but NOT a bare item *name*. The vanilla global
			-- does accept names, so use it to turn a name into a link first.
			local query = item
			if type(item) == "string" and not tonumber(item)
				and not string.find(item, "item:%d+") then
				local _, link = GetItemInfo(item)
				if link then query = link end
			end
			return C_Item_GetItemInfo(query)
		end

		-- Fallback for a client without ClassicAPI: vanilla's short tuple, padded
		-- with a nil itemLevel (slot 4) to keep the modern slot ordering.
		local name, link, rarity, minLevel, itype, isubtype, stack = GetItemInfo(item)
		if not name then return nil end
		return name, link, rarity, nil, minLevel, itype, isubtype, stack
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

-- MoneyTypeInfo.AUCTION: 1.12.1 already ships this natively (UpdateFunc returns
-- this.staticMoney, same as STATIC), so this block is a no-op fallback for any
-- client that lacks it. NOTE: the native UpdateFunc returns this.staticMoney and
-- MoneyFrame_UpdateMoney does NOT nil-check, so callers must seed frame.staticMoney
-- (e.g. = 0) before MoneyFrame_SetType("AUCTION"), else MoneyFrame_Update does
-- floor(nil/..) and errors (see AuctionatorMoneyFrame_OnLoad).
if MoneyTypeInfo and not MoneyTypeInfo["AUCTION"] then
	MoneyTypeInfo["AUCTION"] = {
		UpdateFunc = function() return this.staticMoney or 0; end,
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
