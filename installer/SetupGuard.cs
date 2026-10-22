using System;
using System.IO;
using System.Management;
static class SetupGuard {
 static int Main(string[] args) {
  try {
   if(args.Length!=1||!Path.IsPathRooted(args[0]))return 43;
   var root=Path.GetFullPath(args[0]).TrimEnd('\\')+"\\";
   using(var query=new ManagementObjectSearcher("SELECT ExecutablePath,CommandLine FROM Win32_Process WHERE Name='node.exe' OR Name='ClawBot实例管理器.exe' OR Name='微信助手.exe'"))
   using(var results=query.Get())foreach(ManagementObject process in results) {
    var executable=process["ExecutablePath"] as string;var command=process["CommandLine"] as string;
    if((executable!=null&&executable.StartsWith(root,StringComparison.OrdinalIgnoreCase))||(command!=null&&command.IndexOf(root,StringComparison.OrdinalIgnoreCase)>=0))return 42;
   }
   return 0;
  }catch{return 43;}
 }
}
