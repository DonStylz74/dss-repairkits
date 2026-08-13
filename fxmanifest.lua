fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'Don Stylz Skripts'
description 'Vehicle Repair and Cleaning Kits - ESX Legacy + ox_lib + ox_target + ox_inventory'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua'
}

client_script 'data/client.lua'
server_script 'data/server.lua'

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target',
    'ox_inventory'
}
