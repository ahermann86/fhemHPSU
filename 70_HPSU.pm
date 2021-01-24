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
# ah 1.11 - 11.01.21 - Parse_SetGet_cmd() to find out cmd send via Set or Get argument
#                    -         |-> https://forum.fhem.de/index.php/topic,106503.msg1119787.html#msg1119787
#                    - Sort set an get dropdowns
#                    - When init then cancel DHWForce (with -1)
#                    - New reading: Info.LastDefrostDHWShrink (if mode heating)
#                    - New attribute: SuppressRetryWarnings - to relieve logging
#                    - New attribute: (experimental state !!) - RememberSetValues - save mode_01 val and set after module init
# ah 1.12 - 25.01.21 - Monitor Mode: extend output with header info and signed float


#ToDo:
# - suppress retry

package main;

use strict;
use warnings;
use DevIo; # load DevIo.pm if not already loaded
use JSON;
use SetExtensions;

use constant HPSU_MODULEVERSION => '1.12';

#Prototypes
sub HPSU_Disconnect($);
sub HPSU_Read_JSON_updreadings($);
sub HPSU_CAN_RequestReadings($$$);
sub HPSU_Read_JSON_File($);
sub HPSU_CAN_ParseMsg($$);
sub HPSU_CAN_RequestOrSetMsg($$$);
sub HPSU_CAN_RAW_Message($$);
sub Parse_SetGet_cmd($$);
sub HPSU_Log($); #for development
sub HPSU_Log2($); #for development

my %HPSU_sets =
(
  "Connect"             =>  "noArg",
  "Connect_MonitorMode" =>  "noArg",
  "Disconnect"          =>  "noArg",
  "ForceDHW"            =>  "noArg"
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
  $hash->{AttrList}  = "AutoPoll:on,off AntiMixerSwing:on,off CheckDHWInterrupted:on,off ".
                       "DebugLog:on,onWithMsg,onDHW,off ".
                       "AntiContinousHeating:on,off ".
                       "RememberSetValues:on,off ".
                       "SuppressRetryWarnings:on,off ". #"Comm.(Set|Get)Status", "Error: retry ...
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

  return "no device given" unless($dev);

  # close connection if maybe open (on definition modify)
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));

  # add a default baud rate (38400), if not given by user
  $dev .= '@38400' if(not $dev =~ m/\@\d+$/);

  # set the device to open
  $hash->{DeviceName} = $dev;

  # listen Mode
  $hash->{ELMState} = "defined";
  $hash->{helper}{initstate} = 0;
  $hash->{helper}{CANHeaderID} = "";
  $hash->{helper}{CANAktHeaderID} = "";

  $hash->{helper}{PARTIAL} = "";

  HPSU_Read_JSON_updreadings($hash);
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

    if ($hash->{ELMState} eq "init")
    {
      my $strInit = "ELM327 v";
      my $idxInit = index($msg, $strInit);
      my $idx = -1;
      my $istate = $hash->{helper}{initstate};
      my @init = ("AT Z",             #just reset
                  "AT E1",            #echo on
                  "AT PP 2F SV 19",   #set baud to 20k
                  "AT PP 2F ON",      #activate/save baud parameter
                  "AT SP C",          #activate protocol "C"
                  #"AT ST FF",          #set timeout to max (default is 32 -> 128ms) long enough!
                  "AT Z",             #reset and takeover settings
                  "AT H0",            #Header off
                  "");                #end
                  
      if ($hash->{helper}{MonitorMode})
      {
        $init[6] = "AT H1"; #Header on
      }

      $idx = index($msg, $init[$istate]) if $istate > 0;
      $hash->{ELM327_Version} = substr($msg, $idxInit + length($strInit), 3) if ($idxInit > 0);

      if ($idx >= 0 or $idxInit > 0)
      {
        $istate += 1;
        if ( length($init[$istate]) > 0)
        {
          DevIo_SimpleWrite($hash, $init[$istate]."\r", 2);
          $hash->{STATE} = "Init_step_" . $istate;
        }
        else
        {
          DevIo_SimpleWrite($hash, "AT MA\r", 2) if ($hash->{helper}{MonitorMode});
          
          $hash->{ELMState} = "Initialized";
          $hash->{STATE} = "opened";  # not so nice hack, but works

          $hash->{helper}{CANRequestPending} = -1;
          $hash->{helper}{CANAktHeaderID} = "";
          if (not $hash->{helper}{MonitorMode})
          {
            HPSU_Task($hash);
            
            #Todo: experimental state
            if (AttrVal($name, "RememberSetValues", "off") eq "on")
            {
              my $val = ReadingsVal("$name","FHEMSET.$hash->{jcmd}->{mode_01}->{name}","NotRead");
              
              push @{$hash->{helper}->{queue}}, "mode_01;$val" if ($val ne "NotRead");
            }
          }
        }
        $hash->{helper}{initstate} = $istate;
      }
    }
    elsif ($hash->{ELMState} eq "Initialized")
    {
      if ($hash->{helper}{CANAktHeaderID} ne $hash->{helper}{CANHeaderID})
      {
        my $idx = index($msg, "OK\r");
        if ($idx)
        {
          $hash->{helper}{CANAktHeaderID} = $hash->{helper}{CANHeaderID};
          DevIo_SimpleWrite($hash, $hash->{helper}{firstCommand}."\r", 2);
        }
        $hash->{helper}{firstCommand} = undef;        
      }
      else
      {
        while($msg =~ m/\r/)
        {
          my $msgSplit = "";

          ($msgSplit, $msg) = split("\r", $msg, 2);
          $msgSplit =~ s/ +$//; #delete whitespace

          my ($name, $nicename, $out) = HPSU_CAN_ParseMsg($hash, $msgSplit);
          
          if ($name)
          {              
            $hash->{jcmd}->{$name}->{FHEMLastResponse} = gettimeofday();
            $hash->{jcmd}->{$name}->{AktVal} = $out; #for "verify"...
            
            if (defined $name
                and defined $hash->{helper}{CANRequestName} 
                and $hash->{helper}{CANRequestName} eq $name)
            {
              $hash->{helper}{CANRequestPending} = 0;
              readingsSingleUpdate($hash, "HPSU.$nicename", $out, 1);
            }
          }
          if (defined $hash->{helper}{CANRequestName} 
              and $hash->{helper}{CANRequestName} eq "NO DATA"
              and $hash->{helper}{CANHeaderID} eq "680")
          {
            $hash->{helper}{CANRequestPending} = 0;
          }
        }
      }
    }
  }
  
  if ($hash->{helper}{MonitorMode} and $hash->{ELMState} eq "Initialized")
  {
    while($buffer =~ m/\r/)
    {
      my $msgSplit = "";

      ($msgSplit, $buffer) = split("\r", $buffer, 2);
      $msgSplit =~ s/ +$//; #delete whitespace
      
      HPSU_Log("HPSU ".__LINE__.": MM RAW: $msgSplit" ) if (AttrVal($name, "DebugLog", "off") eq "onWithMsg");
      
      #AT H1
      my $Header = "";
      ($Header, $msgSplit) = split(" ", $msgSplit, 2);      

      my ($name, $nicename, $out) = HPSU_CAN_ParseMsg($hash, $msgSplit);
      
      if ($name)
      {
        readingsSingleUpdate($hash, "HPSU.$nicename"."_MsgHeader.$Header", $out, 1);
      }
      else
      {
        #my ($name1, $extended1) = HPSU_CAN_ParamToFind($hash, $msgSplit);
        my $name1 = 0;

        if (length($name1) < 2)
        {
          my ($rawname, $out) = HPSU_CAN_RAW_Message($hash, $msgSplit);

          readingsSingleUpdate($hash, "$rawname"."_MsgHeader.$Header", $out, 1) if ($rawname);
        }
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

  return "\"set $name\" needs at least one argument" unless(defined($cmd));

  my $hpsuNameCmd = Parse_SetGet_cmd($hash, $cmd);

  return "\"set $name\" needs a setable value" if ($jcmd->{$hpsuNameCmd} and not exists $args[0]);

  if ($hash->{helper}{MonitorMode})
  {
    if($cmd eq "Connect" or $cmd eq "Disconnect")
    {
      DevIo_SimpleWrite($hash, "AA\r", 2); #one char occur error..
      $hash->{helper}{MonitorMode} = undef;      
    }
  }
  
  if($cmd eq "Connect")
  {
    DevIo_OpenDev($hash, 0, "HPSU_Init");
  }
  elsif($cmd eq "Connect_MonitorMode")
  {
    $hash->{helper}{CANHeaderID} = "";
    $hash->{helper}{CANAktHeaderID} = "";

    $hash->{helper}{MonitorMode} = 1;
    DevIo_OpenDev($hash, 0, "HPSU_Init");
    HPSU_Log2("HPSU ".__LINE__.": Monitor Init" );
  }
  elsif($cmd eq "Disconnect")
  {
    HPSU_Disconnect($hash);
  }
  elsif($cmd eq "ForceDHW")
  {
    $hash->{helper}->{DHWForce} = gettimeofday();
  }
  elsif($hpsuNameCmd)
  {
    my $val = $args[0];

    return "Monitor mode active.. set values disabled!" if ($hash->{helper}{MonitorMode});
    return "$hpsuNameCmd not writable" if ($jcmd->{$hpsuNameCmd}->{writable} ne "true");

    #Todo: experimental state
    if (AttrVal($name, "RememberSetValues", "off") eq "on")
    {
      if ($hpsuNameCmd eq "mode_01")
      {
        readingsSingleUpdate($hash, "FHEMSET.$hash->{jcmd}->{$hpsuNameCmd}->{name}", $val, 1);
      }
    }
    
    #min/max check
    if ($jcmd->{$hpsuNameCmd}->{FHEMControl} and (index($jcmd->{$hpsuNameCmd}->{FHEMControl}, "slider,") == 0) )
    {
      my $dmy = "";
      my $que = "";
      my $min = 0;
      my $max = 0;
      
      my $dbgString = "FHEMControl: $jcmd->{$hpsuNameCmd}->{FHEMControl} cmd: $hpsuNameCmd val: $val";

      ($dmy, $que) = split(",", $jcmd->{$hpsuNameCmd}->{FHEMControl}, 2); #i.e. slider,5,0.5,40
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
    
    push @{$hash->{helper}->{queue}}, $qstr;
  }
  else
  {
    my $jcmd = $hash->{jcmd};

    foreach my $key (@{$hash->{helper}{Writablekeys}})
    {
      if ($jcmd->{$key}->{FHEMControl} and $jcmd->{$key}->{FHEMControl} ne "disabled")
      {
        $cmdList .= " HPSU.$jcmd->{$key}->{name}:";
        if ($jcmd->{$key}->{FHEMControl} eq "value_code")
        {
          $cmdList .= join(",", map {"$jcmd->{$key}->{value_code}{$_}"} sort keys %{$jcmd->{$key}->{value_code}});
        }
        else
        {
          $cmdList .= "$jcmd->{$key}->{FHEMControl}";
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
    my $hpsuNameCmd = Parse_SetGet_cmd($hash, $args[0]);

    if ($hpsuNameCmd)
    {
      push @{$hash->{helper}->{queue}}, $hpsuNameCmd;
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
      push @names, $jcmd->{$key0}->{name};
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
  my $buf;
  my $name = $hash->{NAME};
  my $char = undef;
  my $ret = undef;

  HPSU_Read_JSON_updreadings($hash);
  # Reset
  $hash->{helper}{PARTIAL} = "";
  $hash->{helper}{initstate} = 0;
  undef $hash->{helper}->{queue} if ($hash->{helper}->{queue});
  $hash->{helper}{DefrostState} = 0;
  $hash->{helper}->{DHWForce} = -1; #cancel if active...

  $ret = DevIo_SimpleWrite($hash, "AT Z\r", 2);  #reset
  $hash->{STATE} = "Init_step_" . $hash->{helper}{initstate};
  $hash->{ELMState} = "init";
  $hash->{Module_Version} = HPSU_MODULEVERSION;

  HPSU_Log("HPSU ".__LINE__.": Init" ) if (AttrVal($name, "DebugLog", "off") eq "on");

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
        $hash->{jcmd}->{status_pump}->{FHEMPollTime} = 300 if ($hash->{jcmd}->{status_pump}->{FHEMPollTime} < 1);
      }
    }
    
    if ($attrName eq "AntiContinousHeating" and $attrValue eq "on")
    {
      HPSU_Read_JSON_updreadings($hash);
      if ($hash->{JSON_version} < 3.6)
      {
        $attr{$name}{"AntiContinousHeating"} = "off";
        push @{$hash->{helper}->{queue}}, "t_frost_protect";
        return "At least JSON version 3.6 is required for $attrName attribute!";
      }
    }
    
    #Todo: experimental state
    if ($attrName eq "RememberSetValues" and $attrValue eq "on")
    {
      $attr{$name}{"RememberSetValues"} = "on";
      return "This attribute has experimental status!";
    }
  }

  return undef;
}

### FHEM HIFN ###
sub HPSU_Disconnect($)
{
  my ($hash) = @_;

  undef $hash->{helper}->{queue} if ($hash->{helper}->{queue});
  $hash->{ELMState} = "disconnected";
  $hash->{helper}{MonitorMode} = undef;
  RemoveInternalTimer($hash);
  sleep(0.3);  ##wait if pending commands...

  # close the connection
  DevIo_CloseDev($hash);

  return undef;
}

sub HPSU_Task($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $jcmd = $hash->{jcmd};

  $hash->{helper}{autopollState} = 0 if (!exists($hash->{helper}{autopollState}));
  $hash->{helper}{CANRequestPending} = 0 if (!exists($hash->{helper}{CANRequestPending}));
  $hash->{helper}{CANSetTries} = 0 if (!exists($hash->{helper}{CANSetTries}));

  return undef if ($hash->{ELMState} ne "Initialized");
  return undef if ($hash->{helper}{MonitorMode});

  my $AktMode = ReadingsVal("$name","HPSU.$hash->{jcmd}->{mode}->{name}","Standby");
  my $AktMode_01 = ReadingsVal("$name","HPSU.$hash->{jcmd}->{mode_01}->{name}","Bereitschaft");
  $hash->{helper}{HPSULstMode} = $AktMode if (!exists($hash->{helper}{HPSULstMode}));
  $hash->{helper}{HPSULstMode_01} = $AktMode_01 if (!exists($hash->{helper}{HPSULstMode_01}));

  if ($hash->{helper}{CANRequestPending} > 0)
  {
    $hash->{helper}->{GetStatusError} = 0 if (not exists $hash->{helper}->{GetStatusError});
    
    if ($hash->{helper}{CANRequestPending} + 4.0 < gettimeofday() ) #3,5 sometimes needed ! 
    {
      if ($hash->{helper}->{queue}[0]) #set pending ?
      {
        $hash->{helper}{CANSetTries}++;
        if ($hash->{helper}{CANSetTries} >= 2)
        {
          my $sque = shift @{$hash->{helper}->{queue}};
          undef $hash->{helper}->{queue};
          readingsSingleUpdate($hash, "Comm.SetStatus", "Error: timeout [$sque] (".__LINE__.")", 1);

          HPSU_Log("HPSU ".__LINE__.": Comm.SetStatus Error: timeout [$sque]" ) if (AttrVal($name, "DebugLog", "off") eq "on");
          $hash->{helper}{CANSetTries} = 0;
        }
        else
        {
          if (AttrVal($name, "SuppressRetryWarnings", "on") eq "off")
          {
            readingsSingleUpdate($hash, "Comm.SetStatus", "Error: retry [$hash->{helper}->{queue}[0]] (".__LINE__.")", 1);
            HPSU_Log("HPSU ".__LINE__.": Comm.SetStatus Error: retry [$hash->{helper}->{queue}[0]]" ) if (AttrVal($name, "DebugLog", "off") eq "on");          
          }
        }
        $hash->{helper}{CANRequestPending} = -1;
      }
      else
      {
        if ($hash->{helper}->{GetStatusError} == 0)
        {
          HPSU_CAN_RequestReadings($hash, $hash->{helper}{CANRequestName}, undef);  #send lst request again
          if (AttrVal($name, "SuppressRetryWarnings", "on") eq "off" and 
              AttrVal($name, "DebugLog", "off") eq "on")
          {
            HPSU_Log("HPSU ".__LINE__.": Comm.GetStatus Error: retry name: $hash->{helper}{CANRequestName}" );
          }
        }
        $hash->{helper}->{GetStatusError}++;
        if ($hash->{helper}->{GetStatusError} > 1)
        {
          readingsSingleUpdate($hash, "Comm.GetStatus", "Error: timeout name: $hash->{helper}{CANRequestName} (".__LINE__.")", 1);
          HPSU_Log("HPSU ".__LINE__.": Comm.GetStatus Error: timeout name: $hash->{helper}{CANRequestName}" ) if (AttrVal($name, "DebugLog", "off") eq "on");
          $hash->{helper}{CANRequestPending} = -1;
          $hash->{helper}->{GetStatusError} = 0;
        }
      }
    }
  }
  if ($hash->{helper}{CANRequestPending} == 0 and $hash->{helper}->{GetStatusError} > 0)
  {
    $hash->{helper}->{GetStatusError} = 0;
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
    my $status_pump_WasActive = ReadingsVal("$name","HPSU.$hash->{jcmd}->{status_pump}->{name}","active") eq
                      $hash->{jcmd}->{status_pump}->{value_code}->{"1"};
    my $Mod_Cool   = ReadingsVal("$name","HPSU.$hash->{jcmd}->{mode_01}->{name}","Kuehlen") eq
                      $hash->{jcmd}->{mode_01}->{value_code}->{"17"};
    #Nachfolgende T_ Variablen werden zum check verwendet, ob WP tatsaechlich im ES ist - auf $status_pump_WasActive allein kann man sich nicht verlassen!!
    #Es scheint, als waeren die Temperaturen sehr klein, wenn das wirklich der Fall ist
    my $T_VlWez = ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_hs_set}->{name}", 10);  #Soll_Vorlauftemperatur_Waermeerzeuger 0
    #my $T_KmWez = ReadingsNum("$name","HPSU.$hash->{jcmd}->{tliq2}->{name}", 10);     #Kaeltemitteltemperatur -40
    #my $T_Wez   = ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_hs}->{name}", 10);      #Vorlauftemperatur_Waermeerzeuger -50

    $hash->{helper}->{status_pump_WasActive} = 0 if (not exists ($hash->{helper}->{status_pump_WasActive}));
    $hash->{helper}->{status_pump_LstTimeActive} = 0 if (not exists ($hash->{helper}->{status_pump_LstTimeActive}));
    $hash->{helper}->{HPSULstModeTime} = 0 if (not exists ($hash->{helper}->{HPSULstModeTime}));

    my $AktMode_01 = ReadingsVal("$name","HPSU.$hash->{jcmd}->{mode_01}->{name}","Standby");
    if ($hash->{helper}->{HPSULstMode_01} ne $AktMode_01)
    {
      $hash->{helper}->{HPSULstModeTime} = gettimeofday();
    }

    if ($status_pump_WasActive)
    {
      $hash->{helper}->{status_pump_WasActive} = 1;
      $hash->{helper}->{status_pump_LstTimeActive} = gettimeofday();
    }
    if (!$status_pump_WasActive and $T_VlWez <= 0) #Wenn WP im ES war und z.B. WW bereitet
    {
      $hash->{helper}->{status_pump_WasActive} = 0;
    }

    if (!$status_pump_WasActive and
        $hash->{helper}->{status_pump_WasActive} == 1 and
        $hash->{helper}->{status_pump_LstTimeActive}+2.5*60 < gettimeofday() and
        $T_VlWez > 0 and
        $hash->{helper}->{HPSULstModeTime}+5*60 < gettimeofday() and
        !$Mod_Cool )
    {
      push @{$hash->{helper}->{queue}}, "mode_01;$hash->{jcmd}->{mode_01}->{value_code}->{'1'}";
      push @{$hash->{helper}->{queue}}, "mode_01;$AktMode_01";
      push @{$hash->{helper}->{queue}}, "status_pump";
      
      $hash->{helper}->{status_pump_WasActive} = 0;
      
      HPSU_Log("HPSU ".__LINE__.": AntiMixerSwing occurred" ) if (AttrVal($name, "DebugLog", "off") eq "on");
    }
  }

  ### Check if DHW is interrupted
  #$hash->{helper}->{DHWChkStatus} => 0: off, 1: active, 1>: restart

  #helper variables DHW "is interrupted" and "Force"
  my $DHWDiffBig = (ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_dhw_setpoint1}->{name}",48) >  #t_dhw_set
                       ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_dhw}->{name}",48)+0.5);
  my $DHWactive = ReadingsVal("$name","HPSU.$hash->{jcmd}->{mode}->{name}","Standby") eq
                  $hash->{jcmd}->{mode}->{value_code}->{"4"};
  my $DHWdefrost = ReadingsVal("$name","HPSU.$hash->{jcmd}->{mode}->{name}","Standby") eq
                   $hash->{jcmd}->{mode}->{value_code}->{"3"};

  if (AttrVal($name, "CheckDHWInterrupted", "off") eq "on")
  {
    $hash->{helper}->{DHWChkStatus} = 0 if (not exists ($hash->{helper}->{DHWChkStatus}));

    if (not $DHWDiffBig)
    {
      $hash->{helper}->{DHWChkStatus} = 0;
    }
    else
    {
      if ($DHWactive)
      {
        $hash->{helper}->{DHWChkStatus} = 1;
      }
    }

    if ($hash->{helper}->{DHWChkStatus} and $hash->{helper}->{DHWChkStatus} == 1)
    {
      if (not $DHWactive and not $DHWdefrost)
      {
        $hash->{helper}->{DHWChkStatus} += 1;
        $hash->{helper}->{DHWForce} = gettimeofday()+4*60;
        
        HPSU_Log("HPSU ".__LINE__.": DHW was interrupted" ) if (AttrVal($name, "DebugLog", "off") eq "on");
      }
    }
  }

  ### Force DHW
  $hash->{helper}->{DHWForce} = -1 if (not exists ($hash->{helper}->{DHWForce}));
  
  if ($hash->{helper}->{DHWForce} > 0 and $hash->{helper}->{DHWForce} <= gettimeofday()
      and (not $hash->{helper}->{queue} or not $hash->{helper}->{queue}[0]) )
  {
    my $timeout = 0;

    if ($hash->{helper}->{DHWForceState} and $hash->{helper}->{DHWForceState} > 0)
    {
      if (not exists $hash->{helper}->{DHWForceLstTime} or $hash->{helper}->{DHWForceLstTime} <= 0)
      {
        $hash->{helper}->{DHWForceLstTime} = gettimeofday();
      }
      else
      {
        $timeout = 1 if ($hash->{helper}->{DHWForceLstTime}+60 < gettimeofday());
      }
    }

    if ($timeout)
    {
      $hash->{helper}->{DHWForceState} = 2; #set to last step
      HPSU_Log("HPSU ".__LINE__.": DHW set timeout" ) if (AttrVal($name, "DebugLog", "off") eq "onDHW");
    }
    elsif (not $DHWDiffBig)
    {
      readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: force DHW diff to small (".__LINE__.")", 1);
      HPSU_Log("HPSU ".__LINE__.": DHW force DHW diff to small" ) if (AttrVal($name, "DebugLog", "off") eq "onDHW");
      $hash->{helper}->{DHWForce} = -1;
    }

    if ( $hash->{helper}->{DHWForce} >= 0 and
        (not $hash->{helper}->{DHWForceState} or $hash->{helper}->{DHWForceState} == 0) )
    {
      if ($DHWactive)
      {
        readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: (force) DHW still active (".__LINE__.")", 1);
        HPSU_Log("HPSU ".__LINE__.": DHW force DHW still active" ) if (AttrVal($name, "DebugLog", "off") eq "onDHW");
        $hash->{helper}->{DHWForce} = -1;
      }
      else
      {
        $hash->{helper}->{DHWForceState} = 1;
        $hash->{helper}->{DHWForceDesTemp} = ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_dhw_setpoint1}->{name}",48);  #t_dhw_set
        push @{$hash->{helper}->{queue}}, "t_dhw_setpoint1;60";
        HPSU_Log("HPSU ".__LINE__.": DHW push 60deg -> Dest Temp: $hash->{helper}->{DHWForceDesTemp}" ) if (AttrVal($name, "DebugLog", "off") eq "onDHW");
      }
    }
    if ($hash->{helper}->{DHWForceState} == 1)
    {
      if ($DHWactive)
      {
        $hash->{helper}->{DHWForceState} = 2;
        HPSU_Log("HPSU ".__LINE__.": DHW push 60deg -> active" ) if (AttrVal($name, "DebugLog", "off") eq "onDHW");
      }
    }
    if ($hash->{helper}->{DHWForceState} == 2)
    {
      $hash->{helper}->{DHWForceState} = 0;
      $hash->{helper}->{DHWForce} = -1;  #finished

      push @{$hash->{helper}->{queue}}, "t_dhw_setpoint1;$hash->{helper}->{DHWForceDesTemp}";
      $hash->{helper}->{DHWForceLstTime} = -1;
      if ($timeout)
      {
        readingsSingleUpdate($hash, "Comm.ManStatus", "Error: Force DHW timeout (".__LINE__.")", 1);
        HPSU_Log("HPSU ".__LINE__.": DHW force timeout -> Dest Temp: $hash->{helper}->{DHWForceDesTemp}" ) if (AttrVal($name, "DebugLog", "off") eq "onDHW");
      }
      else
      {
        readingsSingleUpdate($hash, "Comm.ManStatus", "Ok: Force DHW (".__LINE__.")", 1);
        HPSU_Log("HPSU ".__LINE__.": DHW force ok -> Dest Temp: $hash->{helper}->{DHWForceDesTemp}" ) if (AttrVal($name, "DebugLog", "off") eq "onDHW");
      }
    }
  }

  #Reading Status "Info.LastDefrostDHWShrink" defrost
  #AntiContinousHeating while heating
  {
    $hash->{helper}{DefrostState} = 0 if (not exists ($hash->{helper}{DefrostState}));
    $hash->{helper}{DefrostStateTime} = gettimeofday() if (not exists ($hash->{helper}{DefrostStateTime}));
    
    if ($hash->{helper}{DefrostState} == 0)
    {
      if ($AktMode                     eq $hash->{jcmd}->{mode}->{value_code}->{"3"} and   #"Abtauen"
          $hash->{helper}{HPSULstMode} eq $hash->{jcmd}->{mode}->{value_code}->{"1"})      #"Heizen"
      {
        $hash->{helper}{DefrostStateTime} = gettimeofday();
        $hash->{helper}{DefrostState} = 1;
        $hash->{helper}->{DefrostDHWStart} = ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_dhw}->{name}",48);
        
        if (AttrVal($name, "AntiContinousHeating", "off") eq "on")
        {
          my $t_frost_protect = ReadingsVal("$name","HPSU.$hash->{jcmd}->{t_frost_protect}->{name}","NotRead");
          if ($t_frost_protect ne $hash->{jcmd}->{t_frost_protect}->{value_code}->{'-160'})  #-160 -> "Aus"
          {
            $hash->{helper}->{t_frost_protect_lst} = $t_frost_protect;
            if ($hash->{helper}->{t_frost_protect_lst} ne "NotRead")
            {
              push @{$hash->{helper}->{queue}}, "t_frost_protect;$hash->{jcmd}->{t_frost_protect}->{value_code}->{'-160'}"; 
              HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set Frost from $t_frost_protect to Off" ) if (AttrVal($name, "DebugLog", "off") eq "on");
            }
          }
          push @{$hash->{helper}->{queue}}, "mode_01;$hash->{jcmd}->{mode_01}->{value_code}->{'5'}"; #"Sommer"
          
          HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set to summer" ) if (AttrVal($name, "DebugLog", "off") eq "on");
        }
      }
    }
    elsif ($hash->{helper}{DefrostState} == 1)
    {
      if ($AktMode ne $hash->{jcmd}->{mode}->{value_code}->{"3"} or   #"Abtauen"
          $hash->{helper}->{DefrostStateTime}+15*60 < gettimeofday()) #emergency exit after 15min
      {
        $hash->{helper}{DefrostStateTime} = gettimeofday();
        $hash->{helper}{DefrostState}++;
        
        if (AttrVal($name, "AntiContinousHeating", "off") eq "on")
        {
          push @{$hash->{helper}->{queue}}, "mode_01;$hash->{jcmd}->{mode_01}->{value_code}->{'3'}"; #"Heizen"
          if(exists $hash->{helper}->{t_frost_protect_lst})
          {
            if ($hash->{helper}->{t_frost_protect_lst} ne "NotRead")
            {
              push @{$hash->{helper}->{queue}}, "t_frost_protect;$hash->{helper}->{t_frost_protect_lst}";
              HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set Frost to $hash->{helper}->{t_frost_protect_lst}" ) if (AttrVal($name, "DebugLog", "off") eq "on");
            }
            delete $hash->{helper}->{t_frost_protect_lst};
          }
          
          HPSU_Log("HPSU ".__LINE__.": AntiContinousHeating set to heat" ) if (AttrVal($name, "DebugLog", "off") eq "on");
        }
      }
    }
    elsif ($hash->{helper}{DefrostState} == 2)
    {
      my $time = $hash->{helper}->{DefrostStateTime}+4*60 < gettimeofday(); #settling time 4min, then dhw is definitely stable
      
      if ($time)
      {
        push @{$hash->{helper}->{queue}}, "t_dhw";   
        $hash->{helper}{DefrostStateTime} = gettimeofday();
        $hash->{helper}{DefrostState}++;
      }
    }
    elsif ($hash->{helper}{DefrostState} == 3)
    {
      my $timeout = $hash->{helper}->{DefrostStateTime}+30 < gettimeofday(); #emergency exit after 30sec
      
      if ($hash->{jcmd}->{t_dhw}->{FHEMLastResponse}+1 < gettimeofday() or   #new DHW value
          $timeout)
      {
        if (not $timeout)
        {
          my $val = $hash->{helper}->{DefrostDHWStart} - ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_dhw}->{name}",48);
          readingsSingleUpdate($hash, "Info.LastDefrostDHWShrink", "$val °C", 1);
        }      
        $hash->{helper}{DefrostStateTime} = 0;
        $hash->{helper}{DefrostState} = 0;
      }
    }
  }

  if (exists($hash->{JSON_parameters}) and $hash->{JSON_parameters} > 0)
  {
    ### Read or set parameter
    # Queue -> manual request or set value
    if ($hash->{helper}{CANRequestPending} <= 0)
    {
      if ($hash->{helper}->{queue}[0])
      {
        my $cntdp = $hash->{helper}->{queue}[0] =~ tr/;//;

        if ($cntdp == 0) #request
        {
          my $name = shift @{$hash->{helper}->{queue}};
          
          HPSU_CAN_RequestReadings($hash, $name, undef);
        }
        elsif ($cntdp == 1) #value change requested?
        {
          $hash->{helper}->{queue}[0] .= ";check;3"; # -> retry 3 times
        }
      }
      
      if ($hash->{helper}->{queue}[0])
      {
        #set value if necessary and verify
        my $cntdp = $hash->{helper}->{queue}[0] =~ tr/;//;
        
        if ($cntdp == 3) #Str format: name;val;state;rep
        {
          my $que = "";
          my $name = "";
          my $val = "";
          my $state = "";
          my $rep = 0;

          ($name,  $que) = split(";", $hash->{helper}->{queue}[0], 2);
          ($val,   $que) = split(";", $que, 2);
          ($state, $que) = split(";", $que, 2);
          $rep           = $que;
          
          if ($state eq "check")
          {
            if ($rep-- > 0)
            {
              $hash->{helper}->{queue}[0] =~ s/;[0-9]$/;$rep/;

              if ( not defined $hash->{jcmd}->{$name}->{AktVal} or
                   $hash->{jcmd}->{$name}->{FHEMLastResponse} + 0.5 < gettimeofday() )
              {
                HPSU_CAN_RequestReadings($hash, $name, undef);
              }
              $hash->{helper}->{queue}[0] =~ s/;$state/;checkAktVal/;
            }
            else
            {
              my $sque = shift @{$hash->{helper}->{queue}};
              readingsSingleUpdate($hash, "Comm.SetStatus", "Error: [$name] too many reading attempts (".__LINE__.")", 1);
              $state = "error";
            }
          }

          if ( $state eq "checkAktVal" or
               $state eq "verify" )
          {
            if (defined $hash->{jcmd}->{$name}->{AktVal})
            {
              my $isSame = 0;

              if ( $hash->{jcmd}->{$name}->{FHEMControl} and
                  ($hash->{jcmd}->{$name}->{FHEMControl} eq "value_code") )
              {
                $isSame = $hash->{jcmd}->{$name}->{AktVal} eq $val;
              }
              else
              {
                my $aktval = ($hash->{jcmd}->{$name}->{AktVal} =~ /(-?\d+(\.\d+)?)/ ? $1 : ""); #to num: 19.5 °C -> 19.5
                $isSame = ($aktval == $val);
              }

              if ($state eq "checkAktVal")
              {
                if ($isSame)
                {
                  my $sque = shift @{$hash->{helper}->{queue}};
                  readingsSingleUpdate($hash, "Comm.SetStatus", "Ok: [$name] already set to $val (".__LINE__.")", 1);
                  $hash->{helper}{CANSetTries} = 0;
                }
                else
                {
                  $hash->{helper}->{queue}[0] =~ s/;$state/;write/;
                }
              }
              else
              {
                if ($isSame)
                {
                  my $sque = shift @{$hash->{helper}->{queue}};
                  readingsSingleUpdate($hash, "Comm.SetStatus", "Ok: [$name] successfully set to $val (".__LINE__.")", 1);
                  $hash->{helper}{CANSetTries} = 0;
                }
                else
                {
                  if ($rep <= 0)
                  {
                    my $sque = shift @{$hash->{helper}->{queue}};
                    readingsSingleUpdate($hash, "Comm.SetStatus", "Error: [$name] verify failed (".__LINE__.")", 1);
                    $hash->{helper}{CANSetTries} = 0;
                  }
                  else
                  {
                    $hash->{helper}->{queue}[0] =~ s/;$state/;check/;
                  }
                }
              }
            }
          }

          if ($state eq "write")
          {
            HPSU_CAN_RequestReadings($hash, $name, $val);
            $hash->{helper}->{queue}[0] =~ s/;$state/;read/;
          }

          if ($state eq "read")
          {
            HPSU_CAN_RequestReadings($hash, $name, undef);
            $hash->{helper}->{queue}[0] =~ s/;$state/;verify/;
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
            if (  $jcmd->{$key}->{FHEMLastResponse} < 0 or           #never requested since yet
                (($jcmd->{$key}->{FHEMLastResponse}+$jcmd->{$key}->{FHEMPollTime}) < gettimeofday())) #poll time
            {
              HPSU_CAN_RequestReadings($hash, $key, undef);
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

  ### Calculate Akt Q
  my $AktQ = 0;
  my $OldQ = ReadingsNum("$name","Info.Q",-100);
  my $t_hs = ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_hs}->{name}",-100);
  my $t_r1 = ReadingsNum("$name","HPSU.$hash->{jcmd}->{t_r1}->{name}",-100);
  my $flow_rate = ReadingsNum("$name","HPSU.$hash->{jcmd}->{flow_rate}->{name}",-100);

  if ( ($AktMode eq $hash->{jcmd}->{mode}->{value_code}->{"1"} or   #"Heizen"
        $AktMode eq $hash->{jcmd}->{mode}->{value_code}->{"2"} or   #"Kuehlen"
        $AktMode eq $hash->{jcmd}->{mode}->{value_code}->{"4"}) and #"Warmwasserbereitung"
        $t_hs > -100 and
        $t_r1 > -100 and
        $flow_rate > -100 )
  {
    #Q = m * c * delta t
    $AktQ = ( ($t_hs-$t_r1) * 4.19 * $flow_rate) / 3600;
    $AktQ = sprintf("%.03f", $AktQ);
  }
  readingsSingleUpdate($hash, "Info.Q", "$AktQ kW", 1) if ($OldQ != $AktQ);

  ### evaluation heating error: cyclic operation
  $hash->{helper}->{TStandby} = gettimeofday() if (not exists ($hash->{helper}->{TStandby}));
  $hash->{helper}->{THeat} = gettimeofday()    if (not exists ($hash->{helper}->{THeat}));
  $hash->{helper}->{StbHeatCnt} = 0            if (not exists ($hash->{helper}->{StbHeatCnt}));
  
  if ($hash->{helper}{HPSULstMode} ne $AktMode)
  {
    $hash->{helper}{TStandby} = gettimeofday() if ($AktMode eq $hash->{jcmd}->{mode}->{value_code}->{"0"});  #"Standby"
    $hash->{helper}{THeat} = gettimeofday() if ($AktMode eq $hash->{jcmd}->{mode}->{value_code}->{"1"});
    
    if ($hash->{helper}{HPSULstMode} eq $hash->{jcmd}->{mode}->{value_code}->{"1"})   #"Heizen"
    {
      if (($hash->{helper}{TStandby} - $hash->{helper}{THeat}) < 8*60)
      {
        $hash->{helper}->{StbHeatCnt}++;
      }
    }
    if ($AktMode eq $hash->{jcmd}->{mode}->{value_code}->{"3"})  #"Abtauen")
    {
      $hash->{helper}->{StbHeatCnt} = 0;
    }
    readingsSingleUpdate($hash, "Info.HeatCyclicErr", "$hash->{helper}->{StbHeatCnt}", 1);
  }
  if (ReadingsAge("$name", "Info.HeatCyclicErr", 0) > 20*60 )
  {
    $hash->{helper}->{StbHeatCnt} = 0;
  }


  $hash->{helper}{HPSULstMode} = $AktMode;
  $hash->{helper}{HPSULstMode_01} = $AktMode_01;

  InternalTimer(gettimeofday()+0.05, "HPSU_Task", $hash);
}

sub HPSU_Read_JSON_updreadings($)
{
  my ($hash) = @_;
  my ($anz, $ver) = HPSU_Read_JSON_File($hash);

  $hash->{JSON_parameters} = $anz;
  $ver = "Error: ".$anz if ($anz < 0);
  $hash->{JSON_version} = $ver;

  if ($anz > 0)
  {
    my $jcmd = $hash->{jcmd};  #after HPSU_Read_JSON_File() valid !

    my @PollTimekeys = grep ( $jcmd->{$_}->{FHEMPollTime} > 0, sort keys %{$jcmd});
    $hash->{helper}{PollTimeKeys} = \@PollTimekeys;
    $hash->{JSON_Auto_poll} = @PollTimekeys;  #Web Info
    my @Writablekeys = grep ( $jcmd->{$_}->{writable} eq "true", sort keys %{$jcmd});
    $hash->{helper}{Writablekeys} = \@Writablekeys;
    $hash->{JSON_Writable} = @Writablekeys;   #Web Info

    foreach my $key (@PollTimekeys)
    {
      $jcmd->{$key}->{FHEMLastResponse} = -1;
    }
  }
}

sub HPSU_CAN_RequestReadings($$$)
{
  my ( $hash, $hpsuNameCmd, $setVal ) = @_;
  my $jcmd = $hash->{jcmd};
  my ($CANMsg) = HPSU_CAN_RequestOrSetMsg($hash, $hpsuNameCmd, $setVal);

  if (defined $setVal)
  {
    $hash->{helper}{CANHeaderID} = "680";
  }
  else
  {
    $hash->{helper}{CANHeaderID} = $jcmd->{$hpsuNameCmd}->{id};
  }

  $hash->{helper}{CANRequestPending} = gettimeofday();
  if (defined $setVal)
  {
    $hash->{helper}{CANRequestName} = "NO DATA";
  }
  else
  {
    $hash->{helper}{CANRequestName} = $hpsuNameCmd;
  }
  if ($hash->{helper}{CANAktHeaderID} ne $hash->{helper}{CANHeaderID})
  {
    DevIo_SimpleWrite($hash, "AT SH $hash->{helper}{CANHeaderID}\r", 2);
    $hash->{helper}{firstCommand} = $CANMsg;
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
  my $cwd = getcwd();

  local $/; #Enable 'slurp' mode
  if (open(my $fh, "<:encoding(UTF-8)",  "$cwd/FHEM/commands_hpsu.json"))
  {
    $json = <$fh>;
    close $fh;
  }
  else
  {
    return -1;
  }

  if (defined($json))
  {
    $data = decode_json($json);

    if ($data->{commands})
    {
      while (my ($key, $value) = each %{ $data->{commands} } )
      {
        return -10 if (not $data->{commands}->{$key}->{name});
        return -10 if (not $data->{commands}->{$key}->{command});
        return -10 if (not $data->{commands}->{$key}->{id});
        return -10 if (not $data->{commands}->{$key}->{divisor});
        return -10 if (not $data->{commands}->{$key}->{type});

        $cnt += 1;
      }

      $hash->{jcmd} = $data->{commands};
    }
    else
    {
      return -2;
    }

  }
  else
  {
    return -3;
  }

  return ($cnt, $data->{version});
}

sub HPSU_CAN_ParamToFind($$)
{
  my ($hash, $CANMsg) = @_;
  my $jcmd = $hash->{jcmd};
  my $val = undef;
  my $cstart = 6; #address
  my $canz = 8;   #address char length

  return undef if (!$CANMsg or length($CANMsg) < $canz);

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

  my @all_matches = grep ( substr($jcmd->{$_}->{command}, $cstart, $canz)
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

  my $type = $jcmd->{$name}->{type};
  my $unit = $jcmd->{$name}->{unit};

  if ($type eq "int")
  {
    $value = HPSU_toSigned($ValByte1, $unit);
  }
  elsif ($type eq "value")
  {
    $value = $ValByte1;
  }
  elsif ($type eq "longint")
  {
    $value = HPSU_toSigned($ValByte2 + $ValByte1 * 0x0100, $unit);
  }
  elsif ($type eq "float")
  {
    $value = HPSU_toSigned($ValByte2 + $ValByte1 * 0x0100, $unit);
  }
  else
  {
    return undef;
  }
  
  $value /= $jcmd->{$name}->{divisor};

  if ($jcmd->{$name}->{value_code})
  {
    my $newvalue = $jcmd->{$name}->{value_code}->{$value};

    if (length($newvalue))
    {
      $value = $newvalue;
    }
  }

  if ($unit and not $jcmd->{$name}->{value_code})
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

  return $name, $jcmd->{$name}->{name}, $value;
}

sub HPSU_CAN_RequestOrSetMsg($$$)
{
  my ($hash, $name, $value) = @_;
  my $jcmd = $hash->{jcmd};
  my $CANMsg = undef;
  my $CANPattern = "00 00 00 00 00 00 00";
  my @value_code = ();
  my $len = 0;

  $CANMsg = $jcmd->{$name}->{command};
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
    return undef if ($jcmd->{$name}->{writable} ne "true");
  }
  
  if (defined $value and ($hash->{jcmd}->{$name}->{FHEMControl} eq "value_code"))
  {
    @value_code = grep ( $jcmd->{$name}->{value_code}->{$_} eq $value, sort keys %{$jcmd->{$name}->{value_code}});

    $value = $value_code[0];
  }

  # TODO toSigned?
  # TODO type value .. immer nur 2. Byte setzen?
  # TODO type longint mit Parameter z.b. aux_time testen

  if (defined $value)
  {
    my $type = $jcmd->{$name}->{type};
    my $unit = $jcmd->{$name}->{unit};
    my $ValByte1 = "00";
    my $ValByte2 = "00";

    if (($value < 0) and ($type ne "float"))
    {
      print "set negative values if type not float not possible !!!";
    }
    
    $value *= $jcmd->{$name}->{divisor};

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
  #my $outb = sprintf("0b%08b 0b%08b", $ValByte1, $ValByte2);

  #$out = "$ValByte1 - $ValByte2 - $out1 - $outb";
  $out = "$ValByte1 - $ValByte2 - $out1 - RAW: $CANMsg";
  
  return $name, $out;
}

sub Parse_SetGet_cmd($$)
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
    @matches = grep($jcmd->{$_}->{name} eq $in, keys %{$jcmd});
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
  my $cwd = getcwd();

  open($fh, ">>:encoding(UTF-8)",  "$cwd/FHEM/70_HPSU_Log.log") || return undef;
  $strout =~ s/\r/<\\r>/g;
  $strout =~ s/\n/<\\n>/g;
  print $fh HPSU_getLoggingTime().": ".$strout."\n";
  close($fh);

  return undef;
}

sub HPSU_Log2($)
{
  my ($str) = @_;
  my $strout = $str;
  my $fh = undef;
  my $cwd = getcwd();

  open($fh, ">>:encoding(UTF-8)",  "$cwd/FHEM/70_HPSU_Log20.log") || return undef;
  $strout =~ s/\r/<\\r>/g;
  $strout =~ s/\n/<\\n>/g;
  print $fh HPSU_getLoggingTime().": ".$strout."\n";
  close($fh);

  return undef;
}

1;
