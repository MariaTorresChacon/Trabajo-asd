
#define _CRT_SECURE_NO_WARNINGS

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
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


//------------------------------------------------------------------------------------------------------------------


//MAIN


int main(int argc, char* argv[]) {

	int max_hilos = omp_get_max_threads();

	printf("USANDO MAXIMO DE HILOS POSIBLE: %d\n", max_hilos);
	printf("BUSCANDO CONTRASENA: '%s' CON LONGITUD: %d, CARACTERES POSIBLES: %d)\n\n",
		CONTRASENA, LONGITUD_CONTRASENA, NUM_CAR);

	long long total_combinaciones = (long long)pow(NUM_CAR, LONGITUD_CONTRASENA);

	printf("POSIBLES COMBINACIONES: %lld\n", total_combinaciones);

	int encontrado = 0; //false
	char resultado[LONGITUD_CONTRASENA + 1]; //almacena resultado (contraseña encontrada)



	double tiempo_inicio = omp_get_wtime();	//mide el tiempo desde el inicio

	omp_set_num_threads(max_hilos);
	long long i;

	#pragma omp parallel for 
	for (i = 0; i < total_combinaciones; i++) {
		char cadena[LONGITUD_CONTRASENA + 1]; 
		indice_a_cadena(i, LONGITUD_CONTRASENA, cadena);

		if (strcmp(cadena, CONTRASENA) == 0) { 
			#pragma omp critical
			if (encontrado == 0) {
				encontrado = 1;
				strcpy(resultado, cadena); 
			}
		}
	}

	double tiempo_fin = omp_get_wtime();

	if (encontrado) {
		printf("USANDO %2d HILOS, CONTRASENA ENCONTRADA: '%s', TIEMPO DE EJECUCION: %.4f s\n",
			max_hilos, resultado, tiempo_fin - tiempo_inicio);
	}
	else {
		printf("USANDO %2d HILOS, NO SE ENCONTRÓ, TIEMPO DE EJECUCION: %.4f s\n",
			max_hilos, tiempo_fin - tiempo_inicio);
	}


	return 0;

}