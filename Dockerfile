# Stage 1 build
FROM alpine:3.18.5

ENV ENGINE_BRANCH=5.8.0
ENV ENGINE_REPO=https://github.com/minetest/minetest

ENV IRRLICHT_BRANCH=1.9.0mt13
ENV IRRLICHT_REPO=https://github.com/minetest/irrlicht

# RelWithDebInfo
# Release
# Debug
ENV ENGINE_BUILD_TYPE=RelWithDebInfo

RUN apk add --no-cache build-base irrlicht-dev cmake bzip2-dev libpng-dev jpeg-dev \
	sqlite-dev curl-dev zlib-dev gmp-dev jsoncpp-dev luajit-dev \
	git postgresql-dev zstd-dev

RUN mkdir /git

# git setup
RUN git config --global user.email "you@example.com" && \
	git config --global user.name "somename"

# prometheus cpp
RUN cd /git && git clone --depth 1 https://github.com/jupp0r/prometheus-cpp.git -b v1.1.0 && \
  cd prometheus-cpp && \
  git submodule init && \
  git submodule update && \
  cmake . && make -j4 && make install

# spatialindex
RUN cd /git && git clone --depth 1 https://github.com/libspatialindex/libspatialindex -b 1.9.3 && \
	cd libspatialindex && \
	cmake . && make -j4 && make install

# irrlicht
RUN cd /git && git clone --depth=1 ${IRRLICHT_REPO} irrlicht -b ${IRRLICHT_BRANCH} && \
	cp -r irrlicht/include /usr/include/irrlichtmt

# download minetest engine
RUN cd /git && git clone ${ENGINE_REPO} minetest && \
	cd minetest && \
	git checkout ${ENGINE_BRANCH}

# apply patches
COPY patches/* /git/minetest/patches/
COPY patch-engine.sh /git/minetest/patch-engine.sh
RUN cd /git/minetest/ && ./patch-engine.sh

# compile engine
RUN cd /git/minetest && cmake . \
	-DCMAKE_INSTALL_PREFIX=/usr/local\
	-DCMAKE_BUILD_TYPE=${ENGINE_BUILD_TYPE} \
	-DRUN_IN_PLACE=FALSE\
	-DBUILD_SERVER=TRUE\
	-DBUILD_CLIENT=FALSE\
	-DENABLE_SPATIAL=TRUE\
	-DENABLE_LUAJIT=TRUE\
	-DENABLE_CURSES=TRUE\
	-DENABLE_POSTGRESQL=TRUE\
	-DENABLE_SYSTEM_GMP=TRUE \
	-DENABLE_SYSTEM_JSONCPP=TRUE \
	-DENABLE_PROMETHEUS=TRUE \
	-DVERSION_EXTRA=docker &&\
	make -j4 &&\
	make install

# Stage 2 package
FROM alpine:3.18.5

RUN apk add --no-cache bzip2 \
	sqlite-libs curl zlib gmp jsoncpp luajit \
	postgresql-libs zstd-libs

RUN echo "http://dl-cdn.alpinelinux.org/alpine/v3.18/community" > /etc/apk/repositories
RUN apk add --no-cache luarocks
RUN luarocks install busted

RUN adduser -D minetest --uid 30000 -h /var/lib/minetest && \
	chown -R minetest:minetest /var/lib/minetest

WORKDIR /var/lib/minetest

COPY --from=0 /usr/local/lib/libspatialindex* /usr/local/lib/
COPY --from=0 /usr/local/share/minetest /usr/local/share/minetest
COPY --from=0 /usr/local/bin/minetestserver /usr/local/bin/minetestserver

USER minetest:minetest

EXPOSE 30000/udp 30000/tcp
VOLUME /var/lib/minetest/ /etc/minetest/

ENTRYPOINT ["/usr/local/bin/minetestserver"]
CMD ["--config", "/etc/minetest/minetest.conf"]