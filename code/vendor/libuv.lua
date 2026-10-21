local majorVersion = '22'
local minorVersion = '22'
local patch = '0'
local baseVersion = ('%s.%s.%s'):format(majorVersion, minorVersion, patch)
local dllName = 'libuv.dll'
local pdbName = 'libuv.pdb'
local libName = 'libuv.lib'
local soName = 'libuv.so'
local linuxShortName = 'uv'

-- cfx only publishes prebuilt Linux binaries for x86_64. On other architectures (arm64) libuv.so is
-- built together with libnode22.so by code/tools/ci/docker-builder/arm64/build_libnode_aarch64.sh
-- and read from CFX_LIBNODE_DIR (default: vendor/libnode/bin/linux-<arch>/), or downloaded from
-- CFX_LIBNODE_URL/libuv.so when that is set; without either, the distro libuv is used (see below).
-- Returns the binary directory and the download base URL (nil when no download should happen).
local function prebuiltSource(defaultDir, defaultURL)
	if os.istarget('windows') or cfx_is_x86_target() then
		return defaultDir, defaultURL
	end

	local dir = os.getenv('CFX_LIBNODE_DIR') or (path.getabsolute('../') .. '/vendor/libnode/bin/linux-' .. cfx_target_arch)
	return dir, os.getenv('CFX_LIBNODE_URL')
end

-- true when a cfx-built libuv.so is available (or downloadable) for a non-x86 Linux target
local function havePrebuilt()
	if os.istarget('windows') or cfx_is_x86_target() then
		return false
	end

	local dir, url = prebuiltSource()
	return url ~= nil or os.isfile(dir .. '/' .. soName)
end

return {
	include = function()
		includedirs { '../vendor/libnode/include/node/uv/include/' }

        if os.istarget('windows') or cfx_is_x86_target() or not havePrebuilt() then
            libdirs { '../vendor/libuv/bin/' }
        else
            libdirs { (prebuiltSource()) }
        end
        if os.istarget('windows') then
            links { libName }
        else
			links { linuxShortName }
        end
	end,

	run = function()
		kind 'Utility'

        files {
            -- dummy file to generate a project, so build commands are executed
			'../vendor/libuv/tag.txt'
		}

        local baseURL = ('https://content.cfx.re/mirrors/vendor/libnode/legacy%s/bin'):format(majorVersion)
        local uvBinDir = path.getabsolute('../') .. '/vendor/libuv/bin'

		if os.istarget('windows') then
			filter 'files:**/tag.txt'
                buildmessage 'Preparing libuv'

                buildoutputs {
                    ('%%{cfg.targetdir}/%s'):format(dllName),
                }

                buildcommands {
                    -- download files, redownload only if outdated
                    ('echo "%s/%s"'):format(baseURL, dllName),
                    ('curl.exe "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(uvBinDir, dllName, uvBinDir, dllName, baseURL, dllName),
                    ('curl.exe "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(uvBinDir, pdbName, uvBinDir, pdbName, baseURL, pdbName),
                    ('curl.exe "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(uvBinDir, libName, uvBinDir, libName, baseURL, libName),
					'if %errorlevel% neq 0 (exit /b 1)',
					('{COPY} %s/%s %%{cfg.targetdir}'):format(uvBinDir, dllName),
                    -- copy pdb manually to the server files
					'{MKDIR} %{cfg.targetdir}/dbg/',
					('{COPY} %s/%s %%{cfg.targetdir}/dbg/'):format(uvBinDir, pdbName),
                }
		elseif cfx_is_x86_target() or havePrebuilt() then
			local binDir, url = prebuiltSource(uvBinDir, baseURL)
			local commands = {}

			if url then
				if not cfx_is_x86_target() then
					table.insert(commands, ('{MKDIR} %s'):format(binDir))
				end

				table.insert(commands, ('curl "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(binDir, soName, binDir, soName, url, soName))
			end

			table.insert(commands, ('{COPY} %s/%s %%{cfg.targetdir}'):format(binDir, soName))

			filter 'files:**/tag.txt'
                buildmessage 'Preparing libuv'

                buildoutputs {
                    ('%%{cfg.targetdir}/%s'):format(soName),
                }

                buildcommands(commands)
		else
			-- no cfx-built libuv for this architecture (no CFX_LIBNODE_DIR/CFX_LIBNODE_URL): use the distro
			-- libuv (libuv-dev; the 1.x ABI is stable) and ship a copy of it next to the server binaries
			filter 'files:**/tag.txt'
                buildmessage 'Preparing libuv from the system'

                buildoutputs {
                    ('%%{cfg.targetdir}/%s'):format(soName),
                }

                buildcommands {
                    ('{MKDIR} %s'):format(uvBinDir),
                    ('cp -L /usr/lib/%s %s/%s'):format(soName, uvBinDir, soName),
					('{COPY} %s/%s %%{cfg.targetdir}'):format(uvBinDir, soName),
                }
		end

	end
}
