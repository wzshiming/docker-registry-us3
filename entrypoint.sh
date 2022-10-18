#!/bin/bash

mountpoint="/var/lib/registry"
checkfile="${mountpoint}/exist"

mkdir -p "${mountpoint}"
mkdir -p /var/log/
mkdir -p /etc/us3fs/

cat << EOF >/etc/us3fs/us3fs.conf
bucket: ${BUCKET}
access_key: ${ACCESS_KEY}
secret_key: ${SECRET_KEY}
endpoint: ${ENDPOINT}
EOF

modprobe fuse
/bin/us3fs -f --passwd=/etc/us3fs/us3fs.conf --keep_pagecache "${BUCKET}" "${mountpoint}" &

for i in {1..10} ;do
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
    echo "${BUCKET}" > "${checkfile}"
else
    if [ "$(cat "${checkfile}")" != "${BUCKET}" ]; then
        echo "The bucket has been changed, please remove the old one and mount the new one."
        echo "In ${checkfile} is ${BUCKET}, the old bucket is $(cat "${checkfile}")"
        exit 1
    fi
fi

mkdir -p /etc/docker/registry/
cat <<EOF > /etc/docker/registry/config.yml
version: 0.1
log:
  accesslog:
    disabled: true
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: ${mountpoint}
  maintenance:
    uploadpurging:
      enabled: false
    readonly:
      enabled: false
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
middleware:
  storage:
    - name: redirect
      options:
        baseurl: ${REDIRECT}
health:
  storagedriver:
    enabled: false

validation:
  disabled: true

proxy:
  remoteurl: ${REMOTE_URL}

EOF
registry serve /etc/docker/registry/config.yml &

echo "Registry started"
while true; do
    sleep 5
    if [ ! -f "${checkfile}" ]; then
        exit 1
    fi
done
