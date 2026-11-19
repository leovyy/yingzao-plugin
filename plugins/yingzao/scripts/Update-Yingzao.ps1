param([string]$HomePath,[string]$DataPath,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$repository='leovyy/yingzao-plugin'
$channel='https://github.com/'+$repository+'/releases/latest/download/'
if(-not $HomePath){$HomePath=Join-Path $env:LOCALAPPDATA 'YingzaoPlugin'}
$HomePath=[IO.Path]::GetFullPath($HomePath)
if(-not $DataPath){$DataPath=Join-Path $HomePath 'data'}
$DataPath=[IO.Path]::GetFullPath($DataPath)
function Get-ReleaseAssets([string]$Selector){
 $client=New-Object Net.WebClient
 $client.Headers['User-Agent']='Yingzao-Plugin-Updater'
 try {
  $release=$client.DownloadString(('https://api.github.com/repos/'+$repository+'/releases/'+$Selector))|ConvertFrom-Json
  if($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^plugin-v\d+\.\d+\.\d+$'){throw 'Expected a stable plugin release.'}
  return $release
 }finally{$client.Dispose()}
}
function Get-AssetEndpoint($Release,[string]$Name){
 $matchesForName=@($Release.assets|Where-Object {$_.name -ceq $Name -and $_.state -eq 'uploaded'})
 if($matchesForName.Count -ne 1 -or [string]$matchesForName[0].id -notmatch '^[1-9][0-9]*$'){throw 'Official release asset missing.'}
 return ('https://api.github.com/repos/'+$repository+'/releases/assets/'+$matchesForName[0].id)
}
function Hash-File([string]$Path){
 $stream=[IO.File]::OpenRead($Path);$hash=[Security.Cryptography.SHA256]::Create()
 try {return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$hash.Dispose()}
}
function Write-Atomic([string]$Path,$Value){
 $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
 Move-Item -LiteralPath $temp -Destination $Path -Force
}
New-Item -ItemType Directory -Path $HomePath -Force|Out-Null
$lockPath=Join-Path $HomePath 'update.lock'
$handle=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
$locked=$false;$stage=$null;$archive=$null
try {
 if($handle.Length -eq 0){$handle.WriteByte(0);$handle.Flush()}
 $handle.Lock(0,1);$locked=$true
 $client=New-Object Net.WebClient
 $client.Headers['User-Agent']='Yingzao-Plugin-Updater'
 $fallbackRelease=$null
 try {$raw=$client.DownloadData($channel+'update.json');$signature=$client.DownloadString($channel+'update.sig')}
 catch [Net.WebException] {
  $fallbackRelease=Get-ReleaseAssets 'latest'
  $client.Headers['Accept']='application/octet-stream'
  $raw=$client.DownloadData((Get-AssetEndpoint $fallbackRelease 'update.json'))
  $signature=$client.DownloadString((Get-AssetEndpoint $fallbackRelease 'update.sig'))
 }
 finally {$client.Dispose()}
 if($raw.Length -gt 65536 -or $signature.Length -gt 4096){throw 'Update metadata exceeds size limit.'}
 $rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
 try {
  $rsa.FromXmlString([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'update-public.xml')))
  if(-not $rsa.VerifyData($raw,'SHA256',[Convert]::FromBase64String($signature))){throw 'Update signature validation failed.'}
 }finally{$rsa.Dispose()}
 $asset=[Text.Encoding]::UTF8.GetString($raw)|ConvertFrom-Json
 if($asset.schema -ne 1 -or $asset.repository -ne $repository -or $asset.platform -ne 'windows-x64' -or $asset.version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid plugin release metadata.'}
 $expected='https://github.com/'+$repository+'/releases/download/plugin-v'+$asset.version+'/yingzao-plugin-'+$asset.version+'-windows-x64.zip'
 if($asset.url -cne $expected -or $asset.sha256 -notmatch '^[a-f0-9]{64}$' -or $asset.bytes -le 0 -or $asset.bytes -gt 536870912){throw 'Invalid release package metadata.'}
 if($CheckOnly){[Console]::Out.WriteLine(($asset|ConvertTo-Json -Compress));return}
 $pointer=Join-Path $HomePath 'current.json'
 $current=$null
 if(Test-Path -LiteralPath $pointer){$current=Get-Content -LiteralPath $pointer -Raw -Encoding UTF8|ConvertFrom-Json}
 if($current -and $current.version -eq $asset.version){[Console]::Error.WriteLine('Yingzao '+$asset.version+' is installed.');return}
 if($current -and [version]$asset.version -lt [version]$current.version){throw 'Normal updates cannot downgrade; use explicit rollback.'}
 $versions=Join-Path $HomePath 'versions';New-Item -ItemType Directory -Path $versions -Force|Out-Null
 $stage=Join-Path $versions ('.staging-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $stage|Out-Null
 $archive=Join-Path $HomePath ('.download-'+[Guid]::NewGuid().ToString('N')+'.zip')
 $client=New-Object Net.WebClient;$client.Headers['User-Agent']='Yingzao-Plugin-Updater'
 try {
  if(-not $fallbackRelease){
   try {$client.DownloadFile($asset.url,$archive)}
   catch [Net.WebException] {$fallbackRelease=Get-ReleaseAssets ('tags/plugin-v'+$asset.version)}
  }
  if($fallbackRelease){
   if($fallbackRelease.tag_name -cne ('plugin-v'+$asset.version)){throw 'Signed metadata and release tag differ.'}
   $client.Headers['Accept']='application/octet-stream'
   $client.DownloadFile((Get-AssetEndpoint $fallbackRelease ([IO.Path]::GetFileName($expected))),$archive)
  }
 }finally{$client.Dispose()}
 if((Get-Item -LiteralPath $archive).Length -ne $asset.bytes -or (Hash-File $archive) -ne $asset.sha256){throw 'Package size or SHA256 mismatch.'}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($archive)
 try {
  $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $expanded=[long]0
  if($zip.Entries.Count -gt 15000){throw 'Too many archive entries.'}
  foreach($entry in $zip.Entries){
   $name=$entry.FullName.TrimEnd('/');$parts=$name.Split('/')
   if(-not $name -or $name.Contains('\') -or $name.Contains(':') -or -not $seen.Add($name)){throw 'Unsafe or duplicate archive path.'}
   foreach($part in $parts){if(-not $part -or $part -eq '.' -or $part -eq '..' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$'){throw 'Unsafe archive component.'}}
   $expanded+=$entry.Length
   if($expanded -gt 2147483648 -or (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960){throw 'Archive link or expanded size invalid.'}
   $resolved=[IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
   if(-not $resolved.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Archive escapes staging directory.'}
  }
  foreach($entry in $zip.Entries){
   $dest=Join-Path $stage $entry.FullName
   if($entry.FullName.EndsWith('/')){New-Item -ItemType Directory -Path $dest -Force|Out-Null;continue}
   New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($dest)) -Force|Out-Null
   [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$dest,$false)
  }
 }finally{$zip.Dispose()}
 $report=Get-Content -LiteralPath (Join-Path $stage 'BUNDLE_RESULT.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($report.schema -ne 1){throw 'Invalid file manifest.'}
 $actual=@(Get-ChildItem -LiteralPath $stage -Recurse -File|Where-Object {$_.Name -ne 'BUNDLE_RESULT.json'})
 if($actual.Count -ne $report.files.Count){throw 'Manifest file count mismatch.'}
 foreach($row in $report.files){
  $file=[IO.Path]::GetFullPath((Join-Path $stage $row.file))
  if(-not $file.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-Item -LiteralPath $file).Length -ne $row.bytes -or (Hash-File $file) -ne $row.sha256){throw 'Manifest path or hash mismatch.'}
 }
 $exe=Join-Path $stage 'runtime\Yingzao.exe'
 # A background installation must never inherit the host MCP input pipe.
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=$exe;$start.Arguments='--runtime-self-check';$start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
 $probe=New-Object Diagnostics.Process;$probe.StartInfo=$start
 try {
  $null=$probe.Start();$probe.StandardInput.Close();$output=$probe.StandardOutput.ReadToEndAsync()
  if(-not $probe.WaitForExit(30000)){$probe.Kill();throw 'Runtime self-check timed out; previous version retained.'}
  if($probe.ExitCode -ne 0 -or ($output.Result|ConvertFrom-Json).version -ne $asset.version){throw 'Runtime self-check failed; previous version retained.'}
 }finally{$probe.Dispose()}
 $destination=Join-Path $versions $asset.version
 if(Test-Path -LiteralPath $destination){throw 'Version directory already exists; verify it before retrying.'}
 Write-Atomic (Join-Path $stage 'installed-release.json') $asset
 Move-Item -LiteralPath $stage -Destination $destination;$stage=$null
 if($current){$current.PSObject.Properties.Remove('previous')}
 Write-Atomic $pointer @{version=$asset.version;path=('versions/'+$asset.version);previous=$current;changed_at=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
 $registryRoot=Join-Path $env:LOCALAPPDATA 'YingzaoPlugin';New-Item -ItemType Directory -Path $registryRoot -Force|Out-Null
 Write-Atomic (Join-Path $registryRoot 'install.json') @{home=$HomePath;data_root=$DataPath}
 [Console]::Error.WriteLine('Installed Yingzao '+$asset.version+'. Personal data retained at '+$DataPath)
}finally{
 if($archive -and (Test-Path -LiteralPath $archive)){Remove-Item -LiteralPath $archive -Force}
 if($stage -and (Test-Path -LiteralPath $stage)){
  $resolved=[IO.Path]::GetFullPath($stage);$expectedRoot=[IO.Path]::GetFullPath((Join-Path $HomePath 'versions'))+'\'
  if($resolved.StartsWith($expectedRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('.staging-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
 }
 if($locked){$handle.Unlock(0,1)};$handle.Dispose()
}
