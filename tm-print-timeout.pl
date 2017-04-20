#!/usr/bin/perl
use strict;
use lib qw(perllib);
use POSIX qw(strftime);
use JSON;
use Data::Dumper;

$|++;
my $json = JSON->new;

my $tmtimeout = 45;
my $tmadmin   = "$ENV{'TUXDIR'}/bin/tmadmin -r";
my $tuxconf   = "$ENV{'PS_CFG_HOME'}/appserv/$ENV{'ORACLE_SID'}/PSTUXCFG";
my @tuxcmd    = qw(psr pclt pq quit);
#my $logpath   = '/var/psoft/appserv/LOGS';
my $logpath   = 'LOGS';

my $tuxcmdstr = join ' && ', map { qq|/bin/echo "$_"| } @tuxcmd;
my @TM;
eval {
  local $SIG{ALRM} = sub { die "alarm\n" };
  alarm $tmtimeout;
  @TM = qx{(/bin/echo "page off" && $tuxcmdstr) | TUXCONFIG=$tuxconf $tmadmin 2>/dev/null};
  alarm 0;
};

my %tux;
my $tuxcmdout='';
if ($@) {
  die unless $@ eq "alarm\n";
} else {
  push @TM,"-\n";
  foreach (@tuxcmd) {
    $tux{$_}->{$_}->{'timestamp'} = strftime "%Y%m%dT%T",localtime unless ($_ eq 'quit');
  }
  foreach (@TM) {
    next if m/^[>\s]/;
    if (m/^-/) {$tuxcmdout=shift @tuxcmd; next;}
    chomp;

    if    ($tuxcmdout eq 'psr') {  #tmadmin psr
      my ($ProgName,$QueueName,$GrpName,$ID,$RqDone,$LoadDone,$dummy,$CurrentService,$dummy) = split /\s+/;
      $tux{'psr'}->{'psr'}->{'ProgNames'}->{$ProgName}->{'ID'}->{$ID} = { QueueName => $QueueName,
                                                                         GrpName   => $GrpName,
                                                                         RqDone    => $RqDone,
                                                                         LoadDone  => $LoadDone,
                                                                         CurrentSrv=> $CurrentService, };
      $tux{'psr'}->{'psr'}->{'ProgNames'}->{$ProgName}->{'Total'}++;
      $tux{'psr'}->{'psr'}->{'ProgNames'}->{$ProgName}->{'Total'.$CurrentService}++;
      $tux{'psr'}->{'psr'}->{'QueueNames'}->{$QueueName}->{'Total'}++;
      $tux{'psr'}->{'psr'}->{'QueueNames'}->{$QueueName}->{'Total'.$CurrentService}++;
#      printf "psr: %s,%s,%s\n", $ProgName,$QueueName,$CurrentService;
    }
    elsif ($tuxcmdout eq 'pclt') { #tmadmin pclt
      my ($LMID,$UserName,$ClientName,$Time,$Status,$BgnCmmtAbrt) = split /\s+/;
      my ($Bgn,$Cmmt,$Abrt) = split /\//,$BgnCmmtAbrt;
      push @{$tux{'pclt'}->{'pclt'}->{'ClientName'}->{$ClientName}->{'ClientList'}}, { LMID     => $LMID,
                                                                                     UserName => $UserName,
                                                                                     Time     => $Time,
                                                                                     Status   => $Status,
                                                                                     BgnCmmtAbrt   => $BgnCmmtAbrt,
                                                                                     Bgn      => $Bgn,
                                                                                     Cmmt     => $Cmmt,
                                                                                     Abrt     => $Abrt,     };
      $tux{'pclt'}->{'pclt'}->{'ClientName'}->{$ClientName}->{'Total'}++;
      $tux{'jsmon'}->{'jsmon'}->{'UserCount'}++ if (m/IDLE\/W/ || m/BUSY\/W/);
      $tux{'jsmon'}->{'jsmon'}->{'BusyCount'}++ if (m/BUSY\/W/);

#      printf "pclt: %s,%s,%d,%d,%d\n", $ClientName,$Status,$Bgn,$Cmmt,$Abrt;
    }
    elsif ($tuxcmdout eq 'pq') { #tmadmin pq
      my ($ProgName,$QueueName,$NumServe,$WkQueued,$NumQueued,$AveLen,$Machine) = split /\s+/;
      $tux{'pq'}->{'pq'}->{'ProgNames'}->{$ProgName} = { QueueName => $QueueName,
                                                         NumServe  => $NumServe,
                                                         WkQueued  => $WkQueued,
                                                         NumQueued => $NumQueued,
                                                         AveLen    => $AveLen,
                                                         Machine   => $Machine,      };
      $tux{'jsmon'}->{'jsmon'}->{'QueueNames'}->{$QueueName} = { NumServe  => $NumServe,
                                                                 NumQueued => $NumQueued,  };
#      printf "pq: %s:%d\n",${ProgName},${NumQueued};

    }
    else                 { next; }

#    print;
  }
}

#Generate "jsmon.sh"-like stats
$tux{'jsmon'}->{'jsmon'}->{'timestamp'} = strftime "%Y%m%dT%T",localtime;
$tux{'jsmon'}->{'jsmon'}->{'UserCount'} = 0 unless defined;
$tux{'jsmon'}->{'jsmon'}->{'BusyCount'} = 0 unless defined;
foreach my $q (keys %{$tux{'jsmon'}->{'jsmon'}->{'QueueNames'}}) {
  $tux{'jsmon'}->{'jsmon'}->{'QueueNames'}->{$q}->{'NonIDLE'} = ( $tux{'psr'}->{'psr'}->{'QueueNames'}->{$q}->{'Total'}
                                                                - $tux{'psr'}->{'psr'}->{'QueueNames'}->{$q}->{'TotalIDLE'}
                                                                );
}

#print "tuxcmdout:$tuxcmdout\n";
my $filedate = strftime "%m%d",localtime;
foreach (qw(jsmon psr pclt pq)) {
  open(FH, ">>${logpath}/tm_${_}-${filedate}.log");
  print FH $json->encode(\%{$tux{$_}}) ."\n"; 
  close FH;
}
#print $json->encode(\%{$tux{'jsmon'}});
#print "\n\n";
#print $json->encode(\%{$tux{'psr'}});
#print "\n\n";
#print $json->encode(\%{$tux{'pclt'}});
#print "\n\n";
#print $json->encode(\%{$tux{'pq'}});
#print "\n\n";
#print Dumper(\%tux) ."\n";
