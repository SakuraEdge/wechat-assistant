using System;
using System.IO;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Runtime.InteropServices;
using System.Reflection;
[assembly: AssemblyTitle("ClawBot实例管理器")]
[assembly: AssemblyDescription("ClawBot实例管理器")]
[assembly: AssemblyProduct("ClawBot实例管理器")]
[assembly: AssemblyVersion("1.4.0.0")]
[assembly: AssemblyFileVersion("1.4.0.0")]
static class Launcher {
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
      if(powershell.HadErrors)MessageBox.Show("管理窗口未能正常运行，请在Codex中检查src/Manager.ps1。","ClawBot实例管理器");
     }
    }
   }catch{MessageBox.Show("无法启动，请检查 Windows PowerShell、Node24与文件包。","ClawBot实例管理器");}
  }
 }
}
