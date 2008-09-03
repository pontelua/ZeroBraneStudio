------------
-- API

local function newAPI()
	return {
		-- tool tip info and reserved names
		tip = {
			staticnames = {},
			keys = {},
			finfo = {},
			finfoclass = {},
		},
		-- autocomplete hierarchy
		ac = {
			childs = {},
		},
	}
end


local apis = {
	none = newAPI(),
	lua = newAPI(),
}


function GetApi(apitype)
	return apis[apitype] or apis["none"]
end

----------
-- API loading

local function key ()
	return {type="keyword"}
end

local function fn (description) 
	local description2,returns,args = description:match("(.+)%-%s*(%b())%s*(%b())")
	if not description2 then
		return {type="function",description=description,
			returns="(?)"} 
	end
	return {type="function",description=description2,
		returns=returns:gsub("^%s+",""):gsub("%s+$",""), args = args} 
end

local function val (description)
	return {type="value",description = description}
end



function addAPI(apifile) -- relative to API directory
	local ftype = apifile:match("api[/\\]([^/\\]+)")
	if not ftype then
		print("The API file must be located in a subdirectory of the API directory\n")
		return
	end
	local fn,err = loadfile(apifile)
	if err then
		print("API file '"..apifile.."' could not be loaded: "..err.."\n")
		return
	end
	local env = apis[ftype] or newAPI()
	apis[ftype] = env
	env = env.ac.childs
	setfenv(fn,env)
	xpcall(function()fn(env)end, function(err)
		DisplayOutput("Error while loading API file: "..apifile..":\n")
		DisplayOutput(debug.traceback(err))
		DisplayOutput("\n")
	end)
end

function loadallAPIs ()
	for i,dir in ipairs(FileSysGet(".\\api\\*.*",wx.wxDIR)) do
		local files = FileSysGet(dir.."\\*.*",wx.wxFILE)
		for i,file in ipairs(files) do
			if file:match "%.lua$" then
				addAPI(file)
			end
		end
	end
end
loadallAPIs()



-- Lua wx specific
do 
	apis.lua.ac.childs.wx = {
		type = "lib",
		description = "WX lib",
		childs = {}
	}
	
	local wxchilds = apis.lua.ac.childs.wx.childs
	for key in pairs(wx) do
		wxchilds[key] = {
			type = "function",
			description = "unknown",
			returns = "unknown",
		}
	end
	
end

---------
-- ToolTip and reserved words list

local function fillTips(api,apibasename)
	local apiac = api.ac
	local tclass = api.tip

	tclass.staticnames = {}
	tclass.keys = {}
	tclass.finfo = {}
	tclass.finfoclass = {}
	
	local staticnames = tclass.staticnames
	local keys = tclass.keys
	local finfo = tclass.finfo
	local finfoclass = tclass.finfoclass
	
	local function traverse (tab,libname)
		if not tab.childs then return end
		for key,info in pairs(tab.childs) do
			traverse(info,key)
			if info.type == "function" then
				local inf = (info.returns or "(?)").." "..libname.."."..key.." "..(info.args or "(?)").."\n"..
					info.description:gsub("("..("."):rep(60)..".-[%s,%)%]:%.])","%1\n")
				
				-- add to infoclass 
				if not finfoclass[libname] then finfoclass[libname] = {} end
				finfoclass[libname][key] = inf
				
				-- add to info
				if not finfo[key] or #finfo[key]<200 then 
					if finfo[key] then finfo[key] = finfo[key] .. "\n\n" --DisplayOutput("twice: func "..key.."\n")
					else finfo[key] = "" end
					finfo[key] = finfo[key] .. inf
				elseif not finfo[key]:match("\n %(%.%.%.%)$") then
					finfo[key] = finfo[key].."\n (...)"
				end
			end
			if info.type == "keyword" then
				keys[key] = true
			end
			staticnames[key] = true
		end
	end
	traverse(apiac,apibasename)
end

fillTips(apis.lua,"luabase")


function GetTipInfo (api,caller,class)
	local tip = api.tip
	return (class and tip.finfoclass[class]) and tip.finfoclass[class][caller] or tip.finfo[caller]
end

-------------
-- Dynamic Words

local dywordentries = {}
local dynamicwords = {}
function AddDynamicWord (api,word )
	if api.tip.staticnames[word] then return end
	if dywordentries[word] then return end
	dywordentries[word] = word
	for i=0,#word do 
		local k = word : sub (1,i)
		dynamicwords[k] = dynamicwords[k] or {}
		table.insert(dynamicwords[k], word)
	end
end
function removeDynamicWord (word)
	if not dywordentries[word] then return end
	dywordentries[word] = nil
	for i=0,#word do 
		local k = word : sub (1,i) : lower()
		if not dynamicwords[k] then break end
		for i=1,#dynamicwords[k] do
			if dynamicwords[i] == word then
				table.remove(dynamicwords,i)
				break
			end
		end
	end
end
function purgeDynamicWordlist ()
	dywordentries = {}
	dynamicwords = {}
end
function AddDynamicWords (editor)
	local api = editor.api
	local content = editor:GetText()

	-- TODO check if inside comment
	for word in content:gmatch "[a-zA-Z_0-9]+" do
		AddDynamicWord(api,word)
	end
end


------------
-- Final Autocomplete

local cache = {}
local function buildcache(childs)
	if cache[childs] then return cache[childs] end
	--DisplayOutput("1> build cache\n")
	cache[childs] = {}
	local t = cache[childs]
	
	for key, info in pairs(childs) do
		local kl = key:lower()
		for i=0,#key do 
			local k = kl:sub(1,i)
			t[k] = t[k] or {}
			t[k][#t[k]+1] = key
		end
	end
	
	return t
end

-- make syntype dependent
function CreateAutoCompList(api,key) -- much faster than iterating the wx. table
	--DisplayOutput(key_.."\n")
	local tip = api.tip
	local ac = api.ac
	
	-- ignore keywords
	if tip.keys[key] then return end
	
	-- search in api autocomplete list
	-- track recursion depth
	local depth = 0
	
	local function findtab (rest,tab)
		local key,krest = rest:match("([a-zA-Z0-9_]+)(.*)")
		
		-- DisplayOutput("2> "..rest.." : "..(key or "nil").." : "..tostring(krest).."\n")
	
		-- check if we can go down hierarchy
		if krest and #(krest:gsub("[%s]",""))>0 and tab.childs and tab.childs[key] then 
			depth = depth + 1
			return findtab(krest,tab.childs[key]) 
		end
		
		return tab,rest:gsub("[^a-zA-Z0-9_]","")
	end
	local tab,rest = findtab (key,ac)
	if not tab or not tab.childs then return end

	-- final list (cached)
	local complete = buildcache(tab.childs)

	local last = key : match "([a-zA-Z0-9_]+)%s*$"

	-- build dynamic word list 
	-- only if api search couldnt descend
	-- ie we couldnt find matching sub items
	local dw = ""
	if (depth < 1) then
		if dynamicwords[last] then
			local list = dynamicwords[last]
			table.sort(list,function(a,b)
				local ma,mb = a:sub(1,#last)==last, b:sub(1,#last)==last
				if (ma and mb) or (not ma and not mb) then return a<b end
				return ma
			end)
			dw = " " .. table.concat(list," ")
		end
	end
	
	local compstr = ""
	if complete and complete[rest:lower()] then
		local list = complete[rest:lower()]
		table.sort(list,function(a,b)
			local ma,mb = a:sub(1,#rest)==last, b:sub(1,#rest)==rest
			if (ma and mb) or (not ma and not mb) then return a<b end
			return ma
		end)
		compstr = table.concat(list," ")
	end
	
	-- concat final, list complete first
--	DisplayOutput("1> "..(rest or "").."- "..tostring(dw).."\n")
	return compstr .. dw

end