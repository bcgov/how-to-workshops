# Crunchy DB PostgresCluster

Here you can find a sample [HA PGO setup](high-availablility/) and a howto on setting up the [Crunchy Monitoring stack](monitoring/).

Docs for Cruncy DB can be found [here](https://access.crunchydata.com/documentation/postgres-operator/v5/).

## Upgrading / Patching

To upgrade your PGO cluster, simply update the `image:` references to the new image names and the operator will take care of the rest. See the [docs](https://access.crunchydata.com/documentation/postgres-operator/5.0.4/tutorial/update-cluster/) for more details.

For the community version, subscribe to the mailing list [pgsql-announce](https://lists.postgresql.org/manage/) to find out about updates. If we upgrade to the enterprise version the platform team will be notified of updates and announce them to the teams using the operator.

## Port Forwarding

If you want to connect to PGO from your local workstation use these steps.

```bash
PG_CLUSTER_PRIMARY_POD=$(oc get pod -n -o name -l postgres-operator.crunchydata.com/cluster=,postgres-operator.crunchydata.com/role=master)
oc -n ae3cec-dev port-forward "${PG_CLUSTER_PRIMARY_POD}" 5432:5432
```
