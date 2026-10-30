# Step 4 (PowerShell): build logos-blockchain-node.exe (release, x86_64-pc-windows-gnu).
# Adjust the paths below to your machine. Output: $env:CARGO_TARGET_DIR\release\logos-blockchain-node.exe
param([string]$Work = 'C:\lb\src', [string]$Lbc = 'C:\lb\lbc\logos-blockchain-circuits-v0.5.7-windows-x86_64', [string]$Msys = 'C:\msys64', [int]$Jobs = 2)
(Get-Process -Id $PID).PriorityClass = 'Idle'   # keep the PC usable while compiling
$env:Path = "$env:USERPROFILE\.cargo\bin;$Msys\mingw64\bin;$Msys\usr\bin;$env:Path"
$env:RAPIDSNARK_LIB_DIR = "$Work\rapidsnark\package\lib"
$env:LBC_ROOT_DIR = $Lbc
$env:LIBCLANG_PATH = "$Msys\mingw64\bin"
$env:RUSTFLAGS = "-L native=$($Msys -replace '\\','/')/lib -l static=mman"
if (-not $env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR = "$Work\target" }
Set-Location "$Work\logos-blockchain"
"start $(Get-Date)"
cargo build -p logos-blockchain-node --release -j $Jobs 2>&1 | % { "$_" }
"BUILD EXIT $LASTEXITCODE $(Get-Date)"
