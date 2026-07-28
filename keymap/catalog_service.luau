--!nonstrict
-- Runtime Noctalia command discovery for Keymap.
--
-- Core commands come from the running instance's IPC help. Plugin actions come
-- from manifest declarations, while concrete panels come from the live panel
-- registry. Newly installed plugins and future built-ins are never hard-coded.

local CATALOG_KEY = "keymap.runtime_command_catalog"
local REFRESH_KEY = "keymap.catalog_refresh_request"
local TIMEOUT_MS = 5000
local MAX_OUTPUT_BYTES = 512 * 1024

local refreshing = false
local refreshQueued = false
local refresh

local function trim(value)
	if type(value) ~= "string" then return "" end
	return value:match("^%s*(.-)%s*$") or ""
end

local function environment(name)
	local value = noctalia.getenv(name)
	return type(value) == "string" and value or ""
end

local function shellQuote(value)
	return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function ipcDisplay()
	local configured = environment("WAYLAND_DISPLAY")
	if configured ~= "" then return configured end
	local runtime = environment("XDG_RUNTIME_DIR")
	if runtime == "" then return nil end
	local entries = noctalia.listDir(runtime)
	if type(entries) ~= "table" then return nil end
	local present = {}
	for _, name in ipairs(entries) do
		if type(name) == "string" then present[name] = true end
	end
	local displays = {}
	for _, name in ipairs(entries) do
		if type(name) == "string" then
			local display = name:match("^noctalia%-(.-)%.sock$")
			-- Ignore auxiliary sockets such as noctalia-dmenu-wayland-1.sock;
			-- a real display also has a Wayland socket with the extracted name.
			if display ~= nil and display ~= "" and not display:find("%c") and present[display] then
				displays[#displays + 1] = display
			end
		end
	end
	table.sort(displays)
	return displays[1]
end

local function ipcCommand(arguments)
	local display = ipcDisplay()
	local prefix = display ~= nil and ("WAYLAND_DISPLAY=" .. shellQuote(display) .. " ") or ""
	return prefix .. "noctalia msg " .. arguments
end

local function categoryFor(command)
	if command:find("^color%-scheme") or command:find("^templates")
		or command:find("^theme%-mode") or command:find("^wallpaper") then return "appearance" end
	if command:find("^effects%-profile") or command:find("^mic%-")
		or command:find("^volume%-") then return "audio" end
	if command:find("^bar%-") then return "bars" end
	if command:find("^clipboard%-") then return "clipboard" end
	if command:find("^bluetooth%-") or command:find("^wifi%-") then return "connectivity" end
	if command:find("^brightness%-") or command:find("^dpms%-")
		or command:find("^keyboard%-backlight") then return "display" end
	if command == "media" then return "media" end
	if command:find("^notification%-") then return "notifications" end
	if command:find("^dock%-") or command:find("^panel%-")
		or command:find("^settings%-") or command == "window-switcher" then return "panels" end
	if command == "plugin" or command == "plugins" then return "plugins" end
	if command:find("^caffeine%-") or command:find("^nightlight%-")
		or command:find("^power%-") then return "power" end
	if command:find("^screenshot%-") then return "screenshots" end
	if command == "session" then return "session" end
	if command:find("^desktop%-widgets") or command:find("^lockscreen%-widgets") then return "widgets" end
	if command:find("^workspace%-") then return "workspaces" end
	return "system"
end

local function placeholderName(value)
	local name = trim(value):lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
	return name ~= "" and name or "value"
end

local function requiredCount(usage)
	local count = 0
	for _ in usage:gmatch("<[^>]+>") do count = count + 1 end
	return count
end

local function appendHelpEntry(entries, command, usage, variant)
	local suffix = variant ~= nil and ("/" .. variant) or ""
	local template
	if variant ~= nil then
		template = "noctalia msg " .. command .. " " .. variant
		if usage:find("...", 1, true) ~= nil then template = template .. " {{arguments}}" end
	elseif requiredCount(usage) == 0 then
		template = "noctalia msg " .. command
	else
		local firstForm = usage:match("^(.-)%s+|%s+") or usage
		firstForm = firstForm:gsub("%s*%b[]", "")
		template = "noctalia msg " .. firstForm:gsub("<([^>]+)>", function(argument)
			return "{{" .. placeholderName(argument) .. "}}"
		end)
	end
	entries[#entries + 1] = {
		id = "noctalia/" .. command .. suffix,
		source = "noctalia",
		origin = "core",
		module = "noctalia",
		module_name = "Noctalia",
		category = categoryFor(command),
		kind = "shell",
		template = template,
		usage = usage,
	}
end

local function originForSource(source)
	if source == "official" then return "official" end
	if source == "community" then return "community" end
	if source == "core" then return "core" end
	return "development"
end

local function parsePluginList(output)
	local plugins = {}
	if type(output) ~= "string" or #output > MAX_OUTPUT_BYTES then return plugins end
	for line in (output .. "\n"):gmatch("([^\n]*)\n") do
		local pluginId, source = line:match("^(%S+)%s+%[([^%]]+)%]")
		if pluginId ~= nil and pluginId:match("^[%w_.%-]+/[%w_.%-]+$") then
			plugins[pluginId] = {
				id = pluginId,
				name = pluginId,
				source = source,
				origin = originForSource(source),
			}
		end
	end
	return plugins
end

local function appendDeclaredPluginCommands(entries, plugins, output)
	if type(output) ~= "string" or #output > MAX_OUTPUT_BYTES
		or type(noctalia.json) ~= "table" or type(noctalia.json.decode) ~= "function" then return end
	local ok, decoded = pcall(noctalia.json.decode, output)
	if not ok or type(decoded) ~= "table" or type(decoded.plugins) ~= "table" then return end
	for _, rawPlugin in ipairs(decoded.plugins) do
		if type(rawPlugin) == "table" and type(rawPlugin.id) == "string"
			and rawPlugin.id:match("^[%w_.%-]+/[%w_.%-]+$") then
			local metadata = plugins[rawPlugin.id] or { id = rawPlugin.id }
			metadata.name = trim(rawPlugin.name) ~= "" and trim(rawPlugin.name) or rawPlugin.id
			metadata.source = trim(rawPlugin.source) ~= "" and trim(rawPlugin.source) or metadata.source
			metadata.origin = originForSource(metadata.source)
			plugins[rawPlugin.id] = metadata
			for _, command in ipairs(type(rawPlugin.commands) == "table" and rawPlugin.commands or {}) do
				if type(command) == "table" and type(command.entry) == "string"
					and type(command.event) == "string" and command.entry:match("^[%w_.%-]+$")
					and command.event:match("^[%w_.%-]+$") then
					local target = trim(command.target) ~= "" and trim(command.target) or "all"
					local template = "noctalia msg plugin " .. rawPlugin.id .. ":" .. command.entry
						.. " " .. target .. " " .. command.event
					local payload = trim(command.payload)
					if payload ~= "" then template = template .. " " .. payload end
					entries[#entries + 1] = {
						id = "plugin/" .. rawPlugin.id .. "/" .. tostring(command.id or command.event),
						source = "noctalia",
						origin = metadata.origin,
						module = rawPlugin.id,
						module_name = metadata.name,
						category = trim(command.category) ~= "" and trim(command.category) or "plugins",
						kind = "shell",
						template = template,
						usage = trim(command.description) ~= "" and trim(command.description)
							or (command.event .. (payload ~= "" and (" " .. payload) or "")),
					}
				end
			end
		end
	end
end

local function parseHelp(output)
	local entries = {}
	if type(output) ~= "string" or #output > MAX_OUTPUT_BYTES then return entries end
	for line in (output .. "\n"):gmatch("([^\n]*)\n") do
		local usage = line:match("^  (.-)%s%s+%S")
		local command = usage ~= nil and usage:match("^(%S+)") or nil
		if command ~= nil and command:match("^[%w%-]+$") then
			local enum = usage:match("<([^<>]*|[^<>]*)>")
			if enum ~= nil and requiredCount(usage) == 1 then
				local variants = {}
				local valid = true
				for value in enum:gmatch("[^|]+") do
					local normalizedValue = trim(value)
					if not normalizedValue:match("^[%w*_.%-]+$") then valid = false break end
					variants[#variants + 1] = normalizedValue
				end
				if valid and #variants > 1 then
					for _, value in ipairs(variants) do appendHelpEntry(entries, command, usage, value) end
				else
					appendHelpEntry(entries, command, usage, nil)
				end
			else
				appendHelpEntry(entries, command, usage, nil)
			end
		end
	end
	return entries
end

local function appendPanels(entries, plugins, output)
	if type(output) ~= "string" or #output > MAX_OUTPUT_BYTES then return end
	local available = output:match("%(available:%s*(.-)%)")
	if available == nil then return end
	for panelId in available:gmatch("[^,]+") do
		local normalizedPanelId = trim(panelId)
		if normalizedPanelId:match("^[%w_./:%-]+$") then
			local pluginId = normalizedPanelId:match("^(.+):[^:]+$")
			local metadata = pluginId ~= nil and plugins[pluginId] or nil
			local origin = metadata ~= nil and metadata.origin or "core"
			local moduleId = pluginId or "noctalia"
			local moduleName = metadata ~= nil and metadata.name or (pluginId or "Noctalia")
			for _, action in ipairs({ "panel-open", "panel-toggle", "panel-close" }) do
				entries[#entries + 1] = {
					id = "noctalia/" .. action .. "/" .. normalizedPanelId:gsub(":", "/"),
					source = "noctalia",
					origin = origin,
					module = moduleId,
					module_name = moduleName,
					category = normalizedPanelId:find(":", 1, true) ~= nil and "plugins" or "panels",
					kind = "shell",
					template = "noctalia msg " .. action .. " " .. normalizedPanelId,
					usage = action .. " " .. normalizedPanelId,
				}
			end
		end
	end
end

local function publish(status, entries, errorCode)
	local unique = {}
	local deduplicated = {}
	for _, entry in ipairs(entries) do
		local key = tostring(entry.template or "")
		if key ~= "" and not unique[key] then
			unique[key] = true
			deduplicated[#deduplicated + 1] = entry
		end
	end
	entries = deduplicated
	table.sort(entries, function(left, right)
		local leftKey = tostring(left.origin) .. "\0" .. tostring(left.module_name)
			.. "\0" .. tostring(left.category) .. "\0" .. tostring(left.id)
		local rightKey = tostring(right.origin) .. "\0" .. tostring(right.module_name)
			.. "\0" .. tostring(right.category) .. "\0" .. tostring(right.id)
		return leftKey < rightKey
	end)
	noctalia.state.set(CATALOG_KEY, {
		status = status,
		entries = entries,
		error = errorCode or "",
		updated_at = os.date("%H:%M:%S"),
	})
end

local function finish()
	refreshing = false
	if refreshQueued then
		refreshQueued = false
		refresh()
	end
end

refresh = function()
	if refreshing then refreshQueued = true return end
	refreshing = true
	noctalia.state.set(CATALOG_KEY, { status = "loading", entries = {} })
	if not noctalia.commandExists("noctalia") then
		publish("error", {}, "noctalia_not_found")
		finish()
		return
	end
	local started = noctalia.runAsync(ipcCommand("--help"), function(helpResult)
		local helpOutput = tostring(helpResult.stdout or "") .. tostring(helpResult.stderr or "")
		local entries = helpResult.timedOut ~= true and helpResult.exitCode == 0 and parseHelp(helpOutput) or {}
		local listStarted = noctalia.runAsync(ipcCommand("plugins list"), function(listResult)
			local listOutput = tostring(listResult.stdout or "") .. tostring(listResult.stderr or "")
			local plugins = parsePluginList(listOutput)
			local function queryPanels()
				local panelStarted = noctalia.runAsync(ipcCommand("panel-toggle __keymap_catalog_probe__"), function(panelResult)
					local panelOutput = tostring(panelResult.stdout or "") .. tostring(panelResult.stderr or "")
					appendPanels(entries, plugins, panelOutput)
					publish(#entries > 0 and "ready" or "error", entries, #entries > 0 and "" or "discovery_failed")
					finish()
				end, TIMEOUT_MS)
				if not panelStarted then
					publish(#entries > 0 and "ready" or "error", entries, #entries > 0 and "" or "panel_discovery_failed")
					finish()
				end
			end
			local commandsStarted = noctalia.runAsync(ipcCommand("plugins commands"), function(commandsResult)
				if commandsResult.timedOut ~= true and commandsResult.exitCode == 0 then
					appendDeclaredPluginCommands(
						entries, plugins,
						tostring(commandsResult.stdout or "") .. tostring(commandsResult.stderr or "")
					)
				end
				queryPanels()
			end, TIMEOUT_MS)
			if not commandsStarted then queryPanels() end
		end, TIMEOUT_MS)
		if not listStarted then
			local plugins = {}
			local panelStarted = noctalia.runAsync(ipcCommand("panel-toggle __keymap_catalog_probe__"), function(panelResult)
				appendPanels(entries, plugins, tostring(panelResult.stdout or "") .. tostring(panelResult.stderr or ""))
				publish(#entries > 0 and "ready" or "error", entries, #entries > 0 and "" or "discovery_failed")
				finish()
			end, TIMEOUT_MS)
			if not panelStarted then publish("error", entries, "panel_discovery_failed") finish() end
		end
	end, TIMEOUT_MS)
	if not started then
		publish("error", {}, "discovery_start_failed")
		finish()
	end
end

function onIpc(event, _payload)
	if event == "refresh" then refresh() end
end

function onConfigChanged()
	refresh()
end

function update()
end

noctalia.state.watch(REFRESH_KEY, function(_request) refresh() end)
refresh()
