
#define _CRT_SECURE_NO_WARNINGS

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

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

		printf("BUSCANDO CONTRASENA: '%s' CON LONGITUD: %d, CARACTERES POSIBLES: %d)\n\n",
				CONTRASENA, LONGITUD_CONTRASENA, NUM_CAR);
	


		// NUM_CAR elevado a LONGITUD_CONTRASENA

		long long total_combinaciones = (long long)pow(NUM_CAR, LONGITUD_CONTRASENA);

		printf("POSIBLES COMBINACIONES: %lld\n", total_combinaciones);

		int encontrado = 0; //false
		char resultado[LONGITUD_CONTRASENA + 1]; //almacena resultado (contraseña encontrada)


		long long i;

		for (i = 0; i < total_combinaciones; i++) {
			char cadena[LONGITUD_CONTRASENA + 1]; //almacena la posible combinacion
			indice_a_cadena(i, LONGITUD_CONTRASENA, cadena); //genera una posible combinacion

			if (strcmp(cadena, CONTRASENA) == 0) { //comparar que cadena es igual a la contraseña
				//anotacion: usar strcmp por que == solo comparan direcciones de memoria, no el contenido

				if (encontrado == 0) {
					encontrado = 1;
					strcpy(resultado, cadena); //copiamos la combinacion en el array resultado
				}
			}
		}

		if (encontrado) {
			printf("CONTRASENA ENCONTRADA: '%s', TIEMPO DE EJECUCION: s\n",
				resultado);
		}
		else {
			printf("NO SE ENCONTRÓ, TIEMPO DE EJECUCION: s\n");
		}

	
		return 0;

}