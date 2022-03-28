#!/usr/bin/perl

############################################################
# BelMonOut.pl: Actua como ESME en una sesion SMPP.        #
#                                                          #
# Revision: 25/11/2002                                     #
#                                                          #
# Este programa inicia una sesion de SMPP, como un ESME en #
# modo transmision. Es el encargado de esperar la          #
# informacion que mande el programa de monitoreo, arma el  #
# paquete SMPP y lo envia al servidor SMPP del proveedor   #
# (Unifon).                                                #
############################################################

use BelMon;
use Net::SMPP;
use IO::Handle;
use Fcntl;
use Socket;
use Carp;
use FileHandle;

sub spawn;	
pipe(READER, WRITER);
WRITER->autoflush(1);

$debug = $ENV{'DEBUG'};
$debug = 1;

if ($pid = fork)
{
	close READER;

	# Abre socket y espera mensajes del capturador
	my $port = shift || 4041;
	my $proto = getprotobyname('tcp');
	socket(SERVER, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
	setsockopt(SERVER, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
                                             or die "setsockopt: $!";
	bind(SERVER, sockaddr_in($port, INADDR_ANY)) or die "bind: $!";
	listen(SERVER,SOMAXCONN)                     or die "listen: $!";

	# A medida que va recibiendo los mensajes del programa
	# de monitoreo, los envia a traves de un pipe, al otro
	# subproceso encargado de la negociacion SMPP.
	for ( ; $paddr = accept(CLIENT,SERVER); close CLIENT)
	{
		my($port,$iaddr) = sockaddr_in($paddr);
		my $name = gethostbyaddr($iaddr,AF_INET);

		if ($debug > 0)
		{
			print "Recibido Mensaje de Programa de Monitoreo\n";
			&logentry("BelMonOut.log", "Recibido Mensaje de Programa de Monitoreo");
		}

		spawn sub
		{
			$mensaje = <STDIN>;
			print STDERR "Esto me llego stderr: $mensaje \n";
			print WRITER $mensaje;
			print "OK\n";
		}
	}
}
else
{
	die "Error al realizar fork: $!" unless defined $pid;
	close WRITER;

	$debug = $ENV{'DEBUG'};
	$debug = 1;
	if ($debug > 0)
	{
		use Data::Dumper;
		$trace = 1;
		$Net::SMPP::trace = 1;
	}

	$SIG{ALRM} = \&enviar_enquire_link_tx;
	$SIG{INT} = \&terminar;

	print "Iniciando Session SMPP\n";
	&logentry("BelMonOut.log", "Iniciando Session SMPP");

	# Establece la sesion SMPP.
	$smpp = Net::SMPP->new_transmitter($server,
			smpp_version => $version,
			system_id => $userid,
			password => $password,
			port => $port,
			)
	or &exit_with_error($debug, "No puedo establecer sesion SMPP: $!");

	# Dispara alarma para el envio del enquire_link
	alarm($periodo_enquire_link);

	sleep (5);

	# A medida que llegan los mensajes del subproceso que espera
	# la informacion del programa de monitoreo, va enviando la misma
	# por SMPP.

	while (1)
	{
		$mensaje = <READER>;
 
		if ($mensaje ne "")
		{
			alarm(0);
			if ($debug > 0)
			{
				$trace = 1;
				$Net::SMPP::trace = 1;
				print "Recibido Mensaje de Programa de Monitoreo\n";
				&logentry("BelMonOut.log", "Recibido Mensaje de Programa de Monitoreo");
			}
 
			print "Este es el mensaje que llego: KK $mensaje KK \n";
			&enviar_paquete_tx($mensaje);
			print "Sali de la subrutina que manda el paquete ... \n";
			$mensaje = "";
		}
	}
	print "Saliendo del proceso hijo \n";
}



sub spawn 
{
       	my $coderef = shift;
 
       	unless (@_ == 0 && $coderef && ref($coderef) eq 'CODE')
	{
		printf "forma de uso: spawn CODEREF";
	}
 
       	my $pid2;
	if (!defined($pid2 = fork))
	{
		printf "no puedo realizar fork: $!";
		return;
	}
	elsif ($pid2)
	{
		return; # proceso padre
	}
	# proceso hijo -- realiza el spawn

	open(STDIN,  "<&CLIENT")    or die "no puedo realizar dup sobre el cliente hacia stdin";
	open(STDOUT, ">&CLIENT")    or die "no puedo realizar dup sobre el clien
te hacia stdout";
	STDOUT->autoflush();
	exit &$coderef();              
}


