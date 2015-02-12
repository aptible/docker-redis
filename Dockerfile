FROM quay.io/aptibe/alpine

RUN apk-install redis=2.8.17-r0
ADD run-redis.sh /usr/bin/

ADD test /tmp/test
RUN bats /tmp/test

EXPOSE 6379
CMD run-redis.sh
