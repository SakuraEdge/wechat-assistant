#requires -Version 5.1
[CmdletBinding()]param([switch]$SelfTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appRoot=Split-Path $PSScriptRoot -Parent
$script:controller=Join-Path $PSScriptRoot 'controller.mjs'
. (Join-Path $PSScriptRoot 'Runtime.ps1')
$script:node=Resolve-ManagerNode $script:appRoot
$script:manager=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Codex\wechat-manager'
$script:jobsDir=Join-Path $script:manager 'jobs'
[void][IO.Directory]::CreateDirectory($script:jobsDir)
$script:jobs=[Collections.ArrayList]::new()
$script:setupRequested=$false;$script:setupShown=$false;$script:setupState=$null;$script:setupDialog=$null
$script:rows=@();$script:selection='';$script:lastRefresh=[datetime]::MinValue;$script:catalog=@();$script:modelsRequested=$false;$script:bindingModel=$false
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
}
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="ClawBot实例管理器" Width="1280" Height="920" MinWidth="1100" MinHeight="820" WindowStartupLocation="CenterScreen" Background="#F4F6FB" FontFamily="Microsoft YaHei UI" FontSize="13">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="14,9"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#CCD3E3"/><Setter Property="Foreground" Value="#26324A"/><Setter Property="Cursor" Value="Hand"/></Style>
  <Style TargetType="CheckBox"><Setter Property="Margin" Value="0,8,22,8"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
 </Window.Resources>
 <Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Margin="0,0,0,20"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <StackPanel><TextBlock Text="ClawBot实例管理器" FontSize="28" FontWeight="SemiBold" Foreground="#24304A"/><TextBlock Text="每个账号独立连接 · 主用户统一管理" Foreground="#69758C" Margin="0,7,0,0"/></StackPanel>
   <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button Name="Setup" Content="首次使用 / 连接客户端"/><Button Name="Refresh" Content="刷新状态"/><Button Name="Add" Content="＋ 新增微信用户" Background="#6454D9" Foreground="White" BorderBrush="#6454D9"/></StackPanel>
  </Grid>
  <Border Grid.Row="1" Background="#E9E6FD" CornerRadius="10" Padding="16,12" Margin="0,0,0,14"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Name="Summary" Text="正在读取实例状态…" Foreground="#493A9E"/><TextBlock Grid.Column="1" Text="模型与强度按实例设置　|　完成通知 → primary" Foreground="#655A9C"/></Grid></Border>
  <DataGrid Name="Instances" Grid.Row="2" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Single" SelectionUnit="FullRow" GridLinesVisibility="Horizontal" HeadersVisibility="Column" RowHeight="48" Background="White" BorderBrush="#E0E5EF" AlternatingRowBackground="#FAFBFE" HorizontalScrollBarVisibility="Auto">
   <DataGrid.Columns>
    <DataGridTextColumn Header="微信用户 / 实例" Binding="{Binding Display}" Width="210"/>
    <DataGridTextColumn Header="权限角色" Binding="{Binding Role}" Width="170"/>
    <DataGridTextColumn Header="聊天人设" Binding="{Binding Persona}" Width="130"/>
    <DataGridTextColumn Header="模型 / 强度" Binding="{Binding Model}" Width="230"/>
    <DataGridTextColumn Header="服务状态" Binding="{Binding Service}" Width="125"/>
    <DataGridTextColumn Header="微信绑定" Binding="{Binding Login}" Width="110"/>
    <DataGridTextColumn Header="队列" Binding="{Binding Queue}" Width="65"/>
    <DataGridTextColumn Header="最近接收" Binding="{Binding Received}" Width="155"/>
    <DataGridTextColumn Header="客户端协作" Binding="{Binding Desktop}" Width="*" MinWidth="110"/>
   </DataGrid.Columns>
  </DataGrid>
  <Border Grid.Row="3" Background="White" BorderBrush="#E0E5EF" BorderThickness="1" CornerRadius="10" Padding="18" Margin="0,14,0,0">
   <StackPanel>
    <TextBlock Name="Detail" Text="请选择一个实例" FontWeight="SemiBold" FontSize="15" Foreground="#26324A"/>
    <TextBlock Name="Workspace" Foreground="#758096" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/>
    <TextBlock Name="Chat" Foreground="#758096" Margin="0,4,0,13" TextTrimming="CharacterEllipsis"/>
    <WrapPanel Margin="0,0,0,14"><Button Name="Connect" Content="扫码连接"/><Button Name="Start" Content="启动服务"/><Button Name="Stop" Content="停止服务" ToolTip="会中止此实例当前工作"/><Button Name="Restart" Content="重启服务" ToolTip="工作中不自动中断，请等待空闲"/><Button Name="OpenChat" Content="在管理器中查看聊天"/><Button Name="OpenCodex" Content="在 Codex 中打开聊天"/><Button Name="OpenFolder" Content="打开工作目录"/></WrapPanel>
    <Border Background="#F5F6FC" Padding="12" CornerRadius="6"><WrapPanel VerticalAlignment="Center">
     <TextBlock Text="权限" VerticalAlignment="Center" Margin="0,0,12,0"/><ComboBox Name="Role" Width="160" Margin="0,0,20,0" VerticalAlignment="Center"><ComboBoxItem Content="日常用户" Tag="standard"/><ComboBoxItem Content="授权管理员" Tag="delegate"/><ComboBoxItem Content="主用户 · 完整权限" Tag="owner"/></ComboBox>
     <CheckBox Name="Images" Content="生图"/><CheckBox Name="Files" Content="文件收发"/><CheckBox Name="Projects" Content="跨项目协作"/>
     <Button Name="Save" Content="保存权限" Margin="6,0,0,0"/>
    </WrapPanel></Border>
    <TextBlock Text="主用户拥有完整业务权限；普通用户默认开放日常功能。保存权限会在空闲时重启该实例。" Foreground="#7C879A" FontSize="11" Margin="0,10,0,0"/>
    <WrapPanel Margin="0,14,0,0"><TextBlock Text="模型" VerticalAlignment="Center" Margin="0,0,12,0"/><ComboBox Name="Model" Width="245" DisplayMemberPath="display_name" SelectedValuePath="model" VerticalAlignment="Center" Margin="0,0,12,0"/><TextBlock Text="推理强度" VerticalAlignment="Center" Margin="0,0,10,0"/><ComboBox Name="Effort" Width="95" VerticalAlignment="Center" Margin="0,0,16,0"/><Button Name="RefreshModels" Content="读取可用模型"/><Button Name="SaveModel" Content="保存模型"/></WrapPanel>
    <WrapPanel Margin="0,14,0,0"><Button Name="Persona" Content="设置人设与名称"/><TextBlock Name="PersonaInfo" Foreground="#69758C" VerticalAlignment="Center"/></WrapPanel>
    <TextBlock Name="ModelInfo" Text="从客户端读取模型列表及各模型支持的推理强度…" Foreground="#7C879A" FontSize="11" Margin="0,8,0,0"/>
   </StackPanel>
  </Border>
  <TextBlock Name="Message" Grid.Row="4" Text="就绪。关闭本窗口不会停止已启动的服务。" TextWrapping="Wrap" Foreground="#58677E" Margin="2,13,0,0"/>
 </Grid>
</Window>
'@
$script:window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$script:window.MinHeight=[Math]::Min(740,[Windows.SystemParameters]::WorkArea.Height-30)
$script:window.Height=[Math]::Min(850,[Windows.SystemParameters]::WorkArea.Height-20)
$script:window.MinWidth=[Math]::Min(1100,[Windows.SystemParameters]::WorkArea.Width-30)
$script:window.Width=[Math]::Min(1280,[Windows.SystemParameters]::WorkArea.Width-20)
$script:ui=@{};foreach($name in @('Refresh','Add','Summary','Instances','Detail','Workspace','Chat','Connect','Start','Stop','Restart','OpenChat','OpenFolder','Role','Images','Files','Projects','Save','Message','Model','Effort','RefreshModels','SaveModel','ModelInfo','Persona','PersonaInfo','OpenCodex','Setup')){$script:ui[$name]=$script:window.FindName($name)}
$iconPath=Join-Path $script:appRoot 'assets\clawbot.ico'
if(Test-Path -LiteralPath $iconPath){$script:window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$iconPath)}
. (Join-Path $PSScriptRoot 'Dialogs.ps1')
function Say([string]$text,[bool]$failed=$false){$script:ui.Message.Text=$text;$script:ui.Message.Foreground=if($failed){'#B54559'}else{'#58677E'}}
function Selected {if($script:ui.Instances.SelectedItem){return $script:ui.Instances.SelectedItem.Raw};return $null}
function Begin-JobCommand($request){
 $readOnly=$request.action -in @('snapshot','history','models','setup-status')
 if($readOnly -and @($script:jobs|Where-Object {$_.Name -eq $request.name -and $_.Action -eq $request.action}).Count){return $false}
 if(-not $readOnly -and @($script:jobs|Where-Object {$_.Name -eq $request.name -and $_.Action -notin @('snapshot','history','models','setup-status')}).Count){Say '此实例的上一项操作仍在进行，请等待完成。';return $false}
 $file=Join-Path $script:jobsDir (([Guid]::NewGuid().ToString('N'))+'.json')
 [IO.File]::WriteAllText($file,($request|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$script:node
 $start.Arguments='"'+$script:controller+'" --request "'+$file+'"'
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
 $proc=[Diagnostics.Process]::Start($start)
 $job=[pscustomobject]@{Action=$request.action;Name=$request.name;Process=$proc;Output=$proc.StandardOutput.ReadToEndAsync();Error=$proc.StandardError.ReadToEndAsync();Started=[datetime]::UtcNow;QrWindow=$null;QrImage=$null;QrHint=$null;QrStamp=[datetime]::MinValue}
 [void]$script:jobs.Add($job)
 if(-not $readOnly){Say ('正在执行：'+$request.action+' · '+$request.name+'。窗口可以继续使用。')}
 if($request.action -eq 'connect'){Show-Qr $job}
 return $true
}
function Show-Qr($job){
 [xml]$qrXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="微信扫码连接" Width="450" Height="560" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="White" FontFamily="Microsoft YaHei UI"><StackPanel Margin="24"><TextBlock Text="请使用该用户自己的微信扫码" FontSize="18" FontWeight="SemiBold" TextAlignment="Center"/><Image Name="QrImage" Width="350" Height="350" Margin="0,15,0,10"/><TextBlock Name="QrHint" Text="正在准备二维码…" TextAlignment="Center" TextWrapping="Wrap" Foreground="#68758C"/><TextBlock Text="关闭此窗口不会取消等待；二维码约5分钟后过期。" TextAlignment="Center" TextWrapping="Wrap" FontSize="11" Margin="0,14,0,0" Foreground="#8C95A7"/></StackPanel></Window>
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
 $row=Selected;$standard=$script:ui.Role.SelectedItem.Tag -eq 'standard'
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
 if(-not $row -or -not $script:catalog.Count){$script:ui.SaveModel.IsEnabled=$false;return}
 $script:bindingModel=$true
 try{$script:ui.Model.ItemsSource=$script:catalog;$script:ui.Model.SelectedValue=$row.model;Update-Efforts $row.reasoning_effort
  $script:ui.ModelInfo.Text='当前配置：'+$row.model+' / '+$(if($row.reasoning_effort){$row.reasoning_effort}else{'无推理强度'})+'；选项来自客户端 model/list，保存后空闲重启生效。'
 }finally{$script:bindingModel=$false}
}
function Update-Selection {
 $row=Selected
 foreach($name in @('Connect','Start','Stop','Restart','OpenChat','OpenCodex','OpenFolder','Save','Persona')){$script:ui[$name].IsEnabled=!!$row}
 if(-not $row){$script:ui.Detail.Text='请选择一个实例';return}
 $script:ui.Detail.Text=$row.label+'  ·  '+$row.name
 $script:ui.PersonaInfo.Text='当前角色：'+$row.persona.assistant_name+' · '+@($row.persona.references).Count+' 张参考图（各实例独立）'
 $script:ui.Workspace.Text='工作目录：'+$row.workspace
 $script:ui.Chat.Text='聊天：'+$(if($row.thread_id){$row.thread_id}else{'尚未建立，首次工作时自动创建'})
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
 $selected=if(Selected){(Selected).name}else{''};$script:rows=@($value.instances);$script:defaultPersona=$value.default_persona
 foreach($row in $script:rows){if($script:chatWindows.ContainsKey($row.name)){$entry=$script:chatWindows[$row.name];$entry.AssistantName=$row.persona.assistant_name;$entry.Window.Title='聊天 · '+$row.label+' ('+$row.name+')';$entry.Window.FindName('Heading').Text=$row.label+' · '+$row.persona.assistant_name}}
 $items=@(foreach($row in $script:rows){
  $phase=switch($row.phase){'working'{'处理中'};'listening'{'监听中'};'stopped'{'已停止'};'needs_attention'{'需检查'};'prepared'{'待扫码'};'ready'{'已就绪'};default{$row.phase}}
  if(-not $row.running -and $row.logged_in){$phase='已停止'};if($row.error){$phase='配置异常'}
  $received=if($row.last_received_at){try{([datetime]$row.last_received_at).ToLocalTime().ToString('MM-dd HH:mm:ss')}catch{'—'}}else{'—'}
  [pscustomobject]@{Display=$row.label+'  ('+$row.name+')';Role=$row.policy.role_label;Persona=$row.persona.assistant_name;Model=$row.model+' / '+$(if($row.reasoning_effort){$row.reasoning_effort}else{'不适用'});Service=$phase;Login=$(if($row.logged_in){'已绑定'}else{'待扫码'});Queue=$row.queued;Received=$received;Desktop=$(if($row.project_tools_connected){'已连接'}elseif($row.running){'待连接 / 检查'}else{'服务未运行'});Raw=$row}
 })
 $script:ui.Instances.ItemsSource=$items
 $pick=$items|Where-Object {$_.Raw.name -eq $selected}|Select-Object -First 1
 if($pick){$script:ui.Instances.SelectedItem=$pick}elseif($items.Count){$script:ui.Instances.SelectedIndex=0}
 $online=@($script:rows|Where-Object {$_.running}).Count
 $script:ui.Summary.Text=('{0} 个实例　·　{1} 个服务运行中　·　状态更新 {2}' -f $items.Count,$online,([datetime]::Now.ToString('HH:mm:ss')))
 $script:nextName=$value.next_name;Update-Selection
}
function Add-User {
 if(-not $script:setupState.ready){Show-Setup;return}
 [xml]$newXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="新增独立微信用户" Width="430" Height="285" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI" Background="White"><StackPanel Margin="24"><TextBlock Name="Name" FontSize="18" FontWeight="SemiBold"/><TextBlock Text="显示名称" Margin="0,16,0,7"/><TextBox Name="Label" Padding="9" MaxLength="60"/><TextBlock Text="独立登录、独立工作目录；默认开放聊天、生图、文件与跨项目协作。" TextWrapping="Wrap" Foreground="#788599" Margin="0,12,0,15"/><Button Name="Create" Content="创建并扫码连接" Padding="10,8" HorizontalAlignment="Right"/></StackPanel></Window>
'@
 $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($newXaml));$dialog.Owner=$script:window
 $name=$script:nextName;if(-not $name){$name='primary'}
 $dialog.FindName('Name').Text='新增实例：'+$name;$dialog.FindName('Label').Text=$name
 $dialog.Tag=@{Name=$name;Label=$dialog.FindName('Label')}
 $dialog.FindName('Create').Add_Click({$dlg=$this.Parent.Parent;$label=$dlg.Tag.Label.Text.Trim();if(-not $label){return};Begin-JobCommand @{action='create';name=$dlg.Tag.Name;label=$label};$dlg.Close()})
 [void]$dialog.ShowDialog()
}
$script:ui.Instances.Add_SelectionChanged({Update-Selection})
$script:ui.Role.Add_SelectionChanged({Enable-Capabilities})
$script:ui.Refresh.Add_Click({$script:lastRefresh=[datetime]::MinValue})
$script:ui.Add.Add_Click({Add-User})
$script:ui.Setup.Add_Click({Show-Setup})
$script:ui.Persona.Add_Click({Show-Persona})
$script:ui.OpenChat.Add_Click({Show-Chat})
$script:ui.Model.Add_SelectionChanged({if(-not $script:bindingModel){Update-Efforts $script:ui.Effort.SelectedItem}})
$script:ui.RefreshModels.Add_Click({if(-not $script:setupState.ready){Show-Setup;return};[void](Begin-JobCommand @{action='models';name=''})})
$script:ui.SaveModel.Add_Click({$row=Selected;$model=$script:ui.Model.SelectedItem;if($row -and $model){Begin-JobCommand @{action='model';name=$row.name;model=$model.model;effort=$script:ui.Effort.SelectedItem}}})
foreach($pair in @(@('Start','start'),@('Stop','stop'),@('Restart','restart'),@('Connect','connect'),@('OpenCodex','open-chat'),@('OpenFolder','open-workspace'))){$script:ui[$pair[0]].Tag=$pair[1];$script:ui[$pair[0]].Add_Click({$row=Selected;if($row){Begin-JobCommand @{action=$this.Tag;name=$row.name}}})}
$script:ui.Save.Add_Click({$row=Selected;if($row){Begin-JobCommand @{action='permissions';name=$row.name;role=$script:ui.Role.SelectedItem.Tag;capabilities=@{images=[bool]$script:ui.Images.IsChecked;files=[bool]$script:ui.Files.IsChecked;projects=[bool]$script:ui.Projects.IsChecked}}}})
$script:timer=[Windows.Threading.DispatcherTimer]::new();$script:timer.Interval=[timespan]::FromMilliseconds(500)
$script:timer.Add_Tick({
 try{
  foreach($job in @($script:jobs.ToArray())){
   if($job.Action -eq 'connect'){Update-Qr $job}
   if(-not $job.Process.HasExited){continue};if(-not $job.Output.IsCompleted -or -not $job.Error.IsCompleted){continue}
   $text=$job.Output.Result;$result=$null
   foreach($line in ($text -split "`r?`n")){if($line.Trim().StartsWith('{')){try{$result=$line|ConvertFrom-Json}catch{}}}
   if($job.QrWindow){$job.QrWindow.Close()}
   [void]$script:jobs.Remove($job);$job.Process.Dispose()
   if(-not $result -or $result.status -eq 'error'){
    $code=if($result.code){$result.code}else{'LOCAL_OPERATION_FAILED'};$detail=if($script:errors.ContainsKey($code)){$script:errors[$code]}else{'操作未完成：'+$code}
    if($job.Action -eq 'history' -and $script:chatWindows.ContainsKey($job.Name)){$script:chatWindows[$job.Name].Window.FindName('Hint').Text=$detail}else{Say $detail $true}
   }elseif($job.Action -eq 'snapshot'){Apply-Snapshot $result
   }elseif($job.Action -eq 'setup-status'){$script:setupState=$result;Update-SetupDialog;if(-not $result.ready -and -not $script:setupShown){Show-Setup}
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
  if(([datetime]::UtcNow-$script:lastRefresh).TotalSeconds -ge 4 -and -not @($script:jobs|Where-Object {$_.Action -eq 'snapshot'}).Count){$script:lastRefresh=[datetime]::UtcNow;Begin-JobCommand @{action='snapshot';name=''}}
  foreach($name in @($script:chatWindows.Keys)){$entry=$script:chatWindows[$name];if(([datetime]::UtcNow-$entry.LastRefresh).TotalSeconds -ge 4){$entry.LastRefresh=[datetime]::UtcNow;[void](Begin-JobCommand @{action='history';name=$name})}}
  if(-not $script:setupRequested){$script:setupRequested=$true;[void](Begin-JobCommand @{action='setup-status';name=''})}
  if($script:setupState.ready -and -not $script:modelsRequested){$script:modelsRequested=$true;Begin-JobCommand @{action='models';name=''}}
 }catch{Say '界面更新异常，请刷新；服务进程保持原状态。' $true}
})
$script:window.Add_Closed({$script:timer.Stop()})
if($SelfTest){$a=New-PersonaDialog;$b=New-ChatDialog;$c=New-SetupDialog;$a.Close();$b.Close();$c.Close();[Console]::WriteLine('WPF_LOAD_OK: manager, persona, chat, setup');exit 0}
$script:timer.Start();[void]$script:window.ShowDialog()
