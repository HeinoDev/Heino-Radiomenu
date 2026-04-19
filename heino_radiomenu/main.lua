local isMenuOpen = false

RegisterCommand('radiomenu', function()
    if not isMenuOpen then
        isMenuOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'show' })
    end
end)

RegisterNUICallback('closeRadio', function(data, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'hide' })
    cb('ok')
end)

RegisterNUICallback('changeAnimation', function(data, cb)
    TriggerEvent('changeradioanim', data.animation)
    cb('ok')
end)

RegisterKeyMapping('radiomenu', 'Heino Radiomenu', 'keyboard', 'F6')
