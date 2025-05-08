-- Unturned ESP Script (Optimized)
-- Displays player information and ESP boxes in Unturned

--[[
    CONFIGURATION SECTION
    Edit these values to customize the ESP appearance
]]
local CONFIG = {
    PLY_ESP_BOX = {
        WIDTH = 100,
        HEIGHT = 150,
        OUTLINE_COLOR = {255, 0, 0, 255},
        FILL_COLOR = {255, 0, 0, 50},
        OUTLINE_THICKNESS = 2,
        FILL_THICKNESS = 1
    },
    VEH_ESP_BOX = {
        WIDTH = 200,
        HEIGHT = 200,
        OUTLINE_COLOR = {100, 100, 255, 255},
        FILL_COLOR = {100, 100, 200, 50},
        OUTLINE_THICKNESS = 2,
        FILL_THICKNESS = 1
    },
    FONTS = {
        TITLE = {name = "Arial", size = 16, weight = 700},
        ESP = {name = "Tahoma", size = 10, weight = 700}
    },
    DEBUG = false -- Set to true to show debug information
}

--[[
    MEMORY STRUCTURE SECTION
    Contains all memory addresses and structure definitions
]]
local MEMORY = {
    POINTER_PATHS = {
        WTS_MATRIX = {"UnityPlayer.dll", 0x1B1B3E0},
        PROJ_MATRIX = {"UnityPlayer.dll", 0x01B49540, 0xA0, 0x28, 0x68, 0x34C},
        PLAYER_INSTANCE = {"UnityPlayer.dll", 0x01ADC688, 0xA0, 0x30, 0x60, 0xA0, 0x0},
        CLIENTS_LIST = {"mono-2.0-bdwgc.dll", 0x009F1BF8, 0x400, 0x3A8, 0x20, 0x60, 0x10, 0x18, 0xC0},
        VEHICLES_LIST = {"UnityPlayer.dll", 0x1A7B800, 0x10, 0x38, 0x20, 0x40, 0x68, 0x60, 0x0}
    },
    STRUCTURES = {
        Player = {
            _channel = 0x38,
            _life = 0x60,
            _movement = 0x78,
            _look = 0x80
        },
        SteamChannel = {
            owner = 0x20
        },
        SteamPlayer = {
            _player = 0x30,
            _playerID = 0x20,
            _isAdmin = 0xB8
        },
        PlayerLife = {
            _stamina = 0xD4,
            _isDead = 0xC8
        },
        List_T = {
            _items = 0x10,
            _size = 0x18
        },
        SteamPlayerID = {
            _characterName = 0x10
        },
        SystemString = {
            _stringLength = 0x10,
            _firstChar = 0x14
        },
        PlayerMovement = {
            lastUpdatedPos = 0x178,
            snapshot = 0x184
        },
        PlayerLook = {
            mainCameraZoomFactor = 0x160
        },
        InteractableVehicle = {
            lastUpdatedPos = 0x2C4,
            real = 0x2EC,
            _isLocked = 0x2B8,
            isExploded = 0x258,
            _asset = 0x178
        },
        VehicleAsset = {
            name = 0x10,
            _rarity = 0x128,
            _size2_z = 0x10C,
            _sqrDelta = 0x1F0
        }
    }
}

--[[
    OBJECT CLASSES SECTION
    Defines the data structures used by the script
]]
local Vector3 = {}
Vector3.__index = Vector3
function Vector3:new(x, y, z)
    return setmetatable({x = x or 0, y = y or 0, z = z or 0}, self)
end

local Player = {}
Player.__index = Player
function Player:new(nickName, isAdmin, addr, origin, isDead, zoomFactor)
    return setmetatable({
        nickName = nickName or 'Undefined',
        isAdmin = isAdmin or 0,
        addr = addr or "0x00000000",
        origin = origin or vec3(0, 0, 0),
        isDead = isDead or 0,
        zoomFactor = zoomFactor or -1
    }, self)
end

local Vehicle = {}
Vehicle.__index = Vehicle
function Vehicle:new(name, real, size2z, sqrDelta)
    return setmetatable({
        name = name or "UNDEFINED",
        real = real or nil,
        size2z = size2z or -1,
        sqrDelta = sqrDelta or -1
    }, self)
end

--[[
    HELPER FUNCTIONS SECTION
    Utility functions for memory access and data manipulation
]]
local function toHex(number)
    return string.format("0x%X", number)
end

local function safeReadInt64(address, offset, errorMsg)
    if address == 0 then return 0 end
    local value = proc.read_int64(address + (offset or 0))
    if value == 0 and errorMsg and CONFIG.DEBUG then
        engine.log(errorMsg, 255, 0, 0, 255)
    end
    return value
end

local function safeReadInt32(address, offset, errorMsg)
    if address == 0 then return 0 end
    local value = proc.read_int32(address + (offset or 0))
    if value == 0 and errorMsg and CONFIG.DEBUG then
        engine.log(errorMsg, 255, 0, 0, 255)
    end
    return value
end

local function safeReadInt8(address, offset)
    if address == 0 then return 0 end
    return proc.read_int8(address + (offset or 0))
end

local function readVector3(address)
    if address == 0 then return vec3(0,0,0) end
    return vec3(
        proc.read_float(address + 0x0),
        proc.read_float(address + 0x4),
        proc.read_float(address + 0x8)
    )
end

local function safeReadString(address, offset)
    local string_obj = safeReadInt64(address, offset)
    local stringLength = safeReadInt32(string_obj, MEMORY.STRUCTURES.SystemString._stringLength)
    
    if stringLength > 0 and stringLength < 65 then -- Reasonable limit to prevent reading garbage
        local stringText = proc.read_wide_string(
            string_obj + MEMORY.STRUCTURES.SystemString._firstChar, 
            stringLength
        )
        return stringText or "Unknown"
    end
    
    return "Unknown"
end
-- local function readMatrix4x4(address)
--     if address == 0 then return nil end
    
--     local matrix = {}
--     for row = 0, 3 do
--         matrix[row + 1] = {}
--         for col = 0, 3 do
--             local offset = (col * 4 + row) * 4  -- Column-major order
--             matrix[row + 1][col + 1] = proc.read_float(address + offset)
--         end
--     end
--     return matrix
-- end

local function readMatrix4x4(address)
    if address == 0 then return nil end
    
    local size = 64
    local buffer = m.alloc(size)
    proc.read_to_memory_buffer(address, buffer, size)
    
    local matrix = {{}, {}, {}, {}}
    local offset = 0
    
    for col = 0, 3 do
        matrix[1][col + 1] = m.read_float(buffer, offset)
        matrix[2][col + 1] = m.read_float(buffer, offset + 4)
        matrix[3][col + 1] = m.read_float(buffer, offset + 8)
        matrix[4][col + 1] = m.read_float(buffer, offset + 12)
        offset = offset + 16
    end
    
    m.free(buffer)
    return matrix
end

-- local function multiplyMatrix4x4(a, b)
--     local result = {}
--     for i = 1, 4 do
--         result[i] = {}
--         for j = 1, 4 do
--             result[i][j] = 
--                 a[i][1] * b[1][j] +
--                 a[i][2] * b[2][j] +
--                 a[i][3] * b[3][j] +
--                 a[i][4] * b[4][j]
--         end
--     end
--     return result
-- end

local function readPointerPath(path)
    local addr = 0x0
    
    -- First path element is module name
    local module_addr, module_size = proc.find_module(path[1])
    if module_addr == 0 or module_size == 0 then
        if CONFIG.DEBUG then 
            engine.log("Failed to find module: " .. path[1], 255, 0, 0, 255) 
        end
        return 0
    end
    addr = module_addr
    
    -- Follow the pointer path
    for i = 2, #path do
        if i == #path then
            addr = addr + path[i]
        else
            addr = proc.read_int64(addr + path[i])
            if addr == 0 then
                if CONFIG.DEBUG then
                    engine.log(string.format("Failed to follow pointer path at index %d", i), 255, 0, 0, 255)
                end
                return 0
            end
        end
    end
    
    return addr
end

local function worldToScreen(position, viewProjMatrix, screenWidth, screenHeight, zoomFactor)
    local zoomFactor = zoomFactor or 1
    if zoomFactor <= 0 then zoomFactor = 1 end

    local clipPos = viewProjMatrix * vec4(position.x, position.y, position.z, 1.0)
    
    if clipPos.w <= 0.001 then 
        return 0, 0, false, 0 
    end
    
    local ndcX = clipPos.x / clipPos.w
    local ndcY = clipPos.y / clipPos.w
    
    if ndcX < -1 or ndcX > 1 or ndcY < -1 or ndcY > 1 then 
        return 0, 0, false, 0 
    end
    
    local screenX = (ndcX + 1.0) * 0.5 * screenWidth
    local screenY = (1.0 - ndcY) * 0.5 * screenHeight
    
    local scale = (1.0 / clipPos.w) * 10 * zoomFactor
    
    return screenX, screenY, true, scale
end

--[[
    GAME STATE FUNCTIONS SECTION
    Functions for accessing and updating game state
]]
local cachedAddresses = {
    wtsMatrixAddr = 0,
    projMatrixAddr = 0,
    clientsListAddr = 0,
    playerInstanceAddr = 0,
    vehiclesListAddr = 0
}

local gameState = {
    localPlayer = nil,
    playersList = {},
    wtsMatrix = nil,
    projMatrix = nil,
    viewProjMatrix = nil,
    screenWidth = 0,
    screenHeight = 0,
    vehiclesList = nil
}

local function refreshCachedAddresses()
    cachedAddresses.wtsMatrixAddr = readPointerPath(MEMORY.POINTER_PATHS.WTS_MATRIX)
    cachedAddresses.projMatrixAddr = readPointerPath(MEMORY.POINTER_PATHS.PROJ_MATRIX)
    cachedAddresses.clientsListAddr = readPointerPath(MEMORY.POINTER_PATHS.CLIENTS_LIST)
    cachedAddresses.playerInstanceAddr = readPointerPath(MEMORY.POINTER_PATHS.PLAYER_INSTANCE)
    cachedAddresses.vehiclesListAddr = readPointerPath(MEMORY.POINTER_PATHS.VEHICLES_LIST)
    
    if CONFIG.DEBUG then
        engine.log(string.format("Updated addresses: WTS=%s, PROJ=%s, LIST=%s, PLAYER=%s, VECHILES=%s",
            toHex(cachedAddresses.wtsMatrixAddr),
            toHex(cachedAddresses.projMatrixAddr),
            toHex(cachedAddresses.clientsListAddr),
            toHex(cachedAddresses.playerInstanceAddr),
            toHex(cachedAddresses.vehiclesListAddr)
        ), 0, 255, 0, 255)
    end
end

local function getLocalPlayer()
    local playerAddr = cachedAddresses.playerInstanceAddr
    if playerAddr == 0 then return nil end
    
    local channelAddr = safeReadInt64(playerAddr, MEMORY.STRUCTURES.Player._channel)
    local ownerAddr = safeReadInt64(channelAddr, MEMORY.STRUCTURES.SteamChannel.owner)
    local playerPtr = safeReadInt64(ownerAddr, MEMORY.STRUCTURES.SteamPlayer._player)
    
    if playerPtr == 0 then return nil end
    
    local playerIDAddr = safeReadInt64(ownerAddr, MEMORY.STRUCTURES.SteamPlayer._playerID)
    local lifeAddr = safeReadInt64(playerPtr, MEMORY.STRUCTURES.Player._life)
    local movementAddr = safeReadInt64(playerPtr, MEMORY.STRUCTURES.Player._movement)
    
    -- local name = readPlayerName(playerIDAddr)
    local name = safeReadString(playerIDAddr, MEMORY.STRUCTURES.SteamPlayerID._characterName)
    local isAdmin = safeReadInt8(ownerAddr, MEMORY.STRUCTURES.SteamPlayer._isAdmin)
    local position = readVector3(movementAddr + MEMORY.STRUCTURES.PlayerMovement.lastUpdatedPos)
    local isDead = safeReadInt8(lifeAddr, MEMORY.STRUCTURES.PlayerLife._isDead)
    local _look = safeReadInt64(playerPtr, MEMORY.STRUCTURES.Player._look)
    local zoomFactor = proc.read_float(MEMORY.STRUCTURES.PlayerLook.mainCameraZoomFactor + _look)
    
    return Player:new(name, isAdmin, toHex(playerPtr), position, isDead, zoomFactor)
end

local function updatePlayersList()
    local result = {}
    local clientsListAddr = cachedAddresses.clientsListAddr
    
    if clientsListAddr == 0 then return result end
    
    local itemsAddr = safeReadInt64(clientsListAddr, MEMORY.STRUCTURES.List_T._items)
    local size = safeReadInt32(clientsListAddr, MEMORY.STRUCTURES.List_T._size)
    
    -- Safety check for list size
    if size <= 0 or size > 128 then
        if CONFIG.DEBUG and size > 128 then
            engine.log(string.format("Warning: Abnormal player list size: %d", size), 255, 255, 0, 255)
        end
        return result
    end
    
    local localPlayerName = gameState.localPlayer and gameState.localPlayer.nickName
    
    for i = 0, size - 1 do
        local playerData = safeReadInt64(itemsAddr + 0x20 + (0x8 * i))
        if playerData == 0 then goto continue end
        
        local playerIDAddr = safeReadInt64(playerData, MEMORY.STRUCTURES.SteamPlayer._playerID)
        local name = safeReadString(playerIDAddr, MEMORY.STRUCTURES.SteamPlayerID._characterName)
        
        -- Skip local player
        if name == localPlayerName then goto continue end
        
        local playerPtr = safeReadInt64(playerData, MEMORY.STRUCTURES.SteamPlayer._player)
        if playerPtr == 0 then goto continue end
        
        local lifeAddr = safeReadInt64(playerPtr, MEMORY.STRUCTURES.Player._life)
        local movementAddr = safeReadInt64(playerPtr, MEMORY.STRUCTURES.Player._movement)
        
        local isAdmin = safeReadInt8(playerData, MEMORY.STRUCTURES.SteamPlayer._isAdmin)
        local position = readVector3(movementAddr + MEMORY.STRUCTURES.PlayerMovement.snapshot)
        local isDead = safeReadInt8(lifeAddr, MEMORY.STRUCTURES.PlayerLife._isDead)
        
        table.insert(result, Player:new(name, isAdmin, toHex(playerPtr), position, isDead))
        
        ::continue::
    end
    
    return result
end

local function updateVehiclesList()
    local result = {}
    local vehiclesListAddr = cachedAddresses.vehiclesListAddr
    
    if vehiclesListAddr == 0 then return result end
    
    local itemsAddr = safeReadInt64(vehiclesListAddr, MEMORY.STRUCTURES.List_T._items)
    local size = safeReadInt32(vehiclesListAddr, MEMORY.STRUCTURES.List_T._size)
    
    -- Safety check for list size
    if size <= 0 or size > 128 then
        if CONFIG.DEBUG and size > 128 then
            engine.log(string.format("Warning: Abnormal vehicles list size: %d", size), 255, 255, 0, 255)
        end
        return result
    end
        
    for i = 0, size - 1 do
        local vehData = safeReadInt64(itemsAddr, 0x20 + (0x8 * i))
        local _asset = safeReadInt64(vehData, MEMORY.STRUCTURES.InteractableVehicle._asset)
        local name = safeReadString(_asset, MEMORY.STRUCTURES.VehicleAsset.name)
        local real = readVector3(vehData + MEMORY.STRUCTURES.InteractableVehicle.real)
        local size2z = proc.read_float(_asset + MEMORY.STRUCTURES.VehicleAsset._size2_z)
        local sqrDelta = proc.read_float(_asset + MEMORY.STRUCTURES.VehicleAsset._sqrDelta)
        table.insert(result, Vehicle:new(name, real, size2z, sqrDelta))
        ::continue::
    end
    
    return result
end

local function updateGameState()
    -- Read matrices
    gameState.wtsMatrix = mat4.from_table(readMatrix4x4(cachedAddresses.wtsMatrixAddr))
    gameState.projMatrix = mat4.from_table(readMatrix4x4(cachedAddresses.projMatrixAddr))
    
    if gameState.wtsMatrix and gameState.projMatrix then
        gameState.viewProjMatrix = gameState.projMatrix * gameState.wtsMatrix
    end
    
    -- Update local player info
    gameState.localPlayer = getLocalPlayer()
    
    -- Update other players
    gameState.playersList = updatePlayersList()
    
    -- Update screen dimensions
    gameState.screenWidth, gameState.screenHeight = render.get_viewport_size()

    -- Update vehicles
    gameState.vehiclesList = updateVehiclesList()
end

--[[
    RENDERING SECTION
    Functions for displaying ESP and debug information
]]
local fonts = {
    title = nil,
    esp = nil
}

local function initializeFonts()
    fonts.title = render.create_font(
        CONFIG.FONTS.TITLE.name, 
        CONFIG.FONTS.TITLE.size, 
        CONFIG.FONTS.TITLE.weight
    )
    
    fonts.esp = render.create_font(
        CONFIG.FONTS.ESP.name, 
        CONFIG.FONTS.ESP.size, 
        CONFIG.FONTS.ESP.weight
    )
end

local function drawESP()
    if not gameState.viewProjMatrix then return end
    if not gameState.localPlayer then return end
    
    for _, player in ipairs(gameState.playersList) do
        -- Skip dead players
        if player.isDead == 1 then goto continue end
        
        -- Calculate screen position
        local screenX, screenY, isVisible, scale = worldToScreen(
            player.origin,
            gameState.viewProjMatrix,
            gameState.screenWidth,
            gameState.screenHeight,
            gameState.localPlayer.zoomFactor
        )
        
        if not isVisible then goto continue end
        
        -- Draw ESP box
        local boxWidth = CONFIG.PLY_ESP_BOX.WIDTH * scale
        local boxHeight = CONFIG.PLY_ESP_BOX.HEIGHT * scale
        local boxX = screenX - (boxWidth / 2)
        local boxY = screenY - (boxHeight * 0.95)
        
        -- Box outline
        render.draw_rectangle(
            boxX, boxY, boxWidth, boxHeight,
            CONFIG.PLY_ESP_BOX.OUTLINE_COLOR[1],
            CONFIG.PLY_ESP_BOX.OUTLINE_COLOR[2],
            CONFIG.PLY_ESP_BOX.OUTLINE_COLOR[3],
            CONFIG.PLY_ESP_BOX.OUTLINE_COLOR[4],
            CONFIG.PLY_ESP_BOX.OUTLINE_THICKNESS,
            false, 1
        )
        
        -- Box fill
        render.draw_rectangle(
            boxX, boxY, boxWidth, boxHeight,
            CONFIG.PLY_ESP_BOX.FILL_COLOR[1],
            CONFIG.PLY_ESP_BOX.FILL_COLOR[2],
            CONFIG.PLY_ESP_BOX.FILL_COLOR[3],
            CONFIG.PLY_ESP_BOX.FILL_COLOR[4],
            CONFIG.PLY_ESP_BOX.FILL_THICKNESS,
            true, 1
        )
        
        -- Player name
        local textWidth, textHeight = render.measure_text(fonts.esp, player.nickName)
        render.draw_text(
            fonts.esp, 
            player.nickName, 
            screenX - textWidth / 2, 
            (screenY - textHeight / 2) - (boxHeight * 1.02),
            255, 255, 255, 255, 
            1, 0, 0, 0, 255
        )
        
        ::continue::
    end

    for _, veh in ipairs(gameState.vehiclesList) do
        -- Calculate screen position
        local screenX, screenY, isVisible, scale = worldToScreen(
            veh.real,
            gameState.viewProjMatrix,
            gameState.screenWidth,
            gameState.screenHeight,
            gameState.localPlayer.zoomFactor
        )
        
        if not isVisible then goto continue end
        
        -- Draw ESP box
        local boxWidth = CONFIG.VEH_ESP_BOX.WIDTH * scale
        local boxHeight = CONFIG.VEH_ESP_BOX.HEIGHT * scale
        local boxX = screenX - (boxWidth / 2)
        local boxY = screenY - (boxHeight * 0.95)
        
        -- Box outline
        render.draw_rectangle(
            boxX, boxY, boxWidth, boxHeight,
            CONFIG.VEH_ESP_BOX.OUTLINE_COLOR[1],
            CONFIG.VEH_ESP_BOX.OUTLINE_COLOR[2],
            CONFIG.VEH_ESP_BOX.OUTLINE_COLOR[3],
            CONFIG.VEH_ESP_BOX.OUTLINE_COLOR[4],
            CONFIG.VEH_ESP_BOX.OUTLINE_THICKNESS,
            false, 1
        )
        
        -- Box fill
        render.draw_rectangle(
            boxX, boxY, boxWidth, boxHeight,
            CONFIG.VEH_ESP_BOX.FILL_COLOR[1],
            CONFIG.VEH_ESP_BOX.FILL_COLOR[2],
            CONFIG.VEH_ESP_BOX.FILL_COLOR[3],
            CONFIG.VEH_ESP_BOX.FILL_COLOR[4],
            CONFIG.VEH_ESP_BOX.FILL_THICKNESS,
            true, 1
        )
        
        -- Vehicle name
        local vntextWidth, vntextHeight = render.measure_text(fonts.esp, veh.name)
        render.draw_text(
            fonts.esp, 
            veh.name, 
            screenX - vntextWidth / 2, 
            (screenY - vntextHeight / 2) - (boxHeight * 1.02),
            255, 255, 255, 255, 
            1, 0, 0, 0, 255
        )

        if CONFIG.DEBUG then
            -- size2z
            local s2ztextWidth, s2ztextHeight = render.measure_text(fonts.esp, veh.size2z)
            render.draw_text(
                fonts.esp, 
                veh.size2z, 
                screenX - s2ztextWidth / 2, 
                (screenY - s2ztextHeight / 2) - (boxHeight * 1.02) - vntextHeight,
                255, 255, 255, 255, 
                1, 0, 0, 0, 255
            )

            -- sqrDelta
            local sqdtextWidth, sqdtextHeight = render.measure_text(fonts.esp, veh.sqrDelta)
            render.draw_text(
                fonts.esp, 
                veh.sqrDelta, 
                screenX - sqdtextWidth / 2, 
                (screenY - sqdtextHeight / 2) - (boxHeight * 1.02) - (s2ztextHeight + vntextHeight),
                255, 255, 255, 255, 
                1, 0, 0, 0, 255
            )
        end
        
        ::continue::
    end
end

local function drawTitle()
    local titleText = "LOOK CLOSER"
    local textWidth, textHeight = render.measure_text(fonts.title, titleText)
    
    -- Draw with shadow effect
    render.draw_text(
        fonts.title, 
        titleText, 
        gameState.screenWidth / 2 - textWidth / 2, 
        10, 
        0, 0, 0, 100, 
        0, 0, 0, 0, 255
    )
end

local function drawDebugInfo()
    if not CONFIG.DEBUG then return end
    if not gameState.localPlayer then return end
    
    local debugText = string.format([[
Local Player: %s
Address: %s
Players Count: %d
Zoom Factor: %d

LP Origin:
-> X: %.2f
-> Y: %.2f
-> Z: %.2f
    ]], 
    gameState.localPlayer and gameState.localPlayer.nickName or "Unknown",
    gameState.localPlayer and gameState.localPlayer.addr or "0x0",
    #gameState.playersList,
    gameState.localPlayer.zoomFactor or -1,
    gameState.localPlayer.origin.x,
    gameState.localPlayer.origin.y,
    gameState.localPlayer.origin.z
    )
    
    render.draw_text(
        fonts.title, 
        debugText, 
        20, 500, 
        0, 255, 0, 255, 
        1, 0, 0, 0, 255
    )

    local sx, sy, vis, scale = worldToScreen(
        vec3(215, 57, 796), 
        gameState.viewProjMatrix,
        gameState.screenWidth,
        gameState.screenHeight,
        gameState.localPlayer.zoomFactor
    )
    render.draw_rectangle(sx, sy, 10 * scale, 10 * scale, 255, 255, 0, 255, 1, false)
end

--[[
    MAIN SECTION
    Script initialization and main loop
]]
-- Initialize the script
local function initialize()
    if not proc.attach_by_name("Unturned.exe") then
        engine.log("Failed to attach to Unturned!", 255, 0, 0, 255)
        return false
    end
    
    initializeFonts()
    refreshCachedAddresses()
    
    return true
end

-- Main rendering function
local function onRender()
    updateGameState()
    drawESP()
    drawTitle()
    drawDebugInfo()
end

refreshCachedAddresses()

local function onTick()
    onRender()
end

-- Initialize and register callbacks
if initialize() then
    engine.register_on_engine_tick(onTick)
    engine.log("ESP Script initialized successfully", 0, 255, 0, 255)
else
    engine.log("ESP Script failed to initialize", 255, 0, 0, 255)
end