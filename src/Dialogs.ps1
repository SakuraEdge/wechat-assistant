function Read-Dialog([string]$source){
 $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$source));if($script:window.IsLoaded){$dialog.Owner=$script:window}
 if($script:window.Icon){$dialog.Icon=$script:window.Icon};return $dialog
}
function New-PersonaDialog {
 return Read-Dialog @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="人设与名称" Width="720" Height="790" MinWidth="620" MinHeight="680" WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI" Background="#F4F6FB">
 <Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel><TextBlock Name="Heading" FontSize="22" FontWeight="SemiBold" Foreground="#26324A"/><TextBlock Text="独立保存此实例的称呼、说话风格与参考图" Foreground="#69758C" Margin="0,7,0,18"/></StackPanel>
  <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="20"/><ColumnDefinition/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="实例显示名称（管理器列表）"/><TextBox Name="DisplayName" MaxLength="60" Padding="9" Margin="0,7,0,16"/></StackPanel><StackPanel Grid.Column="2"><TextBlock Text="聊天角色名称"/><TextBox Name="AssistantName" MaxLength="60" Padding="9" Margin="0,7,0,16"/></StackPanel></Grid>
  <Grid Grid.Row="2"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><TextBlock Text="人设描述与说话风格" Margin="0,0,0,7"/><TextBox Grid.Row="1" Name="Description" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" MaxLength="8000" Padding="12" MinHeight="130"/></Grid>
  <StackPanel Grid.Row="3" Margin="0,16,0,0"><TextBlock Text="参考形象（最多4张，PNG / JPEG / WebP，每张10MiB）"/><ListBox Name="References" Height="170" Margin="0,8,0,8" ScrollViewer.HorizontalScrollBarVisibility="Auto"><ListBox.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ListBox.ItemsPanel><ListBox.ItemTemplate><DataTemplate><StackPanel Width="138" Margin="6"><Image Source="{Binding path}" Height="116" Stretch="Uniform"/><TextBlock Text="{Binding label}" TextTrimming="CharacterEllipsis" Margin="0,5,0,0"/></StackPanel></DataTemplate></ListBox.ItemTemplate></ListBox><WrapPanel><Button Name="AddReference" Content="添加参考图" Padding="12,7" Margin="0,0,8,0"/><Button Name="RemoveReference" Content="移除选中" Padding="12,7" Margin="0,0,8,0"/><Button Name="Reset" Content="恢复默认人设与形象" Padding="12,7"/></WrapPanel></StackPanel>
  <StackPanel Grid.Row="4" Margin="0,15,0,0"><TextBlock Name="Hint" Text="保存时在空闲状态重启此实例；私人设置与图片只保存在本机。" Foreground="#69758C" TextWrapping="Wrap"/><Button Name="SavePersona" Content="保存此实例的人设" Padding="18,10" Margin="0,12,0,0" HorizontalAlignment="Right" Background="#6454D9" Foreground="White"/></StackPanel>
 </Grid>
</Window>
'@
}
function Show-Persona {
 $row=Selected;if(-not $row -or -not $row.persona){return}
 $dialog=New-PersonaDialog;$p=$row.persona
 $refs=[Collections.ObjectModel.ObservableCollection[object]]::new();foreach($item in @($p.references)){$refs.Add([pscustomobject]@{path=$item.path;label=$item.label})}
 $dialog.FindName('Heading').Text='人设与名称 · '+$row.name
 $dialog.FindName('DisplayName').Text=$row.label;$dialog.FindName('AssistantName').Text=$p.assistant_name;$dialog.FindName('Description').Text=$p.description
 $dialog.FindName('References').ItemsSource=$refs
 $dialog.Tag=@{Name=$row.name;Refs=$refs}
 $dialog.FindName('AddReference').Add_Click({
  $dlg=[Windows.Window]::GetWindow($this);$picker=[Microsoft.Win32.OpenFileDialog]::new();$picker.Filter='参考图片|*.png;*.jpg;*.jpeg;*.webp';$picker.Multiselect=$true
  if($picker.ShowDialog($dlg)){
   if($dlg.Tag.Refs.Count+$picker.FileNames.Count -gt 4){$dlg.FindName('Hint').Text='最多4张，请先移除多余的参考图。';return}
   foreach($file in $picker.FileNames){$dlg.Tag.Refs.Add([pscustomobject]@{path=$file;label=[IO.Path]::GetFileName($file)})}
  }
 })
 $dialog.FindName('RemoveReference').Add_Click({$dlg=[Windows.Window]::GetWindow($this);$item=$dlg.FindName('References').SelectedItem;if($item){[void]$dlg.Tag.Refs.Remove($item)}})
 $dialog.FindName('Reset').Add_Click({
  $dlg=[Windows.Window]::GetWindow($this);$p=$script:defaultPersona;if(-not $p){return}
  $dlg.FindName('AssistantName').Text=$p.assistant_name;$dlg.FindName('Description').Text=$p.description;$dlg.Tag.Refs.Clear()
  foreach($item in @($p.references)){$dlg.Tag.Refs.Add([pscustomobject]@{path=$item.path;label=$item.label})}
  $dlg.FindName('Hint').Text='已恢复默认草稿，点击保存后生效；实例显示名称保留。'
 })
 $dialog.FindName('SavePersona').Add_Click({
  $dlg=[Windows.Window]::GetWindow($this)
  if(-not $dlg.FindName('DisplayName').Text.Trim() -or -not $dlg.FindName('AssistantName').Text.Trim() -or -not $dlg.FindName('Description').Text.Trim()){$dlg.FindName('Hint').Text='请填写实例名称、角色名称和人设描述。';return}
  $started=Begin-JobCommand @{action='persona';name=$dlg.Tag.Name;display_name=$dlg.FindName('DisplayName').Text;assistant_name=$dlg.FindName('AssistantName').Text;description=$dlg.FindName('Description').Text;references=@($dlg.Tag.Refs | ForEach-Object { @{path=$_.path;label=$_.label} })}
  if($started){$dlg.Close()}
 })
 [void]$dialog.ShowDialog()
}
function New-ChatDialog {
 return Read-Dialog @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="实例聊天" Width="820" Height="740" MinWidth="600" MinHeight="500" WindowStartupLocation="CenterOwner" Background="#F4F6FB" FontFamily="Microsoft YaHei UI"><Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Name="Heading" FontSize="22" FontWeight="SemiBold" Foreground="#26324A"/><TextBlock Name="Hint" Grid.Row="1" Text="正在读取此实例的聊天记录…" Foreground="#69758C" TextWrapping="Wrap" Margin="0,10,0,14"/><TextBox Name="Messages" Grid.Row="2" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="16" FontSize="14" BorderBrush="#DCE1ED"/><WrapPanel Grid.Row="3" Margin="0,14,0,0"><Button Name="RefreshHistory" Content="刷新聊天" Padding="14,9" Margin="0,0,10,0"/><Button Name="OpenCodex" Content="在 Codex 中打开工作聊天" Padding="14,9"/><TextBlock Text="   只读查看 · 每4秒刷新" Foreground="#758096" VerticalAlignment="Center"/></WrapPanel></Grid></Window>
'@
}
$script:chatWindows=@{}
function Show-Chat {
 $row=Selected;if(-not $row){return}
 if($script:chatWindows.ContainsKey($row.name)){[void]$script:chatWindows[$row.name].Window.Activate();return}
 $dialog=New-ChatDialog;$dialog.Title='聊天 · '+$row.label+' ('+$row.name+')';$dialog.FindName('Heading').Text=$row.label+' · '+$row.persona.assistant_name;$dialog.Tag=$row.name
 $script:chatWindows[$row.name]=@{Window=$dialog;LastRefresh=[datetime]::MinValue;LastText='';AssistantName=$row.persona.assistant_name}
 $dialog.FindName('RefreshHistory').Add_Click({$dlg=[Windows.Window]::GetWindow($this);$script:chatWindows[$dlg.Tag].LastRefresh=[datetime]::MinValue})
 $dialog.FindName('OpenCodex').Add_Click({$dlg=[Windows.Window]::GetWindow($this);[void](Begin-JobCommand @{action='open-chat';name=$dlg.Tag})})
 $dialog.Add_Closed({$script:chatWindows.Remove($this.Tag)})
 $dialog.Show()
}
function Apply-History($value){
 if(-not $script:chatWindows.ContainsKey($value.name)){return};$entry=$script:chatWindows[$value.name];$dlg=$entry.Window
 $dlg.FindName('Hint').Text=if($value.source -eq 'legacy-summary'){'旧版近期摘要，非完整聊天历史。升级后新收发的消息会自动记录；此窗口仅查看。'}else{'微信最近最多300条收发记录；“已提交”不代表手机已读。此窗口仅查看。'}
 $parts=@(foreach($item in @($value.messages)){
  $speaker=if($item.role -eq 'user'){'微信用户'}else{$entry.AssistantName}
  $time=if($item.at){([datetime]$item.at).ToLocalTime().ToString('MM-dd HH:mm:ss')}else{'旧版摘要'}
  $delivery=switch($item.delivery){'received'{'已接收'};'sent'{'已提交'};'unknown'{'提交结果未知'};'failed'{'提交失败'};'attempting'{'提交中'};default{'摘要'}}
  $attachments=@($item.attachments|ForEach-Object {'['+$_.kind+'] '+$_.name}) -join "`r`n"
  $speaker+'  '+$time+'  · '+$delivery+"`r`n"+$item.text+$(if($attachments){"`r`n"+$attachments})
 })
 $text=if($parts.Count){$parts -join "`r`n`r`n────────────────────────`r`n`r`n"}else{'暂无聊天记录。该实例接收消息后会在这里显示。'}
 if($text -ne $entry.LastText){$box=$dlg.FindName('Messages');$atEnd=$box.VerticalOffset -ge $box.ExtentHeight-$box.ViewportHeight-25;$box.Text=$text;if($atEnd -or -not $entry.LastText){$box.ScrollToEnd()};$entry.LastText=$text}
}
