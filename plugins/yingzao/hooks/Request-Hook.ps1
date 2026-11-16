$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding=New-Object System.Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding
$inputJson=[Console]::In.ReadToEnd()
try {
 $registry=Join-Path $env:LOCALAPPDATA 'YingzaoPlugin\install.json'
 $install=Get-Content -LiteralPath $registry -Raw -Encoding UTF8|ConvertFrom-Json
 $current=Get-Content -LiteralPath (Join-Path $install.home 'current.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($current.path -notmatch '^versions/\d+\.\d+\.\d+$' -or [version]$current.version -lt [version]'0.7.6'){throw 'Runtime update required'}
 $runtime=Join-Path $install.home ($current.path+'/runtime/Yingzao.exe')
 $inputJson | & $runtime '--api-plugin-hook' $install.data_root
 if($LASTEXITCODE -ne 0){throw 'Hook runtime failed'}
} catch {
 @{systemMessage='映造消息钩子尚不可用；不能认定逐条分析与检索记录已生效。请检查运行时及钩子信任状态。'}|ConvertTo-Json -Compress
}
