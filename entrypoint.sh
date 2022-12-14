#!/bin/bash

mountpoint="/var/lib/registry"
checkfile="${mountpoint}/exist"

mkdir -p "${mountpoint}"
mkdir -p /var/log/
mkdir -p /etc/us3fs/

cat <<EOF >/etc/us3fs/us3fs.conf
bucket: ${BUCKET}
access_key: ${ACCESS_KEY}
secret_key: ${SECRET_KEY}
endpoint: ${ENDPOINT}
EOF

modprobe fuse
/bin/us3fs -f --passwd=/etc/us3fs/us3fs.conf --keep_pagecache "${BUCKET}" "${mountpoint}" ${US3FS_OPTS} &

for i in {1..10}; do
  if [ "$(df | grep -o ${mountpoint})" == "${mountpoint}" ]; then
    echo "mount success"
    break
  fi
  echo "wait the bucket mounting"
  sleep 1
done

if [ "$(df | grep -o ${mountpoint})" != "${mountpoint}" ]; then
  echo "mount failed"
  exit 1
fi

if [ ! -f "${checkfile}" ]; then
  echo "${BUCKET}" >"${checkfile}"
else
  if [ "$(cat "${checkfile}")" != "${BUCKET}" ]; then
    echo "The bucket has been changed, please remove the old one and mount the new one."
    echo "In ${checkfile} is ${BUCKET}, the old bucket is $(cat "${checkfile}")"
    exit 1
  fi
fi

mkdir -p /etc/docker/registry/

function registry_mirror_config() {
  cat <<EOF
version: 0.1
log:
  accesslog:
    disabled: true
storage:
  filesystem:
    rootdirectory: ${mountpoint}
  maintenance:
    readonly:
      enabled: ${MIRROR_READ_ONLY:-false}
  delete:
    enabled: ${MIRROR_DELETE:-false}
http:
  addr: ${MIRROR_PORT:-0.0.0.0:5000}
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: false

validation:
  disabled: true

compatibility:
  schema1:
    enabled: true

EOF

  if [[ "${MIRROR_REDIRECT}" != "" ]]; then
    cat <<EOF
middleware:
  storage:
    - name: redirect
      options:
        baseurl: ${MIRROR_REDIRECT}
EOF
  fi

  if [[ "${MIRROR_REMOTE_URL}" != "" ]]; then
    cat <<EOF
proxy:
  remoteurl: ${MIRROR_REMOTE_URL}
EOF
  fi
}

function registry_sync_config() {
  cat <<EOF
version: 0.1
log:
  accesslog:
    disabled: true
storage:
  filesystem:
    rootdirectory: ${mountpoint}
  maintenance:
    readonly:
      enabled: ${SYNC_READ_ONLY:-false}
  delete:
    enabled: ${SYNC_DELETE:-false}
http:
  addr: ${SYNC_PORT:-0.0.0.0:80}
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: false

validation:
  disabled: true

compatibility:
  schema1:
    enabled: true
EOF
}

registry_mirror_config >/etc/docker/registry/config-mirror.yml

registry serve /etc/docker/registry/config-mirror.yml &

registry_sync_config >/etc/docker/registry/config-sync.yml

registry serve /etc/docker/registry/config-sync.yml &

echo "Registry started"
while true; do
  sleep 5
  if [ ! -f "${checkfile}" ]; then
    exit 1
  fi
done
