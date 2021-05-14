# TL;DR

In April 2020 we removed Aporeto from the Silver cluster and went all in on Kubernetes Network Policy (KNP). This lab contains the quick start material that will get your environment up and running with the new KNP.

* [OpenShift SDN](https://docs.openshift.com/container-platform/4.6/networking/openshift_sdn/about-openshift-sdn.html)

* [OpenShift NetworkPolicy](https://docs.openshift.com/container-platform/4.6/networking/network_policy/about-network-policy.html#about-network-policy)

* [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

# Prologue

 Back in 2019 we decided to take a strong stance on security and, by way of a security focused project, began implementing several tools to make our OpenShift Container Platform (OCP) a leader in this respect. One of these tools, Aporeto, was chosen as a Software Defined Network solution to control network security for Platform app. Aporeto has been selected over Openshift 4 Built-In SDN capability powered by Kubernetes Network Policy (KNP), because it offered a way to extend security policies outside of OpenShift into other systems that are based on the traditional infrastructure such as databases hosted in Zone B. This would have enabled teams to secure connections between their apps running in the OpenShift Platform and data sources hosted inside the Zone B network zone. 

While Aporeto provided a great developer experience and the functionality that met our needs very well, we ran into some issues with running it on top of our specific OpenShift implementation and thus, the decision to pivot to OCP 4 Built-In SDN. Some might say this was a failure, but in reality, learning new information and acting on it is a success. Learning new information and doing nothing would certainly be a failure.

**Takeaway 🧐**
- Aporeto and Kubernetes NetworkPolicy have a fairly comparable impact from the end-user’s (platform tenant) perspective. The main difference is that Aporeto could be extended to external systems where as KNP only applies to OCP. We are actively looking into the workarounds for the teams that need to secure integrations between their OpenShift applications and Zone B components and expect to finalize the list of options in April 2021.

# Introduction

This guide will walk you through implementing the quick start Network Policy (KNP). While this will be enough to your project up-and-running we **strongly** recommend rolling out more robust NP to ensure your environment(s) are as secure as they can be. Further workshops will expand on this subject. 

The current version of the OpenShift (v4.6) on the platform does not support all features outlined in the [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) documentation. The main differences as noted in the [OpenShift SDN](https://docs.openshift.com/container-platform/4.5/networking/openshift_sdn/about-openshift-sdn.html) documentation are that egress rules and some ipBlock rules are currently not supported; we expect these features to be delivered with OpenShift 4.8 later this fall.

If you need egress rules to limit what your pods can communicate with contact Platform Services (PS) in #devops-how-to RocketChat channel. We can help implement this type of policy.

# Getting Started

Before we dive into the quick start policies, lets go over a few important details:

### Egress Rules

With the quick start KNP in place pods will be able to connect to other pods within their namespace, in other namespaces, or to external systems (outside of the cluster). This is because egress rules are not available to tenants (project teams) just yet. This type of policy is available in OCP v4.6 but there isn't a migration path to them until OCP v4.8 which is expected in June of this year (2021). 

Without egress policy, pods that need to communicate **between namespaces** only require ingress rules on the destination pod to permit the inbound communication. This is fine is most circumstances because you will have a *deny-by-default* rule guarding all your namespaces.

High security projects that require egress rules to isolated a namespace should reach out to Platform Services; these policies can be implemented, as needed, by a cluster administrator.

### Roll Out

As platform tenants implement network policy they are "rolling out" KNP; there is nothing Platform Services needs to do. Everything is in place and working as expected. 

One KNP is installed in every namespaces provisioned by the registry and it cannot be removed; if you remove it a smart robot will just re-create it a few moments later.

```console
➜  how-to-workshops git:(master) ✗ oc get netpol
NAME                                           POD-SELECTOR   AGE
platform-services-controlled-deny-by-default   <none>         57d
```

By adding this policy to a namespace PS effectively enables KNP for that namespace.

## Quick Start

The quick start policy builds on top of the existing `platform-services-controlled-deny-by-default ` by adding two rules that:

1. Allow your routes to work by permitting traffic from the OpenShift HAProxy routers into your namespace (ingress);
2. Allow pods in the same namespace to communicate.

Lets review the thee policies in more detail.


### Walled Garden

First, the PS added policy `platform-services-controlled-deny-by-default` isolate the namespace creating a walled garden. Nothing will be able to talk to the pods inside and the pods inside won't be able to talk to one another:

```yaml
- kind: NetworkPolicy
  apiVersion: networking.k8s.io/v1
  metadata:
    name: platform-services-controlled-deny-by-default
  spec:
    # The default posture for a security first namespace is to
    # deny all traffic. If not added this rule will be added
    # by Platform Services during environment cut-over.
    podSelector: {}
    ingress: []
```

### Ingress

Having a route alone isn't enough to let traffic flow into your pods, you also need a policy to specifically allow this. This will be the first custom policy added to your namespaces. Once in place, any pod with an external route will receive traffic on said route.

```yaml
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-openshift-ingress
  spec:
    # This policy allows any pod with a route & service combination
    # to accept traffic from the OpenShift router pods. This is
    # required for things outside of OpenShift (like the Internet)
    # to reach your pods.
    ingress:
      - from:
          - namespaceSelector:
              matchLabels:
                network.openshift.io/policy-group: ingress
    podSelector: {}
    policyTypes:
      - Ingress
```

**Pro Tip 🤓**
- Add labels to your KNP to easily find and delete them as a group.
- `podSelector: {}` is a wildcard, if you want additional piece of mind add a label like `route-ingress: true` to pods that can accept external traffic and use it in place of the wildcard.

### Any to Any

Allowing pods to accept traffic from a route is great, and maybe that's enough for some projects, but most will have APIs and databases that need to communicate. This is done by adding another rule permitting all pods within a namespace to communicate.

```yaml
- kind: NetworkPolicy
  apiVersion: networking.k8s.io/v1
  metadata:
    name: allow-same-namespace
  spec:
    # Allow all pods within the current namespace to communicate
    # to one another.
    podSelector:
    ingress:
    - from:
      - podSelector: {}
```

**Pro Tip 🤓**
- Add labels to your KNP to easily find and delete them as a group.
- Additional labs will cover writing targeted KNP so that, for example, only the API pod can talk to a database pod.


## Quick Start

There is an OCP template called [QuickStart](./quickstart.yaml) at the root level of this lab. Its adds the two policy described above Before you run the quick start template, consider examining existing KNP and removing any redundant policy; it will make debugging easier in the future.

```console
oc get netpol
```

When you are ready to apply the quick start policy above run the following command passing in the two required parameters described below:

```console
oc process -f quickstart.yaml \
 -p NAMESPACE=<NAMESPACE_NAME_HERE> | \
 oc apply -f -
```

| Parameter    | Description         |
| :----------- | :------------------ |
| NAMESPACE    | The namespace you are deploying this policy to. |

Here is what the command should look like when run:

```console
➜  netpol-quickstart git:(main) ✗ oc process -f quickstart.yaml NAMESPACE -p $(oc project --short) | oc apply -f -
networkpolicy.networking.k8s.io/allow-same-namespace created
networkpolicy.networking.k8s.io/allow-all-internal created
```

That's it. While you're technically done it is **highly** recommended teams write custom policy that deliberately controls how pods communicate. To learn more about this keep reading...

**Pro Tip 🤓**

- Use `oc get netpol` or the OpenShift Web Console to view your newly minted policy;

## Testing

Test connectivity by opening a remote shell `oc rsh pod-name-here` to each pod then use the simple shell command shown below:

```console
timeout 5 bash -c "</dev/tcp/api/8080"; echo $?
```

![How To Test](images/how-to-test.png)


| Item | Description |
| :--- | :---------- |
| A    | The protocol to use, `tcp` or `udp` |
| B    | The `service` or pod name as shown by `oc get service` or `oc get pods` |
| C    | The port number exposed by the Pod |
| D    | The return code of the command: `0` means the pods can communicate, while `124` means the pods cannot communicate on the given protocol / port |
| E    | The delay in seconds the command will wait before failing |

## Need More Help?

If you need more help after reading this please ask questions in the `#devops-how-to` or do a quick search through [these issues](https://github.com/BCDevOps/OpenShift4-Migration/issues) in our OCP4 migration Q&A repo.
