local radioChannel = 0
local radioNames = {}
local disableRadioAnim = false
local radioAnim = nil

---@return boolean isEnabled if radioEnabled is true and LocalPlayer.state.disableRadio is 0 (no bits set)
function isRadioEnabled()
	return radioEnabled and LocalPlayer.state.disableRadio == 0
end

--- event syncRadioData
--- syncs the current players on the radio to the client
---@param radioTable table the table of the current players on the radio
---@param localPlyRadioName string the local players name
function syncRadioData(radioTable, localPlyRadioName)
	radioData = radioTable
	logger.info('[radio] Syncing radio table.')
	if GetConvarInt('voice_debugMode', 0) >= 4 then
	end

	local isEnabled = isRadioEnabled()

	if isEnabled then
		handleRadioAndCallInit()
	end

	sendUIMessage({
		radioChannel = radioChannel,
		radioEnabled = isEnabled
	})
	if GetConvarInt("voice_syncPlayerNames", 0) == 1 then
		radioNames[playerServerId] = localPlyRadioName
	end
end

RegisterNetEvent('pma-voice:syncRadioData', syncRadioData)

--- event setTalkingOnRadio
--- sets the players talking status, triggered when a player starts/stops talking.
---@param plySource number the players server id.
---@param enabled boolean whether the player is talking or not.
function setTalkingOnRadio(plySource, enabled)
	radioData[plySource] = enabled

	if not isRadioEnabled() then return logger.info("[radio] Ignoring setTalkingOnRadio. radioEnabled: %s disableRadio: %s", radioEnabled, LocalPlayer.state.disableRadio) end
	-- If we're on a call we don't want to toggle their voice disabled this will break calls.
	local enabled = enabled or callData[plySource]
	toggleVoice(plySource, enabled, 'radio')
	playMicClicks(enabled)
end
RegisterNetEvent('pma-voice:setTalkingOnRadio', setTalkingOnRadio)

--- event addPlayerToRadio
--- adds a player onto the radio.
---@param plySource number the players server id to add to the radio.
function addPlayerToRadio(plySource, plyRadioName)
	radioData[plySource] = false
	if GetConvarInt("voice_syncPlayerNames", 0) == 1 then
		radioNames[plySource] = plyRadioName
	end
	logger.info('[radio] %s joined radio %s %s', plySource, radioChannel,
		radioPressed and " while we were talking, adding them to targets" or "")
	if radioPressed then
		addVoiceTargets(radioData, callData)
	end
end
RegisterNetEvent('pma-voice:addPlayerToRadio', addPlayerToRadio)

--- event removePlayerFromRadio
--- removes the player (or self) from the radio
---@param plySource number the players server id to remove from the radio.
function removePlayerFromRadio(plySource)
	if plySource == playerServerId then
		logger.info('[radio] Left radio %s, cleaning up.', radioChannel)
		for tgt, _ in pairs(radioData) do
			if tgt ~= playerServerId then
				toggleVoice(tgt, false, 'radio')
			end
		end
		sendUIMessage({
			radioChannel = 0,
			radioEnabled = radioEnabled
		})
		radioNames = {}
		radioData = {}
		addVoiceTargets(callData)
	else
		toggleVoice(plySource, false, 'radio')
		if radioPressed then
			logger.info('[radio] %s left radio %s while we were talking, updating targets.', plySource, radioChannel)
			addVoiceTargets(radioData, callData)
		else
			logger.info('[radio] %s has left radio %s', plySource, radioChannel)
		end
		radioData[plySource] = nil
		if GetConvarInt("voice_syncPlayerNames", 0) == 1 then
			radioNames[plySource] = nil
		end
	end
end

RegisterNetEvent('pma-voice:removePlayerFromRadio', removePlayerFromRadio)

RegisterNetEvent('pma-voice:radioChangeRejected', function()
	logger.info("The server rejected your radio change.")
	radioChannel = 0
end)

--- function setRadioChannel
--- sets the local players current radio channel and updates the server
---@param channel number the channel to set the player to, or 0 to remove them.
function setRadioChannel(channel)
	if GetConvarInt('voice_enableRadios', 1) ~= 1 then return end
	type_check({ channel, "number" })
	TriggerServerEvent('pma-voice:setPlayerRadio', channel)
	radioChannel = channel
end

--- exports setRadioChannel
--- sets the local players current radio channel and updates the server
exports('setRadioChannel', setRadioChannel)
-- mumble-voip compatability
exports('SetRadioChannel', setRadioChannel)

--- exports removePlayerFromRadio
--- sets the local players current radio channel and updates the server
exports('removePlayerFromRadio', function()
	setRadioChannel(0)
end)

--- exports addPlayerToRadio
--- sets the local players current radio channel and updates the server
---@param _radio number the channel to set the player to, or 0 to remove them.
exports('addPlayerToRadio', function(_radio)
	local radio = tonumber(_radio)
	if radio then
		setRadioChannel(radio)
	end
end)

--- exports toggleRadioAnim
--- toggles whether the client should play radio anim or not, if the animation should be played or notvaliddance
exports('toggleRadioAnim', function()
	disableRadioAnim = not disableRadioAnim
	TriggerEvent('pma-voice:toggleRadioAnim', disableRadioAnim)
end)

exports("setDisableRadioAnim", function(shouldDisable)
	disableRadioAnim = shouldDisable
end)

-- exports disableRadioAnim
--- returns whether the client is undercover or not
exports('getRadioAnimState', function()
	return disableRadioAnim
end)

--- check if the player is dead
--- seperating this so if people use different methods they can customize
--- it to their need as this will likely never be changed
--- but you can integrate the below state bag to your death resources.
--- LocalPlayer.state:set('isDead', true or false, false)
function isDead()
	if LocalPlayer.state.isDead then
		return true
	elseif IsPlayerDead(PlayerId()) then
		return true
	end
	return false
end

function isRadioAnimEnabled()
	if
		GetConvarInt('voice_enableRadioAnim', 1) == 1
		and not (GetConvarInt('voice_disableVehicleRadioAnim', 0) == 1
			and IsPedInAnyVehicle(PlayerPedId(), false))
		and not disableRadioAnim then
		return true
	end
	return false
end

local radioprop_dict = nil
local radioprop_anim = nil
local radio_object = nil
local radioPressed = false

local function LoadSavedAnimation()
    radioprop_dict = GetResourceKvpString('radioprop_dict') or 'random@arrests'
    radioprop_anim = GetResourceKvpString('radioprop_anim') or 'generic_radio_enter'
end

local function SaveAnimation(dict, anim)
    SetResourceKvp('radioprop_dict', dict)
    SetResourceKvp('radioprop_anim', anim)
    radioprop_dict = dict
    radioprop_anim = anim
end

CreateThread(function()
    LoadSavedAnimation()
end)

RegisterNetEvent('changeradioanim')
AddEventHandler('changeradioanim', function(anim)
    if anim == 'leanover' then
        SaveAnimation('anim@radio_pose_3', 'radio_holding_gun')
    elseif anim == 'crossed_arms' then
        SaveAnimation('anim@radio_left', 'radio_left_clip')
    elseif anim == 'closeup' then
        SaveAnimation('anim@male@holding_radio', 'holding_radio_clip')
    elseif anim == 'default' then
        SaveAnimation('random@arrests', 'generic_radio_enter')
    end
end)

-- RegisterCommand('radioanim', function()
--     lib.registerContext({
--         id = 'gris:radioanim',
--         title = 'Vertical | Radio Animation',
--         options = {
--             {
--                 title = 'Radio Animation #1',
--                 description = 'Animation: Crossed Arms.',
--                 image = "https://cdn.discordapp.com/attachments/1307418550260072499/1379878406082138233/image.png?ex=6841d768&is=684085e8&hm=2ec2761c84ee6b63b5fc864dd7078524fb7e72e451075723c7f6ad8d04114286&",
--                 onSelect = function()
--                     SaveAnimation('anim@radio_left', 'radio_left_clip')
--                 end,
--             },
--             {
--                 title = 'Radio Animation #2',
--                 description = 'Animation: Leanover.',
--                 image = "https://cdn.discordapp.com/attachments/1307418550260072499/1379878113604796436/image.png?ex=6841d723&is=684085a3&hm=3870081a4c7b7f20823e94a3d44a1747ae80e56d11e0b7b23d4174c38f2ec710&",
--                 onSelect = function()
--                     SaveAnimation('anim@radio_pose_3', 'radio_holding_gun')
--                 end,
--             },
--             {
--                 title = 'Radio Animation #3',
--                 description = 'Animation: Closeup.',
--                 image = "https://cdn.discordapp.com/attachments/1307418550260072499/1379877179701203146/image.png?ex=6841d644&is=684084c4&hm=9568b5f7f660ed5a3b8fcb3aaa77f4a07f8a8233b5cda87b49471d14318236ed&",
--                 onSelect = function()
--                     SaveAnimation('anim@male@holding_radio', 'holding_radio_clip')
--                 end,
--             },
--             {
--                 title = 'Radio Animation #4',
--                 description = 'Animation: Default.',
--                 image = "https://cdn.discordapp.com/attachments/1307418550260072499/1379878539209343057/image.png?ex=6841d788&is=68408608&hm=bfd5c76deb8e9e920dfaf3918b16913d1d08415bf7b561667fe74c00c924da07&",
--                 onSelect = function()
--                     SaveAnimation('random@arrests', 'generic_radio_enter')
--                 end,
--             },
--             {
--                 title = 'Vertical | RADIO ANIMATION',
--                 disabled = true,
--             }
--         }
--     })
--     lib.showContext('gris:radioanim')
-- end)

TriggerEvent("chat:addSuggestion", "/propfix", "Fjern stucked props", {})
RegisterCommand("propfix", function()
    local playerPed = PlayerPedId()
    local nearbyObjects = GetGamePool("CObject")
    for _, object in ipairs(nearbyObjects) do
        if DoesEntityExist(object) and GetEntityAttachedTo(object) == playerPed then
            DetachEntity(object, true, true)
            DeleteEntity(object)
        end
    end
end, false)

RegisterCommand('+radiotalk', function()
    local player = PlayerPedId()
    if GetConvarInt('voice_enableRadios', 1) ~= 1 then return end
    if isDead() then return end
    if not isRadioEnabled() then return end
    if not radioPressed and radioChannel > 0 then
        logger.info('[radio] Start broadcasting, update targets and notify server.')
        addVoiceTargets(radioData, callData)
        TriggerServerEvent('pma-voice:setTalkingOnRadio', true)
        radioPressed = true
        playMicClicks(true)

        RequestAnimDict(radioprop_dict)
        while not HasAnimDictLoaded(radioprop_dict) do
            Wait(10)
        end

        TaskPlayAnim(player, radioprop_dict, radioprop_anim, 8.0, 2.0, -1, 50, 2.0, false, false, false)

        local prop = GetHashKey("prop_cs_hand_radio")
        RequestModel(prop)
        while not HasModelLoaded(prop) do
            Wait(1)
        end
        radio_object = CreateObject(prop, GetEntityCoords(player), true)
        if radioprop_anim == 'holding_radio_clip' then
            AttachEntityToEntity(radio_object, player, GetPedBoneIndex(player, 28422), 0.0750, 0.0230, -0.0230, -90.0, 0.0, -59.9999, true, false, false, false, 2, true)
        else
            AttachEntityToEntity(radio_object, player, GetPedBoneIndex(player, 18905), 0.13555, 0.04555, -0.0120, 130.0, -38.0, 170.0, true, true, false, true, 1, true)
        end

        CreateThread(function()
            TriggerEvent("pma-voice:radioActive", true)
            LocalPlayer.state:set("radioActive", true, true)
            while radioPressed do
                if radioChannel < 0 or isDead() or not isRadioEnabled() then
                    ExecuteCommand("-radiotalk")
                    return
                end
                if not IsEntityPlayingAnim(player, radioprop_dict, radioprop_anim, 3) then
                    TaskPlayAnim(player, radioprop_dict, radioprop_anim, 8.0, 2.0, -1, 50, 2.0, false, false, false)
                end
                SetControlNormal(0, 249, 1.0)
                SetControlNormal(1, 249, 1.0)
                SetControlNormal(2, 249, 1.0)
                Wait(0)
            end
        end)
    end
end, false)

RegisterCommand('-radiotalk', function()
    if radioChannel > 0 and radioPressed then
        radioPressed = false
        MumbleClearVoiceTargetPlayers(voiceTarget)
        addVoiceTargets(callData)
        TriggerEvent("pma-voice:radioActive", false)
        LocalPlayer.state:set("radioActive", false, true)
        playMicClicks(false)
        StopAnimTask(PlayerPedId(), radioprop_dict, radioprop_anim, -4.0)
        if radio_object and DoesEntityExist(radio_object) then
            DeleteEntity(radio_object)
            radio_object = nil
        end
        TriggerServerEvent('pma-voice:setTalkingOnRadio', false)
    end
end, false)
if gameVersion == 'fivem' then
	RegisterKeyMapping('+radiotalk', 'Talk over Radio', 'keyboard', GetConvar('voice_defaultRadio', 'LMENU'))
end

--- event syncRadio
--- syncs the players radio, only happens if the radio was set server side.
---@param _radioChannel number the radio channel to set the player to.
function syncRadio(_radioChannel)
	if GetConvarInt('voice_enableRadios', 1) ~= 1 then return end
	logger.info('[radio] radio set serverside update to radio %s', radioChannel)
	radioChannel = _radioChannel
end
RegisterNetEvent('pma-voice:clSetPlayerRadio', syncRadio)


--- handles "radioEnabled" changing
---@param wasRadioEnabled boolean whether radio is enabled or not
function handleRadioEnabledChanged(wasRadioEnabled)
	if wasRadioEnabled then
		syncRadioData(radioData, "")
	else
		removePlayerFromRadio(playerServerId)
	end
end

--- adds the bit to the disableRadio bits
---@param bit number the bit to add
local function addRadioDisableBit(bit)
	local curVal = LocalPlayer.state.disableRadio or 0
	curVal = curVal | bit
	LocalPlayer.state:set("disableRadio", curVal, true)
end
exports("addRadioDisableBit", addRadioDisableBit)

--- removes the bit from disableRadio
---@param bit number the bit to remove
local function removeRadioDisableBit(bit)
	local curVal = LocalPlayer.state.disableRadio or 0
	curVal = curVal & (~bit)
	LocalPlayer.state:set("disableRadio", curVal, true)
end
exports("removeRadioDisableBit", removeRadioDisableBit)

