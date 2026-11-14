param([Parameter(Mandatory=$true)][string]$HomePath,[Parameter(Mandatory=$true)][string]$DataPath)
$ErrorActionPreference='Stop'
function Save-State($Value){
 $path=Join-Path $HomePath 'bootstrap-state.json';$temp=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
 Move-Item -LiteralPath $temp -Destination $path -Force
}
try {
 Save-State @{state='installing';message='首次安装正在下载并验证运行时；完成后自动加载设置。';pid=$PID}
 & (Join-Path $PSScriptRoot 'Update-Yingzao.ps1') -HomePath $HomePath -DataPath $DataPath
 Save-State @{state='installed';message='运行时已安装，正在连接完整设置。';pid=$PID}
}catch{Save-State @{state='failed';message=$_.Exception.Message;pid=$PID};exit 1}
