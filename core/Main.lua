local ADDON_NAME, GW = ...
GW = GW or {}
local Data = GW.Data
local SUPPORTED_LANGUAGES = Data.SUPPORTED_LANGUAGES
local WELCOME_MESSAGES = Data.WELCOME_MESSAGES
local COMMAND_ALIASES = Data.COMMAND_ALIASES
local CLIENT_LANGUAGE_ALIASES = Data.CLIENT_LANGUAGE_ALIASES
local UI_TEXT = Data.UI_TEXT
local CLASS_WELCOME_MESSAGES = Data.CLASS_WELCOME_MESSAGES
local EXTRA_CLASS_WELCOME_MESSAGES = Data.EXTRA_CLASS_WELCOME_MESSAGES
local BONUS_CLASS_WELCOME_MESSAGES = Data.BONUS_CLASS_WELCOME_MESSAGES
local EPIC_CLASS_WELCOME_MESSAGES = Data.EPIC_CLASS_WELCOME_MESSAGES
local BANTER_CLASS_WELCOME_MESSAGES = Data.BANTER_CLASS_WELCOME_MESSAGES
local CLASS_NAME_ALIASES = Data.CLASS_NAME_ALIASES
local AppendNameMessages = Data.AppendNameMessages
local ResolveGeneratedWelcomeMessages = Data.ResolveGeneratedWelcomeMessages
local ResolveVIPWelcomeMessage = Data.ResolveVIPWelcomeMessage
local ADDON_MESSAGE_PREFIX = "GuildWelcomer"
local COORDINATION_WINDOW_SECONDS = 1.25
local PEER_FRESHNESS_SECONDS = 10
local ROSTER_BASELINE_SECONDS = 5
local HORDE_MESSAGE_REPLACEMENTS = {
    ["The Silver Hand approves"] = "The Blood Knights approve",
    ["Die Silberne Hand nickt zufrieden"] = "Die Blutritter nicken zufrieden",
    ["La Mano de Plata lo aprueba"] = "Los Caballeros de Sangre lo aprueban",
    ["Serebryanaya Desnitsa odobryaet"] = "Rytsari Krovi odobryayut",
    ["La Main d'Argent approuve"] = "Les Chevaliers de sang approuvent",
    ["Silver Hand godkanner detta"] = "Blood Knights godkanner detta",
    ["De Silver Hand keurt dit goed"] = "De Blood Knights keuren dit goed",
}

local state = {
    guildKey = nil,
    rosterReady = false,
    rosterBaselineStartedAt = nil,
    rosterGeneration = 0,
    members = {},
    recentGreetings = {},
    lastMessageByLanguage = {},
    recentMessagesByLanguage = {},
    activeWhoDebugRequest = nil,
    pendingSystemJoins = {},
    pendingGreetings = {},
    combatDeferredGreetings = {},
    addonPeers = {},
    lastSpecialSpeaker = nil,
    specialTurns = {},
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GuildWelcomer|r: " .. message)
end

local schedulerFrame
local scheduledCallbacks = {}
local function SchedulerOnUpdate(_, elapsed)
    for index = #scheduledCallbacks, 1, -1 do
        local entry = scheduledCallbacks[index]
        entry.remaining = entry.remaining - elapsed
        if entry.remaining <= 0 then
            table.remove(scheduledCallbacks, index)
            entry.callback()
        end
    end

    if #scheduledCallbacks == 0 and schedulerFrame then
        schedulerFrame:SetScript("OnUpdate", nil)
    end
end

local function RunAfterDelay(delaySeconds, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delaySeconds, callback)
        return
    end

    if not schedulerFrame then
        schedulerFrame = CreateFrame("Frame")
    end

    scheduledCallbacks[#scheduledCallbacks + 1] = {
        remaining = delaySeconds,
        callback = callback,
    }

    schedulerFrame:SetScript("OnUpdate", SchedulerOnUpdate)
end

local function GetClientLanguage()
    local locale = GetLocale and GetLocale() or "enUS"
    return CLIENT_LANGUAGE_ALIASES[locale] or "EN"
end

local function GetUIText(key)
    local language = GetClientLanguage()
    local localized = UI_TEXT[language]
    if localized and localized[key] then
        return localized[key]
    end

    return UI_TEXT.EN[key]
end

local function PrintLocalized(key, ...)
    Print(string.format(GetUIText(key), ...))
end

local function IsDebugEnabled()
    return GuildWelcomerDB and GuildWelcomerDB.debugEnabled == true
end

local function SetDebugEnabled(enabled)
    GuildWelcomerDB.debugEnabled = enabled and true or false
end

local function GetDebugStatusText()
    if IsDebugEnabled() then
        return GetUIText("debug_on")
    end

    return GetUIText("debug_off")
end

local function DebugPrintGreetingProfile(name, profile)
    if not IsDebugEnabled() then
        return
    end

    PrintLocalized("who_disabled", name, profile.class or GetUIText("unknown_value"))
    if profile.poolLabel then
        PrintLocalized("pool_selected", name, profile.poolLabel)
    end
end

local CanonicalizeName

local function CanonicalizeWhoDebugName(name)
    return CanonicalizeName(name)
end

local function GetWhoResultCount()
    if C_FriendList and C_FriendList.GetNumWhoResults then
        return C_FriendList.GetNumWhoResults() or 0
    end

    if GetNumWhoResults then
        return GetNumWhoResults() or 0
    end

    return 0
end

local function GetWhoResultInfo(index)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local info = C_FriendList.GetWhoInfo(index)
        if info then
            return {
                fullName = info.fullName or info.name,
                race = info.raceStr or info.race or info.raceName,
                class = info.classStr or info.class or info.className,
            }
        end
    end

    if GetWhoInfo then
        local playerName, _, _, _, _, raceName, className = GetWhoInfo(index)
        return {
            fullName = playerName,
            race = raceName,
            class = className,
        }
    end
end

local function FinishDebugWhoLookup(success, request, raceName, className)
    if state.activeWhoDebugRequest ~= request then
        return
    end

    state.activeWhoDebugRequest = nil

    if success then
        PrintLocalized(
            "who_succeeded",
            request.displayName,
            raceName or GetUIText("unknown_value"),
            className or request.className or GetUIText("unknown_value")
        )
    else
        PrintLocalized(
            "who_roster_only",
            request.displayName,
            raceName or GetUIText("unknown_value"),
            request.className or GetUIText("unknown_value")
        )
    end
end

local GetGuildLanguage

local function PrintSlashStatus()
    local guildName = GetGuildInfo("player")
    if guildName then
        PrintLocalized("current_language", guildName, GetGuildLanguage())
    else
        PrintLocalized("default_language")
    end

    PrintLocalized("use_language")
    PrintLocalized("use_debug", GetDebugStatusText())
end

local function UsesSurnames()
    if RegionalUniqueNamesEnabled then
        return RegionalUniqueNamesEnabled()
    end
    local interfaceVersion
    if GetBuildInfo then
        local _, _, _, version = GetBuildInfo()
        interfaceVersion = version
    end
    return interfaceVersion and interfaceVersion >= 16000 and interfaceVersion < 20000
end

local function ReadableName(name)
    if issecretvalue and issecretvalue(name) then
        return nil
    end
    if type(name) ~= "string" then
        return nil
    end
    name = name:match("|Hplayer:([^:|]+)") or name
    name = name:match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

local function SplitCharacterName(name)
    name = ReadableName(name)
    if not name then
        return nil
    end
    local separators = Constants and Constants.CharacterNameSeparatorConsts
    local separator = separators and separators.CHARACTERNAME_SURNAME_SEPARATOR or " "
    local startAt, endAt = name:find(separator, 1, true)
    if not startAt and separator ~= " " then
        -- Accept the human-readable "First Last" form in slash commands too.
        startAt, endAt = name:find(" ", 1, true)
    end
    if startAt then
        return ReadableName(name:sub(1, startAt - 1)), ReadableName(name:sub(endAt + 1))
    end
    return name
end

local function SafeAmbiguate(name)
    name = ReadableName(name)
    if not name then
        return nil
    end

    if UsesSurnames() then
        local firstName, surname = SplitCharacterName(name)
        if firstName and surname then
            return firstName .. " " .. surname
        end
        return firstName
    end

    if Ambiguate then
        return Ambiguate(name, "guild")
    end

    return name
end

CanonicalizeName = function(name)
    local displayName = SafeAmbiguate(name)
    if not displayName then
        return nil
    end

    if UsesSurnames() then
        local firstName, surname = SplitCharacterName(name)
        if not firstName or not surname then
            -- A first name alone is never a Forever player identity.
            return nil
        end
        displayName = (firstName .. " " .. surname):gsub("%s+", " ")
    else
        displayName = displayName:gsub("%s+", "")
    end
    if strlower then
        displayName = strlower(displayName)
    else
        displayName = string.lower(displayName)
    end

    return displayName
end

local function GetPlayerFullName()
    local name, surname
    if UsesSurnames() and UnitNameUnmodified then
        name, surname = UnitNameUnmodified("player")
    else
        name, surname = UnitName("player")
    end
    name = ReadableName(name)
    if not name then
        return nil
    end
    if UsesSurnames() then
        local firstName, includedSurname = SplitCharacterName(name)
        if includedSurname then
            return firstName .. " " .. includedSurname
        end
        surname = ReadableName(surname)
        return surname and (name .. " " .. surname) or nil
    end
    return name
end

local function GetPlayerCanonicalName()
    return CanonicalizeName(GetPlayerFullName())
end

local function NormalizeLookupKey(value)
    if not value then
        return nil
    end

    local replacements = {
        ["à"] = "a", ["á"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a",
        ["ç"] = "c",
        ["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e",
        ["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i",
        ["ñ"] = "n",
        ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ø"] = "o",
        ["ß"] = "ss",
        ["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u",
        ["ý"] = "y", ["ÿ"] = "y",
        ["æ"] = "ae",
        ["œ"] = "oe",
    }

    local normalized = value:gsub("[%s%-%'_]", "")
    if strlower then
        normalized = strlower(normalized)
    else
        normalized = string.lower(normalized)
    end

    normalized = normalized:gsub("[àáâãäåçèéêëìíîïñòóôõöøßùúûüýÿæœ]", replacements)

    return normalized
end

local function ResetRosterState(newGuildKey)
    state.rosterGeneration = state.rosterGeneration + 1
    state.guildKey = newGuildKey
    state.rosterReady = false
    state.rosterBaselineStartedAt = nil
    state.members = {}
    state.recentGreetings = {}
    state.lastMessageByLanguage = {}
    state.recentMessagesByLanguage = {}
    state.activeWhoDebugRequest = nil
    state.pendingSystemJoins = {}
    state.pendingGreetings = {}
    state.combatDeferredGreetings = {}
    state.addonPeers = {}
    state.lastSpecialSpeaker = nil
    state.specialTurns = {}
end

local function GetGuildJoinPattern()
    local guildJoinTemplate = ERR_GUILD_JOIN_S or "%s has joined the guild."
    local escapedTemplate = guildJoinTemplate:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    -- Escaping the template turns %s into %%s; replace both percent signs.
    return "^" .. escapedTemplate:gsub("%%%%s", "(.+)") .. "$"
end

local FindGuildMemberInfoByName
local GreetNewMember
local RefreshGuildRoster

local function HandleSystemMessage(message)
    if issecretvalue and issecretvalue(message) then
        return
    end

    if not message or message == "" or not IsInGuild() then
        return
    end

    local joinPattern = GetGuildJoinPattern()
    local joinedName = message:match(joinPattern)
    if not joinedName or joinedName == "" then
        return
    end

    local canonicalName = CanonicalizeName(joinedName)
    if not canonicalName then
        -- Forever can announce a first name before the new roster arrives.
        -- Resolve it only if the updated roster identifies one member.
        local guildKey = state.guildKey
        local generation = state.rosterGeneration
        RefreshGuildRoster()
        RunAfterDelay(2, function()
            if state.rosterGeneration ~= generation or state.guildKey ~= guildKey then
                return
            end
            local memberInfo = FindGuildMemberInfoByName(joinedName, true)
            if memberInfo and state.rosterReady and not state.members[CanonicalizeName(memberInfo.fullName)] then
                GreetNewMember(memberInfo)
            end
        end)
        return
    end
    if canonicalName == GetPlayerCanonicalName() then
        return
    end

    state.pendingSystemJoins[canonicalName] = {
        detectedAt = GetTime(),
        joinedName = joinedName,
    }
    RefreshGuildRoster()

    RunAfterDelay(2, function()
        local pendingJoin = state.pendingSystemJoins[canonicalName]
        if not pendingJoin or state.pendingGreetings[canonicalName] then
            return
        end

        local memberInfo = FindGuildMemberInfoByName(pendingJoin.joinedName)
        if memberInfo then
            GreetNewMember(memberInfo)
            state.pendingSystemJoins[canonicalName] = nil
        else
            RefreshGuildRoster()
        end
    end)
end

local function GetGuildKey()
    local guildName, _, _, realmName = GetGuildInfo("player")
    if not guildName or guildName == "" then
        return nil
    end

    if not realmName or realmName == "" then
        realmName = GetRealmName()
    end
    if not realmName or realmName == "" then
        return nil
    end
    return realmName .. "::" .. guildName
end

local function EnsureDatabase()
    if type(GuildWelcomerDB) ~= "table" then
        GuildWelcomerDB = {}
    end

    if type(GuildWelcomerDB.guildLanguages) ~= "table" then
        GuildWelcomerDB.guildLanguages = {}
    end

    if type(GuildWelcomerDB.debugEnabled) ~= "boolean" then
        GuildWelcomerDB.debugEnabled = false
    end

end

GetGuildLanguage = function()
    local guildKey = GetGuildKey()
    if not guildKey then
        return "EN"
    end

    local language = GuildWelcomerDB.guildLanguages[guildKey]
    if SUPPORTED_LANGUAGES[language] then
        return language
    end

    return "EN"
end

local function SetGuildLanguage(language)
    local guildKey = GetGuildKey()
    if not guildKey then
        return false
    end

    if guildKey ~= state.guildKey then
        ResetRosterState(guildKey)
    end
    GuildWelcomerDB.guildLanguages[guildKey] = language
    return true
end

local function GetAddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0"
    end

    if GetAddOnMetadata then
        return GetAddOnMetadata(ADDON_NAME, "Version") or "0"
    end

    return "0"
end

local function SendGuildAddonMessage(message)
    if not IsInGuild() then
        return
    end

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(ADDON_MESSAGE_PREFIX, message, "GUILD")
    elseif SendAddonMessage then
        SendAddonMessage(ADDON_MESSAGE_PREFIX, message, "GUILD")
    end
end

local function SendPresence()
    local enabled = GetGuildLanguage() ~= "OFF" and "1" or "0"
    SendGuildAddonMessage("P|" .. GetAddonVersion() .. "|" .. enabled)
end

local function SendElectionQuery(canonicalName)
    SendGuildAddonMessage("Q|" .. canonicalName)
    SendPresence()
end

local function CompareVersions(left, right)
    local leftParts = {}
    local rightParts = {}

    for part in tostring(left or "0"):gmatch("%d+") do
        leftParts[#leftParts + 1] = tonumber(part) or 0
    end

    for part in tostring(right or "0"):gmatch("%d+") do
        rightParts[#rightParts + 1] = tonumber(part) or 0
    end

    local partCount = math.max(#leftParts, #rightParts)
    for index = 1, partCount do
        local leftPart = leftParts[index] or 0
        local rightPart = rightParts[index] or 0
        if leftPart ~= rightPart then
            return leftPart > rightPart and 1 or -1
        end
    end

    return 0
end


local function SelectSpecialSpeaker()
    local now = GetTime and GetTime() or 0
    local candidates = {}
    local highestVersion = nil
    local playerName = GetPlayerCanonicalName()

    local function AddCandidate(name, version)
        if not highestVersion or CompareVersions(version, highestVersion) > 0 then
            highestVersion = version
            candidates = { name }
        elseif CompareVersions(version, highestVersion) == 0 then
            candidates[#candidates + 1] = name
        end
    end

    if GetGuildLanguage() ~= "OFF" and playerName then
        AddCandidate(playerName, GetAddonVersion())
    end

    for peerName, peer in pairs(state.addonPeers) do
        if peer.enabled and (now - peer.lastSeen) <= PEER_FRESHNESS_SECONDS then
            AddCandidate(peerName, peer.version)
        end
    end

    table.sort(candidates)
    if #candidates == 0 then
        return nil
    end

    if state.lastSpecialSpeaker then
        for index, candidateName in ipairs(candidates) do
            if candidateName == state.lastSpecialSpeaker then
                return candidates[(index % #candidates) + 1]
            end
        end
    end

    return candidates[1]
end

local function AnnounceSpecialSpeaker(targetName, speakerName)
    state.lastSpecialSpeaker = speakerName
    state.specialTurns[targetName] = {
        speaker = speakerName,
        receivedAt = GetTime and GetTime() or 0,
    }
    SendGuildAddonMessage("T|" .. targetName .. "|" .. speakerName)
end

local function HandleAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_MESSAGE_PREFIX or channel ~= "GUILD" or not message then
        return
    end

    local version, enabled = message:match("^P|([^|]+)|([01])$")
    if version then
        local peerName = CanonicalizeName(sender)
        if peerName and peerName ~= GetPlayerCanonicalName() then
            state.addonPeers[peerName] = {
                version = version,
                enabled = enabled == "1",
                displayName = SafeAmbiguate(sender) or sender,
                lastSeen = GetTime and GetTime() or 0,
            }
        end
        return
    end

    local queriedName = message:match("^Q|(.+)$")
    if queriedName then
        if UsesSurnames() then
            queriedName = CanonicalizeName(queriedName)
            if not queriedName then
                return
            end
        end
        SendPresence()

        if GetGuildLanguage() ~= "OFF" and not state.pendingGreetings[queriedName] then
            RunAfterDelay(0.2, function()
                if state.pendingGreetings[queriedName] then
                    return
                end

                local memberInfo = FindGuildMemberInfoByName(queriedName)
                if memberInfo then
                    GreetNewMember(memberInfo)
                else
                    RefreshGuildRoster()
                end
            end)
        end
        return
    end

    local targetName, speakerName = message:match("^T|([^|]+)|([^|]+)$")
    if speakerName then
        if UsesSurnames() then
            targetName = CanonicalizeName(targetName)
            speakerName = CanonicalizeName(speakerName)
            if not targetName or not speakerName then
                return
            end
        end
        state.lastSpecialSpeaker = speakerName
        state.specialTurns[targetName] = {
            speaker = speakerName,
            receivedAt = GetTime and GetTime() or 0,
        }
    end
end

local function SeedRandom()
    local seed = time and time() or 1

    if math and math.randomseed then
        math.randomseed(seed)
    elseif randomseed then
        randomseed(seed)
    end
end

local function GetRandomIndex(max)
    if math and math.random then
        return math.random(max)
    end

    if random then
        return random(max)
    end

    return 1
end

local function GetRandomGreetingDelay()
    return GetRandomIndex(5)
end

local function AppendMessages(target, messages)
    if type(messages) ~= "table" then
        return
    end

    for index = 1, #messages do
        target[#target + 1] = messages[index]
    end
end

local function AppendTaggedMessages(target, messages, sourceLabel)
    if type(messages) ~= "table" then
        return
    end

    for index = 1, #messages do
        local message = messages[index]
        if type(message) == "table" then
            target[#target + 1] = message
        else
            target[#target + 1] = {
                text = message,
                source = sourceLabel,
            }
        end
    end
end

local function ResolveLanguageMessages(source, language, key)
    local languageMessages = source[language]
    if languageMessages and languageMessages[key] then
        return languageMessages[key]
    end
end

local function GetMessageCooldownSize(messageCount)
    if messageCount >= 60 then
        return 18
    end

    if messageCount >= 30 then
        return 14
    end

    if messageCount >= 16 then
        return 10
    end

    if messageCount >= 8 then
        return 6
    end

    if messageCount >= 4 then
        return 3
    end

    return 1
end

local function IsMessageOnCooldown(language, cooldownKey)
    local recentMessages = state.recentMessagesByLanguage[language]
    if not recentMessages then
        return false
    end

    for _, recentMessage in ipairs(recentMessages) do
        if recentMessage == cooldownKey then
            return true
        end
    end

    return false
end

local function RememberRecentMessage(language, cooldownKey, messageCount)
    local cooldownSize = GetMessageCooldownSize(messageCount)
    local recentMessages = state.recentMessagesByLanguage[language]

    if not recentMessages then
        recentMessages = {}
        state.recentMessagesByLanguage[language] = recentMessages
    end

    recentMessages[#recentMessages + 1] = cooldownKey

    while #recentMessages > cooldownSize do
        table.remove(recentMessages, 1)
    end
end

local function GetPoolEntryText(entry)
    if type(entry) == "table" then
        return entry.text
    end

    return entry
end

local function GetPoolEntrySource(entry)
    if type(entry) == "table" then
        return entry.source
    end

    return nil
end

local function GetPoolEntryCooldownKey(entry)
    if type(entry) == "table" and entry.cooldownKey then
        return entry.cooldownKey
    end

    return GetPoolEntryText(entry)
end

local function PickRandomFromPool(language, messages)
    if #messages == 0 then
        return nil
    end

    local index = GetRandomIndex(#messages)
    local message = messages[index]
    local messageText = GetPoolEntryText(message)
    local cooldownKey = GetPoolEntryCooldownKey(message)
    local lastMessage = state.lastMessageByLanguage[language]

    if #messages > 1 and lastMessage == messageText then
        index = (index % #messages) + 1
        message = messages[index]
        messageText = GetPoolEntryText(message)
        cooldownKey = GetPoolEntryCooldownKey(message)
    end

    if #messages > 2 and IsMessageOnCooldown(language, cooldownKey) then
        for candidateIndex = 1, #messages do
            local candidateMessage = messages[candidateIndex]
            local candidateText = GetPoolEntryText(candidateMessage)
            local candidateCooldownKey = GetPoolEntryCooldownKey(candidateMessage)
            if candidateText ~= lastMessage and not IsMessageOnCooldown(language, candidateCooldownKey) then
                message = candidateMessage
                messageText = candidateText
                cooldownKey = candidateCooldownKey
                break
            end
        end
    end

    state.lastMessageByLanguage[language] = messageText
    RememberRecentMessage(language, cooldownKey, #messages)
    return messageText, GetPoolEntrySource(message)
end

local function BuildGreetingPool(language, profile)
    local vipMessage = ResolveVIPWelcomeMessage(language, profile)
    if vipMessage then
        return {
            {
                text = vipMessage,
                source = "VIP",
                cooldownKey = "VIP:" .. profile.nameKey,
            },
        }
    end

    local genericMessages = {}
    local themedMessages = {}
    local nameMessages = {}

    AppendTaggedMessages(genericMessages, WELCOME_MESSAGES[language] or WELCOME_MESSAGES.EN, "generic")
    AppendTaggedMessages(genericMessages, ResolveGeneratedWelcomeMessages(language), "generated")

    if profile then
        if profile.classKey then
            AppendTaggedMessages(themedMessages, ResolveLanguageMessages(CLASS_WELCOME_MESSAGES, language, profile.classKey), "class")
            AppendTaggedMessages(themedMessages, ResolveLanguageMessages(EXTRA_CLASS_WELCOME_MESSAGES, language, profile.classKey), "class")
            AppendTaggedMessages(themedMessages, ResolveLanguageMessages(BONUS_CLASS_WELCOME_MESSAGES, language, profile.classKey), "class")
            AppendTaggedMessages(themedMessages, ResolveLanguageMessages(EPIC_CLASS_WELCOME_MESSAGES, language, profile.classKey), "class")
            AppendTaggedMessages(themedMessages, ResolveLanguageMessages(BANTER_CLASS_WELCOME_MESSAGES, language, profile.classKey), "class")
        end

        AppendNameMessages(nameMessages, language, profile)
        if #nameMessages > 0 then
            AppendTaggedMessages(themedMessages, nameMessages, "name")
        end
    end

    if profile and profile.nameKey and profile.nameKey:match("^nya") and #nameMessages > 0 then
        local prioritizedNameMessages = {}
        AppendTaggedMessages(prioritizedNameMessages, nameMessages, "name")
        return prioritizedNameMessages
    end

    if #nameMessages > 0 and GetRandomIndex(100) <= 75 then
        local prioritizedNameMessages = {}
        AppendTaggedMessages(prioritizedNameMessages, nameMessages, "name")
        return prioritizedNameMessages
    end

    if #themedMessages > 0 and GetRandomIndex(100) <= 40 then
        return themedMessages
    end

    local combinedMessages = {}
    AppendMessages(combinedMessages, genericMessages)
    AppendMessages(combinedMessages, themedMessages)
    return combinedMessages
end

local function ResolveClassKey(className, classFileName)
    if classFileName and classFileName ~= "" then
        return string.upper(classFileName)
    end

    return CLASS_NAME_ALIASES[NormalizeLookupKey(className or "")]
end

local function PickGreetingMessage(language, profile)
    local messages = BuildGreetingPool(language, profile)
    return PickRandomFromPool(language, messages)
end

local function GetSpeakerDisplayName(canonicalName)
    if not canonicalName then
        return GetUIText("unknown_value")
    end

    if canonicalName == GetPlayerCanonicalName() then
        return SafeAmbiguate(GetPlayerFullName()) or canonicalName
    end

    local peer = state.addonPeers[canonicalName]
    return peer and peer.displayName or canonicalName
end

local function GetShortName(name)
    if not name then
        return nil
    end

    return SafeAmbiguate(name) or name
end

local FormatGreetingMessage

local function ScheduleGreeting(canonicalName, displayName, guildKey, profile, coordinated, fullName)
    local rosterGeneration = state.rosterGeneration
    local ticket = state.pendingGreetings[canonicalName]
    local welcomeAt = GetTime() + 10
    local function PrepareGreeting()
        if state.rosterGeneration ~= rosterGeneration or state.pendingGreetings[canonicalName] ~= ticket then
            return
        end
        if not IsInGuild() or state.guildKey ~= guildKey or GetGuildLanguage() == "OFF" then
            state.pendingGreetings[canonicalName] = nil
            return
        end

        local language = GetGuildLanguage()
        if coordinated then
            local now = GetTime and GetTime() or 0
            local existingTurn = state.specialTurns[canonicalName]
            local hasCurrentTurn = existingTurn and (now - existingTurn.receivedAt) <= PEER_FRESHNESS_SECONDS
            local selectedSpeaker
            if hasCurrentTurn then
                selectedSpeaker = existingTurn.speaker
            else
                selectedSpeaker = SelectSpecialSpeaker()
            end

            local isSelectedSpeaker = selectedSpeaker == GetPlayerCanonicalName()
            if isSelectedSpeaker and not hasCurrentTurn then
                AnnounceSpecialSpeaker(canonicalName, selectedSpeaker)
            elseif not isSelectedSpeaker then
                state.pendingGreetings[canonicalName] = nil
                if IsDebugEnabled() then
                    PrintLocalized(
                        "coordination_not_selected",
                        GetSpeakerDisplayName(selectedSpeaker),
                        displayName
                    )
                end
                return
            end
        end

        local formattedMessage
        if coordinated then
            local firstName = (UsesSurnames() and SplitCharacterName(fullName)) or displayName
            local guildName = GetGuildInfo("player")
            if not guildName then
                state.pendingGreetings[canonicalName] = nil
                return
            end
            formattedMessage = string.format("Welcome to %s, %s! Glad you’re here.", guildName, firstName)
        else
            local message, poolLabel = PickGreetingMessage(language, profile)
            profile.poolLabel = poolLabel or "unknown"
            DebugPrintGreetingProfile(displayName, profile)
            formattedMessage = FormatGreetingMessage(message, displayName)
        end

        local function SendGreeting()
            if state.rosterGeneration ~= rosterGeneration or state.pendingGreetings[canonicalName] ~= ticket then
                return
            end

            if InCombatLockdown and InCombatLockdown() then
                state.combatDeferredGreetings[canonicalName] = SendGreeting
                return
            end

            state.combatDeferredGreetings[canonicalName] = nil
            state.pendingGreetings[canonicalName] = nil

            if not IsInGuild() or state.guildKey ~= guildKey or GetGuildLanguage() == "OFF" then
                return
            end

            if coordinated and not FindGuildMemberInfoByName(fullName) then
                return
            end

            if C_ChatInfo and C_ChatInfo.SendChatMessage then
                C_ChatInfo.SendChatMessage("[René] " .. formattedMessage, "GUILD")
            else
                SendChatMessage("[René] " .. formattedMessage, "GUILD")
            end
        end

        if coordinated then
            RunAfterDelay(math.max(0, welcomeAt - GetTime()), SendGreeting)
        else
            RunAfterDelay(GetRandomGreetingDelay(), SendGreeting)
        end
    end

    if coordinated then
        SendElectionQuery(canonicalName)
        RunAfterDelay(COORDINATION_WINDOW_SECONDS, PrepareGreeting)
    else
        PrepareGreeting()
    end
end

local function FlushCombatDeferredGreetings()
    local deferredGreetings = state.combatDeferredGreetings
    state.combatDeferredGreetings = {}

    for _, sendGreeting in pairs(deferredGreetings) do
        sendGreeting()
    end
end

local function BuildGreetingProfile(memberInfo)
    local name = GetShortName(memberInfo.fullName)
    local profile = {
        class = memberInfo.className,
        classKey = ResolveClassKey(memberInfo.className, memberInfo.classFileName),
        name = name,
        nameKey = NormalizeLookupKey(name),
    }
    if UsesSurnames() then
        local firstName, surname = SplitCharacterName(memberInfo.fullName)
        profile.firstNameKey = NormalizeLookupKey(firstName)
        profile.surnameKey = NormalizeLookupKey(surname)
        -- Keep a boundary: "Dar Kness" must not match the "dark" fragment.
        profile.nameKey = (profile.firstNameKey or "") .. " " .. (profile.surnameKey or "")
    end
    return profile
end

FormatGreetingMessage = function(message, name)
    if UnitFactionGroup and UnitFactionGroup("player") == "Horde" then
        for allianceText, hordeText in pairs(HORDE_MESSAGE_REPLACEMENTS) do
            message = message:gsub(allianceText, hordeText)
        end
    end

    local safeMessage = message:gsub("%%(.)", function(character)
        if character == "s" or character == "%" then
            return "%" .. character
        end

        return "%%" .. character
    end)

    safeMessage = safeMessage:gsub("%%$", "%%%%")
    return string.format(safeMessage, name)
end

GreetNewMember = function(memberInfo)
    local name = memberInfo and memberInfo.fullName
    if not name or name == "" or not IsInGuild() or GetGuildLanguage() == "OFF" then
        return
    end

    local canonicalName = CanonicalizeName(name)
    if not canonicalName or canonicalName == GetPlayerCanonicalName() then
        return
    end

    local now = GetTime and GetTime() or 0
    local lastGreeting = state.recentGreetings[canonicalName]
    if lastGreeting and (now - lastGreeting) < 10 then
        return
    end

    if state.pendingGreetings[canonicalName] then
        return
    end

    state.recentGreetings[canonicalName] = now
    state.pendingGreetings[canonicalName] = {}
    local shortName = GetShortName(name)
    ScheduleGreeting(canonicalName, shortName, state.guildKey, BuildGreetingProfile(memberInfo), true, name)
end

local function QueueManualGreeting(memberInfo)
    local name = memberInfo and memberInfo.fullName
    if not name or name == "" or not IsInGuild() or GetGuildLanguage() == "OFF" then
        return false
    end

    local canonicalName = CanonicalizeName(name)
    if not canonicalName then
        return false
    end

    if canonicalName == GetPlayerCanonicalName() then
        PrintLocalized("manual_greet_self")
        return false
    end

    if state.pendingGreetings[canonicalName] then
        return false
    end

    state.recentGreetings[canonicalName] = GetTime and GetTime() or 0
    state.pendingGreetings[canonicalName] = true

    local shortName = GetShortName(name)
    ScheduleGreeting(canonicalName, shortName, state.guildKey, BuildGreetingProfile(memberInfo))

    PrintLocalized("manual_greet_sent", shortName or name)
    return true
end

local function BuildRosterSnapshot()
    local snapshot = {}
    local totalMembers = GetNumGuildMembers and GetNumGuildMembers() or 0
    local capturedMembers = 0

    for index = 1, totalMembers do
        local fullName, _, _, _, className, _, _, _, _, _, classFileName = GetGuildRosterInfo(index)
        if fullName then
            local canonicalName = CanonicalizeName(fullName)
            if canonicalName then
                if not snapshot[canonicalName] then
                    capturedMembers = capturedMembers + 1
                end
                snapshot[canonicalName] = {
                    fullName = fullName,
                    className = className,
                    classFileName = classFileName,
                }
            end
        end
    end

    return snapshot, totalMembers, capturedMembers
end

RefreshGuildRoster = function()
    if not IsInGuild() then
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

FindGuildMemberInfoByName = function(query, allowFirstName)
    if not query or query == "" then
        return nil
    end

    if UsesSurnames() then
        local snapshot = BuildRosterSnapshot()
        local canonicalQuery = CanonicalizeName(query)
        if canonicalQuery then
            return snapshot[canonicalQuery]
        end
        if not allowFirstName then
            return nil
        end
        local firstQuery = ReadableName(query)
        if not firstQuery then
            return nil
        end
        local lower = strlower or string.lower
        local match
        for _, memberInfo in pairs(snapshot) do
            local firstName = SplitCharacterName(memberInfo.fullName)
            if firstName and lower(firstName) == lower(firstQuery) then
                if match then
                    return nil, "ambiguous"
                end
                match = memberInfo
            end
        end
        return match
    end

    local normalizedQuery = NormalizeLookupKey(query)
    if not normalizedQuery then
        return nil
    end

    local snapshot = BuildRosterSnapshot()
    for _, memberInfo in pairs(snapshot) do
        local fullName = memberInfo.fullName
        local shortName = GetShortName(fullName)
        if NormalizeLookupKey(fullName) == normalizedQuery or NormalizeLookupKey(shortName or fullName) == normalizedQuery then
            return memberInfo
        end
    end

    return nil
end

local function HandleGuildRosterUpdate()
    local guildKey = GetGuildKey()
    if guildKey ~= state.guildKey then
        ResetRosterState(guildKey)
    end

    if not guildKey then
        ResetRosterState(nil)
        return
    end

    local snapshot, totalMembers, capturedMembers = BuildRosterSnapshot()
    if totalMembers <= 0 or capturedMembers < totalMembers then
        return
    end

    if not state.rosterReady then
        for canonicalName, memberInfo in pairs(snapshot) do
            state.members[canonicalName] = memberInfo
        end

        local now = GetTime and GetTime() or 0
        if not state.rosterBaselineStartedAt then
            state.rosterBaselineStartedAt = now
            local rosterGeneration = state.rosterGeneration
            RunAfterDelay(ROSTER_BASELINE_SECONDS, function()
                if state.rosterGeneration == rosterGeneration and not state.rosterReady then
                    RefreshGuildRoster()
                end
            end)
            return
        end

        if (now - state.rosterBaselineStartedAt) < ROSTER_BASELINE_SECONDS then
            return
        end

        state.rosterReady = true
        return
    end

    for canonicalName, ticket in pairs(state.pendingGreetings) do
        if type(ticket) == "table" and not snapshot[canonicalName] then
            state.pendingGreetings[canonicalName] = nil
            state.combatDeferredGreetings[canonicalName] = nil
            state.recentGreetings[canonicalName] = nil
        end
    end

    -- System messages are not reliable on every client, so complete roster
    -- changes remain the primary fallback after the login baseline is stable.
    for canonicalName, memberInfo in pairs(snapshot) do
        if not state.members[canonicalName] or state.pendingSystemJoins[canonicalName] then
            GreetNewMember(memberInfo)
        end

        if state.pendingSystemJoins[canonicalName] then
            state.pendingSystemJoins[canonicalName] = nil
        end
    end

    local now = GetTime and GetTime() or 0
    for canonicalName, pendingJoin in pairs(state.pendingSystemJoins) do
        local detectedAt = type(pendingJoin) == "table" and pendingJoin.detectedAt or pendingJoin
        if (now - detectedAt) > 20 then
            state.pendingSystemJoins[canonicalName] = nil
        end
    end

    state.members = snapshot
end

local function HandleWhoListUpdate()
    local request = state.activeWhoDebugRequest
    if not request then
        return
    end

    local resultCount = GetWhoResultCount()
    if resultCount <= 0 then
        return
    end

    for index = 1, resultCount do
        local info = GetWhoResultInfo(index)
        if info and info.fullName and CanonicalizeWhoDebugName(info.fullName) == request.canonicalName then
            FinishDebugWhoLookup(true, request, info.race, info.class)
            return
        end
    end
end

local function HandleSlashCommand(message)
    local input = message and message:match("^%s*(.-)%s*$") or ""
    if input == "" then
        PrintSlashStatus()
        return
    end

    local normalizedInput = string.lower(input)
    if normalizedInput == "debug" then
        SetDebugEnabled(not IsDebugEnabled())

        if IsDebugEnabled() then
            PrintLocalized("debug_enabled")
        else
            PrintLocalized("debug_disabled")
        end

        PrintLocalized("use_debug", GetDebugStatusText())
        return
    end

    local language = string.upper(input)
    language = COMMAND_ALIASES[language] or language

    if not SUPPORTED_LANGUAGES[language] then
        local memberInfo, reason = FindGuildMemberInfoByName(input, true)
        if memberInfo then
            QueueManualGreeting(memberInfo)
        elseif reason == "ambiguous" then
            PrintLocalized("manual_greet_ambiguous", input)
        else
            PrintLocalized("manual_greet_missing", input)
            PrintLocalized("use_language")
            PrintLocalized("use_debug", GetDebugStatusText())
        end
        return
    end

    if not SetGuildLanguage(language) then
        PrintLocalized("join_guild")
        return
    end

    SendPresence()
    PrintLocalized("language_set", language)
    PrintLocalized("use_debug", GetDebugStatusText())
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then
            return
        end

        EnsureDatabase()
        SeedRandom()

        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(ADDON_MESSAGE_PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(ADDON_MESSAGE_PREFIX)
        end

        SLASH_GUILDWELCOMER1 = "/gw"
        SLASH_GUILDWELCOMER2 = "/guildwelcomer"
        SlashCmdList.GUILDWELCOMER = HandleSlashCommand
        return
    end

    if event == "PLAYER_LOGIN" then
        ResetRosterState(GetGuildKey())
        RefreshGuildRoster()
        RunAfterDelay(2, SendPresence)
        return
    end

    if event == "PLAYER_GUILD_UPDATE" then
        local guildKey = GetGuildKey()
        if guildKey ~= state.guildKey then
            ResetRosterState(guildKey)
        end
        RefreshGuildRoster()
        RunAfterDelay(2, SendPresence)
        return
    end

    if event == "GUILD_ROSTER_UPDATE" then
        HandleGuildRosterUpdate()
        return
    end

    if event == "CHAT_MSG_SYSTEM" then
        HandleSystemMessage(...)
        return
    end

    if event == "CHAT_MSG_ADDON" then
        HandleAddonMessage(...)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        FlushCombatDeferredGreetings()
        return
    end

end)
