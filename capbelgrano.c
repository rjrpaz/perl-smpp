#include <termios.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include "capturador.h"
#include <sys/socket.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

#define HOST "localhost"
int port = 4041;

int flowchar[2], parser[2], pid, pid_hijo, poschar=0, usuario_yaesta=0, cant_binary, cociente, resto, largo_destino;
char *logfile="/tmp/capturador.log", *shfile="/tmp/stop.sh", *sendfile="/export/home/cba/datafile_send.txt", *sendfile_procesado="/export/home/cba/salida_procesada.txt", *device="/dev/term/3", *hardware_control="FALSE", *baudrate="B9600", linea[MAXLINE], linea_enviada[MAXLINE], linea_procesada[MAXLINE * 2], destino[MAXLINE * 2], respuesta[MAXLINE], buf_res[MAXLINE], cant_binary_ascii[4];
char bandera = 'n', c;
char cadena[256];
int i;

void usage(char *comando)
{
	printf("\nuso: %s [OPCIONES]\n", comando);
	puts("OPCIONES:");
	puts("\t-l <archivo_log> (Valor por defecto: /var/log/capturador.log)");
	puts("\t-b {38400 | 19200 | 9600 | 4800 | 2400 | 1200 | 600 | 300}");
	puts("\t\t(Valor por defecto: 9600 bps)");
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
				exit(1);
		}
	}
}


int main(int argc, char *argv[])
{
	int fd, ref_no, ref_no_ant=100;
	FILE *logfd, *shfd, *sendfd, *sendfd_procesado;
	struct termios oldtio, newtio;
	struct hostent *server_host_name;
	struct sockaddr_in pin;
	int socket_descriptor;
	long int periodo = 2592000;
	struct stat estado;
	time_t tiempo_actual;
	char *statfile="/export/home/cba/capbelgrano";

	procesar_opciones(argc, argv);

/**********************************************************************\
* Creacion de la tuberia que envia caracteres al proceso que genera    *
* el socket                                                            *
\**********************************************************************/
	if (pipe(flowchar) == -1)
	{
		perror("pipe");
		exit (EXIT_FAILURE);
	}

	fd = open(device, O_RDWR | O_NOCTTY);
	if (fd <0) 
	{
		perror(device); 
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


/**********************************************************************\
* Creacion del proceso hijo que analiza el string, y lo envia si es    *
* una llamada saliente.                                                *
\**********************************************************************/
	if ((pid=fork()) == -1)
	{
		perror("fork");
		exit (EXIT_FAILURE);
	}
/**********************************************************************\
* Proceso hijo: este proceso se encarga de leer un caracter de la      *
* tuberia y lo va guardando en un string hasta que recibe la secuencia *
* de caracteres que denota el fin del string. Aqui analiza si es una   *
* llamada saliente, y si es el caso, y ademas el formato es el         *
* correcto, genera un nuevo proceso hijo que se encarga de generar un  *
* socket que actualice la Base de Datos.                               *
\**********************************************************************/
	else if (pid == 0) /* Proceso Hijo */
	{
		close(flowchar[1]);

		if (pipe(parser) == -1)
		{
			perror("pipe");
			exit (EXIT_FAILURE);
		}

		if ((pid_hijo=fork()) == -1)
		{
			perror("fork");
			exit (EXIT_FAILURE);
		}
		else if (pid_hijo == 0) /* proceso hijo en el hijo */
		{
			close(parser[1]);
			close(flowchar[0]);

			while ((read(parser[0],linea,MAXLINE)) > 0)
			{
				respuesta[0] = '\0';
				printf ("===\nPregunta: %s\n---", linea);

				if (bandera == 'y')
				{
					strcpy(respuesta,"OK UPLD completed");
					bandera = 'n';
				}

				if ((strncmp(linea, "atdt", 4) == 0) || (strncmp(linea, "\natdt", 5) == 0))
				{
/*
					if ((strncmp(linea, "\natdt0,0035113967190", 19)) == 0)
					{
						strcpy(respuesta,"\nOK\r\nSINTRA INMARSAT-C LES\r");
					}
					else
					{
*/
						strcpy(respuesta,"\nOK\r\nCONNECT 9600 LAPM COMPRESSED\r");
/*
					}
*/
				}
				else if ((strncmp(linea, "at", 2) == 0) || (strncmp(linea, "\nat", 3) == 0) || (strncmp(linea, "AT", 2) == 0) || (strncmp(linea, "\nAT", 3) == 0) || (strncmp(linea, "+++ath", 6) == 0) || (strncmp(linea, "\n+++ath", 7) == 0))
				{
					strcpy(respuesta,"\nOK\r");
					usuario_yaesta = 0;
					bandera = 'n';
				}
				else if (strcmp(linea, "\nRING\r") == 0)
				{
					strcpy(respuesta,"ATA\r");
				}
				else if (strcmp(linea, "\n@D\r") == 0)
				{
					strcpy(respuesta,"TERMINAL= ");
				}
				else if (strcmp(linea, "D1\r") == 0)
				{
					strcpy(respuesta,"@");
				}
/*
				else if (strcmp(linea, "C 031102030798458\r") == 0)
*/
				else if (strncmp(linea, "C 0", 3) == 0)
				{
					strcpy(respuesta,"Username: ");
				}
				else if (strncmp(linea, "belsat",6) == 0)
				{
					if (usuario_yaesta == 0)
					{
						strcpy(respuesta,"Password: ");
						usuario_yaesta = 1;
					}
					else
					{
						strcpy(respuesta,"What is your terminal type (vt100)? ");
					}
				}
				else if (strcmp(linea, "auto\r") == 0)
				{
					strcpy(respuesta,"OK+ \nOK welcome \nOpening your inbox ");
				}
				else if (strcmp(linea, "rset\r") == 0)
				{
					strcpy(respuesta,"OK RSET completed ");
				}
				else if (strncmp(linea, "addr", 4) == 0)
				{
					strcpy(respuesta,"OK ADDR completed ");
				}
				else if (strncmp(linea, "upld binary", 11) == 0)
				{
					strcpy(respuesta,"OK+ Start mail input; end with <CR><LF>.<CR><LF>");
					bandera = 'y';
				}
				else if (strcmp(linea, "send\r") == 0)
				{
					strcpy(respuesta,"OK MRN is ");
				}
				else if (strcmp(linea, "quit\r") == 0)
				{
					strcpy(respuesta,"BYE");
				}


				if (strcmp(respuesta,"") != 0)
				{
					printf("\n---\nRespuesta: %s\n===\n", respuesta);
					write (fd, respuesta, strlen(respuesta));
				}
			} /* Fin de while */
			close(parser[0]);
			exit (0);
		}
		else
		{ /* proceso padre en el hijo */
			close(parser[0]);

			while (read(flowchar[0],&c,1) > 0)
			{
				linea_enviada[poschar] = c;
				if (bandera == 'n')
				{
					if (c == CR)
					{
						linea_enviada[poschar+1] = '\0';
						if (write(parser[1], linea_enviada, MAXLINE) == -1)
						{
							perror ("write parser");
						}
						poschar = -1;

						if (strncmp(linea_enviada, "addr", 4) == 0)
						{
							i=5;
							while ((linea_enviada[i] != 64) && (i <= (strlen(linea_enviada))))
							{
								printf("Marca %c\n", linea_enviada[i]);
								destino[i-5] = linea_enviada[i];
								i++;
							}
							destino[i - 5] = 124;
							destino[i - 4] = '\0';

							if ((sendfd_procesado = fopen(sendfile_procesado, "w")) == NULL)
							{
								perror(logfile); 
								exit(EXIT_FAILURE); 
							}
							fwrite(destino, sizeof(char), strlen(destino), sendfd_procesado);
							fflush(sendfd_procesado);
							fclose(sendfd_procesado);
						}

						if (strncmp(linea_enviada, "upld binary", 11) == 0)
						{
							bandera = 'y';
							for (i=12; i<strlen(linea_enviada); i++)
							{
								cant_binary_ascii[i-12] = linea_enviada[i];
							}
							cant_binary_ascii[i-12] = '\0';
							printf ("Texto: %s \n", cant_binary_ascii);
							cant_binary = atoi(cant_binary_ascii);
							printf ("Texto en Nro.: %d \n", cant_binary);
						}
					}
				}
				else /* bandera == 'yes' */
				{
					if (poschar == (cant_binary - 1))
					{
						linea_enviada[poschar+1] = '\0';
						if (write(parser[1], linea_enviada, MAXLINE) == -1)
						{
							perror ("write parser");
						}
						poschar = -1;
						bandera = 'n';

						i = 0;
						largo_destino = strlen(destino);
						printf("Largo Destino: %d\n", largo_destino);
/*
						while (i < (cant_binary - 1))
*/
						while (i < cant_binary)
						{
							cociente = (unsigned char) (linea_enviada[i]) / 16;
							resto = (unsigned char) (linea_enviada[i]) % 16;;
							if (cociente < 10)
							{
								destino[ largo_destino + 2*i] = (cociente + 48);
							}
							else
							{
								destino[ largo_destino + 2*i] = (cociente + 55);
							}

							if (resto < 10)
							{
								destino[ largo_destino + 2*i + 1] = (resto + 48);
							}
							else
							{
								destino[ largo_destino + 2*i + 1] = (resto + 55);
							}
							printf("1: %c 2: %c Contador: %d\n", destino[ largo_destino + 2*i], destino[ largo_destino + 2*i +1], largo_destino + 2*i);
							i++;
						}
						printf("Largo Destino: %d\n", largo_destino);
						printf("Largo Destino mas 2 por i: %d\n", largo_destino + 2 * strlen(linea_enviada));
						destino[ largo_destino + 2 * cant_binary] = '\n';
						destino[ largo_destino + 2 * cant_binary + 1] = '\0';
						largo_destino = strlen(destino);
						printf("Largo linea enviada: %d\n", cant_binary);
						printf("Largo Destino: %d\n", largo_destino);
						printf("Destino: %s\n", destino);


						if ((sendfd = fopen(sendfile, "w")) == NULL)
						{
							perror(logfile); 
							exit(EXIT_FAILURE); 
						}
						fwrite(linea_enviada, sizeof(char), strlen(linea_enviada), sendfd);
						fflush(sendfd);
						fclose(sendfd);

						if ((sendfd_procesado = fopen(sendfile_procesado, "a")) == NULL)
						{
							perror(logfile); 
							exit(EXIT_FAILURE); 
						}
						fwrite(linea_procesada, sizeof(char), strlen(linea_procesada), sendfd_procesado);
						fflush(sendfd_procesado);
						fclose(sendfd_procesado);

						if ((server_host_name = gethostbyname(HOST)) == 0)
						{
							perror("Error al intentar resolver nombre del host");
						}
						bzero(&pin, sizeof(pin));
						pin.sin_family = AF_INET;
						pin.sin_addr.s_addr = htonl(INADDR_ANY);
						pin.sin_addr.s_addr = ((struct in_addr *)(server_host_name->h_addr))->s_addr;
						pin.sin_port = htons(port);
						if ((socket_descriptor = socket(AF_INET, SOCK_STREAM, 0)) == -1)
						{
							perror("Error al abrir el socket");
						}
						if (connect(socket_descriptor, (void *)&pin, sizeof(pin)) == -1)
						{
							perror("Error al conectarse al socket");
						}
						if (send(socket_descriptor, destino, sizeof(destino), 0) == -1)
						{
							perror("Error al enviar los datos");
						}
						if (recv(socket_descriptor, buf_res, sizeof(buf_res), 0) == -1)
						{
							perror("Error al recibir respuesta del server");
						}
						else
						{
							if (strcmp(buf_res, "OK\n") != 0)
							{
								perror("El server devolvio un mensaje de error: %s", buf_res);
							}
						}
						close(socket_descriptor);
					} /* Fin del if */
				}
				poschar++;
			}
			close(parser[1]);
			exit (0);
		}
		close(flowchar[0]);
		exit (0);
	}
/**********************************************************************\
* Proceso padre: este proceso es el encargado de capturar el puerto    *
* serial, escribirlo en el log, y escribirlo en la tuberia para que lo *
* reciba el proceso hijo, para que realice el analisis descripto       *
* arriba.                                                              *
\**********************************************************************/
	else
	{
		close(flowchar[0]);

/**********************************************************************\
* Abre archivo de log                                                  *
\**********************************************************************/
		if ((logfd = fopen(logfile, "a")) == NULL)
		{
			perror(logfile); 
			exit(EXIT_FAILURE); 
		}

		/* modem */
		while (read(fd,&c,1) > 0)
		{
			time(&tiempo_actual);
			stat(logfile, &estado);
			if ((tiempo_actual - estado.st_mtime) > periodo)
			{
				if ((shfd = fopen(shfile, "w")) == NULL)
				{
					perror(shfile); 
					exit(EXIT_FAILURE); 
				}
				strcpy(cadena, "#!/bin/sh\n\0");
				fwrite(&cadena, strlen(cadena), 1, shfd);
				fclose(shfd);
				
				printf ("No va a andar.\n");
				exit(0);
			}

			/* archivo de log */
			write(1, c, 1);
			fwrite(&c, sizeof(c), 1, logfd);
			fflush(logfd);

			/* tuberia */
			if (write(flowchar[1],&c,1) != 1)
			{
				perror("write error to flowchar");
			}
		}

		if (isatty(fd) == 1)
		{
			tcsetattr(fd,TCSANOW,&oldtio);
		}

		close(fd);
		close(flowchar[1]);
		fclose(logfd);
		exit (0);
	}
}
