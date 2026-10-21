return {
	include = function()
		if not os.istarget('windows') then
			defines { "BOTAN_DLL=__attribute__((visibility(\"default\")))" }
		end

		if _OPTIONS['game'] == 'server' then
			includedirs { "vendor/botan_sv/include/", "vendor/botan_sv/include/external/" }
		else
			includedirs "vendor/botan/include/"
			includedirs "vendor/botan/include/external/"
		end
	end,

	run = function()
		language "C++"
		kind "SharedLib"
		
		if os.istarget('windows') then
			defines { "BOTAN_DLL=__declspec(dllexport)", "_DISABLE_EXTENDED_ALIGNED_STORAGE" }
			characterset 'MBCS'

			buildoptions '/bigobj'
			buildoptions { '/wd4251', '/wd4275', '/wd4067', '/wd4267', '/wd4996', '/MP' }
			
			if _OPTIONS['with-asan'] then
				buildoptions '-mrdrnd -mrdseed'
			end
		else
			defines { "BOTAN_DLL=__attribute__((visibility(\"default\")))" }

			if cfx_is_x86_target() then
				buildoptions { '-msse', '-msse2' }
			else
				-- the aarch64 amalgamation needs the ARMv8 crypto/CRC ISA enabled at compile time
				-- (arm_neon.h only declares those intrinsics when the ISA is on); Botan still gates
				-- the accelerated code paths behind runtime CPUID checks, so this stays portable
				buildoptions { '-march=armv8-a+crypto+crc' }
			end
		end

		defines { "BOTAN_IS_BEING_BUILT" }

		if os.istarget('windows') then
			links { 'ws2_32', 'crypt32' }

			if _OPTIONS['game'] == 'server' then
				files {
					"vendor/botan_sv/src/*.cpp",
					"vendor/botan_sv/src/*.h"
				}
			else
				files {
					"vendor/botan/src/*.cpp",
					"vendor/botan/src/*.h"
				}				
			end
		elseif os.istarget('linux') then
			-- per-architecture Botan 2.19.5 amalgamations, both generated with
			--   configure.py --disable-modules=win32_stats,proc_walk --amalgamation --cc=clang --os=linux --cc-min-version=11.0 [--cpu=aarch64]
			-- src/linux/ + include/build_linux.h are x86_64, src/linux-aarch64/ + include/build_linux_aarch64.h are arm64
			local amalgamationDir = cfx_is_x86_target() and 'linux' or 'linux-aarch64'
			local buildHeader = cfx_is_x86_target() and 'build_linux.h' or 'build_linux_aarch64.h'

			prebuildcommands {
				('cp -a %s %s'):format(
					path.getabsolute('vendor/botan_sv/include/' .. buildHeader),
					path.getabsolute('vendor/botan_sv/include/botan/build.h')
				)
			}

			files {
				"vendor/botan_sv/src/" .. amalgamationDir .. "/*.cpp",
				"vendor/botan_sv/src/" .. amalgamationDir .. "/*.h"
			}
		end
	end
}
