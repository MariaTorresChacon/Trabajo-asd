FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    openmpi-bin \
    libopenmpi-dev \
    openssh-server \
    openssh-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /root/.ssh
RUN ssh-keygen -A
RUN ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" \
    && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys \
    && chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa \
    && chmod 700 /root/.ssh
RUN printf '\nPermitRootLogin yes\nPasswordAuthentication no\nPubkeyAuthentication yes\nUsePAM no\n' >> /etc/ssh/sshd_config
RUN printf 'Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile=/dev/null\n' > /root/.ssh/config \
    && chmod 600 /root/.ssh/config

ENV OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    OMP_NUM_THREADS=2

WORKDIR /workspace
COPY . /workspace

RUN mpicc -O2 -fopenmp Trabajo_asd_openMP_MPI/cracker_openMP_MPI.c -lm -o /usr/local/bin/cracker_openMP_MPI

COPY start-sshd.sh /usr/local/bin/start-sshd.sh
RUN chmod +x /usr/local/bin/start-sshd.sh

ENTRYPOINT ["/usr/local/bin/start-sshd.sh"]
CMD ["sleep", "infinity"]
