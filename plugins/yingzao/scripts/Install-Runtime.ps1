param([Parameter(Mandatory=$true)][string]$HomePath,[Parameter(Mandatory=$true)][string]$DataPath)
$ErrorActionPreference='Stop'
function Save-State($Value){
 $path=Join-Path $HomePath 'bootstrap-state.json';$temp=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
 Move-Item -LiteralPath $temp -Destination $path -Force
}
# Each MCP client can start a worker. Only the owner downloads and writes state.
$guard=[IO.File]::Open((Join-Path $HomePath 'bootstrap-worker.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
try {
 try{$guard.Lock(0,1)}catch [IO.IOException]{return}
 $pointer=Join-Path $HomePath 'current.json'
 if(Test-Path -LiteralPath $pointer){
  $current=Get-Content -LiteralPath $pointer -Raw -Encoding UTF8|ConvertFrom-Json
  $manifest=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.codex-plugin/plugin.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if([version]$current.version -ge [version]$manifest.version -and $current.path -match '^versions/\d+\.\d+\.\d+$' -and (Test-Path -LiteralPath (Join-Path $HomePath ($current.path+'/runtime/Yingzao.exe')) -PathType Leaf)){
   Save-State @{state='installed';message='运行时已安装，正在连接完整设置。';pid=$PID};return
  }
 }
 Save-State @{state='installing';message='首次安装正在下载并验证运行时；完成后自动加载设置。';pid=$PID}
 & (Join-Path $PSScriptRoot 'Update-Yingzao.ps1') -HomePath $HomePath -DataPath $DataPath
 Save-State @{state='installed';message='运行时已安装，正在连接完整设置。';pid=$PID}
}catch{Save-State @{state='failed';message=$_.Exception.Message;pid=$PID};exit 1}finally{$guard.Dispose()}
