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
#include <math.h>
#include "capturador.h"


void error_log (char *message, char *linea)
{
	FILE *errorfd;
	/**************************************\
	* Abre archivo de log para los errores *
	\**************************************/

	errorfd = fopen(LOGERROR, "a");
	if (errorfd <0) 
	{
		perror(LOGERROR); 
	}

	setvbuf(errorfd, message, _IONBF, 0);
	fwrite(message, strlen(message), 1, errorfd);
	fwrite(" en la linea: ", 14, 1, errorfd);
	fwrite(linea, strlen(linea), 1, errorfd);
	fwrite("\n", 1, 1, errorfd);
	fflush(errorfd);
	fclose (errorfd);
}


int bps (char *baudrate)
{
	if (strcmp(baudrate, "38400") == 0) return B38400;
	else if (strcmp(baudrate, "19200") == 0) return B19200;
	else if (strcmp(baudrate, "9600") == 0) return B9600;
	else if (strcmp(baudrate, "4800") == 0) return B4800;
	else if (strcmp(baudrate, "2400") == 0) return B2400;
	else if (strcmp(baudrate, "1200") == 0) return B1200;
	else if (strcmp(baudrate, "600") == 0) return B600;
	else if (strcmp(baudrate, "300") == 0) return B300;
	else
	{
		return B1200;
	}
}


void spool_entry(char *entrada)
{
	time_t tiempo_actual;
	FILE *queuefd;
	char queue[256];

	(void) time(&tiempo_actual);
	sprintf(queue, "/var/spool/capturador/%ld", tiempo_actual);
	queuefd = fopen (queue, "a");
	if (queuefd < 0)
	{
		perror("Error al intentar abrir archivo en directorio spool");
		exit (EXIT_FAILURE);
	}
	setvbuf (queuefd, NULL, _IOLBF, 1024);
	fwrite (entrada, strlen(entrada), 1, queuefd);
	fflush (queuefd);
	fclose (queuefd);
}

