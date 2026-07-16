
local addonTable = AuctionatorPrivate;
local zc = addonTable.zc;

KM_NULL_STATE	= 0;
KM_PREQUERY		= 1;
KM_INQUERY		= 2;
KM_POSTQUERY	= 3;
KM_ANALYZING	= 4;
KM_SETTINGSORT	= 5;

local AUCTION_CLASS_WEAPON = 1;
local AUCTION_CLASS_ARMOR  = 2;

local gAllScans = {};

local BIGNUM = 999999999999;

local ATR_SORTBY_NAME_ASC = 0;
local ATR_SORTBY_NAME_DES = 1;
local ATR_SORTBY_PRICE_ASC = 2;
local ATR_SORTBY_PRICE_DES = 3;

-----------------------------------------

AtrScan = {};
AtrScan.__index = AtrScan;

-----------------------------------------

AtrSearch = {};
AtrSearch.__index = AtrSearch;

-----------------------------------------

function Atr_NewSearch (itemName, exact, rescanThreshold, callback, opts)

	local srch = {};
	setmetatable (srch, AtrSearch);
	srch:Init (itemName, exact, rescanThreshold, callback, opts);

	return srch;
end

-----------------------------------------

function AtrSearch:Init (searchText, exact, rescanThreshold, callback, opts)

	if (searchText == nil) then
		searchText = "";
	end

	self.origSearchText = searchText;

	if (not exact) then
		if (zc.StringStartsWith (searchText, "\"") and zc.StringEndsWith (searchText, "\"")) then
			searchText = string.sub (searchText, 2, string.len(searchText)-1);
			exact = true;
		end
	end

	self.searchText			= searchText;
	self.exact				= exact;
	self.processing_state	= KM_NULL_STATE
	self.current_page		= -1
	self.items				= {};
	self.query				= Atr_NewQuery();
	self.sortedScans		= nil;
	self.sortHow			= ATR_SORTBY_PRICE_ASC;
	self.callback			= callback;
	self.shoppingMode		= opts and opts.shoppingMode;
	self.bestPerUnitSeen	= nil;
	
	if (exact) then	

		if (rescanThreshold and rescanThreshold > 0) then
			local scan = Atr_FindScan (searchText);
			if (scan and (time() - scan.whenScanned) <= rescanThreshold) then
				self.items[searchText] = scan;
			end
		end
		
		if (not self.items[searchText]) then		
			self.items[searchText] = Atr_FindScanAndInit (searchText);
		end
		
	end
	
end

-----------------------------------------

function Atr_FindScanAndInit (itemName)

	return Atr_FindScan (itemName, true);
end

-----------------------------------------

function Atr_FindScan (itemName, init)

	if (itemName == nil or itemName == "") then
		itemName = "nil";
	end

	local itemNameLC = string.lower (itemName);

	if (gAllScans[itemNameLC] == nil) then

		local scn = {};
		setmetatable (scn, AtrScan);
		scn:Init (itemName);

		gAllScans[itemNameLC] = scn;
	elseif (init) then
		gAllScans[itemNameLC]:Init (itemName);
	end
	
	return gAllScans[itemNameLC];
end

-----------------------------------------

function Atr_ClearScanCache ()

--	zc.msg_red ("Clearing Scan Cache");

	for a,v in pairs (gAllScans) do
		if (a ~= "nil") then
			gAllScans[a] = nil;
		end
	end

end

-----------------------------------------

function AtrScan:Init (itemName)
	self.itemName			= itemName;
	self.itemLink			= nil;
	self.scanData			= {};
	self.sortedData			= {};
	self.whenScanned		= 0;
	self.lowprices			= {BIGNUM, BIGNUM, BIGNUM};
	self.absoluteBest		= nil;
	self.itemClass			= 0;
	self.itemSubclass		= 0;
	self.yourBestPrice		= nil;
	self.yourWorstPrice		= nil;
	self.numYourSingletons	= 0;
	self.itemTextColor 		= { 1.0, 1.0, 1.0 };
	self.searchWasExact		= false;
	
	self:UpdateItemLink (Atr_GetItemLink (itemName));
end

-----------------------------------------

function AtrScan:UpdateItemLink (itemLink)

	self.itemLink = itemLink;
	
	if (itemLink) then
	
		Atr_AddToItemLinkCache (self.itemName, itemLink);

		local _, _, quality, _, _, sType, sSubType = Atr_GetItemInfo(itemLink);

		self.itemQuality	= quality;
		self.itemClass		= Atr_ItemType2AuctionClass (sType);
		self.itemSubclass	= Atr_SubType2AuctionSubclass (self.itemClass, sSubType);	

		local r, g, b = GetItemQualityColor(quality)
		self.itemTextColor = { r, g, b };
	end

end


-----------------------------------------

function AtrSearch:NumScans()

	if (self.sortedScans) then
		return table.getn(self.sortedScans);
	end

	local count = 0;
	for name,scn in pairs (self.items) do
		count = count + 1;
	end

	return count;
end

-----------------------------------------

function AtrSearch:NumSortedScans()

	if (self.sortedScans) then
		return table.getn(self.sortedScans);
	end

	return 0;
end

-----------------------------------------

function AtrSearch:GetFirstScan()

	if (self.sortedScans) then
		return self.sortedScans[1];
	end

	for name,scn in pairs (self.items) do
		return scn;
	end
	
	return nil;

end


-----------------------------------------

function AtrSearch:Start ()

	if (self.searchText == "") then
		return;
	end
	
	if (Atr_IsCompoundSearch (self.searchText)) then
			
		local _, itemClass = Atr_ParseCompoundSearch (self.searchText);
	
		if (itemClass == 0) then
			Atr_Error_Display (ZT("The first part of this compound\n\nsearch is not a valid category."));
			return;
		end

		self.sortHow = ATR_SORTBY_PRICE_DES;

	end
	
	self.processing_state = KM_SETTINGSORT;
	
	SortAuctionClearSort ("list");

	BrowseName:SetText (self.searchText);		-- not necessary but nice when user switches to Browse tab

	self.current_page		= 0;
	self.processing_state	= KM_PREQUERY;

	self:Continue();
	
end

-----------------------------------------

function AtrSearch:Abort ()

	if (self.processing_state == KM_NULL_STATE) then
		return;
	end

	self.processing_state = KM_NULL_STATE;
	self:Init();
end

-----------------------------------------

function AtrSearch:CheckForDuplicatePage ()

	local isDup = self.query:CheckForDuplicatePage(self.current_page);

	if (isDup) then
--		zc.msg_red ("DUPLICATE PAGE FOUND: ", "  current_page: ", self.current_page, "  numDupPages: ", self.query.numDupPages);

		-- A "duplicate" here almost always means we got an AUCTION_ITEM_LIST_UPDATE
		-- that still carries the page we already processed -- the client re-fires
		-- that event once per uncached item as its data resolves. The old code
		-- re-queried the page on every such refire; with a fast (response-driven)
		-- throttle that becomes a re-query storm that trips the numDupPages > 10
		-- abort in AnalyzeResultsPage and returns no results. Instead, stay in
		-- KM_POSTQUERY and ignore the refire: the event that carries the genuinely
		-- new page won't be a dup and will advance the scan. A KM_POSTQUERY
		-- timeout in Atr_Idle re-queries if a page never arrives, so this can't hang.
	end

	return isDup;
end


-----------------------------------------

function AtrSearch:AnalyzeResultsPage()

	self.processing_state = KM_ANALYZING;

	if (self.query.numDupPages > 10) then 	 -- hopefully this will never happen but need check to avoid looping
		return true;						 -- done
	end


	local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");

	-- if (self.current_page == 1 and totalAuctions > 2000) then -- give Blizz servers a break
	-- 	Atr_Error_Display (ZT("Too many results\n\nPlease narrow your search"));
	-- 	return true;  -- done
	-- end

	if (totalAuctions >= 50) then
		local totalPages = ceil(totalAuctions / 50)
		Atr_SetMessage (string.format (ZT("Scanning auctions: page %d of %d"), self.current_page, totalPages));
	end

	-- analyze

	local numNilOwners = 0;
	local maxNonzeroTotalThisPage = 0;

	if (numBatchAuctions > 0) then

		local x;

		for x = 1, numBatchAuctions do

			local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner = GetAuctionItemInfo("list", x);

			if (owner == nil) then
				numNilOwners = numNilOwners + 1;
			end

			local exactMatch = zc.StringSame (name, self.searchText);

			-- `name` can be nil here: on a fast (response-driven) scan the page is
			-- processed before every row's item data has resolved from the client
			-- cache. For an exact search those rows just fail exactMatch and are
			-- skipped, but a category/non-exact search takes the `not self.exact`
			-- branch for every row -- and `self.items[nil] = ...` is a "table index
			-- is nil" error that aborts the whole page, so nothing gets stored and
			-- the results pane stays empty. Guard on `name` so unresolved rows are
			-- skipped instead of crashing.
			if (name and (exactMatch or not self.exact)) then

				if (self.items[name] == nil) then
					self.items[name] = Atr_FindScanAndInit (name);
				end

				local curpage = (tonumber(self.current_page)-1);

				local scn = self.items[name];

				scn:AddScanItem (name, count, buyoutPrice, owner, 1, curpage);

				if (scn.itemLink == nil or self.itemClass == nil) then
					scn:UpdateItemLink (GetAuctionItemLink("list", x));
				end

				if (buyoutPrice and buyoutPrice > 0 and count and count > 0) then
					if (buyoutPrice > maxNonzeroTotalThisPage) then
						maxNonzeroTotalThisPage = buyoutPrice;
					end
					local perUnit = buyoutPrice / count;
					if (self.bestPerUnitSeen == nil or perUnit < self.bestPerUnitSeen) then
						self.bestPerUnitSeen = perUnit;
					end
				end

				if (self.callback) then
					self.callback (x, numBatchAuctions, count, buyoutPrice, owner);
				end

			end
		end
	end

	local done = (numBatchAuctions < 50);

	-- Turtle's AH server returns list-query results in ascending TOTAL-buyout
	-- order across pages (multimap keyed on AuctionEntry::buyout). Combined
	-- with the per-item stack cap, this lets us prove when no later page can
	-- contain a cheaper-per-unit listing than what we've already seen, and
	-- bail out early. Only applies to exact shopping-mode searches where the
	-- caller wants the cheapest current per-unit price for a known item.
	if (not done and self.shoppingMode and self.exact and
			self.bestPerUnitSeen and maxNonzeroTotalThisPage > 0 and
			C_Item and C_Item.GetItemMaxStackSizeByID) then

		local scn = self:GetFirstScan();
		if (scn and scn.itemLink) then
			local maxStack = C_Item.GetItemMaxStackSizeByID (scn.itemLink);
			if (maxStack and maxStack > 0) then
				local minPossibleNextPerUnit = maxNonzeroTotalThisPage / maxStack;
				if (minPossibleNextPerUnit > self.bestPerUnitSeen) then
					done = true;
				end
			end
		end
	end

	if (not done) then
		self.processing_state = KM_PREQUERY;
	end

	return done;
end

-----------------------------------------

function AtrScan:AddScanItem (name, stackSize, buyoutPrice, owner, numAuctions, curpage)

	local sd = {};
	local i;

	if (numAuctions == nil) then
		numAuctions = 1;
	end

	for i = 1, numAuctions do
		sd["stackSize"]		= stackSize;
		sd["buyoutPrice"]	= buyoutPrice;
		sd["owner"]			= owner;
		sd["pagenum"]		= curpage;

		tinsert (self.scanData, sd);
		
		local itemPrice = math.floor (buyoutPrice / stackSize);

		Atr_AddToLowPrices (self.lowprices, itemPrice);
	end

end


-----------------------------------------

function AtrScan:AddSDXToScan (price, owner, volume)	-- helper function for AddExternalDataToScan

	local sd = {};

	if (price and price > 0) then
		sd["stackSize"]		= 1;
		sd["buyoutPrice"]	= price;
		sd["owner"]			= owner;

		if (volume) then
			sd["volume"] = volume;
		end

		tinsert (self.scanData, sd);
	end
	
end

-----------------------------------------

function AtrScan:AddExternalDataToScan ()

	if (self.itemLink == nil) then
		return;
	end

	-- Wowecon

	if (Wowecon and Wowecon.API) then
	
		local priceG, volG = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.GLOBAL_PRICE)
		local priceS, volS = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.SERVER_PRICE)

		self:AddSDXToScan (priceG, "__wowEconG", volG);
		self:AddSDXToScan (priceS, "__wowEconS", volS);
		
	end
	
	-- GoingPrice Wowhead
	
	local id = zc.ItemIDfromLink (self.itemLink);
	
	id = tonumber(id);

	if (GoingPrice_Wowhead_Data and GoingPrice_Wowhead_Data[id] and GoingPrice_Wowhead_SV._index) then
		local index = GoingPrice_Wowhead_SV._index["Buyout price"];

		if (index ~= nil) then
			local price = GoingPrice_Wowhead_Data[id][index];
		
			self:AddSDXToScan (price, "__wowHead");
		end
	end

	-- GoingPrice Allakhazam
	
	if (GoingPrice_Allakhazam_Data and GoingPrice_Allakhazam_Data[id] and GoingPrice_Allakhazam_SV._index) then
		local index = GoingPrice_Allakhazam_SV._index["Median"];

		if (index ~= nil) then
			local price = GoingPrice_Allakhazam_Data[id][index];
		
			self:AddSDXToScan (price, "__allakhazam");
		end
	end

	-- most recent historical price
	
	local price = Atr_Process_Historydata();
	if (price ~= nil) then
		self:AddSDXToScan (price, "__atrLast");
	end

end

-----------------------------------------

function AtrScan:SubtractScanItem (name, stackSize, buyoutPrice)

	local sd;
	local i;

	for i,sd in ipairs (self.scanData) do
		
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice) then
			
			tremove (self.scanData, i);
			return;
		end
	end

end

-----------------------------------------

function Atr_IsCompoundSearch (searchString)
	
	return zc.StringContains (searchString, ">") or zc.StringContains (searchString, "/");
end

-----------------------------------------

function Atr_ParseCompoundSearch (searchString)

	local delim = "/";

	if (zc.StringContains (searchString, ">")) then
		delim = ">";
	end

	local tbl	= { strsplit (delim, searchString) };
	
	local queryString	= "";
	local itemClass		= 0;
	local itemSubclass	= 0;
	local minLevel		= nil;
	local maxLevel		= nil;
	local prevWasItemClass;
	local n;
	
	for n = 1,table.getn(tbl) do
		local s = tbl[n];

		local handled = false;

		if (not handled and tonumber(s)) then
			if (minLevel == nil) then
				minLevel = tonumber(s);
			elseif (maxLevel == nil) then
				maxLevel = tonumber(s);
			end
			
			handled = true;
			prevWasItemClass = false;
		end
		
		if (not handled and prevWasItemClass and itemSubclass == 0) then
			itemSubclass = Atr_SubType2AuctionSubclass (itemClass, s);
			if (itemSubclass > 0) then
				handled = true;
				prevWasItemClass = false;
			end
		end
		
		if (not handled and itemClass == 0) then
			itemClass = Atr_ItemType2AuctionClass (s);
			if (itemClass > 0) then
				prevWasItemClass = true;
				handled = true;
			end
		end
		
		if (not handled) then
			queryString = s;
			handled = true;
		end
	end	

	return queryString, itemClass, itemSubclass, minLevel, maxLevel;
end

-----------------------------------------

function AtrSearch:Continue()

	if (CanSendAuctionQuery()) then

		self.processing_state = KM_IN_QUERY;

		local queryString = self.searchText;

--	zc.md (queryString.."  page:"..self.current_page);
		
		local itemClass		= 0;
		local itemSubclass	= 0;
		local minLevel		= nil;
		local maxLevel		= nil;
		
		if (self.exact) then
			local scn = self:GetFirstScan();
			itemClass		= scn.itemClass;
			itemSubclass	= scn.itemSubclass;
		end

		if (Atr_IsCompoundSearch(queryString)) then
		
			queryString, itemClass, itemSubclass, minLevel, maxLevel = Atr_ParseCompoundSearch (queryString);
		
		end

		queryString = zc.UTF8_Truncate (queryString,63);	-- attempting to reduce number of disconnects

		QueryAuctionItems (queryString, minLevel, maxLevel, nil, itemClass, itemSubclass, self.current_page, nil, nil);

		self.query_sent_when	= gAtr_ptime;
		self.processing_state	= KM_POSTQUERY;
		self.current_page		= self.current_page + 1;
	end

end

-----------------------------------------

local gSortScansBy;

-----------------------------------------

local function Atr_SortScans (x, y)

	if (gSortScansBy == ATR_SORTBY_NAME_ASC) then		return string.lower (x.itemName) < string.lower (y.itemName);	end
	if (gSortScansBy == ATR_SORTBY_NAME_DES) then		return string.lower (x.itemName) > string.lower (y.itemName);	end

	local xprice = 0;
	local yprice = 0;
	
	if (x.absoluteBest) then	xprice = zc.round(x.absoluteBest.buyoutPrice/x.absoluteBest.stackSize);		end;
	if (y.absoluteBest) then	yprice = zc.round(y.absoluteBest.buyoutPrice/y.absoluteBest.stackSize);		end;
	
	if (gSortScansBy == ATR_SORTBY_PRICE_ASC) then		return xprice < yprice;		end
	if (gSortScansBy == ATR_SORTBY_PRICE_DES) then		return xprice > yprice;		end

end

-----------------------------------------

function AtrSearch:Finish()

	local finishTime = time();
	
	self.processing_state	= KM_NULL_STATE;
	self.current_page		= -1;
	self.query_sent_when	= nil;
	
	self.sortedScans = nil;
	
	local wasExactSearch = (self:NumScans() == 1);		-- search returned only 1 item
	
	local x = 1;
	self.sortedScans = {};
	
	for name,scn in pairs (self.items) do
	
		self.sortedScans[x] = scn;
		x = x + 1;
		
		scn.whenScanned		= finishTime;
		scn.searchWasExact	= wasExactSearch;

		scn:CondenseAndSort ();

		-- update the fullscan DB
		
		local newprice = Atr_CalcNewDBprice (scn.itemName, scn.lowprices);
		
		if (newprice > 0) then
			-- scn.itemQuality is set by AtrScan:UpdateItemLink only when the
			-- item's link is in the local cache. On a fresh scan the link may
			-- not have been resolved yet — default to 0 (poor) so the item is
			-- still recorded at the default min-quality (1 = poor).
			if ((scn.itemQuality or 0) + 1 >= AUCTIONATOR_SCAN_MINLEVEL) then
				gAtr_ScanDB[scn.itemName] = newprice;
			end
		end
	end
	
	Atr_ClearBrowseListings();
	
	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
	
end

-----------------------------------------

function AtrSearch:ClickPriceCol()

	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		self.sortHow = ATR_SORTBY_PRICE_DES;
	else
		self.sortHow = ATR_SORTBY_PRICE_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);

end

-----------------------------------------

function AtrSearch:ClickNameCol()

	if (self.sortHow == ATR_SORTBY_NAME_ASC) then
		self.sortHow = ATR_SORTBY_NAME_DES;
	else
		self.sortHow = ATR_SORTBY_NAME_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
end

-----------------------------------------

function AtrSearch:UpdateArrows()

	Atr_Col1_Heading_ButtonArrow:Hide();
	Atr_Col3_Heading_ButtonArrow:Hide();
	
	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_PRICE_DES) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	elseif (self.sortHow == ATR_SORTBY_NAME_ASC) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_NAME_DES) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	end
end

-----------------------------------------

local gAtr_clearListingsPending = false;

function Atr_ClearBrowseListings()

	gAtr_clearListingsPending = true;

end

-----------------------------------------

function Atr_ClearBrowseListings_Idle()

	if (gAtr_clearListingsPending and CanSendAuctionQuery()) then
		gAtr_clearListingsPending = false;
		QueryAuctionItems("xyzzy", 43, 43, 0, 7, 0);
	end

end

-----------------------------------------

function Atr_SortAuctionData (x, y)

	return x.itemPrice < y.itemPrice;

end

-----------------------------------------

function AtrScan:CondenseAndSort ()

	----- Condense the scan data into a table that has only a single entry per stacksize/price combo

	self.sortedData	= {};

	local i,sd;
	local conddata = {};

	for i,sd in ipairs (self.scanData) do

		local ownerCode = "x";
		local dataType  = "n";		-- normal
		
		if (sd.owner == UnitName("player")) then
			ownerCode = "y";
--		elseif (Atr_IsMyToon (sd.owner)) then
--			ownerCode = sd.owner;
		elseif (sd.owner == "__wowEconG") then
			dataType = "eg";
		elseif (sd.owner == "__wowEconS") then
			dataType = "es";
		elseif (sd.owner == "__wowHead") then
			dataType = "h";
		elseif (sd.owner == "__allakhazam") then
			dataType = "k";
		elseif (sd.owner == "__atrLast") then
			dataType = "a";
		end

		local key = "_"..sd.stackSize.."_"..sd.buyoutPrice.."_"..ownerCode..dataType;

		if (conddata[key]) then
			conddata[key].count		= conddata[key].count + 1;
			conddata[key].minpage 	= zc.Min (conddata[key].minpage, sd.pagenum);
			conddata[key].maxpage 	= zc.Max (conddata[key].maxpage, sd.pagenum);
		else
			local data = {};

			data.stackSize 		= sd.stackSize;
			data.buyoutPrice	= sd.buyoutPrice;
			data.itemPrice		= sd.buyoutPrice / sd.stackSize;
			data.minpage		= sd.pagenum;
			data.maxpage		= sd.pagenum;
			data.count			= 1;
			data.type			= dataType;
			data.yours			= (ownerCode == "y");
			
			if (ownerCode ~= "x" and ownerCode ~= "y") then
				data.altname = ownerCode;
			end
			
			if (sd.volume) then
				data.volume = sd.volume;
			end
			
			conddata[key] = data;
		end

	end

	----- create a table of these entries

	local n = 1;

	local i, v;

	for i,v in pairs (conddata) do
		self.sortedData[n] = v;
		n = n + 1;
	end

	-- sort the table by itemPrice

	table.sort (self.sortedData, Atr_SortAuctionData);

	-- analyze and store some info about the data

	self:AnalyzeSortData ();

end

-----------------------------------------

function AtrScan:AnalyzeSortData ()

	self.absoluteBest			= nil;
	self.bestPrices				= {};		-- a table with one entry per stacksize that is the cheapest auction for that particular stacksize
	self.numMatches				= 0;
	self.numMatchesWithBuyout	= 0;
	self.hasStack				= false;
	self.yourBestPrice			= nil;
	self.yourWorstPrice			= nil;
	self.numYourSingletons		= 0;

	local j, sd;

	----- find the best price per stacksize and overall -----

	for j,sd in ipairs(self.sortedData) do

		if (sd.type == "n") then

			self.numMatches = self.numMatches + 1;

			if (sd.itemPrice > 0) then

				self.numMatchesWithBuyout = self.numMatchesWithBuyout + 1;

				if (self.bestPrices[sd.stackSize] == nil or self.bestPrices[sd.stackSize].itemPrice >= sd.itemPrice) then
					self.bestPrices[sd.stackSize] = sd;
				end

				if (self.absoluteBest == nil or self.absoluteBest.itemPrice > sd.itemPrice) then
					self.absoluteBest = sd;
				end
				
				if (sd.yours) then
					if (self.yourBestPrice == nil or self.yourBestPrice > sd.itemPrice) then
						self.yourBestPrice = sd.itemPrice;
					end
					
					if (self.yourWorstPrice == nil or self.yourWorstPrice < sd.itemPrice) then
						self.yourWorstPrice = sd.itemPrice;
					end
					
					if (sd.stackSize == 1) then
						self.numYourSingletons = self.numYourSingletons + sd.count;
					end
				end
			end

			if (sd.stackSize > 1) then
				self.hasStack = true;
			end
		end
	end
end

-----------------------------------------

function AtrScan:FindInSortedData (stackSize, buyoutPrice)
	local j = 1;
	for j = 1,table.getn(self.sortedData) do
		sd = self.sortedData[j];
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice and sd.yours) then
			return j;
		end
	end
	
	return 0;
end


-----------------------------------------

function AtrScan:FindMatchByStackSize (stackSize)

	local index = nil;

	local basedata = self.absoluteBest;

	if (self.bestPrices[stackSize]) then
		basedata = self.bestPrices[stackSize];
	end

	local numrows = table.getn(self.sortedData);

	local n;

	for n = 1,numrows do

		local data = self.sortedData[n];

		if (basedata and data.itemPrice == basedata.itemPrice and data.stackSize == basedata.stackSize and data.yours == basedata.yours) then
			index = n;
			break;
		end
	end

	return index;
	
end

-----------------------------------------

function AtrScan:FindMatchByYours ()

	local index = nil;

	local j;
	for j = 1,table.getn(self.sortedData) do
		sd = self.sortedData[j];
		if (sd.yours) then
			index = j;
			break;
		end
	end

	return index;

end

-----------------------------------------

function AtrScan:FindCheapest ()

	local index = nil;

	local j;
	for j = 1,table.getn(self.sortedData) do
		sd = self.sortedData[j];
		if (sd.itemPrice > 0) then
			index = j;
			break;
		end
	end

	return index;

end


-----------------------------------------

function AtrScan:GetNumAvailable ()

	local num = 0;

	local j, data;
	for j = 1,table.getn(self.sortedData) do

		data = self.sortedData[j];
		num = num + (data.count * data.stackSize);
	end
	
	return num;
end

-----------------------------------------

function AtrScan:IsNil ()

	if (self.itemName == nil or self.itemName == "" or self.itemName == "nil") then
		return true;
	end
	
	return false;
end

-----------------------------------------

ATR_FS_NULL			= 0;
ATR_FS_STARTED		= 1;
ATR_FS_ANALYZING	= 2;
ATR_FS_CLEANING_UP	= 3;

gAtr_FullScanState = ATR_FS_NULL;


-----------------------------------------

function Atr_GetDBsize()

	local n = 0;
	local a,v;

	for a,v in pairs (gAtr_ScanDB) do
		n = n + 1;
	end
	
	return n;
end

-----------------------------------------

local gNumAdded, gNumUpdated;

-- Full-scan paging state. The 1.12 QueryAuctionItems has no getAll, so a full
-- scan walks the whole house one 50-item page at a time, accumulating lowest
-- prices across pages. This mirrors the main AtrSearch paging discipline
-- (response-driven Continue + dup-page detection + idle timeout re-query) so the
-- same refire / dropped-packet handling applies here too.
local gFS_query;
local gFS_current_page;
local gFS_query_sent_when;
local gFS_pstate;			-- "prequery" (send next page) | "postquery" (waiting on a page)
local gFS_lowprices;
local gFS_qualities;
local gFS_numScanned;

-----------------------------------------

function Atr_FullScanContinue()

	if (CanSendAuctionQuery()) then
		-- empty name + wildcard filters = every auction, page by page
		QueryAuctionItems ("", nil, nil, 0, 0, 0, gFS_current_page, 0);
		gFS_query_sent_when	= gAtr_ptime;
		gFS_pstate			= "postquery";
		gFS_current_page	= gFS_current_page + 1;
	end
end

-----------------------------------------

function Atr_FullScanStart()

	-- Page-based full scan: gate on the ordinary query throttle (canQuery), not
	-- canQueryAll -- the getAll capability is never available on 1.12, so gating
	-- on it left the Start Scanning button permanently disabled.
	local canQuery = CanSendAuctionQuery();

	if (canQuery) then

		Atr_FullScanStatus:SetText (ZT("Scanning").."...");
		Atr_FullScanStartButton:Disable();
		Atr_FullScanDone:Disable();

		gAtr_FullScanState = ATR_FS_STARTED;

		SortAuctionClearSort ("list");

		gNumAdded = 0;
		gNumUpdated = 0;

		gFS_lowprices		= {};
		gFS_qualities		= {};
		gFS_numScanned		= 0;
		gFS_query			= Atr_NewQuery();
		gFS_current_page	= 0;
		gFS_pstate			= "prequery";

		Atr_FullScanContinue();		-- send page 0; later pages are driven from idle
	end

end

-----------------------------------------

function Atr_CalcNewDBprice (name, prices)
		
	if (prices[1] ~= BIGNUM) then
		return prices[1];
	end

	return 0;
	
end

-----------------------------------------

function Atr_AddToLowPrices (lowprices, itemPrice)
	
	if (itemPrice > 0) then
		if (itemPrice < lowprices[1]) then
			if (lowprices[1] < lowprices[2]) then
				lowprices[2] = lowprices[1];
			end
			lowprices[1] = itemPrice;
			return true;
		elseif (itemPrice < lowprices[2]) then
			lowprices[2] = itemPrice;
			return true;
		end
	end

	return false;
end




-----------------------------------------

local gScanDetails = {}

-----------------------------------------

function Atr_FullScanMoreDetails ()

	zc.msg (" ");
	zc.msg_atr (ZT("Auctions scanned")..": |cffffffff", gScanDetails.numBatchAuctions, " |r("..gScanDetails.totalItems, "items)");
	zc.msg_atr ("|cffa335ee   "..ZT("Epic items")..": |r",		gScanDetails.numEachQual[5]);
	zc.msg_atr ("|cff0070dd   "..ZT("Rare items")..": |r",		gScanDetails.numEachQual[4]);
	zc.msg_atr ("|cff1eff00   "..ZT("Uncommon items")..": |r",	gScanDetails.numEachQual[3]);
	zc.msg_atr ("|cffffffff   "..ZT("Common items")..": |r",		gScanDetails.numEachQual[2]);
	zc.msg_atr ("|cff9d9d9d   "..ZT("Poor items")..": |r",		gScanDetails.numEachQual[1]);
	
	
	if (gScanDetails.numRemoved[4] > 0) then		zc.msg_atr (ZT("Rare items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[4]);		end
	if (gScanDetails.numRemoved[3] > 0) then		zc.msg_atr (ZT("Uncommon items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[3]);		end
	if (gScanDetails.numRemoved[2] > 0) then		zc.msg_atr (ZT("Common items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[2]);		end
	if (gScanDetails.numRemoved[1] > 0) then		zc.msg_atr (ZT("Poor items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[1]);		end
	
	zc.msg_atr (ZT("Items added to database")..": |cffffffff", gScanDetails.gNumAdded);
	zc.msg_atr (ZT("Items updated in database")..": |cffffffff", gScanDetails.gNumUpdated);
	zc.msg_atr (ZT("Items ignored")..": |cffffffff", gScanDetails.totalItems - (gScanDetails.gNumAdded + gScanDetails.gNumUpdated));
	zc.msg (" ");
end

-----------------------------------------

-- Handle an AUCTION_ITEM_LIST_UPDATE while a full scan is running.
-- The client re-fires this event once per uncached item as data resolves;
-- ignore those refires (same page) and only act on a genuinely new page, the
-- same way the main search does. Process the page, then either finalize (last
-- page) or arm the idle loop to fetch the next page.
function Atr_FullScanOnUpdate()

	if (gFS_pstate ~= "postquery") then
		return;
	end

	if (gFS_query:CheckForDuplicatePage (gFS_current_page)) then
		return;		-- refire of a page we already processed; wait for the real next page
	end

	if (Atr_FullScanProcessPage()) then
		Atr_FullScanFinish();
	else
		gFS_pstate = "prequery";
	end
end

-- Process one page of the full scan into the cross-page accumulators.
-- Returns true when this was the last page (fewer than 50 rows, or we've hit
-- the dup-page guard) so the caller can finalize.
function Atr_FullScanProcessPage()

	local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");

	if (totalAuctions >= 50) then
		local totalPages = ceil (totalAuctions / 50);
		Atr_FullScanStatus:SetText (string.format (ZT("Scanning auctions: page %d of %d"), gFS_current_page, totalPages));
	end

	local x;

	for x = 1, numBatchAuctions do

		local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", x);

		-- `name` can be nil when a row's item data hasn't resolved from the
		-- client cache yet; skip those rows rather than keying tables on nil.
		if (name ~= nil) then

			gFS_qualities[name] = quality;

			if (buyoutPrice ~= nil and count and count > 0) then

				local itemPrice = math.floor (buyoutPrice / count);

				if (itemPrice > 0) then
					if (not gFS_lowprices[name]) then
						gFS_lowprices[name] = {BIGNUM,BIGNUM,BIGNUM};		-- one extra for later
					end

					Atr_AddToLowPrices (gFS_lowprices[name], itemPrice);
				end
			end
		end
	end

	if (Atr_CheckForBargain and numBatchAuctions > 0) then
		for x = 1, numBatchAuctions do
			Atr_CheckForBargain (x);
		end
	end

	gFS_numScanned = gFS_numScanned + numBatchAuctions;

	-- A short page is the last page. The dup-page guard mirrors the main
	-- search: if we somehow keep getting the same page, stop rather than loop.
	return (numBatchAuctions < 50) or (gFS_query.numDupPages > 10);
end

-- Fold the accumulated per-page prices into the scan DB and show the summary.
function Atr_FullScanFinish()

	gAtr_FullScanState = ATR_FS_ANALYZING;

	Atr_FullScanStatus:SetText (ZT("Processing"));

	zc.md ("FULL SCAN: "..gFS_numScanned.." auctions scanned")

	local numEachQual = {0, 0, 0, 0, 0, 0, 0, 0, 0};
	local totalItems = 0;
	local numRemoved = { 0, 0, 0, 0, 0, 0, 0, 0 };

	for name,prices in pairs (gFS_lowprices) do

		local newprice = Atr_CalcNewDBprice (name, prices);

		if (newprice > 0) then

			local qx = gFS_qualities[name] + 1;

			numEachQual[qx]	= numEachQual[qx] + 1;
			totalItems		= totalItems + 1;

			if (qx < AUCTIONATOR_SCAN_MINLEVEL and gAtr_ScanDB[name]) then
				numRemoved[qx] = numRemoved[qx] + 1;
				gAtr_ScanDB[name] = nil;
				zc.md ("removed: |cffbbbbbb", name, "   ("..qx..")");
			end

			if (qx >= AUCTIONATOR_SCAN_MINLEVEL) then

				if (gAtr_ScanDB[name] == nil) then
					gNumAdded = gNumAdded + 1;
				else
					gNumUpdated = gNumUpdated + 1;
				end

				gAtr_ScanDB[name] = newprice;
			end
		end
	end

	gScanDetails.numBatchAuctions		= gFS_numScanned;
	gScanDetails.totalItems				= totalItems;
	gScanDetails.numEachQual			= numEachQual;
	gScanDetails.numRemoved				= numRemoved;
	gScanDetails.gNumAdded				= gNumAdded;
	gScanDetails.gNumUpdated			= gNumUpdated;

	if (Atr_PrintBargains) then
		Atr_PrintBargains();
	end

	gAtr_FullScanState = ATR_FS_CLEANING_UP;

	Atr_FullScanMoreDetails();

	Atr_FullScanStatus:SetText (ZT("Cleaning up"));

	Atr_FullScanStartButton:Enable();
	Atr_FullScanDone:Enable();
	Atr_FullScanStatus:SetText ("");

	Atr_FSR_scanned_count:SetText	(gFS_numScanned);
	Atr_FSR_added_count:SetText		(gNumAdded);
	Atr_FSR_updated_count:SetText	(gNumUpdated);
	Atr_FSR_ignored_count:SetText	(totalItems - (gNumAdded + gNumUpdated));

	Atr_FullScanHTML:Hide();
	Atr_FullScanResults:Show();

	Atr_FullScanResults:SetBackdropColor (0.3, 0.3, 0.4);

	AUCTIONATOR_LAST_SCAN_TIME = time();

	Atr_UpdateFullScanFrame ();

	Atr_ClearBrowseListings();

	gFS_lowprices = {};
	gFS_qualities = {};
	collectgarbage ("collect");
end

-----------------------------------------

function auctionator_AuctionFrameBrowse_Update ()

	return auctionator_orig_AuctionFrameBrowse_Update ();

end

-----------------------------------------

function Atr_ShowFullScanFrame()

	Atr_FullScanHTML:Show();
	Atr_FullScanResults:Hide();

	Atr_FullScanFrame:Show();
	Atr_FullScanFrame:SetBackdropColor(0,0,0,100);
	
	Atr_UpdateFullScanFrame();
	Atr_FullScanStatus:SetText ("");

	local expText = "<html><body>"
					.."<p>"
					..ZT("Scanning is entirely optional.")
					.."<br/><br/>"
					..ZT("SCAN_EXPLANATION")
					.."</p>"
					.."</body></html>"
					;



	Atr_FullScanHTML:SetText (expText);
	Atr_FullScanHTML:SetSpacing (3);
end

-----------------------------------------

function Atr_UpdateFullScanFrame()

	Atr_FullScanDBsize:SetText (Atr_GetDBsize());
	
	if (AUCTIONATOR_LAST_SCAN_TIME) then
		Atr_FullScanDBwhen:SetText (date ("%A, %B %d at %I:%M %p", AUCTIONATOR_LAST_SCAN_TIME));
	else
		Atr_FullScanDBwhen:SetText (ZT("Never"));
	end

	-- Page-based full scan gates on the ordinary query throttle. There is no
	-- 15-minute getAll cooldown on 1.12, so the button is available whenever the
	-- client will accept a query; it's only briefly disabled while one is in flight.
	local canQuery = CanSendAuctionQuery();

	Atr_FullScanNext:SetText (ZT("Now"));

	if (canQuery) then
		Atr_FullScanStatus:SetText ("");
		Atr_FullScanStartButton:Enable();
	else
		Atr_FullScanStartButton:Disable();
	end
end

-----------------------------------------

function Atr_FullScanFrameIdle()

	if (gAtr_FullScanState == ATR_FS_CLEANING_UP) then
	
		Atr_FullScanStatus:SetText ("Cleaning up");
		
		if (GetNumAuctionItems("list") < 100) then
		
			Atr_FullScanStatus:SetText (ZT("Scan complete"));
			PlaySound("AuctionWindowClose");
			
			gAtr_FullScanState = ATR_FS_NULL;
		end
	
	end
	
	if (gAtr_FullScanState == ATR_FS_STARTED) then

		------- drive paging: send the next page when the client will accept a query -------
		if (gFS_pstate == "prequery") then
			Atr_FullScanContinue();
		elseif (gFS_pstate == "postquery" and gFS_query_sent_when
				and (gAtr_ptime - gFS_query_sent_when) > 5) then
			-- Page result never arrived (dropped packet); re-query the page we're
			-- waiting on rather than hanging. Mirrors the main-search safety net.
			gFS_current_page	= gFS_current_page - 1;
			gFS_pstate			= "prequery";
		end

		local btext = Atr_FullScanStatus:GetText ();

		if (btext) then
			if (string.len (btext) > 25) then
				Atr_FullScanStatus:SetText (ZT("Scanning")..".");
			else
				Atr_FullScanStatus:SetText (btext..".");
			end
		end
	end

end







