#!/usr/bin/perl

############################################################
# BelMonIn.pl: Actua como ESME en una sesion SMPP.         #
#                                                          #
# Revision: 25/11/2002                                     #
#                                                          #
# Este programa inicia una sesion de SMPP, como un ESME en #
# modo recepcion. Es el encargado de esperar la            #
# informacion que mande el servidor de SMPP. Luego utiliza #
# kermit para enviar la misma al programa de monitoreo.    #
############################################################

use BelMon;
use Net::SMPP;
use IO::Handle;
use Fcntl;

pipe(READER, WRITER);
WRITER->autoflush(1);

if ($pid = fork)
{
	# Subproceso encargado de esperar los paquetes de SMPP, y luego
	# lo envia al programa de monitoreo utilizando kermit.
	close READER;

	$debug = $ENV{'DEBUG'};
	$debug = 1;
	if ($debug > 0)
	{
		use Data::Dumper;
		$trace = 1;
		$Net::SMPP::trace = 1;
	}

	$SIG{ALRM} = \&enviar_enquire_link;
	$SIG{INT} = \&terminar;

#	%ultima_sesion = ();
	print "Iniciando Session SMPP\n";
	&logentry("BelMonIn.log", "Iniciando Session SMPP");

	$smpp = Net::SMPP->new_receiver($server,
			smpp_version => $version,
			system_id => $userid,
			password => $password,
			port => $port,
			)
	or &exit_with_error($debug, "No puedo establecer sesion SMPP: $!");


	# Dispara alarma para el envio del enquire_link
	alarm($periodo_enquire_link);

	&esperar_paquete();
}
else
{
	# Este subproceso es el encargado de matar uno de los
	# procesos del programa de monitoreo. Cuando este se
	# levanta nuevamente, realiza la negociacion inicial
	# del modem. Luego finaliza.
	die "Error al realizar fork: $!" unless defined $pid;
	close WRITER;

	$csrtcrx_pid = `ps -ae -o pid,comm |grep CSRTCRX |grep -v grep`;
	($csrtcrx_pid) = ($csrtcrx_pid =~ /([^C]*)/);

	$comando = "kill -9 $csrtcrx_pid";
	print "Comando: $comando \n";
	system($comando);

	sysopen (SERIAL, "/dev/term/2", O_RDWR);
	while(<SERIAL>)
	{
		print "Viene de 7: $_";
		if ($_ =~ /^at/i)
		{
			print SERIAL "OK\r\n";
			print "Va al 3: OK\r\n";
		}
		if ($_ = /at&w/i)
		{
			last;
		}
	}
	close (SERIAL);
	print "Saliendo del proceso hijo \n";
}

