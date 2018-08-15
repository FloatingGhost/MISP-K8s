# MISP K8S

A helm chart to install MISP to k8s

## Installation

First make sure [helm](https://helm.sh/) is installed

```bash
# Copy values to edit
cp misp/values.yaml ./localvalues.yaml
helm install ./misp -f localvalues.yaml --name misp
```

Hooray it works

It'll be exposed on port 80 on hostname misp.misp unless you
changed the namespace or service name

### Credit

I more or less stole the dockerfile from [here](https://github.com/misp/misp-docker)
so thanks Xavier Mertens!
