
local addonTable = AuctionatorPrivate;
local zc = addonTable.zc;


-----------------------------------------

local auctionator_orig_GameTooltip_OnTooltipAddMoney;

-----------------------------------------

function auctionator_GameTooltip_OnTooltipAddMoney (self, cost, maxcost)

	if (AUCTIONATOR_V_TIPS == 1) then
		return;
	end

	auctionator_orig_GameTooltip_OnTooltipAddMoney (self, cost, maxcost);
end

-----------------------------------------

function Atr_Hook_OnTooltipAddMoney()
	auctionator_orig_GameTooltip_OnTooltipAddMoney = GameTooltip_OnTooltipAddMoney;
	GameTooltip_OnTooltipAddMoney = auctionator_GameTooltip_OnTooltipAddMoney;
end

------------------------------------------------

local function Atr_AppendHint (results, price, text, volume)

	if (price and price > 0) then
		local e = {};
		e.price		= price;
		e.text		= text;
		e.volume	= volume;
		
		table.insert (results, e);
	end

end

------------------------------------------------

function Atr_BuildHints (itemName)

	local results = {};

	local itemLink = Atr_GetItemLink (itemName);

	if (itemLink == nil and itemName == nil) then
		return results;
	end

	-- Auctionator Full Scan
	
	if (itemName ~= nil and gAtr_ScanDB[itemName] ~= nil) then
		Atr_AppendHint (results, gAtr_ScanDB[itemName], ZT("Auctionator scan data"));
	end

	-- most recent historical price
	
	local price = Atr_GetMostRecentSale(itemName);
	if (price ~= nil) then
		Atr_AppendHint (results, price, ZT("your most recent posting"));
	end

	-- Wowecon

	if (Wowecon and Wowecon.API) then
	
		local priceG, volG, priceS, volS;
		
		if (itemLink) then
			priceG, volG = Wowecon.API.GetAuctionPrice_ByLink (itemLink, Wowecon.API.GLOBAL_PRICE)
			priceS, volS = Wowecon.API.GetAuctionPrice_ByLink (itemLink, Wowecon.API.SERVER_PRICE)
		else
			priceG, volG = Wowecon.API.GetAuctionPrice_ByName (itemName, Wowecon.API.GLOBAL_PRICE)
			priceS, volS = Wowecon.API.GetAuctionPrice_ByName (itemName, Wowecon.API.SERVER_PRICE)
		end
		
		Atr_AppendHint (results, priceG, ZT("Wowecon global price"), volG);
		Atr_AppendHint (results, priceS, ZT("Wowecon server price"), volS);
		
	end
	
	if (itemLink) then
	
		-- GoingPrice Wowhead
		
		local id = zc.ItemIDfromLink (itemLink);
		
		id = tonumber(id);

		if (GoingPrice_Wowhead_Data and GoingPrice_Wowhead_Data[id] and GoingPrice_Wowhead_SV._index) then
			local index = GoingPrice_Wowhead_SV._index["Buyout price"];

			if (index ~= nil) then
				local price = GoingPrice_Wowhead_Data[id][index];
			
				Atr_AppendHint (results, price, "GoingPrice - Wowhead");
			end
		end

		-- GoingPrice Allakhazam
		
		if (GoingPrice_Allakhazam_Data and GoingPrice_Allakhazam_Data[id] and GoingPrice_Allakhazam_SV._index) then
			local index = GoingPrice_Allakhazam_SV._index["Median"];

			if (index ~= nil) then
				local price = GoingPrice_Allakhazam_Data[id][index];
			
				Atr_AppendHint (results, price, "GoingPrice - Allakhazam");
			end
		end
	end
	
	return results;

end

-----------------------------------------

function Atr_ShowHints ()

	Atr_Col1_Heading:Hide();
	Atr_Col3_Heading:Hide();
	Atr_Col4_Heading:Hide();

	Atr_Col3_Heading:SetText (ZT("Source"));

	local currentPane = Atr_GetCurrentPane();

	currentPane.hints = Atr_BuildHints (currentPane.activeScan.itemName);
	
	local numrows = currentPane.hints and table.getn(currentPane.hints) or 0;

	if (numrows > 0) then
		Atr_Col1_Heading:Show();
		Atr_Col3_Heading:Show();
	end

	local line;							-- 1 through 12 of our window to scroll
	local dataOffset;					-- an index into our data calculated from the scroll offset

	FauxScrollFrame_Update (AuctionatorScrollFrame, numrows, 12, 16);

	for line = 1,12 do

		dataOffset = line + FauxScrollFrame_GetOffset (AuctionatorScrollFrame);

		local lineEntry = getglobal ("AuctionatorEntry"..line);

		lineEntry:SetID(dataOffset);

		if (dataOffset <= numrows and currentPane.hints[dataOffset]) then

			local data = currentPane.hints[dataOffset];

			local lineEntry_item_tag = "AuctionatorEntry"..line.."_PerItem_Price";

			local lineEntry_item		= getglobal(lineEntry_item_tag);
			local lineEntry_itemtext	= getglobal("AuctionatorEntry"..line.."_PerItem_Text");
			local lineEntry_text		= getglobal("AuctionatorEntry"..line.."_EntryText");
			local lineEntry_stack		= getglobal("AuctionatorEntry"..line.."_StackPrice");

			lineEntry_item:Show();
			lineEntry_itemtext:Hide();
			lineEntry_stack:SetText	("");

			Atr_SetMFcolor (lineEntry_item_tag, true);

			MoneyFrame_Update (lineEntry_item_tag, zc.round(data.price) );

			local text = data.text;
			if (data.volume) then
				text = text.." ("..ZT("trade volume")..": "..data.volume..")";
			end
			
			lineEntry_text:SetText (text);
			lineEntry_text:SetTextColor (0.8, 0.8, 1.0);

			lineEntry:Show();
		else
			lineEntry:Hide();
		end
	end

	Atr_HighlightEntry (currentPane.hintsIndex);
end


-----------------------------------------

-- SetNormalFontObject is 2.x+; 1.12 buttons use SetTextFontObject.
local function Atr_SetButtonFont (btn, font)
	if (btn.SetNormalFontObject) then
		btn:SetNormalFontObject(font);
	elseif (btn.SetTextFontObject) then
		btn:SetTextFontObject(font);
	end
end

function Atr_SetMFcolor (frameName, blue)

	local goldButton = getglobal(frameName.."GoldButton");
	local silverButton = getglobal(frameName.."SilverButton");
	local copperButton = getglobal(frameName.."CopperButton");

	local font = blue and NumberFontNormalRightATRblue or NumberFontNormalRight;

	Atr_SetButtonFont(goldButton, font);
	Atr_SetButtonFont(silverButton, font);
	Atr_SetButtonFont(copperButton, font);

end


-----------------------------------------

function Atr_GetAuctionPrice (item)  -- itemName or itemID

	local itemName;
	
	if (type (item) == "number") then
		itemName = GetItemInfo (item);
	else
		itemName = item;
	end

	if (itemName == nil) then
		return nil;
	end

	if (gAtr_ScanDB[itemName]) then
		return gAtr_ScanDB[itemName];
	end
	
	return Atr_GetMostRecentSale (itemName);
end	

-----------------------------------------

local function Atr_CalcTextWid (price)

	local wid = 15;
	
	if (price > 9)			then wid = wid + 12;	end;
	if (price > 99)			then wid = wid + 44;	end;
	if (price > 999)		then wid = wid + 12;	end;
	if (price > 9999)		then wid = wid + 44;	end;
	if (price > 99999)		then wid = wid + 12;	end;
	if (price > 999999)		then wid = wid + 12;	end;
	if (price > 9999999)	then wid = wid + 12;	end;
	if (price > 99999999)	then wid = wid + 12;	end;
	
	return wid;
end

-----------------------------------------

local function Atr_CalcTTpadding (price1, price2)

	local padding = "";

	if (price1 and price2) then
		local vpwidth = Atr_CalcTextWid (price1);
		local apwidth = Atr_CalcTextWid (price2);

		local padlen = math.floor ((apwidth - vpwidth)/6);
		local k;
		
		for k = 1,padlen do
			padding = padding.." ";
		end
	end

	return padding;

end

-----------------------------------------

local UNCOMMON	= 2;
local RARE		= 3;
local EPIC		= 4;

local WEAPON = 1;
local ARMOR  = 2;

-- All enchanting mat IDs bundled into one local table so that Atr_InitDETable
-- only consumes ONE upvalue slot for them. Lua 5.0 caps upvalues per function
-- at 32, and 24 individual locals + the rest of the helper upvalues pushed it
-- over the limit.
local MAT = {
	LESSER_MAGIC		= 10938,
	GREATER_MAGIC		= 10939,
	STRANGE_DUST		= 10940,

	SMALL_GLIMMERING	= 10978,
	LESSER_ASTRAL		= 10998,

	GREATER_ASTRAL		= 11082,
	SOUL_DUST			= 11083,
	LARGE_GLIMMERING	= 11084,

	LESSER_MYSTIC		= 11134,
	GREATER_MYSTIC		= 11135,
	VISION_DUST			= 11137,
	SMALL_GLOWING		= 11138,
	LARGE_GLOWING		= 11139,

	LESSER_NETHER		= 11174,
	GREATER_NETHER		= 11175,
	DREAM_DUST			= 11176,
	SMALL_RADIANT		= 11177,
	LARGE_RADIANT		= 11178,

	SMALL_BRILLIANT		= 14343,
	LARGE_BRILLIANT		= 14344,

	LESSER_ETERNAL		= 16202,
	GREATER_ETERNAL		= 16203,
	ILLUSION_DUST		= 16204,

	NEXUS_CRYSTAL		= 20725,
};

local engDEnames = {};

engDEnames [MAT.LESSER_MAGIC]		= "Lesser Magic Essence";
engDEnames [MAT.GREATER_MAGIC]		= "Greater Magic Essence";
engDEnames [MAT.STRANGE_DUST]		= "Strange Dust";

engDEnames [MAT.SMALL_GLIMMERING]	= "Small Glimmering Shard";
engDEnames [MAT.LESSER_ASTRAL]		= "Lesser Astral Essence";

engDEnames [MAT.GREATER_ASTRAL]		= "Greater Astral Essence";
engDEnames [MAT.SOUL_DUST]			= "Soul Dust";
engDEnames [MAT.LARGE_GLIMMERING]	= "Large Glimmering Essence";

engDEnames [MAT.LESSER_MYSTIC]		= "Lesser Mystic Essence";
engDEnames [MAT.GREATER_MYSTIC]		= "Greater Mystic Essence";
engDEnames [MAT.VISION_DUST]		= "Vision Dust";
engDEnames [MAT.SMALL_GLOWING]		= "Small Glowing Shard";
engDEnames [MAT.LARGE_GLOWING]		= "Large Glowing Shard";

engDEnames [MAT.LESSER_NETHER]		= "Lesser Nether Essence";
engDEnames [MAT.GREATER_NETHER]		= "Greater Nether Essence";
engDEnames [MAT.DREAM_DUST]			= "Dream Dust";
engDEnames [MAT.SMALL_RADIANT]		= "Small Radiant";
engDEnames [MAT.LARGE_RADIANT]		= "Large Radiant";

engDEnames [MAT.SMALL_BRILLIANT]	= "Small Brilliant Shard";
engDEnames [MAT.LARGE_BRILLIANT]	= "Large Brilliant Shard";

engDEnames [MAT.LESSER_ETERNAL]		= "Lesser Eternal Essence";
engDEnames [MAT.GREATER_ETERNAL]	= "Greater Eternal Essence";
engDEnames [MAT.ILLUSION_DUST]		= "Illusion Dust";

engDEnames [MAT.NEXUS_CRYSTAL]		= "Nexus Crystal";


local dustsAndEssences = {};

tinsert (dustsAndEssences, MAT.LESSER_MAGIC)
tinsert (dustsAndEssences, MAT.GREATER_MAGIC)
tinsert (dustsAndEssences, MAT.STRANGE_DUST)

tinsert (dustsAndEssences, MAT.SMALL_GLIMMERING)
tinsert (dustsAndEssences, MAT.LESSER_ASTRAL)

tinsert (dustsAndEssences, MAT.GREATER_ASTRAL)
tinsert (dustsAndEssences, MAT.SOUL_DUST)
tinsert (dustsAndEssences, MAT.LARGE_GLIMMERING)

tinsert (dustsAndEssences, MAT.LESSER_MYSTIC)
tinsert (dustsAndEssences, MAT.GREATER_MYSTIC)
tinsert (dustsAndEssences, MAT.VISION_DUST)
tinsert (dustsAndEssences, MAT.SMALL_GLOWING)
tinsert (dustsAndEssences, MAT.LARGE_GLOWING)

tinsert (dustsAndEssences, MAT.LESSER_NETHER)
tinsert (dustsAndEssences, MAT.GREATER_NETHER)
tinsert (dustsAndEssences, MAT.DREAM_DUST)
tinsert (dustsAndEssences, MAT.SMALL_RADIANT)
tinsert (dustsAndEssences, MAT.LARGE_RADIANT)

tinsert (dustsAndEssences, MAT.SMALL_BRILLIANT)
tinsert (dustsAndEssences, MAT.LARGE_BRILLIANT)

tinsert (dustsAndEssences, MAT.LESSER_ETERNAL)
tinsert (dustsAndEssences, MAT.GREATER_ETERNAL)
tinsert (dustsAndEssences, MAT.ILLUSION_DUST)

tinsert (dustsAndEssences, MAT.NEXUS_CRYSTAL)

gAtr_dustCacheIndex = 1;
local dustCacheState = 0;

-----------------------------------------

function Atr_GetNextDustIntoCache()		-- make sure all the dusts and essences are in the local cache
										-- only needed after a major patch and a cache wipe
	if (gAtr_dustCacheIndex == 0) then
		return;
	end

	local itemID		= dustsAndEssences[gAtr_dustCacheIndex];
	local itemString	= "item:"..itemID..":0:0:0:0:0:0:0";
	
	local itemName, itemLink = GetItemInfo(itemString);
	
	if (itemLink == nil and dustCacheState == 0) then
		dustCacheState = 1;
		zc.md ("pulling "..itemString.." into the local cache");
		AtrScanningTooltip:SetHyperlink(itemString);
	end

	if (itemLink) then
		--zc.md (itemName.." is already in local cache");
		dustCacheState = 0;
		gAtr_dustCacheIndex = gAtr_dustCacheIndex + 1;
		
		if (gAtr_dustCacheIndex > table.getn(dustsAndEssences)) then
			gAtr_dustCacheIndex = 0;		-- finished
		end
	end
end

-----------------------------------------

local deItemNames = {};

local function Atr_GetDEitemName (itemID)

	if (deItemNames[itemID] == nil) then
		local itemName = GetItemInfo (itemID);
		if (itemName == nil) then
			zc.md ("defaulting to english DE mat name: "..engDEnames [itemID]);
			return engDEnames [itemID];
		end
		
		deItemNames[itemID] = itemName;
	end
	
	return deItemNames[itemID];

end

-----------------------------------------

function Atr_GetAuctionPriceDE (itemID)
	-- The Wrath/TBC convertible-essence rule (lesser * 3 vs greater) doesn't
	-- apply in vanilla — no "greater" form exists for any vanilla essence.
	return Atr_GetAuctionPrice (Atr_GetDEitemName (itemID));
end

-----------------------------------------

local deTable = {};

-----------------------------------------

local function deKey (itemType, itemRarity)
	local s = tostring(itemType).."_"..itemRarity
	return s;
end

-----------------------------------------

local function DEtableInsert(t, info)

	local entry = {};

	local x, i, n;
	
	entry[1]	= info[1];
	entry[2]	= info[2];
	
	n = 3;
	
	for x = 3,table.getn(info),3 do
		local nums = info[x+1];
		if (type(nums) == "number") then
			entry[n]   = info[x];
			entry[n+1] = info[x+1];
			entry[n+2] = info[x+2];
			n = n + 3;
		else
			for i = nums[1],nums[2] do
				entry[n]   = info[x]/(nums[2]-nums[1]+1);
				entry[n+1] = i;
				entry[n+2] = info[x+2];
				n = n + 3;				
			end
		end
	end
	
	table.insert (t, entry);

end


-----------------------------------------

function Atr_InitDETable()		-- based on table at wowwiki.com/Disenchanting_tables


	-- UNCOMMON ARMOR

	deTable[deKey(ARMOR, UNCOMMON)] = {};
	
	local t = deTable[deKey(ARMOR, UNCOMMON)];
	
	
	DEtableInsert (t, {5, 15,		80, {1,2}, MAT.STRANGE_DUST,	20, {1,2}, MAT.LESSER_MAGIC});
	DEtableInsert (t, {16, 20,		75, {2,3}, MAT.STRANGE_DUST,	20, {1,2}, MAT.GREATER_MAGIC,	5, 1, MAT.SMALL_GLIMMERING});
	DEtableInsert (t, {21, 25,		75, {4,6}, MAT.STRANGE_DUST,	15, {1,2}, MAT.LESSER_ASTRAL,	10, 1, MAT.SMALL_GLIMMERING});
	DEtableInsert (t, {26, 30,		75, {1,2}, MAT.SOUL_DUST,		20, {1,2}, MAT.GREATER_ASTRAL,	5, 1, MAT.LARGE_GLIMMERING});
	DEtableInsert (t, {31, 35,		75, {2,5}, MAT.SOUL_DUST,		20, {1,2}, MAT.LESSER_MYSTIC,	5, 1, MAT.SMALL_GLOWING});
	DEtableInsert (t, {36, 40,		75, {1,2}, MAT.VISION_DUST,		20, {1,2}, MAT.GREATER_MYSTIC,	5, 1, MAT.LARGE_GLOWING});
	DEtableInsert (t, {41, 45,		75, {2,5}, MAT.VISION_DUST,		20, {1,2}, MAT.LESSER_NETHER,	5, 1, MAT.SMALL_RADIANT});
	DEtableInsert (t, {46, 50,		75, {1,2}, MAT.DREAM_DUST,		20, {1,2}, MAT.GREATER_NETHER,	5, 1, MAT.LARGE_RADIANT});
	DEtableInsert (t, {51, 55,		75, {2,5}, MAT.DREAM_DUST,		20, {1,2}, MAT.LESSER_ETERNAL,	5, 1, MAT.SMALL_BRILLIANT});
	DEtableInsert (t, {56, 60,		75, {1,2}, MAT.ILLUSION_DUST,	20, {1,2}, MAT.GREATER_ETERNAL,	5, 1, MAT.LARGE_BRILLIANT});
	DEtableInsert (t, {61, 65,		75, {2,5}, MAT.ILLUSION_DUST,	20, {2,3}, MAT.GREATER_ETERNAL,	5, 1, MAT.LARGE_BRILLIANT});


	-- UNCOMMON WEAPONS

	deTable[deKey(WEAPON, UNCOMMON)] = {};
	
	local t = deTable[deKey(WEAPON, UNCOMMON)];

	DEtableInsert (t, {6, 15,		20, {1,2}, MAT.STRANGE_DUST,	80, {1,2}, MAT.LESSER_MAGIC});
	DEtableInsert (t, {16, 20,		20, {2,3}, MAT.STRANGE_DUST,	75, {1,2}, MAT.GREATER_MAGIC,	5, 1, MAT.SMALL_GLIMMERING});
	DEtableInsert (t, {21, 25,		15, {4,6}, MAT.STRANGE_DUST,	75, {1,2}, MAT.LESSER_ASTRAL,	10, 1, MAT.SMALL_GLIMMERING});
	DEtableInsert (t, {26, 30,		20, {1,2}, MAT.SOUL_DUST,		75, {1,2}, MAT.GREATER_ASTRAL,	5, 1, MAT.LARGE_GLIMMERING});
	DEtableInsert (t, {31, 35,		20, {2,5}, MAT.SOUL_DUST,		75, {1,2}, MAT.LESSER_MYSTIC,	5, 1, MAT.SMALL_GLOWING});
	DEtableInsert (t, {36, 40,		20, {1,2}, MAT.VISION_DUST,		75, {1,2}, MAT.GREATER_MYSTIC,	5, 1, MAT.LARGE_GLOWING});
	DEtableInsert (t, {41, 45,		20, {2,5}, MAT.VISION_DUST,		75, {1,2}, MAT.LESSER_NETHER,	5, 1, MAT.SMALL_RADIANT});
	DEtableInsert (t, {46, 50,		20, {1,2}, MAT.DREAM_DUST,		75, {1,2}, MAT.GREATER_NETHER,	5, 1, MAT.LARGE_RADIANT});
	DEtableInsert (t, {51, 55,		22, {2,5}, MAT.DREAM_DUST,		75, {1,2}, MAT.LESSER_ETERNAL,	5, 1, MAT.SMALL_BRILLIANT});
	DEtableInsert (t, {56, 60,		22, {1,2}, MAT.ILLUSION_DUST,	75, {1,2}, MAT.GREATER_ETERNAL,	5, 1, MAT.LARGE_BRILLIANT});
	DEtableInsert (t, {61, 65,		22, {2,5}, MAT.ILLUSION_DUST,	75, {2,3}, MAT.GREATER_ETERNAL,	5, 1, MAT.LARGE_BRILLIANT});
	
	-- RARE ITEMS
	
	deTable[deKey(ARMOR, RARE)] = {};
	
	t = deTable[deKey(ARMOR, RARE)];

	DEtableInsert (t, {11, 25,		100, 1, MAT.SMALL_GLIMMERING});
	DEtableInsert (t, {26, 30,		100, 1, MAT.LARGE_GLIMMERING});
	DEtableInsert (t, {31, 35,		100, 1, MAT.SMALL_GLOWING});
	DEtableInsert (t, {36, 40,		100, 1, MAT.LARGE_GLOWING});
	DEtableInsert (t, {41, 45,		100, 1, MAT.SMALL_RADIANT});
	DEtableInsert (t, {46, 50,		100, 1, MAT.LARGE_RADIANT});
	DEtableInsert (t, {51, 55,		100, 1, MAT.SMALL_BRILLIANT});
	DEtableInsert (t, {56, 65,		99.5, 1, MAT.LARGE_BRILLIANT,		0.5, 1, MAT.NEXUS_CRYSTAL});

	deTable[deKey(WEAPON, RARE)] = deTable[deKey(ARMOR, RARE)];


	-- EPIC ITEMS
	
	deTable[deKey(ARMOR, EPIC)] = {};
	
	t = deTable[deKey(ARMOR, EPIC)];

	DEtableInsert (t, {40, 45,		100, {2,4}, MAT.SMALL_RADIANT});
	DEtableInsert (t, {46, 50,		100, {2,4}, MAT.LARGE_RADIANT});
	DEtableInsert (t, {51, 55,		100, {2,4}, MAT.SMALL_BRILLIANT});
	DEtableInsert (t, {56, 60,		100, 1, MAT.NEXUS_CRYSTAL});
--	DEtableInsert (t, {61, 80,  FILLED IN BELOW

	deTable[deKey(WEAPON, EPIC)] = zc.CopyDeep (deTable[deKey(ARMOR, EPIC)]);	-- copy it this time because of differences

	DEtableInsert (deTable[deKey(ARMOR,  EPIC)], {61, 80,	50,   1, MAT.NEXUS_CRYSTAL, 	50,   2, MAT.NEXUS_CRYSTAL});
	DEtableInsert (deTable[deKey(WEAPON, EPIC)], {61, 80,	33.3, 1, MAT.NEXUS_CRYSTAL, 	66.6, 2, MAT.NEXUS_CRYSTAL});

end

-----------------------------------------

local function Atr_FindDEentry (itemType, itemRarity, itemLevel)

	local itemTypeNum = Atr_ItemType2AuctionClass (itemType);

	local t = deTable[deKey(itemTypeNum, itemRarity)];

	if (t) then
		local n;
		for n = 1, table.getn(t) do
			
			local ta = t[n];
			
			if (itemLevel >= ta[1] and itemLevel <= ta[2]) then
				return ta;
			end
		end
	end


end

-----------------------------------------

local function Atr_AddDEDetailsToTip (tip, itemType, itemRarity, itemLevel, DEreqLevel)

	local ta = Atr_FindDEentry (itemType, itemRarity, itemLevel);

	if (ta) then
		local x;
		for x = 3,table.getn(ta),3 do
			local percent = math.floor (ta[x]*100) / 100;

			local deitem = Atr_GetDEitemName(ta[x+2]);
			if (deitem == nil) then
				deitem = "???";
			end

			tip:AddLine ("  |cFFFFFFFF"..percent.."%|r   "..ta[x+1].." "..deitem);
		end
	end

	tip:AddLine ("  |cFFAAAAFF"..ZT("Required DE skill level")..": "..DEreqLevel);
end

-----------------------------------------

function Atr_DumpDETable (itemType, itemRarity)

	local t = deTable[deKey(itemType, itemRarity)];

	if (t) then
		local n, x;
		for n = 1, table.getn(t) do
			local ta = t[n];
			
			zc.msg_pink ("iLvl: "..ta[1].."-"..ta[2]);
			
			for x = 3,table.getn(ta),3 do
				zc.msg_pink ("   "..ta[x].."%  "..ta[x+1].."  "..Atr_GetDEitemName(ta[x+2]).."  ("..Atr_GetAuctionPrice (Atr_GetDEitemName(ta[x+2]))..")");
			end
		end
	end

end

-----------------------------------------

function Atr_CalcDisenchantPrice (itemType, itemRarity, itemLevel)

	if (Atr_IsWeaponType (itemType) or Atr_IsArmorType (itemType)) then
		if (itemRarity == UNCOMMON or itemRarity == RARE or itemRarity == EPIC) then

			local dePrice = 0;

			local ta = Atr_FindDEentry (itemType, itemRarity, itemLevel);
			if (ta) then
				local x;
				for x = 3,table.getn(ta),3 do
					local price = Atr_GetAuctionPriceDE (ta[x+2]);
					if (price) then
						dePrice = dePrice + (ta[x] * ta[x+1] * price);
					end
				end
			end

			return math.floor (dePrice/100);
		end
	end
	
	return nil;		-- can't be disenchanted
end

-----------------------------------------

local function ShowTipWithPricing (tip, link, num)

	if (link == nil) then
		return;
	end

--[[
	if (num == "tradeskill") then
	
		local skill = link;
	
		local n;
		for n = 1,GetTradeSkillNumReagents(skill) do
			local rname, _, rnum = GetTradeSkillReagentInfo(skill, n);
			local rlink = GetTradeSkillReagentItemLink (skill, n);
			zc.md (skill, rlink, rnum);
		end
	
		return;
	end
]]--

	local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, _, _, _, _, itemVendorPrice = Atr_GetItemInfo (link);

	local itemID = zc.ItemIDfromLink (link);
	itemID = tonumber(itemID);
	
	local vendorPrice	= 0;
	local auctionPrice	= 0;
	local dePrice		= nil;
	
	if (AUCTIONATOR_V_TIPS == 1) then vendorPrice	= itemVendorPrice; end;
	if (AUCTIONATOR_A_TIPS == 1) then auctionPrice	= Atr_GetAuctionPrice (itemName); end;
	if (AUCTIONATOR_D_TIPS == 1) then dePrice		= Atr_CalcDisenchantPrice (itemType, itemRarity, itemLevel); end;
	
	local xstring = "";
	local showStackPrices = IsShiftKeyDown();
	
	if (AUCTIONATOR_SHIFT_TIPS == 2) then
		showStackPrices = not IsShiftKeyDown();
	end

	if (num and showStackPrices) then
		if (auctionPrice)	then	auctionPrice = auctionPrice * num;	end;
		if (vendorPrice)	then	vendorPrice  = vendorPrice  * num;	end;
		if (dePrice)  		then	dePrice  	 = dePrice  * num;	end;
		xstring = "|cFFAAAAFF x"..num.."|r";
	end;

	if (vendorPrice == nil) then
		vendorPrice = 0;
	end

	-- vendor info

	if (AUCTIONATOR_V_TIPS == 1 and vendorPrice > 0) then
		local vpadding = Atr_CalcTTpadding (vendorPrice, auctionPrice);
		tip:AddDoubleLine (ZT("Vendor")..xstring, "|cFFFFFFFF"..zc.priceToMoneyString (vendorPrice))
	end
	
	-- auction info

	if (AUCTIONATOR_A_TIPS == 1) then
		
		local bonding = Atr_GetBonding(itemID);
		local isBOP   = (bonding == 1);
		local isQuest = (bonding == 4 or bonding == 5);
		
		if (isBOP) then
			tip:AddDoubleLine (ZT("Auction")..xstring, "|cFFFFFFFF"..ZT("BOP").."  ");		
		elseif (isQuest) then
			tip:AddDoubleLine (ZT("Auction")..xstring, "|cFFFFFFFF"..ZT("Quest Item").."  ");		
		elseif (auctionPrice ~= nil) then
			tip:AddDoubleLine (ZT("Auction")..xstring, "|cFFFFFFFF"..zc.priceToMoneyString (auctionPrice));
		else
			tip:AddDoubleLine (ZT("Auction")..xstring, "|cFFFFFFFF"..ZT("unknown").."  ");
		end
	end
	
	-- disenchanting info

	if (AUCTIONATOR_D_TIPS == 1 and dePrice ~= nil) then
		if (dePrice > 0) then
			tip:AddDoubleLine (ZT("Disenchant")..xstring, "|cFFFFFFFF"..zc.priceToMoneyString(dePrice));
		else
			tip:AddDoubleLine (ZT("Disenchant")..xstring, "|cFFFFFFFF"..ZT("unknown").."  ");
		end
	end

	local showDetails = true;
	
	if (AUCTIONATOR_DE_DETAILS_TIPS == 1) then showDetails = IsShiftKeyDown(); end;
	if (AUCTIONATOR_DE_DETAILS_TIPS == 2) then showDetails = IsControlKeyDown(); end;
	if (AUCTIONATOR_DE_DETAILS_TIPS == 3) then showDetails = IsAltKeyDown(); end;
	if (AUCTIONATOR_DE_DETAILS_TIPS == 4) then showDetails = false; end;
	if (AUCTIONATOR_DE_DETAILS_TIPS == 5) then showDetails = true; end;
	
	if (showDetails and dePrice ~= nil) then
		Atr_AddDEDetailsToTip (tip, itemType, itemRarity, itemLevel, Atr_DEReqLevel(itemID));
	end

	tip:Show()

end

-----------------------------------------

hooksecurefunc (GameTooltip, "SetBagItem",
	function(tip, bag, slot)
		local _, num = GetContainerItemInfo(bag, slot);
		ShowTipWithPricing (tip, GetContainerItemLink(bag, slot), num);
	end
);

hooksecurefunc (GameTooltip, "SetAuctionItem",
	function (tip, type, index)
		local _, _, num = GetAuctionItemInfo(type, index);
		ShowTipWithPricing (tip, GetAuctionItemLink(type, index), num);
	end
);

hooksecurefunc (GameTooltip, "SetAuctionSellItem",
	function (tip)
		local name, _, count = GetAuctionSellItemInfo();
		local __, link = GetItemInfo(name);
		ShowTipWithPricing (tip, link, num);
	end
);


hooksecurefunc (GameTooltip, "SetLootItem",
	function (tip, slot)
		if LootSlotIsItem(slot) then
			local link, _, num = GetLootSlotLink(slot);
			ShowTipWithPricing (tip, link, num);
		end
	end
);

-- SetLootRollItem and SetGuildBankItem are 2.x+ tooltip methods. Group-loot
-- rolling tooltips and guild banks didn't exist in 1.12, so guard each hook.
if GameTooltip.SetLootRollItem then
	hooksecurefunc (GameTooltip, "SetLootRollItem",
		function (tip, slot)
			local _, _, num = GetLootRollItemInfo(slot);
			ShowTipWithPricing (tip, GetLootRollItemLink(slot), num);
		end
	);
end


hooksecurefunc (GameTooltip, "SetInventoryItem",
	function (tip, unit, slot)
		ShowTipWithPricing (tip, GetInventoryItemLink(unit, slot), GetInventoryItemCount(unit, slot));
	end
);

if GameTooltip.SetGuildBankItem then
	hooksecurefunc (GameTooltip, "SetGuildBankItem",
		function (tip, tab, slot)
			local _, num = GetGuildBankItemInfo(tab, slot);
			ShowTipWithPricing (tip, GetGuildBankItemLink(tab, slot), num);
		end
	);
end

hooksecurefunc (GameTooltip, "SetTradeSkillItem",
	function (tip, skill, id)
		local link = GetTradeSkillItemLink(skill);
		local num  = GetTradeSkillNumMade(skill);
		if id then
			link = GetTradeSkillReagentItemLink(skill, id);
			local _, _, _reagentCount = GetTradeSkillReagentInfo(skill, id);
			num = _reagentCount;
		end

		ShowTipWithPricing (tip, link, num);
	end
);

hooksecurefunc (GameTooltip, "SetTradePlayerItem",
	function (tip, id)
		local _, _, num = GetTradePlayerItemInfo(id);
		ShowTipWithPricing (tip, GetTradePlayerItemLink(id), num);
	end
);

hooksecurefunc (GameTooltip, "SetTradeTargetItem",
	function (tip, id)
		local _, _, num = GetTradeTargetItemInfo(id);
		ShowTipWithPricing (tip, GetTradeTargetItemLink(id), num);
	end
);

hooksecurefunc (GameTooltip, "SetQuestItem",
	function (tip, type, index)
		local _, _, num = GetQuestItemInfo(type, index);
		ShowTipWithPricing (tip, GetQuestItemLink(type, index), num);
	end
);

hooksecurefunc (GameTooltip, "SetQuestLogItem",
	function (tip, type, index)
		local num, _;
		if type == "choice" then
			_, _, num = GetQuestLogChoiceInfo(index);
		else
			_, _, num = GetQuestLogRewardInfo(index)
		end

		ShowTipWithPricing (tip, GetQuestLogItemLink(type, index), num);
	end
);

hooksecurefunc (GameTooltip, "SetInboxItem",
	function (tip, index, attachIndex)
		local _, _, num = GetInboxItem(index, attachIndex);
		ShowTipWithPricing (tip, GetInboxItemLink(index, attachIndex), num);
	end
);

hooksecurefunc (GameTooltip, "SetSendMailItem",
	function (tip, id)
		local name, _, num = GetSendMailItem(id)
		local name, link = GetItemInfo(name);
		ShowTipWithPricing (tip, link, num);
	end
);

hooksecurefunc (GameTooltip, "SetHyperlink",
	function (tip, itemstring, num)
		local name, link = GetItemInfo (itemstring);
		ShowTipWithPricing (tip, link, num);
	end
);

hooksecurefunc (ItemRefTooltip, "SetHyperlink",
	function (tip, itemstring)
		local name, link = GetItemInfo (itemstring);
		ShowTipWithPricing (tip, link);
	end
);










