using System;
using System.IO;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Text;
[assembly: AssemblyTitle("ClawBot实例管理器")]
[assembly: AssemblyDescription("ClawBot实例管理器")]
[assembly: AssemblyProduct("ClawBot实例管理器")]
[assembly: AssemblyVersion("1.4.2.0")]
[assembly: AssemblyFileVersion("1.4.2.0")]
static class Launcher {
 static string Safe(string value){return (value??"").Replace("\\","\\\\").Replace("\"","\\\"").Replace("\r","").Replace("\n","");}
 static void Diagnose(string phase,ErrorRecord error,Exception exception,bool show) {
  var script=error==null||error.InvocationInfo==null?"Manager.ps1":Path.GetFileName(error.InvocationInfo.ScriptName);
  var line=error==null||error.InvocationInfo==null?0:error.InvocationInfo.ScriptLineNumber;
  var type=exception==null?"PowerShellError":exception.GetType().FullName;
  try {
   var directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Codex","wechat-manager","diagnostics");Directory.CreateDirectory(directory);
   File.WriteAllText(Path.Combine(directory,"manager-last-error.json"),"{\"phase\":\""+Safe(phase)+"\",\"script\":\""+Safe(script)+"\",\"line\":"+line+",\"exception_type\":\""+Safe(type)+"\",\"at\":\""+DateTime.UtcNow.ToString("o")+"\"}",new UTF8Encoding(false));
  }catch{}
  if(show)MessageBox.Show("管理器运行出错："+script+(line>0?" 第"+line+"行":"")+"（"+type+"）。\n脱敏诊断保存在本机 wechat-manager\\diagnostics\\manager-last-error.json，请在Codex中检查对应窗口代码。","ClawBot实例管理器");
 }
 [DllImport("shell32.dll", CharSet=CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
 [STAThread] static void Main() {
  SetCurrentProcessExplicitAppUserModelID("ClawBot.InstanceManager");
  var root=AppDomain.CurrentDomain.BaseDirectory;
  var script=Path.Combine(root,"src","Manager.ps1");
  if(!File.Exists(script)){MessageBox.Show("未找到 src/Manager.ps1，请保持文件包目录完整。","ClawBot实例管理器");return;}
  bool created;
  using(var mutex=new Mutex(true,"Local\\CodexWeChatAssistantManager",out created)) {
   if(!created){MessageBox.Show("管理窗口已经打开，请切换到ClawBot实例管理器。","ClawBot实例管理器");return;}
   try {
    using(var space=RunspaceFactory.CreateRunspace()) {
     space.ApartmentState=ApartmentState.STA;space.ThreadOptions=PSThreadOptions.UseCurrentThread;space.Open();
     using(var powershell=PowerShell.Create()) {
      powershell.Runspace=space;
      powershell.AddCommand("Set-ExecutionPolicy").AddParameter("Scope","Process").AddParameter("ExecutionPolicy","Bypass").AddParameter("Force");powershell.Invoke();powershell.Commands.Clear();powershell.Streams.Error.Clear();
      powershell.AddCommand(script);powershell.Invoke();
      var handoff=space.SessionStateProxy.GetVariable("ClawBotUpdateHandoff");
      if(powershell.HadErrors&&!Object.Equals(handoff,true))Diagnose("run",powershell.Streams.Error.Count>0?powershell.Streams.Error[0]:null,null,powershell.InvocationStateInfo.State==PSInvocationState.Failed);
     }
    }
   }catch(RuntimeException error){Diagnose("run",error.ErrorRecord,error,true);}
   catch(Exception error){Diagnose("start",null,error,true);}
  }
 }
}
