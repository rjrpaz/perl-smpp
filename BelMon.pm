package BelMon;

############################################################
# BelMon.pm: Modulo que incluye las funciones utilizadas   #
# por los scripts de SMPP.                                 #
#                                                          #
# Revision: 25/11/2002                                     #
############################################################

require Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION %ultima_sesion);

$VERSION     = 0.01;

@ISA         = qw(Exporter);
@EXPORT      = qw($smpp $pdu $paddr $cmd $trace $version $server $port $userid $password $source_address $periodo_enquire_link $logdir $spooldir &logentry &reiniciar_timer_enquire_link &enviar_enquire_link  &enviar_enquire_link_tx &terminar &esperar_paquete &enviar_paquete_tx &estan_todos_los_paquetes &chequear_duplicidad &generar_cabecera &conversion);

%EXPORT_TAGS = ();

@EXPORT_OK   = qw();
use vars qw($smpp $pdu $paddr $cmd $trace @parametro $sig $version $server $port $userid $password $source_address $periodo_enquire_link $logdir $spooldir &logentry &reiniciar_timer_enquire_link &enviar_enquire_link  &enviar_enquire_link_tx &terminar &esperar_paquete &estan_todos_los_paquetes &chequear_duplicidad &generar_cabecera &conversion);

# Version del protocolo SMPP que se utilizara
$version = 0x34;

# Definicion del nombre o IP del SMSC, y el puerto TCP donde atiende
#$server = '01svrmsg.emocion.net.ar';
$server = '200.5.68.33';
$port = 5024;

# Definicion del nombre de usuario
$userid = "Belcarg";

# Definicion de la password
$password = "es7wdsev";

# Definicion de la direccion de SMPP asignada por el proveedor.
#$source_address = "156";
$source_address = "169";

# Tiempo (sugerido por el proveedor) que debe pasar entre los distintos
# mensajes sucesivos de SMPP. En el caso de que pase un tiempo como este
# y no se hace generado ningun mensaje SMPP, se debe generar uno del 
# tipo "enquire_link". El tiempo esta en segundos.
$periodo_enquire_link = 300;

# Directorio donde se generaran los logs de los programa, cuando estos
# se arranquen en modo debug
$logdir = "/var/log";
$spooldir = "/export/home/cba/spool";

# Esta tabla guarda el valor de la ultima sesion recibida por cada
# locomotora, para compararla con la que recibe.

# Esta tabla es utilizada para la conversion de los caracteres es hexa,
# al equivalente ascii de los mismos.
my %equivalencia = ();
$equivalencia{'0'} = 0;
$equivalencia{'1'} = 1;
$equivalencia{'2'} = 2;
$equivalencia{'3'} = 3;
$equivalencia{'4'} = 4;
$equivalencia{'5'} = 5;
$equivalencia{'6'} = 6;
$equivalencia{'7'} = 7;
$equivalencia{'8'} = 8;
$equivalencia{'9'} = 9;
$equivalencia{'a'} = 10;
$equivalencia{'b'} = 11;
$equivalencia{'c'} = 12;
$equivalencia{'d'} = 13;
$equivalencia{'e'} = 14;
$equivalencia{'f'} = 15;



# La siguiente subrutina genera una entrada de texto en el archivo de
# log que se indique
sub logentry
{
	my $logfile;
	my $mensaje;
	my $date;

	local (@parametro) = @_;
	$logfile = $parametro[0];
	$mensaje = $parametro[1];

	$date = `/bin/date +"%Y%m%d %H:%M:%S"`;
	($date) = ($date =~ /([^\n]*)/);
	open (LOGFILE, ">> ".$logdir."/".$logfile);
	print LOGFILE $date, ": ", $mensaje,"\n";
	close (LOGFILE);
}



# La siguiente subrutina reinicia el timer de la alarma que avisa cuando
# se debe mandar el paquete enquire_link
sub reiniciar_timer_enquire_link
{
	alarm(0);
	alarm($periodo_enquire_link);
}     



# La siguiente subrutina envia un mensaje de tipo enquire_link para el
# ESME en modo recepcion
sub enviar_enquire_link
{
	local($sig) = @_;

	$smpp->enquire_link()
	or logentry("BelMonIn.log", "Problemas para enviar enquire_link"); 
	alarm($periodo_enquire_link);
	&esperar_paquete();
}     



# La siguiente subrutina envia un mensaje de tipo enquire_link para el
# ESME en modo transmision
sub enviar_enquire_link_tx
{
	local($sig) = @_;

	$smpp->enquire_link()
	or logentry("BelMonOut.log", "Problemas para enviar enquire_link"); 
	alarm($periodo_enquire_link);
}     



# La siguiente subrutina muestra un mensaje de error por pantalla
# y termina el programa
sub exit_with_error
{
	my $debug;
	my $mensaje;

	local(@parametro) = @_;
	$debug = $parametro[0];
	$mensaje = $parametro[1];
	
	print $mensaje,"\n";
	if ($debug > 0)
	{
		&logentry("BelMonIn.log", $mensaje); 
	}
	exit(1);
}     



# La siguiente subrutina envia un paquete para una finalizacion
# "suave" de la sesion
sub terminar
{
	local($sig) = @_;

	$smpp->unbind()
	or logentry("BelMonIn.log", "Problemas para enviar unbind"); 
	exit(0);
}     



# La siguiente subrutina procesa los paquetes de SMPP que van llegando,
# y eventualmente genera el paquete de respuesta (si es necesario).
sub esperar_paquete
{
	my $debug;
	my $comando;
	my $filename;

	# Caracteres que identifican la combinacion que debe ser
	# evitada de enviar al equipo de transmision satelital.
	my $t1 = 0x0b;
	my $t2 = 0x90;

	my $c_ant = '';
	my $c = '';
	my $contador = 0;
	my $letra;
	my $cabecera = "";
	my $ascii = "";
	my $mensaje = "";
	my $mensaje_procesado = "";
	my @mensaje = ();
	my $nro_locomotora = "";
	my $cant_paquetes = "";
	my $nro_orden = "";
	my $nro_sesion = "";
	my $archivo_sesion = "";
	my $date = "";

#	$debug = $ENV{'DEBUG'};
	$debug = "1";

	while (1)
	{
		if ($debug > 0)
		{
			use Net::SMPP;
			use Data::Dumper;
        		$trace = 1;
        		$Net::SMPP::trace = 1;
			print "Esperando por un PDU enviado por el SMSC\n";
			&logentry("BelMonIn.log", "Esperando por un PDU enviado por el SMSC");
		}
		$pdu = $smpp->read_pdu()
		or &exit_with_error($debug, "$$: no se pudo leer PDU. Cerrando la conexion");

		$cmd = Net::SMPP::pdu_tab->{$pdu->{cmd}}{cmd};
		if ($debug > 0)
		{
			print "Recibido #$pdu->{seq} $pdu->{cmd}:".$cmd."\n";
			&logentry("BelMonIn.log", "Recibido #$pdu->{seq} $pdu->{cmd}:".$cmd);
			warn Dumper($pdu) if $trace;
		}

		alarm(0);

		if (($cmd eq "generick_nack") || ($cmd eq "bind_receiver_resp") || ($cmd eq "bind_transmitter_resp") || ($cmd eq "query_sm_resp") || ($cmd eq "submit_sm_resp") || ($cmd eq "deliver_sm_resp") || ($cmd eq "replace_sm_resp") || ($cmd eq "cancel_sm_resp") || ($cmd eq "bind_transceiver_resp") || ($cmd eq "enquire_link_resp") || ($cmd eq "submit_multi_resp") || ($cmd eq "alert_notification") || ($cmd eq "data_sm") || ($cmd eq "data_sm_resp") || ($cmd eq "bind_transceiver"))
		{
			if ($debug > 0)
			{
				print "El comando $cmd recibido, no requiere respuesta.\n";
				&logentry("BelMonIn.log", "El comando $cmd recibido, no requiere respuesta.");
			}
		}
		elsif (($cmd eq "bind_receiver") || ($cmd eq "bind_transmitter") || ($cmd eq "query_sm") || ($cmd eq "submit_sm") || ($cmd eq "replace_sm") || ($cmd eq "cancel_sm"))
		{
			if ($debug > 0)
			{
				print "No deberia recibir $cmd ya que actuo como ESME en modo recepcion.\n";
				&logentry("BelMonIn.log", "No deberia recibir $cmd ya que actuo como ESME en modo recepcion.");
			}
		}
		elsif ($cmd eq "deliver_sm")
		{
			$smpp->deliver_sm_resp(message_id=>'123456789',
			seq => $pdu->{seq});
#######################################################################
# Aqui se procesan los paquetes que se reciben. En el caso de que los #
# paquetes vengan por partes, la referencia que se utilizara, es la   #
# que sigue:                                                          #
#                                                                     #
# Byte 1 y 2): Nro. de Locomotora.                                    #
# Byte 3 y 4): Cantidad de paquetes que conforman el mensaje final.   #
# Byte 5 y 6): Nro. de orden del paquete.                             #
# Byte 7 y 8): Nro. de sesion en el caso de que se hayan enviado 2 o  #
#              mas mensajes de manera simultanea.                     #
#                                                                     #
# La parte de datos del paquete se puede extender hasta 150           #
# caracteres (75 caracteres reales), ya que existe un limite impuesto #
# por el proveedor, de 168 caracteres.                                #
#######################################################################

			print "El Mensaje recibido es: ",$pdu->{short_message},"\n";
			$ascii = $pdu->{short_message};
			$ascii =~ tr/[A-F]/[a-f]/;
			(@mensaje) = ($ascii =~ /(.{2})/g);
			$nro_locomotora = $mensaje[0];
			$cant_paquetes = $mensaje[1];
			$nro_orden = $mensaje[2];
			$nro_sesion = $mensaje[3];

			if (($cant_paquetes == 0) || ($nro_orden == 0))
			{
				print "Ni el Nro. de orden ni la cantidad de paquetes puede valer 0\n";
			}

			$nro_locomotora = sprintf("%02d", $nro_locomotora);
			$nro_sesion = sprintf("%02d", $nro_sesion);
			$nro_orden = sprintf("%02d", $nro_orden);

			# Genera ACK
			open (CONF, "< /etc/BelMon.conf");
			while (<CONF>)
			{
				chop;
				next if ($_ =~ /^#/);
				next if ($_ =~ /^\s*$/);
				@valores = split /,/, $_;
				if ($valores[0] eq $nro_locomotora)
				{
					$comsat_address = $valores[2];
					last;
				}
			}

			$comando = "/export/home/cba/client_out.pl \"".$comsat_address."||".$nro_locomotora."00".$nro_orden.$nro_sesion."\"";
			system($comando);

#			$nro_locomotora = &conversion($nro_locomotora);
#			$cant_paquetes = &conversion($cant_paquetes);
#			$nro_orden = &conversion($nro_orden);
#			$nro_sesion = &conversion($nro_sesion);

			print "NRO. LOCOMOTORA: $nro_locomotora \n";
			$mensaje_procesado = "";
			for ($i = 4; $i <= $#mensaje; $i++)
			{
				$letra = &conversion($mensaje[$i]);
				$mensaje_procesado = $mensaje_procesado.pack("C",$letra);
			}
			print "El Mensaje procesado es: ",$mensaje_procesado,"\n";

			$filename = $spooldir."/datafile.txt";
			open (FILE, ">".$filename);
			print FILE $mensaje_procesado;
			close(FILE);

			# Lo envia al programa de monitoreo
			if ((&chequear_duplicidad($nro_locomotora, $nro_sesion)) eq "No")
			{
				$filename = $nro_locomotora."_".$nro_sesion."_".$nro_orden;
				open (FILE, ">".$spooldir."/".$filename);
				if ($nro_orden == 1)
				{
					$cabecera = &generar_cabecera();
					print FILE $cabecera;
				}
				@mensaje = ();
				@mensaje = unpack('C*', $mensaje_procesado);

				$contador = 0;
				$letra = "";
				print "Eliminacion de los caracteres que sobran: \n";
				foreach $mensaje (@mensaje)
				{
					$c_ant = $c;
					$c = $mensaje;

					if ($contador > 0)
					{
						# Elimina la combinacion indeseada de caracteres
						if (($c_ant == 0x1b) && (($c == 0x91) || ($c == 0x93) || ($c == 0x98) || ($c == 0x9b)))
						{
							$c = ($c_ant & 0xf0) | ($c & 0x0f);
						}
						else
						{
							$letra = $letra.pack("C",$c_ant);
						}
					}
					$contador++;
				}
				$letra = $letra.pack("C",$c);
				print FILE $letra;
				close (FILE);
			}

			if (((&estan_todos_los_paquetes($nro_locomotora, $nro_sesion, $cant_paquetes)) eq "Si") && ((&chequear_duplicidad($nro_locomotora, $nro_sesion)) eq "No"))
			{
				$date = `/usr/bin/date +%y%m%d%H%M%S`;
				($date) = ($date =~ /([^\n]*)/);
				$comando = "cat ".$spooldir."/".$nro_locomotora."_".$nro_sesion."_?? > ".$spooldir."/".$date.".".$filename;
				system($comando);

				$comando = "cat ".$spooldir."/".$nro_locomotora."_".$nro_sesion."_?? > ".$spooldir."/".$date.".".$filename.".in";
				system($comando);

				$comando = "rm ".$spooldir."/".$nro_locomotora."_".$nro_sesion."_??";
				system($comando);

				$comando = "/export/home/cba/enviar_kermit.pl ".$spooldir."/".$date.".".$filename.".in &";
				system($comando);

				$archivo_sesion = $spooldir."/".$nro_locomotora.".sesion_in";
				open (SESION, "> ".$archivo_sesion);
				print SESION $nro_sesion;
				close (SESION);
			}
			&reiniciar_timer_enquire_link();
		}
		elsif ($cmd eq "unbind")
		{
			$smpp->unbind_resp(seq => $pdu->{seq});
			print "$$ Recibido pedido de desconexion por parte del SMSC. Desconectando ...\n";
			&logentry("BelMonIn.log", "$$ Recibido pedido de desconexion por parte del SMSC. Desconectando ...");
			exit;
		}
		elsif ($cmd eq "unbind_resp")
		{
			print "$$ Aceptado pedido de desconexion por parte del SMSC.\n";
			&logentry("BelMonIn.log", "$$ Aceptado pedido de desconexion por parte del SMSC.");
			exit;
		}
		elsif ($cmd eq "outbind")
		{
			$smpp->set_version($version);
			$smpp->bind_receiver(system_id => $userid,
			password => $password);
			alarm($periodo_enquire_link);
		}
		elsif ($cmd eq "enquire_link")
		{
			$smpp->enquire_link_resp(seq => $pdu->{seq});
			alarm($periodo_enquire_link);
		}
		elsif ($cmd eq "submit_multi")
		{
			$smpp->submit_multi_resp(message_id=>'123456789',
			seq => $pdu->{seq} );
			alarm($periodo_enquire_link);
		}
		else
		{
			if ($debug > 0)
			{
				print "No se como responder a $pdu->{cmd}.\n";
				&logentry("BelMonIn.log", "No se como responder a $pdu->{cmd}.");
			}
		}
	}
}



#######################################################################
# Aqui se procesan los paquetes que se enviaran por SMPP en el caso   #
# de que el ESME haya arrancado en modo transmision. En el caso de    #
# que los paquetes se envian por partes, la referencia que se         #
# utilizara, es la que sigue:                                         #
#                                                                     #
# Byte 1 y 2): Nro. de Locomotora.                                    #
# Byte 3 y 4): Cantidad de paquetes que conforman el mensaje final.   #
# Byte 5 y 6): Nro. de orden del paquete.                             #
# Byte 7 y 8): Nro. de sesion en el caso de que se hayan enviado 2 o  #
#              mas mensajes de manera simultanea.                     #
#######################################################################
sub enviar_paquete_tx
{
	my $mensaje;
	my @mensaje = ();
	my $nro_locomotora;
	my $nro_sesion;
	my $mensaje_procesado;
	my $mensaje_enviado;
	my $cantidad_paquetes;
	my $nro_orden;
	my $letra;
	my $resp;

	local (@parametro) = @_;

	my $cabecera = "";
	($nro_locomotora, $mensaje_procesado, $cabecera) = split /\|/, $parametro[0];
	print "El Nro. de Locomotora es: ",$nro_locomotora,"\n";

        # Obtiene datos de las locomotoras desde el archivo
        # de configuracion.
	open (CONF, "< /etc/BelMon.conf");
	while (<CONF>)
	{
		chop;
		next if ($_ =~ /^#/);
		next if ($_ =~ /^\s*$/);
		@valores = split /,/, $_;
		if ($valores[2] eq $nro_locomotora)
		{
			$nro_locomotora = $valores[0];
			$telefono = $valores[3];
			last;
		}
	}
	close(CONF);

	print "CANT. VALORES: ",$#valores,"\n";
	print "NUESTRO Nro. de Locomotora es: ",$nro_locomotora,"\n";
	print "NUESTRO telefono es: ",$telefono,"\n";
	print "El Mensaje procesado es: ",$mensaje_procesado,"\n";

	if ($nro_locomotora ne "")
	{
		# Obtiene el numero de sesion para nuestra cabecera. Este
		# numero lo incrementa en uno y lo guarda.
		$archivo_sesion = $spooldir."/".$nro_locomotora.".sesion";
		if (-e $archivo_sesion)
		{
			open (SESION, "< ".$archivo_sesion);
			$nro_sesion = <SESION>;
			close (SESION);
		}
		else
		{
			$nro_sesion = 0;
		}
		$nro_sesion++;
		if ($nro_sesion == 100)
		{
			$nro_sesion = 0
		}
		open (SESION, "> ".$archivo_sesion);
		print SESION $nro_sesion;
		close (SESION);

		if (length ($mensaje_procesado) > 148)
		{
			$cantidad_paquetes = int (length ($mensaje_procesado) / 148);
			if (length ($mensaje_procesado) % 148)
			{
				$cantidad_paquetes++;
			}
		}
		else
		{
			$cantidad_paquetes = 1;
		}

		print "Cantidad de paquetes: ",$cantidad_paquetes,"\n";
		$nro_orden = 1;

		while ($nro_orden <= $cantidad_paquetes)
		{
			$mensaje = substr ($mensaje_procesado, 0, 148, "");
			print "Nro. de Orden del paquete: ",$nro_orden,"\n";

			if ($cabecera eq "")
			{
				print "Cabecera Armada en el proceso \n";
				$mensaje_enviado = sprintf("%02d", $nro_locomotora).sprintf("%02d", $cantidad_paquetes).sprintf("%02d", $nro_orden).sprintf("%02d", $nro_sesion).$mensaje;
			}
			else
			{
				print "Cabecera sugerida por el cliente \n";
				$mensaje_enviado = $cabecera.$mensaje;
			}
			$resp = $smpp->submit_sm(
			source_addr => $source_address,
			destination_addr => $telefono,
			short_message=>$mensaje_enviado,
			) or die;

			$nro_orden++;
			sleep (1);
		}

		&reiniciar_timer_enquire_link();
	}
}



# La siguiente subrutina cuenta la cantidad de partes que hay de un
# paquete que sera enviado, y devuelve un "Si" si estan todos los paquetes
# necesarios.
sub estan_todos_los_paquetes
{
	my $nro_locomotora;
	my $nro_sesion;
	my $cant_paquetes;
	my $archivo;
	my $contador = 1;

	local (@parametro) = @_;
	$nro_locomotora = $parametro[0];
	$nro_sesion = $parametro[1];
	$cant_paquetes = $parametro[2];

	print "CANTIDAD DE PAQUETES: $cant_paquetes \n";

	while ($contador <= $cant_paquetes)
	{
		$contador = sprintf("%02d", $contador);
		$archivo = $spooldir."/".$nro_locomotora."_".$nro_sesion."_".$contador;
		if (!(-e $archivo))
		{
			return("No");
		}
		$contador++;
	}
	return("Si");
}



# La siguiente subrutina chequea que no se mande dos veces el mismo paquete.
# Devuelve un "No" si el nro. de sesion del paquete actual y del anterior
# no son la misma.
sub chequear_duplicidad
{
	my $archivo;
	my $nro_sesion_arch;
	my $contador = 1;

	local (@parametro) = @_;
	my $nro_locomotora = sprintf("%02d", $parametro[0]);
	my $nro_sesion = sprintf("%02d", $parametro[1]);

	$archivo = $spooldir."/".$nro_locomotora.".sesion_in";
	if (!(-e $archivo))
	{
		return("No");
	}

	open (SESION, "<".$archivo);
	$nro_sesion_arch = <SESION>;
	close (SESION);

	if ($nro_sesion eq $nro_sesion_arch)
	{
		print "Nro de sesion es el mismo\n";
		return("Si");
	}
	else
	{
		print "Distinto Nro de sesion\n";
		return("No");
	}
}



# La siguiente subrutina genera la cabecera del paquete que sera enviado
# via kermit al programa de monitoreo. 
sub generar_cabecera
{
	my $respuesta;

	$respuesta = "USA COMSAT AORE 497220057 02-11-04 19:33 104510\r\nSTX:\r\n";
	return $respuesta;
}



# La siguiente subrutina convierte el valor en hexagesimal de los
# caracteres a enviar, a su valor decimal.
sub conversion
{
	my $resultado;

	local (@parametro) = @_;
	($a, $b) = ($parametro[0] =~ /(.)/g);

	$resultado = 16 * $equivalencia{$a} + $equivalencia{$b};
	return $resultado;
}



# La siguiente subrutina convierte el valor en hexagesimal de los
# caracteres a enviar, a la version en ascii de los mismos.
sub conversion_a_hexa
{
	my $caracter;
	my $resultado;

	local (@parametro) = @_;
	$caracter = $parametro[0];

	$caracter = sprintf("%02x", $caracter);
	$resultado = sprintf("%s", $caracter);

	return $resultado;
}



END {};


1;
