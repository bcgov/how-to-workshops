# BC Government implementation guide for using DevExchange "Vault" Service

The DevExchange group provisions a Hashicorp Vault for each Openshift (OC4) Project Set (licensepate-dev/test/prod/tools - eg: abc123-dev, abc123-test, abc123-prod, abc123-tools).

To start, you need to have permissions to use the Vault. What we've been able to gather is that whomever is the "owner" of the Openshift environment is generally also the "technical contact". This same person (or persons) are also owner(s) of the Vault. This is typically the person who requested the OC4 Project Set.  Within the Vault service the only people who are able to grant additional permissions is the DevExchange team. The owner does not have rights to alter roles. Best method to get additional technical resources (eg: Devops Engineers) is to ask the owner to post a request in the [#devops-vault RocketChat channel](https://chat.developer.gov.bc.ca/channel/devops-vault). As of the time of writing, users do not have permissions to create additional secret engines. You must therefore organize your secrets into the pre-allocated secret engines. This constraint may cause issues if your secrets have the same name throughout the different namespaces.

To log into the vault start here:
[https://vault.developer.gov.bc.ca/](https://vault.developer.gov.bc.ca/)

To log in use the following values:
Namespace: platform-services
Method: OIDC
Role: {LicensePlate}  (eg: abc123) (Note: No need for the dev/test/prod suffix)

It will then prompt you to authorize with your Github account.

Once you've authenticated to your vault you will see 3 secret engines. {licenseplate}-nonprod, {licenseplate}-prod and cubbyhole. Your prod namespace has its own secret engine, while your tools, dev and test namespaces will share the nonprod secret engine as the naming suggests. The cubbyhole secret engine was not used in our environment.

We organized our secrets as follows:

```
{licenseplate}-nonprod                #secret engine
- |---microservices-secret-dev          #secret name
-     |---dev_database_host             #secret data
-     |---dev_database_name             #secret data
-     |---dev_service_account           #secret data
-     |---dev_service_account_pass      #secret data

- |---microservices-secret-debug        #secret name
-     |---dev_hostname                  #secret data
-     |---dev_toolbox                   #secret data

- |---microservices-secret-test         #secret name
-     |---test_database_host            #secret data
-     |---test_database_name            #secret data
-     |---test_service_account          #secret data
-     |---test_service_account_pass     #secret data

{licenseplate}-prod                     #secret engine
- |---microservices-secret-prod         #secret name
-     |---prod_database_host            #secret data
-     |---prod_database_name            #secret data
-     |---prod_service_account          #secret data
-     |---prod_service_account_pass     #secret data
```

Note: Don't use a hyphen in a "key".  Vault will accept the value but it's problematic in the Openshift templates which shows up as an error in the vault-init container.

# Usage of the Vault secrets in Openshift.
When you look at the getting-started-demo you'll see there's already a deployment template to assist. The two important parts of this vault demo are:
    annotations
    serviceaccount

## Annotation
We elected to use the annotation / sidecar method. [This was helpful from Hashicorp](https://www.vaultproject.io/docs/platform/k8s/injector/examples).

Note: Learn from my mistake in the Deployment. Place the annotation in the correct location. In the "Deployment" it belongs in the "metadata" portion of "template" NOT the root metadata section:

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
        vault.hashicorp.com/role: abc123-nonprod  # licenseplate-nonprod or licenseplate-prod are your options
        # We don't really know if this key needs to match the secret or not...please update if you know.
        vault.hashicorp.com/agent-inject-secret-microservices-secret-dev: abc123-nonprod/microservices-secret-dev
        vault.hashicorp.com/agent-inject-template-microservices-secret-dev: |
          {{- with secret "abc123-nonprod/microservices-secret-dev" }}
          export dev_database_host="{{ .Data.data.dev_database_host }}"
          export dev_database_name="{{ .Data.data.dev_database_name }}"
          {{- end `}} }}

        # This is another sample. This set uses some HELM chart variable replacements. There's a bit of magic with the ` symbol in the agent-inject-template section. It also required some additional braces {}. You can use this as an example of what worked for me.
        vault.hashicorp.com/agent-inject-secret-microservices-secret-debug: {{ .Values.global.licenseplate }}-{{ .Values.global.vault_engine }}/microservices-secret-debug
        vault.hashicorp.com/agent-inject-template-microservices-secret-debug: |
          {{`{{- with secret `}}"{{ .Values.global.licenseplate }}-{{ .Values.global.vault_engine }}/microservices-secret-debug"{{` }}
          export dev_hostname="{{ .Data.data.dev_hostname }}"
          export dev_toolbox="{{ .Data.data.dev_toolbox }}"
          {{- end `}} }}
    spec:
      serviceAccount: abc123-vault
      # or for HELM with var replacements use:
      #serviceAccount: {{ .Values.global.licenseplate }}-vault

  ```

Note the additional line under spec that I added. This is the service account that is needed to connect to the Vault. This account has been created already for you in Openshift so on the surface it's straight forward. You may notice another one that's used in the demo:
```        serviceAccountName: LICENSE-vault```
I believe the serviceAccountName is used for Openshift and ServiceAccount is used by Kubernetes. I've yet to determine the differences or why there is a difference, but in any case, using ServiceAccount did the trick for me while using Deployments. Having both did not hurt. This is more the Kubernetes way of doing things than the Openshift method which I've seen uses DeploymentConfigs and possibly that's where serviceAccountName comes into play?

There's a issue to be aware of with using this service account. In my case I use Imagestreams from the {licenseplate}-tools namespace which means I need to have a service account that's allowed to read from the image stream between namespaces (eg: between abc123-dev and abc123-tools). Originally I'd set the "deployer" account with the permissions to do this by adding the vault secrets to the deployer SA, but for some reason it didn't work. What did work was using the {licenseplate}-vault service account (abc123-vault). It already had permissions to read from the tools namespace. Perhaps not optimal, but it worked.
