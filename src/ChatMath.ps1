# Loaded locally: chat text never enters a browser or remote formula service.
$script:chatMathReady=$null
function Initialize-ChatMath {
 if($null -ne $script:chatMathReady){return $script:chatMathReady}
 try{
  $directory=Join-Path $script:appRoot 'assets\math'
  $pins=Get-Content -LiteralPath (Join-Path $directory 'dependencies.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($name in @('XamlMath.Shared.dll','WpfMath.dll')){
   $pin=@($pins.files | Where-Object {$_.path -ceq $name})
   $file=Join-Path $directory $name
   $stream=[IO.File]::OpenRead($file);$algorithm=[Security.Cryptography.SHA256]::Create()
   try{$hash=([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$algorithm.Dispose()}
   if($pin.Count -ne 1 -or (Get-Item -LiteralPath $file).Length -ne $pin[0].bytes -or $hash -ine $pin[0].sha256){throw 'CHAT_MATH_DEPENDENCY_MISMATCH'}
   [void][Reflection.Assembly]::LoadFrom($file)
  }
  if(-not ('ClawBot.ChatMath.Renderer' -as [type])){
   $references=@([Windows.Controls.RichTextBox].Assembly.Location,[Windows.Media.Brush].Assembly.Location,[Windows.DependencyObject].Assembly.Location,(Join-Path $directory 'WpfMath.dll'),(Join-Path $directory 'XamlMath.Shared.dll'),'System.dll','System.Core.dll','System.Xaml.dll')
   Add-Type -Path (Join-Path $PSScriptRoot 'ChatMath.cs') -ReferencedAssemblies $references -ErrorAction Stop
  }
  $script:chatMathReady=$true
 }catch{$script:chatMathReady=$false}
 return $script:chatMathReady
}
function Update-ChatView($entry){
 $dialog=$entry.Window;$raw=$dialog.FindName('ShowRaw');$rendered=$dialog.FindName('Messages');$source=$dialog.FindName('MessageSource')
 $dialog.FindName('Hint').Text=$entry.HistoryHint
 if($raw.IsChecked){$rendered.Visibility='Collapsed';$source.Visibility='Visible';if($script:chatMathReady -eq $false){$dialog.FindName('Hint').Text+=' 公式组件未就绪，已显示原文；请使用完整软件目录并重新打开。'};return}
 if(-not (Initialize-ChatMath)){
  $raw.IsChecked=$true;$raw.IsEnabled=$false;$rendered.Visibility='Collapsed';$source.Visibility='Visible'
  $dialog.FindName('Hint').Text=$entry.HistoryHint+' 公式组件未就绪，已显示原文；请使用完整软件目录并重新打开。';return
 }
 $source.Visibility='Collapsed';$rendered.Visibility='Visible'
 if($entry.RenderedText -ne $entry.LastText){
  $atEnd=$rendered.VerticalOffset -ge $rendered.ExtentHeight-$rendered.ViewportHeight-25;$offset=$rendered.VerticalOffset
  $rendered.Document=[ClawBot.ChatMath.Renderer]::BuildMessages([string[]]$entry.Parts)
  if($atEnd -or -not $entry.RenderedText){$rendered.ScrollToEnd()}else{$rendered.ScrollToVerticalOffset($offset)}
  $entry.RenderedText=$entry.LastText
 }
 if($rendered.Document.Tag.Fallbacks){$dialog.FindName('Hint').Text+=' 部分公式保留原文，可切换查看。'}
}
