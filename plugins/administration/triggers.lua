--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local triggers = {}
local mattata = require('mattata')
local redis = require('libs.redis')

function triggers:init()
    triggers.commands = mattata.commands(self.info.username):command('triggers'):command('trigger'):command('custom'):command('addtrigger'):command('deltrigger').table
    triggers.help = '/triggers - Allows admins to view existing word triggers. Use /addtrigger <trigger> <value> to add one, and /deltrigger <trigger> to delete one. Each chat is allowed 8 word triggers, with a maximum of 16 characters per word trigger and 256 characters per response. Trigger words can be alpha-numerical, and may have hashtags at the start. Aliases: /trigger, /custom.'
end

function triggers:on_new_message(message)
    if message.command or message.is_media or self.is_ai then
        return false
    end
    local matches = redis:hgetall('triggers:' .. message.chat.id)
    if not next(matches) == 0 then
        return false
    end
    for trigger, value in pairs(matches) do
        if message.text:lower():match(trigger:lower()) then
            local trail
            if trigger:lower() == 'ayy' and value:lower() == 'lmao' then
                trail = message.text:lower():match('(ayy+)'):gsub('^ay', '')
                value = 'lma' .. string.rep('o', trail:len())
            elseif trigger:lower() == 'lmao' and value:lower() == 'ayy' then
                trail = message.text:lower():match('(lmao+)'):gsub('^lma', '')
                value = 'ay' .. string.rep('y', trail:len())
            end
            if value:len() > 4096 then
                value = value:sub(1, 4096)
            end
            if not message.is_edited then
                local success = mattata.send_message(message.chat.id, '<pre>' .. mattata.escape_html(value) .. '</pre>', 'html')
                if success then
                    redis:set('bot:' .. message.chat.id .. ':' .. message.message_id, success.result.message_id)
                end
                return success
            else
                local message_id = redis:get('bot:' .. message.chat.id .. ':' .. message.message_id)
                if message_id then
                    return mattata.edit_message_text(message.chat.id, message_id, '<pre>' .. mattata.escape_html(value) .. '</pre>', 'html')
                end
            end
        end
    end
    return
end

function triggers:on_message(message)
    self.is_done = true
    if message.chat.type == 'private' or not mattata.is_group_admin(message.chat.id, message.from.id) then
        return false
    elseif message.command == 'triggers' then
        local matches = redis:hgetall('triggers:' .. message.chat.id)
        if not next(matches) then
            return mattata.send_reply(message, 'This chat doesn\'t have any triggers set up. To add one, use /addtrigger <trigger> <value>.')
        end
        local output = 'Triggers for <b>%s</b>\n\n%s'
        local all = {}
        for trigger, value in pairs(matches) do
            local line = '<code>%s</code>: <i>%s</i>'
            line = string.format(line, mattata.escape_html(trigger), mattata.escape_html(value))
            table.insert(all, line)
        end
        table.insert(all, '\nTo delete a trigger, use <code>/deltrigger &lt;trigger&gt;</code>')
        all = table.concat(all, '\n')
        output = string.format(output, mattata.escape_html(message.chat.title), all)
        return mattata.send_reply(message, output, 'html')
    elseif message.command == 'addtrigger' or message.command == 'trigger' or message.command == 'custom' then
        local input = mattata.input(message.text)
        if not input or not input:match('^#?%w+ .-$') then
            return mattata.send_reply(message, triggers.help)
        end
        local trigger, value = input:match('^(#?%w+) (.-)$')
        local count = 0
        local is_duplicate = false
        local all = redis:hgetall('triggers:' .. message.chat.id)
        for _, v in ipairs(all) do
            count = count + 1
            if v == trigger then
                is_duplicate = true
            end
        end
        if is_duplicate then
            return mattata.send_reply(message, 'That trigger already exists! To modify it, delete it first using /deltrigger ' .. trigger .. ', then use this command again!')
        elseif count >= 8 then
            return mattata.send_reply(message, 'You can\'t have more than 8 triggers! Please delete one using /deltrigger <trigger>. To view a list of this chat\'t triggers, use /triggers.')
        end
        if trigger:len() > 16 then
            return mattata.send_reply(message, 'The trigger needs to be 1-16 characters long, and alpha-numerical.')
        elseif value:len() > 256 then
            return mattata.send_reply(message, 'The value must be no more than 256 characters long!')
        end
        redis:hset('triggers:' .. message.chat.id, trigger, value)
        return mattata.send_reply(message, 'Successfully added that trigger! To view a list of triggers, send /triggers.')
    elseif message.command == 'deltrigger' then
        local input = mattata.input(message.text)
        if not input or not input:match('^#?%w+$') then
            return mattata.send_reply(message, 'Please specify the trigger you\'d like to delete! To view your existing triggers, send /triggers.')
        end
        local deleted = redis:hdel('triggers:' .. message.chat.id, input)
        if deleted == 0 then
            return mattata.send_reply(message, 'That trigger does not exist! Use /triggers to view a list of existing triggers for this chat.')
        end
        return mattata.send_reply(message, 'Successfully deleted that trigger!')
    end
    return false
end

return triggers