# Logos testnet one-click panel (native Windows). No keys/IPs hardcoded.
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$Ini  = Join-Path $Root 'logos-miner.ini'
$Exe  = Join-Path $Root 'bin\logos-blockchain-node.exe'
$Data = Join-Path $Root 'data'
$Ucfg = Join-Path $Data 'user_config.yaml'
$Log  = Join-Path $Data 'node.log'
$env:Path = (Join-Path $Root 'bin') + ';' + $env:Path
$BuildNo = 8; $BuildName = 'v8'          # bumped on every release; the updater compares this number with the manifest
$PauseFile = Join-Path $Data 'mining.paused' # exists = you pressed "Stop mining" (menu 5); the background helper then leaves mining off

# CPU facts. Mining speed is limited by CPU threads, NOT by RAM (a thread needs very little memory).
function Cpu-Cores { if ($script:cores) { return $script:cores }; $n = 0; try { Get-CimInstance Win32_Processor -ErrorAction Stop | % { $n += [int]$_.NumberOfCores } } catch {}; if ($n -lt 1) { $n = [Environment]::ProcessorCount }; $script:cores = $n; $n }
# default = half of the CPU threads (at least 1, at most 8): leaves the PC usable and the node API responsive
function Auto-Threads { $l = [Environment]::ProcessorCount; [int][math]::Max(1, [math]::Min(8, [math]::Floor($l / 2))) }
function Load-Cfg {
  $c=@{}; Get-Content $Ini | ? { $_ -match '^\s*([a-z_]+)\s*=\s*(.*)$' } | % { $c[$Matches[1]]=$Matches[2].Trim() }
  # validate everything that reaches a command line / config (ini is untrusted input)
  if ($c.mode -notin 'full','mine') { $c.mode='mine' }
  $c.threads_auto = $false
  if ($c.threads -eq 'auto' -or -not $c.threads) { $c.threads_auto = $true; $c.threads = [string](Auto-Threads) }
  elseif ($c.threads -notmatch '^\d{1,3}$' -or [int]$c.threads -lt 1) { $c.threads='1' }
  elseif ([int]$c.threads -gt [Environment]::ProcessorCount) { $c.threads = [string][Environment]::ProcessorCount }
  if ($c.net_port -notmatch '^\d{1,5}$' -or [int]$c.net_port -gt 65535) { $c.net_port='3000' }
  if ($c.api -notmatch '^127\.0\.0\.1:\d{1,5}$' -and $c.api -notmatch '^localhost:\d{1,5}$') { Write-Host "api must be 127.0.0.1:<port> (REST API has no auth) - using 127.0.0.1:8080" -ForegroundColor Yellow; $c.api='127.0.0.1:8080' }
  if ($c.external_address -and $c.external_address -notmatch '^[A-Za-z0-9.-]{1,253}$') { Write-Host 'invalid external_address ignored' -ForegroundColor Yellow; $c.external_address='' }
  if ($c.update_url -and $c.update_url -notmatch '^(https://[^\s"''<>|]+|file:///[^\s"''<>|]+)$') { Write-Host 'invalid update_url ignored (only https:// or file:/// allowed)' -ForegroundColor Yellow; $c.update_url='' }
  if ($c.claim_public_key -and $c.claim_public_key -notmatch '^[0-9a-fA-F]{64}$') { Write-Host 'invalid claim_public_key ignored' -ForegroundColor Yellow; $c.claim_public_key='' }
  if ($c.peers) { $c.peers = (@($c.peers -split ',' | % { $_.Trim() } | ? { $_ -match '^/(ip4|ip6|dns4|dns6|dns)/[A-Za-z0-9.:-]+/udp/\d{1,5}/quic-v1/p2p/[1-9A-HJ-NP-Za-km-z]{40,60}$' })) -join ',' }
  $c
}
function Save-Cfg($c) {
  $lines = Get-Content $Ini
  foreach ($k in @($c.Keys)) { if ($k -eq 'threads_auto') { continue }; $val = $c[$k]; if ($k -eq 'threads' -and $c.threads_auto) { $val = 'auto' }; $lines = $lines | % { if ($_ -match "^\s*$k\s*=") { "$k=$val" } else { $_ } } }
  Set-Content $Ini $lines
}
function Api($path, $method='GET', $to=60) {
  $c = Load-Cfg
  try { $r = Invoke-WebRequest -UseBasicParsing -Method $method -Uri "http://$($c.api)$path" -TimeoutSec $to -ContentType 'application/json'
        if ($r.Content) { try { $r.Content | ConvertFrom-Json } catch { $r.Content } } else { 'ok' } } catch { $null }
}
# --- Mining state. Ground truth = node REST /pow/status (is_mining). While every CPU thread mines the node answers /pow/* slowly (HTTP 408),
# so the node.log lines "PoW mining started" / "PoW mining stopped" are the fallback.  (v6: the panel no longer waits for a log line to ask for mining.)
function Pow-State {   # 'ready' = the node's PoW service is up | 'stalled' = a service gave up waiting at startup | 'waiting' | 'nolog'
  if (-not (Test-Path $Log)) { return 'nolog' }
  $m = @(Select-String -Path $Log -SimpleMatch -Pattern 'starting the PoW service','Error while waiting for Service' -ErrorAction SilentlyContinue | % { $_.Line })
  if ($m -match 'starting the PoW service') { return 'ready' }
  if ($m -match 'Error while waiting for Service') { return 'stalled' }
  'waiting'
}
function Log-Mining {  # 'on' | 'off' | '' (never logged)
  if (-not (Test-Path $Log)) { return '' }
  $l = Select-String -Path $Log -SimpleMatch -Pattern 'PoW mining started','PoW mining stopped' -ErrorAction SilentlyContinue | select -Last 1
  if (-not $l) { return '' }
  if ($l.Line -match 'mining started') { 'on' } else { 'off' }
}
function Mining-State($to=10) {   # @{ state='on'|'off'|'unknown'; src='api'|'log'|''; st=<status object or $null> }
  $st = Api '/pow/status' 'GET' $to
  if ($st -and ($st.PSObject.Properties.Name -contains 'is_mining')) { return @{ state = $(if ($st.is_mining) {'on'} else {'off'}); src='api'; st=$st } }
  $lm = Log-Mining
  if ($lm) { return @{ state=$lm; src='log'; st=$null } }
  @{ state='unknown'; src=''; st=$null }
}
function Chain-Online { $i = Api '/cryptarchia/info' 'GET' 15; [bool]($i -and $i.cryptarchia_info.state -eq 'Online') }
$HealLog = Join-Path $Data 'autoheal.log'
function Can-Heal { $n = 0; if (Test-Path $HealLog) { $n = @(Get-Content $HealLog | ? { try { ([datetime]$_) -gt (Get-Date).AddHours(-6) } catch { $false } }).Count }; $n -lt 3 }
function Note-Heal { Add-Content $HealLog (Get-Date -Format s) }
function Local-Time($line) { try { if (($line -replace '\x1b\[[0-9;]*m','') -match '^(\S+Z)') { return [DateTimeOffset]::Parse($Matches[1]).ToLocalTime().ToString('HH:mm') } } catch {}; '?' }
function Pow-Started-At { $l = Select-String -Path $Log -SimpleMatch -Pattern 'PoW mining started' -ErrorAction SilentlyContinue | select -Last 1; if ($l) { Local-Time $l.Line } else { '' } }
function Start-Detached($argline) { Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine="powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argline"} | Out-Null }
function Arm-Write($t) {
  $f = Join-Path $Data 'arm.log'
  Add-Content $f "$(Get-Date -Format s) $t"
  try { if ((Get-Item $f).Length -gt 2MB) { $l = Get-Content $f -Tail 300; Set-Content $f $l } } catch {}
}
# Background helper (hidden, one per node). Every cycle: if the chain is Online and mining is not ON (and you did not pause it), send
# PUT /pow/mining/start.  The request is idempotent and the node queues it even when it answers 408, so it is safe to repeat.
# It NEVER restarts a node that is Online and healthy; the only automatic restart is for the slow-PC startup failure ("Error while waiting for Service").
function Arm-Loop {
  while (Node-Proc) {
    $paused = Test-Path $PauseFile
    $online = Chain-Online
    $ps = Pow-State; $ms = $null; $act = '-'
    if ($online -and -not $paused) {
      $ms = Mining-State 20
      if ($ms.state -ne 'on') {
        if (Test-Path $PauseFile) { $act = 'skip:paused-meanwhile' }   # menu 5 was pressed while this cycle was running
        else { $r = Api '/pow/mining/start' 'PUT' 25; $act = $(if ($r) { 'start:accepted' } else { 'start:sent(no answer yet)' }) }
      }
    } elseif ($online) { $ms = Mining-State 10; $act = 'paused-by-user' }
    $stj = ''; if ($ms -and $ms.st) { $stj = ' status=' + ($ms.st | ConvertTo-Json -Compress -Depth 4) }
    Arm-Write "online=$online powservice=$ps mining=$($ms.state)/$($ms.src) action=$act$stj"
    if ($ps -eq 'stalled' -and -not ($ms -and $ms.state -eq 'on') -and (Can-Heal)) { Note-Heal; Arm-Write 'AUTO-HEAL: a node service gave up waiting at startup (slow PC) and mining cannot start - restarting node'; Start-Detached '--restart'; return }
    $nap = $(if ($ms -and $ms.state -eq 'on') { 120 } elseif ($online) { 30 } else { 45 })
    Start-Sleep $nap
  }
}
function Node-Up-Min { $np = Node-Proc | select -First 1; if (-not $np) { return 0 }; try { $st = $np.StartTime } catch { $st = $null }; if (-not $st) { try { $st = (Get-CimInstance Win32_Process -Filter "ProcessId=$($np.Id)" -ErrorAction Stop).CreationDate } catch {} }; if (-not $st) { return 0 }; [int](((Get-Date) - $st).TotalMinutes) }
# only THIS folder's node (several copies / test folders on one PC must never touch each other)
function Node-Proc {
  $want = [IO.Path]::GetFullPath($Exe).ToLower()
  $ids = @(Get-CimInstance Win32_Process -Filter "Name='logos-blockchain-node.exe'" -ErrorAction SilentlyContinue | ? { $_.ExecutablePath -and ([IO.Path]::GetFullPath($_.ExecutablePath).ToLower() -eq $want) } | % { [int]$_.ProcessId })
  if ($ids.Count) { Get-Process -Id $ids -ErrorAction SilentlyContinue }
}

function Init-Node {
  if (Test-Path $Ucfg) { Write-Host "Node already initialised ($Ucfg)."; return }
  New-Item -ItemType Directory -Force $Data | Out-Null
  # lock data dir (keystore) to current user + SYSTEM + Administrators; C:\ root default ACL lets all Users read and Authenticated Users modify
  icacls $Data /inheritance:r /grant:r "*$([Security.Principal.WindowsIdentity]::GetCurrent().User.Value):(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" /Q | Out-Null
  Push-Location $Data
  & $Exe init-config -o user_config.yaml
  Pop-Location
  if (Test-Path $Ucfg) { Write-Host "Created fresh node identity + keystore in $Data (back up keystore.yaml, never share it)." -ForegroundColor Green }
  else { Write-Host "init-config failed" -ForegroundColor Red }
}

# --- node config editing (v8). Node 0.3.4 keeps a SPARSE user_config.yaml (only values that differ from the defaults), and on its
# first start it converts a 0.3.2 config to that form (the original is kept as user_config.yaml.0.3.2.bak). So a setting may simply
# be missing from the file: these helpers set a value by its path and add the missing parent keys. They understand only the plain
# block YAML the node itself writes (2-space indent, list items at the parent key's indent).
function Yaml-Lines([string]$path) {
  $t = ''; if (Test-Path $path) { $t = [IO.File]::ReadAllText($path) }
  $r = New-Object 'Collections.Generic.List[string]'
  foreach ($x in ($t -split "\r?\n")) { $r.Add($x) }
  while ($r.Count -and $r[$r.Count-1].Trim() -eq '') { $r.RemoveAt($r.Count-1) }
  if ($r.Count -eq 1 -and $r[0].Trim() -in '{}','null','~','---') { $r.Clear() }   # an empty sparse config
  ,$r
}
function Yaml-Save([string]$path, $L) { [IO.File]::WriteAllText($path, (($L -join "`n") + "`n")) }
function Yaml-BlockEnd($L, [int]$i, [int]$ind) {   # first line after the block that starts at line $i (a key at indent $ind)
  for ($j = $i + 1; $j -lt $L.Count; $j++) {
    $ln = $L[$j]; if ($ln -match '^\s*(#.*)?$') { continue }
    $li = $ln.Length - $ln.TrimStart(' ').Length
    if ($li -lt $ind) { return $j }
    if ($li -eq $ind -and $ln.Substring($ind) -notmatch '^-( |$)') { return $j }
  }
  $L.Count
}
function Yaml-Find($L, [string[]]$path) {
  $start = 0; $end = $L.Count; $ind = 0; $parent = -1
  for ($d = 0; $d -lt $path.Count; $d++) {
    $pat = '^' + (' ' * $ind) + [regex]::Escape($path[$d]) + ':(\s|$)'; $hit = -1
    for ($j = $start; $j -lt $end; $j++) { if ($L[$j] -match $pat) { $hit = $j; break } }
    if ($hit -lt 0) { return @{ i=-1; depth=$d; end=$end; ind=$ind; parent=$parent } }
    $be = Yaml-BlockEnd $L $hit $ind
    if ($d -eq $path.Count - 1) { return @{ i=$hit; end=$be; ind=$ind; depth=$d+1; parent=$parent } }
    $parent = $hit; $start = $hit + 1; $end = $be; $ind += 2
  }
}
function Yaml-Get($L, [string[]]$path) {   # -> $null (missing) or @{ inline = text after 'key:'; block = lines below it }
  $f = Yaml-Find $L $path; if ($f.i -lt 0) { return $null }
  $m = [regex]::Match($L[$f.i], ':\s*(.*)$')
  $pre = ' ' * $f.ind   # block lines are returned relative to the key's indent, the form Yaml-Set takes
  @{ inline = $m.Groups[1].Value.Trim(); block = @(if ($f.end -gt $f.i + 1) { $L.GetRange($f.i + 1, $f.end - $f.i - 1) | % { if ($_.StartsWith($pre)) { $_.Substring($pre.Length) } else { $_.TrimStart() } } }) }
}
# $inline = value on the key's line; $block = lines placed under the key (list items, written at the key's indent like the node does)
function Yaml-Set($L, [string[]]$path, [string]$inline, [string[]]$block) {
  $f = Yaml-Find $L $path
  if ($f.i -ge 0) { $at = $f.i; $ind = $f.ind; $L.RemoveRange($f.i, $f.end - $f.i) }
  else {
    if ($f.parent -ge 0) {   # 'logger: {}' / 'logger: null' -> 'logger:'; any other inline value = not plain block YAML, leave the file alone
      $m = [regex]::Match($L[$f.parent], '^(\s*[^:#]+:)\s*(.*?)\s*$')
      if ($m.Groups[2].Value -in '{}','null','~') { $L[$f.parent] = $m.Groups[1].Value } elseif ($m.Groups[2].Value) { return $false }
    }
    $at = $f.end; $ind = $f.ind
    for ($d = $f.depth; $d -lt $path.Count - 1; $d++) { $L.Insert($at, (' ' * $ind) + $path[$d] + ':'); $at++; $ind += 2 }
  }
  $pre = ' ' * $ind
  if ($block) { $L.Insert($at, "$pre$($path[-1]):"); $at++; foreach ($b in $block) { $L.Insert($at, "$pre$b"); $at++ } }
  else { $L.Insert($at, "$pre$($path[-1]): $inline") }
  $true
}
function Yaml-IsEmptyList($v) { (-not $v) -or ($v.inline -eq '[]') -or (($v.inline -eq '' -or $v.inline -eq 'null') -and -not @($v.block | ? { $_.Trim() }).Count) }
function Cfg-Is032 { (Test-Path $Ucfg) -and [bool](Select-String -Path $Ucfg -Pattern '^\s+(secs|nanos):\s' -Quiet) }   # 0.3.2 wrote durations as secs/nanos
# auto-claim targets the node uses when the config does not list them (they come from the keystore): read them from the node's own
# --show-config output (secrets are redacted there; only the public keys and thresholds are used)
function Effective-Targets {
  if (-not (Test-Path $Exe)) { return @() }
  Push-Location $Data
  try { $out = & $Exe user_config.yaml --show-config 2>$null } catch { $out = @() } finally { Pop-Location }
  $L = New-Object 'Collections.Generic.List[string]'; foreach ($x in @($out)) { $L.Add([string]$x) }
  $v = Yaml-Get $L @('pow','auto_claim','targets'); if (-not $v) { return @() }
  $t = @(); $cur = $null
  foreach ($b in $v.block) {
    if ($b -match '^\s*-?\s*public_key:\s*([0-9a-fA-F]{64})\s*$') { $cur = @{ pk = $Matches[1].ToLower(); th = '2000000000' }; $t += $cur }
    elseif ($cur -and $b -match '^\s*threshold:\s*(\d+)\s*$') { $cur.th = $Matches[1] }
  }
  $t
}
function Patch-Config($c) {
  $L = Yaml-Lines $Ucfg
  $ok = $true
  $ok = (Yaml-Set $L @('pow','mining','max_threads') $c.threads) -and $ok
  $ok = (Yaml-Set $L @('api','backend','listen_address') $c.api) -and $ok
  # The rolling file logger wants a '<prefix>.latest' symlink, which fails (Windows error 1314) for normal accounts without
  # Developer Mode; node 0.3.4 even turns that logger on by default. Logs already go to node.log via stdout, so switch it off.
  $ok = (Yaml-Set $L @('tracing','logger','file') 'null') -and $ok
  # empty cors_origins = Access-Control-Allow-Origin: * (any website could drive the API) -> pin to loopback only
  if (Yaml-IsEmptyList (Yaml-Get $L @('api','backend','cors_origins'))) { $ok = (Yaml-Set $L @('api','backend','cors_origins') '' @('- http://127.0.0.1')) -and $ok }
  $ok = (Yaml-Set $L @('network','backend','swarm','host') '0.0.0.0') -and $ok
  $ok = (Yaml-Set $L @('network','backend','swarm','port') $c.net_port) -and $ok
  if ($c.peers) {
    $pl = @($c.peers -split ',' | % { $_.Trim() } | ? { $_ })
    if (Yaml-IsEmptyList (Yaml-Get $L @('network','backend','initial_peers'))) { $ok = (Yaml-Set $L @('network','backend','initial_peers') '' @($pl | % { "- $_" })) -and $ok }
    if (Yaml-IsEmptyList (Yaml-Get $L @('cryptarchia','network','bootstrap','ibd','peers'))) { $ok = (Yaml-Set $L @('cryptarchia','network','bootstrap','ibd','peers') '' @($pl | % { '- ' + ($_ -replace '^.*/p2p/','') })) -and $ok }
  }
  # Auto-claim stops paying AND stops mining once the claim key balance reaches its threshold (node default 2000000000).
  # Raise only the exact default to u64 max on every auto-claim target (custom values are left alone; keys are never changed here).
  $u64 = '18446744073709551615'
  $tg = Yaml-Get $L @('pow','auto_claim','targets')
  if ($tg -and @($tg.block | ? { $_ -match 'public_key:' }).Count) {
    $nb = @($tg.block | % { $_ -replace '^(\s*(?:-\s+)?threshold:) 2000000000[ \t]*$', "`$1 $u64" })
    $ok = (Yaml-Set $L @('pow','auto_claim','targets') '' $nb) -and $ok
  } elseif (-not $tg) {
    Yaml-Save $Ucfg $L   # --show-config reads the file
    $et = @(Effective-Targets)
    if ($et.Count) {
      $nb = @(); foreach ($t in $et) { $th = $(if ($t.th -eq '2000000000') { $u64 } else { $t.th }); $nb += "- public_key: $($t.pk)"; $nb += "  threshold: $th" }
      $ok = (Yaml-Set $L @('pow','auto_claim','targets') '' $nb) -and $ok
    }
  }
  Yaml-Save $Ucfg $L
  if (-not $ok) { Write-Host 'Note: data\user_config.yaml has a layout this panel does not edit; some settings from logos-miner.ini were not applied.' -ForegroundColor Yellow }
}

function Strip-Ansi($t) { $t -replace "\x1b\[[0-9;]*m", '' }
function Show-StartFailure($np, $c) {
  $errTxt = ''
  foreach ($f in @("$Log.err", $Log)) { if (Test-Path $f) { $errTxt += (Get-Content $f -Tail 40 -ErrorAction SilentlyContinue | Out-String) } }
  $errTxt = Strip-Ansi $errTxt
  if ($np -and $np.HasExited) { Write-Host "The node stopped by itself right after starting (exit code $($np.ExitCode))." -ForegroundColor Red }
  else { Write-Host 'The node is still running but its API did not answer within 5 minutes.' -ForegroundColor Yellow }
  $last = @(Get-Content "$Log.err" -Tail 12 -ErrorAction SilentlyContinue | % { Strip-Ansi $_ } | ? { $_.Trim() })
  if (-not $last) { $last = @(Get-Content $Log -Tail 12 -ErrorAction SilentlyContinue | % { Strip-Ansi $_ } | ? { $_.Trim() }) }
  if ($last) { Write-Host '--- last lines of the node log ---' -ForegroundColor DarkGray; $last | % { Write-Host "  $_" -ForegroundColor Gray }; Write-Host '----------------------------------' -ForegroundColor DarkGray }
  $elev = $false
  if ($errTxt -match '1314|symlink') {
    Say 'Plain English: Windows did not allow the node to create a shortcut (symlink) for its log file. This needs special rights that normal accounts do not have. This package already turns that log file off, so if you still see this your config was not updated.' Yellow
    Say 'Fix: restart this panel and choose Start again, or run it once as Administrator (or turn on Developer Mode in Windows Settings > For developers).' Yellow; $elev = $true }
  elseif ($errTxt -match '10048|in use|Address already|AddrInUse|only one usage') { Say 'Plain English: another program (or another copy of the node) is already using the port. Close the other node, or change api/net_port in logos-miner.ini, then start again.' Yellow }
  elseif ($errTxt -match 'Access is denied|os error 5\b|code: 5,') { Say 'Plain English: Windows denied access to a file or folder. Move the LogosMiner folder somewhere you own (for example your Desktop or Documents) or run once as Administrator.' Yellow; $elev = $true }
  elseif ($errTxt -match 'unknown field|missing field|invalid type|did not find expected|while parsing') { Say 'Plain English: the node could not read data\user_config.yaml. If you went back to an older LogosMiner build, its node cannot read the file that node 0.3.4 converted: use Update menu > roll back, or rename data\user_config.yaml.0.3.2.bak to user_config.yaml.' Yellow }
  elseif ($errTxt -match 'keystore|decrypt|password') { Say 'Plain English: the node could not read its keystore (data\keystore.yaml). Do not delete it - it holds your keys. Restore it from your backup if it is damaged.' Yellow }
  elseif ($errTxt -match '0xc000|STATUS_DLL|not a valid Win32|libstdc|libwinpthread|libgcc') { Say 'Plain English: Windows could not load the node program or one of its DLLs. Re-extract the whole zip (keep the bin folder together) and check that antivirus did not quarantine a file.' Yellow }
  else { Say 'Unknown cause. The lines above are the node own error message; send them to whoever supports you.' Yellow }
  if ($elev) {
    $a = Read-Host 'Try again as Administrator now? (y/N)'
    if ($a -match '^[yY]') { try { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" --start" -Wait } catch { Say 'Elevation was cancelled.' Yellow } }
  }
}

# Port check before a start: the node fails late and cryptically when another program (often another copy of the node) holds its ports.
function Port-Owner($procId) { try { $pr = Get-Process -Id $procId -ErrorAction Stop; $n = $pr.ProcessName; try { if ($pr.Path) { $n += " ($($pr.Path))" } } catch {}; $n } catch { "process id $procId" } }
function Port-Conflicts($c) {   # -> list of plain-English problems (empty = all ports free). Call only while THIS folder's node is stopped.
  $apiPort = [int](($c.api -split ':')[-1]); $udp = @([int]$c.net_port)
  if (Test-Path $Ucfg) { $m = [regex]::Match((Get-Content $Ucfg -Raw), '(?m)^\s+listening_address:\s*/ip[46]/[^/]+/udp/(\d{1,5})/'); if ($m.Success -and [int]$m.Groups[1].Value -notin $udp) { $udp += [int]$m.Groups[1].Value } }
  $haveCmd = [bool](Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) -and [bool](Get-Command Get-NetUDPEndpoint -ErrorAction SilentlyContinue)
  $out = @()
  for ($try = 1; $try -le 4; $try++) {   # a node that was just stopped can hold its ports for a moment
    $out = @()
    if ($haveCmd) {
      $l = @(Get-NetTCPConnection -State Listen -LocalPort $apiPort -ErrorAction SilentlyContinue)
      if ($l.Count) { $out += "TCP port $apiPort (api= in logos-miner.ini) is already used by $(Port-Owner $l[0].OwningProcess)" }
      foreach ($u in $udp) { $e = @(Get-NetUDPEndpoint -LocalPort $u -ErrorAction SilentlyContinue); if ($e.Count) { $out += "UDP port $u (node P2P/Blend port) is already used by $(Port-Owner $e[0].OwningProcess)" } }
    } else {
      try { $t = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback, $apiPort); $t.Start(); $t.Stop() } catch { $out += "TCP port $apiPort (api= in logos-miner.ini) is already in use" }
      foreach ($u in $udp) { try { $s = New-Object Net.Sockets.UdpClient ($u); $s.Close() } catch { $out += "UDP port $u (node P2P/Blend port) is already in use" } }
    }
    if (-not $out.Count) { return @() }
    Start-Sleep 2
  }
  $out
}
function Arm-Running { [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -and $_.CommandLine.Contains($PSCommandPath) -and $_.CommandLine -match '--arm' }) }
function Start-Node {
  $c = Load-Cfg
  if (Test-Path $Data) { icacls $Data /inheritance:r /grant:r "*$([Security.Principal.WindowsIdentity]::GetCurrent().User.Value):(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" /Q | Out-Null; icacls "$Data\*" /inheritance:e /T /Q /C | Out-Null }
  if (-not (Test-Path $Ucfg)) { Init-Node }
  if (Node-Proc) { Write-Host 'Node already running.' } else {
    $pc = @(Port-Conflicts $c)
    if ($pc.Count) { Write-Host 'Cannot start the node: a port it needs is already taken.' -ForegroundColor Red; $pc | % { Write-Host "  - $_" -ForegroundColor Yellow }
      Say 'Fix: close the other program (if it is another Logos node or another LogosMiner folder, stop that one first), or pick free ports with api= / net_port= in logos-miner.ini. Nothing was started.' Yellow; return }
    Patch-Config $c
    $was032 = Cfg-Is032
    if ($was032) { Say 'First start with node 0.3.4: it converts data\user_config.yaml to its new, shorter format (the old file is kept as data\user_config.yaml.0.3.2.bak).' Cyan }
    # dry run: the node only reads its config and exits; this also does the 0.3.2 -> 0.3.4 conversion, so it is done before the real start
    Push-Location $Data; $chk = (& $Exe user_config.yaml --check-config 2>&1 | Out-String); $chkCode = $LASTEXITCODE; Pop-Location
    if ($chkCode -ne 0) {
      Write-Host 'Cannot start the node: it could not read data\user_config.yaml.' -ForegroundColor Red
      @((Strip-Ansi $chk) -split "\r?\n" | ? { $_.Trim() } | select -Last 8) | % { Write-Host "  $_" -ForegroundColor Gray }
      Say 'If you just went back to an older LogosMiner build: use Update menu > roll back (it also puts the matching config back), or rename data\user_config.yaml.0.3.2.bak to user_config.yaml.' Yellow
      return }
    if ($was032) { Patch-Config $c }   # re-apply logos-miner.ini on the converted file
    $nargs = @('user_config.yaml')
    if ($c.mode -eq 'full') {
      if (-not (Get-NetFirewallRule -Name LogosNodeP2P -ErrorAction SilentlyContinue)) {
        $fw = "New-NetFirewallRule -Name LogosNodeP2P -DisplayName 'Logos node P2P (UDP)' -Protocol UDP -LocalPort $($c.net_port) -Action Allow; New-NetFirewallRule -Name LogosNodeP2PTcp -DisplayName 'Logos node P2P (TCP)' -Protocol TCP -LocalPort $($c.net_port) -Action Allow"
        try { New-NetFirewallRule -Name LogosNodeP2P -DisplayName 'Logos node P2P (UDP)' -Protocol UDP -LocalPort ([int]$c.net_port) -Action Allow -ErrorAction Stop | Out-Null; New-NetFirewallRule -Name LogosNodeP2PTcp -DisplayName 'Logos node P2P (TCP)' -Protocol TCP -LocalPort ([int]$c.net_port) -Action Allow -ErrorAction Stop | Out-Null } catch { Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -Command $fw" }
      }
      if ($c.external_address) { $proto = $(if ($c.external_address -match '^\d+\.\d+\.\d+\.\d+$') {'ip4'} else {'dns4'}); $nargs += @('--external-address', "/$proto/$($c.external_address)/udp/$($c.net_port)/quic-v1") }
    } else {
      # mine-only: make sure nothing is left open from an earlier full-node run
      if (Get-NetFirewallRule -Name LogosNodeP2P* -ErrorAction SilentlyContinue) {
        try { Remove-NetFirewallRule -Name LogosNodeP2P,LogosNodeP2PTcp -ErrorAction Stop } catch { Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -Command Remove-NetFirewallRule -Name LogosNodeP2P,LogosNodeP2PTcp' }
      }
    }
    Remove-Item $PauseFile -Force -ErrorAction SilentlyContinue   # a fresh start always mines (the 'stop mining' pause only lasts until the node restarts)
    if (Test-Path $Log) { Move-Item $Log "$Log.prev" -Force -ErrorAction SilentlyContinue }
    $script:fresh = $true
    $np = Start-Process -FilePath $Exe -ArgumentList $nargs -WorkingDirectory $Data -WindowStyle Hidden `
      -RedirectStandardOutput $Log -RedirectStandardError "$Log.err" -PassThru
    $null = $np.Handle  # cache the process handle so ExitCode is readable after exit
    Write-Host "Node starting ($($c.mode) mode, $($c.threads) threads). Waiting for API (up to 5 minutes; a first start can be slow)" -NoNewline -ForegroundColor Cyan
    $up = $false
    for ($i=0; $i -lt 150; $i++) {
      Start-Sleep 2; Write-Host '.' -NoNewline -ForegroundColor DarkCyan
      if ($np.HasExited) { break }
      if (Api '/cryptarchia/info') { $up = $true; break }
    }
    Write-Host ''
    if (-not $up) { Show-StartFailure $np $c; return }
  }
  if (Api '/cryptarchia/info') {
    if ($script:fresh) {
      Start-Sleep 5; $ps = Pow-State
      if ($ps -eq 'stalled') {
        if (Can-Heal) { Note-Heal; Write-Host 'Your PC was too slow to finish the node startup within 60 s, so its mining service did not start. Restarting the node automatically (this normally fixes it)...' -ForegroundColor Yellow; Stop-Node; $script:fresh = $false; Start-Node; return }
        else { Write-Host 'The node mining service did not start (slow PC). Auto-restart limit reached; try menu R, or close other heavy programs first.' -ForegroundColor Red }
      }
    }
    if (-not (Arm-Running)) { Start-Detached '--arm' }
    Write-Host 'Node is up. A small background helper switches mining on the moment the chain is Online (a brand-new node needs sync + up to 1 hour bootstrap; a node with existing data is usually Online within a minute or two). Check progress with menu 3 (Status).' -ForegroundColor Green
    Write-Host 'Rewards: the node claims its winning tickets by itself (auto-claim runs with no balance limit). Menu C (manual claim) is optional.' -ForegroundColor Green
  } else { Write-Host "The node process is running but its API is not answering yet. Wait a minute and check status (menu), or see $Log" -ForegroundColor Yellow }
}

function Say($t,$col='Gray') { Write-Host $t -ForegroundColor $col }
function Kv($k,$v,$col='White') { Write-Host ('  {0,-13}' -f $k) -NoNewline -ForegroundColor DarkCyan; Write-Host $v -ForegroundColor $col }

# Long-running REST call with a live "working... Ns" line (node API can take minutes while all threads mine).
function Invoke-Slow($path, $method='GET', $body=$null, $maxSec=600) {
  $c = Load-Cfg
  Add-Type -AssemblyName System.Net.Http
  $hc = New-Object System.Net.Http.HttpClient; $hc.Timeout = [TimeSpan]::FromSeconds($maxSec + 30)
  $uri = "http://$($c.api)$path"
  $req = $null
  try { $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::new($method), [Uri]$uri) } catch { return @{ ok=$false; code=0; text="bad request/address ($uri): $($_.Exception.Message)" } }
  if ($body) { $req.Content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json') }
  $sw = [Diagnostics.Stopwatch]::StartNew(); $task = $hc.SendAsync($req)
  while (-not $task.IsCompleted) {
    if ($sw.Elapsed.TotalSeconds -gt $maxSec) { Write-Host ''; return @{ ok=$false; code=0; text="gave up after $maxSec s (node still too busy)" } }
    Write-Host ("`r  working... {0,4}s elapsed (node is busy mining, this can take minutes - please wait)   " -f [int]$sw.Elapsed.TotalSeconds) -NoNewline -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
  }
  Write-Host ("`r  done in {0}s{1}" -f [int]$sw.Elapsed.TotalSeconds, (' ' * 60)) -ForegroundColor DarkGray
  if ($task.IsFaulted) { return @{ ok=$false; code=0; text=$task.Exception.GetBaseException().Message } }
  $r = $task.Result; $txt = $r.Content.ReadAsStringAsync().Result
  @{ ok=$r.IsSuccessStatusCode; code=[int]$r.StatusCode; text=$txt }
}
function Log-Claims {
  # Ground truth from the node log (works even when the REST API is too busy to answer)
  $r = @{ n = 0; last = ''; tick = '' }
  if (Test-Path $Log) {
    $l = Get-Content $Log -Tail 4000 -ErrorAction SilentlyContinue | ? { $_ -match 'Claimed \d+ PoW|Mined a winning' }
    $cl = @($l | ? { $_ -match 'Claimed \d+ PoW' }); $r.n = $cl.Count
    if ($cl.Count) { $r.last = ($cl[-1] -replace '\x1b\[[0-9;]*m','') }
    $tk = @($l | ? { $_ -match 'Mined a winning' }); if ($tk.Count) { $r.tick = ($tk[-1] -replace '\x1b\[[0-9;]*m','') }
  }
  $r
}
function Claim-Rewards {
  $c = Load-Cfg
  Say '  ---- CLAIM REWARDS ----' Cyan
  if (-not (Node-Proc)) { Say '  The node is not running. Start it first (menu 1 or 2).' Yellow; return }
  $ps = Pow-State
  if ($ps -eq 'stalled') {
    Say '  Cannot claim: the node mining service never started (slow PC startup), so the claim call can only time out.' Red
    if ((Read-Host '  Restart the node now to fix this? y/N') -eq 'y') { Stop-Node; Start-Node }
    return
  }
  if ($ps -ne 'ready') {
    Say '  Nothing to claim yet: mining has not started. It starts only after the chain is Online (a brand-new node: sync + up to 1 hour). Check menu 3 and come back later.' Yellow
    return
  }
  Say '  Note: the node already claims winning tickets by itself (see "Claimed N PoW reward(s)" in the log, menu 9). This manual claim is optional.' DarkGray
  $res = $null
  for ($try=1; $try -le 4; $try++) {
    Say "  Checking claimable rewards (attempt $try/4)..." Cyan
    $res = Invoke-Slow '/pow/rewards/claimable' 'GET' $null 600
    if ($res.ok) { break }
    if ($res.code -eq 408) { Say '  node busy (HTTP 408) - retrying...' Yellow } else { break }
  }
  if (-not $res.ok) {
    Say "  Could not read claimable rewards via API: HTTP $($res.code) $($res.text)" Red
    Say '  This is normal while the PC is busy mining: the node answers these calls very slowly (HTTP 408 = "node busy"). Nothing is broken and nothing is lost.' Yellow
    Say '  Winning tickets are claimed automatically by the node; so a manual claim is optional. Showing what the node log says instead:' Yellow
    $lc = Log-Claims
    if ($lc.tick) { Kv 'last ticket' $lc.tick DarkGray }
    if ($lc.last) { Kv 'last claim' $lc.last DarkGray } else { Kv 'last claim' 'none in recent log' DarkGray }
  } else {
    Say '  Claimable rewards:' Green
    try { $res.text | ConvertFrom-Json | ConvertTo-Json -Depth 6 | % { Write-Host "    $_" -ForegroundColor White } } catch { Write-Host "    $($res.text)" -ForegroundColor White }
  }
  $addr = $c.claim_public_key
  if ($addr) { Say "  Pay to claim_public_key from logos-miner.ini: $addr" DarkCyan }
  else {
    Say '  No claim_public_key set in logos-miner.ini. Default = this node''s own reward key (auto-claim target).' Yellow
    $in = Read-Host '  Press Enter for the default, or paste a 64-hex PUBLIC key to pay to'
    if ($in) {
      if ($in -match '^[0-9a-fA-F]{64}$') {
        $addr = $in
        if ((Read-Host '  Save this public key into logos-miner.ini? y/N') -eq 'y') { $c.claim_public_key = $addr; Save-Cfg $c; Say '  Saved (public key only).' Green }
      } else { Say '  Not a valid 64-hex public key - using the default.' Red }
    }
  }
  if ((Read-Host '  Claim now? y/N') -ne 'y') { Say '  Cancelled.' Yellow; return }
  $body = $(if ($addr) { @{ claim_address = $addr } | ConvertTo-Json -Compress } else { $null })
  $before = Log-Claims
  $cr = $null
  for ($try=1; $try -le 3; $try++) {
    Say "  Submitting claim (attempt $try/3)..." Cyan
    $cr = Invoke-Slow '/pow/claim' 'POST' $body 600
    if ($cr.ok) { break }
    if ($cr.code -ne 408) { break }
    Say '  HTTP 408: node did not answer in time. The claim may still have been processed - verifying...' Yellow
    Start-Sleep 5
    $after = Log-Claims
    if ($after.last -and $after.last -ne $before.last) { Say '  VERIFIED: node log shows a new claim went through:' Green; Write-Host "    $($after.last)" -ForegroundColor White; return }
    $v = Invoke-Slow '/pow/rewards/claimable' 'GET' $null 120
    if ($v.ok) { Say "  Re-check claimable: $($v.text)" White }
    if ($try -lt 3) { Say '  Not confirmed yet - retrying (a repeat claim is safe: it only pays what is still claimable).' Yellow }
  }
  if ($cr.ok) {
    Say '  CLAIM SUBMITTED' Green
    if ($cr.text -and $cr.text.Trim() -notin 'null','') { Write-Host "  Result (tx): $($cr.text)" -ForegroundColor White } else { Say '  Node reports nothing to claim right now (no claimable tickets yet).' Yellow }
  } else {
    Say "  CLAIM NOT CONFIRMED: HTTP $($cr.code) $($cr.text)" Red
    $after = Log-Claims
    if ($after.last -and $after.last -ne $before.last) { Say '  ...but the node log shows a claim did go through:' Green; Write-Host "    $($after.last)" -ForegroundColor White }
    else { Say '  No new claim in the node log. The node is too busy right now; also note the node auto-claims winning tickets on its own (see "Claimed N PoW reward(s)" in the log). Try again later.' Yellow }
  }
}
function Run-Threads { if (Test-Path $Ucfg) { $m = Select-String -Path $Ucfg -Pattern '^\s+max_threads:\s*(\d+)' | select -First 1; if ($m) { return [int]$m.Matches[0].Groups[1].Value } }; 0 }
function Status {
  $p = Node-Proc; $c = Load-Cfg
  Say '  ---- STATUS ----' Cyan
  $upm = 0
  if ($p) { $upm = Node-Up-Min; Kv 'Node' "running (pid $($p.Id)), up $upm min" Green } else { Kv 'Node' 'stopped' Red }
  Kv 'Threads' "$($c.threads) configured, $(if ($p) { (Run-Threads) } else { '-' }) used by the running node  (this PC has $([Environment]::ProcessorCount) CPU threads / $(Cpu-Cores) cores)" White
  $i = Api '/cryptarchia/info' 'GET' 15
  $online = $false
  if ($i) {
    $ci = $i.cryptarchia_info; $online = ($ci.state -eq 'Online')
    $col = $(if ($online) {'Green'} else {'Yellow'})
    Kv 'Chain state' "$($ci.state) / $($i.phase)" $col
    Kv 'Height' "$($ci.height)   (slot $($ci.slot))" White
    if (-not $online) { $left = [math]::Max(0, 60 - $upm); Kv 'Bootstrap' "chain not Online yet. After sync a brand-new node waits up to 60 min in total (started $upm min ago, at most ~$left min to go)." Yellow }
  } elseif ($p) { Kv 'Chain' 'API busy or starting...' Yellow }
  if ($p) {
    $ps = Pow-State
    if ($ps -eq 'ready') {
      $ms = Mining-State 10
      if ($ms.state -eq 'on') {
        $since = Pow-Started-At
        Kv 'Mining' "ACTIVE$(if ($since) { " (since $since)" })$(if ($ms.src -eq 'log') { '  [confirmed from node log; the status call is slow while all CPU threads are busy - that is normal]' })" Green
        if ($ms.st -and $ms.st.auto_claim) { $t = @($ms.st.auto_claim.targets)[0]; Kv 'Auto-claim' "$(if ($ms.st.auto_claim.is_armed) {'armed'} else {'NOT armed'}), reward key balance $(if ($t) { Fmt $t.balance } else { '?' }) base units" $(if ($ms.st.auto_claim.is_armed) {'Green'} else {'Yellow'}) }
      } elseif ($ms.state -eq 'off') {
        if (Test-Path $PauseFile) { Kv 'Mining' 'OFF - you stopped it (menu 5). Press 6 to start again.' Yellow }
        elseif ($online) { Kv 'Mining' 'OFF right now - the background helper is switching it on (menu 6 does it at once)' Yellow }
        else { Kv 'Mining' 'OFF - the node is not Online yet; mining starts when it is' Yellow }
      } else {
        if ($online) { Kv 'Mining' 'not confirmed yet - the node did not answer the status call (busy). Press 6, or look again in a minute.' Yellow }
        else { Kv 'Mining' 'not started - it starts when the chain is Online (see Bootstrap above)' Yellow }
      }
    } elseif ($ps -eq 'stalled') {
      Kv 'Mining' 'NOT RUNNING - a node service gave up waiting at startup (slow PC).' Red
      Say '               Fix: menu R (restart node). The panel also tries this automatically up to 3 times.' Yellow
    } else {
      if ($online) { Kv 'Mining' 'waiting - the mining service is about to start (check again in a minute)' Yellow }
      else { Kv 'Mining' 'not started - it starts by itself the moment the chain is Online (see Bootstrap above)' Yellow }
    }
    if (Test-Path (Join-Path $Data 'autoheal.log')) { Kv 'Auto-repair' "$(@(Get-Content $HealLog).Count) automatic restart(s) so far" DarkGray }
  }
}
function Show-Log {
  $f = $Log
  if (-not (Test-Path $f)) { Say "  No log yet ($f). Start the node first (menu 1 or 2)." Yellow; return }
  $fi = Get-Item $f
  $off = [TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalHours
  Say "  Log file: $f  ($([int]($fi.Length/1024)) KB). Times in the log are UTC; your local time is UTC$(if ($off -ge 0) {'+'})$off." DarkCyan
  $raw = @(Get-Content $f -Tail 400 -ErrorAction SilentlyContinue | % { Strip-Ansi $_ } | ? { $_.Trim() })
  if (-not $raw) { Say '  (the log is still empty - the node has only just started; try again in a minute)' Yellow }
  $noise = @($raw | ? { $_ -match 'quinn_udp|sending stopped by peer|Sending response failed|Failed to send blocks to peer' })
  $keep = @($raw | ? { $_ -notmatch 'quinn_udp|sending stopped by peer|Sending response failed|Failed to send blocks to peer' }) | select -Last 40
  foreach ($l in $keep) { $l = $(if ($l.Length -gt 220) { $l.Substring(0,220) + ' ...' } else { $l }); if ($l -match ' ERROR ') { Write-Host "  $l" -ForegroundColor Red } elseif ($l -match ' WARN ') { Write-Host "  $l" -ForegroundColor Yellow } else { Write-Host "  $l" -ForegroundColor Gray } }
  if ($noise.Count) { Say "  ($($noise.Count) harmless network-noise lines hidden: peers disconnecting / Windows UDP size warnings)" DarkGray }
  if ((Test-Path "$f.err") -and (Get-Item "$f.err").Length -gt 0) { Say '  --- node.log.err (last 15 lines) ---' DarkCyan; Get-Content "$f.err" -Tail 15 | % { Write-Host "  $(Strip-Ansi $_)" -ForegroundColor Red } }
}
function Stop-Node {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -and $_.CommandLine.Contains($PSCommandPath) -and $_.CommandLine -match '--arm' } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Api '/pow/mining/stop' 'PUT' 6 | Out-Null; $p = Node-Proc; if ($p) { $p | Stop-Process -Force -EA 0; Start-Sleep 3; Node-Proc | % { Invoke-CimMethod -Query "select * from Win32_Process where ProcessId=$($_.Id)" -MethodName Terminate | Out-Null }; Write-Host "Node stopped." -ForegroundColor Yellow } }

# ======================= WALLET + INSCRIBE (added v3) =======================
$Lx         = Join-Path $Root 'bin\lxpost.exe'
$InscKey    = Join-Path $Data 'inscribe_key.json'
$InscLog    = Join-Path $Data 'inscriptions.log'
$InscTmp    = Join-Path $Data 'inscribe_tmp'
$Explorer   = 'https://logos.ulti.mom'
$MaxInsc    = 1835008      # protocol limit: MAX_BLOCK_TRANSACTIONS_SIZE (2 MiB) * 7/8, whole inscription incl. our header
$TxOverhead = 369          # bytes a funded inscription tx adds around the payload (1 funding input + change note + proofs); measured
$ExecGas    = 646          # 56 (inscribe op) + 590 (fee transfer op)
$PrioPct    = 12           # safety margin the wallet adds on top of the mandatory fee (same default as the official wallet/SDK)
$script:DryRun = ($args -contains '--dry-run')

function Fmt($n) { ([decimal]$n).ToString('N0', [Globalization.CultureInfo]::InvariantCulture) }
function Ceil-Div($a,$b) { [int64][math]::Floor(([decimal]$a + [decimal]$b - 1) / [decimal]$b) }
function Est-Fee($bytes, $ep, $sp) {   # estimate before building the tx; the exact fee is read from the real funded tx afterwards
  $m = [int64]$ExecGas * $ep + ([int64]$bytes + $TxOverhead) * $sp
  [int64]($m + (Ceil-Div ($m * $PrioPct) 100))
}
function Say2($a,$ac,$b,$bc) { Write-Host $a -NoNewline -ForegroundColor $ac; Write-Host $b -ForegroundColor $bc }

# Slow-API wrapper: retries HTTP 408 / timeouts (node answers slowly while all threads mine)
function Retry-Slow($path, $method='GET', $body=$null, $maxSec=300, $tries=3) {
  $r = $null
  for ($i=1; $i -le $tries; $i++) {
    $r = Invoke-Slow $path $method $body $maxSec
    if ($r.ok -or ($r.code -ne 408 -and $r.code -ne 0)) { return $r }
    if ($i -lt $tries) { Say "  node busy (HTTP $($r.code)) - retrying ($($i+1)/$tries)..." Yellow; Start-Sleep 3 }
  }
  $r
}

function Get-WalletKey($apiSec=60) {
  # The node's own wallet key = auto-claim target (rewards land here and this node can spend from it). Public key only.
  if (Test-Path $Ucfg) { $m = [regex]::Match((Get-Content $Ucfg -Raw), '(?ms)^  auto_claim:.*?-\s*public_key:\s*([0-9a-fA-F]{64})'); if ($m.Success) { return $m.Groups[1].Value.ToLower() } }
  $al = Get-Content (Join-Path $Data 'arm.log') -Tail 8 -ErrorAction SilentlyContinue
  foreach ($l in @($al)) { if ($l -match '"targets":\[\{"public_key":"([0-9a-f]{64})"') { return $Matches[1] } }
  if (-not (Node-Proc)) { return $null }
  $s = Api '/pow/status' 'GET' $apiSec
  if ($s -and $s.auto_claim -and $s.auto_claim.targets) { $k = @($s.auto_claim.targets)[0].public_key; if ($k -match '^[0-9a-f]{64}$') { return $k } }
  $null
}
function Get-Balance($pk) {
  $r = Retry-Slow "/wallet/$pk/balance" 'GET' $null 300 3
  if ($r.code -eq 404) { return @{ ok=$true; bal=[int64]0; notes=0 } }       # 404 = key has no notes yet = balance 0
  if (-not $r.ok) { return @{ ok=$false; code=$r.code; text=$r.text } }
  $b = [regex]::Match($r.text, '"balance":(\d+)').Groups[1].Value
  if (-not $b) { return @{ ok=$false; code=$r.code; text='unexpected answer from node' } }
  @{ ok=$true; bal=[int64]$b; notes=([regex]::Matches($r.text, '"[0-9a-f]{64}":\d+')).Count }
}
function Show-Balance {
  $c = Load-Cfg
  Say '  ---- WALLET BALANCE ----' Cyan
  if (-not (Node-Proc)) { Say '  The node is not running. Start it first (menu 1 or 2).' Red; return }
  $pk = Get-WalletKey
  if (-not $pk) { Say '  Could not find this node''s wallet key yet (the node has not reported its mining status). Wait a few minutes after the node is Online and try again.' Yellow; return }
  Kv 'Wallet key' $pk White
  $b = Get-Balance $pk
  if (-not $b.ok) { Say "  Could not read the balance: HTTP $($b.code) $($b.text)" Red; Say '  The node API is busy (it is mining). Try again in a minute.' Yellow; return }
  if ($b.bal -eq 0) { Kv 'Balance' '0 base units  (no rewards claimed to this key yet)' Yellow }
  else { Kv 'Balance' "$(Fmt $b.bal) base units   ($($b.notes) coins/notes)" Green }
  Kv 'Explorer' "$Explorer/#/addr/$pk" DarkGray
  if ($c.claim_public_key) {
    if ($c.claim_public_key -ne $pk) {
      Write-Host ''
      Kv 'Payout key' "$($c.claim_public_key)   (claim_public_key in logos-miner.ini)" White
      $b2 = Get-Balance $c.claim_public_key
      if ($b2.ok) { Kv 'Balance' "$(Fmt $b2.bal) base units   (rewards claimed with menu C go here; this node cannot spend it unless it owns that key)" Gray }
      Kv 'Explorer' "$Explorer/#/addr/$($c.claim_public_key)" DarkGray
    } else { Kv 'Payout key' 'same as wallet key' DarkGray }
  } else { Kv 'Payout key' 'not set - claims go to the wallet key above' DarkGray }
  Say '  Unit: testnet base units. Inscriptions are paid from the wallet key above.' DarkGray
}

# ---- helpers for inscribe ----
function Run-Lx([string[]]$a, [string]$out, [string]$err) {
  $q = ($a | % { '"' + ($_ -replace '"','\"') + '"' }) -join ' '
  $p = Start-Process -FilePath $Lx -ArgumentList $q -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $p.ExitCode
}
function Read-Out([string]$f, [string]$pattern='\S') {   # read a tool output file; wait briefly if the OS has not flushed it yet
  for ($i=0; $i -lt 25; $i++) { if (Test-Path $f) { $t = Get-Content $f -Raw -ErrorAction SilentlyContinue; if ($t -and $t -match $pattern) { return $t } }; Start-Sleep -Milliseconds 200 }
  ''
}
function Utf8NoBom { New-Object Text.UTF8Encoding $false }
function Be16([int]$n) { [byte[]]@([math]::Floor($n / 256), ($n % 256)) }
function Sha256Hex([byte[]]$b) { $s=[Security.Cryptography.SHA256]::Create(); ([BitConverter]::ToString($s.ComputeHash($b)) -replace '-','').ToLower() }
function Clean-Str([string]$s, [int]$max) { $s = ($s -replace '[\x00-\x1f\x7f]', ' ').Trim(); if ($s.Length -gt $max) { $s = $s.Substring(0,$max) }; $s }
function Envelope([string]$magic, $meta, [byte[]]$data) {
  $mb = (Utf8NoBom).GetBytes(($meta | ConvertTo-Json -Compress))
  if ($mb.Length -gt 65535) { return $null }
  $ms = New-Object IO.MemoryStream
  $h = [Text.Encoding]::ASCII.GetBytes($magic); $ms.Write($h,0,4); $l = Be16 $mb.Length; $ms.Write($l,0,2); $ms.Write($mb,0,$mb.Length); $ms.Write($data,0,$data.Length)
  $ms.ToArray()
}
function Is-Protected-Path([string]$p) {
  $full = [IO.Path]::GetFullPath($p).ToLower()
  $dd = ([IO.Path]::GetFullPath($Data).TrimEnd('\') + '\').ToLower()
  if ($full.StartsWith($dd)) { return $true }
  $leaf = [IO.Path]::GetFileName($full)
  return ($leaf -in 'keystore.yaml','user_config.yaml','inscribe_key.json')
}
function Image-Mime([byte[]]$b) {
  if ($b.Length -ge 3 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF) { return 'image/jpeg' }
  if ($b.Length -ge 8 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'image/png' }
  if ($b.Length -ge 6 -and $b[0] -eq 0x47 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x38) { return 'image/gif' }
  if ($b.Length -ge 12 -and $b[0] -eq 0x52 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x46 -and $b[8] -eq 0x57 -and $b[9] -eq 0x45 -and $b[10] -eq 0x42 -and $b[11] -eq 0x50) { return 'image/webp' }
  $null
}
function Read-FilePath([string]$what) {
  $p = (Read-Host "  Path of the $what (you can drag the file into this window)").Trim().Trim('"').Trim("'")
  if (-not $p) { Say '  Cancelled (no path).' Yellow; return $null }
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Say "  That is not a file: $p" Red; return $null }
  $p
}
function Size-Table($ep, $sp) {
  Say '  Rough price list (fee grows with size):' DarkGray
  foreach ($kb in 1,10,100,500,1024) { $by = $kb*1024; if ($by -lt $MaxInsc) { Write-Host ('     {0,6} KB  ~  {1,12} base units' -f $kb, (Fmt (Est-Fee $by $ep $sp))) -ForegroundColor DarkGray } }
}
function Resize-Advice {
  Say '  How to make an image smaller:' Yellow
  Say '   - Paint / Photos: Resize (e.g. 50%), then Save as JPEG (quality 70-80%).' Yellow
  Say '   - Or convert to WebP (very small) at https://squoosh.app  -  aim for under 100 KB.' Yellow
}

function Get-Channel($cid) {   # returns @{ ok; tip = '' (new channel) | 64hex }
  $r = Retry-Slow "/channel/$cid" 'GET' $null 120 3
  if ($r.code -eq 404) { return @{ ok=$true; tip='' } }
  if (-not $r.ok) { return @{ ok=$false; code=$r.code; text=$r.text } }
  if (-not $r.text -or $r.text.Trim() -in 'null','') { return @{ ok=$true; tip='' } }
  $m = [regex]::Match($r.text, '"tip_message":"([0-9a-f]{64})"')
  @{ ok=$true; tip=$m.Groups[1].Value; raw=$r.text }
}
function Http-Quiet($path, $method='GET', $sec=40) {   # no spinner; for polling
  $c = Load-Cfg
  Add-Type -AssemblyName System.Net.Http
  $hc = New-Object System.Net.Http.HttpClient; $hc.Timeout = [TimeSpan]::FromSeconds($sec)
  try { $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::new($method), [Uri]"http://$($c.api)$path")
        $r = $hc.SendAsync($req).GetAwaiter().GetResult(); $t = $r.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        @{ ok=$r.IsSuccessStatusCode; code=[int]$r.StatusCode; text=$t } } catch { @{ ok=$false; code=0; text=$_.Exception.Message } }
}
function Tx-State($hash, $cid, $msgId) {   # 'landed' | 'pending' | 'unknown'   (the tx lookup also answers for queued txs, so the queue is checked first)
  $r = Http-Quiet "/channel/$cid" 'GET' 40
  if ($r.ok -and $msgId -and $r.text -match "`"tip_message`":`"$msgId`"") { return 'landed' }
  $m = Http-Quiet '/mempool/view' 'GET' 60
  if ($m.ok -and $m.text -match $hash) { return 'pending' }
  $t = Http-Quiet "/cryptarchia/transaction/$hash" 'GET' 40
  if ($t.ok) { return 'landed' }
  'unknown'
}
function Log-Insc($o) { Add-Content $InscLog ($o | ConvertTo-Json -Compress) -Encoding UTF8 }
function Last-Insc { if (Test-Path $InscLog) { $l = @(Get-Content $InscLog -ErrorAction SilentlyContinue | ? { $_.Trim() }); if ($l.Count) { try { return ($l[-1] | ConvertFrom-Json) } catch {} } }; $null }
function Show-InscHistory {
  Say '  ---- YOUR INSCRIPTIONS (this PC) ----' Cyan
  if (-not (Test-Path $InscLog)) { Say '  none yet' Yellow; return }
  $rows = @(Get-Content $InscLog | ? { $_.Trim() } | % { try { $_ | ConvertFrom-Json } catch {} })
  foreach ($r in ($rows | Select -Last 10)) {
    Write-Host ("  {0}  {1,-6} {2,10} B  fee {3,9}  {4}" -f $r.time, $r.kind, (Fmt $r.bytes), (Fmt $r.fee), $r.status) -ForegroundColor White
    Write-Host "     tx $($r.hash)" -ForegroundColor Gray
    Write-Host "     $Explorer/#/tx/$($r.hash)" -ForegroundColor DarkGray
  }
  $last = $rows | Select -Last 1
  if ($last -and $last.status -ne 'landed' -and $last.cid) {
    Say '  Checking the last one on the node...' DarkCyan
    $st = Tx-State $last.hash $last.cid $last.msg
    Say "  Last inscription state: $st" $(if ($st -eq 'landed') {'Green'} else {'Yellow'})
    if ($st -eq 'landed') { Log-Insc @{ time=(Get-Date -Format s); hash=$last.hash; msg=$last.msg; cid=$last.cid; kind=$last.kind; bytes=$last.bytes; fee=$last.fee; status='landed' } }
  }
}

function Inscribe-Menu {
  Say '  ---- INSCRIBE: write data permanently on the Logos chain ----' Cyan
  if ($script:DryRun) { Say '  *** DRY-RUN: everything is calculated and checked, NOTHING is sent ***' Magenta }
  if (-not (Test-Path $Lx)) { Say '  bin\lxpost.exe is missing - re-extract the whole zip.' Red; return }
  if (-not (Node-Proc)) { Say '  The node is not running. Start it first (menu 1 or 2).' Red; return }
  $ci = Api '/cryptarchia/info'
  if (-not $ci) { Say '  The node API is not answering yet (busy or starting). Try again in a minute.' Yellow; return }
  if ($ci.cryptarchia_info.state -ne 'Online') { Say "  The node is '$($ci.cryptarchia_info.state)' - it must be Online and fully synced before it can send transactions. Check status (3)." Yellow; return }
  Write-Host ''
  Say '  How it works, in plain words:' White
  Say '   * An inscription is data (text, a picture, any file) stored forever inside a blockchain transaction.' Gray
  Say '   * It is PUBLIC and PERMANENT: everyone can read it, nobody can edit or delete it - not even you.' Gray
  Say '   * You pay a small fee from your wallet; it depends on the size in bytes. You see the exact price first.' Gray
  Say "   * Maximum size: $(Fmt $MaxInsc) bytes (1.75 MiB) per inscription, including a small header we add." Gray
  Say '   * Nothing is sent until you type YES on the final confirmation screen.' Gray
  Write-Host ''
  MenuItem '1' 'Text      (a message, up to a few KB is typical)' Green
  MenuItem '2' 'Image     (JPEG / PNG / GIF / WebP - shows up in the explorer gallery)' Cyan
  MenuItem '3' 'Other file (any file; stored on-chain, explorer does not preview it)' Magenta
  MenuItem '4' 'My inscriptions / check status of the last one' Yellow
  MenuItem '0' 'Back' DarkGray
  $ch = (Read-Host '  Choose').Trim()
  if ($ch -eq '4') { Show-InscHistory; return }
  if ($ch -notin '1','2','3') { return }

  # ---- 1. gather the data + build the on-chain payload ----
  $kind = ''; $desc = ''; $payload = $null; $rawBytes = 0
  if ($ch -eq '1') {
    $kind = 'text'
    Say '  Type your text. Finish with an EMPTY line (just press Enter on a blank line).' White
    $lines = @(); while ($true) { $l = Read-Host '  >'; if ($l -eq '') { break }; $lines += $l }
    $text = $lines -join "`n"
    if (-not $text.Trim()) { Say '  Nothing typed - cancelled (an empty inscription is not allowed).' Yellow; return }
    $payload = (Utf8NoBom).GetBytes($text); $rawBytes = $payload.Length
    if ($text -match '^(?:LX[A-Z]\d)') { Say '  Text may not start with LX?1 (reserved prefix used by other inscription formats). Add a word in front.' Red; return }
    if ($text -match '[0-9a-fA-F]{64}') { Say '  WARNING: your text contains a 64-character hex string - that looks like a KEY. Anything inscribed is public forever!' Red; if ((Read-Host '  Continue anyway? type YES') -cne 'YES') { Say '  Cancelled.' Yellow; return } }
    $one = $text.Replace("`n",' / '); if ($one.Length -gt 60) { $one = $one.Substring(0,57) + '...' }
    $desc = "text: `"$one`"  ($($text.Length) characters)"
    if ($payload.Length -ne $text.Length) { Say "  Note: $($text.Length) characters = $($payload.Length) bytes (accents/emoji take more than 1 byte)." DarkGray }
  } else {
    $p = Read-FilePath $(if ($ch -eq '2') {'image'} else {'file'})
    if (-not $p) { return }
    if (Is-Protected-Path $p) { Say '  REFUSED: that file is part of your node data (keys/config). It must never be published.' Red; return }
    $fi = Get-Item -LiteralPath $p
    if ($fi.Length -eq 0) { Say '  REFUSED: the file is empty (0 bytes).' Red; return }
    if ($fi.Length -gt $MaxInsc) {
      Say "  REFUSED: file is $(Fmt $fi.Length) bytes; the absolute maximum is $(Fmt $MaxInsc) bytes (and a few bytes less after our header)." Red
      Say "  It is $(Fmt ($fi.Length - $MaxInsc)) bytes too big." Red
      if ($ch -eq '2') { Resize-Advice } else { Say '  Compress it (ZIP / 7-Zip) or split it into smaller parts.' Yellow }
      return }
    $bytes = [IO.File]::ReadAllBytes($p); $rawBytes = $bytes.Length
    $name = Clean-Str $fi.Name 120
    if ($ch -eq '2') {
      $kind = 'image'
      $mime = Image-Mime $bytes
      if (-not $mime) { Say '  REFUSED: this is not a JPEG, PNG, GIF or WebP image (checked the file contents, not the name). Use option 3 for other files.' Red; return }
      $title = Clean-Str (Read-Host "  Title (optional, Enter = none)") 80
      $creator = Clean-Str (Read-Host "  Creator (optional, Enter = none)") 80
      $meta = [ordered]@{ mime=$mime; sha256=(Sha256Hex $bytes) }
      if ($title) { $meta.title = $title }; if ($creator) { $meta.creator = $creator }
      $payload = Envelope 'LXI1' $meta $bytes
      $desc = "image $mime  `"$name`"" + $(if ($title) {"  title `"$title`""} else {''})
    } else {
      $kind = 'file'
      $ext = [IO.Path]::GetExtension($name).ToLower()
      $mime = switch ($ext) { '.pdf' {'application/pdf'} '.txt' {'text/plain'} '.json' {'application/json'} '.zip' {'application/zip'} '.md' {'text/markdown'} '.csv' {'text/csv'} '.mp3' {'audio/mpeg'} '.mp4' {'video/mp4'} default {'application/octet-stream'} }
      if ($ext -in '.exe','.dll','.bat','.cmd','.ps1','.scr','.msi','.vbs','.js') { Say '  WARNING: this is a program/script file. It will be public forever on the chain.' Yellow }
      $meta = [ordered]@{ name=$name; mime=$mime; sha256=(Sha256Hex $bytes) }
      $payload = Envelope 'LXF1' $meta $bytes
      $desc = "file `"$name`" ($mime)"
    }
    if (-not $payload) { Say '  Internal error building the header.' Red; return }
  }
  $total = $payload.Length
  if ($total -gt $MaxInsc) {
    Say "  REFUSED: with our header the inscription would be $(Fmt $total) bytes (maximum $(Fmt $MaxInsc)). Reduce the file by at least $(Fmt ($total - $MaxInsc)) bytes." Red
    if ($kind -eq 'image') { Resize-Advice }; return }

  # ---- 2. prices, wallet, channel ----
  Write-Host ''; Say '  Checking prices, your wallet and your inscription channel...' DarkCyan
  $gp = Retry-Slow '/mantle/gas-prices' 'GET' $null 120 3
  if (-not $gp.ok) { Say "  Could not read the current fee prices from the node: HTTP $($gp.code) $($gp.text). Try again shortly." Red; return }
  $ep = [int64]([regex]::Match($gp.text,'"execution_base_gas_price":(\d+)').Groups[1].Value); $sp = [int64]([regex]::Match($gp.text,'"storage_gas_price":(\d+)').Groups[1].Value)
  if ($ep -lt 1 -or $sp -lt 1) { Say "  Unexpected fee prices from node: $($gp.text)" Red; return }
  $pk = Get-WalletKey
  if (-not $pk) { Say '  Could not find this node''s wallet key yet. Wait until the node is Online and mining status is available, then retry.' Yellow; return }
  $bal = Get-Balance $pk
  if (-not $bal.ok) { Say "  Could not read your balance: HTTP $($bal.code) $($bal.text). The node is busy; try again in a minute." Red; return }
  $est = Est-Fee $total $ep $sp
  if ($bal.bal -lt $est) {
    Say "  NOT ENOUGH FUNDS. Estimated fee $(Fmt $est) base units, your balance $(Fmt $bal.bal). Missing about $(Fmt ($est - $bal.bal))." Red
    Say '  Keep mining and claim rewards (menu C), or send a smaller inscription.' Yellow; Size-Table $ep $sp; return }
  New-Item -ItemType Directory -Force $InscTmp | Out-Null
  $fReq = Join-Path $InscTmp 'req.json'; $fResp = Join-Path $InscTmp 'resp.json'; $fTx = Join-Path $InscTmp 'tx.json'; $fPay = Join-Path $InscTmp 'payload.bin'
  $fOut = Join-Path $InscTmp 'out.txt'; $fErr = Join-Path $InscTmp 'err.txt'
  function Clean-Tmp { Get-ChildItem $InscTmp -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
  if (-not (Test-Path $InscKey)) {
    Say '  First time: creating your inscription signing key (data\inscribe_key.json). Back it up with keystore.yaml; never share it.' Yellow
    if ((Run-Lx @('keygen',$InscKey) $fOut $fErr) -ne 0) { Say '  Could not create the signing key.' Red; Get-Content $fErr -ErrorAction SilentlyContinue | % { Say "   $_" Red }; return }
  }
  if ((Run-Lx @('ident',$InscKey) $fOut $fErr) -ne 0) { Say '  Could not read the signing key (file damaged?).' Red; return }
  $idt = Read-Out $fOut 'channel_id'
  try { $idj = $idt | ConvertFrom-Json; $cid = $idj.channel_id; $signer = $idj.signer } catch { $cid = '' }
  if ($cid -notmatch '^[0-9a-f]{64}$') { Say '  Could not read the signing key identity (file damaged?).' Red; Clean-Tmp; return }
  $chn = Get-Channel $cid
  if (-not $chn.ok) { Say "  Could not read your channel from the node: HTTP $($chn.code) $($chn.text)" Red; return }
  # one inscription at a time per channel: the next one must build on the previous one
  $prev = Last-Insc
  if ($prev -and $prev.status -ne 'landed' -and $prev.cid -eq $cid) {
    $st = Tx-State $prev.hash $cid $prev.msg
    if ($st -eq 'landed') { Log-Insc @{ time=(Get-Date -Format s); hash=$prev.hash; msg=$prev.msg; cid=$cid; kind=$prev.kind; bytes=$prev.bytes; fee=$prev.fee; status='landed' }; $chn = Get-Channel $cid }
    elseif ($st -eq 'pending') { Say "  Your previous inscription is still waiting in the node's queue ($($prev.hash)). Wait until it is included, then try again (menu 4 shows its state)." Yellow; return }
    else { Say "  Note: your previous inscription ($($prev.hash)) is neither on-chain nor queued - it was probably dropped. Continuing." DarkYellow }
  }
  [IO.File]::WriteAllBytes($fPay, $payload)
  $maxFee = [int64][math]::Min([decimal]$bal.bal, [decimal]([math]::Max($est * 3, 100000)))
  $rc = Run-Lx (@('fund-req',$InscKey,"@$fPay",$pk,"$maxFee") + $(if ($chn.tip) { @($chn.tip) } else { @() })) $fReq $fErr
  if ($rc -ne 0) { Say '  Could not build the transaction:' Red; Get-Content $fErr -Tail 3 | % { Say "   $_" Red }; Clean-Tmp; return }
  $msgId = [regex]::Match((Read-Out $fErr 'msg_id='), 'msg_id=([0-9a-f]{64})').Groups[1].Value
  if (-not $msgId) { Say '  Could not determine the inscription id.' Red; Clean-Tmp; return }
  $fr = Retry-Slow '/wallet/fund' 'POST' ([IO.File]::ReadAllText($fReq)) 600 3
  if (-not $fr.ok) {
    Say "  The wallet could not prepare the payment: HTTP $($fr.code)" Red
    if ($fr.text -match 'nsufficient|enough funds') { Say "  Not enough funds (balance $(Fmt $bal.bal), estimated fee $(Fmt $est))." Red } else { Say "  $($fr.text)" Gray }
    if ($fr.text -match 'exceeds max_tx_fee') { Say '  The fee came out higher than expected (network prices moved). Nothing was sent - just try again.' Yellow }
    if ($fr.code -eq 408 -or $fr.code -eq 0) { Say '  The node is too busy mining to answer. Try again in a few minutes (or lower mining threads, menu 4).' Yellow }
    Clean-Tmp; return }
  [IO.File]::WriteAllText($fResp, $fr.text, (Utf8NoBom))
  if ((Run-Lx @('info',$fResp,"$ep","$sp") $fOut $fErr) -ne 0) { Say '  Could not compute the exact fee.' Red; Clean-Tmp; return }
  try { $inf = (Read-Out $fOut 'mandatory_fee') | ConvertFrom-Json; if (-not $inf.mandatory_fee) { throw 'x' } } catch { Say '  Could not compute the exact fee.' Red; Clean-Tmp; return }
  $mand = [int64]$inf.mandatory_fee; $margin = Ceil-Div ($mand * $PrioPct) 100; $fee = $mand + $margin
  if ($fee -gt $bal.bal) { Say "  NOT ENOUGH FUNDS. Exact fee $(Fmt $fee), balance $(Fmt $bal.bal). Missing $(Fmt ($fee - $bal.bal))." Red; Clean-Tmp; return }
  $after = $bal.bal - $fee

  # ---- 3. confirmation screen ----
  Write-Host ''
  Say ('  ' + ('=' * 20) + ' CONFIRM INSCRIPTION ' + ('=' * 20)) Yellow
  Kv 'What' $desc White
  Kv 'Your data' "$(Fmt $rawBytes) bytes" White
  Kv 'On chain' "$(Fmt $total) bytes (data + header)   max allowed $(Fmt $MaxInsc)" White
  Kv 'Fee' "$(Fmt $fee) base units   = network fee $(Fmt $mand) + $PrioPct% safety margin $(Fmt $margin)" Green
  Kv 'Fee basis' "execution $(Fmt $inf.execution_gas) gas x $ep  +  $(Fmt $inf.storage_gas_bytes) tx bytes x $sp" DarkGray
  Kv 'From wallet' $pk White
  Kv 'Balance' "$(Fmt $bal.bal)  ->  $(Fmt $after) after" White
  Kv 'Channel' $cid DarkGray
  Kv 'Signer' $signer DarkGray
  Say '  This is IRREVERSIBLE: the data is PUBLIC and PERMANENT, and the fee is not refunded.' Red
  if ($script:DryRun) { Say '  DRY-RUN: stopping here. Nothing was sent, nothing was paid.' Magenta; Clean-Tmp; return }
  $ans = Read-Host '  Type YES (capital letters) to send it, anything else cancels'
  if ($ans -cne 'YES') { Say '  Cancelled. Nothing was sent.' Yellow; Clean-Tmp; return }

  # ---- 4. sign + submit (the tx hash is known before sending, so a retry can never double-send) ----
  if ((Run-Lx @('sign',$InscKey,$fResp) $fTx $fErr) -ne 0) { Say '  Signing failed:' Red; Get-Content $fErr -Tail 3 | % { Say "   $_" Red }; Clean-Tmp; return }
  $hash = [regex]::Match((Read-Out $fErr 'tx_hash='), 'tx_hash=(?:0x)?([0-9a-f]{64})').Groups[1].Value
  if (-not $hash) { Say '  Signing produced no transaction hash.' Red; Clean-Tmp; return }
  $rec = @{ time=(Get-Date -Format s); hash=$hash; msg=$msgId; cid=$cid; kind=$kind; bytes=$total; fee=$fee; status='sending' }
  Log-Insc $rec
  $body = [IO.File]::ReadAllText($fTx)
  $sent = $false; $final = $null
  for ($try=1; $try -le 3 -and -not $sent; $try++) {
    Say "  Sending to the network (attempt $try/3)..." Cyan
    $r = Invoke-Slow '/mempool/add/tx' 'POST' $body 600
    if ($r.ok) { $sent = $true; break }
    $final = $r
    if ($r.code -ne 408 -and $r.code -ne 0) { break }
    Say "  No answer in time (HTTP $($r.code)). Checking whether the node already has it, so nothing is sent twice..." Yellow
    $st = Tx-State $hash $cid $msgId
    if ($st -ne 'unknown') { $sent = $true; Say "  The node already has the transaction ($st). Not sending again." Green; break }
    Start-Sleep 5
  }
  if (-not $sent) {
    $rec.status = 'rejected'; Log-Insc $rec
    Say '  NOT SENT. The node refused or did not accept the transaction.' Red
    Say "  HTTP $($final.code): $($final.text)" Gray
    if ($final.text -match 'nsufficient|fee') { Say '  Plain English: the fee/balance did not fit. Try again; prices or your coins may have changed.' Yellow }
    elseif ($final.text -match 'parent|channel|nonce|Inscription') { Say '  Plain English: your channel moved on (an earlier inscription of yours landed or is pending). Wait a minute and try again.' Yellow }
    elseif ($final.text -match 'ouble|already|spent|nullifier|exists') { Say '  Plain English: the coins used for the fee are already used by another pending transaction. Wait for it to be included, then retry.' Yellow }
    else { Say '  Nothing was paid. Safe to try again later.' Yellow }
    Clean-Tmp; return }
  $rec.status = 'sent'; Log-Insc $rec
  try { Set-Clipboard -Value $hash } catch {}
  Write-Host ''
  Say '  SENT!  Transaction hash (full):' Green
  Write-Host "  $hash" -ForegroundColor White
  Say '  (copied to your clipboard)' DarkGray
  Say '  Verify on the explorer once it is in a block:' Gray
  Write-Host "    $Explorer/#/tx/$hash" -ForegroundColor Cyan
  if ($kind -eq 'image') { Write-Host "    $Explorer/#/inscription/$hash   (image page)" -ForegroundColor Cyan }
  Write-Host "    your channel: $cid" -ForegroundColor DarkGray
  Say '  Waiting for it to be included in a block (up to 3 minutes)...' DarkCyan
  $deadline = (Get-Date).AddMinutes(3); $st = 'pending'
  while ((Get-Date) -lt $deadline) {
    Start-Sleep 10
    $st = Tx-State $hash $cid $msgId
    Write-Host ("`r  state: {0}   " -f $st) -NoNewline -ForegroundColor Yellow
    if ($st -eq 'landed') { break }
  }
  Write-Host ''
  if ($st -eq 'landed') { $rec.status = 'landed'; Log-Insc $rec; Say '  INCLUDED ON-CHAIN. Done.' Green }
  else { Say '  Still waiting in the queue (normal when the network is busy). It will be included later; check with menu I > 4.' Yellow }
  Clean-Tmp
}
# ===================== end WALLET + INSCRIBE =====================

# ======================= SEND + RECEIVE (added v7) =======================
$XferLog = Join-Path $Data 'transfers.log'
$MaxXferInputs = 32   # the node's transfer builder takes at most 32 coins (notes) per transaction (measured on 0.3.2; unchanged in 0.3.4)
function Notes-Of($balText) {   # sorted-descending list of note values from a /wallet/<pk>/balance answer
  $v = @([regex]::Matches($balText, '"[0-9a-f]{64}":(\d+)') | % { [int64]$_.Groups[1].Value })
  @($v | Sort-Object -Descending)
}
function Get-Spendable($pk, $maxSec=300, $tries=3) {   # @{ ok; total; notes=<values desc>; map=<id,value hash> }
  $r = Retry-Slow "/wallet/$pk/balance" 'GET' $null $maxSec $tries
  if ($r.code -eq 404) { return @{ ok=$true; total=[int64]0; notes=@(); map=@{} } }
  if (-not $r.ok) { return @{ ok=$false; code=$r.code; text=$r.text } }
  $map = @{}; foreach ($m in [regex]::Matches($r.text, '"([0-9a-f]{64})":(\d+)')) { $map[$m.Groups[1].Value] = [int64]$m.Groups[2].Value }
  $tot = [regex]::Match($r.text, '"balance":(\d+)').Groups[1].Value
  if (-not $tot) { return @{ ok=$false; code=$r.code; text='unexpected answer from node' } }
  @{ ok=$true; total=[int64]$tot; notes=(Notes-Of $r.text); map=$map }
}
function Log-Xfer($o) { Add-Content $XferLog ($o | ConvertTo-Json -Compress) -Encoding UTF8 }
function Last-Xfer { if (Test-Path $XferLog) { $l = @(Get-Content $XferLog -ErrorAction SilentlyContinue | ? { $_.Trim() }); if ($l.Count) { try { return ($l[-1] | ConvertFrom-Json) } catch {} } }; $null }
function Xfer-State($hash) {   # 'landed' | 'pending' | 'unknown'
  $m = Http-Quiet '/mempool/view' 'GET' 60
  if ($m.ok -and $m.text -match $hash) { return 'pending' }
  $t = Http-Quiet "/cryptarchia/transaction/$hash" 'GET' 40
  if ($t.ok) { return 'landed' }
  'unknown'
}
function Explorer-Addr($pk, $to=25) {   # the community explorer's page data for one key, or $null (offline / not indexed yet)
  try {
    $ProgressPreference = 'SilentlyContinue'
    $r = Invoke-WebRequest -UseBasicParsing -Uri "$Explorer/data/a/$($pk.Substring(0,3)).json" -TimeoutSec $to
    $j = $r.Content | ConvertFrom-Json
    $p = $j.PSObject.Properties[$pk]; if ($p) { return $p.Value }
    return $false   # explorer reachable, key never seen
  } catch { return $null }
}
function Fund-Transfer($pk, $dest, [int64]$amount, [int64]$maxFee) {   # asks the node to pick coins + change (NOTHING is sent); returns the raw HTTP result
  $body = '{"tip":null,"tx_builder":{"mantle_tx":{"ops":[]},"ledger_inputs":[],"pending_transfer":{"inputs":[],"outputs":[{"value":' + $amount + ',"pk":"' + $dest + '"}]},"channel_multi_sig_proofs":{}},"change_public_key":"' + $pk + '","funding_public_keys":["' + $pk + '"],"max_tx_fee":' + $maxFee + ',"priority_fee_percent":' + $PrioPct + '}'
  Retry-Slow '/wallet/fund' 'POST' $body 600 3
}
# ---- reusable core (no prompts, no printing of secrets): the menus below call these ----
function Get-XferEnv {   # @{ ok; err; pk; ep; sp; w=<spendable>; estMax; top; pendingHash }
  if (-not (Test-Path $Lx)) { return @{ ok=$false; err='bin\lxpost.exe is missing - re-extract the whole zip.' } }
  if (-not (Node-Proc)) { return @{ ok=$false; err='The node is not running. Start it first (menu 1 or 2).' } }
  $ci = Api '/cryptarchia/info'
  if (-not $ci) { return @{ ok=$false; err='The node API is not answering yet (busy or starting). Try again in a minute.' } }
  if ($ci.cryptarchia_info.state -ne 'Online') { return @{ ok=$false; err="The node is '$($ci.cryptarchia_info.state)' - it must be Online and fully synced before it can send. Check status (3)." } }
  $pk = Get-WalletKey
  if (-not $pk) { return @{ ok=$false; err='Could not find this node''s wallet key yet. Wait until the node is Online and mining status is available, then retry.' } }
  $pend = $null
  $prev = Last-Xfer
  if ($prev -and $prev.status -eq 'sent') {
    $st = Xfer-State $prev.hash
    if ($st -eq 'landed') { $prev.status = 'landed'; Log-Xfer $prev } elseif ($st -eq 'pending') { $pend = $prev.hash }
  }
  $gp = Retry-Slow '/mantle/gas-prices' 'GET' $null 120 3
  if (-not $gp.ok) { return @{ ok=$false; err="Could not read the current fee prices from the node: HTTP $($gp.code) $($gp.text). Try again shortly." } }
  $ep = [int64]([regex]::Match($gp.text,'"execution_base_gas_price":(\d+)').Groups[1].Value); $sp = [int64]([regex]::Match($gp.text,'"storage_gas_price":(\d+)').Groups[1].Value)
  if ($ep -lt 1 -or $sp -lt 1) { return @{ ok=$false; err="Unexpected fee prices from node: $($gp.text)" } }
  $w = Get-Spendable $pk
  if (-not $w.ok) { return @{ ok=$false; err="Could not read your balance: HTTP $($w.code) $($w.text). The node is busy; try again in a minute." } }
  $top = @($w.notes | Select-Object -First $MaxXferInputs)
  $topSum = [int64]0; foreach ($x in $top) { $topSum += $x }
  $estMax = [int64][math]::Max(0, $topSum - (Xfer-Fee ([math]::Max(1,$top.Count)) $ep $sp).fee - 1000)   # local estimate from the coin list; the node's exact numbers are checked after you type SEND
  @{ ok=$true; pk=$pk; ep=$ep; sp=$sp; w=$w; estMax=$estMax; ncoins=@($w.notes).Count; pendingHash=$pend }
}
function Test-DestKey([string]$d) {   # -> @{ ok; key; err }
  $d = ($d.Trim().ToLower()) -replace '^0x',''
  if ($d -notmatch '^[0-9a-f]{64}$') { return @{ ok=$false; err="That is not a Logos key. It must be exactly 64 characters, 0-9 and a-f (you typed $($d.Length) characters)." } }
  if ($d -match '^0{64}$') { return @{ ok=$false; err='The all-zero key is not a real address.' } }
  @{ ok=$true; key=$d }
}
function Xfer-Fee([int]$n, [int64]$ep, [int64]$sp) {   # exact fee of a 2-output transfer with n coins (measured: 244 bytes + 32 per extra coin); @{ mand; fee }
  $mand = [int64](590 * $ep + (244 + 32 * ($n - 1)) * $sp); $margin = Ceil-Div ($mand * $PrioPct) 100
  @{ mand=$mand; fee=($mand + $margin) }
}
function New-TransferPreview($xe, [string]$dest, [int64]$amount, [bool]$isMax=$false) {
  # Local calculation only: asks the node for NOTHING, so it reserves no coins. -> @{ ok; err; hint; plan } (plan.estimated = $true)
  $pk = $xe.pk; $w = $xe.w; $self = ($dest -eq $pk)
  $notes = @($w.notes)
  if ($isMax) {
    $n = [math]::Min($MaxXferInputs, $notes.Count); $sum = [int64]0; foreach ($x in ($notes | Select-Object -First $n)) { $sum += $x }
    $amount = $sum - (Xfer-Fee $n $xe.ep $xe.sp).fee - 1000
  }
  if ($amount -lt 1) { return @{ ok=$false; err='The amount must be at least 1 (after the fee).' } }
  if ($amount -gt $w.total) { return @{ ok=$false; err="NOT ENOUGH FUNDS: you want to send $(Fmt $amount) but have $(Fmt $w.total)." } }
  $sum = [int64]0; $n = 0; $f = $null
  foreach ($x in $notes) { $sum += $x; $n++; $f = Xfer-Fee $n $xe.ep $xe.sp; if ($sum -ge $amount + $f.fee + 1) { break } }
  if ($sum -lt $amount + $f.fee) { return @{ ok=$false; err="NOT ENOUGH FUNDS: $(Fmt $amount) plus the fee of about $(Fmt $f.fee) is more than your balance $(Fmt $w.total)." } }
  if ($n -gt $MaxXferInputs) { return @{ ok=$false; err="Too big for ONE transfer: it would need $n coins (the limit is $MaxXferInputs). Send less, or first send to your own key to merge coins." } }
  $change = $sum - $amount - $f.fee
  @{ ok=$true; plan=@{ dest=$dest; self=$self; amount=$amount; fee=$f.fee; mand=$f.mand; execGas=590; storBytes=(244 + 32 * ($n - 1)); ep=$xe.ep; sp=$xe.sp
       nIn=$n; sumIn=$sum; change=$change; balance=$w.total; after=($w.total - $f.fee - $(if ($self) { 0 } else { $amount })); from=$pk; estimated=$true } }
}
function Prepare-Transfer($xe, [string]$dest, [int64]$amount, [bool]$isMax=$false) {
  # Builds and fully checks a transfer WITHOUT sending it. -> @{ ok; err; hint; plan }.  The node reserves the chosen coins for a few minutes.
  $pk = $xe.pk; $w = $xe.w; $ep = $xe.ep; $sp = $xe.sp; $self = ($dest -eq $pk)
  if ($amount -lt 1) { return @{ ok=$false; err='The amount must be at least 1.' } }
  if ($amount -gt $w.total) { return @{ ok=$false; err="NOT ENOUGH FUNDS: you want to send $(Fmt $amount) but have $(Fmt $w.total)." } }
  if (-not $isMax -and $amount -gt $xe.estMax + 5000) { return @{ ok=$false; err="Too big for ONE transfer (max about $(Fmt $xe.estMax) with your current coins). First send some to your own key to merge coins, or send less." } }
  New-Item -ItemType Directory -Force $InscTmp | Out-Null
  $fResp = Join-Path $InscTmp 'xfer_resp.json'; $fOut = Join-Path $InscTmp 'out.txt'; $fErr = Join-Path $InscTmp 'err.txt'
  $maxFee = [int64][math]::Min([decimal]$w.total, 20000000)
  $fr = Fund-Transfer $pk $dest $amount $maxFee
  if ($isMax) { for ($k = 1; $k -le 14 -and -not $fr.ok -and $fr.text -match 'static maximum|nsufficient|enough funds'; $k++) { $amount = $(if ($k -le 4) { $amount - 1500 } else { [int64]($amount * 0.97) }); $fr = Fund-Transfer $pk $dest $amount $maxFee } }   # "max": step down until the change coin's own fee fits
  if (-not $fr.ok) {
    $e = "The wallet could not build the transfer: HTTP $($fr.code)"; $h = ''
    if ($fr.text -match 'nsufficient|enough funds') { $e = "Not enough free coins to send $(Fmt $amount) plus the fee. Try a smaller amount."; $h = 'After a preview or a send, the node keeps those coins reserved for a few minutes. If you just did one, wait ~5 minutes and retry.' }
    elseif ($fr.text -match 'static maximum') { $h = "That needs more than $MaxXferInputs coins. Send less, or first send to your own key to merge coins." }
    elseif ($fr.text -match 'exceeds max_tx_fee') { $h = 'The fee came out unexpectedly high. Nothing was sent.' }
    elseif ($fr.code -eq 408 -or $fr.code -eq 0) { $h = 'The node is too busy mining to answer. Try again in a few minutes (or lower mining threads, menu 4).' }
    elseif ($fr.code -eq 422 -or $fr.text -match 'nvalid|ecode|ield|deserial') { $h = 'The node does not accept that key (not a valid key value). Check it again.' }
    else { $h = $fr.text }
    return @{ ok=$false; err=$e; hint=$h } }
  [IO.File]::WriteAllText($fResp, $fr.text, (Utf8NoBom))
  try { $fj = $fr.text | ConvertFrom-Json } catch { return @{ ok=$false; err='Could not read the node answer.' } }
  $tops = @($fj.funded_tx.ops | ? { $_.opcode -eq 0 })
  if ($tops.Count -ne 1 -or @($fj.funded_tx.ops).Count -ne 1) { return @{ ok=$false; err='SAFETY STOP: the node returned an unexpected transaction shape. Nothing was sent.' } }
  $ins = @($tops[0].payload.inputs); $outs = @($tops[0].payload.outputs)
  $sumIn = [int64]0; $unknown = 0
  foreach ($i in $ins) { if ($w.map.ContainsKey($i)) { $sumIn += $w.map[$i] } else { $unknown++ } }
  if ($unknown) { return @{ ok=$false; err="SAFETY STOP: $unknown input coin(s) are not in your wallet view (the wallet changed meanwhile). Nothing was sent - try again." } }
  $recv = @($outs | ? { $_.pk -eq $dest -and [int64]$_.value -eq $amount })
  $bad  = @($outs | ? { $_.pk -ne $dest -and $_.pk -ne $pk })
  if ($recv.Count -lt 1 -or $bad.Count -gt 0) { return @{ ok=$false; err='SAFETY STOP: the transaction does not pay exactly what you asked, or pays a third key. Nothing was sent.' } }
  $sumOut = [int64]0; foreach ($o in $outs) { $sumOut += [int64]$o.value }
  $fee = $sumIn - $sumOut; $change = $sumOut - $amount
  if ($fee -lt 1 -or $fee -gt $maxFee) { return @{ ok=$false; err="SAFETY STOP: computed fee $(Fmt $fee) is outside the expected range. Nothing was sent." } }
  if (-not $self -and $fee -gt [math]::Max(200000, [int64]($amount / 2))) { return @{ ok=$false; err="SAFETY STOP: the fee ($(Fmt $fee)) is far larger than expected for this amount. Nothing was sent." } }
  if ((Run-Lx @('info',$fResp,"$ep","$sp") $fOut $fErr) -ne 0) { return @{ ok=$false; err='Could not compute the network fee.' } }
  try { $inf = (Read-Out $fOut 'mandatory_fee') | ConvertFrom-Json; $mand = [int64]$inf.mandatory_fee; if ($mand -lt 1) { throw 'x' } } catch { return @{ ok=$false; err='Could not compute the network fee.' } }
  @{ ok=$true; plan=@{ dest=$dest; self=$self; amount=$amount; fee=$fee; mand=$mand; execGas=$inf.execution_gas; storBytes=$inf.storage_gas_bytes; ep=$ep; sp=$sp
       nIn=$ins.Count; sumIn=$sumIn; change=$change; balance=$w.total; after=($w.total - $fee - $(if ($self) { 0 } else { $amount })); from=$pk; respFile=$fResp } }
}
function Sign-TransferPlan($plan) {   # -> @{ ok; err; hash; body }   (signing only; nothing is sent)
  $fTx = Join-Path $InscTmp 'xfer_tx.json'; $fOut = Join-Path $InscTmp 'out.txt'; $fErr = Join-Path $InscTmp 'err.txt'
  if (-not (Test-Path $InscKey)) { if ((Run-Lx @('keygen',$InscKey) $fOut $fErr) -ne 0) { return @{ ok=$false; err='Could not prepare the signing helper.' } } }   # (this helper key only satisfies the tool; the transfer itself is signed by the node wallet)
  if ((Run-Lx @('sign',$InscKey,$plan.respFile) $fTx $fErr) -ne 0) { return @{ ok=$false; err='Signing failed: ' + ((Get-Content $fErr -Tail 3 -ErrorAction SilentlyContinue) -join ' ') } }
  $hash = [regex]::Match((Read-Out $fErr 'tx_hash='), 'tx_hash=(?:0x)?([0-9a-f]{64})').Groups[1].Value
  if (-not $hash) { return @{ ok=$false; err='Signing produced no transaction hash.' } }
  @{ ok=$true; hash=$hash; body=[IO.File]::ReadAllText($fTx) }
}
function Submit-TransferPlan($plan, $sg, [scriptblock]$log={ param($m) Say "  $m" Cyan }) {   # -> @{ ok; err; code; hash }.  Only call after the user typed SEND.
  $rec = @{ time=(Get-Date -Format s); hash=$sg.hash; to=$plan.dest; amount=$plan.amount; fee=$plan.fee; status='sending' }
  Log-Xfer $rec
  $sent = $false; $final = $null
  for ($try=1; $try -le 3 -and -not $sent; $try++) {
    & $log "Sending to the network (attempt $try/3)..."
    $r = Invoke-Slow '/mempool/add/tx' 'POST' $sg.body 600
    if ($r.ok) { $sent = $true; break }
    $final = $r
    if ($r.code -ne 408 -and $r.code -ne 0) { break }
    & $log "No answer in time (HTTP $($r.code)). Checking whether the node already has it, so nothing is sent twice..."
    if ((Xfer-State $sg.hash) -ne 'unknown') { $sent = $true; & $log 'The node already has the transaction. Not sending again.'; break }
    Start-Sleep 5
  }
  if (-not $sent) { $rec.status = 'rejected'; Log-Xfer $rec; return @{ ok=$false; code=$final.code; err=$final.text; hash=$sg.hash } }
  $rec.status = 'sent'; Log-Xfer $rec
  @{ ok=$true; hash=$sg.hash }
}
function Get-ReceiveKey {   # -> @{ ok; err; pk; payoutKey }   FAST: local files first, never waits on a busy node for long. Public keys only.
  $c = Load-Cfg
  $pk = Get-WalletKey 15
  if (-not $pk) {
    if (-not (Test-Path $Ucfg)) { return @{ ok=$false; err='This folder has no node identity yet (data\user_config.yaml is missing). Start the node once (menu 1 or 2), then try again.' } }
    if (-not (Node-Proc)) { return @{ ok=$false; err='Could not find the wallet key in data\user_config.yaml and the node is not running. Start it (menu 1 or 2) and try again.' } }
    return @{ ok=$false; err='Could not find this node''s wallet key yet (not in data\user_config.yaml and the node did not answer within 15 s). Try again in a few minutes.' }
  }
  @{ ok=$true; pk=$pk; payoutKey=$(if ($c.claim_public_key -and $c.claim_public_key.ToLower() -ne $pk) { $c.claim_public_key.ToLower() } else { '' }) }
}
function Get-RecentIncoming($pk, $budgetSec=20) {   # -> @{ ok; rows; checked; partial }  explorer only, strict time budget (never blocks the menu)
  $ProgressPreference = 'SilentlyContinue'   # Windows PowerShell 5.1 downloads are very slow with the progress bar on
  $res = @{ ok=$true; rows=@(); checked=0; partial=$false }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $ex = Explorer-Addr $pk 10
  if ($ex -eq $null) { $res.ok = $false; return $res }
  if ($ex -eq $false -or -not $ex.recv) { return $res }
  $own = @{}; foreach ($s in @($ex.sent)) { $own[[string]$s[0]] = $true }   # change from my own sends is not "incoming"
  $cand = @($ex.recv | Select-Object -Last 40); [array]::Reverse($cand)
  $shards = @{}; $rows = @()
  foreach ($r in $cand) {
    if ($rows.Count -ge 8) { break }
    $h = [string]$r[0]; if ($own.ContainsKey($h) -or $h.Length -lt 3) { continue }
    $pre = $h.Substring(0,3)
    if (-not $shards.ContainsKey($pre)) {
      $left = [int]($budgetSec - $sw.Elapsed.TotalSeconds)
      if ($left -lt 2) { $res.partial = $true; break }
      try { $shards[$pre] = (Invoke-WebRequest -UseBasicParsing -Uri "$Explorer/data/tx/$pre.json" -TimeoutSec ([math]::Min(8, $left))).Content | ConvertFrom-Json } catch { $shards[$pre] = $null }
    }
    $res.checked++
    $t = $(if ($shards[$pre]) { $shards[$pre].PSObject.Properties[$h] } else { $null })
    $isReward = $false; if ($t) { foreach ($o in @($t.Value.tx.ops)) { if ($o.opcode -eq 64) { $isReward = $true } } }   # opcode 64 = PoW reward claim
    if (-not $isReward) { $rows += @{ height=$r[2]; value=[int64]$r[1]; tx=$h } }
  }
  $res.rows = $rows; $res
}
function Get-ReceiveInfo {   # -> @{ ok; err; pk; balanceOk; balance; coins; payoutKey; incoming=<rows>; sent=<rows>; explorerOk }  (bounded: ~1.5 min worst case)
  $k = Get-ReceiveKey
  if (-not $k.ok) { return @{ ok=$false; err=$k.err } }
  $res = @{ ok=$true; pk=$k.pk; payoutKey=$k.payoutKey; balanceOk=$false; balance=0; coins=0; incoming=@(); sent=@(); explorerOk=$true }
  if (Node-Proc) { $w = Get-Spendable $k.pk 60 1; if ($w.ok) { $res.balanceOk = $true; $res.balance = $w.total; $res.coins = @($w.notes).Count } }
  $in = Get-RecentIncoming $k.pk; $res.explorerOk = $in.ok; $res.incoming = $in.rows
  if (Test-Path $XferLog) { $res.sent = @(Get-Content $XferLog | ? { $_.Trim() } | % { try { $_ | ConvertFrom-Json } catch {} } | Group-Object hash | % { $_.Group[-1] } | Select-Object -Last 5) }
  $res
}

# ---- the Send menu (text screens only; all logic is in the functions above) ----
function Send-Menu {
  Say '  ---- SEND: move coins to another Logos key ----' Cyan
  if ($script:DryRun) { Say '  *** DRY-RUN: everything is calculated and checked, NOTHING is sent ***' Magenta }
  $env_ = Get-XferEnv
  if (-not $env_.ok) { Say "  $($env_.err)" $(if ($env_.err -match 'missing|not running') { 'Red' } else { 'Yellow' }); return }
  if ($env_.pendingHash) { Say "  Your previous transfer is still waiting in the node's queue ($($env_.pendingHash)). Wait until it is included, then try again." Yellow; return }
  Write-Host ''
  Say '  How it works, in plain words:' White
  Say '   * You send testnet coins from THIS wallet key to any Logos key (64 characters, 0-9 and a-f).' Gray
  Say '   * Amounts are in base units, whole numbers only. Rewards come in coins of about 2,000,000 base units each.' Gray
  Say '   * A small network fee (roughly 1,500-5,000 base units) is paid on top. You see the exact numbers first.' Gray
  Say '   * A transfer is FINAL: a wrong destination cannot be undone. Nothing is sent until you type SEND.' Gray
  Say "   * One transfer can gather at most $MaxXferInputs coins. For a bigger amount, first send to your own key to merge coins." Gray
  Say '   * Only coins can be sent. Inscriptions cannot be sent one by one (the chain has no per-inscription owner).' Gray
  Write-Host ''
  $c = Load-Cfg
  if ($c.claim_public_key -and $c.claim_public_key.ToLower() -ne $env_.pk) { Say "  NOTE: your payout key (claim_public_key) is a different key. Only this node's wallet key can be spent from here." Yellow }
  Kv 'From wallet' $env_.pk White
  Kv 'Balance' "$(Fmt $env_.w.total) base units in $($env_.ncoins) coins" Green
  Kv 'Fee prices' "execution $($env_.ep), storage $($env_.sp)" DarkGray
  if ($env_.ncoins -eq 0) { Say '  You have no coins to send yet. Keep mining and claim rewards (menu C).' Yellow; return }
  Kv 'Max per send' "about $(Fmt $env_.estMax) base units (your $MaxXferInputs biggest coins; merge coins by sending to your own key)" DarkGray
  Write-Host ''
  $dt = Read-Host '  Destination key (64 characters, or empty to cancel)'
  if (-not $dt.Trim()) { Say '  Cancelled.' Yellow; return }
  $dk = Test-DestKey $dt
  if (-not $dk.ok) { Say "  REFUSED: $($dk.err)" Red; return }
  $dest = $dk.key; $self = ($dest -eq $env_.pk)
  if ($self) { Say '  That is YOUR OWN wallet key: this merges your coins into fewer, bigger coins (costs only the fee).' Yellow }
  $at = (Read-Host '  Amount in base units (whole number, or "max")').Trim().ToLower() -replace '[,_ ]',''
  $isMax = ($at -eq 'max')
  if ($isMax) { $amount = $env_.estMax } elseif ($at -match '^\d{1,18}$') { $amount = [int64]$at } else { Say '  REFUSED: type a whole number like 5000000 (no decimals, no letters).' Red; return }
  $pr = New-TransferPreview $env_ $dest $amount $isMax
  if (-not $pr.ok) { Say "  $($pr.err)" Red; if ($pr.hint) { Say "  $($pr.hint)" Yellow }; return }
  $p = $pr.plan
  $ex = $null; if (-not $p.self) { $ex = Explorer-Addr $dest }
  Write-Host ''
  Say ('  ' + ('=' * 22) + ' CONFIRM TRANSFER ' + ('=' * 22)) Yellow
  Kv 'To' $dest White
  if ($p.self) { Kv '' '(your own wallet key - coin merge)' DarkGray }
  elseif ($ex -eq $null) { Say '               (could not check the explorer for this key)' DarkGray }
  elseif ($ex -is [bool]) { Say '               Never seen on-chain before (explorer). Fine for a new key - but double-check every character.' Yellow }
  else { Kv '' "known key: $($ex.claims) claims, last active block $($ex.last)" DarkGray }
  Kv 'Amount' "$(Fmt $p.amount) base units" Green
  Kv 'Network fee' "$(Fmt $p.fee) base units   = $(Fmt $p.mand) mandatory + $(Fmt ($p.fee - $p.mand)) safety margin ($PrioPct%)" Green
  Kv 'Fee basis' "execution $(Fmt $p.execGas) gas x $($p.ep)  +  $(Fmt $p.storBytes) tx bytes x $($p.sp)" DarkGray
  Kv 'Total leaves' "$(Fmt ($p.amount + $p.fee)) base units$(if ($p.self) {'   (only the fee is really lost - the rest returns to you)'})" White
  Kv 'Coins used' "$($p.nIn) coin(s) worth $(Fmt $p.sumIn)" White
  Kv 'Change back' "$(Fmt $p.change) base units, returned to your wallet key" White
  Kv 'Balance' "$(Fmt $p.balance)  ->  $(Fmt $p.after) after" White
  if (-not $p.self -and $p.amount -le $p.fee * 2) { Say "  WARNING: the fee ($(Fmt $p.fee)) is $(if ($p.amount -le $p.fee) {'as large as or larger than'} else {'more than half of'}) the amount you send ($(Fmt $p.amount)). You pay more in fees than the receiver gets. Tiny coins also cost the receiver extra fee when they spend them later." Yellow }
  Say '  This is IRREVERSIBLE: the coins cannot be recalled and the fee is not refunded.' Red
  Say '  (Numbers are calculated from your coin list. The node confirms the exact fee the moment you type SEND.)' DarkGray
  if ($script:DryRun) {
    Say '  DRY-RUN: stopping here. Nothing was sent, nothing was paid, no coins were reserved.' Magenta; return }
  $ans = Read-Host '  Type SEND (capital letters) to send it, anything else cancels'
  if ($ans -cne 'SEND') { Say '  Cancelled. Nothing was sent.' Yellow; return }
  Say '  Asking the node to pick the coins and confirm the exact fee...' DarkCyan
  $pp = Prepare-Transfer $env_ $dest $p.amount $isMax
  if (-not $pp.ok) { Say "  $($pp.err)" Red; if ($pp.hint) { Say "  $($pp.hint)" Yellow }; Say '  Nothing was sent.' Yellow; return }
  $q = $pp.plan
  if ($q.fee -ne $p.fee -or $q.nIn -ne $p.nIn -or $q.amount -ne $p.amount) {
    Say '  The node chose slightly different coins, so the final numbers changed:' Yellow
    Kv 'Amount' "$(Fmt $q.amount) base units" Green
    Kv 'Network fee' "$(Fmt $q.fee) base units   (was $(Fmt $p.fee))" Green
    Kv 'Coins used' "$($q.nIn) coin(s) worth $(Fmt $q.sumIn); change $(Fmt $q.change)" White
    if ((Read-Host '  Type SEND again to accept these numbers, anything else cancels') -cne 'SEND') { Say '  Cancelled. Nothing was sent. (The node holds those coins reserved for a few minutes.)' Yellow; return }
  }
  $p = $q
  $sg = Sign-TransferPlan $p
  if (-not $sg.ok) { Say "  $($sg.err)" Red; return }
  $res = Submit-TransferPlan $p $sg
  if (-not $res.ok) {
    Say '  NOT SENT. The node refused or did not accept the transaction.' Red
    Say "  HTTP $($res.code): $($res.err)" Gray
    if ($res.err -match 'ouble|already|spent|nullifier|exists|input') { Say '  Plain English: some of the coins are already used by another waiting transaction. Wait for it to be included, then retry.' Yellow }
    elseif ($res.err -match 'nsufficient|fee|gas') { Say '  Plain English: the fee did not fit (prices may have just changed). Nothing was paid - try again.' Yellow }
    else { Say '  Nothing was paid. Safe to try again later.' Yellow }
    return }
  try { Set-Clipboard -Value $res.hash } catch {}
  Write-Host ''
  Say '  SENT!  Transaction hash (full):' Green
  Write-Host "  $($res.hash)" -ForegroundColor White
  Say '  (copied to your clipboard)' DarkGray
  Write-Host "    $Explorer/#/tx/$($res.hash)" -ForegroundColor Cyan
  Say '  Waiting for it to be included in a block (up to 3 minutes)...' DarkCyan
  $deadline = (Get-Date).AddMinutes(3); $st = 'pending'
  while ((Get-Date) -lt $deadline) {
    Start-Sleep 10
    $st = Xfer-State $res.hash
    Write-Host ("`r  state: {0}   " -f $st) -NoNewline -ForegroundColor Yellow
    if ($st -eq 'landed') { break }
  }
  Write-Host ''
  if ($st -eq 'landed') { Log-Xfer @{ time=(Get-Date -Format s); hash=$res.hash; to=$p.dest; amount=$p.amount; fee=$p.fee; status='landed' }; Say '  INCLUDED ON-CHAIN. Done. (The explorer can lag a few minutes behind.)' Green }
  else { Say '  Still waiting in the queue (normal when the network is busy). It will be included later; check with menu A.' Yellow }
}
function Receive-Menu {
  Say '  ---- RECEIVE: your address and incoming coins ----' Cyan
  # 1) the address FIRST, straight from this folder's config (no waiting on the node)
  $k = Get-ReceiveKey
  if (-not $k.ok) { Say "  $($k.err)" Yellow; return }
  Write-Host ''
  Say '  Give this PUBLIC key to whoever sends you coins. It is safe to share (it is not a secret):' White
  Write-Host "  $($k.pk)" -ForegroundColor Green
  try { Set-Clipboard -Value $k.pk -ErrorAction Stop; Say '  (copied to your clipboard)' DarkGray } catch { Say '  (could not copy to clipboard - select and copy it from above)' DarkGray }
  if ($k.payoutKey) { Kv 'Payout key' "$($k.payoutKey)   (claimed rewards go here; it is a different key)" Gray }
  Kv 'Explorer' "$Explorer/#/addr/$($k.pk)" DarkGray
  Write-Host ''
  # 2) balance: ONE attempt, at most 60 s (the node API is slow while all threads mine)
  if (-not (Node-Proc)) { Say '  Balance: the node is not running (start it with menu 1 or 2). Your address above is still valid.' Yellow }
  else {
    Say '  Reading the balance from the node (max 60 s)...' DarkCyan
    $w = Get-Spendable $k.pk 60 1
    if ($w.ok) { Kv 'Balance' "$(Fmt $w.total) base units in $(@($w.notes).Count) coins" Green }
    else { Say "  Could not read the balance in time (node busy mining: $(if ($w.code) {"HTTP $($w.code)"} else {$w.text})). Try menu W later - your address above is all a sender needs." Yellow }
  }
  Write-Host ''
  # 3) incoming transfers from the explorer, strict 20 s budget
  Say '  Recent incoming transfers (mining rewards hidden; the explorer can lag ~10 minutes):' White
  $in = Get-RecentIncoming $k.pk 20
  if (-not $in.ok) { Say '   could not reach the explorer (offline?)' DarkGray }
  elseif (-not @($in.rows).Count) { Say "   none seen yet$(if ($in.checked) {' (only mining rewards)'})$(if ($in.partial) {' - checked only the newest entries (time limit); see the explorer link above'})" DarkGray }
  else { foreach ($r in $in.rows) { Write-Host ("   block {0,-8} +{1,14}   tx {2}" -f $r.height, (Fmt $r.value), $r.tx) -ForegroundColor White }; if ($in.partial) { Say '   (time limit reached - older entries not checked; see the explorer link above)' DarkGray } }
  $sent = @(); if (Test-Path $XferLog) { $sent = @(Get-Content $XferLog | ? { $_.Trim() } | % { try { $_ | ConvertFrom-Json } catch {} } | Group-Object hash | % { $_.Group[-1] } | Select-Object -Last 5) }
  if ($sent.Count) {
    Write-Host ''
    Say '  Sent from this PC:' White
    foreach ($r in $sent) { $to = [string]$r.to; $toS = $(if ($to.Length -ge 64) { $to.Substring(0,8) + '..' + $to.Substring(56) } else { $to }); Write-Host ("   {0}  -{1,14}  fee {2,6}  {3}  to {4}" -f $r.time, (Fmt $r.amount), (Fmt $r.fee), $r.status, $toS) -ForegroundColor White }
  }
}
# ===================== end SEND + RECEIVE =====================

# ======================= MINING ON/OFF (v6) =======================
function Set-Mining([bool]$on) {
  if (-not (Node-Proc)) { Say '  The node is not running. Use menu 1 or 2.' Yellow; return }
  if ((Pow-State) -ne 'ready') { Say '  The node mining service is not up yet (the chain must be Online first - see menu 3). Nothing to switch.' Yellow; return }
  $want = $(if ($on) { 'on' } else { 'off' })
  if ($on) { Remove-Item $PauseFile -Force -ErrorAction SilentlyContinue } else { Set-Content $PauseFile (Get-Date -Format s) }
  $path = $(if ($on) { '/pow/mining/start' } else { '/pow/mining/stop' })
  Say "  Asking the node to $(if ($on) {'start'} else {'stop'}) mining..." Cyan
  $r = Invoke-Slow $path 'PUT' $null 120
  $ms = $null
  for ($i = 0; $i -lt 10; $i++) { $ms = Mining-State 15; if ($ms.state -eq $want) { break }; Start-Sleep 3 }
  if ($ms.state -eq $want) {
    if ($on) { Say '  Mining is ON.' Green } else { Say '  Mining is OFF (the node keeps running; it stays off until you press 6 or restart the node).' Yellow }
  } elseif ($r.ok -or $r.code -eq 408) {
    Say "  Request sent (HTTP $($r.code)); the node has not confirmed yet - it is busy. Check menu 3 in a minute." Yellow
  } else { Say "  The node did not accept it: HTTP $($r.code) $($r.text)" Red }
}

# ======================= UPDATE (experimental, v6) =======================
# Signed manifest: manifest.json + manifest.sig (RSA-3072 / SHA-256, public key below). Files are downloaded to update\stage, checked against
# the sha256 in the manifest, the old files are backed up to update\backup-*, then swapped in. data\ (keys, chain, config), logos-miner.ini are never touched.
$DefaultUpdateUrl = 'https://logos.ulti.mom/miner/manifest.json'
$UpdPubMod = 'e47a89cfe99ef87dce43d0200bfbe353a1ed1c691ea778abe25011ea2be39e8b2dcc5d2b917a871d63f65670bfb8ae67350a102924b777c0335dc476fe3f1a30c6c02a97cfb95920d67c0e529eaf2dec53e0a2ae742ab2db7494efdb3e8aa73ef772d9390a233452d4d21316b61e1f254560ce32057a13dcfdb642eabcb39c7dab2f94945e272b79bdb4633fce09dc3b851a8d175668d9d8cc40a8b6277ef7dcd9d5928ab08f88f3e9b804e31f796cb9beef2ade71d4a54f931b79ea8ace0bf7154a81a86224eac5ded46aab5b19ad316b5967aac6bcbf4af6c8ed92822a7c541d5ce231991c346c69f318b534f20aeffd401e9c9cbfc1c179076ec18ed28c92735ce97bf3de4a83c84afd87607c0c10c1fb303da7991ebfa59f5c4a6a72fddc9176dc32d080826213e48538c20c16ec4600af05cdd54c79ec17530cb585ed652b554e4d7a2c641937017d42db40e0b6b6c8c203f602c6cde13d1820cabbb92434cfe2631e8edb1b6aebff9b787dcde457e8cf0f435c1e93d856f17d714fb82b'
$UpdPubExp = '010001'
$UpdDir = Join-Path $Root 'update'
$UpdLog = Join-Path $UpdDir 'update.log'
$UpdOkPath = '^(panel\.ps1|README\.txt|version\.txt|bin/[A-Za-z0-9._+-]+\.(exe|dll))$'    # LogosMiner.bat and logos-miner.ini are never replaced
function Upd-Log($t) { New-Item -ItemType Directory -Force $UpdDir | Out-Null; Add-Content $UpdLog "$(Get-Date -Format s) $t" }
function Hex2Bytes([string]$h) { $b = New-Object byte[] ($h.Length / 2); for ($i=0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($h.Substring(2*$i,2),16) }; $b }
function File-Sha([string]$f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() }
function Local-Build { $f = Join-Path $Root 'version.txt'; if (Test-Path $f) { $m = [regex]::Match((Get-Content $f -Raw), '^\s*(\d+)'); if ($m.Success) { return [int]$m.Groups[1].Value } }; $BuildNo }
function Fetch-File([string]$url, [string]$dest) {
  if ($url -match '^file:///') { Copy-Item -LiteralPath ([Uri]$url).LocalPath -Destination $dest -Force -ErrorAction Stop; return }
  if ($url -notmatch '^https://') { throw 'only https:// (or file:///) update addresses are allowed' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Add-Type -AssemblyName System.Net.Http
  $hc = New-Object System.Net.Http.HttpClient; $hc.Timeout = [TimeSpan]::FromMinutes(20)
  $hc.DefaultRequestHeaders.UserAgent.ParseAdd('LogosMiner-updater/' + $BuildNo)
  $resp = $hc.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
  if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode) for $url" }
  $fs = [IO.File]::Create($dest)
  try { $resp.Content.CopyToAsync($fs).GetAwaiter().GetResult() } finally { $fs.Close(); $hc.Dispose() }
}
function Verify-Sig([byte[]]$data, [byte[]]$sig) {
  $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
  $p = New-Object Security.Cryptography.RSAParameters
  $p.Modulus = Hex2Bytes $UpdPubMod; $p.Exponent = Hex2Bytes $UpdPubExp
  $rsa.ImportParameters($p)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $rsa.VerifyData($data, $sha, $sig) } catch { $false }
}
function Rel-Url([string]$base, [string]$rel) {
  $u = New-Object Uri ((New-Object Uri $base), $rel)
  $b = New-Object Uri $base
  if ($u.Scheme -ne $b.Scheme -or $u.Host -ne $b.Host) { throw "manifest points to a different host ($($u.Host)) - refused" }
  $u.AbsoluteUri
}
# returns @{ ok; msg; m = manifest object; base = url; bytes } after signature check
function Get-Manifest([string]$url) {
  $t = Join-Path $UpdDir 'tmp-manifest'; New-Item -ItemType Directory -Force $UpdDir | Out-Null
  try { Fetch-File $url "$t.json"; Fetch-File ($url -replace '\.json$', '.sig') "$t.sig" } catch { return @{ ok=$false; msg="could not download the update manifest: $($_.Exception.Message)" } }
  $mb = [IO.File]::ReadAllBytes("$t.json")
  $sigTxt = ([IO.File]::ReadAllText("$t.sig")).Trim()
  try { $sb = [Convert]::FromBase64String($sigTxt) } catch { return @{ ok=$false; msg='the manifest signature file is damaged' } }
  if (-not (Verify-Sig $mb $sb)) { return @{ ok=$false; msg='SIGNATURE CHECK FAILED - the manifest is not signed by the Logos Miner release key. Update refused.' } }
  try { $m = ([Text.Encoding]::UTF8.GetString($mb)).TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return @{ ok=$false; msg='manifest is not valid JSON' } }
  if ($m.app -ne 'LogosMiner' -or -not $m.build -or -not $m.files) { return @{ ok=$false; msg='manifest has the wrong format' } }
  @{ ok=$true; m=$m; base=$url }
}
function Move-Retry([string]$a,[string]$b) { for ($i=1; $i -le 8; $i++) { try { Move-Item -LiteralPath $a -Destination $b -Force -ErrorAction Stop; return } catch { if ($i -eq 8) { throw }; Start-Sleep 3 } } }   # Defender may lock a fresh file for a moment
function Pick-Backups { Get-ChildItem $UpdDir -Directory -Filter 'backup-*' -ErrorAction SilentlyContinue | sort Name }
function Restore-Backup([string]$bdir) {
  # put the saved files back (also used for automatic rollback)
  $listF = Join-Path $bdir 'files.txt'
  foreach ($rel in @(Get-Content $listF)) {
    if (-not $rel -or $rel -notmatch $UpdOkPath) { continue }
    $src = Join-Path $bdir ($rel -replace '/','\'); $dst = Join-Path $Root ($rel -replace '/','\')
    if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination "$dst.restore" -Force; Move-Retry "$dst.restore" $dst }
  }
  Restore-Cfg $bdir
}
# The node config must match the node version: node 0.3.4 converts a 0.3.2 config on its first start and node 0.3.2 cannot read the result.
# Since v8 every update saves a copy of data\user_config.yaml (kept inside data\, which only you can read); older backups (made by
# build 7 or earlier, node 0.3.2) have none, so for those the copy node 0.3.4 kept (user_config.yaml.0.3.2.bak) is used.
function Restore-Cfg([string]$bdir) {
  $src = $null
  $cf = Join-Path $bdir 'cfg.txt'
  if (Test-Path $cf) { $n = (Get-Content $cf -TotalCount 1).Trim(); if ($n -match '^cfg-backup-[\w.-]+\.yaml$') { $p = Join-Path $Data $n; if (Test-Path $p) { $src = $p } } }
  if (-not $src) {
    $vb = 0; $vf = Join-Path $bdir 'version.txt'; if (Test-Path $vf) { $m = [regex]::Match((Get-Content $vf -Raw), '^\s*(\d+)'); if ($m.Success) { $vb = [int]$m.Groups[1].Value } }
    if ($vb -ge 1 -and $vb -le 7 -and (Test-Path $Ucfg) -and -not (Cfg-Is032)) {
      $src = Get-ChildItem $Data -File -Filter 'user_config.yaml.0.3.2.bak*' -ErrorAction SilentlyContinue | sort LastWriteTime | select -Last 1 | % { $_.FullName }
    }
  }
  if (-not $src) { return }
  if (Test-Path $Ucfg) { Copy-Item -LiteralPath $Ucfg -Destination "$Ucfg.before-rollback" -Force }
  Copy-Item -LiteralPath $src -Destination "$Ucfg.restore" -Force; Move-Retry "$Ucfg.restore" $Ucfg
  Say "  Node config put back from $(Split-Path $src -Leaf) (the newer one is kept as user_config.yaml.before-rollback)." DarkGray
}
function Stop-For-Update {   # returns $true when no node process is left
  if (-not (Node-Proc)) { return $true }
  Say '  Stopping the node...' Yellow; Stop-Node
  for ($i=0; $i -lt 15; $i++) { if (-not (Node-Proc)) { return $true }; Start-Sleep 1 }
  [bool](-not (Node-Proc))
}
function Start-After-Update {   # starts the node with the (new) panel file in a detached process; $true when the API answers
  Say '  Starting the node with the updated files (this can take a few minutes)...' Cyan
  Start-Detached '--start'
  for ($i=0; $i -lt 180; $i++) { Start-Sleep 2; if ((Node-Proc) -and (Api '/cryptarchia/info' 'GET' 15)) { return $true } }
  $false
}
function Update-Menu([switch]$CheckOnly, [switch]$Yes) {
  Say '  ---- UPDATE (experimental) ----' Cyan
  $c = Load-Cfg
  $url = $(if ($c.update_url) { $c.update_url } else { $DefaultUpdateUrl })
  $localB = Local-Build
  Kv 'Installed' "build $localB ($BuildName)" White
  Kv 'Source' $url DarkGray
  Say '  Checking (the manifest must carry the Logos Miner release signature)...' DarkCyan
  $mf = Get-Manifest $url
  if (-not $mf.ok) { Say "  $($mf.msg)" Red; Upd-Log "check failed: $($mf.msg)"; return }
  $m = $mf.m
  Kv 'Latest' "build $($m.build) ($($m.name)), node $($m.node)" White
  if ($m.notes) { Kv 'What is new' ([string]$m.notes) Gray }
  if ([int]$m.build -le $localB) { Say '  You are up to date. Nothing to do.' Green; return }
  # decide which files differ
  $todo = @(); $bytes = 0
  foreach ($f in @($m.files)) {
    if ($f.path -notmatch $UpdOkPath) { Say "  Manifest lists a file that is not allowed to be updated ($($f.path)) - update refused." Red; Upd-Log "refused path $($f.path)"; return }
    if ($f.sha256 -notmatch '^[0-9a-f]{64}$') { Say '  Manifest has a bad checksum field - update refused.' Red; return }
    $dst = Join-Path $Root ($f.path -replace '/','\')
    if ((Test-Path $dst) -and ((File-Sha $dst) -eq $f.sha256)) { continue }
    $todo += $f; $bytes += [int64]$f.size
  }
  if (-not $todo.Count) { Say '  Files are already identical (only the version number changes).' Yellow }
  Say "  Files to replace: $($todo.Count)   download size: $([math]::Round($bytes/1MB,1)) MB" White
  foreach ($f in $todo) { Say "    - $($f.path)  ($([math]::Round([int64]$f.size/1KB)) KB)" Gray }
  Say '  Safe by design: old files are backed up first, data\ (keys, chain), logos-miner.ini are never touched, and if the node does not start again the old files are put back automatically.' DarkGray
  if ($CheckOnly) { Say '  (check only - nothing changed)' DarkGray; return }
  if (-not $Yes) { if ((Read-Host '  Install this update now? y/N') -ne 'y') { Say '  Cancelled. Nothing changed.' Yellow; return } }

  $stage = Join-Path $UpdDir 'stage'; Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $stage | Out-Null
  Upd-Log "update to build $($m.build) started from build $localB"
  # 1. download + verify into stage (nothing live is touched yet)
  try {
    foreach ($f in $todo) {
      $out = Join-Path $stage ($f.path -replace '/','_')
      Say "  Downloading $($f.path)..." Cyan
      if ($f.parts) {
        $fs = [IO.File]::Create($out)
        try { foreach ($pt in @($f.parts)) {
          $pf = "$out.part"; Fetch-File (Rel-Url $mf.base $pt.url) $pf
          if ((File-Sha $pf) -ne $pt.sha256) { throw "checksum mismatch in a part of $($f.path)" }
          $bs = [IO.File]::ReadAllBytes($pf); $fs.Write($bs, 0, $bs.Length); Remove-Item $pf -Force } } finally { $fs.Close() }
      } else { Fetch-File (Rel-Url $mf.base $f.url) $out }
      if ((File-Sha $out) -ne $f.sha256) { throw "checksum mismatch for $($f.path) - download damaged or tampered" }
      if ($f.path -eq 'panel.ps1') {
        $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($out, [ref]$null, [ref]$errs)
        if ($errs -and $errs.Count) { throw "new panel.ps1 does not parse ($($errs.Count) errors)" }
      }
    }
  } catch { Say "  DOWNLOAD/VERIFY FAILED: $($_.Exception.Message)" Red; Say '  Nothing was changed.' Green; Upd-Log "download failed: $($_.Exception.Message)"; Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue; return }
  Say '  All files downloaded and checksums verified.' Green
  # 2. backup
  $bdir = Join-Path $UpdDir ("backup-{0}-b{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $localB)
  New-Item -ItemType Directory -Force $bdir | Out-Null
  $saved = @()
  foreach ($f in $todo) { $src = Join-Path $Root ($f.path -replace '/','\'); if (Test-Path $src) { $d = Join-Path $bdir ($f.path -replace '/','\'); New-Item -ItemType Directory -Force (Split-Path $d) | Out-Null; Copy-Item -LiteralPath $src -Destination $d -Force; $saved += $f.path } }
  foreach ($x in 'version.txt') { $src = Join-Path $Root $x; if ((Test-Path $src) -and ($saved -notcontains $x)) { Copy-Item $src (Join-Path $bdir $x) -Force; $saved += $x } }
  Set-Content (Join-Path $bdir 'files.txt') $saved
  if (Test-Path $Ucfg) { $cn = 'cfg-backup-' + (Split-Path $bdir -Leaf) + '.yaml'; Copy-Item -LiteralPath $Ucfg -Destination (Join-Path $Data $cn) -Force; Set-Content (Join-Path $bdir 'cfg.txt') $cn }
  Say "  Backup saved: $bdir" DarkGray
  # 3. stop node, swap files
  $wasRunning = [bool](Node-Proc)
  if (-not (Stop-For-Update)) { Say '  Could not stop the running node (it was probably started as Administrator). Close it (or run this panel as Administrator) and try again. Nothing was changed.' Red; Upd-Log 'abort: node would not stop'; return }
  $swapped = $false
  try {
    foreach ($f in $todo) {
      $dst = Join-Path $Root ($f.path -replace '/','\'); $srcS = Join-Path $stage ($f.path -replace '/','_')
      New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
      Copy-Item -LiteralPath $srcS -Destination "$dst.new" -Force; Move-Retry "$dst.new" $dst
      if ((File-Sha $dst) -ne $f.sha256) { throw "file $($f.path) does not match after copy" }
    }
    if (@($todo | ? { $_.path -eq 'version.txt' }).Count -eq 0) { Set-Content (Join-Path $Root 'version.txt') ("{0}`r`n{1}" -f $m.build, $m.name) }
    $swapped = $true
  } catch { Say "  SWAP FAILED: $($_.Exception.Message) - rolling back." Red; Upd-Log "swap failed: $($_.Exception.Message)" }
  # 4. restart + verify
  $good = $swapped
  if ($swapped -and $wasRunning) {
    $good = Start-After-Update
    if ($good) { Start-Sleep 20; if (-not (Node-Proc)) { $good = $false } }
    if (-not $good) { Say '  The node did not come back up with the new files - rolling back.' Red; Upd-Log 'node did not start after update' }
  }
  if (-not $good) {
    if (Node-Proc) { Stop-Node }
    Restore-Backup $bdir
    Say '  Old files restored.' Yellow; Upd-Log 'rolled back'
    if ($wasRunning) { if (Start-After-Update) { Say '  Node restarted on the old version. Update failed; nothing lost.' Yellow } else { Say '  Old files are back, but the node did not answer yet - use menu R.' Red } }
    return
  }
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
  Pick-Backups | select -SkipLast 2 | % { Remove-Item (Join-Path $Data ('cfg-backup-' + $_.Name + '.yaml')) -Force -ErrorAction SilentlyContinue; Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  Upd-Log "update to build $($m.build) OK"
  Say "  UPDATED to build $($m.build) ($($m.name))." Green
  Say '  Close this window and start LogosMiner.bat again to use the new panel. (To undo: Update menu > roll back.)' Green
  if ($script:updExit) { exit 0 }
  if (-not $CheckOnly -and -not $Yes) { Read-Host '  Press Enter to close this panel' | Out-Null }
  exit 0
}
function Rollback-Menu([switch]$Yes) {
  Say '  ---- ROLL BACK to the files saved before the last update ----' Cyan
  $b = @(Pick-Backups); if (-not $b.Count) { Say '  No backup found (no update was done on this PC).' Yellow; return }
  $bdir = $b[-1].FullName; Say "  Backup: $($b[-1].Name)" White
  if (-not $Yes) { if ((Read-Host '  Restore these files now? y/N') -ne 'y') { Say '  Cancelled.' Yellow; return } }
  $wasRunning = [bool](Node-Proc)
  if (-not (Stop-For-Update)) { Say '  Could not stop the node. Nothing changed.' Red; return }
  Restore-Backup $bdir; Upd-Log "manual rollback from $($b[-1].Name)"
  Say '  Files restored.' Green
  if ($wasRunning) { if (Start-After-Update) { Say '  Node restarted.' Green } else { Say '  Node did not answer yet - use menu R.' Yellow } }
  Say '  Close this window and start LogosMiner.bat again.' Green
  exit 0
}
function Update-Submenu {
  Say '  ---- UPDATE (experimental) ----' Cyan
  Say '  Experimental: it has been tested but is new. Your data\ folder, keys and settings are never touched, old files are backed up.' Yellow
  MenuItem '1' 'Check for an update and install it' Green
  MenuItem '2' 'Roll back to the files from before the last update' Yellow
  MenuItem '0' 'Back' DarkGray
  switch ((Read-Host '  Choose').Trim()) { '1' { Update-Menu } '2' { Rollback-Menu } default { } }
}
# ===================== end UPDATE =====================

if ($args -contains '--arm') { Arm-Loop; exit }
if ($args -contains '--start') { Start-Node; exit }
if ($args -contains '--status') { Status; exit }
if ($args -contains '--stop') { Stop-Node; exit }
if ($args -contains '--restart') { Stop-Node; Start-Node; exit }
if ($args -contains '--log') { Show-Log; exit }
if ($args -contains '--full') { $c=Load-Cfg; $c.mode='full'; Save-Cfg $c; Start-Node; exit }
if ($args -contains '--mine') { $c=Load-Cfg; $c.mode='mine'; Save-Cfg $c; Start-Node; exit }
function Show-Banner {
  Clear-Host
  Write-Host ''
  Write-Host '   _     ___   ____  ___  ____  ' -NoNewline -ForegroundColor Cyan; Write-Host '  _   _  ___  ____  _____ ' -ForegroundColor Magenta
  Write-Host '  | |   / _ \ / ___|/ _ \/ ___| ' -NoNewline -ForegroundColor Cyan; Write-Host ' | \ | |/ _ \|  _ \| ____|' -ForegroundColor Magenta
  Write-Host '  | |  | | | | |  _| | | \___ \ ' -NoNewline -ForegroundColor Blue; Write-Host ' |  \| | | | | | | |  _|  ' -ForegroundColor Magenta
  Write-Host '  | |__| |_| | |_| | |_| |___) |' -NoNewline -ForegroundColor Blue; Write-Host ' | |\  | |_| | |_| | |___ ' -ForegroundColor DarkMagenta
  Write-Host '  |_____\___/ \____|\___/|____/ ' -NoNewline -ForegroundColor DarkCyan; Write-Host ' |_| \_|\___/|____/|_____|' -ForegroundColor DarkMagenta
  Write-Host '        ' -NoNewline; Write-Host 'for Windows' -NoNewline -ForegroundColor Yellow; Write-Host '  -  Logos testnet node + miner  -  v0.3.4 ' + $BuildName -ForegroundColor DarkGray
  Write-Host ('  ' + ('=' * 58)) -ForegroundColor DarkBlue
}

function MenuItem($k,$t,$col='White') { Write-Host '   [' -NoNewline -ForegroundColor DarkGray; Write-Host $k -NoNewline -ForegroundColor Yellow; Write-Host '] ' -NoNewline -ForegroundColor DarkGray; Write-Host $t -ForegroundColor $col }
if ($args -contains '--balance') { Show-Balance; exit }
if ($args -contains '--mining-start') { Set-Mining $true; exit }
if ($args -contains '--mining-stop') { Set-Mining $false; exit }
if ($args -contains '--update-check') { Update-Menu -CheckOnly; exit }
if ($args -contains '--update') { $script:updExit = $true; Update-Menu -Yes:($args -contains '--yes'); exit }
if ($args -contains '--rollback') { Rollback-Menu -Yes:($args -contains '--yes'); exit }
if ($args -contains '--version') { "build $(Local-Build) ($BuildName)"; exit }
if ($args -contains '--inscribe') { Inscribe-Menu; exit }
if ($args -contains '--send') { Send-Menu; exit }
if ($args -contains '--receive') { Receive-Menu; exit }
$pause = $false
while ($true) {
  $c = Load-Cfg
  if ($pause) { Write-Host ''; Read-Host '  (press Enter to return to the menu)' | Out-Null }
  Show-Banner
  $mc = $(if ($c.mode -eq 'full') {'Green'} else {'Cyan'})
  Write-Host '  Mode: ' -NoNewline -ForegroundColor DarkCyan; Write-Host $(if ($c.mode -eq 'full') {'FULL NODE'} else {'MINE ONLY'}) -NoNewline -ForegroundColor $mc
  Write-Host '   Threads: ' -NoNewline -ForegroundColor DarkCyan; $rt = $(if (Node-Proc) { Run-Threads } else { 0 }); $thTxt = "$($c.threads) of $([Environment]::ProcessorCount) CPU threads$(if ($c.threads_auto) {' (auto)'})"; if ($rt -and $rt -ne [int]$c.threads) { $thTxt += " [node still uses $rt - press R to apply]" }; Write-Host $thTxt -NoNewline -ForegroundColor Magenta
  Write-Host '   Node: ' -NoNewline -ForegroundColor DarkCyan; if (Node-Proc) { Write-Host 'running' -NoNewline -ForegroundColor Green; $lm = Log-Mining; Write-Host '   Mining: ' -NoNewline -ForegroundColor DarkCyan; if (Test-Path $PauseFile) { Write-Host 'paused' -ForegroundColor Yellow } elseif ($lm -eq 'on') { Write-Host 'ON' -ForegroundColor Green } elseif ($lm -eq 'off') { Write-Host 'OFF' -ForegroundColor Yellow } else { Write-Host 'not yet (starts when Online)' -ForegroundColor Yellow } } else { Write-Host 'stopped' -ForegroundColor Red }
  Write-Host ''
  Say '   START' DarkYellow
  MenuItem '1' 'Install full node + start mining   (opens P2P port)' Green
  MenuItem '2' 'Mine only + start                  (outbound only, nothing opened)' Cyan
  Write-Host ''
  Say '   CONTROL' DarkYellow
  MenuItem '3' 'Status'
  MenuItem '4' 'Set mining threads' Magenta
  MenuItem '5' 'Stop mining  (node keeps running)' Yellow
  MenuItem '6' 'Start mining  (switches it on right now)' Green
  MenuItem '7' 'Stop node' Red
  MenuItem 'R' 'Restart node  (applies new thread count; fixes a stuck start)' Yellow
  Write-Host ''
  Say '   TOOLS' DarkYellow
  MenuItem '8' 'Set public address / domain (full node)'
  MenuItem '9' 'Show log tail'
  MenuItem 'C' 'Claim rewards'
  MenuItem 'W' 'Wallet balance' Green
  MenuItem 'S' 'Send coins  (to another Logos key)' Green
  MenuItem 'A' 'Receive  (my address, balance, incoming)' Cyan
  MenuItem 'I' 'Inscribe  (text / image / file on-chain)' Magenta
  MenuItem 'U' 'Update  (experimental)' DarkYellow
  MenuItem 'Q' 'Quit' DarkGray
  Write-Host ''
  $pause = $true
  switch ((Read-Host '  Choose').ToUpper()) {
    '1' { $c.mode='full'; Save-Cfg $c; Say '  Starting full node...' Green; Start-Node }
    '2' { $c.mode='mine'; Save-Cfg $c; Say '  Starting mine-only node...' Cyan; Start-Node }
    '3' { Status }
    '4' {
      $n=[Environment]::ProcessorCount
      Write-Host "  This PC has $n CPU threads ($(Cpu-Cores) cores). Mining speed depends on CPU threads, not on RAM." -ForegroundColor Magenta
      Write-Host "  Currently configured: $($c.threads)$(if (Node-Proc) { ';  the running node uses ' + (Run-Threads) })" -ForegroundColor Magenta
      Write-Host "  Tip: about half ($(Auto-Threads)) keeps the PC usable; all $n makes the node API very slow." -ForegroundColor DarkGray
      $t = Read-Host "  new thread count (1-$n, or 'auto' = $(Auto-Threads))"
      $old = $c.threads
      if ($t -eq 'auto') { $c.threads = [string](Auto-Threads); $c.threads_auto = $true; Save-Cfg $c; $t = $c.threads; $ok = $true }
      elseif ($t -match '^\d+$' -and [int]$t -ge 1 -and [int]$t -le $n) { $c.threads_auto = $false; $c.threads=$t; Save-Cfg $c; $ok = $true } else { $ok = $false }
      if (-not $ok) { Say '  Not changed (type a whole number between 1 and the CPU thread count).' Red }
      else {
        $chk = (Load-Cfg).threads
        Say "  Saved in logos-miner.ini: threads $old -> $chk." Green
        if (Node-Proc) {
          if ((Read-Host '  The running node only reads this at startup. Restart the node now to apply? y/N') -eq 'y') { Stop-Node; Start-Node; Say "  Applied: node restarted with $(Run-Threads) threads." Green }
          else { Say '  Not applied yet. Use menu R later to apply.' Yellow }
        } else { Say '  It will be used the next time you start the node (menu 1 or 2).' Green }
      }
    }
    '5' { Set-Mining $false }
    '6' { Set-Mining $true }
    '7' { Stop-Node }
    'R' { if (Node-Proc) { Say '  Restarting node...' Yellow; Stop-Node }; Start-Node }
    '8' { $c.external_address = Read-Host '  public IP or domain (empty = none)'; Save-Cfg $c; Say '  Saved.' Green }
    '9' { Show-Log }
    'C' { Claim-Rewards }
    'W' { Show-Balance }
    'S' { Send-Menu }
    'A' { Receive-Menu }
    'I' { Inscribe-Menu }
    'U' { Update-Submenu }
    'Q' { exit }
    default { $pause = $false }
  }
}
