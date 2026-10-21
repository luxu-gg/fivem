local majorVersion = '22'
local minorVersion = '22'
local patch = '0'
local baseVersion = ('%s.%s.%s'):format(majorVersion, minorVersion, patch)
local dllName = ('libnode%s.dll'):format(majorVersion)
local pdbName = ('libnode%s.pdb'):format(majorVersion)
local libName = ('libnode%s.lib'):format(majorVersion)
local soName = ('libnode%s.so'):format(majorVersion)
local linuxShortName = ('node%s'):format(majorVersion)

-- cfx only publishes prebuilt Linux binaries for x86_64. On other architectures (arm64) libnode22.so
-- and libuv.so are built with code/tools/ci/docker-builder/arm64/build_libnode_aarch64.sh and read
-- from CFX_LIBNODE_DIR (default: vendor/libnode/bin/linux-<arch>/), or downloaded from
-- CFX_LIBNODE_URL/<file> when that is set. Returns the binary directory and the download base URL
-- (nil when the files are expected to already be in place).
local function prebuiltSource(defaultDir, defaultURL)
	if os.istarget('windows') or cfx_is_x86_target() then
		return defaultDir, defaultURL
	end

	local dir = os.getenv('CFX_LIBNODE_DIR') or (path.getabsolute('../') .. '/vendor/libnode/bin/linux-' .. cfx_target_arch)
	return dir, os.getenv('CFX_LIBNODE_URL')
end

return {
	include = function()
		includedirs { '../vendor/libnode/include/' }
		includedirs { '../vendor/libnode/include/node/' }
		includedirs { '../vendor/libnode/include/node/uv/include/' }
		includedirs { '../vendor/libnode/include/node/v8/include/' }
		includedirs { '../vendor/libnode/include/node/openssl/' }

        libdirs { (prebuiltSource('../vendor/libnode/bin/')) }
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
			('../vendor/libnode/tag.txt'):format(baseVersion)
		}

        local baseURL = ('https://content.cfx.re/mirrors/vendor/libnode/legacy%s/bin'):format(majorVersion)
        local nodeBinDir = path.getabsolute('../') .. '/vendor/libnode/bin'

		if os.istarget('windows') then
			filter 'files:**/tag.txt'
                buildmessage 'Preparing libnode'

                buildoutputs {
                    ('%%{cfg.targetdir}/%s'):format(dllName),
                }

                buildcommands {
                    -- download files, redownload only if outdated
                    ('curl.exe "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(nodeBinDir, dllName, nodeBinDir, dllName, baseURL, dllName),
                    ('curl.exe "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(nodeBinDir, pdbName, nodeBinDir, pdbName, baseURL, pdbName),
                    ('curl.exe "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(nodeBinDir, libName, nodeBinDir, libName, baseURL, libName),
					'if %errorlevel% neq 0 (exit /b 1)',
					('{COPY} %s/%s %%{cfg.targetdir}'):format(nodeBinDir, dllName),
                    -- copy pdb manually to the server files
					'{MKDIR} %{cfg.targetdir}/dbg/',
					('{COPY} %s/%s %%{cfg.targetdir}/dbg/'):format(nodeBinDir, pdbName),
                }
		else
			local binDir, url = prebuiltSource(nodeBinDir, baseURL)
			local commands = {}

			if url then
				if not cfx_is_x86_target() then
					table.insert(commands, ('{MKDIR} %s'):format(binDir))
				end

				table.insert(commands, ('curl "-z%s/%s" -L "-o%s/%s" "%s/%s"'):format(binDir, soName, binDir, soName, url, soName))
			else
				table.insert(commands, ('test -f "%s/%s" || { echo "%s/%s not found: build it with code/tools/ci/docker-builder/arm64/build_libnode_aarch64.sh, or set CFX_LIBNODE_DIR / CFX_LIBNODE_URL" >&2; exit 1; }'):format(binDir, soName, binDir, soName))
			end

			table.insert(commands, ('{COPY} %s/%s %%{cfg.targetdir}'):format(binDir, soName))

			filter 'files:**/tag.txt'
                buildmessage 'Preparing libnode'

                buildoutputs {
                    ('%%{cfg.targetdir}/%s'):format(soName),
                }

                buildcommands(commands)
		end

		filter {}
	end
}
