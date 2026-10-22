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
$script:updateState=$null;$script:downloadState=$null;$script:updateDialog=$null;$script:installPending=$false
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
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="ClawBot实例管理器" Width="1320" Height="900" MinWidth="1020" MinHeight="700" WindowStartupLocation="CenterScreen" Background="#F3F5F7" FontFamily="Microsoft YaHei UI" FontSize="13">
 <Window.Resources>
  <Style x:Key="ModernButton" TargetType="{x:Type Button}">
   <Setter Property="Padding" Value="14,8"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="MinHeight" Value="36"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#D4DCE3"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="#243142"/><Setter Property="FontWeight" Value="Medium"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="{x:Type Button}"><Border x:Name="Chrome" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" RecognizesAccessKey="True"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Opacity" Value="0.9"/><Setter TargetName="Chrome" Property="BorderBrush" Value="#9EB0BE"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Chrome" Property="Opacity" Value="0.78"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Chrome" Property="BorderBrush" Value="#0F766E"/><Setter TargetName="Chrome" Property="BorderThickness" Value="2"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Chrome" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="{x:Type Button}" BasedOn="{StaticResource ModernButton}"/>
  <Style x:Key="PrimaryButton" TargetType="{x:Type Button}" BasedOn="{StaticResource ModernButton}"><Setter Property="Background" Value="#0F766E"/><Setter Property="BorderBrush" Value="#0F766E"/><Setter Property="Foreground" Value="White"/></Style>
  <Style x:Key="DangerButton" TargetType="{x:Type Button}" BasedOn="{StaticResource ModernButton}"><Setter Property="Foreground" Value="#A83A48"/><Setter Property="BorderBrush" Value="#E7C3C8"/></Style>
  <Style x:Key="NavButton" TargetType="{x:Type RadioButton}">
   <Setter Property="Foreground" Value="#B7C2D1"/><Setter Property="Background" Value="Transparent"/><Setter Property="FontSize" Value="14"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Padding" Value="13,10"/><Setter Property="Margin" Value="0,0,0,3"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="{x:Type RadioButton}"><Border x:Name="NavChrome" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter RecognizesAccessKey="True"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="NavChrome" Property="Background" Value="#223149"/><Setter Property="Foreground" Value="White"/></Trigger><Trigger Property="IsChecked" Value="True"><Setter TargetName="NavChrome" Property="Background" Value="#0F766E"/><Setter Property="Foreground" Value="White"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="NavChrome" Property="BorderBrush" Value="#7DD3C7"/><Setter TargetName="NavChrome" Property="BorderThickness" Value="2"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="SidebarButton" TargetType="{x:Type Button}" BasedOn="{StaticResource ModernButton}"><Setter Property="Background" Value="#223149"/><Setter Property="BorderBrush" Value="#34445D"/><Setter Property="Foreground" Value="#E8EEF5"/><Setter Property="Margin" Value="0"/></Style>
  <Style TargetType="{x:Type CheckBox}"><Setter Property="Margin" Value="0,7,24,7"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Foreground" Value="#334155"/></Style>
  <Style TargetType="{x:Type TextBox}"><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#D4DCE3"/><Setter Property="Padding" Value="10,8"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
  <Style TargetType="{x:Type ComboBox}">
   <Setter Property="MinHeight" Value="34"/><Setter Property="Padding" Value="10,5"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#D4DCE3"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="#243142"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="MaxDropDownHeight" Value="320"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="{x:Type ComboBox}"><Grid><ToggleButton Name="DropDownToggle" Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"><ToggleButton.Template><ControlTemplate TargetType="{x:Type ToggleButton}"><Border Name="ToggleChrome" Background="{Binding Background, RelativeSource={RelativeSource AncestorType={x:Type ComboBox}}}" BorderBrush="{Binding BorderBrush, RelativeSource={RelativeSource AncestorType={x:Type ComboBox}}}" BorderThickness="{Binding BorderThickness, RelativeSource={RelativeSource AncestorType={x:Type ComboBox}}}" CornerRadius="7"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="34"/></Grid.ColumnDefinitions><ContentPresenter Margin="{Binding Padding, RelativeSource={RelativeSource AncestorType={x:Type ComboBox}}}" HorizontalAlignment="Left" VerticalAlignment="Center" Content="{Binding Text, RelativeSource={RelativeSource AncestorType={x:Type ComboBox}}}"/><Path Grid.Column="1" Data="M 0 0 L 4 4 L 8 0" Stroke="#607083" StrokeThickness="1.5" HorizontalAlignment="Center" VerticalAlignment="Center"/></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ToggleChrome" Property="BorderBrush" Value="#9EB0BE"/></Trigger><Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="ToggleChrome" Property="BorderBrush" Value="#0F766E"/></Trigger></ControlTemplate.Triggers></ControlTemplate></ToggleButton.Template></ToggleButton><Popup Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade"><Border Background="White" BorderBrush="#CFD8DF" BorderThickness="1" CornerRadius="7" Margin="0,4,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="{TemplateBinding MaxDropDownHeight}"><ScrollViewer VerticalScrollBarVisibility="Auto"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border></Popup></Grid><ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="{x:Type DataGrid}"><Setter Property="Background" Value="White"/><Setter Property="BorderThickness" Value="0"/><Setter Property="GridLinesVisibility" Value="Horizontal"/><Setter Property="HorizontalGridLinesBrush" Value="#E7ECF0"/><Setter Property="RowHeight" Value="44"/><Setter Property="ColumnHeaderHeight" Value="40"/></Style>
  <Style TargetType="{x:Type DataGridColumnHeader}"><Setter Property="Background" Value="#F5F7F8"/><Setter Property="Foreground" Value="#526174"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="12,0"/><Setter Property="BorderBrush" Value="#E0E6EA"/><Setter Property="BorderThickness" Value="0,0,0,1"/></Style>
  <Style TargetType="{x:Type DataGridCell}"><Setter Property="Padding" Value="12,0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/></Style>
  <Style TargetType="{x:Type DataGridRow}"><Setter Property="Background" Value="White"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Foreground" Value="#263445"/><Style.Triggers><Trigger Property="AlternationIndex" Value="1"><Setter Property="Background" Value="#FAFBFC"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#F0F7F5"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#DCEFEB"/><Setter Property="Foreground" Value="#173D39"/></Trigger></Style.Triggers></Style>
 </Window.Resources>
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="224"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <Border Grid.Column="0" Background="#172033">
   <Grid Margin="16,22,16,18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Width="34" Height="34" Background="#0F766E" CornerRadius="8"><TextBlock Text="C" Foreground="White" FontSize="19" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><StackPanel Grid.Column="1" Margin="9,0,0,0" VerticalAlignment="Center"><TextBlock Text="ClawBot" Foreground="White" FontSize="17" FontWeight="SemiBold"/><TextBlock Text="实例管理器" Foreground="#8FA0B5" FontSize="11" Margin="0,2,0,0"/></StackPanel></Grid>
    <StackPanel Grid.Row="1" Margin="0,28,0,0">
     <TextBlock Text="工作区" Foreground="#74859B" FontSize="11" FontWeight="SemiBold" Margin="13,0,0,9"/>
     <RadioButton Name="NavOverview" GroupName="Navigation" Tag="overview" Style="{StaticResource NavButton}" IsChecked="True"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE80F;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="25" VerticalAlignment="Center"/><TextBlock Text="概览" VerticalAlignment="Center"/></StackPanel></RadioButton>
     <RadioButton Name="NavService" GroupName="Navigation" Tag="service" Style="{StaticResource NavButton}"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE7B8;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="25" VerticalAlignment="Center"/><TextBlock Text="实例与服务" VerticalAlignment="Center"/></StackPanel></RadioButton>
     <RadioButton Name="NavPermissions" GroupName="Navigation" Tag="permissions" Style="{StaticResource NavButton}"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="25" VerticalAlignment="Center"/><TextBlock Text="权限与能力" VerticalAlignment="Center"/></StackPanel></RadioButton>
     <RadioButton Name="NavModels" GroupName="Navigation" Tag="models" Style="{StaticResource NavButton}"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE8A5;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="25" VerticalAlignment="Center"/><TextBlock Text="模型与人设" VerticalAlignment="Center"/></StackPanel></RadioButton>
     <RadioButton Name="NavUsage" GroupName="Navigation" Tag="usage" Style="{StaticResource NavButton}"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE9D2;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="25" VerticalAlignment="Center"/><TextBlock Text="账户额度" VerticalAlignment="Center"/></StackPanel></RadioButton>
     <RadioButton Name="NavUpdates" GroupName="Navigation" Tag="updates" Style="{StaticResource NavButton}"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE895;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="25" VerticalAlignment="Center"/><TextBlock Text="软件更新" VerticalAlignment="Center"/></StackPanel></RadioButton>
    </StackPanel>
    <StackPanel Grid.Row="2"><Border Height="1" Background="#2B3850" Margin="0,0,0,14"/><TextBlock Name="SidebarSummary" Text="正在读取实例状态…" Foreground="#AAB7C7" FontSize="11" Margin="2,0,0,10"/><Button Name="Setup" Content="连接客户端" Style="{StaticResource SidebarButton}"/><TextBlock Name="VersionLabel" Text="ClawBot" Foreground="#708198" FontSize="10" HorizontalAlignment="Center" Margin="0,14,0,0"/></StackPanel>
   </Grid>
  </Border>
  <Grid Grid.Column="1" Margin="28,24,28,18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Name="PageTitle" Text="概览" FontSize="27" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="PageSubtitle" Text="查看实例状态、绑定和最近接收情况" Foreground="#64748B" Margin="0,6,0,0"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button Name="Refresh" Content="刷新状态"/><Button Name="Add" Content="＋ 新增用户" Style="{StaticResource PrimaryButton}" Margin="0"/></StackPanel></Grid>
   <Border Grid.Row="1" Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,17,0,17"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="300"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="当前实例" Foreground="#64748B" VerticalAlignment="Center" Margin="0,0,12,0"/><ComboBox Name="InstancePicker" Grid.Column="1" DisplayMemberPath="Display" VerticalAlignment="Center"/><TextBlock Name="SelectionState" Grid.Column="2" Text="选择实例后可进行服务、权限或模型操作" Foreground="#526174" VerticalAlignment="Center" Margin="18,0,0,0" TextTrimming="CharacterEllipsis"/></Grid></Border>
   <ScrollViewer Grid.Row="2" Name="PageScroller" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><Grid Name="PageHost">
    <StackPanel Name="PageOverview">
     <Grid Margin="0,0,0,14"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="18,14" Margin="0,0,10,0"><StackPanel><TextBlock Text="实例总数" Foreground="#64748B" FontSize="11"/><TextBlock Name="StatInstances" Text="—" FontSize="25" FontWeight="SemiBold" Foreground="#172033" Margin="0,5,0,0"/></StackPanel></Border><Border Grid.Column="1" Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="18,14" Margin="0,0,10,0"><StackPanel><TextBlock Text="服务运行" Foreground="#64748B" FontSize="11"/><TextBlock Name="StatRunning" Text="—" FontSize="25" FontWeight="SemiBold" Foreground="#0F766E" Margin="0,5,0,0"/></StackPanel></Border><Border Grid.Column="2" Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="18,14"><StackPanel><TextBlock Text="待扫码" Foreground="#64748B" FontSize="11"/><TextBlock Name="StatPending" Text="—" FontSize="25" FontWeight="SemiBold" Foreground="#B7791F" Margin="0,5,0,0"/></StackPanel></Border></Grid>
     <Border Background="#EAF3F1" BorderBrush="#CFE3DE" BorderThickness="1" CornerRadius="8" Padding="15,11" Margin="0,0,0,14"><TextBlock Name="Summary" Text="正在读取实例状态…" Foreground="#285B52" TextWrapping="Wrap"/></Border>
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="16,14"><StackPanel><Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="实例清单" FontSize="16" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Text="选择一行后，可从左侧进入服务、权限或模型页面。" Foreground="#718096" FontSize="11" Margin="0,4,0,0"/></StackPanel><TextBlock Grid.Column="1" Text="每4秒自动刷新" Foreground="#8794A3" FontSize="11" VerticalAlignment="Center"/></Grid><Grid><DataGrid Name="Instances" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" CanUserDeleteRows="False" SelectionMode="Single" SelectionUnit="FullRow" HeadersVisibility="Column" Height="340" AlternatingRowBackground="#FAFBFC" HorizontalScrollBarVisibility="Auto"><DataGrid.Columns><DataGridTextColumn Header="微信用户 / 实例" Binding="{Binding Display}" Width="1.7*" MinWidth="170"/><DataGridTextColumn Header="权限角色" Binding="{Binding Role}" Width="1.1*" MinWidth="115"/><DataGridTextColumn Header="模型 / 强度" Binding="{Binding Model}" Width="1.5*" MinWidth="145"/><DataGridTextColumn Header="服务状态" Binding="{Binding Service}" Width="*" MinWidth="95"/><DataGridTextColumn Header="微信绑定" Binding="{Binding Login}" Width="*" MinWidth="90"/><DataGridTextColumn Header="最近接收" Binding="{Binding Received}" Width="1.2*" MinWidth="125"/></DataGrid.Columns></DataGrid><Border Name="OverviewEmpty" Background="#FFFFFF" Padding="28" Visibility="Collapsed"><StackPanel HorizontalAlignment="Center" VerticalAlignment="Center"><TextBlock Text="还没有微信实例" FontSize="16" FontWeight="SemiBold" Foreground="#334155" HorizontalAlignment="Center"/><TextBlock Text="点击右上角“新增用户”，完成连接后由本人扫码。" Foreground="#718096" Margin="0,8,0,0"/></StackPanel></Border></Grid></StackPanel></Border>
    </StackPanel>
    <StackPanel Name="PageService" Visibility="Collapsed">
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22"><StackPanel><TextBlock Text="连接与运行" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="ServiceContext" Text="请先在顶部选择实例" Foreground="#64748B" Margin="0,6,0,16"/><TextBlock Name="Detail" Text="尚未选择实例" FontWeight="SemiBold" FontSize="15" Foreground="#263445"/><TextBlock Name="Workspace" Text="工作目录将在这里显示" Foreground="#718096" Margin="0,7,0,0" TextTrimming="CharacterEllipsis"/><TextBlock Name="Chat" Text="聊天ID将在这里显示" Foreground="#718096" Margin="0,4,0,18" TextTrimming="CharacterEllipsis"/><WrapPanel><Button Name="Connect" Content="扫码连接"/><Button Name="Start" Content="启动服务"/><Button Name="Stop" Content="停止服务" Style="{StaticResource DangerButton}" ToolTip="会中止此实例当前工作"/><Button Name="Restart" Content="重启服务" ToolTip="工作中不自动中断，请等待空闲"/></WrapPanel><TextBlock Text="停止或重启会影响此实例当前任务；其他实例不受影响。" Foreground="#7A8797" FontSize="11" Margin="0,13,0,0"/></StackPanel></Border>
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22" Margin="0,14,0,0"><StackPanel><TextBlock Text="聊天与工作目录" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Text="查看近期收发记录，或转到 Codex 工作聊天继续处理。" Foreground="#64748B" Margin="0,6,0,16"/><WrapPanel><Button Name="OpenChat" Content="查看近期聊天"/><Button Name="OpenCodex" Content="在 Codex 中打开"/><Button Name="OpenFolder" Content="打开工作目录"/></WrapPanel></StackPanel></Border>
    </StackPanel>
    <StackPanel Name="PagePermissions" Visibility="Collapsed">
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22"><StackPanel><TextBlock Text="角色与功能权限" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="PermissionContext" Text="请先在顶部选择实例" Foreground="#64748B" Margin="0,6,0,18"/><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="180"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="权限角色" Foreground="#526174" Margin="0,0,0,7"/><ComboBox Name="Role"><ComboBoxItem Content="日常用户" Tag="standard"/><ComboBoxItem Content="授权管理员" Tag="delegate"/><ComboBoxItem Content="主用户 · 完整权限" Tag="owner"/></ComboBox></StackPanel><StackPanel Grid.Column="1" Margin="26,0,0,0"><TextBlock Text="可用功能" Foreground="#526174" Margin="0,0,0,4"/><WrapPanel><CheckBox Name="Images" Content="生图"/><CheckBox Name="Files" Content="文件收发"/><CheckBox Name="Projects" Content="跨项目协作"/></WrapPanel></StackPanel></Grid><Border Height="1" Background="#E7ECF0" Margin="0,18,0,16"/><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="保存权限会在实例空闲时重启；主用户始终保留完整业务权限。" Foreground="#718096" FontSize="11" VerticalAlignment="Center"/><Button Grid.Column="1" Name="Save" Content="保存权限" Style="{StaticResource PrimaryButton}" Margin="0"/></Grid></StackPanel></Border>
    </StackPanel>
    <StackPanel Name="PageModels" Visibility="Collapsed">
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22"><StackPanel><TextBlock Text="模型与推理强度" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="ModelContext" Text="请先在顶部选择实例" Foreground="#64748B" Margin="0,6,0,18"/><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="150"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Margin="0,0,14,0"><TextBlock Text="可用模型" Foreground="#526174" Margin="0,0,0,7"/><ComboBox Name="Model" DisplayMemberPath="display_name" SelectedValuePath="model"/></StackPanel><StackPanel Grid.Column="1" Margin="0,0,14,0"><TextBlock Text="推理强度" Foreground="#526174" Margin="0,0,0,7"/><ComboBox Name="Effort"/></StackPanel><StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Bottom"><Button Name="RefreshModels" Content="读取模型"/><Button Name="SaveModel" Content="保存模型" Style="{StaticResource PrimaryButton}"/></StackPanel></Grid><TextBlock Name="ModelInfo" Text="从客户端读取模型列表及各模型支持的推理强度…" Foreground="#718096" FontSize="11" Margin="0,12,0,0" TextWrapping="Wrap"/></StackPanel></Border>
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22" Margin="0,14,0,0"><StackPanel><TextBlock Text="角色名称与参考形象" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="PersonaInfo" Text="选择实例后显示当前角色与参考图" Foreground="#64748B" Margin="0,6,0,16" TextWrapping="Wrap"/><Button Name="Persona" Content="编辑人设与名称" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left" Margin="0"/><TextBlock Text="设置只保存在本机并属于当前实例，不影响其他账号或全局模型。" Foreground="#718096" FontSize="11" Margin="0,13,0,0"/></StackPanel></Border>
    </StackPanel>
    <StackPanel Name="PageUsage" Visibility="Collapsed">
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22"><StackPanel><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="Codex 账号额度" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Text="账号级共享数据，不属于单个微信实例。" Foreground="#64748B" Margin="0,6,0,0"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><ComboBox Name="UsageBucket" Width="155" DisplayMemberPath="label" SelectedValuePath="id"/><Button Name="RefreshUsage" Content="刷新额度" Style="{StaticResource PrimaryButton}" Margin="8,0,0,0"/></StackPanel></Grid><TextBlock Name="UsageHint" Text="连接客户端后读取；未提供的额度显示未知。" FontSize="11" TextWrapping="Wrap" Foreground="#718096" Margin="0,14,0,0"/></StackPanel></Border>
     <Grid Margin="0,14,0,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="20" Margin="0,0,7,0"><StackPanel><TextBlock Text="五小时额度" FontSize="15" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="FiveUsage" Text="尚未读取" FontSize="20" FontWeight="SemiBold" Foreground="#334155" Margin="0,16,0,11"/><ProgressBar Name="FiveProgress" Minimum="0" Maximum="100" Value="0" Height="9" Foreground="#0F766E" Background="#E8EFED"/><TextBlock Name="FiveReset" Text="重置：未提供" FontSize="11" Foreground="#718096" Margin="0,12,0,0"/></StackPanel></Border><Border Grid.Column="1" Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="20" Margin="7,0,0,0"><StackPanel><TextBlock Text="每周额度" FontSize="15" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="WeekUsage" Text="尚未读取" FontSize="20" FontWeight="SemiBold" Foreground="#334155" Margin="0,16,0,11"/><ProgressBar Name="WeekProgress" Minimum="0" Maximum="100" Value="0" Height="9" Foreground="#B7791F" Background="#F4EEDF"/><TextBlock Name="WeekReset" Text="重置：未提供" FontSize="11" Foreground="#718096" Margin="0,12,0,0"/></StackPanel></Border></Grid>
    </StackPanel>
    <StackPanel Name="PageUpdates" Visibility="Collapsed">
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22"><StackPanel><TextBlock Text="正式版更新" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Name="CurrentVersion" Text="当前版本" Foreground="#64748B" Margin="0,6,0,18"/><Button Name="Update" Content="检测正式版本" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left" Margin="0"/><TextBlock Text="只检查本软件公开 GitHub 仓库的正式 Release。下载后核对大小与 SHA-256；安装前会等待当前管理操作结束。" TextWrapping="Wrap" LineHeight="22" Foreground="#718096" Margin="0,16,0,0"/></StackPanel></Border>
     <Border Background="White" BorderBrush="#DFE5E9" BorderThickness="1" CornerRadius="8" Padding="22" Margin="0,14,0,0"><StackPanel><TextBlock Text="Windows 安装包" FontSize="17" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Text="安装包内置固定 Node 运行环境和扫码依赖。源码或便携目录不会被原地覆盖；升级安装保留账号、角色、模型、人设与聊天。" TextWrapping="Wrap" LineHeight="22" Foreground="#64748B" Margin="0,7,0,0"/><TextBlock Text="macOS 与 Linux 尚未适配，不列为已支持。" Foreground="#B7791F" Margin="0,13,0,0"/></StackPanel></Border>
    </StackPanel>
   </Grid></ScrollViewer>
   <Border Grid.Row="3" Background="#EEF2F4" CornerRadius="7" Padding="12,8" Margin="0,14,0,0"><TextBlock Name="Message" Text="就绪。关闭本窗口不会停止已启动的服务。" TextWrapping="Wrap" Foreground="#526174"/></Border>
  </Grid>
 </Grid>
</Window>
'@
$script:window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$script:window.MinHeight=[Math]::Min(700,[Windows.SystemParameters]::WorkArea.Height-24)
$script:window.Height=[Math]::Min(900,[Windows.SystemParameters]::WorkArea.Height-16)
$script:window.MinWidth=[Math]::Min(1020,[Windows.SystemParameters]::WorkArea.Width-24)
$script:window.Width=[Math]::Min(1320,[Windows.SystemParameters]::WorkArea.Width-16)
if($env:CLAWBOT_MANAGER_WINDOW_SUFFIX){$script:window.Title=$script:window.Title+' · '+$env:CLAWBOT_MANAGER_WINDOW_SUFFIX}
$script:ui=@{};foreach($name in @('Refresh','Add','Summary','Instances','Detail','Workspace','Chat','Connect','Start','Stop','Restart','OpenChat','OpenFolder','Role','Images','Files','Projects','Save','Message','Model','Effort','RefreshModels','SaveModel','ModelInfo','Persona','PersonaInfo','OpenCodex','Setup','Update','UsageBucket','UsageHint','RefreshUsage','FiveUsage','FiveProgress','FiveReset','WeekUsage','WeekProgress','WeekReset','PageScroller','PageTitle','PageSubtitle','InstancePicker','SelectionState','PageOverview','PageService','PagePermissions','PageModels','PageUsage','PageUpdates','NavOverview','NavService','NavPermissions','NavModels','NavUsage','NavUpdates','StatInstances','StatRunning','StatPending','OverviewEmpty','SidebarSummary','ServiceContext','PermissionContext','ModelContext','CurrentVersion','VersionLabel')){$script:ui[$name]=$script:window.FindName($name)}
$script:ui.VersionLabel.Text='v'+$script:packageVersion
$script:ui.CurrentVersion.Text='当前源码版本 v'+$script:packageVersion+'。更新只提供正式版安装包，源码版本不自动覆盖。'
$iconPath=Join-Path $script:appRoot 'assets\clawbot.ico'
if(Test-Path -LiteralPath $iconPath){$script:window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$iconPath)}
. (Join-Path $PSScriptRoot 'Dialogs.ps1')
. (Join-Path $PSScriptRoot 'Dashboard.ps1')
function Say([string]$text,[bool]$failed=$false){$script:ui.Message.Text=$text;$script:ui.Message.Foreground=if($failed){'#B54559'}else{'#58677E'}}
function Selected {if($script:ui.InstancePicker.SelectedItem){return $script:ui.InstancePicker.SelectedItem.Raw};return $null}
function Show-Page([string]$page){
 $meta=@{
  overview=@{title='概览';subtitle='查看实例状态、绑定和最近接收情况'}
  service=@{title='实例与服务';subtitle='管理当前实例的连接、运行与工作位置'}
  permissions=@{title='权限与能力';subtitle='按实例设置角色和可用功能'}
  models=@{title='模型与人设';subtitle='选择实际可用的模型、推理强度和角色形象'}
  usage=@{title='账户额度';subtitle='只读查看当前 Codex 账号的共享额度'}
  updates=@{title='软件更新';subtitle='检查正式发行、下载并核对安装包'}
 }
 if(-not $meta.ContainsKey($page)){return}
 $script:currentPage=$page
 foreach($pair in @(@('overview','PageOverview'),@('service','PageService'),@('permissions','PagePermissions'),@('models','PageModels'),@('usage','PageUsage'),@('updates','PageUpdates'))){$script:ui[$pair[1]].Visibility=if($pair[0] -eq $page){'Visible'}else{'Collapsed'}}
 $script:ui.PageTitle.Text=$meta[$page].title;$script:ui.PageSubtitle.Text=$meta[$page].subtitle
 foreach($pair in @(@('overview','NavOverview'),@('service','NavService'),@('permissions','NavPermissions'),@('models','NavModels'),@('usage','NavUsage'),@('updates','NavUpdates'))){$script:ui[$pair[1]].IsChecked=$pair[0] -eq $page}
 $scopeText=if($page -eq 'usage'){'账号级共享数据 · 与当前实例选择无关'}elseif($page -eq 'updates'){'软件级设置 · 与当前实例选择无关'}else{$null}
 $script:ui.InstancePicker.IsEnabled=(-not $scopeText -and $script:rows.Count -gt 0)
 if($scopeText){$script:ui.SelectionState.Text=$scopeText}
 $script:ui.PageScroller.ScrollToTop()
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
 $job=[pscustomobject]@{Action=$request.action;Name=$request.name;UserFeedback=[bool]$request.user_feedback;Process=$proc;Output=$proc.StandardOutput.ReadToEndAsync();Error=$proc.StandardError.ReadToEndAsync();Started=[datetime]::UtcNow;QrWindow=$null;QrImage=$null;QrHint=$null;QrStamp=[datetime]::MinValue}
 [void]$script:jobs.Add($job)
 if(-not $readOnly){Say ('正在执行：'+$request.action+' · '+$request.name+'。窗口可以继续使用。')}
 if($request.action -eq 'connect'){Show-Qr $job}
 return $true
}
function Show-Qr($job){
 [xml]$qrXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="微信扫码连接" Width="450" Height="560" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="#F3F5F7" FontFamily="Microsoft YaHei UI"><StackPanel Margin="24"><TextBlock Text="请使用该用户自己的微信扫码" FontSize="18" FontWeight="SemiBold" Foreground="#172033" TextAlignment="Center"/><Image Name="QrImage" Width="350" Height="350" Margin="0,15,0,10"/><TextBlock Name="QrHint" Text="正在准备二维码…" TextAlignment="Center" TextWrapping="Wrap" Foreground="#526174"/><TextBlock Text="关闭此窗口不会取消等待；二维码约5分钟后过期。" TextAlignment="Center" TextWrapping="Wrap" FontSize="11" Margin="0,14,0,0" Foreground="#718096"/></StackPanel></Window>
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
 $scopeText=if($script:currentPage -eq 'usage'){'账号级共享数据 · 与当前实例选择无关'}elseif($script:currentPage -eq 'updates'){'软件级设置 · 与当前实例选择无关'}else{$null}
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
 $script:ui.ServiceContext.Text='当前实例：'+$row.label+' ('+$row.name+')'
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
  [pscustomobject]@{Display=$row.label+'  ('+$row.name+')';Role=$row.policy.role_label;Persona=$row.persona.assistant_name;Model=$row.model+' / '+$(if($row.reasoning_effort){$row.reasoning_effort}else{'不适用'});Service=$phase;Login=$(if($row.logged_in){'已绑定'}else{'待扫码'});Queue=$row.queued;Received=$received;Desktop=$(if($row.project_tools_connected){'已连接'}elseif($row.running){'待连接 / 检查'}else{'服务未运行'});Raw=$row}
 })
 $pick=$items|Where-Object {$_.Raw.name -eq $selected}|Select-Object -First 1
 $script:bindingSelection=$true
 try{
  $script:ui.Instances.ItemsSource=$items;$script:ui.InstancePicker.ItemsSource=$items
  if($pick){$script:ui.Instances.SelectedItem=$pick;$script:ui.InstancePicker.SelectedItem=$pick}elseif($items.Count){$script:ui.Instances.SelectedIndex=0;$script:ui.InstancePicker.SelectedIndex=0}else{$script:ui.Instances.SelectedItem=$null;$script:ui.InstancePicker.SelectedItem=$null}
 }finally{$script:bindingSelection=$false}
 $online=@($script:rows|Where-Object {$_.running}).Count
 $pending=@($script:rows|Where-Object {-not $_.logged_in}).Count
 $script:ui.StatInstances.Text=[string]$items.Count;$script:ui.StatRunning.Text=[string]$online;$script:ui.StatPending.Text=[string]$pending
 $script:ui.SidebarSummary.Text=('{0}/{1} 个服务运行' -f $online,$items.Count)
 $script:ui.Summary.Text=if($items.Count){('{0} 个实例　·　{1} 个服务运行中　·　状态更新 {2}' -f $items.Count,$online,([datetime]::Now.ToString('HH:mm:ss')))}else{'尚未新增微信实例。连接客户端后，点击“新增用户”创建 primary 并本人扫码。'}
 $script:ui.OverviewEmpty.Visibility=if($items.Count){'Collapsed'}else{'Visible'}
 $script:nextName=$value.next_name;Update-Selection
}
function Add-User {
 if(-not $script:setupState.ready){Show-Setup;return}
 [xml]$newXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="新增独立微信用户" Width="430" Height="285" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI" Background="#F3F5F7"><StackPanel Margin="24"><TextBlock Name="Name" FontSize="18" FontWeight="SemiBold" Foreground="#172033"/><TextBlock Text="显示名称" Margin="0,16,0,7" Foreground="#526174"/><TextBox Name="Label" Padding="9" MaxLength="60" BorderBrush="#D4DCE3"/><TextBlock Text="独立登录、独立工作目录；默认开放聊天、生图、文件与跨项目协作。" TextWrapping="Wrap" Foreground="#64748B" Margin="0,12,0,15"/><Button Name="Create" Content="创建并扫码连接" Padding="12,8" HorizontalAlignment="Right" Background="#0F766E" BorderBrush="#0F766E" Foreground="White"/></StackPanel></Window>
'@
 $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($newXaml));$dialog.Owner=$script:window
 $name=$script:nextName;if(-not $name){$name='primary'}
 $dialog.FindName('Name').Text='新增实例：'+$name;$dialog.FindName('Label').Text=$name
 $dialog.Tag=@{Name=$name;Label=$dialog.FindName('Label')}
 $dialog.FindName('Create').Add_Click({$dlg=$this.Parent.Parent;$label=$dlg.Tag.Label.Text.Trim();if(-not $label){return};Begin-JobCommand @{action='create';name=$dlg.Tag.Name;label=$label};$dlg.Close()})
 [void]$dialog.ShowDialog()
}
foreach($pair in @(@('NavOverview','overview'),@('NavService','service'),@('NavPermissions','permissions'),@('NavModels','models'),@('NavUsage','usage'),@('NavUpdates','updates'))){$script:ui[$pair[0]].Tag=$pair[1];$script:ui[$pair[0]].Add_Click({if($this.IsChecked){Show-Page ([string]$this.Tag)}})}
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
$script:ui.Refresh.Add_Click({$script:lastRefresh=[datetime]::MinValue})
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
   if(-not $job.Process.HasExited){continue};if(-not $job.Output.IsCompleted -or -not $job.Error.IsCompleted){continue}
   $text=$job.Output.Result;$result=$null
   foreach($line in ($text -split "`r?`n")){if($line.Trim().StartsWith('{')){try{$result=$line|ConvertFrom-Json}catch{}}}
   if($job.QrWindow){$job.QrWindow.Close()}
   [void]$script:jobs.Remove($job);$job.Process.Dispose()
   if(-not $result -or $result.status -eq 'error'){
    $code=if($result.code){$result.code}else{'LOCAL_OPERATION_FAILED'};$detail=if($script:errors.ContainsKey($code)){$script:errors[$code]}else{'操作未完成：'+$code}
    if($job.Action -eq 'history' -and $script:chatWindows.ContainsKey($job.Name)){$script:chatWindows[$job.Name].Window.FindName('Hint').Text=$detail}elseif($job.Action -eq 'setup-status'){
     Complete-SetupCheck ([pscustomobject]@{ready=$false;prompt='';connection_error=$code;checked_at=[datetime]::UtcNow;bundled_node=$false;node_version='';client_verified=$false}) $job.UserFeedback
    }elseif($job.Action -eq 'usage'){$script:ui.RefreshUsage.IsEnabled=$true;$script:ui.RefreshUsage.Content='刷新额度';$script:ui.UsageHint.Text='读取额度失败，请稍后刷新。';Say $detail $true
    }elseif($job.Action -like '*update'){Fail-Update $detail}else{Say $detail $true}
   }elseif($job.Action -eq 'snapshot'){Apply-Snapshot $result
   }elseif($job.Action -eq 'setup-status'){Complete-SetupCheck $result $job.UserFeedback
   }elseif($job.Action -eq 'usage'){Apply-Usage $result
   }elseif($job.Action -eq 'check-update'){Apply-UpdateCheck $result
   }elseif($job.Action -eq 'download-update'){Apply-UpdateDownload $result
   }elseif($job.Action -eq 'install-update' -and $result.status -eq 'update_handoff'){if($script:updateDialog){$script:updateDialog.Close()};$script:window.Close();return
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
  if($script:installPending){if(-not $script:jobs.Count){$script:installPending=$false;[void](Begin-JobCommand @{action='install-update';name='';version=$script:downloadState.version;manager_pid=$PID})};return}
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
 foreach($page in @('overview','service','permissions','models','usage','updates')){Show-Page $page;if($script:currentPage -ne $page){throw 'PAGE_SWITCH_FAILED'}}
 Show-Page 'overview'
 $a=New-PersonaDialog;$b=New-ChatDialog;$c=New-SetupDialog;$d=New-UpdateDialog
 if(-not $a -or -not $b -or -not $c -or -not $d){throw 'DIALOG_LOAD_FAILED'}
 $a.Close();$b.Close();$c.Close();$d.Close()
 [Console]::WriteLine('WPF_LOAD_OK: sidebar pages, instance picker, manager, persona, chat, setup, update');exit 0
}
$script:timer.Start();[void]$script:window.ShowDialog()
