<#
.Synopsis
Runs the built WSL server install in the specified data directory.
#>

param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string] $Path,

	[switch] $WithDebugger
)

Push-Location $Path

# musl loader name for the architecture of the WSL distribution (ld-musl-x86_64.so.1, ld-musl-aarch64.so.1, ...)
$arch = (wsl -d FXServer-Alpine uname -m).Trim()
$muslLoader = "ld-musl-$arch.so.1"

wsl -d FXServer-Alpine cp -a /lib/$muslLoader /opt/cfx-server/

if (!$WithDebugger) {
	wsl -d FXServer-Alpine /opt/cfx-server/$muslLoader /opt/cfx-server/FXServer +set citizen_dir /opt/cfx-server/citizen/ +exec server.cfg @args
} else {
	# TODO: gdbinit
	wsl -d FXServer-Alpine apk add gdb
	wsl -d FXServer-Alpine gdb --args /opt/cfx-server/FXServer +set citizen_dir /opt/cfx-server/citizen/ +exec server.cfg @args
}
Pop-Location
