TARGET =	capturador.o \
			capdemo \
			capbelgrano \
			emu_nec

RM = /bin/rm -f

all: $(TARGET)

.c.o:
	$(CC) -c $<

capdemo: capdemo.o capturador.o
	$(CC) -o capdemo $(CFLAGS) capturador.o capdemo.o
capbelgrano: capbelgrano.o capturador.o
	$(CC) -o capbelgrano $(CFLAGS) capturador.o capbelgrano.o
emu_nec: emu_nec.o capturador.o
	$(CC) -o emu_nec $(CFLAGS) capturador.o emu_nec.o

clean: 
	$(RM) $(TARGET) *.o

