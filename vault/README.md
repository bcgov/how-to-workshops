# BC Government implementation guide for using DevExchange "Vault" Service

The DevExchange group provisions a Hashicorp Vault for each Openshift (OC4) Project Set (Licensepate-dev/test/prod/tools).

To start off you need to be have permissions to use the vault.  By default the admin associated with the OC4 will be granted admin permissions to the Vault.

To log into the vault start go here:
https://vault.developer.gov.bc.ca/

To log in use the following values:
Namespace: platform-services
Method: OIDC
Role: {LicensePlate}  (eg: abc123) (Note: No need for the dev/test/prod suffix)

It will then prompt you to authorize with your Github account.

*** TODO: ADAM
 - add details as to how to use Vault to add secrets.
 - Provide an example of the way we did it with nonprod and prod
 - speak to the challenges we had around dev/test/tools all in nonprod (same var name different value)
 - speak to how we weren't able to separate dev/test into sub catagories like we wanted eg: /nonprod/dev/variable, /nonprod/test/variable

I've had questions about the DevExchange Vault service and ownership/permissions.  I can't say I have all the details, but what I've been able to gether is that whomever is the "owner" of the Openshift environment is generally also the "technical contact".  This same person (or persons) are also owner(s) of the Vault.  This is typically the person who requested the OC4 "Project Set" (a project set is the OC4 dev/test/prod/tools namespaces).  Within the Vault service the only people who are able to grant additional permissions is the DevExchange team.  The owner does not have rights to alter roles.  Best method to get additional technical resources (eg: Devops Engineers) is to ask the owner to post a request in the [#devops-vault RocketChat channel](https://chat.developer.gov.bc.ca/channel/devops-vault).


TODO: a note to incorporate somewhere.  Don't use a hyphen in a "key".  Vault will accept the value but it's problematic in the openshift templates which shows up as an error in the vault-init container.


# Usage of the Vault secrets in Openshift.
When you look at the getting-started-demo you'll see there's already a deployment template the assist. The two important parts of this vault demp are:
    annotations
    serviceaccount

## Annotation
We elected to use the annotation / sidecar method. [This was helpful from Hashicorp](https://www.vaultproject.io/docs/platform/k8s/injector/examples).

Note: learn from my mistake in the Deployment. Place the annotation in the correct location. In the "Deployment" it belongs in the template category of course:

```
kind: Deployment
apiVersion: apps/v1
metadata:
  name: myapp
  labels:
    app: myapp
  annotations:
    # NOT HERE!!!
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
      annotations:
        # Vault sidecar code goes here, inside the template.
        vault.hashicorp.com/agent-inject: 'true'
        vault.hashicorp.com/agent-inject-token: 'true'
        vault.hashicorp.com/auth-path: auth/k8s-gold  # This was tricky.  Be sure to use k8s-silver, k8s-gold, or k8s-golddr
        vault.hashicorp.com/namespace: platform-services
        vault.hashicorp.com/role: abc123-nonprod  # licenselace-nonprod or licenseplate-prod are your options

        vault.hashicorp.com/agent-inject-secret-microservicesVar: abc123-nonprod/SecretsVarA
        vault.hashicorp.com/agent-inject-template-microservicesVar: |
          {{- with secret "abc123-nonprod/SecretVarA" }}
          export env_var_1="{{ .Data.data.var1 }}"
          export env_var_2="{{ .Data.data.var2 }}"
          {{- end `}} }}

        # This is another sample.  This set uses some HELM chart variable replacements.  There's a bit of a trick with the ` symbol in the agent-inject-template section.  It also required some fancier braces {}.  You can use this as an example of what worked for me.
        vault.hashicorp.com/agent-inject-secret-microservicesVar2: {{ .Values.global.licenseplate }}-{{ .Values.global.vault_engine }}/microservicesVar2
        vault.hashicorp.com/agent-inject-template-microservicesVar2: |
          {{`{{- with secret `}}"{{ .Values.global.licenseplate }}-{{ .Values.global.vault_engine }}/microservicesVar2"{{` }}
          export env_var_3="{{ .Data.data.var3 }}"
          export env_var_4="{{ .Data.data.var4 }}"
          {{- end `}} }}
    spec:
      serviceAccount: {{ .Values.global.licenseplate }}-vault
  ```


Note the additional line under spec that I added. This is the service account that is needed to connect to the Vault. This account has been created already for you so on the surface it's straight forward. You may notice two another one that's used:
```        serviceAccountName: LICENSE-vault```
I believe the serviceAccountName is used for Openshift and ServiceAccount is used by Kubernetes.  I've yet to determine the differences or why there is a difference, but in anycase, using ServiceAccount did the trick for me while using Deployments.  This is more the Kubernetes way of doing things than the Openshift method which I've seen use DeploymentConfigs and possibly that's where serviceAccountName comes into play.

There's a trick/issue to be aware of with using this service account. In my case I use Imagestreams from the licenseplate-tools namespace which means I need to have a service account that's allowed to read from the image stream between namespaces (eg: between abc123-dev and abc123-tools). Originally I'd set the "deployer" account with the permissions to do this by adding the vault secrets to the deployer SA, but for some reason it didn't work.  What did work was using the {licenseplate}-vault service account (abc123-vault).  It already had permissions to read from the tools namespace.  Perhaps not optimal, but it worked.
