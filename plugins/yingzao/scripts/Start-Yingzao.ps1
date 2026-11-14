param([ValidateSet('mcp','settings')][string]$Mode='mcp')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$registry=Join-Path $env:LOCALAPPDATA 'YingzaoPlugin\install.json'
$homePath=Join-Path $env:LOCALAPPDATA 'YingzaoPlugin'
$dataPath=Join-Path $homePath 'data'
if(Test-Path -LiteralPath $registry){
 $saved=Get-Content -LiteralPath $registry -Raw -Encoding UTF8|ConvertFrom-Json
 if($saved.home -and [IO.Path]::IsPathRooted($saved.home)){$homePath=[IO.Path]::GetFullPath($saved.home)}
 if($saved.data_root -and [IO.Path]::IsPathRooted($saved.data_root)){$dataPath=[IO.Path]::GetFullPath($saved.data_root)}
}
$pointer=Join-Path $homePath 'current.json'
if(-not(Test-Path -LiteralPath $pointer)){
 & (Join-Path $PSScriptRoot 'Update-Yingzao.ps1') -HomePath $homePath -DataPath $dataPath
}
$current=Get-Content -LiteralPath $pointer -Raw -Encoding UTF8|ConvertFrom-Json
if($current.path -notmatch '^versions/\d+\.\d+\.\d+$'){throw 'Invalid Yingzao runtime pointer.'}
$runtime=Join-Path $homePath ($current.path+'/runtime/Yingzao.exe')
if(-not(Test-Path -LiteralPath $runtime -PathType Leaf)){throw 'Yingzao runtime missing; use Update-Yingzao.ps1.'}
$env:YINGZAO_PLUGIN_HOME=$homePath
$env:YINGZAO_DATA_ROOT=$dataPath
$verb=if($Mode -eq 'mcp'){'--api-plugin-mcp'}else{'--api-plugin-ui'}
& $runtime $verb $dataPath
exit $LASTEXITCODE
