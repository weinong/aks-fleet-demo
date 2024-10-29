# AKS Fleet Manager Demo

As a platform engineering team, I'd like to ensure [fluent-bit](https://docs.fluentbit.io/manual/installation/kubernetes#installation) installed in every k8s cluster managed by [Azure Fleet Manager](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/).

In this demo, I will
* Create one AKS Fleet Manager with Hub and three AKS clusters
* The first two AKS clusters join the Fleet
* Create a `ClusterResourcePlacement` to deploy `fluent-bit` namespace to all members
* Deploy `fluent-bit` helm chart to the Hub
* Observe the `fluent-bit` pods running in the two member clusters
* Join the last AKS cluster to the Fleet
* Observe the `fluent-bit` pods running in the newly joined member

To run this demo, you need `Owner` role to an Azure subscription.

## Additional Resources

### Run Fleet Manager on your OnPrem k8s clusters

https://github.com/Azure/fleet/blob/main/docs/getting-started/on-prem.md

### Joining an OnPrem k8s to Azure Fleet Manager

https://github.com/Azure/fleet/blob/main/docs/tutorials/Azure/JoinOnPremClustersToFleet.md