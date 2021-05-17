# cf-s3server-buildpack

Cloudfoundry buildpack to manage buckets S3, GCS ... based on [rclone](https://rclone.org/)


## Using it

Example `manifest.yml`: 

```manifest.yml
---
applications:
- name: rclone
  memory: 512M
  instances: 1
  stack: cflinuxfs3
  random-route: true
  buildpacks:
  - https://github.com/SpringerPE/cf-rclone-buildpack.git
  services:
  - jose-rclone-gcs
  - jose-rclone-aws
  env:
    AUTH_USER: "admin"
    AUTH_PASSWORD: "admin"
    CLONE_SOURCE_SERVICE: "jose-rclone-aws"
    CLONE_DESTINATION_SERVICE: "jose-rclone-gcs"
    CLONE_MODE: sync
    CLONE_TIMER: 600
```

# Development

Buildpack implemented using bash scripts to make it easy to understand and change.

https://docs.cloudfoundry.org/buildpacks/understand-buildpacks.html

The builpack uses the `deps` and `cache` folders according the implementation purposes,
so, the first time the buildpack is used it will download all resources, next times 
it will use the cached resources.


# Author

(c) 2019 Jose Riguera Lopez  <jose.riguera@springernature.com>
Springernature Engineering Enablement

MIT License
