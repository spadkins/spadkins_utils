
all: mysqldumpf
app_options.o: app_options.c app_options.h
mysqldumpf.o: mysqldumpf.c app_options.h
mysqldumpf: app_options.o mysqldumpf.o

clean:
	rm -f *.o

