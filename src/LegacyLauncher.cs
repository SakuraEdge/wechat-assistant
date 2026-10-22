using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
static class LegacyLauncher {
 [STAThread] static void Main() {
  var target=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ClawBot实例管理器.exe");
  if(File.Exists(target))Process.Start(new ProcessStartInfo(target){UseShellExecute=true});
  else MessageBox.Show("请先运行 build.ps1 构建ClawBot实例管理器。","ClawBot实例管理器");
 }
}
