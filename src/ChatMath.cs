using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using WpfMath.Controls;

namespace ClawBot.ChatMath {
 public sealed class Segment {
  public string Kind { get; set; }
  public string Text { get; set; }
  public string Source { get; set; }
 }
 public sealed class RenderStats {
  public int Formulas { get; set; }
  public int Fallbacks { get; set; }
 }
 public static class Renderer {
  const int MaxFormulaLength=4096;
  const int MaxFormulas=200;
  static bool Escaped(string text,int index) {
   int count=0;for(int i=index-1;i>=0&&text[i]=='\\';i--)count++;
   return count%2!=0;
  }
  static int RunLength(string text,int index) {
   int end=index+1;while(end<text.Length&&text[end]==text[index])end++;
   return end-index;
  }
  static bool LinePrefix(string text,int index) {
   int start=index;while(start>0&&text[start-1]!='\n')start--;
   if(index-start>3)return false;
   for(int i=start;i<index;i++)if(text[i]!=' ')return false;
   return true;
  }
  static int CodeEnd(string text,int index,int count) {
   char marker=text[index];
   if(count>=3&&LinePrefix(text,index)) {
    int line=text.IndexOf('\n',index+count);
    while(line>=0&&line+1<text.Length) {
     int start=line+1,end=start;while(end<text.Length&&text[end]==' '&&end-start<4)end++;
     if(end-start<=3&&end<text.Length&&text[end]==marker) {
      int length=RunLength(text,end),tail=end+length;
      if(length>=count) {
       while(tail<text.Length&&(text[tail]==' '||text[tail]=='\t'||text[tail]=='\r'))tail++;
       if(tail==text.Length||text[tail]=='\n')return tail==text.Length?tail:tail+1;
      }
     }
     line=text.IndexOf('\n',line+1);
    }
    return text.Length;
   }
   if(marker!='`')return -1;
   int cursor=index+count;
   while(cursor<text.Length) {
    cursor=text.IndexOf('`',cursor);if(cursor<0)return -1;
    int length=RunLength(text,cursor);if(length==count)return cursor+length;
    cursor+=length;
   }
   return -1;
  }
  static int MathEnd(string text,int start,string close,bool singleDollar) {
   int limit=Math.Min(text.Length,start+MaxFormulaLength+close.Length);
   for(int i=start;i<limit;i++) {
    if(singleDollar&&(text[i]=='\n'||text[i]=='\r'))return -1;
    if(i+close.Length>limit||String.CompareOrdinal(text,i,close,0,close.Length)!=0||Escaped(text,i))continue;
    if(singleDollar&&(i==start||Char.IsWhiteSpace(text[i-1])||(i+1<text.Length&&(Char.IsDigit(text[i+1])||text[i+1]=='$'))))return -1;
    if(!singleDollar&&close=="$$"&&RunLength(text,i)!=2)return -1;
    return i;
   }
   return -1;
  }
  static Segment Part(string kind,string source,string text) {
   return new Segment {Kind=kind,Source=source,Text=text};
  }
  public static Segment[] Split(string value) {
   string text=value??"";var result=new List<Segment>();int plain=0,index=0;
   while(index<text.Length) {
    if((text[index]=='`'||text[index]=='~')&&!Escaped(text,index)) {
     int count=RunLength(text,index),end=CodeEnd(text,index,count);
     if(end>=0) {
      if(index>plain)result.Add(Part("text",text.Substring(plain,index-plain),text.Substring(plain,index-plain)));
      string code=text.Substring(index,end-index);result.Add(Part("code",code,code));index=end;plain=index;continue;
     }
     index+=count;continue;
    }
    string open=null,close=null,kind=null;
    if(text[index]=='$'&&!Escaped(text,index)) {
     int count=RunLength(text,index);
     if(count>2){index+=count;continue;}
     open=count==2?"$$":"$";close=open;kind=count==2?"display":"inline";
     if(count==1&&(index+1==text.Length||Char.IsWhiteSpace(text[index+1]))){index++;continue;}
    } else if(text[index]=='\\'&&!Escaped(text,index)&&index+1<text.Length&&(text[index+1]=='('||text[index+1]=='[')) {
     bool block=text[index+1]=='[';open=block?@"\[":@"\(";close=block?@"\]":@"\)";kind=block?"display":"inline";
    }
    if(open!=null) {
     int end=MathEnd(text,index+open.Length,close,open=="$");
     if(end>=0&&end>index+open.Length) {
      if(index>plain)result.Add(Part("text",text.Substring(plain,index-plain),text.Substring(plain,index-plain)));
      result.Add(Part(kind,text.Substring(index,end+close.Length-index),text.Substring(index+open.Length,end-index-open.Length)));
      index=end+close.Length;plain=index;continue;
     }
     index+=open.Length;continue;
    }
    index++;
   }
   if(plain<text.Length)result.Add(Part("text",text.Substring(plain),text.Substring(plain)));
   return result.ToArray();
  }
  static bool WithinLimits(string formula) {
   if(formula.Length>MaxFormulaLength)return false;
   int depth=0;for(int i=0;i<formula.Length;i++) {
    if(Escaped(formula,i))continue;
    if(formula[i]=='{'&&++depth>64)return false;
    if(formula[i]=='}')depth--;
   }
   return true;
  }
  static string Normalize(string formula) {
   formula=formula.Replace("×",@"\times ").Replace("÷",@"\div ").Replace("−","-").Replace("≤",@"\leq ").Replace("≥",@"\geq ").Replace("≠",@"\neq ").Replace("∞",@"\infty ");
   // XAML-Math names the aligned environment "align" and exposes matrix commands.
   foreach(string env in new [] {"aligned","align*"})formula=formula.Replace(@"\begin{"+env+"}",@"\begin{align}").Replace(@"\end{"+env+"}",@"\end{align}");
   string[] names={"matrix","bmatrix","Bmatrix","vmatrix","Vmatrix","pmatrix"};
   string[] left={"",@"\left[",@"\left\{",@"\left|",@"\left\|",@"\left("};
   string[] right={"",@"\right]",@"\right\}",@"\right|",@"\right\|",@"\right)"};
   for(int i=0;i<names.Length;i++)formula=formula.Replace(@"\begin{"+names[i]+"}",left[i]+@"\matrix{").Replace(@"\end{"+names[i]+"}","}"+right[i]);
   return formula.Replace(@"\begin{cases}",@"\left\{\matrix{").Replace(@"\end{cases}",@"}\right.");
  }
  public static FlowDocument Build(string text) {return BuildMessages(new [] {text});}
  public static FlowDocument BuildMessages(string[] messages) {
   var document=new FlowDocument {FontFamily=new FontFamily("Microsoft YaHei UI"),FontSize=15,PagePadding=new Thickness(16),Foreground=new SolidColorBrush(Color.FromRgb(36,38,54))};
   var stats=new RenderStats();document.Tag=stats;
   for(int message=0;message<messages.Length;message++) {
    if(message>0)document.Blocks.Add(new Paragraph(new Run("────────────────────────")) {Foreground=Brushes.LightGray,Margin=new Thickness(0,14,0,14)});
    var paragraph=new Paragraph {Margin=new Thickness(0),LineStackingStrategy=LineStackingStrategy.MaxHeight};
    document.Blocks.Add(paragraph);
    foreach(var segment in Split(messages[message])) {
     if(segment.Kind=="text"||segment.Kind=="code") {
      var run=new Run(segment.Source);if(segment.Kind=="code"){run.FontFamily=new FontFamily("Consolas");run.Background=new SolidColorBrush(Color.FromRgb(244,243,249));}
      paragraph.Inlines.Add(run);continue;
     }
     try {
      if(stats.Formulas>=MaxFormulas||!WithinLimits(segment.Text))throw new FormatException();
      var formula=new FormulaControl {Scale=segment.Kind=="display"?20:17,SystemTextFontName="Microsoft YaHei UI",Foreground=document.Foreground,Margin=new Thickness(2,3,2,3),IsHitTestVisible=false,ToolTip=segment.Source};
      formula.Formula=Normalize(segment.Text);if(formula.HasError)throw new FormatException();
      formula.Measure(new Size(Double.PositiveInfinity,Double.PositiveInfinity));
      if(formula.DesiredSize.Width>16000||formula.DesiredSize.Height>4000)throw new FormatException();
      if(segment.Kind=="display") {
       var scroll=new ScrollViewer {Content=formula,HorizontalScrollBarVisibility=ScrollBarVisibility.Auto,VerticalScrollBarVisibility=ScrollBarVisibility.Disabled,Padding=new Thickness(6),Margin=new Thickness(0,5,0,5)};
       formula.HorizontalAlignment=HorizontalAlignment.Left;
       document.Blocks.Add(new BlockUIContainer(scroll));
       paragraph=new Paragraph {Margin=new Thickness(0)};document.Blocks.Add(paragraph);
      }else paragraph.Inlines.Add(new InlineUIContainer(formula) {BaselineAlignment=BaselineAlignment.Center});
      stats.Formulas++;
     }catch(Exception) {
      paragraph.Inlines.Add(new Run(segment.Source) {ToolTip="此公式暂不支持，保留原文。"});stats.Fallbacks++;
     }
    }
   }
   return document;
  }
 }
}
