# Trabajo-asd

## Compilar en Linux

```bash
gcc -O3 Trabajo_asd/cracker.c -o cracker_seq
gcc -O3 -fopenmp Trabajo_asd_openMP/cracker_openMP.c -o cracker_openMP
mpicc -O3 Trabajo_asd_MPI/cracker_MPI.c -o cracker_MPI
mpicc -O3 -fopenmp Trabajo_asd_openMP_MPI/cracker_openMP_MPI.c -o cracker_openMP_MPI
```

## Ejecutar en cluster (3 nodos x 2 CPU)

`hostfile.txt` define en que nodos se lanzan procesos MPI y cuantos procesos maximos por nodo (`slots`).

Ejemplo reproducible:

```bash
./run_cluster_bench.sh hostfile.txt
```

Variables opcionales:

```bash
NP_MPI=6 NP_HYBRID=3 OMP_THREADS=2 ./run_cluster_bench.sh hostfile.txt
```

Nota: en el caso hibrido el script usa `--map-by ppr:1:node` para forzar 1 proceso MPI por nodo.
