function Reset-Time($value){if(-not $value){return '未提供'};try{return ([datetime]$value).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz')}catch{return '未提供'}}
function Usage-Text($value){
 if(-not $value -or $null -eq $value.remaining_percent){return '当前账号未提供此额度'}
 return ('剩余 {0:0.#}%　·　已用 {1:0.#}%' -f $value.remaining_percent,$value.used_percent)
}
function Update-UsageView {
 $bucket=$script:ui.UsageBucket.SelectedItem
 foreach($pair in @(@('Five','five_hour'),@('Week','weekly'))){
  $value=if($bucket){$bucket.($pair[1])}else{$null}
  $script:ui[$pair[0]+'Usage'].Text=Usage-Text $value
  $script:ui[$pair[0]+'Reset'].Text='重置：'+$(if($value){Reset-Time $value.resets_at}else{'未提供'})
  $script:ui[$pair[0]+'Progress'].Value=if($value -and $null -ne $value.remaining_percent){$value.remaining_percent}else{0}
  $script:ui[$pair[0]+'Progress'].Opacity=if($value -and $null -ne $value.remaining_percent){1}else{0.25}
 }
}
function Apply-Usage($result){
 $selected=$script:ui.UsageBucket.SelectedValue;$script:usageState=$result
 $script:ui.UsageBucket.ItemsSource=@($result.buckets)
 $target=if(@($result.buckets|Where-Object {$_.id -eq $selected}).Count){$selected}else{$result.preferred_id}
 $script:ui.UsageBucket.SelectedValue=$target;Update-UsageView
 $time=([datetime]$result.at).ToLocalTime().ToString('HH:mm:ss')
 $script:ui.UsageHint.Text=if($result.available){'当前Codex账号共享额度 · 本机时间 · 更新于 '+$time}else{'当前账号或提供商暂未提供可读取的额度 · '+$time+' · 可稍后刷新'}
 $script:ui.RefreshUsage.IsEnabled=$true;$script:ui.RefreshUsage.Content='刷新额度'
}
function New-UpdateDialog {
 return Read-Dialog @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="检测更新" Width="650" Height="440" MinWidth="600" MinHeight="400" WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI" Background="#F3F5F7"><Grid Margin="26"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Text="ClawBot实例管理器 · 软件更新" FontSize="22" FontWeight="SemiBold" Foreground="#172033"/><Border Grid.Row="1" Background="#E9F2F0" CornerRadius="8" Padding="15" Margin="0,18,0,14"><TextBlock Name="UpdateHint" Text="正在检查GitHub正式版本，请稍候…" TextWrapping="Wrap" LineHeight="24" Foreground="#285B52"/></Border><TextBlock Grid.Row="2" Name="UpdateDetails" Text="仅检查 SakuraEdge/wechat-assistant 的正式Release。下载后核对大小与SHA-256，点击安装才会执行安装程序。&#10;&#10;安装版：将停止此安装目录的空闲服务并关闭管理窗口，安装完成后恢复服务。忙碌时请等待任务完成。&#10;&#10;源码/便携版：可下载安装包，在独立安装目录使用，保留原目录。" TextWrapping="Wrap" LineHeight="24" Foreground="#64748B"/><WrapPanel Grid.Row="3" Margin="0,15,0,0"><Button Name="CheckUpdateAgain" Content="重新检测" Padding="12,9" Margin="0,0,8,0"/><Button Name="DownloadUpdate" Content="下载更新" IsEnabled="False" Padding="12,9" Margin="0,0,8,0"/><Button Name="InstallUpdate" Content="安装更新" IsEnabled="False" Padding="12,9" Margin="0,0,8,0" Background="#0F766E" BorderBrush="#0F766E" Foreground="White"/><Button Name="OpenDownload" Content="打开下载目录" IsEnabled="False" Padding="12,9" Margin="0,0,8,0"/><Button Name="CloseUpdate" Content="关闭" Padding="12,9"/></WrapPanel></Grid></Window>
'@
}
function Update-Hint([string]$text){Say $text;if($script:updateDialog -and $script:updateDialog.IsVisible){$script:updateDialog.FindName('UpdateHint').Text=$text}}
function Begin-UpdateCheck {
 if(Begin-JobCommand @{action='check-update';name=''}){Update-Hint '正在检测GitHub正式版本，请稍候…';if($script:updateDialog){$script:updateDialog.FindName('CheckUpdateAgain').IsEnabled=$false;$script:updateDialog.FindName('DownloadUpdate').IsEnabled=$false;$script:updateDialog.FindName('InstallUpdate').IsEnabled=$false}}
}
function Apply-UpdateCheck($result){
 $script:updateState=$result;$dialog=$script:updateDialog
 $text=if($result.available){'发现新版本 '+$result.latest_version+'（当前 '+$result.current_version+'），安装包约 '+[math]::Round($result.asset.size/1MB,1)+' MiB。点击“下载更新”继续。'}elseif($result.reason -eq 'NO_PUBLISHED_RELEASE'){'GitHub暂未提供正式Release。当前版本 '+$result.current_version+'。'}elseif($result.current_version -eq $result.latest_version){'检测完成：当前 '+$result.current_version+' 已是最新正式版本。'}else{'检测完成：当前 '+$result.current_version+' 高于GitHub已发布版本 '+$result.latest_version+'，无需降级。'}
 Update-Hint $text
 if($dialog -and $dialog.IsVisible){$dialog.FindName('CheckUpdateAgain').IsEnabled=$true;$dialog.FindName('DownloadUpdate').IsEnabled=[bool]$result.available;$dialog.FindName('InstallUpdate').IsEnabled=[bool]($result.available -and $result.installed -and $script:downloadState.version -eq $result.latest_version)}
}
function Apply-UpdateDownload($result){
 $script:downloadState=$result;$dialog=$script:updateDialog
 Update-Hint ('版本 '+$result.version+' 下载完成，文件大小与SHA-256校验通过。'+$(if($script:updateState.installed){'点击“安装更新”继续。'}else{'当前为源码/便携目录，请打开下载目录，在独立目录安装。'}))
 if($dialog -and $dialog.IsVisible){$dialog.FindName('CheckUpdateAgain').IsEnabled=$true;$dialog.FindName('DownloadUpdate').IsEnabled=$true;$dialog.FindName('OpenDownload').IsEnabled=$true;$dialog.FindName('InstallUpdate').IsEnabled=[bool]$script:updateState.installed}
}
function Show-Update {
 if($script:updateDialog -and $script:updateDialog.IsVisible){[void]$script:updateDialog.Activate();return}
 $dialog=New-UpdateDialog;$script:updateDialog=$dialog
 $dialog.FindName('CloseUpdate').Add_Click({[Windows.Window]::GetWindow($this).Close()})
 $dialog.FindName('CheckUpdateAgain').Add_Click({Begin-UpdateCheck})
 $dialog.FindName('DownloadUpdate').Add_Click({
  if(-not $script:updateState.available){return}
  if(Begin-JobCommand @{action='download-update';name='';version=$script:updateState.latest_version}){$this.IsEnabled=$false;$script:updateDialog.FindName('CheckUpdateAgain').IsEnabled=$false;Update-Hint '正在下载安装包并校验，请稍候。关闭此窗口不会取消下载。'}
 })
 $dialog.FindName('OpenDownload').Add_Click({if($script:downloadState.file){Start-Process -FilePath explorer.exe -ArgumentList ('/select,"'+$script:downloadState.file+'"') -WindowStyle Normal}})
 $dialog.FindName('InstallUpdate').Add_Click({
  if(-not $script:updateState.installed -or -not $script:downloadState){return}
  $answer=[Windows.MessageBox]::Show($script:updateDialog,'将停止此安装目录的空闲服务、关闭管理器并打开安装向导。安装完成后恢复这些服务；其他目录的服务不受影响。继续安装？','安装更新',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question,[Windows.MessageBoxResult]::No)
  if($answer -eq [Windows.MessageBoxResult]::Yes){$script:installPending=$true;$this.IsEnabled=$false;Update-Hint '正在等待当前管理操作结束，随后检查空闲服务并准备安装…'}
 })
 Begin-UpdateCheck
 [void]$dialog.ShowDialog();$script:updateDialog=$null
}
function Fail-Update([string]$message){
 Update-Hint $message;$script:installPending=$false
 if($script:updateDialog -and $script:updateDialog.IsVisible){$dialog=$script:updateDialog;$dialog.FindName('CheckUpdateAgain').IsEnabled=$true;$dialog.FindName('DownloadUpdate').IsEnabled=[bool]$script:updateState.available;$dialog.FindName('InstallUpdate').IsEnabled=[bool]($script:updateState.installed -and $script:downloadState)}
}
