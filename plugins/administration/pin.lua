--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local pin = {}
local mattata = require('mattata')
local redis = require('libs.redis')

function pin:init()
    pin.commands = mattata.commands(self.info.username):command('pin').table
    pin.help = '/pin <text> - Pins the given text, with Markdown formatting enabled. To update the pin, send the command again with the new pin content.'
end

function pin:on_service_message(service_type, message, configuration, language)
    if service_type == 'pinned message' then
        local current = tonumber(redis:hget('chat:' .. message.chat.id .. ':info', 'pin'))
        if mattata.get_setting(message.chat.id, 'remove channel pins') and message.from.id == 777000 then
            if current then
                return mattata.pin_chat_message(message.chat.id, current, true)
            end
            return mattata.unpin_chat_message(message.chat.id)
        elseif mattata.get_setting(message.chat.id, 'remove other pins') then
            if current and message.pinned_message.message_id ~= current then
                return mattata.pin_chat_message(message.chat.id, current, true)
            end
        end
        if message.from.id == self.info.id then
            return mattata.delete_message(message.chat.id, message.message_id)
        end
    end
end

function pin:on_message(message, configuration, language)
    if not mattata.is_group_admin(message.chat.id, message.from.id) then
        return mattata.send_reply(message, language['errors']['admin'])
    end
    local input = mattata.input(message.text)
    local last_pin = redis:hget('chat:' .. message.chat.id .. ':info', 'pin')
    if not input then
        if not last_pin then
            return mattata.send_reply(message, language['pin']['1'])
        end
        local success = mattata.send_message(message, language['pin']['2'], nil, true, false, last_pin)
        if not success then
            return mattata.send_reply(message, language['pin']['3'])
        end
        return
    end
    local success = mattata.edit_message_text(message.chat.id, last_pin, input, true)
    if not success then
        if not redis:hget('chat:' .. message.chat.id .. ':info', 'pin') then
            mattata.send_reply(message, language['pin']['4'])
        end
        local new_pin = mattata.send_message(message, input, 'markdown', true, false)
        if not new_pin then
            return mattata.send_reply(message, language['pin']['5'])
        end
        mattata.pin_chat_message(message.chat.id, new_pin.result.message_id, true)
        redis:hset('chat:' .. message.chat.id .. ':info', 'pin', new_pin.result.message_id)
        last_pin = new_pin.result.message_id
    end
    return mattata.pin_chat_message(message.chat.id, last_pin)
end

return pin