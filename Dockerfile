FROM docker.io/library/centos:7

# us3fs made an incompatible change and we fallback to use the old version of binary 👎
# RUN curl -o /bin/us3fs https://ufile-release.cn-bj.ufileos.com/us3fs/us3fs && chmod +x /bin/us3fs
COPY /bin/us3fs /bin/us3fs

RUN yum install -y fuse

COPY --from=ghcr.io/wzshiming/distribution/registry:v2.8.1-fork.0 /bin/registry /bin/registry

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]
