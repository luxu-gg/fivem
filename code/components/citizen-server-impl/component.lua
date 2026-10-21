-- MSVC for GLM
defines { "_ENABLE_EXTENDED_ALIGNED_STORAGE" }

-- built without the Mono runtime (premake --without-mono): citizen:scripting:mono is skipped as an
-- optional dependency, so the MonoEnsureThreadAttached() calls have to go as well
if cfx_without_mono then
	defines { "WITHOUT_MONO" }
end

if os.istarget('windows') then
	filter { "configurations:Release" }
		flags { "LinkTimeOptimization" }
	
	filter {}
		buildoptions '/fp:fast'
end

return function()
	filter {}
	add_dependencies { 'vendor:folly' }

	removefiles {
		'components/citizen-server-impl/src/state/**'
	}
end
