#requires -Version 5.1
[CmdletBinding()]param([switch]$SelfTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appRoot=Split-Path $PSScriptRoot -Parent
$script:packageVersion=(Get-Content -LiteralPath (Join-Path $script:appRoot 'package.json') -Raw | ConvertFrom-Json).version
$script:controller=Join-Path $PSScriptRoot 'controller.mjs'
. (Join-Path $PSScriptRoot 'Runtime.ps1')
$script:node=Resolve-ManagerNode $script:appRoot
$script:manager=Join-Path $env:LOCALAPPDATA 'Codex\wechat-manager'
$script:jobsDir=Join-Path $script:manager 'jobs'
[void][IO.Directory]::CreateDirectory($script:jobsDir)
$script:jobs=[Collections.ArrayList]::new()
$script:setupRequested=$false;$script:setupShown=$false;$script:setupState=$null;$script:setupDialog=$null
$script:snapshotLoaded=$false;$script:addAfterSetup=$false;$script:usageState=$null;$script:lastUsage=[datetime]::MinValue
$script:setupVerifyRequested=$false
$script:updateState=$null;$script:downloadState=$null;$script:downloadProgress=$null;$script:updateDialog=$null;$script:installPending=$false
$script:rows=@();$script:selection='';$script:lastRefresh=[datetime]::MinValue;$script:catalog=@();$script:modelsRequested=$false;$script:bindingModel=$false;$script:bindingSelection=$false;$script:currentPage='overview'
$script:errors=@{
 INSTANCE_REGISTRY_AMBIGUOUS='检测到多份实例登记目录，已暂停自动选择。请在Codex中检查并指定原有实例目录，勿重新扫码覆盖。'
 INSTANCE_REGISTRY_UNREADABLE='无法读取本机实例登记目录，请检查当前Windows用户及目录访问权限。'
 DESKTOP_CONNECTION_UNREADABLE='无法读取原有客户端连接，请在当前Codex中重新初始化连接。'
 CLIENT_CONNECTION_REQUIRED='请先点击“首次使用 / 连接客户端”，在已登录的Codex中完成连接初始化。'
 INSTANCE_BUSY='该实例有工作、附件或聊天正在处理，请稍后再保存权限或重启。'
 WECHAT_LOGIN_REQUIRED='尚未绑定微信，请点“扫码连接”。'
 CODEX_NOT_FOUND='未找到 Codex 运行程序，请在 Codex 客户端中运行本包的 initialize.ps1。'
 CODEX_PATH_REQUIRED='请先在 Codex 客户端中运行 initialize.ps1，保存客户端连接。'
 BRIDGE_UNAVAILABLE='主实例未运行，请先启动主实例，然后再打开聊天。'
 CHAT_NOT_READY='尚未建立工作聊天，请先从微信发送一个工作安排。'
 PRIMARY_OWNER_REQUIRED='主用户始终拥有完整权限，不能降级；其他用户不能设为主用户。'
 DIFFERENT_OWNER_REQUIRES_NEW_DATA_DIRECTORY='此实例已绑定其他微信，请为新用户单独新增实例。'
 LOCAL_OPERATION_FAILED='本地操作未完成，请检查 Node 24、Codex 客户端及联网状态。'
 DESKTOP_CONNECTION_UNAVAILABLE='客户端连接不可用，请在当前 Codex 中重新运行 initialize.ps1。'
 DESKTOP_ACTION_REJECTED='客户端未接受打开聊天请求，请在 Codex 中重新初始化连接。'
 DESKTOP_ACTION_UNCONFIRMED='打开聊天结果尚未确认，请查看客户端。'
 INSTANCE_OPERATION_FAILED='服务操作未完成，请检查客户端连接、登录或运行状态。'
 SERVICE_TIMEOUT='等待服务切换超时，请刷新并核对状态，勿重复操作。'
 QR_EXPIRED='二维码已过期，请重新点击“扫码连接”。'
 CHILD_START_FAILED='无法启动后台命令，请检查依赖和安装目录。'
 MODEL_NOT_AVAILABLE='所选模型已不在可用列表，请刷新模型后重新选择。'
 EFFORT_NOT_AVAILABLE='该模型不支持所选强度，请从实际可用强度中选择。'
 MODEL_LIST_EMPTY='客户端未返回可用模型，请检查账号和提供商配置。'
 CODEX_PROCESS_FAILED='客户端程序路径已失效，请在当前 Codex 中重新运行 initialize.ps1。'
 INVALID_PERSONA='请填写有效名称（60字内）和人设描述（8000字内）。'
 PERSONA_IMAGE_LIMIT='最多允许4张参考图，请移除多余图片。'
 PERSONA_IMAGE_INVALID='参考图无效或超过10MiB，请选择有效的PNG、JPEG或WebP文件。'
 PERSONA_PATH_REJECTED='参考图或保存目录不在允许范围，请检查目录链接。'
 PERSONA_CONFIG_INVALID='此实例人设配置无效，请检查本机配置后重试。'
 UPDATE_NETWORK_FAILED='检测更新失败，请检查联网后重新检测。'
 UPDATE_DOWNLOAD_FAILED='安装包下载失败，请检查联网并重新下载。'
 UPDATE_RATE_LIMITED='GitHub暂时限制请求，请稍后再检测更新。'
 UPDATE_RELEASE_INVALID='GitHub发行信息无效，本次不会下载或安装。'
 UPDATE_ASSET_MISSING='新版本尚未提供唯一可用的Windows安装包，请稍后再检测。'
 UPDATE_ASSET_INVALID='安装包大小或SHA-256信息不完整，本次不会安装。'
 UPDATE_URL_REJECTED='下载地址不属于本软件的可信GitHub发行地址，已停止更新。'
 UPDATE_HASH_MISMATCH='安装包校验失败，请重新下载；本次没有运行安装程序。'
 UPDATE_SIZE_MISMATCH='安装包长度与发行记录不符，请重新下载。'
 UPDATE_PATH_REJECTED='更新文件目录存在异常链接，请检查本机下载目录后重试。'
 UPDATE_CHANGED_RECHECK='发行版本已变化或当前没有可安装更新，请重新检测。'
 UPDATE_INSTALLER_ONLY='当前为源码或便携目录，请打开下载目录，在独立目录安装。'
 UPDATE_HANDOFF_FAILED='无法准备安装，管理窗口保持打开；已停止的服务将尝试恢复。'
 UPDATE_PROCESS_UNVERIFIED='无法核对本安装目录的服务进程，请稍后重试，或手动停止服务再更新。'
}
[xml]$xaml=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Manager.xaml') -Raw -Encoding UTF8
$script:window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$script:window.MinHeight=[Math]::Min(700,[Windows.SystemParameters]::WorkArea.Height-24)
$script:window.Height=[Math]::Min(900,[Windows.SystemParameters]::WorkArea.Height-16)
$script:window.MinWidth=[Math]::Min(1020,[Windows.SystemParameters]::WorkArea.Width-24)
$script:window.Width=[Math]::Min(1320,[Windows.SystemParameters]::WorkArea.Width-16)
if($env:CLAWBOT_MANAGER_WINDOW_SUFFIX){$script:window.Title=$script:window.Title+' · '+$env:CLAWBOT_MANAGER_WINDOW_SUFFIX}
$script:ui=@{};foreach($name in @('Refresh','Add','Summary','Instances','Detail','Workspace','Chat','Connect','Start','Stop','Restart','OpenChat','OpenFolder','Role','Images','Files','Projects','Save','Message','Model','Effort','RefreshModels','SaveModel','ModelInfo','Persona','PersonaInfo','OpenCodex','Setup','Update','UsageBucket','UsageHint','RefreshUsage','FiveUsage','FiveProgress','FiveReset','WeekUsage','WeekProgress','WeekReset','PageScroller','PageTitle','PageSubtitle','InstancePicker','SelectionState','PageOverview','PageService','PagePermissions','PageModels','PageUpdates','NavOverview','NavService','NavPermissions','NavModels','NavUpdates','StatInstances','StatRunning','StatPending','OverviewEmpty','SidebarSummary','ServiceContext','PermissionContext','ModelContext','CurrentVersion','VersionLabel','InstanceScope','InstanceCount','ManageAll','ViewServices','ServiceHealth','ServiceBadge','ServiceGlyph','ConnectionDot','FiveCaption','FiveUsed','WeekCaption','WeekUsed')){$script:ui[$name]=$script:window.FindName($name);if(-not $script:ui[$name]){throw ('UI_CONTROL_MISSING: '+$name)}}
$script:ui.VersionLabel.Text='v'+$script:packageVersion
$script:ui.CurrentVersion.Text='当前源码版本 v'+$script:packageVersion+'。更新只提供正式版安装包，源码版本不自动覆盖。'
$iconPath=Join-Path $script:appRoot 'assets\clawbot.ico'
if(Test-Path -LiteralPath $iconPath){$script:window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$iconPath)}
. (Join-Path $PSScriptRoot 'Dialogs.ps1')
. (Join-Path $PSScriptRoot 'Dashboard.ps1')
function Say([string]$text,[bool]$failed=$false){$script:ui.Message.Text=$text;$script:ui.Message.Foreground=if($failed){'#B54559'}else{'#58677E'}}
function Selected {if($script:ui.InstancePicker.SelectedItem){return $script:ui.InstancePicker.SelectedItem.Raw};return $null}
function Show-Page([string]$page){
 if($page -eq 'usage'){$page='overview'}
 $meta=@{
  overview=@{title='首页';subtitle='查看实例运行状态和账号额度'}
  service=@{title='实例与服务';subtitle='管理当前实例的连接、运行和工作聊天'}
  models=@{title='模型与人设';subtitle='为每个实例设置模型、推理强度与角色形象'}
  permissions=@{title='权限与能力';subtitle='按实例设置角色和可用功能'}
  updates=@{title='软件更新';subtitle='检查正式发行、下载并核对安装包'}
 }
 if(-not $meta.ContainsKey($page)){return}
 $script:currentPage=$page
 foreach($pair in @(@('overview','PageOverview'),@('service','PageService'),@('permissions','PagePermissions'),@('models','PageModels'),@('updates','PageUpdates'))){$script:ui[$pair[1]].Visibility=if($pair[0] -eq $page){'Visible'}else{'Collapsed'}}
 $script:ui.PageTitle.Text=$meta[$page].title;$script:ui.PageSubtitle.Text=$meta[$page].subtitle
 foreach($pair in @(@('overview','NavOverview'),@('service','NavService'),@('permissions','NavPermissions'),@('models','NavModels'),@('updates','NavUpdates'))){$script:ui[$pair[1]].IsChecked=$pair[0] -eq $page}
 $script:ui.InstanceScope.Visibility=if($page -in @('service','permissions','models')){'Visible'}else{'Collapsed'}
 Update-Selection
 $script:ui.PageScroller.ScrollToTop()
}
function Select-Instance([string]$name){
 $item=$script:ui.Instances.Items|Where-Object {$_.Raw.name -eq $name}|Select-Object -First 1
 if(-not $item){Say '这个实例已不在当前列表中，请刷新后重试。' $true;return $false}
 $script:bindingSelection=$true
 try{$script:ui.Instances.SelectedItem=$item;$script:ui.InstancePicker.SelectedItem=$item}finally{$script:bindingSelection=$false}
 Update-Selection;return $true
}
function New-InstanceMenu([string]$name){
 $menu=[Windows.Controls.ContextMenu]::new();$menu.Tag=$name
 foreach($pair in @(@('查看近期聊天','chat'),@('在 Codex 中打开','open-chat'),@('管理此实例','service'),@('模型与人设','models'),@('权限与能力','permissions'),@('打开工作目录','open-workspace'))){
  $item=[Windows.Controls.MenuItem]::new();$item.Header=$pair[0];$item.Tag=[pscustomobject]@{Name=$name;Action=$pair[1]}
  $item.Add_Click({
   if(-not (Select-Instance ([string]$this.Tag.Name))){return}
   switch([string]$this.Tag.Action){
    'chat' {Show-Chat}
    'open-chat' {[void](Begin-JobCommand @{action='open-chat';name=(Selected).name})}
    'open-workspace' {[void](Begin-JobCommand @{action='open-workspace';name=(Selected).name})}
    default {Show-Page ([string]$this.Tag.Action)}
   }
  });[void]$menu.Items.Add($item)
 }
 return $menu
}
function Show-InstanceMenu($button,[string]$name){
 $menu=New-InstanceMenu $name
 $button.ContextMenu=$menu;$menu.PlacementTarget=$button;$menu.Placement='Bottom';$menu.IsOpen=$true
}
function Update-ConnectionSummary {
 $ready=[bool]$script:setupState.ready
 $script:ui.SidebarSummary.Text=if($ready){'客户端已连接'}elseif($script:setupState){'客户端尚未连接'}else{'正在检测客户端…'}
 $script:ui.ConnectionDot.Fill=if($ready){'#28AA68'}else{'#A0A3B5'}
}
function Begin-JobCommand($request){
 $readOnly=$request.action -in @('snapshot','history','models','setup-status','usage','check-update')
 if($readOnly -and @($script:jobs|Where-Object {$_.Name -eq $request.name -and $_.Action -eq $request.action}).Count){return $false}
 if(-not $readOnly -and @($script:jobs|Where-Object {$_.Name -eq $request.name -and $_.Action -notin @('snapshot','history','models','setup-status','usage','check-update')}).Count){Say '此实例的上一项操作仍在进行，请等待完成。';return $false}
 $file=Join-Path $script:jobsDir (([Guid]::NewGuid().ToString('N'))+'.json')
 [IO.File]::WriteAllText($file,($request|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$script:node
 $start.Arguments='"'+$script:controller+'" --request "'+$file+'"'
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
 $proc=[Diagnostics.Process]::Start($start)
 $job=[pscustomobject]@{Action=$request.action;Name=$request.name;ProgressFile=($file+'.progress.json');UserFeedback=[bool]$request.user_feedback;Process=$proc;Output=$proc.StandardOutput.ReadToEndAsync();Error=$proc.StandardError.ReadToEndAsync();Started=[datetime]::UtcNow;QrWindow=$null;QrImage=$null;QrHint=$null;QrStamp=[datetime]::MinValue}
 [void]$script:jobs.Add($job)
 if(-not $readOnly){Say ('正在执行：'+$request.action+' · '+$request.name+'。窗口可以继续使用。')}
 if($request.action -eq 'connect'){Show-Qr $job}
 return $true
}
function Show-Qr($job){
 [xml]$qrXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="微信扫码连接" Width="450" Height="560" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="#F8F9FC" FontFamily="Microsoft YaHei UI"><StackPanel Margin="24"><TextBlock Text="请使用该用户自己的微信扫码" FontSize="18" FontWeight="SemiBold" Foreground="#242636" TextAlignment="Center"/><Image Name="QrImage" Width="350" Height="350" Margin="0,15,0,10"/><TextBlock Name="QrHint" Text="正在准备二维码…" TextAlignment="Center" TextWrapping="Wrap" Foreground="#526174"/><TextBlock Text="关闭此窗口不会取消等待；二维码约5分钟后过期。" TextAlignment="Center" TextWrapping="Wrap" FontSize="11" Margin="0,14,0,0" Foreground="#718096"/></StackPanel></Window>
'@
 $qrWindow=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($qrXaml));$qrWindow.Owner=$script:window
 $job.QrWindow=$qrWindow;$job.QrImage=$qrWindow.FindName('QrImage');$job.QrHint=$qrWindow.FindName('QrHint');$qrWindow.Show()
}
function Update-Qr($job){
 if(-not $job.QrWindow -or -not $job.QrWindow.IsVisible){return}
 $file=Join-Path $script:manager ('qr\'+$job.Name+'.png')
 if(Test-Path -LiteralPath $file){$info=Get-Item -LiteralPath $file
  if($info.LastWriteTimeUtc -ge $job.Started.AddSeconds(-1) -and $info.LastWriteTimeUtc -gt $job.QrStamp){
   try{$bitmap=[Windows.Media.Imaging.BitmapImage]::new();$bitmap.BeginInit();$bitmap.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad;$bitmap.UriSource=[uri]$file;$bitmap.EndInit();$bitmap.Freeze();$job.QrImage.Source=$bitmap;$job.QrStamp=$info.LastWriteTimeUtc}catch{}
  }
 }
 $left=[Math]::Max(0,300-[int]([datetime]::UtcNow-$job.Started).TotalSeconds)
 $job.QrHint.Text=if($job.QrImage.Source){'扫码后在手机确认，成功后服务会自动启动。剩余约 '+$left+' 秒。'}else{'正在准备二维码，请稍候…'}
}
function Enable-Capabilities {
 $row=Selected;$roleTag=if($script:ui.Role.SelectedItem){$script:ui.Role.SelectedItem.Tag}else{''};$standard=$roleTag -eq 'standard'
 foreach($name in @('Images','Files','Projects')){$script:ui[$name].IsEnabled=!!($row -and $row.name -ne 'primary' -and $standard);if(-not $standard){$script:ui[$name].IsChecked=$true}}
}
function Update-Efforts($preferred) {
 $model=$script:ui.Model.SelectedItem
 if(-not $model){$script:ui.Effort.ItemsSource=@();$script:ui.SaveModel.IsEnabled=$false;return}
 $values=@($model.efforts|ForEach-Object {$_.value})
 $script:ui.Effort.ItemsSource=$values;$script:ui.Effort.IsEnabled=$values.Count -gt 0
 if($values -contains $preferred){$script:ui.Effort.SelectedItem=$preferred}elseif($values -contains $model.default_effort){$script:ui.Effort.SelectedItem=$model.default_effort}elseif($values.Count){$script:ui.Effort.SelectedIndex=0}
 $script:ui.SaveModel.IsEnabled=!!(Selected)
}
function Load-ModelChoice($row) {
 if(-not $row){$script:ui.SaveModel.IsEnabled=$false;return}
 if(-not $script:catalog.Count){
  $fallback=[pscustomobject]@{display_name=$row.model;model=$row.model;default_effort=$row.reasoning_effort;efforts=@()}
  $script:bindingModel=$true
  try{
   $script:ui.Model.ItemsSource=@($fallback);$script:ui.Model.SelectedIndex=0
   $efforts=@();if($row.reasoning_effort){$efforts=@([string]$row.reasoning_effort)}
   $script:ui.Effort.ItemsSource=$efforts;if($efforts.Count){$script:ui.Effort.SelectedIndex=0}else{$script:ui.Effort.SelectedItem=$null}
   $script:ui.ModelInfo.Text='当前配置：'+$row.model+' / '+$(if($row.reasoning_effort){$row.reasoning_effort}else{'无推理强度'})+'；模型列表尚未读取，点击“读取模型”更新可选范围。'
  }finally{$script:bindingModel=$false}
  $script:ui.SaveModel.IsEnabled=$false
  return
 }
 $script:bindingModel=$true
 try{$script:ui.Model.ItemsSource=$script:catalog;$script:ui.Model.SelectedValue=$row.model;Update-Efforts $row.reasoning_effort
  $script:ui.ModelInfo.Text='当前配置：'+$row.model+' / '+$(if($row.reasoning_effort){$row.reasoning_effort}else{'无推理强度'})+'；选项来自客户端 model/list，保存后空闲重启生效。'
 }finally{$script:bindingModel=$false}
}
function Update-Selection {
 $row=Selected
 foreach($name in @('Connect','Start','Stop','Restart','OpenChat','OpenCodex','OpenFolder','Save','Persona','RefreshModels','Model','Role')){$script:ui[$name].IsEnabled=!!$row}
 $scopeText=if($script:currentPage -in @('overview','updates')){'账号额度与软件设置不属于单个实例'}else{$null}
 $script:ui.InstancePicker.IsEnabled=(-not $scopeText -and $script:rows.Count -gt 0)
 if(-not $row){
  $script:selection=''
  $script:ui.SelectionState.Text=if($scopeText){$scopeText}else{'选择实例后可进行服务、权限或模型操作'}
  $script:ui.Detail.Text='尚未选择实例'
  $script:ui.Workspace.Text='从顶部选择实例后显示工作目录'
  $script:ui.Chat.Text='从顶部选择实例后显示关联聊天'
  $script:ui.PersonaInfo.Text='选择实例后显示当前角色与参考图'
  $script:ui.ServiceContext.Text='请先在顶部选择实例'
  $script:ui.PermissionContext.Text='请先在顶部选择实例'
  $script:ui.ModelContext.Text='请先在顶部选择实例'
  $script:ui.Role.IsEnabled=$false;$script:ui.Save.IsEnabled=$false
  foreach($name in @('Images','Files','Projects')){$script:ui[$name].IsEnabled=$false}
  $script:ui.Model.IsEnabled=$false;$script:ui.Effort.IsEnabled=$false;$script:ui.SaveModel.IsEnabled=$false
  return
 }
 $script:ui.Detail.Text=$row.label+'  ·  '+$row.name
 $script:ui.PersonaInfo.Text='当前角色：'+$row.persona.assistant_name+' · '+@($row.persona.references).Count+' 张参考图（各实例独立）'
 $script:ui.Workspace.Text='工作目录：'+$row.workspace
 $script:ui.Chat.Text='聊天：'+$(if($row.thread_id){$row.thread_id}else{'尚未建立，首次工作时自动创建'})
 $phase=switch($row.phase){'working'{'处理中'};'listening'{'监听中'};'stopped'{'已停止'};'needs_attention'{'需检查'};'prepared'{'待扫码'};'ready'{'已就绪'};default{$row.phase}}
 if(-not $row.running -and $row.logged_in){$phase='已停止'};if($row.error){$phase='配置异常'}
 $script:ui.SelectionState.Text=if($scopeText){$scopeText}else{$phase+'　·　队列 '+$row.queued+'　·　'+$row.model+' / '+$(if($row.reasoning_effort){$row.reasoning_effort}else{'不适用'})}
 $script:ui.ServiceContext.Text='当前实例：'+$row.label+' ('+$row.name+') · '+$(if($row.logged_in){'微信已绑定'}else{'待本人扫码'})+' · '+$row.policy.role_label
 $script:ui.PermissionContext.Text='当前实例：'+$row.label+' ('+$row.name+') · '+$row.policy.role_label
 $script:ui.ModelContext.Text='当前实例：'+$row.label+' ('+$row.name+')'
 if($script:selection -ne $row.name){
  $script:selection=$row.name
  foreach($item in $script:ui.Role.Items){if($item.Tag -eq $row.policy.role){$script:ui.Role.SelectedItem=$item;break}}
  $script:ui.Images.IsChecked=!!$row.policy.capabilities.images;$script:ui.Files.IsChecked=!!$row.policy.capabilities.files;$script:ui.Projects.IsChecked=!!$row.policy.capabilities.projects
  Load-ModelChoice $row
 }
 $script:ui.Role.IsEnabled=$row.name -ne 'primary';$script:ui.Save.IsEnabled=$row.name -ne 'primary'
 Enable-Capabilities
}
function Apply-Snapshot($value){
 $script:snapshotLoaded=$true
 $selected=if(Selected){(Selected).name}else{''};$script:rows=@($value.instances);$script:defaultPersona=$value.default_persona
 foreach($row in $script:rows){if($script:chatWindows.ContainsKey($row.name)){$entry=$script:chatWindows[$row.name];$entry.AssistantName=$row.persona.assistant_name;$entry.Window.Title='聊天 · '+$row.label+' ('+$row.name+')';$entry.Window.FindName('Heading').Text=$row.label+' · '+$row.persona.assistant_name}}
 $items=@(foreach($row in $script:rows){
  $phase=switch($row.phase){'working'{'处理中'};'listening'{'监听中'};'stopped'{'已停止'};'needs_attention'{'需检查'};'prepared'{'待扫码'};'ready'{'已就绪'};default{$row.phase}}
  if(-not $row.running -and $row.logged_in){$phase='已停止'};if($row.error){$phase='配置异常'}
  $received=if($row.last_received_at){try{([datetime]$row.last_received_at).ToLocalTime().ToString('MM-dd HH:mm:ss')}catch{'—'}}else{'—'}
  if($row.running -and $row.phase -in @('listening','ready')){$phase='运行中'}
  $statusBrush=if($row.error -or $row.phase -eq 'needs_attention'){'#C25769'}elseif($row.running){'#28AA68'}else{'#A8844E'}
  $knownModel=$script:catalog|Where-Object {$_.model -eq $row.model}|Select-Object -First 1
  $modelLabel=if($knownModel.display_name){$knownModel.display_name}else{$row.model}
  $effortNames=@{none='无';minimal='最低';low='低';medium='中';high='高';xhigh='极高';max='最高';ultra='超高'}
  $effort=if($row.reasoning_effort -and $effortNames.ContainsKey([string]$row.reasoning_effort)){$effortNames[[string]$row.reasoning_effort]}elseif($row.reasoning_effort){$row.reasoning_effort}else{'不适用'}
  $owner=$row.name -eq 'primary';$label=[string]$row.label
  [pscustomobject]@{Display=$row.label+'  ('+$row.name+')';Role=$row.policy.role_label;Service=$phase;Received=$received;Raw=$row;Initial=$(if($label.Length){$label.Substring(0,1)}else{'友'});AvatarBrush=$(if($owner){'#8670E4'}else{'#608AF0'});RoleBackground=$(if($owner){'#F0EBFD'}else{'#EAF0FF'});RoleBrush=$(if($owner){'#8670E4'}else{'#608AF0'});StatusBrush=$statusBrush;ModelLabel=$modelLabel;EffortLabel='推理强度：'+$effort}
 })
 # Keep existing row controls alive when only backend metadata changes, including open menus.
 $viewKey=ConvertTo-Json -InputObject @($items|Select-Object * -ExcludeProperty Raw) -Depth 5 -Compress
 if($viewKey -ne $script:instanceViewKey){
  $pick=$items|Where-Object {$_.Raw.name -eq $selected}|Select-Object -First 1
  $script:bindingSelection=$true
  try{
   $script:ui.Instances.ItemsSource=$items;$script:ui.InstancePicker.ItemsSource=$items
   if($pick){$script:ui.Instances.SelectedItem=$pick;$script:ui.InstancePicker.SelectedItem=$pick}elseif($items.Count){$script:ui.Instances.SelectedIndex=0;$script:ui.InstancePicker.SelectedIndex=0}else{$script:ui.Instances.SelectedItem=$null;$script:ui.InstancePicker.SelectedItem=$null}
   $script:instanceViewKey=$viewKey
  }finally{$script:bindingSelection=$false}
 }else{
  foreach($item in $script:ui.Instances.Items){$current=$script:rows|Where-Object {$_.name -eq $item.Raw.name}|Select-Object -First 1;if($current){$item.Raw=$current}}
 }
 $online=@($script:rows|Where-Object {$_.running}).Count
 $pending=0;foreach($row in $script:rows){$pending+=[int]$row.queued}
 $script:ui.StatInstances.Text=[string]$items.Count;$script:ui.InstanceCount.Text=[string]$items.Count
 $script:ui.StatRunning.Text=[string]$online;$script:ui.StatPending.Text=[string]$pending
 $script:ui.Instances.Height=38+80*[Math]::Min([Math]::Max(1,$items.Count),5)+2
 $attention=@($script:rows|Where-Object {$_.error -or $_.phase -eq 'needs_attention'}).Count
 $health=if(-not $items.Count){'等待添加微信实例'}elseif($attention){'有实例需要检查'}elseif($online -eq $items.Count){'服务运行正常'}else{'有实例尚未运行'}
 $script:ui.ServiceHealth.Text=$health
 $script:ui.ServiceBadge.Background=if($attention){'#C25769'}elseif($online -eq $items.Count -and $items.Count){'#28AA68'}else{'#B49360'}
 $script:ui.ServiceGlyph.Text=if($online -eq $items.Count -and $items.Count -and -not $attention){[char]0xE73E}else{[char]0xE946}
 $script:ui.Summary.Text='任务完成通知发送至主实例 · 状态更新 '+([datetime]::Now.ToString('HH:mm:ss'))
 $script:ui.OverviewEmpty.Visibility=if($items.Count){'Collapsed'}else{'Visible'}
 Update-ConnectionSummary
 $script:nextName=$value.next_name;Update-Selection
}
function Add-User {
 if(-not $script:setupState.ready){Show-Setup;return}
 [xml]$newXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="新增独立微信用户" Width="430" Height="285" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI" Background="#F8F9FC"><StackPanel Margin="24"><TextBlock Name="Name" FontSize="18" FontWeight="SemiBold" Foreground="#242636"/><TextBlock Text="显示名称" Margin="0,16,0,7" Foreground="#526174"/><TextBox Name="Label" Padding="9" MaxLength="60" BorderBrush="#D4DCE3"/><TextBlock Text="独立登录、独立工作目录；默认开放聊天、生图、文件与跨项目协作。" TextWrapping="Wrap" Foreground="#64748B" Margin="0,12,0,15"/><Button Name="Create" Content="创建并扫码连接" Padding="12,8" HorizontalAlignment="Right" Background="#7864DC" BorderBrush="#7864DC" Foreground="White"/></StackPanel></Window>
'@
 $dialog=Read-Dialog $newXaml
 $name=$script:nextName;if(-not $name){$name='primary'}
 $dialog.FindName('Name').Text='新增实例：'+$name;$dialog.FindName('Label').Text=$name
 $dialog.Tag=@{Name=$name;Label=$dialog.FindName('Label')}
 $dialog.FindName('Create').Add_Click({$dlg=$this.Parent.Parent;$label=$dlg.Tag.Label.Text.Trim();if(-not $label){return};Begin-JobCommand @{action='create';name=$dlg.Tag.Name;label=$label};$dlg.Close()})
 [void]$dialog.ShowDialog()
}
foreach($pair in @(@('NavOverview','overview'),@('NavService','service'),@('NavPermissions','permissions'),@('NavModels','models'),@('NavUpdates','updates'))){$script:ui[$pair[0]].Tag=$pair[1];$script:ui[$pair[0]].Add_Click({if($this.IsChecked){Show-Page ([string]$this.Tag)}})}
$script:ui.ManageAll.Add_Click({Show-Page 'service'})
$script:ui.ViewServices.Add_Click({Show-Page 'service'})
$script:ui.Instances.AddHandler([Windows.Controls.Button]::ClickEvent,[Windows.RoutedEventHandler]{param($sender,$event)
 $button=$event.OriginalSource
 if($button -isnot [Windows.Controls.Button] -or $button.Tag -notin @('row-chat','row-menu')){return}
 $event.Handled=$true;$name=[string]$button.DataContext.Raw.name
 if(-not (Select-Instance $name)){return}
 if($button.Tag -eq 'row-chat'){Show-Chat}else{Show-InstanceMenu $button $name}
},$true)
$script:ui.Instances.Add_SelectionChanged({
 if(-not $script:bindingSelection){
  $item=$script:ui.Instances.SelectedItem
  if($item){$script:bindingSelection=$true;try{$script:ui.InstancePicker.SelectedItem=$item}finally{$script:bindingSelection=$false}}
  Update-Selection
 }
})
$script:ui.InstancePicker.Add_SelectionChanged({
 if(-not $script:bindingSelection){
  $item=$script:ui.InstancePicker.SelectedItem
  if($item){$script:bindingSelection=$true;try{$script:ui.Instances.SelectedItem=$item}finally{$script:bindingSelection=$false}}
  Update-Selection
 }
})
$script:ui.Role.Add_SelectionChanged({Enable-Capabilities})
$script:ui.Refresh.Add_Click({$script:lastRefresh=[datetime]::MinValue;$script:lastUsage=[datetime]::MinValue;Say '正在刷新实例状态和账号额度…'})
$script:ui.Add.Add_Click({Add-User})
$script:ui.Setup.Add_Click({Show-Setup})
$script:ui.Update.Add_Click({Show-Update})
$script:ui.UsageBucket.Add_SelectionChanged({Update-UsageView})
$script:ui.RefreshUsage.Add_Click({if(Begin-JobCommand @{action='usage';name=''}){$script:ui.RefreshUsage.IsEnabled=$false;$script:ui.RefreshUsage.Content='正在读取…';$script:ui.UsageHint.Text='正在读取当前Codex账号额度…';$script:lastUsage=[datetime]::UtcNow}})
$script:ui.Persona.Add_Click({Show-Persona})
$script:ui.OpenChat.Add_Click({Show-Chat})
$script:ui.Model.Add_SelectionChanged({if(-not $script:bindingModel){Update-Efforts $script:ui.Effort.SelectedItem}})
$script:ui.RefreshModels.Add_Click({if(-not $script:setupState.ready){Show-Setup;return};[void](Begin-JobCommand @{action='models';name=''})})
$script:ui.SaveModel.Add_Click({$row=Selected;$model=$script:ui.Model.SelectedItem;if($row -and $model){Begin-JobCommand @{action='model';name=$row.name;model=$model.model;effort=$script:ui.Effort.SelectedItem}}})
foreach($pair in @(@('Start','start'),@('Stop','stop'),@('Restart','restart'),@('Connect','connect'),@('OpenCodex','open-chat'),@('OpenFolder','open-workspace'))){$script:ui[$pair[0]].Tag=$pair[1];$script:ui[$pair[0]].Add_Click({$row=Selected;if($row){Begin-JobCommand @{action=$this.Tag;name=$row.name}}})}
$script:ui.Save.Add_Click({$row=Selected;if($row){Begin-JobCommand @{action='permissions';name=$row.name;role=$script:ui.Role.SelectedItem.Tag;capabilities=@{images=[bool]$script:ui.Images.IsChecked;files=[bool]$script:ui.Files.IsChecked;projects=[bool]$script:ui.Projects.IsChecked}}}})
$startPage=if($env:CLAWBOT_MANAGER_START_PAGE -in @('overview','service','permissions','models','usage','updates')){$env:CLAWBOT_MANAGER_START_PAGE}else{'overview'}
Show-Page $startPage;Update-Selection
$script:timer=[Windows.Threading.DispatcherTimer]::new();$script:timer.Interval=[timespan]::FromMilliseconds(500)
$script:timer.Add_Tick({
 try{
  foreach($job in @($script:jobs.ToArray())){
   if($job.Action -eq 'connect'){Update-Qr $job}
   if($job.Action -eq 'download-update'){Read-DownloadProgress $job}
   if(-not $job.Process.HasExited){continue};if(-not $job.Output.IsCompleted -or -not $job.Error.IsCompleted){continue}
   $text=$job.Output.Result;$result=$null
   foreach($line in ($text -split "`r?`n")){if($line.Trim().StartsWith('{')){try{$result=$line|ConvertFrom-Json}catch{}}}
   if($job.QrWindow){$job.QrWindow.Close()}
   [void]$script:jobs.Remove($job);$job.Process.Dispose();if([IO.File]::Exists($job.ProgressFile)){try{[IO.File]::Delete($job.ProgressFile)}catch{}}
   if(-not $result -or $result.status -eq 'error'){
    $code=if($result.code){$result.code}else{'LOCAL_OPERATION_FAILED'};$detail=if($script:errors.ContainsKey($code)){$script:errors[$code]}else{'操作未完成：'+$code}
    if($job.Action -eq 'history' -and $script:chatWindows.ContainsKey($job.Name)){$script:chatWindows[$job.Name].Window.FindName('Hint').Text=$detail}elseif($job.Action -eq 'setup-status'){
     Complete-SetupCheck ([pscustomobject]@{ready=$false;prompt='';connection_error=$code;checked_at=[datetime]::UtcNow;bundled_node=$false;node_version='';client_verified=$false}) $job.UserFeedback
    }elseif($job.Action -eq 'usage'){$script:ui.RefreshUsage.IsEnabled=$true;$script:ui.RefreshUsage.Content='刷新额度';$script:ui.UsageHint.Text='读取额度失败，请稍后刷新。';Say $detail $true
    }elseif($job.Action -like '*update'){Fail-Update $detail $job.Action}else{Say $detail $true}
   }elseif($job.Action -eq 'snapshot'){Apply-Snapshot $result
   }elseif($job.Action -eq 'setup-status'){Complete-SetupCheck $result $job.UserFeedback
   }elseif($job.Action -eq 'usage'){Apply-Usage $result
   }elseif($job.Action -eq 'check-update'){Apply-UpdateCheck $result
   }elseif($job.Action -eq 'download-update'){Apply-UpdateDownload $result
   }elseif($job.Action -eq 'install-update' -and $result.status -eq 'update_handoff'){$global:ClawBotUpdateHandoff=$true;if($script:updateDialog){$script:updateDialog.Close()};$script:window.Close();return
   }elseif($job.Action -eq 'history'){Apply-History $result
   }elseif($job.Action -eq 'models'){$script:catalog=@($result.models);Load-ModelChoice (Selected);Say ('已从客户端读取 '+$script:catalog.Count+' 个可用模型及各自推理强度。')
   }else{
    $words=@{start='服务已启动';stop='服务已停止';restart='服务已重启';connect='扫码连接完成，服务已启动';permissions='权限已保存';model='该实例模型已保存';persona='该实例人设、参考图与名称已保存';'open-chat'='已请求客户端打开对应聊天';'open-workspace'='已打开工作目录';create='实例已创建'}
    if($result.status -eq 'local_verification_required'){Say '微信要求额外验证码，请在本机终端运行该实例 Login 完成验证。' $true}else{Say ($words[$job.Action]+' · '+$job.Name)}
    $script:lastRefresh=[datetime]::MinValue
    if($job.Action -in @('permissions','model','persona')){$script:selection=''}
    if($job.Action -eq 'create'){Begin-JobCommand @{action='connect';name=$job.Name}}
   }
  }
  if($script:installPending){if(-not $script:jobs.Count){$script:installPending=$false;[void](Begin-JobCommand @{action='install-update';name='';version=$script:downloadState.version;manager_pid=$PID;manager_start_ticks=([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks.ToString())})};return}
  if(@($script:jobs|Where-Object {$_.Action -eq 'install-update'}).Count){return}
  if(([datetime]::UtcNow-$script:lastRefresh).TotalSeconds -ge 4 -and -not @($script:jobs|Where-Object {$_.Action -eq 'snapshot'}).Count){$script:lastRefresh=[datetime]::UtcNow;Begin-JobCommand @{action='snapshot';name=''}}
  foreach($name in @($script:chatWindows.Keys)){$entry=$script:chatWindows[$name];if(([datetime]::UtcNow-$entry.LastRefresh).TotalSeconds -ge 4){$entry.LastRefresh=[datetime]::UtcNow;[void](Begin-JobCommand @{action='history';name=$name})}}
  if(-not $script:setupRequested){$script:setupRequested=$true;[void](Begin-JobCommand @{action='setup-status';name=''})}
  if($script:snapshotLoaded -and $script:setupState -and -not $script:setupShown -and (-not $script:setupState.ready -or -not $script:rows.Count)){$script:setupShown=$true;[void]$script:window.Dispatcher.BeginInvoke([Action]{Show-Setup})}
  if($script:setupVerifyRequested -and -not @($script:jobs|Where-Object {$_.Action -eq 'setup-status'}).Count){$script:setupVerifyRequested=$false;[void](Begin-JobCommand @{action='setup-status';name='';verify=$true;user_feedback=$true})}
  if($script:setupState.ready -and -not $script:modelsRequested){$script:modelsRequested=$true;Begin-JobCommand @{action='models';name=''}}
  if($script:setupState.ready -and ([datetime]::UtcNow-$script:lastUsage).TotalMinutes -ge 5){$script:lastUsage=[datetime]::UtcNow;[void](Begin-JobCommand @{action='usage';name=''})}
 }catch{Say '界面更新异常，请刷新；服务进程保持原状态。' $true}
})
$script:window.Add_Closed({$script:timer.Stop()})
if($SelfTest){
 foreach($page in @('overview','service','permissions','models','updates')){Show-Page $page;if($script:currentPage -ne $page){throw 'PAGE_SWITCH_FAILED'}}
 . (Join-Path $PSScriptRoot 'ViewSelfTest.ps1')
 Show-Page 'overview'
 $a=New-PersonaDialog;$b=New-ChatDialog;$c=New-SetupDialog;$d=New-UpdateDialog
 if(-not $a -or -not $b -or -not $c -or -not $d){throw 'DIALOG_LOAD_FAILED'}
 $a.Close();$b.Close();$c.Close();$d.Close()
 [Console]::WriteLine('WPF_LOAD_OK: five pages, home quotas, row actions, instance picker, manager and four dialogs');exit 0
}
$script:timer.Start();[void]$script:window.ShowDialog()
