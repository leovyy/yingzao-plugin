param([Parameter(Mandatory=$true)][string]$HomePath,[Parameter(Mandatory=$true)][string]$DataPath)
$ErrorActionPreference='Stop'
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$script:manifest=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.codex-plugin\plugin.json') -Raw -Encoding UTF8|ConvertFrom-Json
$script:child=$null;$script:installer=$null;$script:init=$null;$script:ready=$false
$script:capability=@{readTool='plugin_settings_read';updateTool='plugin_settings_update'}
New-Item -ItemType Directory -Path $HomePath -Force|Out-Null
function Emit($Value){[Console]::Out.WriteLine(($Value|ConvertTo-Json -Depth 80 -Compress));[Console]::Out.Flush()}
function Launch-Installer {
 if($script:installer -and -not $script:installer.HasExited){return}
 $args=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Install-Runtime.ps1')+'"'),'-HomePath',('"'+$HomePath+'"'),'-DataPath',('"'+$DataPath+'"'))
 $empty=Join-Path $HomePath 'bootstrap-empty-input.txt';[IO.File]::WriteAllBytes($empty,[byte[]]@())
 $script:installer=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardInput $empty -RedirectStandardOutput (Join-Path $HomePath 'bootstrap-install.log') -RedirectStandardError (Join-Path $HomePath 'bootstrap-install.error.log')
}
function Runtime-Path {
 try {
  $pointer=Get-Content -LiteralPath (Join-Path $HomePath 'current.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if([version]$pointer.version -lt [version]$script:manifest.version -or $pointer.path -notmatch '^versions/\d+\.\d+\.\d+$'){return $null}
  $exe=Join-Path $HomePath ($pointer.path+'/runtime/Yingzao.exe')
  if(Test-Path -LiteralPath $exe -PathType Leaf){return $exe}
 }catch{}
 return $null
}
function Child-Rpc($Message){
 $script:child.StandardInput.WriteLine(($Message|ConvertTo-Json -Depth 80 -Compress));$script:child.StandardInput.Flush()
 if(-not $Message.Contains('id')){return $null}
 $deadline=[DateTime]::UtcNow.AddSeconds(90)
 while([DateTime]::UtcNow -lt $deadline){
  $read=$script:child.StandardOutput.ReadLineAsync()
  if(-not $read.Wait([Math]::Max(1,[int]($deadline-[DateTime]::UtcNow).TotalMilliseconds))){throw 'Yingzao runtime response timed out; original request was not replayed.'}
  $line=$read.Result;if($null -eq $line){throw 'Yingzao runtime closed its connection.'}
  $value=$line|ConvertFrom-Json
  if($value.PSObject.Properties.Name -contains 'id' -and $value.id -eq $Message.id){return $value}
  Emit $value
 }
 throw 'Yingzao response missing.'
}
function Connect-Runtime {
 if($script:ready -or -not $script:init){return}
 $exe=Runtime-Path;if(-not $exe){return}
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=$exe;$start.Arguments='--api-plugin-mcp "'+$DataPath+'"';$start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true
 # Windows PowerShell 5.1 uses .NET Framework: stdin inherits Console.InputEncoding.
 $start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
 $start.EnvironmentVariables['YINGZAO_PLUGIN_HOME']=$HomePath;$start.EnvironmentVariables['YINGZAO_DATA_ROOT']=$DataPath
 $script:child=New-Object Diagnostics.Process;$script:child.StartInfo=$start;$null=$script:child.Start()
 $response=Child-Rpc @{jsonrpc='2.0';id=('setup-init-'+[Guid]::NewGuid().ToString('N'));method='initialize';params=$script:init}
 if($response.PSObject.Properties.Name -contains 'error'){throw 'Yingzao initialization failed.'}
 $null=Child-Rpc @{jsonrpc='2.0';method='notifications/initialized'}
 $script:ready=$true
 Emit @{jsonrpc='2.0';method='notifications/tools/list_changed'}
}
function Setup-Settings {
 $message='首次安装正在准备运行时；下载完成后自动加载启用映造、内部API和完整设置。'
 try{$state=Get-Content -LiteralPath (Join-Path $HomePath 'bootstrap-state.json') -Raw -Encoding UTF8|ConvertFrom-Json;if($state.message){$message=$state.message}}catch{}
 return @{schema=@{type='object';properties=@{}};values=@{};layout=@(@{kind='group';title='映造插件 · '+$message;items=@(@{kind='tool';tool='plugin_setup_retry'})})}
}
function Setup-Tools {
 $input=@{type='object';properties=@{};additionalProperties=$false}
 $catalog=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'tool-catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($catalog.schema -ne 1 -or @($catalog.tools).Count -ne 30){throw 'Plugin tool metadata invalid.'}
 $retry=@{name='plugin_setup_retry';title='重试安装映造运行时';description='只重试签名运行时安装，不调用模型。';inputSchema=@{type='object';properties=@{}};_meta=@{ui=@{visibility=@('app')}}}
 return @($catalog.tools)+@($retry)
}
Launch-Installer
try {
 $inputReader=New-Object IO.StreamReader([Console]::OpenStandardInput(),[Text.Encoding]::UTF8)
 $pending=$inputReader.ReadLineAsync()
 while($true){
  if(-not $pending.Wait(100)){Connect-Runtime;continue}
  $line=$pending.Result;if($null -eq $line){break};$pending=$inputReader.ReadLineAsync()
  if($line.Length -gt 2097152){throw 'Request exceeds size limit.'}
  $request=$line|ConvertFrom-Json
  if($request.method -like 'notifications/*'){continue}
  $id=$request.id
  try {
   $method=$request.method;$params=$request.params
   if($method -eq 'initialize'){
    $script:init=$params
    $result=@{protocolVersion='2025-11-25';serverInfo=@{name='yingzao-production';version=$script:manifest.version};capabilities=@{tools=@{listChanged=$true};resources=@{};experimental=@{'openai/settings'=$script:capability};extensions=@{'openai/settings'=$script:capability}};instructions='映造首次安装异步下载签名运行时。安装期间只查看状态，禁止调用模型或改用其他收费服务。就绪后用plugin_status与plugin_workflow开始原任务。'}
   }elseif($method -eq 'server/discover'){
    $result=@{resultType='complete';supportedVersions=@('2025-11-25','2026-07-28');capabilities=@{tools=@{listChanged=$true};resources=@{};extensions=@{'openai/settings'=$script:capability}};_meta=@{'io.modelcontextprotocol/serverInfo'=@{name='yingzao-production';version=$script:manifest.version}}}
   }else{
    Connect-Runtime
    if($script:ready -and $method -eq 'tools/call' -and $params.name -eq 'plugin_setup_retry'){Emit @{jsonrpc='2.0';id=$id;result=@{content=@(@{type='text';text='签名运行时已就绪，无需重试。'});structuredContent=@{state='ready';model_calls=0}}};continue}
    if($script:ready){$forward=@{jsonrpc='2.0';id=$id;method=$method};if($null -ne $params){$forward.params=$params};Emit (Child-Rpc $forward);continue}
    switch($method){
     'ping' {$result=@{}}
     'tools/list' {$result=@{tools=@(Setup-Tools)}}
     'resources/list' {$result=@{resources=@()}}
     'tools/call' {
      if($params.name -eq 'plugin_settings_read'){$data=Setup-Settings}
      elseif($params.name -eq 'plugin_setup_retry'){Launch-Installer;$data=@{state='installing';message='正在核对并安装签名运行时；已有下载不会重复启动。';model_calls=0}}
      elseif($params.name -eq 'plugin_status'){$data=@{state='installing';runtime_ready=$false;model_calls=0;message=(Setup-Settings).layout[0].title}}
      else{throw '运行时尚未安装，未执行制作或修改设置。'}
      $result=@{content=@(@{type='text';text=($data|ConvertTo-Json -Depth 30 -Compress)});structuredContent=$data}
     }
     default {throw 'Runtime preparation is in progress.'}
    }
   }
   Emit @{jsonrpc='2.0';id=$id;result=$result}
  }catch{Emit @{jsonrpc='2.0';id=$id;error=@{code=-32603;message=$_.Exception.Message}}}
 }
}finally{if($script:child){$script:child.StandardInput.Close();if(-not $script:child.WaitForExit(5000)){$script:child.Kill()};$script:child.Dispose()}}
