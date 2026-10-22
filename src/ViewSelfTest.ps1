# Runs only under Manager.ps1 -SelfTest. Fixtures never start services or call the controller.
$fixture=@'
{"instances":[{"name":"primary","label":"主实例","running":true,"logged_in":true,"phase":"listening","queued":0,"model":"example-model","reasoning_effort":"high","workspace":"fixture","thread_id":"fixture-primary","persona":{"assistant_name":"助手","references":[]},"policy":{"role":"owner","role_label":"主用户","capabilities":{"images":true,"files":true,"projects":true}}},{"name":"user-2","label":"测试用户","running":true,"logged_in":true,"phase":"listening","queued":3,"model":"other-model","reasoning_effort":"medium","workspace":"fixture","thread_id":"fixture-second","persona":{"assistant_name":"助手","references":[]},"policy":{"role":"standard","role_label":"日常用户","capabilities":{"images":true,"files":true,"projects":true}}}],"next_name":"user-3"}
'@ | ConvertFrom-Json
Apply-Snapshot $fixture
if($script:ui.StatPending.Text -ne '3' -or $script:ui.ServiceHealth.Text -ne '服务运行正常'){throw 'HOME_SNAPSHOT_FAILED'}
if(-not (Select-Instance 'user-2') -or (Selected).name -ne 'user-2'){throw 'ROW_SELECTION_FAILED'}
$rowBeforeRefresh=$script:ui.Instances.SelectedItem
Apply-Snapshot $fixture
if((Selected).name -ne 'user-2' -or $script:ui.Instances.SelectedItem.Raw.name -ne 'user-2'){throw 'REFRESH_SELECTION_FAILED'}
if(-not [object]::ReferenceEquals($rowBeforeRefresh,$script:ui.Instances.SelectedItem)){throw 'UNCHANGED_ROW_WAS_REBUILT'}
foreach($page in @('service','models','permissions','updates','overview')){
 Show-Page $page
 $expected=if($page -in @('service','models','permissions')){'Visible'}else{'Collapsed'}
 if([string]$script:ui.InstanceScope.Visibility -ne $expected -or (Selected).name -ne 'user-2'){throw 'PAGE_SCOPE_OR_SELECTION_FAILED'}
}
Show-Page 'usage'
if($script:currentPage -ne 'overview' -or $script:window.FindName('NavUsage')){throw 'LEGACY_USAGE_ROUTE_FAILED'}
$bucket=[pscustomobject]@{id='one';label='One';five_hour=[pscustomobject]@{remaining_percent=72;used_percent=28;resets_at='2026-10-22T10:30:00Z'};weekly=$null}
$usage=[pscustomobject]@{buckets=@($bucket);preferred_id='one';available=$true;at='2026-10-22T06:30:00Z'}
Apply-Usage $usage
if($script:ui.FiveUsage.Text -ne '72%' -or $script:ui.FiveProgress.Value -ne 28 -or $script:ui.FiveUsed.Text -ne '已用 28%'){throw 'USAGE_USED_REMAINING_FAILED'}
if($script:ui.WeekUsage.Text -ne '—' -or $script:ui.WeekCaption.Text -ne '未提供' -or $script:ui.WeekProgress.Opacity -ge 1){throw 'UNKNOWN_USAGE_FAILED'}
if([string]$script:ui.UsageBucket.Visibility -ne 'Collapsed'){throw 'SINGLE_BUCKET_FAILED'}
$second=[pscustomobject]@{id='two';label='Two';five_hour=[pscustomobject]@{remaining_percent=0;used_percent=100;resets_at=$null};weekly=[pscustomobject]@{remaining_percent=100;used_percent=0;resets_at=$null}}
$usage.buckets=@($bucket,$second);Apply-Usage $usage
$script:ui.UsageBucket.SelectedValue='two';Update-UsageView
Apply-Usage $usage
if($script:ui.FiveUsage.Text -ne '0%' -or $script:ui.FiveProgress.Value -ne 100 -or $script:ui.WeekUsage.Text -ne '100%' -or $script:ui.WeekProgress.Value -ne 0){throw 'ZERO_FULL_USAGE_FAILED'}
if($script:ui.UsageBucket.SelectedValue -ne 'two' -or [string]$script:ui.UsageBucket.Visibility -ne 'Visible'){throw 'BUCKET_PRESERVATION_FAILED'}
$second.five_hour.used_percent=$null;Update-UsageView
if($script:ui.FiveProgress.Opacity -ge 1){throw 'MISSING_USED_PERCENT_APPEARS_KNOWN'}
foreach($buckets in @($null,@())){
 $usage.buckets=$buckets;Apply-Usage $usage
 if($script:ui.UsageBucket.Items.Count -ne 0 -or $script:ui.FiveCaption.Text -ne '未提供'){throw 'EMPTY_BUCKET_FAILED'}
}
Show-Page 'overview'
foreach($size in @(@(1020,700),@(1320,900),@(1700,1000))){
 $script:window.Content.Measure([Windows.Size]::new($size[0],$size[1]))
 $script:window.Content.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]))
 $script:window.Content.UpdateLayout()
 if($script:ui.Instances.ActualWidth -lt 650 -or $script:ui.FiveProgress.ActualWidth -lt 200){throw 'HOME_MINIMUM_LAYOUT_FAILED'}
}
function Find-ViewActionButtons($element){
 if($element -is [Windows.Controls.Button] -and $element.Tag -in @('row-chat','row-menu')){Write-Output $element}
 for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($element);$i++){Find-ViewActionButtons ([Windows.Media.VisualTreeHelper]::GetChild($element,$i))}
}
$viewButtons=@(Find-ViewActionButtons $script:ui.Instances)
if($viewButtons.Count -ne 4){throw 'ROW_BUTTONS_NOT_RENDERED'}
$savedChat=${function:Show-Chat};$savedMenu=${function:Show-InstanceMenu};$script:viewActionTarget=''
try{
 function Show-Chat {$script:viewActionTarget='chat:'+(Selected).name}
 function Show-InstanceMenu($button,[string]$name){$script:viewActionTarget='menu:'+$name}
 foreach($tag in @('row-chat','row-menu')){
  [void](Select-Instance 'primary')
  $button=$viewButtons|Where-Object {$_.Tag -eq $tag -and $_.DataContext.Raw.name -eq 'user-2'}|Select-Object -First 1
  $click=[Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent,$button);$click.Handled=$true
  $button.RaiseEvent($click)
  $expected=if($tag -eq 'row-chat'){'chat:user-2'}else{'menu:user-2'}
  if($script:viewActionTarget -ne $expected -or (Selected).name -ne 'user-2'){throw ('ROW_ACTION_TARGET_FAILED: '+$tag+' / '+$script:viewActionTarget)}
 }
 $menu=New-InstanceMenu 'user-2'
 Apply-Snapshot $fixture;[void](Select-Instance 'primary')
 $chatItem=$menu.Items|Where-Object {$_.Tag.Action -eq 'chat'}|Select-Object -First 1
 $chatItem.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent,$chatItem))
 if($script:viewActionTarget -ne 'chat:user-2' -or (Selected).name -ne 'user-2'){throw 'MENU_ACTION_AFTER_REFRESH_FAILED'}
}finally{Set-Item Function:Show-Chat $savedChat;Set-Item Function:Show-InstanceMenu $savedMenu}
$fixture.instances[1].running=$false;Apply-Snapshot $fixture
if($script:ui.ServiceHealth.Text -ne '有实例尚未运行'){throw 'SERVICE_STOPPED_STATE_FAILED'}
$fixture.instances=@();Apply-Snapshot $fixture
if([string]$script:ui.OverviewEmpty.Visibility -ne 'Visible' -or $script:ui.StatInstances.Text -ne '0' -or (Selected)){throw 'EMPTY_HOME_FAILED'}
