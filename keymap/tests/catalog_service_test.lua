local stateValues = {}
local watchers = {}
local commands = {}

local help = [[Usage: noctalia msg <command> [args]

Commands:
  media <next|previous|toggle>          Control media
  panel-open <id> [context]             Open a panel
  plugins <list|enable|disable|update|source> ...  Manage plugins
  volume-up [step]                      Increase volume
  effects-profile-set <output|input> <profile>  Select a profile
]]

noctalia = {
	state = {
		get = function(key) return stateValues[key] end,
		set = function(key, value) stateValues[key] = value end,
		watch = function(key, callback) watchers[key] = callback end,
	},
	getenv = function(name)
		if name == "XDG_RUNTIME_DIR" then return "/run/user/1000" end
		return ""
	end,
	listDir = function(path)
		if path == "/run/user/1000" then
			return { "noctalia-dmenu-wayland-9.sock", "noctalia-wayland-9.sock", "wayland-9" }
		end
		return {}
	end,
	commandExists = function(command) return command == "noctalia" end,
	json = { decode = function(_output)
		return {
			schema = 1,
			plugins = {
				{
					id = "someone/new-plugin", name = "New Plugin", source = "community",
					commands = {
						{
							id = "do-thing", entry = "service", target = "all", event = "do-thing",
							payload = "{{value}}", description = "Do the thing", category = "system",
						},
					},
				},
			},
		}
	end },
	runAsync = function(command, callback, _timeout)
		commands[#commands + 1] = command
		if command:find("%-%-help") then
			callback({ exitCode = 0, timedOut = false, stdout = help, stderr = "" })
		elseif command:find("plugins list", 1, true) then
			callback({
				exitCode = 0, timedOut = false,
				stdout = "someone/new-plugin [community] 1.0.0 enabled\n", stderr = "",
			})
		elseif command:find("plugins commands", 1, true) then
			callback({ exitCode = 0, timedOut = false, stdout = "{}", stderr = "" })
		else
			callback({
				exitCode = 1,
				timedOut = false,
				stdout = "",
				stderr = 'error: unknown panel (available: launcher, someone/new-plugin:panel)',
			})
		end
		return true
	end,
}

assert(loadfile("catalog_service.luau"))()

assert(#commands == 4, "catalog discovery must query help, plugins, declared commands, and panels")
assert(commands[1]:find("WAYLAND_DISPLAY='wayland%-9' noctalia msg %-%-help") ~= nil,
	"catalog must target the discovered Noctalia IPC display")

local catalog = stateValues["keymap.runtime_command_catalog"]
assert(type(catalog) == "table" and catalog.status == "ready", "runtime catalog was not published")

local byTemplate = {}
for _, entry in ipairs(catalog.entries) do byTemplate[entry.template] = entry end

for _, command in ipairs({
	"noctalia msg media next",
	"noctalia msg media previous",
	"noctalia msg media toggle",
	"noctalia msg volume-up",
	"noctalia msg panel-open launcher",
	"noctalia msg panel-toggle launcher",
	"noctalia msg panel-close launcher",
	"noctalia msg panel-open someone/new-plugin:panel",
	"noctalia msg panel-toggle someone/new-plugin:panel",
}) do
	assert(byTemplate[command] ~= nil, "missing complete runtime command: " .. command)
	assert(command:find("{{", 1, true) == nil, "ready runtime command contains a placeholder")
end

assert(byTemplate["noctalia msg plugins enable {{arguments}}"] ~= nil,
	"commands with trailing arguments must not be presented as ready fragments")

assert(byTemplate["noctalia msg panel-open {{id}}"] ~= nil,
	"generic commands with required input must remain customizable")
assert(byTemplate["noctalia msg effects-profile-set {{output-input}} {{profile}}"] ~= nil,
	"multi-argument commands must expose every required argument")
assert(byTemplate["noctalia msg panel-toggle someone/new-plugin:panel"].category == "plugins",
	"community panel commands must be grouped as plugins")
assert(byTemplate["noctalia msg panel-toggle someone/new-plugin:panel"].origin == "community",
	"panel origin must come from the active plugin source")
assert(byTemplate["noctalia msg panel-toggle someone/new-plugin:panel"].module_name == "New Plugin",
	"panel commands must use the plugin display name")
assert(byTemplate["noctalia msg plugin someone/new-plugin:service all do-thing {{value}}"] ~= nil,
	"manifest-declared plugin commands must be included")

print("catalog service tests: ok")
