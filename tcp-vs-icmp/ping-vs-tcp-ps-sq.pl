#!/usr/local/bin/perl -w
#See https://confluence.slac.stanford.edu/display/IEPM/IEPM+Perl+Coding+Styles
#for version of perl to use.

#The following code is placed at the top to ensure we are able to use perl -d
#and stop things before they call other things.
my $debug; #For cronjobs use -1, for normal execution from command line use 0, 
           #for debugging information use > 0, max value = 3.
if (-t STDOUT) {$debug=0;}
else           {$debug=-1;} #script executed from cronjob

use strict;
$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
#  ....................................................................
(my $progname = $0) =~ s'^.*/'';#strip path components, if any
# **************************************************************** 
#  Please send comments and/or suggestion to Les Cottrell.
# Owner(s): Les Cottrell (1/10/2018).                                
# Revision History:                                                
#my $version="0.1, 1/10/2018";
#my $version="0.2, 1/22/2018, Cottrell";#Fix $opt_p bug, add $port to reports, made $fn unique, comment hostname check, replaced getopts.
my $version="0.3, 1/20/2018, Cottrell";#Fix --help, --count, -port for nping.
# **************************************************************** 
#Get some useful variables for general use in code
my $t0=time();
umask(0002);
#use Net::Domain qw(hostname hostfqdn hostdomain);
#my $hostname = hostfqdn();
#use Socket;
#my $ipaddr=inet_ntoa(scalar(gethostbyname($hostname||'localhost')));
my $user=scalar(getpwuid($<));
##################Your code starts here..#######################
my $url='http://www-iepm.slac.stanford.edu/pinger/pingerworld/slaconly-nodes.cf';
my $fn="/tmp/nodes-$$.cf";
my $cf='ps-v6-sq.cf';
my $USAGE = "Usage:\t $progname [opts] 
        Opts:
        --help     print this USAGE information
        --debug    debug_level (default=$debug)
        --prot     protocol (6 or '') (default '')
        --port     application port (default = 80)
        --count    count of pings or npings to be sent (default = 10)
        --conf     input csv config file with target hosts
Function:
  Ping the list of hosts provided in the configuration file
  $cf.
  This list is obtained from the perfSONAR JSON database.
  For each host it gets the IP address either from the list (IPv4)
  or using the dig command (IPv6).
  It then Pings and npings the host and gathers the min, average, maximum
  RTTs and losses and reports them to STDOUT, together with a time stamp
  and host information  such as name, IP address, country, region etc.  
Externals:
  Requires nping (requires root/sudo privs), dig
Input:
  It gets information on the PingER hosts from 
  $cf.
Examples:
 $progname
 $progname --prot 6 --port 22 --count 10
 sudo $progname --conf ps-v6-sq.cf | tee ps-v6-sq.txt
 $progname --help 
Warning:
 If the config file is obtained from Windows then you will need to change the
 file froma Windows text file to a Linux text file. This can be done from
 the command line via the command:
 perl -p -e 's/\r$//' < winfile.txt > unixfile.txt
 In our experience the unixfile.txt will still need some editing to remove 
 some special characters and to fix up some broken lines.
Hint: 
 To turn the output into a real csv file do something like:
 grep warning ps-v6-sq.txt > ps-v6-sq.csv 
Version=$version
";
##############################################################
#Process options
use Getopt::Long;
my $prot="6"; my$port='80'; my $help; my $count='10';
GetOptions ("prot=s" => \$prot,
            "port=s" => \$port,
            "debug=i"=> \$debug,    
            "help"   => \$help,
            "conf=s" => \$cf,
            "count=i"=> \$count) or die('Error in command line options\n');
if(defined($help)) {print $USAGE; exit;}
##############################################################
#Read the csv configuration file;
my $nk = `wc -l < $cf`;
die "wc failed: $?" if $?;
chomp($nk);
#open(my $fh, '<:encoding(UTF-8)', $cf)
open(my $fh, $cf)
  or die "Could not open file '$cf' $!";
############################################################## 
my %n; $n{'noping'}=0; $n{'success'}=0; $n{'noNping'}=0; $n{'Npings'}=0;
while (my $row = <$fh>) {
  $n{'lines'}++;
  chomp $row;
  if($debug>0) {print "Input from $cf: $row\n";}
  #Example of Configuration file input
  #64.251.58.166, perfsonar.cen.ct.gov,  US, Hartford, 41.767688, -72.687567, 1
  #109.105.125.233, pship02.csc.fi,  FI, Espoo, 60.1915, 24.8993, 1
  #164.113.32.89, ps-esu-lt.perfsonar.kanren.net,  US, Lawrence, 38.415, -96.182, 1
  #134.75.250.194, ,  KR, Daejeon, 36.366561, 128.358820, N/A
  my ($sn,$key,$ipv6,$city,$lat,$long,$tld,$country)=split(',',$row);
  if($sn eq 'Serial No.') {next;} #Skip header
  my $ip=$ipv6;
  #$if($prot eq '6') {
  #  $ip=dig($key);
  #  if($ip=~/^warning/) {next;}
  #}  
  my $result=get_ping_rtt($ip,$prot,$count);
  if($result=~/^warning/) {
    $n{'noping'}++; 
    if($debug>0) {print "$result\n";}
    next;
  }
  $n{'success'}++;
  print "(success=$n{'success'}/noping=$n{'noping'}/$n{'lines'}/$nk)$key($ip,$port),"
      . "gave $result\n";
  my $result1=get_nping_rtt($ip,$prot,$count,$port);
  my $summary="";
  if($result1=~/^warning/) {
    $n{'noNping'}++; 
    if($debug>0) {print "$result1\n";}
    next;
  }
  if($result1=~/100.00%/)   {
    $n{'noNping'}++;
  }
  else { 
    $n{'Npings'}++;
    $summary=scalar(localtime()).",summary,$count,$key,$ip,$port,$country,$tld,$lat,$long,ping,$result,nping,$result1";
  }
  print "(Npings=$n{'Npings'}/noNping=$n{'noNping'}/$n{'lines'}/$nk)$key($ip,$port) "
      . "gave $result1\n";
  if($summary ne "") {print "$summary\n";}
}
unlink $fn;
`rm -f $fn`;
#################################################
#Execute the nping and return result or a warning
sub get_nping_rtt {
  my $ip_addr=$_[0]; my $prot=$_[1]; my $count=$_[2]; my $port=$_[3];
  my $pr="";
  if ($prot eq '6') {
    $pr='-6';
    if(valid_ip($ip_addr) ne $prot) {
      return ("warning invalid IPv6 address = $ip_addr for nping\n");
    }
  }
  my $cmd="sudo nping -c $count  -p $port $pr --tcp-connect $ip_addr";
  my @ans=`$cmd`;
  #Typical output
  # Starting Nping 0.5.51 ( http://nmap.org/nping ) at 2018-01-13 15:21 PST
  # SENT (0.0021s) Starting TCP Handshake > 2001:da8:270:2018:f816:3eff:fef3:bd3:80
  # RECV (0.1679s) Handshake with 2001:da8:270:2018:f816:3eff:fef3:bd3:80 completed
  # ..
  # Max rtt: 165.789ms | Min rtt: 165.073ms | Avg rtt: 165.431ms
  #TCP connection attempts: 2 | Successful connections: 2 | Failed: 0 (0.00%)
  #Tx time: 1.00329s | Tx bytes/s: 159.48 | Tx pkts/s: 1.99
  #Rx time: 1.16836s | Rx bytes/s: 68.47 | Rx pkts/s: 1.71
  #Nping done: 1 IP address pinged in 1.17 seconds 
  my @rtts=grep(/^Max rtt/,@ans);
  unless(@rtts) {return("warning no valid response for $cmd, response:\n@ans");}
  if(scalar(@ans)<10) {
    my $temp=valid_ip($ip_addr);
    return("warning too few line from $cmd, response:\n@ans");
  }
  my $temp=$rtts[0];
  my @tokens=split(/\|/,$temp);
  my $rtts="";
  foreach my $token (@tokens) {
     my (undef,$rtt)=split(/:/,$token);
     $rtt=~s/ //g;
     $rtt=~s/ms//g; chomp($rtt);
     $rtts=$rtts.$rtt.',';
  }   
  my @loss=grep(/^TCP connection attempts:/,@ans);
  unless(@loss) {return("warning no nping loss information for $ip_addr, response:\n@ans");}
  $temp=$loss[0]; chomp($temp);
  my $loss="";
  (undef,$loss)=split(/\(/, $temp);
  if($loss eq "") {return("warning unable to get loss from nping for $ip_addr, response:\n@ans");}
  $loss=~s/\)//; chomp($loss);
  return("$rtts, $loss");
}
#################################################
#Execute the ping and return min/avg/max RTT for the IP address
sub get_ping_rtt {
  my $ip_addr=$_[0]; my $prot=$_[1]; my $count=$_[2];
  my $ping="ping";
  if($prot eq '6') {$ping='ping6';}
  my $cmd="$ping -c $count $ip_addr";
  my @ans=`$cmd`;
  my $rc=$?;
  #Typical answer
  #PING unk.us (50.63.202.23) 56(84) bytes of data.
  #64 bytes from ip-50-63-202-23.ip.secureserver.net (50.63.202.23): icmp_seq=1 ttl=51 time=20.0 ms
  #...
  #64 bytes from ip-50-63-202-23.ip.secureserver.net (50.63.202.23): icmp_seq=10 ttl=51 time=20.1 ms
  #--- unk.us ping statistics ---
  #10 packets transmitted, 9 received, 1% packet loss, time 13410ms
  #rtt min/avg/max/mdev = 20.010/20.082/20.178/0.192 ms
  if(@ans && $ans[$#ans]=~/^rtt min/) {
    my $temp=$ans[$#ans];
    my (undef,$rtt)=split(' = ',$temp);
    $rtt=~s/ ms//; chomp $rtt;
    $rtt=~s/\//,/g;
    $temp=$ans[$#ans-1];
    my @tokens=split(', ', $temp);
    $temp=$tokens[2];
    my ($loss,undef)=split('\s+', $temp);
    return ("$rtt, $loss");
  }
  else {
    if ($rc eq '512') {
      print "$cmd received no response, \$?=$rc\n";
    } 
    return "warning: no valid ping response for $ip_addr, response:\n@ans";
  }
}    
#################################################
#Given a hostname provide the IPv6 address
sub dig {
  my $name=$_[0];
  my $cmd="dig $name AAAA | grep -v ';' | grep 'IN' | grep AAAA";#remove comments and blank lines
  #dig command output:
  #449cottrell@pinger:~$dig hcc-ps02.unl.edu AAAA
  #
  #; <<>> DiG 9.8.2rc1-RedHat-9.8.2-0.62.rc1.el6_9.4 <<>> hcc-ps02.unl.edu AAAA
  #;; global options: +cmd
  #;; Got answer:
  #;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 23042
  #;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 2, ADDITIONAL: 4
  #
  #;; QUESTION SECTION:
  #;hcc-ps02.unl.edu.              IN      AAAA
  #
  #;; ANSWER SECTION:
  #hcc-ps02.unl.edu.       86342   IN      AAAA    2600:900:6:1101:21b:21ff:fe96:a3d4
  #
  #;; AUTHORITY SECTION:
  #unl.edu.                69696   IN      NS      dns2.unl.edu.
  #unl.edu.                69696   IN      NS      dns1.unl.edu.
  #
  #;; ADDITIONAL SECTION:
  #dns1.unl.edu.           368399  IN      A       129.93.168.59
  #dns1.unl.edu.           542     IN      AAAA    2600:908:300:101::3
  #dns2.unl.edu.           18325   IN      A       129.93.168.60
  #dns2.unl.edu.           542     IN      AAAA    2600:908:300:101::4
  #
  #;; Query time: 1 msec
  #;; SERVER: 134.79.111.111#53(134.79.111.111)
  #;; WHEN: Thu Jan 11 15:57:01 2018
  #;; MSG SIZE  rcvd: 188
  #
  #
  #After removal of comments and blank lines this reolves to:
  #hcc-ps02.unl.edu.       85669   IN      AAAA    2600:900:6:1101:21b:21ff:fe96:a3d4
  #unl.edu.                69023   IN      NS      dns1.unl.edu.
  #unl.edu.                69023   IN      NS      dns2.unl.edu.
  #dns1.unl.edu.           367726  IN      A       129.93.168.59
  #dns2.unl.edu.           17652   IN      A       129.93.168.60
  my @ans=`$cmd`;
  if(!defined($ans[0])) {
    return("warning:$cmd can't find any records");
  }
  my @tokens=split(/\s/,$ans[0]);
  if(!defined($tokens[4])){
    return("warning:$cmd can't find an AAAA record");
  }
  if(valid_ip($tokens[4]) ne '6') {
    return("warning:$cmd returned an invalid IP address=$tokens[4]");
  }
  return($tokens[4]);
}
#################################################
#Given a string, it checks whether it is a valid IP name (returns "n"),
#or valid IPv4 address (returns "4"), or valid IPv6 address returns "6").
#If invalid it returns "0";
#For IP name see: http://stackoverflow.com/questions/106179/regular-expression-to-match-hostname-or-ip-address
#For IPv4 address see: http://answers.oreilly.com/topic/318-how-to-match-ipv4-addresses-with-regular-expressions/
#For IPv6 address see: http://forums.dartware.com/viewtopic.php?t=452
#Test cases for IPv6 address (we are using aeron) see http://download.dartware.com/thirdparty/test-ipv6-regex.pl
sub valid_ip {
  if(length($_[0])<256) {
    if($_[0]=~/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/){#IPv4 address
      return "4";
    }
    elsif($_[0]=~/^(((?=(?>.*?::)(?!.*::)))(::)?([0-9A-F]{1,4}::?){0,5}|([0-9A-F]{1,4}:){6})(\2([0-9A-F]{1,4}(::?|$)){0,2}|((25[0-5]|(2[0-4]|1[0-9]|[1-9])?[0-9])(\.|$)){4}|[0-9A-F]{1,4}:[0-9A-F]{1,4})(?<![^:]:)(?<!\.)\z/i) {#IPv6 Address
      return "6";
    }
    elsif($_[0]=~/^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*$/) {#Name
      return "n";    
    } 
  }
  return "0";
}
__END__
