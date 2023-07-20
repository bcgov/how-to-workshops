# Skupper

Skupper lets you connect services in multiple OpenShift clusters together with MutualTLS. You can also connect to Linux hosts running Skupper via Podman. All the communication is done via port 443, and can flow over forward proxy servers. Only one Skupper Site needs to be accessable by the rest for data to flow.


- [Skupper](#skupper)
  - [Install the CLI](#install-the-cli)
  - [Create Primary Site](#create-primary-site)
  - [Create a Secondary Site](#create-a-secondary-site)
  - [Create a Connection Token](#create-a-connection-token)
  - [Create a Backend Service to be Accessed](#create-a-backend-service-to-be-accessed)
  - [Create a Frontend Service](#create-a-frontend-service)
  - [Test the app](#test-the-app)
  - [Set up a Linux VM as a Site](#set-up-a-linux-vm-as-a-site)
  - [Additional Resources](#additional-resources)

## Install the CLI

Get the CLI and install it from <https://github.com/skupperproject/skupper/releases>

## Create Primary Site

Create the first Skupper Site. This will include an OpenShift Route object that other sites will connect to to join the network. Suggest doing this in the Silver or Gold cluster.

```bash
skupper init --create-network-policy --site-name silver --routers 2
```

This will set up a skupper router pod, a couple routes, and a network policy allowing other pods in the namespace to communicate with the skupper router.

Ensure you have a NetworkPolicy to allow incoming connections from the router.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-openshift-ingress
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          network.openshift.io/policy-group: ingress
  podSelector: {}
  policyTypes:
  - Ingress
```

## Create a Secondary Site

In another terminal window connected to another OCP cluster, next we'll set up another Skupper Site.

I'll do this in the Emerald cluster. We will need some extra NetworkPolicy since that cluster enforces Egress rules as well.

```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: skupper-router-egress
spec:
  podSelector:
    matchLabels:
      skupper.io/component: router
  egress:
    - ports:
        - protocol: TCP
          port: 443
      to:
        - ipBlock:
            cidr: 1.2.3.4/32 # IP of primary site router
  policyTypes:
    - Egress
---
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: skupper-controller-egress
spec:
  podSelector:
    matchLabels:
      skupper.io/component: service-controller
  egress:
    - to:
        - podSelector:
            matchLabels:
              skupper.io/component: router
    - ports:
        - protocol: TCP
          port: 443
      to:
        - ipBlock:
            cidr: 1.2.3.4/32 # IP of primary site router
  policyTypes:
    - Egress
```

When initiating the site we also need to add the DataClass label for the pods to ensure they can communicate within the guardrails of NSX.

```bash
skupper init --create-network-policy --labels DataClass=Medium --site-name emerald --routers 2
```

Label the routes that are created

```bash
oc annotate route --all aviinfrasetting.ako.vmware.com/name=dataclass-medium
```

## Create a Connection Token

On the primary terminal, create a connection token secret. This is a Kubernetes Secret file with a CA cert, a password, and the route of the primary site in it. Be sure to keep it secret, as it is what controls access to your Skupper network. The name is of the secondary site.

```bash
skupper token create ./skupper.secret
```

Copy the secret to your terminal for the secondary site, then link that site to the primary. The token is only good for 15 minutes. the name is of the primary site.

```bash
skupper link create ~/skupper.secret --name silver
```

## Create a Backend Service to be Accessed

We can now set up a "backend" service in the NSX cluster to be accessed by a "frontend" service in the Silver cluster.

```bash
# Create a deployment
oc create deployment hello-world-backend --image quay.io/skupper/hello-world-backend
# Add DataClass labels
oc patch deployment/hello-world-backend --type=merge -p '{"spec":{"template":{"metadata":{"labels":{"DataClass":"High"}}}}}'
# Create a service
oc expose deployment hello-world-backend --port=8080
```

Then, we'll make some NetworkPolicies to allow traffic from the Skupper Router to the new deployment

```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: backend-from-skupper
spec:
  podSelector:
    matchLabels:
      app: hello-world-backend
  ingress:
    - ports:
        - protocol: TCP
          port: 8080
      from:
        - podSelector:
            matchLabels:
              skupper.io/component: router
  policyTypes:
    - Ingress
---
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: skupper-to-backend
spec:
  podSelector:
    matchLabels:
      skupper.io/component: router
  egress:
    - ports:
        - protocol: TCP
          port: 8080
      to:
        - podSelector:
            matchLabels:
              app: hello-world-backend
  policyTypes:
    - Egress
```

Lastly, lets add the service to the Skupper network.

```bash
skupper expose service hello-world-backend --address backend
```

## Create a Frontend Service

We'll create a frontend service with a Route in our public (Silver) cluster that connects to the backend service in the NSX cluster.

```bash
# Create a deployment
oc create deployment hello-world-frontend --image quay.io/skupper/hello-world-frontend
# Create a service
oc expose deployment hello-world-frontend --port=8080
# Create a route
oc expose service hello-world-frontend
```

## Test the app

Connect to the route of the frontend app in your browser. Click on the "Say hello" button, and you should get a message below back from the backend service.

## Set up a Linux VM as a Site

Get a RHEL 9 VM that can access your backend service as well as the Route of one of your other Skupper Sites.

Have the Linux team install some packages for you and set up your user/service account to run Podman.

```bash
sudo dnf install podman netavark
sudo loginctl enable-linger someuser_a
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 someuser_a
```

Log in as your user and set up podman

```bash
systemctl --user start podman.socket
mkdir .local/bin -p
tar zxvf skupper-cli-1.4.1-linux-amd64.tgz -C .local/bin/
podman network create skupper
```

If you VM can connect to the internet, it will be able to pull down the Skupper podman image. If not, then import the image to your namespace and pull it from there.

```bash
# In your namespace
oc tag quay.io/skupper/skupper-router:2.4.1 ce9012-test/skupper-router:2.4.1 --scheduled
oc create token default # this will give the "password" to log into the image registry with
# On your VM
export SKUPPER_IMAGE_REGISTRY=image-registry.apps.silver.devops.gov.bc.ca/ce9012-test
podman login -u serviceaccount image-registry.apps.silver.devops.gov.bc.ca
# supply the token from above
```

Now we can set up the Skupper Site on the VM

```bash
skupper switch podman
skupper init --ingress none --container-network skupper
```

Then we expose the service from this site. The IP can be the local VM, or another IP this VM can reach such as a DB server.

```bash
skupper expose host 142.x.x.x --address foobla --port 80
```

Then back in your namespace, add the service to the Skupper network

```bash
skupper service create foobla 80
```

Now, from any of the namespaces in the Skupper network, you can connect to the new service.

## Additional Resources

- Skupper CLI docs - <https://skupper.io/docs/cli/index.html>
- Hello World example - <https://github.com/skupperproject/skupper-example-hello-world>
- Red Hat Service Interconnect docs - <https://access.redhat.com/documentation/en-us/red_hat_application_interconnect/1.1>
