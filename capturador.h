/************************************************\
*  Gerencia de Telecomunicaciones y Teleprocesos *
\************************************************/

#include <stdlib.h>
#include <malloc.h>

#define CR 13
#define LF 10
#define MAXLINE 4096

#define TRUE 1
#define FALSE 0

#define LOGERROR "/var/log/capturador_error.log"

typedef struct
{
	unsigned int localidad_id;
	char servicio[255];
	unsigned int prestador_id;
	char clave[2];
} localidad_reg;


void error_log (char *message, char *linea);

int bps (char *baudrate);


void spool_entry (char *entrada);
