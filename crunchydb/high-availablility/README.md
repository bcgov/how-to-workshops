# Sample HA CrunchyDB PostgresCluster

This is a sample `PostgresCluster` adapted from the example at <https://github.com/CrunchyData/postgres-operator-examples/tree/main/kustomize/high-availability>.

You can find a full tutorial and docs on CrunchyDB at <https://access.crunchydata.com/documentation/postgres-operator/5.0.0/tutorial/>.

In this example, my license plate is `be1c6b`.

`NetworkPolicy.yaml` has a sample NetworkPolicy for allowing the cluster pods to talk to each other, and the one needed by Monitoring for access.

`RoleBinding` has the Role and RoleBinding needed by the Monitoring stack.

`PostgresCluster` has the sample PostgresCluster with 3 replicas, backups, and monitoring.

## Images

The PostgresCluster should include the version specifications for PostgreSQL and if required PostGIS. The reference to the image should always be specified to ensure that it can be found.

```
spec:
  postgresVersion: 15
  postGISVersion: "3.3"
  image: artifacts.developer.gov.bc.ca/bcgov-docker-local/crunchy-postgres-gis:ubi8-15.2-3.3-0
  imagePullPolicy: IfNotPresent
```

The following images are available in the artifacts.developer.gov.bc.ca/bcgov-docker-local image repository.

* Postgres
    * 13 ?????
    * 14
        * crunchy-postgres:ubi8-14.7-0
        * crunchy-postgres-gis:ubi8-14.7-3.1-0 (3.2-0 or (3.3-0))
    * 15
        * crunchy-postgres-gis:ubi8-15.2
        * crunchy-postgres-gis:ubi8-15.2-3.3-0
* PGAdmin: crunchy-pgadmin4:ubi8-4.30-10
* PGBackRest: crunchy-pgbackrest:ubi8-2.41-4
* PGBouncer: crunchy-pgbouncer:ubi8-1.18-0
* PGExporter: crunchy-postgres-exporter:ubi8-5.3.1-0

## Monitoring Sidecar

The monitoring side car is added like this.

```yaml
spec:
  monitoring:
    pgmonitor:
      exporter:
        image: registry.developers.crunchydata.com/crunchydata/crunchy-postgres-exporter:ubi8-5.0.4-0
```

## Storage Class

Postgres works best on block storage.

```yaml
spec:
  instances:
    - name: pgha1
      dataVolumeClaimSpec:
        storageClassName: netapp-block-standard
```

## Backups

Keep 2 copies of full backups.

```yaml
spec:
  backups:
    pgbackrest:
      global:
        repo1-retention-full: "2"
```

Set the cron schedule for full and incremental backups.

```yaml
spec:
  backups:
    pgbackrest:
      repos:
      - name: repo1
        schedules:
          # Full backup every day at 8:00am UTC
          full: "0 8 * * *"
          # Incremental backup every 4 hours, except at 8am UTC (when the full backup is running)
          incremental: "0 0,4,12,16,20 * * *"
```

### Four Storage Options

* PVC
* S3
* Azure
* GCS

#### PVC

Set the backups to go to a PVC that is [backed up](https://developer.gov.bc.ca/OCP4-Backup-and-Restore).

```yaml
spec:
  backups:
    pgbackrest:
      repos:
      - name: repo1
        volume:
            storageClassName: netapp-file-backup
```

#### S3

* Add S3 credentials to [StorageSecret.yaml](./StorageSecret.yaml)
* If different repo $index then update keys accordingly and apply
* Update global configuration by adding `repo1-s3-uri-style: path`
* Add below config to PostgresCluster.yaml

```yaml
spec:
  backups:
    pgbackrest:
      configuration:
      - secret:
        name: hippo-ha-pgbackrest-secret
      repos:
      - name: repo1
        s3:
          bucket: <YOUR_S3_BUCKET>
          region: us-west-1
          endpoint: bc-data-obj.objectstore.gov.bc.ca
```

##### Note:

Update below command and use it to spawn minio for verifying backups

```bash
docker run -it --rm -p 9000:9000 -p 9001:9001 --name minio-s3 \
 -e "MINIO_ROOT_USER=<YOUR_S3_BUCKET_KEY>" \
 -e "MINIO_ROOT_PASSWORD=<YOUR_S3_BUCKET_SECRET>" \
 quay.io/minio/minio gateway s3 --console-address ":9001" https://bc-data-obj.objectstore.gov.bc.ca
```
