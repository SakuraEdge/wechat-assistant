#requires -Version 5.1
param([string]$AppRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appRoot=$AppRoot
. (Join-Path $AppRoot 'src\ChatMath.ps1')
if(-not (Initialize-ChatMath)){throw ('CHAT_MATH_LOAD_FAILED: '+$Error[0])}
$cases=@(
 @{text='中文行内 $x^2+1$ 和 \(\frac{1}{2}\)。';math=2;code=0},
 @{text="显示：`n"+'$$\sum_{i=1}^{n}i$$' + "`n"+'\[\sqrt{x}\]';math=2;code=0},
 @{text='价格 $5 和 $10；转义 \$20；未闭合 $x';math=0;code=0},
 @{text='`$code$` 与 ``\(code\)``，公式 $x$';math=1;code=2},
 @{text='```tex'+"`n"+'$$code$$'+"`n"+'````'+"`n"+'$x$';math=1;code=1},
 @{text='~~~tex'+"`n"+'\[code\]'+"`n"+'~~~'+"`n"+'$x$';math=1;code=1},
 @{text='```tex'+"`n"+'$unfinished$';math=0;code=1},
 @{text='\$literal\$ 和 \\$x$；\\(literal\\)';math=1;code=0},
 @{text='$a'+"`n"+'b$；$$'+"`n"+'c'+"`n"+'$$';math=1;code=0},
 @{text='$a $b$；$x$2；$$$literal$$$';math=1;code=0}
)
foreach($case in $cases){
 $parts=@([ClawBot.ChatMath.Renderer]::Split($case.text))
 if(($parts.Source -join '') -cne $case.text){throw 'CHAT_MATH_SOURCE_LOST'}
 if(@($parts | Where-Object {$_.Kind -in @('inline','display')}).Count -ne $case.math){throw ('CHAT_MATH_DELIMITERS_FAILED: '+$case.text)}
 if(@($parts | Where-Object {$_.Kind -eq 'code'}).Count -ne $case.code){throw 'CHAT_MATH_CODE_PROTECTION_FAILED'}
}
$samples=@(
 '$x^2+y_1$',
 '\[\frac{-b\pm\sqrt{b^2-4ac}}{2a}\]',
 '$$\sum_{i=1}^{n}i=\frac{n(n+1)}{2}$$',
 '\[\int_0^1 x^2\,dx=\frac{1}{3}\]',
 '\[\begin{bmatrix}1&2\\3&4\end{bmatrix}\]',
 '\[\begin{aligned}a&=b+1\\c&=d\end{aligned}\]',
 '\[f(x)=\begin{cases}x^2&x>0\\0&x\leq0\end{cases}\]',
 '\(\text{面积}=\pi r^2\)',
 '\((180-30×2)÷60=2\)',
 ('\['+"`n"+'(600-120)÷2÷6=40\text{（米/分）}'+"`n"+'\]')
)
$doc=[ClawBot.ChatMath.Renderer]::BuildMessages([string[]]$samples)
if($doc.Tag.Formulas -ne $samples.Count -or $doc.Tag.Fallbacks){throw ('CHAT_MATH_RENDER_FAILED: '+($doc.Tag|ConvertTo-Json -Compress))}
$reader=[Windows.Controls.RichTextBox]::new();$reader.Document=$doc
$reader.Measure([Windows.Size]::new(720,640));$reader.Arrange([Windows.Rect]::new(0,0,720,640));$reader.UpdateLayout()
if($reader.ExtentHeight -le 0){throw 'CHAT_MATH_LAYOUT_FAILED'}
$bad='$\ClawBotUnsupportedCommand{x}$'
$fallback=[ClawBot.ChatMath.Renderer]::Build($bad)
if($fallback.Tag.Formulas -or $fallback.Tag.Fallbacks -ne 1 -or ([Windows.Documents.TextRange]::new($fallback.ContentStart,$fallback.ContentEnd).Text).Trim() -cne $bad){throw 'CHAT_MATH_FALLBACK_LOST_SOURCE'}
$separate=[ClawBot.ChatMath.Renderer]::BuildMessages([string[]]@(('```tex'+"`n"+'$literal$'),'$x$'))
if($separate.Tag.Formulas -ne 1){throw 'CHAT_MATH_MESSAGE_BOUNDARY_FAILED'}
$deep='$'+('{'*65)+'x'+('}'*65)+'$';$limited=[ClawBot.ChatMath.Renderer]::Build($deep)
if($limited.Tag.Fallbacks -ne 1){throw 'CHAT_MATH_NESTING_LIMIT_FAILED'}
[Console]::WriteLine('CHAT_MATH_OK: delimiters, currencies, code, source preservation, native layout, matrix, aligned, cases, Chinese, fallback and limits')
