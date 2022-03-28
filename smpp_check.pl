#!/usr/bin/perl
#
# Fecha: 16/05/2003
#
# /export/home/cba/smpp_check.pl - Chequea que los procesos de SMPP
# esten corriendo.
#

use strict;
use Time::Local;
use vars qw'$patron';

my $hora_actual = timelocal(localtime);
my $homedir = "/export/home/cba/";
my $filename;
my $mtime;
my $diferencia;
my $comando;
my $ps;

# Chequea que este corriendo el proceso BelMonIn.pl
$filename = $homedir."BelMonIn.out";
$mtime = (stat($filename))[9];
$diferencia = abs($hora_actual - $mtime);

if ($diferencia > 310)
{
	&bajar_procesos("BelMonIn.pl");
}

$ps = `/usr/bin/ps -e -o pid,comm,args | /usr/bin/grep BelMonIn.pl | /usr/bin/grep perl| /usr/bin/grep -v grep | wc -l`;
($ps) = ($ps =~ /\s*([^\n]*)/);
if ($ps != 1)
{
	print "$ps BelMonIn.pl corriendo ...";
	&bajar_procesos("BelMonIn.pl");
	$comando = "cd /export/home/cba; /export/home/cba/BelMonIn.pl >> /export/home/cba/BelMonIn.out 2>> /export/home/cba/BelMonIn.out &";
	system($comando);
}


# Chequea que este corriendo el proceso capbelgrano
$ps = `/usr/bin/ps -e -o pid,comm,args | /usr/bin/grep capbelgrano | /usr/bin/grep -v grep | wc -l`;
($ps) = ($ps =~ /\s*([^\n]*)/);
if ($ps == 0)
{
	$comando = "cd /export/home/cba; /export/home/cba/capbelgrano -b 9600 -l /tmp/capturador.log -d /dev/term/3 >> /export/home/cba/capbelgrano.out 2>> /export/home/cba/capbelgrano.out &";
	system($comando);
}


# Chequea que este corriendo el proceso BelMonOut.pl
$filename = $homedir."BelMonOut.out";
$mtime = (stat($filename))[9];
$diferencia = abs($hora_actual - $mtime);

if ($diferencia > 310)
{
	&bajar_procesos("BelMonOut.pl");
}

$ps = `/usr/bin/ps -e -o pid,comm,args | /usr/bin/grep BelMonOut.pl | /usr/bin/grep perl| /usr/bin/grep -v grep | wc -l`;
($ps) = ($ps =~ /\s*([^\n]*)/);
if ($ps != 2)
{
	print "$ps BelMonOut.pl corriendo ...";
	&bajar_procesos("BelMonOut.pl");
	$comando = "cd /export/home/cba; /export/home/cba/BelMonOut.pl >> /export/home/cba/BelMonOut.out 2>> /export/home/cba/BelMonOut.out &";
	system($comando);
}

exit;



sub bajar_procesos
{
	print "Matando proceso $patron si existe ...";
	($patron) = @_;

	my $ps = "/usr/bin/ps -e -o pid,comm,args | /usr/bin/grep $patron | /usr/bin/grep perl| /usr/bin/grep -v grep | /usr/bin/sed -e 's/^  *//' -e 's/ .*//'";
	open (PID, "$ps |");
	while (<PID>)
	{
		my $comando;
		chop;

		$comando = "kill $_ >/dev/null 2>/dev/null";
		system($comando);
		sleep(1);
	}
}
