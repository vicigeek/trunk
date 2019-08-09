#!/usr/bin/perl
#
# AST_CRON_audio_4_ftp2_FTPSSL.pl
#
# This is a STEP-4 program in the audio archival process
#
# runs every 3 minutes and copies the recording files to an FTPSSL server
# 
# ************* IMPORTANT!!!!!!!!!!!!!!!!!!!! ***************************
#  THIS SCRIPT REQUIRES THE Net::FTPSSL PERL MODULE TO RUN!!!
#  $ cpan
#  cpan> install ExtUtils::MakeMaker
#  cpan> install IO::Socket::SSL
#  cpan> install Net::SSLeay::Handle
#  cpan> install Net::FTPSSL
#  cpan> quit
#
#  MAKE SURE YOU TEST THAT THIS IS WORKING MANUALLY BEFORE PUTTING INTO THE CRONTAB!!!
#
# ************* IMPORTANT!!!!!!!!!!!!!!!!!!!! ***************************
#
# put an entry into the cron of of your asterisk machine to run this script 
# every 3 minutes or however often you desire
#
# ### recording mixing/compressing/ftping scripts
##0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl
# 0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_VDonly.pl
# 1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --GSM
# 2,5,8,11,14,17,20,23,26,29,32,35,38,41,44,47,50,53,56,59 * * * * /usr/share/astguiclient/AST_CRON_audio_3_ftp.pl --GSM
# 0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_4_ftp2_FTPSSL.pl
#
# FLAG FOR NO DATE DIRECTORY ON FTP
# --NODATEDIR
#
# if pinging is not working, try the 'icmp' Ping command in the code instead
# 
# make sure that the following directories exist:
# /var/spool/asterisk/monitorDONE	# where the mixed -all files are put
# 
# This program assumes that recordings are saved by Asterisk as .wav
# 
# Copyright (C) 2016  Matt Florell <vicidial@gmail.com>    LICENSE: AGPLv2
#
# CHANGES:
# 130730-1849 - First Build based upon AST_CRON_audio_4_ftp2.pl script
# 161212-1650 - Changed to use hard-coded encryption flag for module
#

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year = ($year + 1900);
$mon++;
if ($hour < 10) {$hour = "0$hour";}
if ($min < 10) {$min = "0$min";}
if ($sec < 10) {$sec = "0$sec";}
if ($mon < 10) {$mon = "0$mon";}
if ($mday < 10) {$mday = "0$mday";}
$FTPdate = "$year-$mon-$mday";

$GSM=0;   $MP3=0;   $OGG=0;   $WAV=0;   $GSW=0;   $NODATEDIR=0;

# Default variables for FTP
$VARFTP_host = '10.0.0.4';
$VARFTP_user = 'cron';
$VARFTP_pass = 'test';
$VARFTP_port = '21';
$VARFTP_dir  = 'RECORDINGS';
$VARHTTP_path = 'http://10.0.0.4';

$file_limit = 1000;
$list_limit = 1000;
$FTPpersistent=0;
$FTPvalidate=0;

### begin parsing run-time options ###
if (length($ARGV[0])>1)
	{
	$i=0;
	while ($#ARGV >= $i)
		{
		$args = "$args $ARGV[$i]";
		$i++;
		}

	if ($args =~ /--help/i)
		{
		print "allowed run time options:\n";
		print "  [--help] = this screen\n";
		print "  [--debug] = debug\n";
		print "  [--debugX] = super debug\n";
		print "  [--test] = test\n";
		print "  [--run-check] = concurrency check, die if another instance is running\n";
		print "  [--transfer-limit=XXX] = number of files to transfer before exiting\n";
		print "  [--list-limit=XXX] = number of files to list in the directory before moving on\n";
		print "  [--debugX] = super debug\n";
		print "  [--nodatedir] = do not put into dated directories\n";
		print "  [--ftp-server=XXX] = FTPSSL server\n";
		print "  [--ftp-port=XXX] = FTPSSL server port\n";
		print "  [--ftp-login=XXX] = FTPSSL server login account\n";
		print "  [--ftp-pass=XXX] = FTPSSL server password\n";
		print "  [--ftp-dir=XXX] = FTPSSL server directory\n";
		print "  [--ftp-encrypt=X] = FTPSSL encryption type, E=Explicit, I=Implicit, default=E\n";
		print "  [--ftp-persistent] = Does not log out between every file transmission\n";
	#	print "  [--ftp-validate] = Checks for a file size on the file after transmission\n";
		print "\n";
		exit;
		}
	else
		{
		if ($args =~ /--debug/i)
			{
			$DB=1;
			print "\n----- DEBUG -----\n\n";
			}
		if ($args =~ /--debugX/i)
			{
			$DBX=1;
			print "\n----- SUPER DEBUG -----\n\n";
			}
		if ($args =~ /--test/i)
			{
			$T=1;   $TEST=1;
			print "\n----- TESTING -----\n\n";
			}
		if ($args =~ /--nodatedir/i)
			{
			$NODATEDIR=1;
			if ($DB) {print "\n----- NO DATE DIRECTORIES -----\n\n";}
			}
		if ($args =~ /--run-check/i)
			{
			$run_check=1;
			if ($DB) {print "\n----- CONCURRENCY CHECK -----\n\n";}
			}
		if ($args =~ /--transfer-limit=/i) 
			{
			my @data_in = split(/--transfer-limit=/,$args);
			$file_limit = $data_in[1];
			$file_limit =~ s/ .*//gi;
			print "\n----- FILE TRANSFER LIMIT: $file_limit -----\n\n";
			}
		if ($args =~ /--list-limit=/i) 
			{
			my @data_in = split(/--list-limit=/,$args);
			$list_limit = $data_in[1];
			$list_limit =~ s/ .*//gi;
			print "\n----- FILE LIST LIMIT: $list_limit -----\n\n";
			}
		if ($args =~ /--ftp-server=/i) 
			{
			my @data_in = split(/--ftp-server=/,$args);
			$VARFTP_host = $data_in[1];
			$VARFTP_host =~ s/ .*//gi;
			$CLIFTP_host=1;
			if ($DB > 0) 
				{print "\n----- FTPSSL SERVER: $VARFTP_host -----\n\n";}
			}
		if ($args =~ /--ftp-port=/i)
			{
			my @data_in = split(/--ftp-port=/,$args);
			$VARFTP_port = $data_in[1];
			$VARFTP_port =~ s/ .*//gi;
			$CLIFTP_port=1;
			if ($DB > 0)
				{print "\n----- FTPSSL PORT: $VARFTP_port -----\n\n";}
			}
		if ($args =~ /--ftp-login=/i) 
			{
			my @data_in = split(/--ftp-login=/,$args);
			$VARFTP_user = $data_in[1];
			$VARFTP_user =~ s/ .*//gi;
			$CLIFTP_user=1;
			if ($DB > 0) 
				{print "\n----- FTPSSL LOGIN: $VARFTP_user -----\n\n";}
			}
		if ($args =~ /--ftp-pass=/i) 
			{
			my @data_in = split(/--ftp-pass=/,$args);
			$VARFTP_pass = $data_in[1];
			$VARFTP_pass =~ s/ .*//gi;
			$CLIFTP_pass=1;
			if ($DB > 0) 
				{print "\n----- FTPSSL PASS: $VARFTP_pass -----\n\n";}
			}
		if ($args =~ /--ftp-dir=/i) 
			{
			my @data_in = split(/--ftp-dir=/,$args);
			$VARFTP_dir = $data_in[1];
			$VARFTP_dir =~ s/ .*//gi;
			$CLIFTP_dir=1;
			if ($DB > 0) 
				{print "\n----- FTPSSL DIRECTORY: $VARFTP_dir -----\n\n";}
			}
		if ($args =~ /--ftp-encrypt=/i) 
			{
			my @data_in = split(/--ftp-encrypt=/,$args);
			$VARFTP_encrypt = $data_in[1];
			$VARFTP_encrypt =~ s/ .*//gi;
			if ($VARFTP_encrypt =~ /E/) {$VARFTP_encrypt = 'EXP_CRYPT';}
			if ($VARFTP_encrypt =~ /I/) {$VARFTP_encrypt = 'IMP_CRYPT';}
			if (length($VARFTP_encrypt)<5) {$VARFTP_encrypt = 'EXP_CRYPT';}
			$CLIFTP_encrypt=1;
			if ($DB > 0) 
				{print "\n----- FTPSSL ENCRYPTION: $VARFTP_encrypt -----\n\n";}
			}
		if ($args =~ /--ftp-persistent/i) 
			{
			$FTPpersistent=1;
			if ($DB > 0) 
				{print "\n----- FTPSSL PERSISTENT: $FTPpersistent -----\n\n";}
			}
	#	if ($args =~ /--ftp-validate/i) 
	#		{
	#		$FTPvalidate=1;
	#		if ($DB > 0) 
	#			{print "\n----- FTPSSL VALIDATE: $FTPvalidate -----\n\n";}
	#		}
		}
	}
else
	{
	#print "no command line options set\n";
	$WAV=1;
	}
if (length($VARFTP_encrypt)<5) {$VARFTP_encrypt = 'EXP_CRYPT';}


# default path to astguiclient configuration file:
$PATHconf =		'/etc/astguiclient.conf';

open(conf, "$PATHconf") || die "can't open $PATHconf: $!\n";
@conf = <conf>;
close(conf);
$i=0;
foreach(@conf)
	{
	$line = $conf[$i];
	$line =~ s/ |>|\n|\r|\t|\#.*|;.*//gi;
	if ( ($line =~ /^PATHhome/) && ($CLIhome < 1) )
		{$PATHhome = $line;   $PATHhome =~ s/.*=//gi;}
	if ( ($line =~ /^PATHlogs/) && ($CLIlogs < 1) )
		{$PATHlogs = $line;   $PATHlogs =~ s/.*=//gi;}
	if ( ($line =~ /^PATHagi/) && ($CLIagi < 1) )
		{$PATHagi = $line;   $PATHagi =~ s/.*=//gi;}
	if ( ($line =~ /^PATHweb/) && ($CLIweb < 1) )
		{$PATHweb = $line;   $PATHweb =~ s/.*=//gi;}
	if ( ($line =~ /^PATHsounds/) && ($CLIsounds < 1) )
		{$PATHsounds = $line;   $PATHsounds =~ s/.*=//gi;}
	if ( ($line =~ /^PATHmonitor/) && ($CLImonitor < 1) )
		{$PATHmonitor = $line;   $PATHmonitor =~ s/.*=//gi;}
	if ( ($line =~ /^PATHDONEmonitor/) && ($CLIDONEmonitor < 1) )
		{$PATHDONEmonitor = $line;   $PATHDONEmonitor =~ s/.*=//gi;}
	if ( ($line =~ /^VARserver_ip/) && ($CLIserver_ip < 1) )
		{$VARserver_ip = $line;   $VARserver_ip =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_server/) && ($CLIDB_server < 1) )
		{$VARDB_server = $line;   $VARDB_server =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_database/) && ($CLIDB_database < 1) )
		{$VARDB_database = $line;   $VARDB_database =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_user/) && ($CLIDB_user < 1) )
		{$VARDB_user = $line;   $VARDB_user =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_pass/) && ($CLIDB_pass < 1) )
		{$VARDB_pass = $line;   $VARDB_pass =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_port/) && ($CLIDB_port < 1) )
		{$VARDB_port = $line;   $VARDB_port =~ s/.*=//gi;}
	if ( ($line =~ /^VARFTP_host/) && ($CLIFTP_host < 1) )
		{$VARFTP_host = $line;   $VARFTP_host =~ s/.*=//gi;}
	if ( ($line =~ /^VARFTP_user/) && ($CLIFTP_user < 1) )
		{$VARFTP_user = $line;   $VARFTP_user =~ s/.*=//gi;}
	if ( ($line =~ /^VARFTP_pass/) && ($CLIFTP_pass < 1) )
		{$VARFTP_pass = $line;   $VARFTP_pass =~ s/.*=//gi;}
	if ( ($line =~ /^VARFTP_port/) && ($CLIFTP_port < 1) )
		{$VARFTP_port = $line;   $VARFTP_port =~ s/.*=//gi;}
	if ( ($line =~ /^VARFTP_dir/) && ($CLIFTP_dir < 1) )
		{$VARFTP_dir = $line;   $VARFTP_dir =~ s/.*=//gi;}
	if ( ($line =~ /^VARHTTP_path/) && ($CLIHTTP_path < 1) )
		{$VARHTTP_path = $line;   $VARHTTP_path =~ s/.*=//gi;}
	$i++;
	}


### concurrency check
if ($run_check > 0)
	{
	my $grepout = `/bin/ps ax | grep $0 | grep -v grep | grep -v '/bin/sh'`;
	my $grepnum=0;
	$grepnum++ while ($grepout =~ m/\n/g);
	if ($grepnum > 1) 
		{
		if ($DB) {print "I am not alone! Another $0 is running! Exiting...\n";}
		exit;
		}
	}

# Customized Variables
$server_ip = $VARserver_ip;		# Asterisk server IP
if (!$VARDB_port) {$VARDB_port='3306';}

use Time::HiRes ('gettimeofday','usleep','sleep');  # necessary to have perl sleep command of less than one second
use DBI;

$dbhA = DBI->connect("DBI:mysql:$VARDB_database:$VARDB_server:$VARDB_port", "$VARDB_user", "$VARDB_pass")
 or die "Couldn't connect to database: " . DBI->errstr;

use Net::Ping;
use Net::FTPSSL;

### directory where -all recordings are
$dir2 = "$PATHDONEmonitor/FTP";

opendir(FILE, "$dir2/");
@FILES = readdir(FILE);

### Loop through files first to gather filesizes
$i=0;
$files_that_count=0;
foreach(@FILES)
	{
	$FILEsize1[$i] = 0;
	if ( (length($FILES[$i]) > 4) && (!-d "$dir2/$FILES[$i]") )
		{
		$FILEsize1[$i] = (-s "$dir2/$FILES[$i]");
		if ($DBX) {print "$dir2/$FILES[$i] $FILEsize1[$i]\n";}
		$files_that_count++;
		}
	$i++;
	if ($files_that_count >= $list_limit)
		{
		last();
		}		
	}

sleep(5);

$transfered_files = 0;

### Loop through files a second time to gather filesizes again 5 seconds later
$i=0;
foreach(@FILES)
	{
	$FILEsize2[$i] = 0;

	if ( (length($FILES[$i]) > 4) && (!-d "$dir2/$FILES[$i]") )
		{
		$FILEsize2[$i] = (-s "$dir2/$FILES[$i]");
		if ($DBX) {print "$dir2/$FILES[$i] $FILEsize2[$i]\n\n";}
		
		if ($FILEsize1[$i] ne $FILEsize2[$i]) 
			{
			if ($DBX) {print "not transfering $dir2/$FILES[$i]. File size mismatch $FILEsize2[$i] != $FILEsize1[$i]\n\n";}
			}

		if ( ($FILES[$i] !~ /out\.|in\.|lost\+found/i) && ($FILEsize1[$i] eq $FILEsize2[$i]) && (length($FILES[$i]) > 4))
			{
			$recording_id='';
			$ALLfile = $FILES[$i];
			$SQLFILE = $FILES[$i];
			$SQLFILE =~ s/\.gpg//gi;
			$SQLFILE =~ s/-all\.wav|-all\.gsm|-all\.ogg|-all\.mp3//gi;

			$stmtA = "select recording_id,start_time from recording_log where filename='$SQLFILE' order by recording_id desc LIMIT 1;";
			if($DBX){print STDERR "\n|$stmtA|\n";}
			$sthA = $dbhA->prepare($stmtA) or die "preparing: ",$dbhA->errstr;
			$sthA->execute or die "executing: $stmtA ", $dbhA->errstr;
			$sthArows=$sthA->rows;
			if ($sthArows > 0)
				{
				@aryA = $sthA->fetchrow_array;
				$recording_id =	$aryA[0];
				$start_date =	$aryA[1];
				$start_date =~ s/ .*//gi;
				}
			$sthA->finish();

			if (length($start_date) < 6)
				{$start_date = $FTPdate;}

			if ($DB) {print "|$recording_id|$start_date|$ALLfile|     |$SQLfile|\n";}

	### BEGIN Remote file transfer
			if ( ($FTPpersistent > 0) && ($ping_good > 0) )
				{$ping_good=1;}
			else
				{
				$p = Net::Ping->new();
				$ping_good = $p->ping("$VARFTP_host");
				}

			if (!$ping_good)
				{
				$p = Net::Ping->new("icmp");
				$ping_good = $p->ping("$VARFTP_host");
				}

			if ($ping_good)
				{	
				$transfered_files++;
				
				$start_date_PATH='';
				$FTPdb=0;
				if ($DBX>0) {$FTPdb=1;}
				if ( ($FTPpersistent > 0) && ($transfered_files > 1) )
					{
					if($DBX){print STDERR "FTPSSL PERSISTENT, skipping login\n";}
					if ($NODATEDIR < 1)
						{
						$ftps->cwd("../");
						}
					}
				else
					{
					# Some versions of the FTPSSL perl module require you to hard code the encryption value: IMP_CRYPT or EXP_CRYPT
					# $ftps = Net::FTPSSL->new("$VARFTP_host", Port => $VARFTP_port, Encryption => $VARFTP_encrypt, Debug => $FTPdb);
					if ( $VARFTP_encrypt eq "IMP_CRYPT" ) 
						{
						$ftps = Net::FTPSSL->new("$VARFTP_host", Port => $VARFTP_port, Encryption => IMP_CRYPT, Debug => $FTPdb);
						}
					else 
						{
						$ftps = Net::FTPSSL->new("$VARFTP_host", Port => $VARFTP_port, Encryption => EXP_CRYPT, Debug => $FTPdb);
						}
					$ftps->login("$VARFTP_user","$VARFTP_pass");
					$ftps->cwd("$VARFTP_dir");
					}
				if ($NODATEDIR < 1)
					{
					$ftps->Net::FTPSSL::mkdir("$start_date");
					$ftps->cwd("$start_date");
					$start_date_PATH = "$start_date/";
					}
				$ftps->binary();
				$ftps->put("$dir2/$ALLfile", "$ALLfile");
			#	if ($FTPvalidate > 0)
			#		{
			#		$FTPfilesize = $ftps->size("$ALLfile");
			#		if($DBX){print STDERR "FTP FILESIZE:   $FTPfilesize/$FILEsize1[$i] | $ALLfile\n";}
			#		if ( ($FILEsize1[$i] > 100) && ($FTPfilesize < 100) )
			#			{
			#			print "ERROR! File did not transfer, exiting:   $FTPfilesize/$FILEsize1[$i] | $ALLfile\n";
			#			exit;
			#			}
			#		}
				if ($FTPpersistent < 1)
					{
					$ftps->quit;
					}

			# FTP2 scripts do not alter the URL of the recording
			#	$stmtA = "UPDATE recording_log set location='$VARHTTP_path/$start_date_PATH$ALLfile' where recording_id='$recording_id';";
			#		if($DB){print STDERR "\n|$stmtA|\n";}
			#	$affected_rows = $dbhA->do($stmtA); #  or die  "Couldn't execute query:|$stmtA|\n";

				if (!$T)
					{
					`mv -f "$dir2/$ALLfile" "$PATHDONEmonitor/FTP2/$ALLfile"`;
					}
				
				if($DBX){print STDERR "Transfered $transfered_files files\n";}
				
				if ( $transfered_files == $file_limit) 
					{
					if($DBX){print STDERR "Transfer limit of $file_limit reached breaking out of the loop\n";}
					last();
					}
				}
			else
				{
				if($DB){print "ERROR: Could not ping server $VARFTP_host\n";}
				}
	### END Remote file transfer

			### sleep for twenty hundredths of a second to not flood the server with disk activity
			usleep(1*200*1000);

			}
		}
	$i++;
	}

if ($DB) {print "DONE... EXITING\n\n";}

$dbhA->disconnect();


exit;
