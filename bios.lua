print("CBios v1.0.0")
print("CrfOS v1.7.4")
print("Node "..tostring(njs.host_emu_version()))
print("OpenSSL v"..tostring(njs.host_openssl_version()))

local nativesetfenv = setfenv
local nativeprint = print
local nativegetfenv = getfenv

-- Prevent access to metatables or environments of strings, as these are global between all computers
do
    local nativegetmetatable = getmetatable
    local nativeerror = error
    local nativetype = type
    local string_metatable = nativegetmetatable("")
    function getmetatable( t )
        local mt = nativegetmetatable( t )
        if mt == string_metatable then
            nativeerror( "Attempt to access string metatable", 2 )
        else
            return mt
        end
    end
end

-- Install lua parts of the os api
function os.version()
    return "CraftOS 1.7"
end

function os.pullEventRaw( sFilter )
    return coroutine.yield( sFilter )
end

function os.pullEvent( sFilter )
    local eventData = { os.pullEventRaw( sFilter ) }
    if eventData[1] == "terminate" then
        error( "Terminated", 0 )
    end
    return table.unpack( eventData )
end

-- Install globals
function sleep( nTime )
    local timer = os.startTimer( nTime or 0 )
    repeat
        local sEvent, param = os.pullEvent( "timer" )
    until param == timer
end

function write( sText )
  njs.write(sText)
end

function print( ... )
  local tArgs = { ... }

  if tArgs[0] == nil then
    nativeprint()
  else
    nativeprint(...)
  end
end

function printError( ... )
    print( ... )
end

function read( _sReplaceChar, _tHistory, _fnComplete )
    sLine = njs.read()

    return sLine
end

loadfile = function( _sFile, _tEnv )
    local file = fs.open( _sFile, "r" )
    if file then
        local func, err = load( file.readAll(), fs.getName( _sFile ), "t", _tEnv )
        file.close()
        return func, err
    end
    return nil, "File not found"
end

-- Install the rest of the OS api
function os.run( _tEnv, _sPath, ... )
    local tArgs = { ... }
    local tEnv = _tEnv
    setmetatable( tEnv, { __index = _G } )
    local fnFile, err = loadfile( _sPath, tEnv )
    if fnFile then
        local ok, err = pcall( function()
            fnFile( table.unpack( tArgs ) )
        end )
        if not ok then
            if err and err ~= "" then
                printError( err )
            end
            return false
        end
        return true
    end
    if err and err ~= "" then
        printError( err )
    end
    return false
end

local tAPIsLoading = {}
function os.loadAPI( _sPath )
    local sName = fs.getName( _sPath )
    if tAPIsLoading[sName] == true then
        printError( "API "..sName.." is already being loaded" )
        return false
    end
    tAPIsLoading[sName] = true

    local tEnv = {}
    setmetatable( tEnv, { __index = _G } )
    local fnAPI, err = loadfile( _sPath, tEnv )
    if fnAPI then
        local ok, err = pcall( fnAPI )
        if not ok then
            printError( err )
            tAPIsLoading[sName] = nil
            return false
        end
    else
        printError( err )
        tAPIsLoading[sName] = nil
        return false
    end

    local tAPI = {}
    for k,v in pairs( tEnv ) do
        if k ~= "_ENV" then
            tAPI[k] =  v
        end
    end

    _G[sName] = tAPI
    tAPIsLoading[sName] = nil
    return true
end

function os.unloadAPI( _sName )
    if _sName ~= "_G" and type(_G[_sName]) == "table" then
        _G[_sName] = nil
    end
end

function os.sleep( nTime )
    sleep( nTime )
end

-- Install the lua part of the HTTP api (if enabled)
if http then
    local nativeHTTPRequest = http.request

    local function wrapRequest( _url, _post, _headers )
        local ok, err = nativeHTTPRequest( _url, _post, _headers )
        if ok then
            while true do
                local event, param1, param2 = os.pullEvent()
                if event == "http_success" and param1 == _url then
                    return param2
                elseif event == "http_failure" and param1 == _url then
                    return nil, param2
                end
            end
        end
        return nil, err
    end

    http.get = function( _url, _headers )
        return wrapRequest( _url, nil, _headers )
    end

    http.post = function( _url, _post, _headers )
        return wrapRequest( _url, _post or "", _headers )
    end

    http.request = function( _url, _post, _headers )
        local ok, err = nativeHTTPRequest( _url, _post, _headers )
        if not ok then
            os.queueEvent( "http_failure", _url, err )
        end
        return ok, err
    end
end

-- Install the lua part of the FS api
local tEmpty = {}
function fs.complete( sPath, sLocation, bIncludeFiles, bIncludeDirs )
    bIncludeFiles = (bIncludeFiles ~= false)
    bIncludeDirs = (bIncludeDirs ~= false)
    local sDir = sLocation
    local nStart = 1
    local nSlash = string.find( sPath, "[/\\]", nStart )
    if nSlash == 1 then
        sDir = ""
        nStart = 2
    end
    local sName
    while not sName do
        local nSlash = string.find( sPath, "[/\\]", nStart )
        if nSlash then
            local sPart = string.sub( sPath, nStart, nSlash - 1 )
            sDir = fs.combine( sDir, sPart )
            nStart = nSlash + 1
        else
            sName = string.sub( sPath, nStart )
        end
    end

    if fs.isDir( sDir ) then
        local tResults = {}
        if bIncludeDirs and sPath == "" then
            table.insert( tResults, "." )
        end
        if sDir ~= "" then
            if sPath == "" then
                table.insert( tResults, (bIncludeDirs and "..") or "../" )
            elseif sPath == "." then
                table.insert( tResults, (bIncludeDirs and ".") or "./" )
            end
        end
        local tFiles = fs.list( sDir )
        for n=1,#tFiles do
            local sFile = tFiles[n]
            if #sFile >= #sName and string.sub( sFile, 1, #sName ) == sName then
                local bIsDir = fs.isDir( fs.combine( sDir, sFile ) )
                local sResult = string.sub( sFile, #sName + 1 )
                if bIsDir then
                    table.insert( tResults, sResult .. "/" )
                    if bIncludeDirs and #sResult > 0 then
                        table.insert( tResults, sResult )
                    end
                else
                    if bIncludeFiles and #sResult > 0 then
                        table.insert( tResults, sResult )
                    end
                end
            end
        end
        return tResults
    end
    return tEmpty
end

-- Load APIs
local bAPIError = false
local tApis = fs.list( "rom/apis" )
for n,sFile in ipairs( tApis ) do
    if string.sub( sFile, 1, 1 ) ~= "." then
        local sPath = fs.combine( "rom/apis", sFile )
        if not fs.isDir( sPath ) then
            if not os.loadAPI( sPath ) then
                bAPIError = true
            end
        end
    end
end

if bAPIError then
  error('An API failed to load')
end

-- Run the shell
local ok, err = pcall( function()
    parallel.waitForAny(
        function()
          njs.docode()
        end,
        function()
          rednet.run()
        end )
end )

-- If the shell errored, let the user read it.
term.redirect( term.native() )
if not ok then
  print(err)
end

-- End
os.shutdown()
