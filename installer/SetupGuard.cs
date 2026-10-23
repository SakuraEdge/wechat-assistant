using System;
using System.IO;
using System.Management;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
static class SetupGuard {
 [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CommandLineToArgvW(string command,out int count);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
 static string[] Arguments(string command) {
  int count;var memory=CommandLineToArgvW(command,out count);if(memory==IntPtr.Zero)throw new InvalidOperationException();
  try{var result=new string[count];for(int i=0;i<count;i++)result[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory,i*IntPtr.Size));return result;}finally{LocalFree(memory);}
 }
 static bool Inside(string file,string root) {
  if(String.IsNullOrWhiteSpace(file)||!Path.IsPathRooted(file))return false;
  try{return Path.GetFullPath(file).StartsWith(root,StringComparison.OrdinalIgnoreCase);}catch{return false;}
 }
 static bool UsesScript(string name,string command,string root) {
  if(String.IsNullOrWhiteSpace(command))return false;var args=Arguments(command);
  if(name.Equals("powershell.exe",StringComparison.OrdinalIgnoreCase)||name.Equals("pwsh.exe",StringComparison.OrdinalIgnoreCase)) {
   for(int i=1;i+1<args.Length;i++)if(args[i].Equals("-File",StringComparison.OrdinalIgnoreCase))return Inside(args[i+1],root);
   return false;
  }
  if(!name.Equals("node.exe",StringComparison.OrdinalIgnoreCase))return false;
  for(int i=1;i<args.Length;i++) {
   var value=args[i];
   if(value=="--")return i+1<args.Length&&Inside(args[i+1],root);
   if(value=="-e"||value=="--eval"||value=="-p"||value=="--print"||value.StartsWith("--eval=")||value.StartsWith("--print="))return false;
   if(value=="-r"||value=="--require"||value=="--import"||value=="--loader"||value=="--experimental-loader") {if(i+1<args.Length&&Inside(args[++i],root))return true;continue;}
   if(value.StartsWith("-")){int equal=value.IndexOf('=');if(equal>0&&Inside(value.Substring(equal+1),root))return true;continue;}
   // Only the entry script owns files here; later arguments can contain arbitrary user paths.
   return Inside(value,root);
  }
  return false;
 }
 static void Report(string status,List<string> blockers,string details) {
  Console.WriteLine("{\"status\":\""+status+"\",\"processes\":["+String.Join(",",blockers.ToArray())+"]}");
  if(details!=null)File.WriteAllText(details,String.Join(Environment.NewLine,blockers.ToArray()),Encoding.UTF8);
 }
 static int Main(string[] args) {
  var blockers=new List<string>();string details=null;
  try {
   if((args.Length!=1&&args.Length!=2&&args.Length!=3)||!Path.IsPathRooted(args[0]))return 43;
   if(args.Length==2&&args[1]!="--report")return 43;
   if(args.Length==3){if(args[1]!="--details"||!Path.IsPathRooted(args[2]))return 43;details=args[2];}
   var root=Path.GetFullPath(args[0]).TrimEnd('\\')+"\\";
   using(var query=new ManagementObjectSearcher("SELECT ProcessId,Name,ExecutablePath,CommandLine FROM Win32_Process WHERE Name='node.exe' OR Name='ClawBot实例管理器.exe' OR Name='微信助手.exe' OR Name='powershell.exe' OR Name='pwsh.exe'"))
   using(var results=query.Get())foreach(ManagementObject process in results) {
    var executable=process["ExecutablePath"] as string;var command=process["CommandLine"] as string;var name=process["Name"] as string;
    if(Inside(executable,root)||UsesScript(name??"",command,root))blockers.Add("{\"pid\":"+process["ProcessId"]+",\"name\":\""+name+"\"}");
   }
   Report(blockers.Count==0?"idle":"blocked",blockers,details);if(blockers.Count>0)return 42;
   return 0;
  }catch{Report("unverified",blockers,details);return 43;}
 }
}
