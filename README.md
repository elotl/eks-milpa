# Create a Nodeless Kubernetes Cluster on EKS with Milpa

## Introduction

This document will go through the steps required to get a nodeless kubernetes cluster up and running on Amazon EKS with [Milpa](https://www.elotl.co/milpadocs) and [Kiyot](https://www.elotl.co/kiyotdocs).

Prerequisites:
* An AWS account that can create and manage EKS clusters.
* Terraform is used for provisioning the EKS cluster. Get it [here](https://www.terraform.io/downloads.html).
* Kubectl for interacting with Kubernetes. Install a compatible version from [here](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl). Kubectl supports one release of version skew, and here we use Kubernetes 1.10, so you will need kubectl 1.10 or 1.11.

Optional:
* A license for Milpa. Get one for free [here](https://www.elotl.co/trial). If no license is set, Milpa will switch into Developer Edition mode, which limits the number of pods it will handle.

Note: creating and running an EKS cluster on AWS will cost you money.

## Create an EKS Cluster

You will find a Terraform configuration in `terraform/`. Feel free to poke around, check out the .tf files, etc.

Next, you need to set a few variables for your new EKS cluster.

```
$ cd terraform/
$ cp env.tfvars.example env.tfvars
$ vi env.tfvars # Check the comments in the file to see what each variables does.
```

Once you set all the variables, you are ready to create the cluster:

```
$ terraform init # Only needed the first time you run terraform in this directory.

Initializing provider plugins...
- Checking for available provider plugins on https://releases.hashicorp.com...
- Downloading plugin for provider "aws" (2.2.0)...

[...]

$ terraform destroy -var-file env.tfvars

[...]

Plan: 26 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

Type `yes`, and terraform will start creating your EKS infrastructure. This will take a few minutes to complete.

## Configure your Cluster

A kubeconfig named `kubeconfig` is automatically created in the current working directory. To use it, either copy it to `~/.kube/config`, or set the `KUBECONFIG` environment variable:

```
$ export KUBECONFIG=$(pwd)/kubeconfig
```

At this point your cluster is ready for deploying your applications. You can go through our [Kiyot tutorials](https://static.elotl.co/docs/latest/kiyot/kiyot.html#tutorials) to get started.

## Cleanup

To remove all Kubernetes resources:

```
for ns in $(kubectl get namespaces | tail -n+2 | awk '{print $1}'); do
    kubectl delete --all pods --namespace=$ns
    kubectl delete --all deployments --namespace=$ns
    kubectl delete --all services --namespace=$ns
    kubectl delete --all daemonsets --namespace=$ns
done
```

Now you can remove the cluster via Terraform:

```
$ terraform destroy -var-file env.tfvars
```
