/************************************************\
*  Gerencia de Telecomunicaciones y Teleprocesos *
\************************************************/

#include <termios.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include "capturador.h"

#define DBUP "/root/dbup_demo"
/*
#define BAUDRATE B1200
*/

extern char *tzname[2];
long int timezone;

int hardware, flowchar[2], parser[2], pid, pid_hijo, poschar=0;
char *logfile="/var/log/capturador.log", *device="/dev/ttyS1", *hardware_control="FALSE", *baudrate="B9600", linea[MAXLINE], linea_enviada[MAXLINE];
char bandera, c, c_ant, registro, llamante[24], llamado[24], codigo[10], fecha[10], fecha_fin[10], cadena[256], pulsos[4], anio[4];
int mes, dia, hora, minuto, segundo, i, j;
long int duracion;
struct tm *tm_ptr, *tiempo_antes_ptr, *tiempo_despues_ptr;
time_t tiempo_actual, *tiempo_antes, *tiempo_despues;

void usage(char *comando)
{
	printf("\nuso: %s [OPCIONES]\n", comando);
	printf("OPCIONES:\n");
	puts("\t-l <archivo_log> (Valor por defecto: /var/log/capturador.log)");
	puts("\t-b {38400 | 19200 | 9600 | 4800 | 2400 | 1200 | 600 | 300}");
	puts("\t\t(Valor por defecto: 1200 bps)");
	puts("\t-d <device_capturado> (Valor por defecto: /dev/ttyS0)");
	puts("\t-x (Habilita control de flujo por hardware)");
	puts("\t-h Presenta este menu de ayuda\n");
}


void procesar_opciones(int argc, char *argv[])
{
	while ((c = getopt(argc, argv, "l:b:d:x:h")) != EOF)
	{
		switch (c)
		{
			case 'l':
				logfile = optarg;
				break;
			case 'b':
				baudrate = optarg;
				break;
			case 'd':
				device = optarg;
				break;
			case 'x':
				hardware_control = "TRUE";
				break;
			case 'h':
			default:
				usage(argv[0]);
				exit(EXIT_SUCCESS);
		}
	}
	argc -= optind;
	argv += optind;

	if (argc > 1)
	{
		usage(argv[0]);
		exit(EXIT_FAILURE);
	}
}

int main(int argc, char *argv[])
{
	int fd;
	FILE *logfd;
	struct termios oldtio, newtio;
	char inicio[20];

	procesar_opciones(argc, argv);

	printf ("Logfile: %s\n", logfile);
	printf ("Dispositivo: %s\n", device);

/**********************************************************************\
* Abre el modem como lectura-escritura, y no como una tty que controla *
* al proceso, de esta forma no se muere si por una linea ruidosa llega *
* una señal equivalente a CTRL-C.                                      *
\**********************************************************************/
	fd = open(device, O_RDWR | O_NOCTTY);
	if (fd <0) 
	{
		perror(device); 
		exit(EXIT_FAILURE); 
	}
 
/**********************************************************************\
* Abre archivo de log                                                  *
\**********************************************************************/
	logfd = fopen(logfile, "a");
	if (logfd <0) 
	{
		perror(logfile); 
		exit(EXIT_FAILURE); 
	}

/**********************************************************************\
* Si el archivo es una terminal, la configura, si es un archivo        *
* regular, simplemente lo lee .                                        *
\**********************************************************************/
	if (isatty(fd) == 1)
	{
/**********************************************************************\
* Guarda la configuracion previa de la terminal.                       *
\**********************************************************************/
		if (tcgetattr(fd,&oldtio) < 0)
		{
			perror("tcgetattr"); 
			exit (EXIT_FAILURE);
		}
		
 
/**********************************************************************\
* Configura la velocidad en bps, control de flujo desde el hardware, y *
* 8N1 (8 bit, sin paridad, 1 bit de stop). Tambien no se cuelga        *
* automaticamente e ignora estado del modem. Finalmente, habilita la   *
* terminal para recibir caracteres.                                    *
* newtio.c_cflag = BAUDRATE | CRTSCTS | CS8 | CLOCAL | CREAD;          *
* CRTSCTS habilita control de flujo desde hardware, que puede ir o no. *
\**********************************************************************/
		newtio.c_cflag = bps(baudrate) | CS8 | CLOCAL | CREAD;
		if (strcmp(hardware_control, "TRUE") == 0)
		{
			newtio.c_cflag |= CRTSCTS;
		}
 
/**********************************************************************\
* Ignora CR en la entrada                                              *
	newtio.c_iflag = IXON | IXOFF | IGNBRK | ISTRIP | IGNPAR;
* newtio.c_iflag = IGNPAR;                                             *
	newtio.c_iflag = IGNCR;
\**********************************************************************/
		newtio.c_iflag = 0;
 
/**********************************************************************\
* salida "raw".                                                        *
\**********************************************************************/
		newtio.c_oflag = 0;
 
/**********************************************************************\
* No hace echo de caracteres y no genera señales.                      *
\**********************************************************************/
		newtio.c_lflag = 0;
 
/**********************************************************************\
* Bloquea la lectura hasta que un caracter llega por la linea.         *
\**********************************************************************/
		newtio.c_cc[VMIN]=1;
		newtio.c_cc[VTIME]=0;

/**********************************************************************\
* Limpia la terminal y activa el seteo de la misma.                    *
\**********************************************************************/
		if (tcflush(fd, TCIFLUSH) < 0)
		{
			perror("tcflush"); 
			exit (EXIT_FAILURE);
		}
		
		if (tcsetattr(fd,TCSANOW,&newtio) < 0)
		{
			perror("tcsetattr"); 
			exit (EXIT_FAILURE);
		}
	}

	strcpy(inicio, "ATA\r\n");
	write(fd, inicio, strlen(inicio));

	/* modem */
	while (read(fd,&c,1) > 0)
	{
		/* archivo de log */
		fwrite(&c, sizeof(c), 1, logfd);
		fflush(logfd);
		printf ("%c", c);
	}

	if (isatty(fd) == 1)
	{
		tcsetattr(fd,TCSANOW,&oldtio);
	}
	close(fd);
	fclose(logfd);
	exit (0);
}
