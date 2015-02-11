# ![](https://gravatar.com/avatar/11d3bc4c3163e3d238d558d5c9d98efe?s=64) aptible/redis

[![Docker Repository on Quay.io](https://quay.io/repository/aptible/redis/status)](https://quay.io/repository/aptible/redis)

Redis on Docker

## Installation and Usage

    docker pull quay.io/aptible/redis
    docker run quay.io/aptible/redis

### Specifying configuration at runtime

The image respects some environment variables passed in:

* `REDIS_PASSWORD`
* `REDIS_MAX_MEMORY` (default `100mb`): the redis server runs in [LRU mode](http://redis.io/topics/lru-cache). This variable controls the memory cap.

Example:

    docker run -dP -e REDIS_PASSWORD=asdf -e REDIS_MAX_MEMORY=20mb quay.io/aptible/redis

## Available Tags

* `latest`: Currently Redis 2.8.17

## Tests

Tests are run as part of the `Dockerfile` build. To execute them separately within a container, run:

    bats test

## Deployment

To push the Docker image to Quay, run the following command:

    make release

## Copyright and License

MIT License, see [LICENSE](LICENSE.md) for details.

Copyright (c) 2014-2015 [Aptible](https://www.aptible.com) and contributors.

[<img src="https://s.gravatar.com/avatar/f7790b867ae619ae0496460aa28c5861?s=60" style="border-radius: 50%;" alt="@fancyremarker" />](https://github.com/fancyremarker)
