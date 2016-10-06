# Tryggve - Report on the Epouta connection

This document describes how we set up a test project that runs on
Knox, and uses Epouta's virtual machines (VMs) to extend the list of
compute nodes.

The network settings are described in the [network report](../docs.md).
We describe here the tests we chose, and the results we obtained.

# NFS stress test

https://www.pdc.kth.se/~pek/sob

# Cancer Analysis Workflow

From the [SciLifeLab github repo](https://github.com/SciLifeLab/CAW)

`nextflow run MultiFQtoVC.nf -c <slurm_partition>.config --sample /mnt/projects/CAW/data/tsv/sample.tsv`

# Whole Genome Sequencing Structural Variation Pipeline

From the [NBIS github repo](https://github.com/NBISweden/wgs-structvar)

`nextflow run main.nf --bam <bamfile.bam> --steps manta,vep`

