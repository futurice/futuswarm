
# Quickstart to futuswarm

To get a feeling for what is possible check the full feature set via `futuswarm -hh`.

CLI defaults:
- -t|--tag=latest
- --port=8000 (eg. matching `EXPOSE 8000` in Dockerfile)

#### Build a docker image for your project

```
# Use a unique tag. Using Git? TAG=$(git rev-parse --short HEAD)
docker build -t IMAGE_NAME:TAG .
```

#### Push a local image to futuswarm

`futuswarm image:push -i IMAGE_NAME -t TAG`

#### Deploy the image

`futuswarm app:deploy -i IMAGE_NAME -t TAG -n APP_NAME`

#### Show application status

`futuswarm app:list -n APP_NAME`

#### Show application logs

`futuswarm app:logs -n APP_NAME`

#### Set environment configuration for the container

`futuswarm config:set KEY=val KEY2=val2 -n APP_NAME`

#### Show configuration

`futuswarm config -n APP_NAME`

#### Access the container

`futuswarm app:shell -n APP_NAME`

#### Attach a database (Postgres)

`futuswarm db:create:postgres -n APP_NAME`

The database connection configuration is created for you, check `futuswarm config -n APP_NAME`.

#### Attach an EBS volume to a container

Create a volume named **data**,
`futuswarm volume:create:ebs data --size 10 -n my`

get the full volume name,
`futuswarm volume:list -n my`

and attach it to /data on the container:
`futuswarm app:create ... --extra="--mount type=volume,target=/data,source=MY-VOLUME-NAME,volume-driver=rexray"`

To add persistence to an existing service remove it first.

#### Open access to service for everyone

At deployment stage set `--open=true` to allow access to the service from the configured `OPEN_DOMAIN`. An existing service needs to be removed for this flag to come in effect.

`futuswarm app:inspect -n APP_NAME` lists `com.df.serviceDomain` as the working domain names for the service.
