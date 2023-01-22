################################################################
#
# $Id$
#
# 2019-2021 by Axel Hermann
#
# FHEM Forum : https://forum.fhem.de/index.php/topic,106503.0.html
#
################################################################

# Version -   Date   - description
# ah  1.0 - 19.12.19 - first version
# ah  1.1 - 05.01.19 - add $readingFnAttributes to AttrList,
#                    - activatable log File via AttrList (70_HPSU_Log.log),
#                    - AttrList: "AntiMixerSwing" for default to "on" (workaround for RoCon bug)
#                    - set: ForceDHW - force to make hot water if possible without backup heater
#                    - reading: calculated Q (actual produced energy) -> Info.Q
#                    - CheckDHWInterrupted
# ah  1.2 - 13.01.20 - CheckDHWInterrupted and AntiMixerSwing fixed (was experimental)
#                    - init improved for virgin ELM327 (set 20k baud and write to eeprom)
# ah  1.3 - 01.02.20 - Warning "uninitialized value in transliteration (tr///)" eliminated
#                    - CheckDHWInterrupted and AntiMixerSwing tested and fixed (time optimization)
# ah  1.4 - 09.02.20 - "use JSON" and "use SetExtensions" added
#                    - If "SetStatus Error: timeout" then retry 1 time ($hash->{helper}{CANSetTries})
# ah  1.5 - 07.04.20 - commands_hpsu.json V3.4 -> status_pump renamed to "Direkter_Heizkreis_Modus"/"Direct_heater_mode"
#                    - Save last Pump activity. Maybe the HPSU is in power-saving mode and do not make "AntiMixerSwing"!
#                    - "AntiMixerSwing" for default to "off" - Someone reported in the FHEM forum not working properly..?
#           12.05.20 - ForceDHW: t_dhw_set -> t_dhw_set -> if before ForceDHW is set new value
#           27.05.20 - AntiMixerSwing -> Set status_pump_WasActive 0 if ($T_VlWez <= 0)
#           04.07.20 - AntiMixerSwing -> ... and check "mode_01" change
#           21.09.20 - Init: set timeout to max
#           27.09.20 - $DHWDiffBig condition changed from "t_dhw_set" to "t_dhw_setpoint1"
# ah  1.6 - 28.09.20 - Receive with "CANRequestName" to suppress timeouts an just get requested data.
#                      Now it is also possible to set func_heating, quiet_mode, hc_func...
#           01.10.20 - New Mode: "Connect_MonitorMode". Just Parse CAN Messages an decode them also if not in commands.json
#           05.10.20 - ForceDHW: Wait while something is in queue. Fix condition such as t_dhw_setpoint1 changed before..
# ah  1.7 - 11.12.20 - Info.HeatCyclicErr - Count pulsed mode of compressor (Heat Mode < 8 minutes)
#                    - DebugLog: New mode "onDHW" just for ForceDHW
# ah  1.8 - 31.12.20 - New Attribut: AntiContinousHeating - While defrost no heating from dhw buffer
#                    -               |-> https://www.haustechnikdialog.de/Forum/p/3075032 (thanks to andi2055)
# ah  1.9 - 05.01.21 - During AntiContinousHeating the parameter t_frost_protect must also be switched off
#                    - |-> https://forum.fhem.de/index.php/topic,106503.msg1116881.html#msg1116881
#                    - Setting negative float values are now possible - necessary because t_frost_protect
#           06.01.21 - Min / max check corrected when setting with "slider" parameter
#                    - KompActive.. - renamed to status_pump..
# ah 1.10 - 07.01.21 - Force "t_frost_protect" if AntiContinousHeating is set to "on"
#                    - if t_frost_protect_lst ne "NotRead"Force then change not "t_frost_protect"
#                    - Min / max check corrected
# ah 1.11 - 14.01.21 - Parse_SetGet_cmd() to find out cmd send via Set or Get argument
#                    -         |-> https://forum.fhem.de/index.php/topic,106503.msg1119787.html#msg1119787
#                    - Sort set an get dropdowns
#                    - When init then cancel DHWForce (with -1)
#                    - New reading: Info.LastDefrostDHWShrink (if mode heating)
#                    - New attribute: SuppressRetryWarnings - to relieve logging
#                    - New attribute: (experimental state !!) - RememberSetValues - save mode_01 val and set after module init
#                    - "Infoname" if val set
# ah 1.12 - 25.01.21 - Parse_SetGet_cmd() renamed to HPSU_Parse_SetGet_cmd()
#                    - Monitor Mode: extend output with header info and signed float
#           03.02.21 - New reading: Info.Ts - temperature spread
#                    - Added support for Rotex HPSU ULTRA -> https://forum.fhem.de/index.php/topic,106503.msg1128547.html#msg1128547
#                    - Initialize the ELM to only send as many bytes as specified - no padding to 8 bytes!
#                    - Request with header 0x10F and calculated response filter from command
#                    - Set value with header 0x10A
#                    - RememberSetValues tested and fixed
#           09.02.21 - Change request header adresses
#                    - Reformat Info.LastDefrostDHWShrink
#           20.02.21 - Init improved with que
#                    - Logging improved
#                    - Define of module extend with "system": [comfort|ultra] -  define <name> HPSU <device> [system]
#                    - i.e.: define myHPSU HPSU /dev/ttyUSB0 comfort
#                    - JSON File: Parameter "id" no longer needed / new param "system" for differentiation
#                    - Fixed RequestHeaderID to 680 
#                    - Calculate CANRequestHeaderID
# ah 1.13 - 13.03.21 - Warning if not comfort and AntiContinousHeating is set
#                    - HPSU_DbLog_split -> https://forum.fhem.de/index.php/topic,106503.msg1136285.html#msg1136285
#                    - After AntiContinousHeating set back to the previously mode -> https://forum.fhem.de/index.php/topic,106503.msg1139316.html#msg1139316
#                    - $attr{global}{modpath} instead of cwd()
#                    - Reformat Info.Ts
# ah 1.14 - 05.11.21 - improve/cleanup code
#                    - ForceDHW only possible if HPSU not in idle mode
#                    - New JSON Parameter: "statistic":"h|d". To generate hour and daily statistic for specified reading.
#           15.11.21 - set: ForceDHWTemp - ForceDHW with (new) destination temperature (i.e. set myHPSU ForceDHWTemp 45)
#           18.11.21 - New Attribut: AntiShortCycle to suppress short compressor running times
#                    - Calculate "AktQ" only if compressor is running
#           27.11.21 - Remove internal redundant values ..{AktVal} and ..{FHEMLastResponse}
#                    - set: if verify failed retry 2 times
# ah 1.15 - 01.12.21 - handle exception for decode_json(..)
#           07.12.21 - if AntiContinousHeating is currently active mustn't let set mode_01 direct
#                    - Do AntiMixerSwing only if DHW > 35.5
# ah 1.16 - 29.12.21 - get "split" -> $TimeSuspend if AntiShortCycle occurred
#           10.02.22 - if AntiContinousHeating is not active fixed
#                    - Attr: JSON_version check fixed
#           14.03.22 - CANSetTries no longer needed (since 1.14)
# ah 1.17 - 22.01.23 - New JSON Parameter: "repeatTime". Check set after x secounds

#ToDo:
# - suppress retry

package main;

use strict;
use warnings;
use DevIo; # load DevIo.pm if not already loaded
use JSON;
use SetExtensions;

use constant HPSU_MODULEVERSION => '1.17';

#Prototypes
sub HPSU_Disconnect($);
sub HPSU_Read_JSON_updreadings($);
sub HPSU_CAN_RequestReadings($$$);
sub HPSU_Read_JSON_File($);
sub HPSU_CAN_ParseMsg($$);
sub HPSU_CAN_RequestOrSetMsg($$$);
sub HPSU_CAN_RAW_Message($$);
sub HPSU_Parse_SetGet_cmd($$);
sub HPSU_Log($); #for development
sub HPSU_RAW_Log($); #for MA development

my %HPSU_sets =
(
  "Connect"             =>  "noArg",
  "Connect_MonitorMode" =>  "noArg",
  "Disconnect"          =>  "noArg",
  "ForceDHW"            =>  "noArg",
  "ForceDHWTemp"        =>  "textField",
  "Reset.ShortCycleSuspend"  =>  "noArg"
);

my %HPSU_gets =
(
  "UpdateJson"        =>  "noArg"
);

sub HPSU_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "HPSU_Define";
  $hash->{UndefFn}  = "HPSU_Undef";
  $hash->{SetFn}    = "HPSU_Set";
  $hash->{GetFn}    = "HPSU_Get";
  $hash->{ReadFn}   = "HPSU_Read";
  $hash->{ReadyFn}  = "HPSU_Ready";
  $hash->{AttrFn}    = "HPSU_Attr";
  $hash->{DbLog_splitFn} = "HPSU_DbLog_split";
  $hash->{AttrList}  = "AutoPoll:on,off AntiMixerSwing:on,off ".
                       "CheckDHWInterrupted:on,off ".
                       "DebugLog:on,onDHW,off ".
                       "AntiContinousHeating:on,off ".
                       "RememberSetValues:on,off ".
                       "SuppressRetryWarnings:on,off ".   #"Comm.(Set|Get)Status", "Error: retry ...
                       "AntiShortCycle:textField ".
                       $readingFnAttributes;
}

# called when a new definition is created (by hand or from configuration read on FHEM startup)
sub HPSU_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  my $name = $a[0];

  # $a[1] is always equals the module name "HPSU"

  # first argument is a serial device (e.g. "/dev/ttyUSB0@38400")
  my $dev = $a[2];
  
  if ($a[3])
  {
    if ($a[3] =~ "comfort|ultra")
    {
      $hash->{System} = $a[3];
    }
    else
    {
      return "$a[3] not known !!"
    }
  }

  return "no device given" unless($dev);

  # close connection if maybe open (on definition modify)
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));

  # add a default baud rate (38400), if not given by user
  $dev .= '@38400' if(not $dev =~ m/\@\d+$/);

  # set the device to open
  $hash->{DeviceName} = $dev;

  # listen Mode
  $hash->{ELMState} = "defined";

  DevIo_OpenDev($hash, 0, "HPSU_Init");

  $hash->{Module_Version} = HPSU_MODULEVERSION;

  return undef;
}

# called when definition is undefined
# (config reload, shutdown or delete of definition)
sub HPSU_Undef($$)
{
  my ($hash, $name) = @_;

  HPSU_Disconnect($hash);

  return undef;
}

# called repeatedly if device disappeared
sub HPSU_Ready($)
{
  my ($hash) = @_;

  # try to reopen the connection in case the connection is lost
  return DevIo_OpenDev($hash, 1, "HPSU_Init");
}

# called when data was received
sub HPSU_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $data = DevIo_SimpleRead($hash);
  return if(!defined($data)); # connection lost

  my $buffer = $hash->{helper}{PARTIAL};
  $buffer .= $data;

  while($buffer =~ m/>/)
  {
    my $msg = "";
    ($msg, $buffer) = split(">", $buffer, 2);
    my $ELMerr = index($msg, "?\r");
    my $ELMok = index($msg, "OK\r");
    
    if ($hash->{ELMState} eq "init")
    {
      if ($ELMerr < 0 and
          $ELMok < 0)
      {
        my $strInit = "ELM327 v";
        my $idxInit = index($msg, $strInit);

        if ($idxInit > 0)
        {
          $hash->{ELM327_Version} = substr($msg, $idxInit + length($strInit), 3);
        }
        $ELMok = 0;
      }
      elsif ($ELMerr >= 0)
      {
        HPSU_Log("HPSU ".__LINE__.": Init err before: \"$hash->{helper}{WriteQueue}[0]\"") if (AttrVal($name, "DebugLog", "off") =~ "on");
        $ELMerr = -1;
        $ELMok = 0;
      }
    }
    
    if ($ELMerr >= 0)
    {
      $hash->{helper}{CANAktRequestHeaderID} = "";
      $hash->{helper}{CANAktResponseHeaderID} = "";
      $hash->{helper}{CANRequestPending} = 0;      
    }
    elsif ($ELMok >= 0)
    {
      if (@{$hash->{helper}{WriteQueue}})
      {
        my $sque = shift @{$hash->{helper}{WriteQueue}};
        
        if ($hash->{ELMState} eq "init")
        {
          HPSU_Log("HPSU ".__LINE__.": Init: \"$sque\"") if (AttrVal($name, "DebugLog", "off") =~ "on");
        }
        
        if ($sque eq "Initialized")
        {
          if ($hash->{helper}{MonitorMode})
          {
            $hash->{ELMState} = "Monitor mode active"; #just for development
            
            DevIo_SimpleWrite($hash, "AT MA\r", 2);
            HPSU_Log("HPSU ".__LINE__.": Init: \"$hash->{ELMState}\"") if (AttrVal($name, "DebugLog", "off") =~ "on");
          }
          else
          {
            $hash->{ELMState} = "Initialized"; #normal operation
            
            HPSU_Task($hash);
            HPSU_Stat_Task($hash, undef, undef);
          
            if (AttrVal($name, "RememberSetValues", "off") eq "on")
            {
              my $val = ReadingsVal($name, "FHEMSET.$hash->{jcmd}{mode_01}{name}","NotRead");
              
              push @{$hash->{helper}{queue}}, "mode_01;$val" if ($val ne "NotRead");
            }
          }
          $hash->{STATE} = "opened";  #not so nice hack, but works          
        }
        else
        {
          DevIo_SimpleWrite($hash, $sque."\r", 2);
        }
      }
      else
      {
        $hash->{helper}{CANRequestPending} = 0;
      }
    }
    else
    {
      while($msg =~ m/\r/)
      {
        my $msgSplit = "";

        ($msgSplit, $msg) = split("\r", $msg, 2);
        $msgSplit =~ s/ +$//; #delete whitespace

        if (defined $hash->{helper}{CANRequestName})
        {
          my ($key, $nicename, $out) = HPSU_CAN_ParseMsg($hash, $msgSplit);
          
          if ($key)
          {
            my $oldval = ReadingsNum($name, "HPSU.$nicename",0);
            
            if ($hash->{helper}{CANRequestName} eq $key)
            {
              $hash->{helper}{CANRequestPending} = 0;
              readingsSingleUpdate($hash, "HPSU.$nicename", $out, 1);
              HPSU_Stat_Task($hash, $key, $oldval);
            }
          }
          if ($hash->{helper}{CANRequestName} eq "NO DATA")
          {
            $hash->{helper}{CANRequestPending} = 0;
          }
        }
      }
    }
  }
  
  if ($hash->{ELMState} eq "Monitor mode active")
  {
    while($buffer =~ m/\r/)
    {
      my $msgSplit = "";

      ($msgSplit, $buffer) = split("\r", $buffer, 2);
      $msgSplit =~ s/ +$//; #delete whitespace
            
      #AT H1
      my $Header = "";
      ($Header, $msgSplit) = split(" ", $msgSplit, 2);      

      my ($key, $nicename, $out) = HPSU_CAN_ParseMsg($hash, $msgSplit);
      my ($rawName, $rawOut) = HPSU_CAN_RAW_Message($hash, $msgSplit);
      
      my $sreq = undef;
      my $HeaderDes = sprintf("%03X", hex(substr($msgSplit, 0, 1)) * 0x10 * 0x08);
      if ($Header eq "680")
      {
        $sreq = 1;
      }
      else
      {
        $sreq = substr($msgSplit, 0, 2) eq "D2";
      }
      
      if ($key)
      {
        HPSU_RAW_Log("H:$Header HD:$HeaderDes M:$msgSplit K:$key-$nicename O:$out") if (not $sreq);
        readingsSingleUpdate($hash, "HPSU.$nicename"."_MsgHeader.$Header", $out." : ".$rawOut, 1);
      }
      else
      {
        HPSU_RAW_Log("H:$Header HD:$HeaderDes M:$msgSplit") if (not $sreq);
        readingsSingleUpdate($hash, "$rawName"."_MsgHeader.$Header", $rawOut, 1) if ($rawName);
      }
    }
  }

  $hash->{helper}{PARTIAL} = $buffer;
}

sub HPSU_Set($@)
{
  my ($hash, $name, $cmd, @args ) = @_;
  my $cmdList = join(" ", map {"$_:$HPSU_sets{$_}"} keys %HPSU_sets);
  my $jcmd = $hash->{jcmd};
  my $hpsuNameCmd = "";

  return "\"set $name\" needs at least one argument" unless(defined($cmd));

  my $ret = HPSU_Parse_SetGet_cmd($hash, $cmd);
  $hpsuNameCmd = $ret if $ret;

  return "\"set $name\" needs a setable value" if ($jcmd->{$hpsuNameCmd} and not exists $args[0]);
  
  if($cmd eq "Connect")
  {
    undef $hash->{helper}{MonitorMode};
    DevIo_OpenDev($hash, 0, "HPSU_Init");
  }
  elsif($cmd eq "Connect_MonitorMode")
  {
    $hash->{helper}{MonitorMode} = 1;
    DevIo_OpenDev($hash, 0, "HPSU_Init");
  }
  elsif($cmd eq "Disconnect")
  {
    undef $hash->{helper}{MonitorMode};
    HPSU_Disconnect($hash);
  }
  elsif($cmd eq "ForceDHW")
  {
    $hash->{helper}{DHWForce} = gettimeofday();
  }
  elsif($cmd eq "Reset.ShortCycleSuspend")
  {
    if (defined $hash->{helper}{ShortCycle}{TimeSuspend})
    {
      readingsSingleUpdate($hash, "Info.AntiShortCycle", "Idle", 1);
      HPSU_Log("HPSU ".__LINE__.": AntiShortCycle - Idle - Restore mode \"$hash->{helper}{ShortCycle}{BModeStart}\"" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
      push @{$hash->{helper}{queue}}, "mode_01;$hash->{helper}{ShortCycle}{BModeStart}";
    }
    delete $hash->{helper}{ShortCycle};
  }
  elsif($cmd eq "ForceDHWTemp")
  {
    return "\"set $name\" needs a temperature value" if ((not exists $args[0]) ||
                                                         ($args[0] =~ /^\d+$/ != 1));
    
    $hash->{helper}{DHWForce} = gettimeofday();
    $hash->{helper}{DHWForceDesTempFromSet} = $args[0];
  }
  elsif($hpsuNameCmd)
  {
    my $val = $args[0];

    return "Monitor mode active.. set values disabled!" if ($hash->{helper}{MonitorMode});
    return "$hpsuNameCmd not writable" if ($jcmd->{$hpsuNameCmd}{writable} ne "true");

    if ($hpsuNameCmd eq "mode_01")
    {
      if (AttrVal($name, "RememberSetValues", "off") eq "on")
      {
        readingsSingleUpdate($hash, "FHEMSET.$hash->{jcmd}{$hpsuNameCmd}{name}", $val, 1);
      }
      if (defined $hash->{helper}{AntiCHeat}{BModeStart})  #AntiContinousHeating is currently active
      {
        my $infoName = "\"$hash->{jcmd}{$hpsuNameCmd}{name}\" [$hpsuNameCmd]";
        
        if ($hash->{helper}{AntiCHeat}{BModeStart} eq $val)
        {          
          readingsSingleUpdate($hash, "Comm.SetStatus", "Ok: $infoName already set to \"$val\" after AntiContinousHeating (".__LINE__.")", 1);
        }
        else
        {
          readingsSingleUpdate($hash, "Comm.SetStatus", "Ok: $infoName set to \"$val\" after AntiContinousHeating (".__LINE__.")", 1);
          $hash->{helper}{AntiCHeat}{BModeStart} = $val;
        }
        $val = undef;
      }
    }
    
    #min/max check
    if (defined $val and $jcmd->{$hpsuNameCmd}{FHEMControl} and (index($jcmd->{$hpsuNameCmd}{FHEMControl}, "slider,") == 0) )
    {
      my $dmy = "";
      my $que = "";
      my $min = 0;
      my $max = 0;
      
      my $dbgString = "FHEMControl: $jcmd->{$hpsuNameCmd}{FHEMControl} cmd: $hpsuNameCmd val: $val";

      ($dmy, $que) = split(",", $jcmd->{$hpsuNameCmd}{FHEMControl}, 2); #i.e. slider,5,0.5,40
      ($min, $que) = split(",", $que, 2);
      ($dmy, $que) = split(",", $que, 2);
      ($max, $que) = split(",", $que, 2);
      
      if (not $dmy or not $max)
      {
        HPSU_Log("HPSU ".__LINE__.": MinMax argument error --> $dbgString" ) if (AttrVal($name, "DebugLog", "off") eq "on");
      }
      elsif ($min > $max)
      {
        HPSU_Log("HPSU ".__LINE__.": MinMax value error --> $dbgString - min: $min max: $max" ) if (AttrVal($name, "DebugLog", "off") eq "on");
      }
      else
      {
        if ($val < $min)
        {
          HPSU_Log("HPSU ".__LINE__.": $hpsuNameCmd: value $val is less than minimum -> corrected to $min" ) if (AttrVal($name, "DebugLog", "off") eq "on");
          $val = $min;
        }
        if ($val > $max)
        {
          $val = $max;
          HPSU_Log("HPSU ".__LINE__.": $hpsuNameCmd: value $val is greater than maximum -> corrected to $max" ) if (AttrVal($name, "DebugLog", "off") eq "on");
        }
      }
    }
    my $qstr = "$hpsuNameCmd;$val";
    
    push @{$hash->{helper}{queue}}, $qstr if (defined $val);
  }
  else
  {
    my $jcmd = $hash->{jcmd};

    foreach my $key (@{$hash->{helper}{Writablekeys}})
    {
      if ($jcmd->{$key}{FHEMControl} and $jcmd->{$key}{FHEMControl} ne "disabled")
      {
        $cmdList .= " HPSU.$jcmd->{$key}{name}:";
        if ($jcmd->{$key}{FHEMControl} eq "value_code")
        {
          $cmdList .= join(",", map {"$jcmd->{$key}{value_code}{$_}"} sort keys %{$jcmd->{$key}{value_code}});
        }
        else
        {
          $cmdList .= "$jcmd->{$key}{FHEMControl}";
        }
      }
    }

    return SetExtensions($hash, $cmdList, $name, $cmd, @args);
  }

  return undef;
}


sub HPSU_Get($$@)
{
  my ( $hash, $name, $opt, @args ) = @_;
  my $cmdList = join(" ", map {"$_:$HPSU_gets{$_}"} sort keys %HPSU_gets);
  my $jcmd = $hash->{jcmd};

  return "\"get $name\" needs at least one argument" unless(defined($opt));

  if($opt eq "UpdateJson")
  {
    HPSU_Read_JSON_updreadings($hash);
  }
  elsif($opt eq "HPSU")
  {
    return "Monitor mode active.. get values manually disabled!" if ($hash->{helper}{MonitorMode});
  
    #find [xxx] (i.e. "Aktive_Betriebsart_[mode]" -> mode)
    my $hpsuNameCmd = HPSU_Parse_SetGet_cmd($hash, $args[0]);

    if ($hpsuNameCmd)
    {
      push @{$hash->{helper}{queue}}, $hpsuNameCmd;
    }
    else
    {
      return "Unknown HPSU parameter name!";
    }
  }
  else
  {
    my $jcmdString = "";
    my @names = ();
    
    foreach my $key0 (keys %{$jcmd}) 
    {
      push @names, $jcmd->{$key0}{name} if (length($jcmd->{$key0}{name}));
    }

    foreach $name (sort @names)
    {
      $jcmdString .= "$name,";
    }

    return "Unknown argument $opt, choose one of " . $cmdList. " HPSU:".$jcmdString;
  }

  return undef;
}

sub HPSU_Init($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{System} = "comfort" if (not($hash->{System}));   #default value
  
  HPSU_Read_JSON_updreadings($hash);
  # Reset
  $hash->{helper}{PARTIAL} = "";
  @{$hash->{helper}{queue}} = ();
  delete $hash->{helper}{AntiCHeat};
  delete $hash->{helper}{DHWForce};

  $hash->{ELMState} = "init";
  $hash->{ELM327_Version} = "not read";
  $hash->{Module_Version} = HPSU_MODULEVERSION;
  
  $hash->{helper}{CANRequestHeaderID} = "";
  $hash->{helper}{CANAktRequestHeaderID} = "";
  $hash->{helper}{CANResponseHeaderID} = "";
  $hash->{helper}{CANAktResponseHeaderID} = "";
  $hash->{helper}{CANRequestPending} = 0;
  $hash->{helper}{autopollState} = 0;
  @{$hash->{helper}{WriteQueue}} = ();

  if (not HPSU_Read_JSON_updreadings($hash))
  {
    push @{$hash->{helper}{WriteQueue}}, "";
    push @{$hash->{helper}{WriteQueue}}, "AT Z";             #just reset
    push @{$hash->{helper}{WriteQueue}}, "AT E1";            #echo on
    push @{$hash->{helper}{WriteQueue}}, "AT PP 2F SV 19";   #set baud to 20k
    push @{$hash->{helper}{WriteQueue}}, "AT PP 2F ON";      #activate/save baud parameter
    push @{$hash->{helper}{WriteQueue}}, "AT SP C";          #activate protocol "C"
    push @{$hash->{helper}{WriteQueue}}, "AT Z";             #reset and takeover settings
    push @{$hash->{helper}{WriteQueue}}, "AT V1";            #Send only as many bytes as given - no padding!
    push @{$hash->{helper}{WriteQueue}}, ($hash->{helper}{MonitorMode})?"AT H1":"AT H0";  #Header off
    push @{$hash->{helper}{WriteQueue}}, "Initialized";
    
    my $sque = shift @{$hash->{helper}{WriteQueue}};
    HPSU_Log("HPSU ".__LINE__.": Init start: \"$sque\"") if (AttrVal($name, "DebugLog", "off") =~ "on");
    DevIo_SimpleWrite($hash, $sque."\r", 2);
  }
  else
  {
    HPSU_Log("HPSU ".__LINE__.": Init failed: Eror while parsing JSON file !" ) if (AttrVal($name, "DebugLog", "off") eq "on");
  }

  return undef;
}

sub HPSU_Attr($$$$)
{
  my ( $cmd, $name, $attrName, $attrValue ) = @_;
  my $hash = $defs{$name};

  if($cmd eq "set")
  {
    if($attrName eq "AntiMixerSwing")
    {
      if($attrValue eq "on")
      {
        #needed for "AntiMixerSwing" checking...
        $hash->{jcmd}{status_pump}{FHEMPollTime} = 300 if ($hash->{jcmd}{status_pump}{FHEMPollTime} < 1);
      }
    }
    
    if ($attrName eq "AntiContinousHeating")
    {
      if ($attrValue =~ "on")
      {
        my ($major, $minor) = split('\.', $hash->{JSON_version});
        
        HPSU_Read_JSON_updreadings($hash);
        if ($major < 3 || $minor < 6)
        {
          $attr{$name}{"AntiContinousHeating"} = "off";
          push @{$hash->{helper}{queue}}, "t_frost_protect";
          return "At least JSON version 3.6 is required for $attrName attribute!";
        }
        if ($hash->{System} ne "comfort")
        {
          $attr{$name}{"AntiContinousHeating"} = "off";
          return "Not possible and not necessary with $hash->{System}";
        }
      }
    }
  }

  if ($attrName eq "AntiShortCycle")
  {
    if($cmd eq "set")
    {
      if ($attrValue ne "0")
      {
        return "Wrong parameters - examples are: \"0\", \"1\" or \"1;3;30\"" if (not ($attrValue =~ /(^\d+;\d+;\d+$)|(^\d+$)/));
        readingsSingleUpdate($hash, "Info.AntiShortCycle", "Idle", 1);
        return undef;
      }
    }
    
    readingsDelete($hash, "Info.AntiShortCycle");
    delete $hash->{helper}{ShortCycle};
  }

  return undef;
}

sub HPSU_DbLog_split($$)
{
  my ($event, $device) = @_;
  my $reading = "";
  my $value = "";
  my $unit = "";
  my @parts = split(/ /, $event, 3);
 
  if(defined($parts[1]))
  {
    $reading = $parts[0];
    chop $reading;
    $value = $parts[1];
    $unit = $parts[2] if(defined($parts[2]));
  }
  return ($reading, $value, $unit);  
}

### FHEM HIFN ###
sub HPSU_Disconnect($)
{
  my ($hash) = @_;

  $hash->{ELMState} = "disconnected";
  RemoveInternalTimer($hash);
  sleep(0.3);  ##wait if pending commands...

  # close the connection
  DevIo_CloseDev($hash);

  return undef;
}

sub HPSU_Stat_Task($$$)
{
  my ($hash, $name, $oldval) = @_;
      
  if ($name) #new value
  {
    my $key = $name;
    return if (not defined $hash->{jcmd}{$key}{statistic});
    
    my $val = ReadingsNum($hash->{NAME},"HPSU.$hash->{jcmd}{$key}{name}",0);
    
    if (defined $hash->{stat}{$key}{hour})
    {
      my $avg = 0;                
      
      $hash->{stat}{$key}{hour}{max} = $val if ($hash->{stat}{$key}{hour}{max} < $val);
      $hash->{stat}{$key}{hour}{min} = $val if ($hash->{stat}{$key}{hour}{min} > $val);
      
      if ($oldval != $val)
      {
        $hash->{stat}{$key}{hour}{avg} += $val;
        $hash->{stat}{$key}{hour}{avgCnt}++;
      }
    }
    else
    {
      $hash->{stat}{$key}{hour}{min} = $val;
      $hash->{stat}{$key}{hour}{avg} = $val;
      $hash->{stat}{$key}{hour}{max} = $val;
      $hash->{stat}{$key}{hour}{avgCnt} = 1;
    }    
  }
  else
  {
    my $NextHour = 3600 * ( int((gettimeofday()+5)/3600) + 1 ) - 5;
    
    foreach my $key (@{$hash->{helper}{PollTimeKeys}})
    {
      if (defined $hash->{jcmd}{$key}{statistic})
      {
        next if (not defined $hash->{stat}{$key});
        
        my $min = sprintf("%.01f", $hash->{stat}{$key}{hour}{min});
        my $max = sprintf("%.01f", $hash->{stat}{$key}{hour}{max});
        my $avg = ($max+$min)/2;
        if ($hash->{stat}{$key}{hour}{avgCnt}) #.. no values but full hour -> crash because of avgCnt == 0 !!
        {
          $avg = sprintf("%.02f", $hash->{stat}{$key}{hour}{avg} / $hash->{stat}{$key}{hour}{avgCnt});
        }
        if ($hash->{jcmd}{$key}{statistic} =~ "h")
        {
          readingsSingleUpdate($hash, "Stat.HPSU.$hash->{jcmd}{$key}{name}.Hour", "Min: $min Avg: $avg Max: $max", 1);
        }
        my $val = ReadingsNum($hash->{NAME},"HPSU.$hash->{jcmd}{$key}{name}",0);        
        $hash->{stat}{$key}{hour}{min} = $val;
        $hash->{stat}{$key}{hour}{avg} = $val;
        $hash->{stat}{$key}{hour}{max} = $val;
        $hash->{stat}{$key}{hour}{avgCnt} = 1;
        
        if ($hash->{jcmd}{$key}{statistic} =~ "d")
        {
          my $init = 0;
          
          if (not defined $hash->{stat}{$key}{day})
          {
            $init = 1;
          }
          else
          {
            my $avgDay = 0;
            my $hour = ( localtime )[2];  #securer than fhem "hour"
            
            $hash->{stat}{$key}{day}{max} = $max if ($hash->{stat}{$key}{day}{max} < $max);
            $hash->{stat}{$key}{day}{min} = $min if ($hash->{stat}{$key}{day}{min} > $min);            
            $hash->{stat}{$key}{day}{avg} += $avg;
            $hash->{stat}{$key}{day}{avgCnt}++;
            $avgDay = sprintf("%.02f", $hash->{stat}{$key}{day}{avg} / $hash->{stat}{$key}{day}{avgCnt});
            readingsSingleUpdate($hash, "Stat.HPSU.$hash->{jcmd}{$key}{name}.Day", "Min: $hash->{stat}{$key}{day}{min} ".
                                                                                   "Avg: $avgDay ".
                                                                                   "Max: $hash->{stat}{$key}{day}{max}", 1);
            if ($hour == 23)
            {
              $init = 1;
            }
          }
          if ($init)
          {
            $hash->{stat}{$key}{day}{min} = $min;
            $hash->{stat}{$key}{day}{avg} = $avg;
            $hash->{stat}{$key}{day}{max} = $max;
            $hash->{stat}{$key}{day}{avgCnt} = 1;
          }
        }
      }
    }
    
    InternalTimer($NextHour, "HPSU_Stat_Task", $hash);
  }
}

sub HPSU_Task($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $jcmd = $hash->{jcmd};

  return undef if ($hash->{ELMState} ne "Initialized");
  return undef if ($hash->{helper}{MonitorMode});

  my $AktMode = ReadingsVal($name, "HPSU.$hash->{jcmd}{mode}{name}","Standby");
  my $AktMode_01 = ReadingsVal($name, "HPSU.$hash->{jcmd}{mode_01}{name}","Bereitschaft");
  $hash->{helper}{HPSULstMode} = $AktMode if (!exists($hash->{helper}{HPSULstMode}));
  $hash->{helper}{HPSULstMode_01} = $AktMode_01 if (!exists($hash->{helper}{HPSULstMode_01}));
  my $HPSUModeIdle = $AktMode_01 eq $hash->{jcmd}{mode_01}{value_code}{"1"};

  if ($hash->{helper}{HPSULstMode} ne $AktMode)
  {
    $hash->{helper}{TStandby} = gettimeofday() if ($AktMode eq $hash->{jcmd}{mode}{value_code}{"0"});
    $hash->{helper}{THeat}    = gettimeofday() if ($AktMode eq $hash->{jcmd}{mode}{value_code}{"1"});
  }
  
  if ($hash->{helper}{CANRequestPending} > 0)
  {
    if ($hash->{helper}{CANRequestPending} + 4.0 < gettimeofday() ) #3,5 sometimes needed ! 
    {
      if ($hash->{helper}{queue}[0]) #set pending ?
      {
        $hash->{helper}{CANRequestPending} = -1;
      }
      else
      {
        if (not defined $hash->{helper}{GetStatusError})
        {
          $hash->{helper}{GetStatusError} = 1;
          HPSU_CAN_RequestReadings($hash, $hash->{helper}{CANRequestName}, undef);  #send lst request again
          if (AttrVal($name, "SuppressRetryWarnings", "on") eq "off" and 
              AttrVal($name, "DebugLog", "off") eq "on")
          {
            HPSU_Log("HPSU ".__LINE__.": Comm.GetStatus Error: retry name: $hash->{helper}{CANRequestName}" );
          }
        }
        else
        {
          delete $hash->{helper}{GetStatusError};
          readingsSingleUpdate($hash, "Comm.GetStatus", "Error: timeout name: $hash->{helper}{CANRequestName} (".__LINE__.")", 1);
          HPSU_Log("HPSU ".__LINE__.": Comm.GetStatus Error: timeout name: $hash->{helper}{CANRequestName} raw: $hash->{helper}{PARTIAL}" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
          $hash->{helper}{CANRequestPending} = -1;
        }
      }
    }
  }
  if ($hash->{helper}{CANRequestPending} == 0 && defined $hash->{helper}{GetStatusError})
  {
    delete $hash->{helper}{GetStatusError};
    readingsSingleUpdate($hash, "Comm.GetStatus", "Ok", 1);
    if (AttrVal($name, "SuppressRetryWarnings", "on") eq "off" and 
        AttrVal($name, "DebugLog", "off") eq "on")
    {
      HPSU_Log("HPSU ".__LINE__.": Comm.GetStatus Ok: retry name: $hash->{helper}{CANRequestName}" );
    }
  }

  #Firmware bug of RoCon?
  #if mixer schwing from 20 to 100% the whole time....
  if (AttrVal($name, "AntiMixerSwing", "off") eq "on")
  {
    my $status_pump_WasActive = ReadingsVal($name, "HPSU.$hash->{jcmd}{status_pump}{name}","active") eq
                                $hash->{jcmd}{status_pump}{value_code}{"1"};
    my $Mod_Cool   = ReadingsVal($name, "HPSU.$hash->{jcmd}{mode_01}{name}","Kuehlen") eq
                     $hash->{jcmd}{mode_01}{value_code}{"17"};
    #t_hs_set wird zum Check verwendet, ob WP tatsaechlich im ES ist - auf $status_pump_WasActive allein kann man sich nicht verlassen!!
    my $T_VlWez = ReadingsNum($name, "HPSU.$hash->{jcmd}{t_hs_set}{name}", 10);  #Soll_Vorlauftemperatur_Waermeerzeuger 0

    $hash->{helper}{status_pump_WasActive} = 0 if (not exists ($hash->{helper}{status_pump_WasActive}));
    $hash->{helper}{status_pump_LstTimeActive} = 0 if (not exists ($hash->{helper}{status_pump_LstTimeActive}));
    $hash->{helper}{HPSULstModeTime} = 0 if (not exists ($hash->{helper}{HPSULstModeTime}));

    if ($hash->{helper}{HPSULstMode_01} ne $AktMode_01)
    {
      $hash->{helper}{HPSULstModeTime} = gettimeofday();
    }

    if ($status_pump_WasActive)
    {
      $hash->{helper}{status_pump_WasActive} = 1;
      $hash->{helper}{status_pump_LstTimeActive} = gettimeofday();
    }
    if (!$status_pump_WasActive and $T_VlWez <= 0) #Wenn WP im ES war und z.B. WW bereitet
    {
      $hash->{helper}{status_pump_WasActive} = 0;
    }

    if (!$status_pump_WasActive and
        $hash->{helper}{status_pump_WasActive} == 1 and
        $hash->{helper}{status_pump_LstTimeActive}+2.5*60 < gettimeofday() and
        $T_VlWez > 0 and
        $hash->{helper}{HPSULstModeTime}+5*60 < gettimeofday() and
        !$Mod_Cool and
        ReadingsNum($name, "HPSU.$hash->{jcmd}{t_dhw}{name}", 48) > 35.5)
    {
      push @{$hash->{helper}{queue}}, "mode_01;$hash->{jcmd}{mode_01}{value_code}{'1'}";
      push @{$hash->{helper}{queue}}, "mode_01;$AktMode_01";
      push @{$hash->{helper}{queue}}, "status_pump";
      
      $hash->{helper}{status_pump_WasActive} = 0;
      
      HPSU_Log("HPSU ".__LINE__.": AntiMixerSwing occurred" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
    }
  }

  ### Check if compressor has short cycle
  my $AntiShortCycleVal = AttrVal($name, "AntiShortCycle", undef);
  if ($AntiShortCycleVal)
  {
    my $MaxDiff = 1;
    my $MinTimeMaxDiff = 3;
    my $TimeSuspend = 30;
    
    if ($AktMode eq $hash->{jcmd}{mode}{value_code}{"1"})      #"Heizen"
    {
      if ($AntiShortCycleVal =~ /^\d+;\d+;\d+$/)
      {
        ($MaxDiff, $MinTimeMaxDiff, $TimeSuspend) = split(";", $AntiShortCycleVal);
      }
      if ( (ReadingsNum($name, "HPSU.$hash->{jcmd}{t_hc}{name}", 0) -
            ReadingsNum($name, "HPSU.$hash->{jcmd}{t_hc_set}{name}", 0)) > $MaxDiff )
      {
        if (not defined $hash->{helper}{ShortCycle}{TimeMaxDiff})
        {
          $hash->{helper}{ShortCycle}{TimeMaxDiff} = gettimeofday();
        }
        elsif ($hash->{helper}{ShortCycle}{TimeMaxDiff}+$MinTimeMaxDiff*60 < gettimeofday())
        {
          if (not defined $hash->{helper}{ShortCycle}{TimeMaxDiffOccurred})
          {
            $hash->{helper}{ShortCycle}{TimeMaxDiffOccurred} = 1;
            readingsSingleUpdate($hash, "Info.AntiShortCycle", "MaxDiffOccurred", 1);
            HPSU_Log("HPSU ".__LINE__.": AntiShortCycle - MaxDiffOccurred" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
          }
        }
      }
      else
      {
        delete $hash->{helper}{ShortCycle}{TimeMaxDiff}; 

        if (defined $hash->{helper}{ShortCycle}{TimeMaxDiffOccurred})
        {
          delete $hash->{helper}{ShortCycle}{TimeMaxDiffOccurred};
          readingsSingleUpdate($hash, "Info.AntiShortCycle", "Idle", 1);
          HPSU_Log("HPSU ".__LINE__.": AntiShortCycle - Idle" ) if (AttrVal($name, "DebugLog", "off") =~ "on");          
        }
      }
    }
    if ($hash->{helper}{HPSULstMode} ne $AktMode)
    {
      delete $hash->{helper}{ShortCycle}{TimeMaxDiff}; #if occurred but mode change before
      
      if (defined $hash->{helper}{ShortCycle}{TimeMaxDiffOccurred})
      {
        delete $hash->{helper}{ShortCycle}{TimeMaxDiffOccurred};
        
        if (    $AktMode eq $hash->{jcmd}{mode}{value_code}{"3"}     #Abtauen
            or  $AktMode eq $hash->{jcmd}{mode}{value_code}{"4"} )   #DHW
        {
          readingsSingleUpdate($hash, "Info.AntiShortCycle", "Idle", 1);
          HPSU_Log("HPSU ".__LINE__.": AntiShortCycle - Idle - reset because \"$AktMode\"" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
          delete $hash->{helper}{ShortCycle};
        }
        else
        {
          if ($AntiShortCycleVal =~ /^\d+;\d+;\d+$/)
          {
            ($MaxDiff, $MinTimeMaxDiff, $TimeSuspend) = split(";", $AntiShortCycleVal);
          }
          $hash->{helper}{ShortCycle}{TimeSuspend} = gettimeofday()+$TimeSuspend*60;
          readingsSingleUpdate($hash, "Info.AntiShortCycle", "on", 1);
          HPSU_Log("HPSU ".__LINE__.": AntiShortCycle - on" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
          $hash->{helper}{ShortCycle}{BModeStart} = ReadingsVal($name, "HPSU.$hash->{jcmd}{mode_01}{name}","Heizen");
          push @{$hash->{helper}{queue}}, "mode_01;$hash->{jcmd}{mode_01}{value_code}{'5'}"; #"Sommer"
        }
      }
    }
    if (defined $hash->{helper}{ShortCycle}{TimeSuspend})
    {
      if ($hash->{helper}{ShortCycle}{TimeSuspend} < gettimeofday())
      {
        HPSU_Set($hash, $name, "Reset.ShortCycleSuspend");
      }
    }

    if ($hash->{helper}{HPSULstMode_01} ne $AktMode_01)
    {
      delete $hash->{helper}{ShortCycle} if ($HPSUModeIdle);
    }
  }
  
  ### Check if DHW is interrupted
  #$hash->{helper}{DHWChkStatus} => 0: off, 1: active, 1>: restart

  #helper variables DHW "is interrupted" and "Force"
  my $DHWDiffBig = (ReadingsNum($name, "HPSU.$hash->{jcmd}{t_dhw_setpoint1}{name}",48) >
                    ReadingsNum($name, "HPSU.$hash->{jcmd}{t_dhw}{name}",          48) + 0.5);
  my $DHWactive  =  ReadingsVal($name, "HPSU.$hash->{jcmd}{mode}{name}","Standby") eq
                                             $hash->{jcmd}{mode}{value_code}{"4"};
  my $DHWdefrost =  ReadingsVal($name, "HPSU.$hash->{jcmd}{mode}{name}","Standby") eq
                                             $hash->{jcmd}{mode}{value_code}{"3"};
                                              
  if (AttrVal($name, "CheckDHWInterrupted", "off") eq "on")
  {
    if (defined $hash->{helper}{DHWChkStatus})
    {
      if (not $DHWDiffBig or $HPSUModeIdle)
      {
        delete $hash->{helper}{DHWChkStatus};
      }
      else
      {
        if (not $DHWactive and not $DHWdefrost)
        {
          if ($hash->{helper}{DHWChkStatus} == 1)
          {
            $hash->{helper}{DHWChkStatus} += 1;
            $hash->{helper}{DHWForce} = gettimeofday()+4*60;
          }
        }
      }
    }
    else
    {
      if ($DHWactive)
      {
        $hash->{helper}{DHWChkStatus} = 1;
      }
    }
  }

  ### Force DHW  
  if (defined($hash->{helper}{DHWForce}))
  {
    my $del = 0;
    
    if ($hash->{helper}{DHWForce} <= gettimeofday())
    {
      my $ForceDHWFrom_CheckDHWInterrupted = defined $hash->{helper}{DHWChkStatus}
                                                  && $hash->{helper}{DHWChkStatus} > 1;
      if ($ForceDHWFrom_CheckDHWInterrupted)
      {
        HPSU_Log("HPSU ".__LINE__.": ForceDHW from CheckDHWInterrupted" ) if (AttrVal($name, "DebugLog", "off") =~ "on|onDHW");
      }
      
      if (defined($hash->{helper}{DHWForceDesTempFromSet}))
      {
        $DHWDiffBig = ($hash->{helper}{DHWForceDesTempFromSet} >
                       ReadingsNum($name, "HPSU.$hash->{jcmd}{t_dhw}{name}", 48) + 0.5);
      }

      if (defined $hash->{helper}{TStandby} and
          $AktMode eq $hash->{jcmd}{mode}{value_code}{"0"} and 
          $hash->{helper}{TStandby}+60 > gettimeofday())
      {
        $hash->{helper}{DHWForce} = $hash->{helper}{TStandby}+3*60;
        readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: ForceDHW pending (".__LINE__.")", 1);
      }
      elsif (not $DHWDiffBig)
      {
        readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: ForceDHW diff to small (".__LINE__.")", 1);
      }
      elsif ($DHWactive)
      {
        if (not $ForceDHWFrom_CheckDHWInterrupted)
        {
          readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: DHW still active (".__LINE__.")", 1);
        }
      }
      else
      {
        if (defined ($hash->{helper}{DHWForceState}))
        {
          readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: (Force)DHW still active (".__LINE__.")", 1);
        }
        else
        {
          $hash->{helper}{DHWForceState} = 1;
          
          $hash->{helper}{DHWForceDesTemp} = defined($hash->{helper}{DHWForceDesTempFromSet})?$hash->{helper}{DHWForceDesTempFromSet}:
                                             ReadingsNum($name, "HPSU.$hash->{jcmd}{t_dhw_setpoint1}{name}", 48);
        }
      }

      $del = ($hash->{helper}{DHWForce} <= gettimeofday());
    }

    if ($HPSUModeIdle || $del)
    { # |--> if $hash->{helper}{DHWForce} is waiting
      delete $hash->{helper}{DHWForce};
      delete $hash->{helper}{DHWForceDesTempFromSet};
    }
  }
  
  if (defined ($hash->{helper}{DHWForceState}))
  {
    my $ok = 1;
    
    if ($HPSUModeIdle)
    {
      readingsSingleUpdate($hash, "Comm.ManStatus", "Info: ForceDHW - Mode idle (".__LINE__.")", 1);
      HPSU_Log("HPSU ".__LINE__.": ForceDHW not possible - HPSU mode idle" ) if (AttrVal($name, "DebugLog", "off") =~ "onDHW");
      $hash->{helper}{DHWForceState} = 3; #set to last step
      $ok = 0; #HPSU mode idle
    }
    
    if (not defined $hash->{helper}{DHWForceLstTime})
    {
      $hash->{helper}{DHWForceLstTime} = gettimeofday();
    }
    else
    {
      if ($hash->{helper}{DHWForceLstTime}+60 < gettimeofday())
      {
        readingsSingleUpdate($hash, "Comm.ManStatus", "Error: ForceDHW timeout (".__LINE__.")", 1);
        HPSU_Log("HPSU ".__LINE__.": ForceDHW timeout}" ) if (AttrVal($name, "DebugLog", "off") =~ "onDHW");
        $hash->{helper}{DHWForceState} = 3; #set to last step
        $ok = 0; #Timeout
      }
    }
    
    if ($hash->{helper}{DHWForceState} == 1)
    {
      push @{$hash->{helper}{queue}}, "t_dhw_setpoint1;69";
      $hash->{helper}{DHWForceState} = 2;
      HPSU_Log("HPSU ".__LINE__.": ForceDHW push 69deg" ) if (AttrVal($name, "DebugLog", "off") =~ "onDHW");
    }
    if ($hash->{helper}{DHWForceState} == 2)
    {
      if ($DHWactive)
      {
        $hash->{helper}{DHWForceState} = 3;
        HPSU_Log("HPSU ".__LINE__.": ForceDHW push 60deg -> active" ) if (AttrVal($name, "DebugLog", "off") =~ "onDHW");
      }
    }
    if ($hash->{helper}{DHWForceState} == 3)
    {
      push @{$hash->{helper}{queue}}, "t_dhw_setpoint1;$hash->{helper}{DHWForceDesTemp}";
      if ($ok)
      {
        readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: ForceDHW (".__LINE__.")", 1);
        HPSU_Log("HPSU ".__LINE__.": ForceDHW ok -> Dest Temp: $hash->{helper}{DHWForceDesTemp}" ) if (AttrVal($name, "DebugLog", "off") =~ "onDHW");
      }

      delete $hash->{helper}{DHWForceLstTime};
      delete $hash->{helper}{DHWForceDesTemp};
      delete $hash->{helper}{DHWForceState};
    }
  }

  #Reading Status "Info.LastDefrostDHWShrink" defrost
  #AntiContinousHeating while heating
  if (not defined $hash->{helper}{AntiCHeat}{State})
  {
    if ($AktMode                     eq $hash->{jcmd}{mode}{value_code}{"3"} and   #"Abtauen"
        $hash->{helper}{HPSULstMode} eq $hash->{jcmd}{mode}{value_code}{"1"})      #"Heizen"
    {
      if (AttrVal($name, "AntiContinousHeating", "off") eq "on")
      {
        $hash->{helper}{AntiCHeat}{StateTime} = gettimeofday();
        $hash->{helper}{AntiCHeat}{State} = 1;
        $hash->{helper}{AntiCHeat}{DHWStart} = ReadingsNum($name, "HPSU.$hash->{jcmd}{t_dhw}{name}",48);
        $hash->{helper}{AntiCHeat}{BModeStart} = ReadingsVal($name, "HPSU.$hash->{jcmd}{mode_01}{name}","Heizen");

        my $t_frost_protect = ReadingsVal($name, "HPSU.$hash->{jcmd}{t_frost_protect}{name}","NotRead");
        if ($t_frost_protect ne $hash->{jcmd}{t_frost_protect}{value_code}{'-160'})  #-160 -> "Aus"
        {
          $hash->{helper}{t_frost_protect_lst} = $t_frost_protect;
          if ($hash->{helper}{t_frost_protect_lst} ne "NotRead")
          {
            push @{$hash->{helper}{queue}}, "t_frost_protect;$hash->{jcmd}{t_frost_protect}{value_code}{'-160'}"; 
            HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set Frost from $t_frost_protect to Off" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
          }
        }
        push @{$hash->{helper}{queue}}, "mode_01;$hash->{jcmd}{mode_01}{value_code}{'5'}"; #"Sommer"
        
        HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set to $hash->{jcmd}{mode_01}{value_code}{'5'}" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
      }
    }
  }
  elsif ($hash->{helper}{AntiCHeat}{State} == 1)
  {
    if ($AktMode ne $hash->{jcmd}{mode}{value_code}{"3"} or   #"Abtauen"
        $hash->{helper}{AntiCHeat}{StateTime}+15*60 < gettimeofday()) #emergency exit after 15min
    {
      $hash->{helper}{AntiCHeat}{StateTime} = gettimeofday();
      $hash->{helper}{AntiCHeat}{State}++;
      
      push @{$hash->{helper}{queue}}, "mode_01;$hash->{helper}{AntiCHeat}{BModeStart}";      
      HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set to $hash->{helper}{AntiCHeat}{BModeStart}" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
      if(exists $hash->{helper}{t_frost_protect_lst})
      {
        if ($hash->{helper}{t_frost_protect_lst} ne "NotRead")
        {
          push @{$hash->{helper}{queue}}, "t_frost_protect;$hash->{helper}{t_frost_protect_lst}";
          HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set Frost to $hash->{helper}{t_frost_protect_lst}" ) if (AttrVal($name, "DebugLog", "off") eq "on");
        }
        delete $hash->{helper}{t_frost_protect_lst};
      }
    }
  }
  elsif ($hash->{helper}{AntiCHeat}{State} == 2)
  {
    my $time = $hash->{helper}{AntiCHeat}{StateTime}+4.0*60 < gettimeofday(); #settling time 4min, then dhw is definitely stable
    
    if ($time)
    {
      push @{$hash->{helper}{queue}}, "t_dhw";   
      $hash->{helper}{AntiCHeat}{StateTime} = gettimeofday();
      $hash->{helper}{AntiCHeat}{State}++;
    }
  }
  elsif ($hash->{helper}{AntiCHeat}{State} == 3)
  {
    my $timeout = $hash->{helper}{AntiCHeat}{StateTime}+30 < gettimeofday(); #emergency exit after 30sec
    
    if (ReadingsAge($name, "HPSU.$hash->{jcmd}{t_dhw}{name}", -1)+1 < gettimeofday() or   #new DHW value
        $timeout)
    {
      if (not $timeout)
      {
        my $val = $hash->{helper}{AntiCHeat}{DHWStart} - ReadingsNum($name, "HPSU.$hash->{jcmd}{t_dhw}{name}",48);
        $val = sprintf("%.02f", $val);
        readingsSingleUpdate($hash, "Info.LastDefrostDHWShrink", "$val °C", 1);
      }
      delete $hash->{helper}{AntiCHeat};
    }
  }

  if (exists($hash->{JSON_parameters}) and $hash->{JSON_parameters} > 0)
  {
    ### Read or set parameter
    # Queue -> manual request or set value
    if ($hash->{helper}{CANRequestPending} <= 0)
    {
      if ($hash->{helper}{queue}[0])
      {
        my $cntdp = $hash->{helper}{queue}[0] =~ tr/;//;
        
        if ($cntdp == 0) #request
        {
          my $name = shift @{$hash->{helper}{queue}};
          
          HPSU_CAN_RequestReadings($hash, $name, undef);
        }
        elsif ($cntdp == 1) #value change requested?
        {
          $hash->{helper}{queue}[0] .= ";check;3"; # -> retry 3 times
        }
      }
      
      if ($hash->{helper}{queue}[0])
      {
        #set value if necessary and verify
        my $cntdp = $hash->{helper}{queue}[0] =~ tr/;//;
        
        if ($cntdp >= 3) #Str format: name;val;state;rep[;TimeForRetry]
        {
          my ($key, $val, $state, $rep, $repWait) = split(";", $hash->{helper}{queue}[0]);
          my $AktVal = ReadingsVal($name, "HPSU.$hash->{jcmd}{$key}{name}", undef);
          my $infoName = "\"$hash->{jcmd}{$key}{name}\" [$key]";
          
          if ($state eq "check")
          {
            my $noRes = 0;
            
            if (defined $hash->{jcmd}{$key}{option})
            {
              if ($hash->{jcmd}{$key}{option} =~ "noRes")
              {
                my $sque = shift @{$hash->{helper}{queue}};
                
                HPSU_CAN_RequestReadings($hash, $key, $val);
                readingsSingleUpdate($hash, "Comm.SetStatus", "Ok: $infoName set to \"$val\" (".__LINE__.")", 1);                
                $noRes = 1;
              }
            }
            
            if (!$noRes)
            {
              if ( not defined $AktVal 
                    or ReadingsAge($name, "HPSU.$hash->{jcmd}{$key}{name}", -1) + 0.5 < gettimeofday() 
                  )
              {
                HPSU_CAN_RequestReadings($hash, $key, undef);
              }
              $hash->{helper}{queue}[0] = "$key;$val;checkAktVal;$rep";
            }
          }

          if ( $state eq "checkAktVal" or
               $state eq "verify" )
          {
            if (defined $AktVal)
            {
              my $isSame = 0;

              if ( $hash->{jcmd}{$key}{FHEMControl} and
                  ($hash->{jcmd}{$key}{FHEMControl} eq "value_code") )
              {
                $isSame = $AktVal eq $val;
              }
              else
              {
                $isSame = $val == ReadingsNum($name, "HPSU.$hash->{jcmd}{$key}{name}", -999);
              }

              if ($state eq "checkAktVal")
              {
                if ($isSame)
                {
                  my $sque = shift @{$hash->{helper}{queue}};
                  readingsSingleUpdate($hash, "Comm.SetStatus", "Ok: $infoName already set to \"$val\" (".__LINE__.")", 1);
                }
                else
                {
                  $hash->{helper}{queue}[0] = "$key;$val;write;$rep";
                }
              }
              else # "verify"
              {
                if ($isSame)
                {
                  my $sque = shift @{$hash->{helper}{queue}};
                  readingsSingleUpdate($hash, "Comm.SetStatus", "Ok: $infoName successfully set to \"$val\" (".__LINE__.")", 1);
                  if (defined $hash->{jcmd}{$key}{repeatTime})
                  {
                    $jcmd->{$key}{repeatPending} = gettimeofday()+$hash->{jcmd}{$key}{repeatTime};
                    $jcmd->{$key}{repeatVal} = $val;
                  }
                }
                else
                {
                  if (--$rep <= 0)
                  {
                    my $sque = shift @{$hash->{helper}{queue}};
                    readingsSingleUpdate($hash, "Comm.SetStatus", "Error: $infoName verify failed (".__LINE__.")", 1);
                  }
                  else
                  {
                    #retry
                    my $RetryTimeStamp = gettimeofday()+2;
                    
                    $hash->{helper}{queue}[0] = "$key;$val;write;$rep;$RetryTimeStamp";
                    readingsSingleUpdate($hash, "Comm.SetStatus", "Retry: set $infoName to \"$val\" (".__LINE__.")", 1);
                    HPSU_Log("HPSU ".__LINE__.": Set retry cmd: $hash->{helper}{queue}[0]" ) if (AttrVal($name, "DebugLog", "off") =~ "on");
                  }
                }
              }
            }
            else
            {
              my $sque = shift @{$hash->{helper}{queue}};
              readingsSingleUpdate($hash, "Comm.SetStatus", "Error: $infoName undefined value (".__LINE__.")", 1);
            }
          }

          if ($state eq "write")
          {
            if (!$repWait || $repWait < gettimeofday())
            {
              HPSU_CAN_RequestReadings($hash, $key, $val);
              $hash->{helper}{queue}[0] = "$key;$val;read;$rep";
            }
          }

          if ($state eq "read")
          {
            HPSU_CAN_RequestReadings($hash, $key, undef);
            $hash->{helper}{queue}[0] = "$key;$val;verify;$rep";
          }
        }
      }
    }

    ### Autopoll
    if (AttrVal($name, "AutoPoll", "on") eq "on")
    {
      if ($hash->{helper}{CANRequestPending} <= 0)
      {
        my $i = 0;

        foreach my $key (@{$hash->{helper}{PollTimeKeys}})
        {
          if ($hash->{helper}{autopollState} == $i)
          {
            my $Age = ReadingsAge($name, "HPSU.$hash->{jcmd}{$key}{name}", -999);

            if (    $Age < 0                                             #never requested since yet
                 or $Age >= $jcmd->{$key}{FHEMPollTime}) #poll time
            {
              HPSU_CAN_RequestReadings($hash, $key, undef);
              
              if (defined $hash->{jcmd}{$key}{repeatPending})
              {
                if ($hash->{jcmd}{$key}{repeatPending} <= gettimeofday())
                {
                  push @{$hash->{helper}{queue}}, "$key;$jcmd->{$key}{repeatVal}";
                  
                  delete $hash->{jcmd}{$key}{repeatPending};
                  delete $hash->{jcmd}{$key}{repeatVal};
                }
              }
              last;
            }
          }
          $i++;
        }

        $hash->{helper}{autopollState} += 1;
        $hash->{helper}{autopollState} = 0 if ($hash->{helper}{autopollState} > @{$hash->{helper}{PollTimeKeys}});
      }
    }
  }
  else
  {
    $hash->{helper}{autopollState} = 0;
    $hash->{helper}{CANRequestPending} = 0;
  }

  ### Calculate Akt Q and temperature spread
  my $AktQ = 0;
  my $AktTs = 0;
  my $t_hs = ReadingsNum($name, "HPSU.$hash->{jcmd}{t_hs}{name}",-100);
  my $t_r1 = ReadingsNum($name, "HPSU.$hash->{jcmd}{t_r1}{name}",-100);
  my $flow_rate = ReadingsNum($name, "HPSU.$hash->{jcmd}{flow_rate}{name}",-100);
  my $compressor_active = (defined $hash->{jcmd}{comp_aktiv}{name}) ? 
                          ReadingsVal($name, "HPSU.$hash->{jcmd}{comp_aktiv}{name}","") : "on";

  if ( ($AktMode eq $hash->{jcmd}{mode}{value_code}{"1"} or   #"Heizen"
        $AktMode eq $hash->{jcmd}{mode}{value_code}{"2"} or   #"Kuehlen"
        $AktMode eq $hash->{jcmd}{mode}{value_code}{"4"}) and #"Warmwasserbereitung"
        $compressor_active eq "on" and
        $t_hs > -100 and
        $t_r1 > -100 and
        $flow_rate > -100 )
  {
    #Q = m * c * delta t
    $AktQ = ( ($t_hs-$t_r1) * 4.19 * $flow_rate) / 3600;
    $AktQ = sprintf("%.03f", $AktQ);
    $AktTs = sprintf("%.02f", $t_hs-$t_r1);
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash, "Info.Q", "$AktQ kW");
  readingsBulkUpdateIfChanged($hash, "Info.Ts", "$AktTs °C");
  readingsEndUpdate($hash, 1);

  ### evaluation heating error: cyclic operation
  if ($hash->{helper}{HPSULstMode} ne $AktMode)
  {
    if ($hash->{helper}{HPSULstMode} eq $hash->{jcmd}{mode}{value_code}{"1"})   #"Heizen"
    {
      if (defined $hash->{helper}{TStandby} and defined $hash->{helper}{THeat})
      {
        if (($hash->{helper}{TStandby} - $hash->{helper}{THeat}) < 8*60)
        {
          my $val = ReadingsVal("$name","Info.HeatCyclicErr", "0");
          readingsSingleUpdate($hash,   "Info.HeatCyclicErr", $val+1, 1);
        }
      }
    }
    if ($AktMode eq $hash->{jcmd}{mode}{value_code}{"3"})  #"Abtauen")
    {
      readingsSingleUpdate($hash, "Info.HeatCyclicErr", 0, 1);
    }
  }
  if (ReadingsAge("$name", "Info.HeatCyclicErr", 0) > 20*60 )
  {
    readingsSingleUpdate($hash, "Info.HeatCyclicErr", 0, 1);
  }

  $hash->{helper}{HPSULstMode} = $AktMode;
  $hash->{helper}{HPSULstMode_01} = $AktMode_01;

  InternalTimer(gettimeofday()+0.05, "HPSU_Task", $hash);
}

sub HPSU_Read_JSON_updreadings($)
{
  my ($hash) = @_;
  my ($anz, $str) = HPSU_Read_JSON_File($hash);

  $hash->{JSON_parameters} = $anz;
  $str = "Error $anz: $str" if ($anz < 0);
  $hash->{JSON_version} = $str;
  
  return 1 if ($anz < 0);

  my $jcmd = $hash->{jcmd};  #after HPSU_Read_JSON_File() valid !
  
  my @PollTimekeys = grep ( $jcmd->{$_}{FHEMPollTime} > 0, sort keys %{$jcmd});
  $hash->{helper}{PollTimeKeys} = \@PollTimekeys;
  $hash->{JSON_Auto_poll} = @PollTimekeys;  #Web Info
  my @Writablekeys = grep ( $jcmd->{$_}{writable} eq "true", sort keys %{$jcmd});
  $hash->{helper}{Writablekeys} = \@Writablekeys;
  $hash->{JSON_Writable} = @Writablekeys;   #Web Info
  
  return 0;
}

sub HPSU_CAN_RequestReadings($$$)
{
  my ( $hash, $hpsuNameCmd, $setVal ) = @_;
  my $jcmd = $hash->{jcmd};
  my ($CANMsg) = HPSU_CAN_RequestOrSetMsg($hash, $hpsuNameCmd, $setVal);

  #get res id:
  #example 61 00 05 00 00 00 00  ->  0x60 = 0x06 * 0x10 * 0x08 = 0x300
  $hash->{helper}{CANResponseHeaderID} = sprintf("%X", hex(substr($CANMsg, 0, 1)) * 0x10 * 0x08);
  $hash->{helper}{CANRequestPending} = gettimeofday();
  
  if (defined $setVal)
  {
    $hash->{helper}{CANRequestName} = "NO DATA";
  }
  else
  {
    $hash->{helper}{CANRequestName} = $hpsuNameCmd;
  }
  
  $hash->{helper}{CANRequestHeaderID} = "680";  # http://www.juerg5524.ch -> 680 - PC (ComfortSoft)
                                       #  |--> RoCon Display has 10A - must not be used!
  
  my $ReqHdDiff = $hash->{helper}{CANAktRequestHeaderID} ne $hash->{helper}{CANRequestHeaderID};
  my $ResHdDiff = $hash->{helper}{CANAktResponseHeaderID} ne $hash->{helper}{CANResponseHeaderID};
  
  if ($ReqHdDiff or $ResHdDiff)
  {
    @{$hash->{helper}{WriteQueue}} = ();
    
    $hash->{helper}{CANAktRequestHeaderID} = $hash->{helper}{CANRequestHeaderID};
    $hash->{helper}{CANAktResponseHeaderID} = $hash->{helper}{CANResponseHeaderID};
    
    push @{$hash->{helper}{WriteQueue}}, "AT SH $hash->{helper}{CANRequestHeaderID}"   if ($ReqHdDiff);
    push @{$hash->{helper}{WriteQueue}}, "AT CRA $hash->{helper}{CANResponseHeaderID}" if ($ResHdDiff);
    push @{$hash->{helper}{WriteQueue}}, $CANMsg;
    
    my $sque = shift @{$hash->{helper}{WriteQueue}};
    DevIo_SimpleWrite($hash, $sque."\r", 2);
  }
  else
  {
    DevIo_SimpleWrite($hash, $CANMsg."\r", 2);
  }
}

### HIFN ###
sub HPSU_Read_JSON_File($)
{
  my ($hash) = @_;
  my $cnt = 0;
  my $json = undef;
  my $data = undef;

  local $/; #Enable 'slurp' mode
  if (open(my $fh, "<:encoding(UTF-8)",  "$attr{global}{modpath}/FHEM/commands_hpsu.json"))
  {
    $json = <$fh>;
    close $fh;
  }
  else
  {
    return (-__LINE__, "Can't find/open commands_hpsu.json");
  }

  if (defined($json))
  {   
    $data = eval { decode_json($json) };
    if ($@)
    {
      return (-__LINE__, "Invalid json:\n$@");
    }

    if ($data->{commands})
    {
      while (my ($key, $value) = each %{ $data->{commands} } )
      {
        $data->{commands}{$key}{system} = $hash->{System} if (not $data->{commands}{$key}{system});
        
        if (not $hash->{helper}{MonitorMode})
        {
          if (index($data->{commands}{$key}{system}, $hash->{System}) < 0)
          {
            delete $data->{commands}{$key};
            next;
          }
        }
        return (-__LINE__, "Error $key") if (not $data->{commands}{$key}{name});
        return (-__LINE__, "Error $key") if (not $data->{commands}{$key}{command});
        #return -10 if (not $data->{commands}{$key}{id});  --->  no longer used since version 1.13
        return (-__LINE__, "Error $key") if (not $data->{commands}{$key}{divisor});
        return (-__LINE__, "Error $key") if (not $data->{commands}{$key}{type});

        $cnt += 1;
      }

      $hash->{jcmd} = $data->{commands};
    }
    else
    {
      return (-__LINE__, "Invalid json: no \"commands\"");
    }
  }
  else
  {
    return (-__LINE__, "Invalid json: unknown");
  }

  return ($cnt, $data->{version});
}

sub HPSU_CAN_ParamToFind($$)
{
  my ($hash, $CANMsg) = @_;
  my $jcmd = $hash->{jcmd};
  my $cstart = 6; #address
  my $canz = 8;   #address char length

  return undef if (!$CANMsg or length($CANMsg) < $canz);
  return undef if (not defined $jcmd);

  if (substr($CANMsg, $cstart, 2) eq "FA")
  {
    #Byte 3 == FA
    #31 00 FA 0B D1 00 00   <- $CANMsg
    #      |------| -> len: 8
    #      ^pos: 6
    $canz = 8;
  }
  else
  {
    #Byte 3 != FA
    #31 00 05 00 00 00 00   <- $CANMsg
    #      || -> len: 2
    #      ^pos: 6
    $canz = 2;
  }

  my @all_matches = grep ( substr($jcmd->{$_}{command}, $cstart, $canz)
                    eq     substr($CANMsg, $cstart, $canz) , keys %{$jcmd});

  return $all_matches[0], ($canz == 2)?0:1 if ((my $anz = @all_matches) == 1);

  return undef;
}

sub HPSU_toSigned($$)
{
  my ($val, $unit) = @_;

  if ($unit =~ "deg|value_code_signed")
  {
    $val = $val & 0xFFFF;
    return ($val ^ 0x8000) - 0x8000;
  }
  else
  {
    return $val;
  }
}

sub HPSU_CAN_ParseMsg($$)
{
  my ($hash, $CANMsg) = @_;
  my $jcmd = $hash->{jcmd};
  my ($name, $extended) = HPSU_CAN_ParamToFind($hash, $CANMsg);
  my $value = 0;
  my $ValByte1 = 0x00;
  my $ValByte2 = 0x00;
  my $cntSpaces = $CANMsg =~ tr/ //;               #how much spaces?
  my $strUnit = "";
  
  return undef if ($cntSpaces != 6);               #6 spaces necessary
  return undef if (substr($CANMsg, 1, 1) eq "1");  #no answer
  return undef if (not defined $name);             #unknown CANMsg


  if ($extended)  # -> Byte3 eq FA
  {
    #20 0A FA 01 D6 00 D9   <- $CANMsg
    #               |  ^pos: 18
    #               ^pos: 15
    #   t_hs - 21,7

    $ValByte1 = hex(substr($CANMsg, 15, 2));
    $ValByte2 = hex(substr($CANMsg, 18, 2));
  }
  else
  {
    #20 0A 0E 01 E8 00 00   <- $CANMsg
    #         |  ^pos: 12
    #         ^pos: 9
    #   t_dhw - 48,8Â°
    $ValByte1 = hex(substr($CANMsg,  9, 2));
    $ValByte2 = hex(substr($CANMsg, 12, 2));
  }

  my $type = $jcmd->{$name}{type};
  my $unit = $jcmd->{$name}{unit};

  if ($type eq "int")
  {
    $value = HPSU_toSigned($ValByte1, $unit);
  }
  elsif ($type eq "value")
  {
    $value = $ValByte1;
    #example: mode_01 val 4       -> 31 00 FA 01 12 04 00
    #                                                ^
  }
  elsif ($type eq "longint")
  {
    $value = HPSU_toSigned($ValByte2 + $ValByte1 * 0x0100, $unit);
    #example: one_hot_water val 1 -> 31 00 FA 01 44 00 01
    #                                                   ^
  }
  elsif ($type eq "float")
  {
    $value = HPSU_toSigned($ValByte2 + $ValByte1 * 0x0100, $unit);
  }
  else
  {
    return undef;
  }
  
  $value /= $jcmd->{$name}{divisor};

  if ($jcmd->{$name}{value_code})
  {
    my $newvalue = $jcmd->{$name}{value_code}{$value};

    if (length($newvalue))
    {
      $value = $newvalue;
    }
  }

  if ($unit and not $jcmd->{$name}{value_code})
  {
    $unit = lc($unit);
    if ($unit eq "deg")
    {
      $value .= " °C";
    }
    elsif ($unit eq "percent")
    {
      $value .= " %";
    }
    elsif ($unit eq "bar")
    {
      $value .= " bar";
    }
    elsif ($unit eq "kwh")
    {
      $value .= " kWh";
    }
    elsif ($unit eq "kw")
    {
      $value .= " kW";
    }
    elsif ($unit eq "w")
    {
      $value .= " W";
    }
    elsif ($unit eq "sec")
    {
      $value .= " sec";
    }
    elsif ($unit eq "min")
    {
      $value .= " min";
    }
    elsif ($unit eq "hour")
    {
      $value .= " h";
    }
    elsif ($unit eq "lh")
    {
      $value .= " lh";
    }
  }

  return $name, $jcmd->{$name}{name}, $value;
}

sub HPSU_CAN_RequestOrSetMsg($$$)
{
  my ($hash, $name, $value) = @_;
  my $jcmd = $hash->{jcmd};
  my $CANMsg = undef;
  my $CANPattern = "00 00 00 00 00 00 00";  #needed because of V0 (no padding)
  my @value_code = ();
  my $len = 0;

  $CANMsg = $jcmd->{$name}{command};
  return undef if (not defined $CANMsg);
  
  #nice to have --->
  #00 00 00 00 00 00 00 -> 20
  #31 00 FA C1 02       -> 14
  #             20 - 14  =  6
  $len = length($CANMsg);
  if ($len < length($CANPattern))
  {
    $CANMsg .= substr($CANPattern, $len, length($CANPattern)-$len);
  }
  # <---
  
  if (defined $value)
  {
    return undef if ($jcmd->{$name}{writable} ne "true");
  }
  
  if (defined $value and ($hash->{jcmd}{$name}{FHEMControl} eq "value_code"))
  {
    @value_code = grep ( $jcmd->{$name}{value_code}{$_} eq $value, sort keys %{$jcmd->{$name}{value_code}});

    $value = $value_code[0];
  }

  # TODO toSigned?
  # TODO type value .. immer nur 2. Byte setzen?
  # TODO type longint mit Parameter z.b. aux_time testen

  if (defined $value)
  {
    my $type = $jcmd->{$name}{type};
    my $unit = $jcmd->{$name}{unit};
    my $ValByte1 = "00";
    my $ValByte2 = "00";

    if (($value < 0) and ($type ne "float"))
    {
      print "set negative values if type not float not possible !!!";
    }
    
    $value *= $jcmd->{$name}{divisor};

    if ($type eq "int")
    {
      $ValByte1 = sprintf("%02X", $value);
    }
    elsif ($type eq "value")
    {
      $ValByte1 = sprintf("%02X", $value);
    }
    elsif ($type eq "longint")
    {
      my $hexval = sprintf("%04X", $value);
      $ValByte1 = substr($hexval, 0, 2);
      $ValByte2 = substr($hexval, 2, 2);
    }
    elsif ($type eq "float")
    {
      my $hexval = sprintf("%04X", $value & 0xFFFF);
      $ValByte1 = substr($hexval, 0, 2);
      $ValByte2 = substr($hexval, 2, 2);
    }
    else
    {
      return undef;
    }

    substr($CANMsg, 1, 1, "0"); #character No 2: 0=write 1=read 2=answer

    if (substr($CANMsg, 6, 2) eq "FA")  # 6=pos address
    {
      #Byte 3 == FA
      #30 0A FA 01 D6 00 D9   <- $CANMsg
      #               |  ^pos: 18
      #               ^pos: 15
      substr($CANMsg, 15, 2, $ValByte1);
      substr($CANMsg, 18, 2, $ValByte2);
    }
    else
    {
      #Byte 3 != FA
      #30 0A 0E 01 E8 00 00   <- $CANMsg
      #         |  ^pos: 12
      #         ^pos: 9
      #   t_dhw - 48,8Â°
      substr($CANMsg,  9, 2, $ValByte1);
      substr($CANMsg, 12, 2, $ValByte2);
    }
  }

  return $CANMsg;
}

sub HPSU_CAN_RAW_Message($$)
{
  my ($hash, $CANMsg) = @_;
  my $ValByte1 = 0x00;
  my $ValByte2 = 0x00;
  my $name = "";
  my $out = "";

  return undef if (!$CANMsg or length($CANMsg) < 8);
  my $cntSpaces = $CANMsg =~ tr/ //;                   #how much spaces?
  return undef if ($cntSpaces < 6 or $cntSpaces > 7);  #6 spaces necessary

  if (substr($CANMsg, 6, 2) eq "FA")  # -> Byte3 eq FA
  {
    #20 0A FA 01 D6 00 D9   <- $CANMsg
    #               |  ^pos: 18
    #               ^pos: 15
    #   t_hs - 21,7

    $ValByte1 = hex(substr($CANMsg, 15, 2));
    $ValByte2 = hex(substr($CANMsg, 18, 2));
    
    $name = substr($CANMsg, 9, 2)."_".substr($CANMsg, 12, 2)."__".substr($CANMsg, 1, 1);
  }
  else
  {
    #20 0A 0E 01 E8 00 00   <- $CANMsg
    #         |  ^pos: 12
    #         ^pos: 9
    #   t_dhw - 48,8Â°
    $ValByte1 = hex(substr($CANMsg,  9, 2));
    $ValByte2 = hex(substr($CANMsg, 12, 2));
    
    $name = substr($CANMsg, 6, 2)."__".substr($CANMsg, 1, 1);
  }
  
  my $out1 = HPSU_toSigned($ValByte2 + $ValByte1 * 0x0100, "deg");

  $out = "$ValByte1 - $ValByte2 - $out1 - RAW: $CANMsg";
  
  return $name, $out;
}

sub HPSU_Parse_SetGet_cmd($$)
{
  my ($hash, $in) = @_;
  my $jcmd = $hash->{jcmd};
  my @matches = ();
  
  #HPSUxxx.Betriebsart_[mode_01]
  my ($hpsuNameCmd) = $in =~ /\[(.*?)\]/; #just get name between []
  
  if (not $hpsuNameCmd)
  {
    #HPSUxxx.Betriebsart Heizen
    my $cntpt = $in =~ tr/.//;
    if ($cntpt == 1) #only one point allowed
    {
      $in = substr($in, index($in, ".")+1);
    }
    elsif ($cntpt > 1)
    {
      return undef;
    }
    
    #search mode_01
    @matches = grep($jcmd->{$_}{name} eq $in, keys %{$jcmd});
    return $matches[0] if (@matches == 1);
  }
  else
  {
    $in = $hpsuNameCmd;
  }
  
  #search Betriebsart and find mode_01
  @matches = grep($_ eq $in, keys %{$jcmd});
  return $matches[0] if (@matches == 1);
    
  return undef;
}

### HIFN for development ###
sub HPSU_getLoggingTime
{

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
  my $nice_timestamp = sprintf ( "%04d.%02d.%02d_%02d:%02d:%02d",
                                 $year+1900,$mon+1,$mday,$hour,$min,$sec);
  return $nice_timestamp;
}

sub HPSU_Log($)
{
  my ($str) = @_;
  my $strout = $str;
  my $fh = undef;

  open($fh, ">>:encoding(UTF-8)",  "$attr{global}{modpath}/FHEM/70_HPSU_Log.log") || return undef;
  $strout =~ s/\r/<\\r>/g;
  $strout =~ s/\n/<\\n>/g;
  print $fh HPSU_getLoggingTime().": ".$strout."\n";
  close($fh);

  return undef;
}

sub HPSU_RAW_Log($)
{
  my ($str) = @_;
  my $strout = $str;
  my $fh = undef;

  open($fh, ">>:encoding(UTF-8)",  "$attr{global}{modpath}/FHEM/70_HPSU_Raw.log") || return undef;
  $strout =~ s/\r/<\\r>/g;
  $strout =~ s/\n/<\\n>/g;
  print $fh HPSU_getLoggingTime().": ".$strout."\n";
  close($fh);

  return undef;
}

1;
