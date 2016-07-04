--[[
Lua hot update for lua5.3.
Update functions and keep data.
From https://github.com/asqbtcupid/lua_hotupdate
--]]

local HU = {
	ModuleNameOfUpdateList = "",
	OldCode = { },
	ChangedFuncList = { },
	VisitedSig = { },

	FakeENV = nil,
	ENV = nil,
	NewFakeT = nil,  -- Create a fake table.
}

-- The app can change these notify functions:
--    HU.InfoNotify = function(msg) log_info(msg) end
function HU.FailNotify(MsgStr)
end
function HU.InfoNotify(MsgStr)
end
function HU.DebugNotify(MsgStr)
end

-- Init HU.NewFakeT
function HU.InitFakeTblCreator()
	local meta = { }
	HU.Meta = meta  -- HU.Meta is in HU.Protection.
	local function NewFakeT() return setmetatable( { }, meta) end
	local function EmptyFunc() end
	local function pairs() return EmptyFunc end
	local function setmetatable(t, metaT)
		HU.MetaMap[t] = metaT
		return t
	end
	local function require(LuaPath)
		if not HU.RequireMap[LuaPath] then
			local FakeTable = NewFakeT()
			HU.RequireMap[LuaPath] = FakeTable
		end
		return HU.RequireMap[LuaPath]
	end
	function meta.__index(t, k)
		if k == "setmetatable" then
			return setmetatable
		elseif k == "pairs" or k == "ipairs" then
			return pairs
		elseif k == "next" then
			return EmptyFunc
		elseif k == "require" then
			return require
		elseif k == "table" then
			return table
		elseif k == "string" then
			return string
		elseif k == "math" then
			return math
		else
			local FakeTable = NewFakeT()
			rawset(t, k, FakeTable)
			return FakeTable
		end
	end
	function meta.__newindex(t, k, v) rawset(t, k, v) end
	function meta.__call() return NewFakeT(), NewFakeT(), NewFakeT() end
	function meta.__add() return meta.__call() end
	function meta.__sub() return meta.__call() end
	function meta.__mul() return meta.__call() end
	function meta.__div() return meta.__call() end
	function meta.__mod() return meta.__call() end
	function meta.__pow() return meta.__call() end
	function meta.__unm() return meta.__call() end

	-- No in lua5.1:
	function meta.__idiv() return meta.__call() end
	function meta.__band() return meta.__call() end
	function meta.__bor() return meta.__call() end
	function meta.__bxor() return meta.__call() end
	function meta.__bnot() return meta.__call() end
	function meta.__shl() return meta.__call() end
	function meta.__shr() return meta.__call() end

	function meta.__concat() return meta.__call() end
	function meta.__eq() return meta.__call() end
	function meta.__lt() return meta.__call() end
	function meta.__le() return meta.__call() end
	function meta.__len() return meta.__call() end
	HU.NewFakeT = NewFakeT
end

function HU.InitProtection()
	HU.Protection = { }
	HU.Protection[setmetatable] = true
	HU.Protection[pairs] = true
	HU.Protection[ipairs] = true
	HU.Protection[next] = true
	HU.Protection[require] = true
	HU.Protection[HU] = true
	HU.Protection[HU.Meta] = true
	HU.Protection[math] = true
	HU.Protection[string] = true
	HU.Protection[table] = true
end

function HU.Reload(ModuleName)
	package.loaded[ModuleName] = nil
	return require(ModuleName)
end

function HU.ErrorHandle(e)
	HU.FailNotify("HotUpdate error: " .. tostring(e))
	HU.ErrorHappen = true
end

function HU.BuildNewCode(SysPath, LuaPath)
	io.input(SysPath)
	local NewCode = io.read("*all")
	io.input():close()
	if HU.OldCode[SysPath] == NewCode then
		return false
	end
	HU.InfoNotify("Update: " .. LuaPath .. " -> " .. SysPath)
	local chunk = "--[[" .. LuaPath .. "]] " .. NewCode
	local FakeENV = HU.NewFakeT()
	local NewFunction = load(chunk, LuaPath, 't', FakeENV)  -- Lua5.2+
	if not NewFunction then
		HU.FailNotify(SysPath .. " has syntax error.")
		collectgarbage("collect")
		return false
	end

	HU.FakeENV = FakeENV
	HU.MetaMap = { }
	HU.RequireMap = { }
	local NewObject
	HU.ErrorHappen = false
	xpcall( function() NewObject = NewFunction() end, HU.ErrorHandle)
	if not HU.ErrorHappen then
		HU.OldCode[SysPath] = NewCode
		return true, NewObject
	else
		collectgarbage("collect")
		return false
	end
end

function HU.Travel_G()
	local visited = { }
	visited[HU] = true
	local function f(t)
		if (type(t) ~= "function" and type(t) ~= "table") or visited[t] or HU.Protection[t] then return end
		visited[t] = true
		if type(t) == "function" then
			for i = 1, math.huge do
				local name, value = debug.getupvalue(t, i)
				if not name then break end
				if type(value) == "function" then
					for _, funcs in ipairs(HU.ChangedFuncList) do
						if value == funcs[1] then
							debug.setupvalue(t, i, funcs[2])
						end
					end
				end
				f(value)
			end
		elseif type(t) == "table" then
			f(debug.getmetatable(t))
			for k, v in pairs(t) do
				f(k); f(v);
				if type(v) == "function" or type(k) == "function" then
					for _, funcs in ipairs(HU.ChangedFuncList) do
						if v == funcs[1] then t[k] = funcs[2] end
						if k == funcs[1] then t[funcs[2]] = t[k]; t[k] = nil end
					end
				end
			end
		end
	end

	f(_G)
	local registryTable = debug.getregistry()
	for _, funcs in ipairs(HU.ChangedFuncList) do
		for k, v in pairs(registryTable) do
			if v == funcs[1] then
				registryTable[k] = funcs[2]
			end
		end
	end
	for _, funcs in ipairs(HU.ChangedFuncList) do
		if funcs[3] == "HUDebug" then funcs[4]:HUDebug() end
	end
end

function HU.ReplaceOld(OldObject, NewObject, LuaPath, From, Deepth)
	if type(OldObject) == type(NewObject) then
		if type(NewObject) == "table" then
			HU.UpdateAllFunction(OldObject, NewObject, LuaPath, From, "")
		elseif type(NewObject) == "function" then
			HU.UpdateOneFunction(OldObject, NewObject, LuaPath, nil, From, "")
		end
	end
end

function HU.HotUpdateCode(LuaPath, SysPath)
	local OldObject = package.loaded[LuaPath]
	if OldObject ~= nil then
		HU.VisitedSig = { }
		HU.ChangedFuncList = { }
		local Success, NewObject = HU.BuildNewCode(SysPath, LuaPath)
		if Success then
			HU.ReplaceOld(OldObject, NewObject, LuaPath, "Main", "")
			for LuaPath, NewObject in pairs(HU.RequireMap) do
				local OldObject = package.loaded[LuaPath]
				HU.ReplaceOld(OldObject, NewObject, LuaPath, "Main_require", "")
			end
			setmetatable(HU.FakeENV, nil)
			HU.UpdateAllFunction(HU.ENV, HU.FakeENV, "ENV", "Main", "")
			if #HU.ChangedFuncList > 0 then
				HU.Travel_G()
			end
			collectgarbage("collect")
		end
	elseif HU.OldCode[SysPath] == nil then
		io.input(SysPath)
		HU.OldCode[SysPath] = io.read("*all")
		io.input():close()
	end
end

function HU.Debug(Deepth, HUFunName, Name, From)
	HU.DebugNotify(string.format("%s%s name:%s from:%s",
		Deepth, HUFunName, Name, From))
end  -- FormatDebugMsg()

function HU.ResetENV(object, name, From, Deepth)
	local visited = { }
	local function f(object, name, From, Deepth)
		if not object or visited[object] then return end
		visited[object] = true
		HU.Debug(Deepth, "HU.ResetENV", name, From)
		if type(object) == "function" then
			-- xpcall( function() setfenv(object, HU.ENV) end, HU.FailNotify)
		elseif type(object) == "table" then
			for k, v in pairs(object) do
				f(k, tostring(k) .. "__key", "HU.ResetENV", Deepth .. "    ")
				f(v, tostring(k), "HU.ResetENV", Deepth .. "    ")
			end
		end
	end
	f(object, name, From, Deepth)
end

-- Get upvalues of OldFunction and update those of NewFunction.
function HU.UpdateUpvalue(OldFunction, NewFunction, Name, From, Deepth)
	assert("function" == type(OldFunction))
	assert("function" == type(NewFunction))
	HU.Debug(Deepth, "HU.UpdateUpvalue", Name, From)
	local OldUpvalueMap = { }
	local OldExistName = { }
	for i = 1, math.huge do
		local name, value = debug.getupvalue(OldFunction, i)
		if not name then break end
		OldUpvalueMap[name] = value
		OldExistName[name] = true
	end
	for i = 1, math.huge do
		local name, value = debug.getupvalue(NewFunction, i)
		if not name then break end
		if OldExistName[name] then
			local OldValue = OldUpvalueMap[name]
			if type(OldValue) ~= type(value) then
				debug.setupvalue(NewFunction, i, OldValue)
			elseif type(OldValue) == "function" then
				HU.UpdateOneFunction(OldValue, value, name, nil, "HU.UpdateUpvalue", Deepth .. "    ")
			elseif type(OldValue) == "table" then
				HU.UpdateAllFunction(OldValue, value, name, "HU.UpdateUpvalue", Deepth .. "    ")
				debug.setupvalue(NewFunction, i, OldValue)
			else
				debug.setupvalue(NewFunction, i, OldValue)
			end
		else
			HU.ResetENV(value, name, "HU.UpdateUpvalue", Deepth .. "    ")
		end
	end
end 

function HU.UpdateOneFunction(OldFunction, NewFunction, FuncName, OldTable, From, Deepth)
	assert("function" == type(OldFunction))
	assert("function" == type(NewFunction))
	if HU.Protection[OldFunction] or HU.Protection[NewFunction] then return end
	if OldFunction == NewFunction then return end
	local signature = tostring(OldFunction) .. tostring(NewFunction)
	if HU.VisitedSig[signature] then return end
	HU.VisitedSig[signature] = true
	HU.Debug(Deepth, "HU.UpdateOneFunction", FuncName, From)
	-- if pcall(debug.setfenv, NewFunction, getfenv(OldFunction)) then
		HU.UpdateUpvalue(OldFunction, NewFunction, FuncName, "HU.UpdateOneFunction", Deepth .. "    ")
		HU.ChangedFuncList[#HU.ChangedFuncList + 1] = { OldFunction, NewFunction, FuncName, OldTable }
	-- end
end

function HU.UpdateAllFunction(OldTable, NewTable, Name, From, Deepth)
	if HU.Protection[OldTable] or HU.Protection[NewTable] then return end
	if OldTable == NewTable then return end
	local signature = tostring(OldTable) .. tostring(NewTable)
	if HU.VisitedSig[signature] then return end
	HU.VisitedSig[signature] = true
	HU.Debug(Deepth, "HU.UpdateAllFunction", Name, From)
	for ElementName, Element in pairs(NewTable) do
		local OldElement = OldTable[ElementName]
		if type(Element) == type(OldElement) then
			if type(Element) == "function" then
				HU.UpdateOneFunction(OldElement, Element, ElementName, OldTable, "HU.UpdateAllFunction", Deepth .. "    ")
			elseif type(Element) == "table" then
				HU.UpdateAllFunction(OldElement, Element, ElementName, "HU.UpdateAllFunction", Deepth .. "    ")
			end
		elseif OldElement == nil and type(Element) == "function" then
			-- if pcall(setfenv, Element, HU.ENV) then
				OldTable[ElementName] = Element
			-- end
		end
	end
	local OldMeta = debug.getmetatable(OldTable)
	local NewMeta = HU.MetaMap[NewTable]
	if type(OldMeta) == "table" and type(NewMeta) == "table" then
		HU.UpdateAllFunction(OldMeta, NewMeta, Name .. "'s Meta", "HU.UpdateAllFunction", Deepth .. "    ")
	end
end

-- ModuleNameOfUpdateList is the module name that returns the hot update list.
function HU.Init(ModuleNameOfUpdateList, ENV)
	assert("string" == type(ModuleNameOfUpdateList))
	assert("table" == type(require(ModuleNameOfUpdateList)))

	HU.ModuleNameOfUpdateList = ModuleNameOfUpdateList
	HU.ENV = ENV or _G
	HU.InitFakeTblCreator()
	HU.InitProtection()
end

function HU.Update()
	HU.DebugNotify("Update()")
	local UpdateModuleNames = HU.Reload(HU.ModuleNameOfUpdateList)
	local Path = package.path .. ";" .. package.cpath
	for _, ModuleName in pairs(UpdateModuleNames) do
		local SysPath, ErrMsg = package.searchpath(ModuleName, Path)
		if SysPath then
			HU.HotUpdateCode(ModuleName, SysPath)
		else
			HU.DebugNotify(ErrMsg)
		end
	end
end

return HU
