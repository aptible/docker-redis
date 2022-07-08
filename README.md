# ![](https://gravatar.com/avatar/11d3bc4c3163e3d238d558d5c9d98efe?s=64) aptible/redis

[![Docker Repository on Quay.io](https://quay.io/repository/aptible/redis/status)](https://quay.io/repository/aptible/redis)
[![Build Status](https://travis-ci.org/aptible/docker-redis.svg?branch=master)](https://travis-ci.org/aptible/docker-redis)

Redis on Docker

## Installation and Usage

    docker pull quay.io/aptible/redis

This is an image conforming to the [Aptible database specification](https://support.aptible.com/topics/paas/deploy-custom-database/). To run a server for development purposes, execute

    docker create --name data quay.io/aptible/redis
    docker run --volumes-from data -e PASSPHRASE=pass quay.io/aptible/redis --initialize
    docker run --volumes-from data -P quay.io/aptible/redis

The first command sets up a data container named `data` which will hold the configuration and data for the database. The second command creates a Redis instance with the passphrase of your choice. The third command starts the database server.

## Configuration

In addition to the standard Aptible database ENV variables, which may be specified when invoking this image with `--initialize`, the following environment variables may be set at runtime (i.e., launching a container from the image without arguments):

| Variable | Description |
| -------- | ----------- |
| `MAX_MEMORY` | Memory limit for Redis server (e.g., 100mb) |

## Available Tags

* `latest`: Currently Redis 7.0-aof
* `7.0`: Redis 7.0.2 w/ RDB persistence
* `7.0-aof`: AOF+RDB persistence
* `7.0-nordb`: no persistennce
* `6.0`: Redis 6.0.16 w/ RDB persistence
* `6.0-aof`: AOF+RDB persistence
* `6.0-nordb`: no persistennce
* `5.0`: Redis 5.0.14 w/ RDB persistence [EOL](https://redis.io/topics/releases)
* `5.0-aof`: AOF+RDB persistence
* `5.0-nordb`: no persistennce
* `4.0`: Redis 4.0.14 w/ RDB persistence [EOL](https://redis.io/topics/releases)
* `4.0-aof`: AOF+RDB persistence
* `4.0-nordb`: no persistennce
* `3.2`: Redis 3.2.13 w/ RDB persistence [EOL](https://redis.io/topics/releases)
* `3.2-aof`: AOF+RDB persistence
* `3.2-nordb`: no persistennce
* `3.0`: Redis 3.0.7 w/ RDB persistence [EOL](https://redis.io/topics/releases)
* `3.0-aof`: AOF+RDB persistence
* `3.0-nordb`: no persistennce
* `2.8`: Redis 2.8.24 w/ RDB persistence [EOL](https://redis.io/topics/releases)
* `2.8-aof`: AOF+RDB persistence
* `2.8-nordb`: no persistennce

## Tests

Tests are run as part of the `Dockerfile` build. To execute them separately within a container, run:

    bats test

## Continuous Integration

Images are built and pushed to Docker Hub on every deploy. Because Quay currently only supports build triggers where the Docker tag name exactly matches a GitHub branch/tag name, we must run the following script to synchronize all our remote branches after a merge to master:

    make sync-branches

## Deployment

To push the Docker image to Quay, run the following command:

    make release

## Copyright and License

MIT License, see [LICENSE](LICENSE.md) for details.

Copyright (c) 2019 [Aptible](https://www.aptible.com) and contributors.
