
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <x86intrin.h>

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

//------------------------------------------------------------------------------------------------------------------

//MAIN


int main() {

		printf("BUSCANDO CONTRASENA: '%s' CON LONGITUD: %d, CARACTERES POSIBLES: %d)\n",
				CONTRASENA, LONGITUD_CONTRASENA, NUM_CAR);
		printf("MEDICION CON TSC\n\n");
	


		// NUM_CAR elevado a LONGITUD_CONTRASENA

		long long total_combinaciones = (long long)pow(NUM_CAR, LONGITUD_CONTRASENA);

		printf("POSIBLES COMBINACIONES: %lld\n", total_combinaciones);

		int encontrado = 0;
		char resultado[LONGITUD_CONTRASENA + 1];
		encontrado = 0;
		resultado[0] = '\0';

		unsigned long long start = __rdtsc();

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
		unsigned long long end = __rdtsc();
		unsigned long long ciclos = end - start;

		if (encontrado) {
			printf("CONTRASENA ENCONTRADA: '%s'\n", resultado);
		} else {
			printf("NO SE ENCONTRO\n");
		}
		printf("TIEMPO (ciclos): %llu\n", ciclos);

	
		return 0;

}
