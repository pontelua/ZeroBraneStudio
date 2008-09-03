local frame    = ide.frame
local menuBar  = frame.menuBar

local openDocuments = ide.openDocuments

--[=[
-- tool definition
-- main entries are optional
tool = {
	fnmenu = function(frame,menubar),	
		-- can be used for init
		-- and custom menu
	exec = {
		-- quick exec action
		name = "",
		description = "",
		fn = function(wxfilename,projectdir),
	}
}

]=]


local toolArgs = {{},}


-- fill in tools that have a automatic execution
-- function
do
	local cnt = 1
	local maxcnt = 10
	
	-- todo config specifc ignore/priority list
	for name,tool in pairs(ide.tools) do
		local exec = tool.exec
		if (exec and cnt < maxcnt and exec.name and exec.fn and exec.description) then
			local id = ID("tools.exec."..name)
			table.insert(toolArgs,{id , exec.name.."\tCtrl-"..cnt, exec.description})
			-- flag it
			tool._execid = id
			cnt = cnt + 1
		end
	end
end

-- Build Menu
local toolMenu = wx.wxMenu{
		unpack(toolArgs)
	}
menuBar:Append(toolMenu, "&Tools")


-- connect auto execs
do
	for name,tool in pairs(ide.tools) do
		if (tool._execid) then
			frame:Connect(tool._execid, wx.wxEVT_COMMAND_MENU_SELECTED,
			function (event)
				local editor = GetEditor()
				if (not editor) then return end
				
				local id       = editor:GetId()
				local saved    = false
				local fn       = wx.wxFileName(openDocuments[id].filePath or "")
				fn:Normalize() 
				
				tool.exec.fn(fn,ide.config.path.projectdir)
				
				return true
			end)
		end
	end
end


-- Generate Custom Menus/Init
for name,tool in pairs(ide.tools) do
	if (tool.fninit) then
		tool.fninit(frame,menuBar)
	end
end