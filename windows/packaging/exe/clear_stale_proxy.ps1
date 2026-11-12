# Setup runs this after killing the app, which skips the exit path that turns
# the system proxy off. Any FlClashX version sets 127.0.0.1:<port>; a proxy
# there with nothing listening is the dead one and goes back to direct.
$ErrorActionPreference = 'Stop'
$settings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$connections = "$settings\Connections"

function Get-ProxyServer([byte[]]$blob) {
  if ($blob.Length -lt 16) { return $null }
  $length = [BitConverter]::ToInt32($blob, 12)
  if ($length -le 0 -or 16 + $length -gt $blob.Length) { return $null }
  [Text.Encoding]::ASCII.GetString($blob, 16, $length)
}

function Test-Listening([int]$port) {
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    $listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    if (-not ($listeners | Where-Object Port -eq $port)) { return $false }
    Start-Sleep -Milliseconds 100
  }
  $true
}

$key = Get-Item -LiteralPath $connections -ErrorAction SilentlyContinue
if ($null -eq $key) { exit 0 }
$changed = $false
foreach ($name in $key.GetValueNames()) {
  if ($name -eq 'SavedLegacySettings') { continue }
  $blob = $key.GetValue($name)
  if ($blob -isnot [byte[]]) { continue }
  if ((Get-ProxyServer $blob) -notmatch '^127\.0\.0\.1:(\d{1,5})$') { continue }
  $flags = [BitConverter]::ToInt32($blob, 8)
  if (($flags -band 2) -eq 0 -or (Test-Listening ([int]$Matches[1]))) { continue }
  [BitConverter]::GetBytes([int32](($flags -band (-bnot 2)) -bor 1)).CopyTo($blob, 8)
  $counter = ([BitConverter]::ToUInt32($blob, 4) + 1) % 4294967296
  [BitConverter]::GetBytes([uint32]$counter).CopyTo($blob, 4)
  Set-ItemProperty -LiteralPath $connections -Name $name -Value $blob -Type Binary
  if ($name -eq 'DefaultConnectionSettings') {
    Set-ItemProperty -LiteralPath $settings -Name ProxyEnable -Value 0 -Type DWord
  }
  $changed = $true
}
if ($changed) {
  Add-Type -Namespace FlClashX -Name WinInet -MemberDefinition '[DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr handle, int option, IntPtr buffer, int length);'
  [FlClashX.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
  [FlClashX.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}
