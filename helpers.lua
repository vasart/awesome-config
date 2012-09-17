-- {{{ Helper functions
require('posix')

-- autorun
function resolve_symlink(file, level)
	if not level then
		level = -1
	end
	local file_stat = posix.stat(file)
	if level ~= 0 and file_stat and file_stat.type == 'link' then
		local readlink_output = awful.util.pread(string.format('readlink %s', file)):gsub('%s*$', '')
		return resolve_symlink(readlink_output, level - 1)
	end

	return file
end

function launch_command(command)
	local basename = command:gsub('^.*/', ''):gsub('%s+.*$', '')
	awful.util.spawn_with_shell(string.format('pgrep -u $USER -f "%s$" >/dev/null || (%s &)', basename, command))
end

local autorun_commands = {}

-- Awesome autorun directory
local autorun_dir = string.format('%s/autorun', awful.util.getdir('config'))
local autorun_stat = posix.stat(autorun_dir)
if autorun_stat and autorun_stat.type == 'directory' then
	local files = posix.dir(autorun_dir)
	if files then
		for _, file in pairs(files) do
			local full_file = resolve_symlink(string.format('%s/%s', autorun_dir, file), 1)
			local file_stat = posix.stat(full_file)
			if file_stat and file_stat.type == 'regular' then
				autorun_commands[full_file] = full_file
			end
		end
	end
end

-- XDG autorun
xdg_enable = false
if xdg_enable then
	local xdg_autorun_dirs = { string.format('%s/.config/autostart', os.getenv('HOME')), '/etc/xdg/autostart' }
	for _, xdg_autorun_dir in pairs(xdg_autorun_dirs) do
		local xdg_autorun_stat = posix.stat(xdg_autorun_dir)
		if xdg_autorun_stat and xdg_autorun_stat.type == 'directory' then
			local xdg_autorun_dirs = posix.dir(xdg_autorun_dir)
			for _, xdg_autorun_name in pairs(xdg_autorun_dirs) do
				local xdg_autorun_file = string.format('%s/%s', xdg_autorun_dir, xdg_autorun_name)
				local xdg_autorun_file_stat = posix.stat(resolve_symlink(xdg_autorun_file))
				if xdg_autorun_file_stat and xdg_autorun_file_stat.type == 'regular' and xdg_autorun_name:find('\.desktop$') then
					local section
					local commands = {}
					for line in io.lines(xdg_autorun_file) do
						local new_section
						line:gsub('^%[([^%]]+)%]$', function(a) new_section = a:lower() end)
						if (not section and new_section) or (new_section and section and section ~= new_section) then
							section = new_section
							commands[section] = { condition = true }
						end
						local key, value
						line:gsub('^([^%s=]+)%s*=%s*(.+)%s*$', function(a, b) key = a:lower() value = b end)
						if section and key and key == 'exec' then
							commands[section]['command'] = value:gsub('%%.', ''):gsub('%s+$', '')
						elseif section and key and key == 'autostartcondition' then
							local condition = false
							local condition_method, condition_args
							value:gsub('^([^%s]+)%s+(.+)$', function(a, b) condition_method = a:lower() condition_args = b end)
							if condition_method and condition_args and condition_method == 'gsettings' then
								local gsettings_output = awful.util.pread(string.format('gsettings get %s', condition_args)):gsub('%s*$', '')
								condition = gsettings_output and gsettings_output == 'true'
							elseif condition_method and condition_args and condition_method == 'gnome' then
								local gconftool_output = awful.util.pread(string.format('gconftool --get %s', condition_args)):gsub('%s*$', '')
								condtion = gconftool_output and gconftool_output == 'true'
							elseif condition_method and condition_args and condition_method == 'gnome3' then -- ignore
							else
								print(string.format('[awesome] Unknown AutostartCondition method: %s', condition_method))
							end
							commands[section]['condition'] = condition
						end
					end
					local try_sections = { 'desktop action tray', 'desktop entry' }
					for _, try_section in pairs(try_sections) do
						if commands[try_section] and commands[try_section]['command'] and commands[try_section]['condition'] then
							autorun_commands[commands[try_section]['command']] = 1
							break
						end
					end
				end
			end
		end
	end
end

for command in pairs(autorun_commands) do
	launch_command(command)
end

function run_once(prg,arg_string,pname,screen)
	if not prg then
		do return nil end
	end

	if not pname then
		pname = prg
	end

	if not arg_string then 
		awful.util.spawn_with_shell("pgrep -f -u $USER -x '" .. pname .. "' || (" .. prg .. ")",screen)
	else
		awful.util.spawn_with_shell("pgrep -f -u $USER -x '" .. pname .. "' || (" .. prg .. " " .. arg_string .. ")",screen)
	end
end

function dbg(vars)
	local text = ""
	if type(vars) == "table" then
		for i=1, #vars do text = text .. vars[i] .. " | " end
	elseif type(vars) == "string" then
		text = vars
	end
	naughty.notify({ text = text, timeout = 0 })
end

function clean(string)
	s = string.gsub(string, '^%s+', '')
	s = string.gsub(s, '%s+$', '')
	s = string.gsub(s, '[\n\r]+', ' ')
	return s
end

function file_exists(file)
	local cmd = "/bin/bash -c 'if [ -e " .. file .. " ]; then echo true; fi;'"
	local fh = io.popen(cmd)

	s = clean(fh:read('*a'))

	if s == 'true' then return true else return nil end
end

--% Find the path of an application, return nil of doesn't exist
----@ app (string) Text of the first parameter
----@ return string of app path, or nil (remember, only nil and false is false in lua)
function whereis_app(app)
	local fh = io.popen('which ' .. app)
	s = clean(fh:read('*a'))

	if s == "" then return nil else return s end
	return s
end

function require_safe(lib)
	if file_exists(awful.util.getdir("config") .. '/' .. lib ..'.lua') or
		file_exists(awful.util.getdir("config") .. '/' .. lib) then
			require(lib)
	end
end

-- }}}
