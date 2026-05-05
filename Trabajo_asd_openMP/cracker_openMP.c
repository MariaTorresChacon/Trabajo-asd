
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
#include <omp.h>

#define CONTRASENA "asd123"
#define LONGITUD_CONTRASENA 6
#define CARACTERES "abcdefghijklmnopqrstuvwxyz0123456789"
#define NUM_CAR 36


//------------------------------------------------------------------------------------------------------------------


//funcion que sirve para convertir un indice numerico a una cadena, 
// para poder probar todas las posibles combinaciones de cierta longitud indicando un numero (indice del bucle for)
void indice_a_cadena(long long indice, int longitud, char* resultado) {
	for (int i = longitud - 1; i >= 0; i--) {
		resultado[i] = CARACTERES[indice % NUM_CAR];
		indice = indice / NUM_CAR;
	} resultado[longitud] = '\0'; //marca el final del array
}	


static long long potencia_entera(int base, int exponente) {
	long long resultado = 1;
	for (int i = 0; i < exponente; i++) {
		resultado *= base;
	}
	return resultado;
}

//------------------------------------------------------------------------------------------------------------------


//MAIN


int main() {
	
	 int hilos = omp_get_max_threads();
		

	omp_set_num_threads(hilos);
	printf("USANDO HILOS OpenMP: %d\n", hilos);
	printf("BUSCANDO CONTRASENA: '%s' CON LONGITUD: %d, CARACTERES POSIBLES: %d)\n\n",
		CONTRASENA, LONGITUD_CONTRASENA, NUM_CAR);

	long long total_combinaciones = potencia_entera(NUM_CAR, LONGITUD_CONTRASENA);

	printf("POSIBLES COMBINACIONES: %lld\n", total_combinaciones);

	printf("MEDICION CON omp_get_wtime (segundos)\n");

	int encontrado = 0;
	char resultado[LONGITUD_CONTRASENA + 1];
	double segundos = 0.0;


	double start = omp_get_wtime();

	#pragma omp parallel for 
	for (long long i = 0; i < total_combinaciones; i++) {
		char cadena[LONGITUD_CONTRASENA + 1];
		indice_a_cadena(i, LONGITUD_CONTRASENA, cadena);

		if (strcmp(cadena, CONTRASENA) == 0) {
			#pragma omp critical
			{
				if (encontrado == 0) {
					encontrado = 1;
					strcpy(resultado, cadena);
				}
			}
		}
	}

	double end = omp_get_wtime();
	segundos = end - start;

	if (encontrado) {
		printf("USANDO %2d HILOS, CONTRASENA ENCONTRADA: '%s'\n", hilos, resultado);
	}
	else {
		printf("USANDO %2d HILOS, NO SE ENCONTRO\n", hilos);
	}
	printf("TIEMPO (s): %.6f\n", segundos);


	return 0;

}
