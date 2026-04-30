#!/usr/bin/env bash
set -euo pipefail

mkdir -p /var/run/sshd

if [ ! -f /root/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
  cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa
  chmod 700 /root/.ssh
fi

if [ ! -f /root/.ssh/config ]; then
  cat > /root/.ssh/config <<'EOF'
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
  chmod 600 /root/.ssh/config
fi

/usr/sbin/sshd
exec "$@"
