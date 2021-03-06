--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local chatroulette = {}
local mattata = require('mattata')
local redis = require('libs.redis')

function chatroulette:init(configuration)
    chatroulette.commands = mattata.commands(self.info.username):command('chatroulette'):command('endchat').table
    chatroulette.help = '/chatroulette - Connect yourself to another random user, and have a conversation with them! To end the chat, use /endchat.'
    chatroulette.limit = configuration.limits.chatroulette
end

function chatroulette:on_new_message(message, _, language)
    if message.chat.type ~= 'private' or message.command or (message.is_media and not message.text) then -- we only want to process non-command, text messages in private chat
        return false
    end
    local output
    local other_user = redis:get('chatroulette:' .. message.from.id)
    if not other_user then
        return false
    elseif message.text:len() > chatroulette.limit then -- we'll set a message length limit to stop a wall of text to the other user
        self.is_done = true
        output = string.format(language['chatroulette']['1'], chatroulette.limit)
        return mattata.send_message(message.from.id, output)
    end
    self.is_done = true
    output = string.format(language['chatroulette']['2'], mattata.escape_markdown(message.text))
    local success = mattata.send_message(other_user, output, true)
    if not success then -- if the message couldn't be sent it must mean the bot was blocked
        redis:del('chatroulette:' .. other_user)
        redis:del('chatroulette:' .. message.from.id)
        return mattata.send_message(message.from.id, language['chatroulette']['3'])
    end
    return success
end

function chatroulette.on_message(_, message, _, language)
    if message.chat.type ~= 'private' then
        return mattata.send_reply(message, language.errors.private)
    elseif message.command == 'endchat' then
        local existing = redis:get('chatroulette:' .. message.from.id)
        if existing then -- if their session hasn't ended, we'll force them to end it
            redis:del('chatroulette:' .. message.from.id)
            mattata.send_message(existing, language['chatroulette']['4']) -- send the other person a notification saying their session has ended
            redis:del('chatroulette:' .. existing)
            return mattata.send_message(message.from.id, language['chatroulette']['5'])
        elseif redis:get('chatroulette:searching:' .. message.from.id) then
            redis:del('chatroulette:searching:' .. message.from.id)
            return mattata.send_message(message.from.id, language['chatroulette']['6'])
        end
        return mattata.send_message(message.from.id, language['chatroulette']['7'])
    elseif message.command == 'chatroulette' then
        local success = mattata.send_message(message.from.id, language['chatroulette']['8'])
        if not success then
            return false
        end
        local available = redis:keys('chatroulette:searching:*')
        for pos, user in pairs(available) do
            if user:match('^chatroulette:searching:(.-)$') == tostring(message.from.id) then
                table.remove(available, pos)
            end
        end
        if #available == 0 then
            redis:set('chatroulette:searching:' .. message.from.id, true)
            return mattata.edit_message_text(message.from.id, success.result.message_id, language['chatroulette']['9'])
        end
        available = available[math.random(#available)]
        available = available:match('^chatroulette:searching:(.-)$')
        local paired = mattata.send_message(available, language['chatroulette']['10'])
        redis:del('chatroulette:searching:' .. available)
        if not paired then
            return mattata.edit_message_text(message.from.id, success.result.message_id, language['chatroulette']['11'])
        end
        redis:del('chatroulette:searching:' .. message.from.id)
        redis:set('chatroulette:' .. available, message.from.id)
        redis:set('chatroulette:' .. message.from.id, available)
        return mattata.edit_message_text(message.from.id, success.result.message_id, language['chatroulette']['12'])
    end
    return false
end

return chatroulette