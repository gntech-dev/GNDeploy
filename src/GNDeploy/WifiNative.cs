using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace GNDeploy {
 public class WirelessNetwork { public string SSID; public uint Signal; public string Security; public string InterfaceName; public Guid InterfaceId; public bool Connected; public bool Supported; }
 public static class Wifi {
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Adapter { public Guid Id; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string Name; public uint State; }
  [StructLayout(LayoutKind.Sequential)] struct Ssid {public uint Length;[MarshalAs(UnmanagedType.ByValArray,SizeConst=32)]public byte[] Bytes;}
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Network {
   [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)]public string Profile;public Ssid SSID;public uint BssType;public uint Bssids;public int Connectable;public uint Reason;public uint Phys;
   [MarshalAs(UnmanagedType.ByValArray,SizeConst=8)] public uint[] PhyTypes;public int MorePhy;public uint Signal;public int Secure;public uint Auth;public uint Cipher;public uint Flags;public uint Reserved;
  }
  [DllImport("wlanapi.dll")]static extern uint WlanOpenHandle(uint version,IntPtr reserved,out uint negotiated,out IntPtr handle);
  [DllImport("wlanapi.dll")]static extern uint WlanEnumInterfaces(IntPtr handle,IntPtr reserved,out IntPtr list);
  [DllImport("wlanapi.dll")]static extern uint WlanScan(IntPtr handle,ref Guid adapter,IntPtr ssid,IntPtr extra,IntPtr reserved);
  [DllImport("wlanapi.dll")]static extern uint WlanGetAvailableNetworkList(IntPtr handle,ref Guid adapter,uint flags,IntPtr reserved,out IntPtr list);
  [DllImport("wlanapi.dll")]static extern uint WlanCloseHandle(IntPtr handle,IntPtr reserved);
  [DllImport("wlanapi.dll")]static extern void WlanFreeMemory(IntPtr value);
  static void Check(uint value){if(value!=0)throw new Win32Exception((int)value);}
  public static WirelessNetwork[] Networks(){
   IntPtr handle=IntPtr.Zero,interfaces=IntPtr.Zero;uint version;var result=new List<WirelessNetwork>();
   Check(WlanOpenHandle(2,IntPtr.Zero,out version,out handle));
   try{Check(WlanEnumInterfaces(handle,IntPtr.Zero,out interfaces));int count=Marshal.ReadInt32(interfaces);if(count<0||count>64)throw new InvalidOperationException("Invalid WLAN adapter count");
    for(int i=0;i<count;i++){var adapter=(Adapter)Marshal.PtrToStructure(IntPtr.Add(interfaces,8+i*Marshal.SizeOf(typeof(Adapter))),typeof(Adapter));WlanScan(handle,ref adapter.Id,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);}
    if(count>0)System.Threading.Thread.Sleep(1800);
    for(int i=0;i<count;i++){var adapter=(Adapter)Marshal.PtrToStructure(IntPtr.Add(interfaces,8+i*Marshal.SizeOf(typeof(Adapter))),typeof(Adapter));IntPtr networks=IntPtr.Zero;
     try{Check(WlanGetAvailableNetworkList(handle,ref adapter.Id,0,IntPtr.Zero,out networks));int total=Marshal.ReadInt32(networks);if(total<0||total>4096)throw new InvalidOperationException("Invalid WLAN network count");
      for(int n=0;n<total;n++){var item=(Network)Marshal.PtrToStructure(IntPtr.Add(networks,8+n*Marshal.SizeOf(typeof(Network))),typeof(Network));if(item.SSID.Length==0||item.SSID.Length>32)continue;
       string security=item.Secure==0?"Abierta":item.Auth==7?"WPA2 Personal":item.Auth==9?"WPA3 Personal":"Empresa / perfil XML";
       result.Add(new WirelessNetwork{SSID=Encoding.UTF8.GetString(item.SSID.Bytes,0,(int)item.SSID.Length),Signal=item.Signal,Security=security,InterfaceName=adapter.Name,InterfaceId=adapter.Id,Connected=(item.Flags&1)!=0,Supported=item.Secure==0||item.Auth==7||item.Auth==9});
      }
     }finally{if(networks!=IntPtr.Zero)WlanFreeMemory(networks);}
    }
   }finally{if(interfaces!=IntPtr.Zero)WlanFreeMemory(interfaces);if(handle!=IntPtr.Zero)WlanCloseHandle(handle,IntPtr.Zero);}
   return result.ToArray();
  }
 }
}
