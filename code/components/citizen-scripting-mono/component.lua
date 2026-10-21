local cwd = os.getcwd()

return function()
	filter {}
	
	add_dependencies { 'vendor:eastl' }

	if os.istarget('windows') then
		filter 'architecture:x64'
			links { "mono-2.0-sgen" }
	
		filter 'architecture:x86'
			links { "mono-2.0-sgen-x86" }
	
		filter {}
	
		if _OPTIONS['game'] == 'server' then
			includedirs { cwd .. "/deps/server/include/" }
			libdirs { cwd .. "/deps/server/lib/" }
		else
			includedirs { cwd .. "/deps/include/" }
			libdirs { cwd .. "/deps/lib/" }
		end
	else
		-- the static mono runtime (mono 5.16.1.0-r9991) comes from the cfx Alpine apk repository on
		-- x86_64 and from the tarball built by tools/ci/docker-builder/arm64/build_mono_aarch64.sh on
		-- aarch64 (see tools/ci/docker-builder/proot_prepare.sh); both install to the same paths
		includedirs { '/usr/include/mono-2.0/ '}
	
		linkoptions '/usr/lib/libmonosgen-2.0.a -Wl,--defsym=mono_handle_native_crash=mono_handle_native_crash_nop'
	end
end
