FROM gliderlabs/alpine:3.1

# TODO: better way to install bats?
RUN apk-install bash git \
	&& git clone https://github.com/sstephenson/bats /tmp/bats \
	&& cd /tmp/bats \
	&& ./install.sh /usr/local \
	&& rm -rf /tmp/bats \
	&& apk del git

RUN apk-install redis=2.8.17-r0
ADD run-redis.sh /usr/bin/

ADD test /tmp/test
RUN bats /tmp/test

EXPOSE 6379
CMD run-redis.sh
