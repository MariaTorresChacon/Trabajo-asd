#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "mpi.h"

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
	}
	resultado[longitud] = '\0'; //marca el final del array
}

static long long potencia_entera(int base, int exponente) {
	long long resultado = 1;
	for (int i = 0; i < exponente; i++) {
		resultado *= base;
	}
	return resultado;
}

//------------------------------------------------------------------------------------------------------------------

//idea: cuando un proceso encuentra la contraseña (encontrado=1) todos los demas deben recivirlo a trabes de mensajes

//MAIN

int main(int argc, char* argv[]) {
	MPI_Init(&argc, &argv);

	int size, rank;
	MPI_Comm_size(MPI_COMM_WORLD, &size);
	MPI_Comm_rank(MPI_COMM_WORLD, &rank);

	if (rank == 0) {
		printf("PROCESOS MPI: %d\n", size);
		printf("BUSCANDO CONTRASENA: '%s' CON LONGITUD: %d, CARACTERES POSIBLES: %d)\n",
			CONTRASENA, LONGITUD_CONTRASENA, NUM_CAR);
		printf("MEDICION CON MPI_Wtime (segundos)\n");
	}

	long long total_combinaciones = potencia_entera(NUM_CAR, LONGITUD_CONTRASENA);

	if (rank == 0) {
		printf("POSIBLES COMBINACIONES: %lld\n\n", total_combinaciones);
	}

	int encontrado = 0;
	char resultado[LONGITUD_CONTRASENA + 1];

	int encontrado_global = 0;
	char resultado_global[LONGITUD_CONTRASENA + 1];
	resultado_global[0] = '\0';

	//dividir que proceso hace cada parte del bucle
	long long inicio = (total_combinaciones / size) * rank;
	long long final;
	if (rank == size - 1) {
		final = total_combinaciones;
	}
	else {
		final = inicio + (total_combinaciones / size);
	}

	encontrado = 0;
	resultado[0] = '\0';

	MPI_Barrier(MPI_COMM_WORLD);
	double start = MPI_Wtime();

	for (long long i = inicio; i < final; i++) {
		char cadena[LONGITUD_CONTRASENA + 1];
		indice_a_cadena(i, LONGITUD_CONTRASENA, cadena);

		if (strcmp(cadena, CONTRASENA) == 0) {
			if (encontrado == 0) {
				encontrado = 1;
				strcpy(resultado, cadena);
			}
		}
	}

	double end = MPI_Wtime();
	double tiempo_local = end - start;

	double tiempo_global = 0.0;
	MPI_Reduce(&tiempo_local, &tiempo_global, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);

	//si alguno encuentra la contraseña, encontrado=1, debe avisar a los demas
	MPI_Allreduce(&encontrado, &encontrado_global, 1, MPI_INT, MPI_MAX, MPI_COMM_WORLD);

	//si algun proceso la encontro (y se lo ha comunicado a los demas procesos)
	if (encontrado_global) {
		// el proceso que lo encontro (que no sea el 0) se lo envia al 0
		if (encontrado && rank != 0) {
			MPI_Send(resultado, LONGITUD_CONTRASENA + 1, MPI_CHAR, 0, 0, MPI_COMM_WORLD);
		}

		// El proceso 0 recive la contraseña encontrada
		if (rank == 0) {
			if (encontrado) {
				strcpy(resultado_global, resultado); // caso en el que el proceso 0 es el que la encuentra
			}
			else {
				MPI_Status status;
				MPI_Recv(resultado_global, LONGITUD_CONTRASENA + 1, MPI_CHAR,
					MPI_ANY_SOURCE, 0, MPI_COMM_WORLD, &status);
			}
			printf("CONTRASENA ENCONTRADA: '%s'\n", resultado_global);
			printf("TIEMPO MPI (s, max entre procesos): %.6f\n", tiempo_global);
		}
	}
	else if (rank == 0) {
		printf("NO SE ENCONTRO\n");
		printf("TIEMPO MPI (s, max entre procesos): %.6f\n", tiempo_global);
	}

	MPI_Finalize();
	return 0;
}
