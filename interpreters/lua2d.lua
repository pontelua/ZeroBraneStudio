local lua2d
local win = ide.osname == "Windows"

return {
  name = "Lua2D",
  description = "Lua2D mobile platform",
  api = {"baselib", "lua2d"},
  frun = function(self,wfilename,rundebug)
    lua2d = lua2d or ide.config.path.lua2d -- check if the path is configured
    if not lua2d then
      local sep = win and ';' or ':'
      local default =
           win and ([[C:\Program Files\Lua2D]]..sep..[[D:\Program Files\Lua2D]]..sep)
        or ''
      local path = default
                 ..(os.getenv('PATH') or '')..sep
                 ..(os.getenv('LUA2D_BIN') or '')..sep
                 ..(os.getenv('HOME') and os.getenv('HOME') .. '/bin' or '')
      local paths = {}
      for p in path:gmatch("[^"..sep.."]+") do
        lua2d = lua2d or GetFullPathIfExists(p, win and 'Lua2D.exe' or 'Lua2D')
        table.insert(paths, p)
      end
      if not lua2d then
        DisplayOutput("Can't find lua2d executable in any of the folders in PATH or LUA2D_BIN: "
          ..table.concat(paths, ", ").."\n")
        return
      end
    end

    local file
    local epoints = ide.config.lua2d and ide.config.lua2d.entrypoints
    if epoints then
      epoints = type(epoints) == 'table' and epoints or {epoints}
      for _,entry in pairs(epoints) do
        file = GetFullPathIfExists(self:fworkdir(wfilename), entry)
        if file then break end
      end
      if not file then
        DisplayOutput("Can't find any of the specified entry points ("
          ..table.concat(epoints, ", ")
          ..") in the current project; continuing with the current file...\n")
      end
    end

    if rundebug then
      -- start running the application right away
      DebuggerAttachDefault({runstart=true, startwith = file})
      local code = (
[[xpcall(function() 
    io.stdout:setvbuf('no')
    require("mobdebug").moai() -- enable debugging for coroutines
    %s
  end, function(err) print(debug.traceback(err)) end)]]):format(rundebug)
      local tmpfile = wx.wxFileName()
      tmpfile:AssignTempFileName(".")
      file = tmpfile:GetFullPath()
      local f = io.open(file, "w")
      if not f then
        DisplayOutput("Can't open temporary file '"..file.."' for writing\n")
        return 
      end
      f:write(code)
      f:close()
    end

    file = file or wfilename:GetFullPath()

    -- try to find a config file: (1) LUA2D_CONFIG, (2) project directory,
    -- (3) folder with the current file, (4) folder with lua2d executable
    local config = GetFullPathIfExists(os.getenv('LUA2D_CONFIG') or self:fworkdir(wfilename), 'config.lua')
      or GetFullPathIfExists(wfilename:GetPath(wx.wxPATH_GET_VOLUME), 'config.lua')
      or GetFullPathIfExists(wx.wxFileName(lua2d):GetPath(wx.wxPATH_GET_VOLUME), 'config.lua')
    local cmd = config and ('"%s" "%s" "%s"'):format(lua2d, config, file)
      or ('"%s" "%s"'):format(lua2d, file)
    -- CommandLineRun(cmd,wdir,tooutput,nohide,stringcallback,uid,endcallback)
    return CommandLineRun(cmd,self:fworkdir(wfilename),true,false,nil,nil,
      function() ide.debugger.pid = nil if rundebug then wx.wxRemoveFile(file) end end)
  end,
  fprojdir = function(self,wfilename)
    return wfilename:GetPath(wx.wxPATH_GET_VOLUME)
  end,
  fworkdir = function(self,wfilename)
    return ide.config.path.projectdir or wfilename:GetPath(wx.wxPATH_GET_VOLUME)
  end,
  hasdebugger = true,
  fattachdebug = function(self) DebuggerAttachDefault() end,
}
