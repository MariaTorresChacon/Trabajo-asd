
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

#define CONTRASENA "asd123"
#define LONGITUD_CONTRASENA 6
#define CARACTERES "abcdefghijklmnopqrstuvwxyz0123456789"
#define NUM_CAR 36


//------------------------------------------------------------------------------------------------------------------


//funcion que sirve para convertir un indice numerico a una cadena, 
// para poder probar todas las posibles combinaciones de cierta longitud indicando un numero (indice del bucle for)
void indice_a_cadena(long long indice, int longitud, char *resultado){
	for (int i = longitud - 1; i >= 0; i--) {
		resultado[i] = CARACTERES[indice % NUM_CAR];
		indice= indice / NUM_CAR;
		} resultado[longitud] = '\0'; //marca el final del array
}

static long long potencia_entera(int base, int exponente) {
	long long resultado = 1;
	for (int i = 0; i < exponente; i++) {
		resultado *= base;
	}
	return resultado;
}

static double tiempo_monotonico_segundos(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + ((double)ts.tv_nsec * 1e-9);
}

//------------------------------------------------------------------------------------------------------------------

//MAIN


int main(void) {

		printf("BUSCANDO CONTRASENA: '%s' CON LONGITUD: %d, CARACTERES POSIBLES: %d)\n",
				CONTRASENA, LONGITUD_CONTRASENA, NUM_CAR);
		printf("MEDICION CON CLOCK_MONOTONIC (segundos)\n\n");
	


		// NUM_CAR elevado a LONGITUD_CONTRASENA

		long long total_combinaciones = potencia_entera(NUM_CAR, LONGITUD_CONTRASENA);

		printf("POSIBLES COMBINACIONES: %lld\n", total_combinaciones);

		int encontrado = 0;
		char resultado[LONGITUD_CONTRASENA + 1];
		encontrado = 0;
		resultado[0] = '\0';

		double start = tiempo_monotonico_segundos();

		for (long long i = 0; i < total_combinaciones; i++) {
			char cadena[LONGITUD_CONTRASENA + 1];
			indice_a_cadena(i, LONGITUD_CONTRASENA, cadena);

			if (strcmp(cadena, CONTRASENA) == 0) {
				if (encontrado == 0) {
					encontrado = 1;
					strcpy(resultado, cadena);
				}
			}
		}
		double end = tiempo_monotonico_segundos();
		double segundos = end - start;

		if (encontrado) {
			printf("CONTRASENA ENCONTRADA: '%s'\n", resultado);
		} else {
			printf("NO SE ENCONTRO\n");
		}
		printf("TIEMPO (s): %.6f\n", segundos);

	
		return 0;

}
