# Tryggve - Report on the Epouta connection

This document describes how we set up a test project that runs on
Knox, and uses Epouta's virtual machines (VMs) to extend the list of
compute nodes.

We first describes how Knox and Epouta are connected, and we then
describe the test example we ran.

# Knox and network settings

There is a dedicated fiber link between Knox and Epouta. We first
describe the setup on Knox.

# NFS stress test

https://www.pdc.kth.se/~pek/sob

# Fake mosler examples

Assume we have a project running in a mosler environment, and that
this project uses a set of VMs on Knox. We use Epouta's VMs to extend
the latter set.

In reality, we do not have a mosler setup. Instead, we use a vanilla
openstack installation, and non-sensitive data (or rather, trivial
data from a small test case). On this openstack installation, we
instantiate a project on VLAN 1203. The VMs on that VLAN will be
communicate transparently to the ones in Epouta.

## Cancer Analysis Workflow

From the [SciLifeLab github repo](https://github.com/SciLifeLab/CAW)

`nextflow run MultiFQtoVC.nf -c <slurm_partition>.config --sample /mnt/projects/CAW/data/tsv/sample.tsv`

## Whole Genome Sequencing Structural Variation Pipeline

From the [NBIS github repo](https://github.com/NBISweden/wgs-structvar)

`nextflow run main.nf --bam <bamfile.bam> --steps manta,vep`

