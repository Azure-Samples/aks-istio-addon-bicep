#!/bin/bash

az aks install-cli --only-show-errors

# Get AKS credentials
az aks get-credentials \
  --admin \
  --name $clusterName \
  --resource-group $resourceGroupName \
  --subscription $subscriptionId \
  --only-show-errors

# Check if the cluster is private or not
private=$(az aks show --name $clusterName \
  --resource-group $resourceGroupName \
  --subscription $subscriptionId \
  --query apiServerAccessProfile.enablePrivateCluster \
  --output tsv)

if [[ $private == 'true' ]]; then
  # Log whether the cluster is public or private
  echo "$clusterName AKS cluster is public"

  # Create cluster issuer for the Application Gateway Ingress Controller (AGIC)
  if [[ $applicationGatewayEnabled == 'true' ]]; then
    command="cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-application-gateway
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $email
    privateKeySecretRef:
      name: letsencrypt
    solvers:
    - http01:
        ingress:
          class: azure/application-gateway
          podTemplate:
            spec:
              nodeSelector:
                "kubernetes.io/os": linux
EOF"

    az aks command invoke \
      --name $clusterName \
      --resource-group $resourceGroupName \
      --subscription $subscriptionId \
      --command "$command"
  fi

  # Create a namespace for the sample bookinfo application
  command="kubectl create namespace $namespace"

  az aks command invoke \
    --name $clusterName \
    --resource-group $resourceGroupName \
    --subscription $subscriptionId \
    --command "$command"

  # To automatically install sidecar to any new pods, annotate your namespaces
  # The default istio-injection=enabled labeling doesn't work. Explicit versioning (istio.io/rev=asm-1-17) is required.
  command="kubectl label namespace $namespace istio.io/rev=asm-1-17"

  az aks command invoke \
    --name $clusterName \
    --resource-group $resourceGroupName \
    --subscription $subscriptionId \
    --command "$command"

  # Deploy the sample bookinfo application
  command="kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/bookinfo/platform/kube/bookinfo.yaml -n $namespace"

  az aks command invoke \
    --name $clusterName \
    --resource-group $resourceGroupName \
    --subscription $subscriptionId \
    --command "$command"

  # The sample bookinfo application isn't accessible from outside the cluster by default after enabling the ingress gateway.
  # To make the application accessible from the internet, map the sample deployment's ingress to the Istio ingress gateway using the following manifest.
  # Create an ingress resource for the application
  command="cat <<EOF | kubectl apply -n $namespace -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: bookinfo-gateway-external
  namespace: $namespace
spec:
  selector:
    istio: aks-istio-ingressgateway-external
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: bookinfo-vs-external
  namespace: $namespace
spec:
  hosts:
  - "*"
  gateways:
  - bookinfo-gateway-external
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: productpage
        port:
          number: 9080
EOF"

  az aks command invoke \
    --name $clusterName \
    --resource-group $resourceGroupName \
    --subscription $subscriptionId \
    --command "$command"

else
  # Log whether the cluster is public or private
  echo "$clusterName AKS cluster is public"

  # Create a namespace for the sample bookinfo application
  kubectl create namespace $namespace

  # To automatically install sidecar to any new pods, annotate your namespaces
  # The default istio-injection=enabled labeling doesn't work. Explicit versioning (istio.io/rev=asm-1-17) is required.
  kubectl label namespace $namespace istio.io/rev=asm-1-17

  # Deploy the sample bookinfo application
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/bookinfo/platform/kube/bookinfo.yaml -n $namespace

  # The sample bookinfo application isn't accessible from outside the cluster by default after enabling the ingress gateway.
  # To make the application accessible from the internet, map the sample deployment's ingress to the Istio ingress gateway using the following manifest.
  # Create an ingress resource for the application
  cat <<EOF | kubectl apply -n $namespace -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: bookinfo-gateway-external
  namespace: $namespace
spec:
  selector:
    istio: aks-istio-ingressgateway-external
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: bookinfo-vs-external
  namespace: $namespace
spec:
  hosts:
  - "*"
  gateways:
  - bookinfo-gateway-external
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: productpage
        port:
          number: 9080
EOF

fi

ingressHostExternal=$(kubectl -n aks-istio-ingress get service aks-istio-ingressgateway-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ingressPortExternal=$(kubectl -n aks-istio-ingress get service aks-istio-ingressgateway-external -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
gatewayUrlExternal=$ingressHostExternal:$ingressPortExternal

# Create output as JSON file
echo '{}' |
  jq --arg x $namespace                                '.namespace=$x' |
  jq --arg x $ingressHostExternal                      '.ingressHostExternal=$x' |
  jq --arg x $ingressPortExternal                      '.ingressPortExternal=$x' |
  jq --arg x $gatewayUrlExternal                       '.gatewayUrlExternal=$x'  |
  jq --arg x "http://$gatewayUrlExternal/productpage"  '.bookInfoUrlExternal=$x'  >$AZ_SCRIPTS_OUTPUT_PATH
