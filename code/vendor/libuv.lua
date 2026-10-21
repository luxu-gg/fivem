local majorVersion = '22'
local minorVersion = '22'
local patch = '0'
local baseVersion = ('%s.%s.%s'):format(majorVersion, minorVersion, patch)
local dllName = 'libuv.dll'
local pdbName = 'libuv.pdb'
local libName = 'libuv.lib'
local soName = 'libuv.so'
local linuxShortName = 'uv'

return {
	include = function()
		includedirs { '../vendor/libnode/include/node/uv/include/' }

        libdirs { '../vendor/libuv/bin/' }
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
		elseif cfx_is_x86_target() then
			filter 'files:**/tag.txt'
                buildmessage 'Preparing libuv'

                buildoutputs {
                    ('%%{cfg.targetdir}/%s'):format(soName),
                }

                buildcommands {
                    ('curl "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(uvBinDir, soName, uvBinDir, soName, baseURL, soName),
					('{COPY} %s/%s %%{cfg.targetdir}'):format(uvBinDir, soName),
                }
		else
			-- no prebuilt libuv is published for this architecture: use the distro libuv (libuv-dev;
			-- the 1.x ABI is stable) and ship a copy of it next to the server binaries
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
