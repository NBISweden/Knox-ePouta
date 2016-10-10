# Tryggve - Report on the Epouta connection

This document describes, given the [network settings](./docs.md) of
the Knox-Epouta connection, how we tested the limitations of a system,
in case some of the compute nodes are distributed accross the nordic
countries.

We sat up a test project that runs on Knox, and uses Epouta's virtual
machines (VMs) to extend the list of compute nodes. The main
limitation is the disk accesses, i.e. the network file system (NFS)
(cf. the last test).

# Cancer Analysis Workflow

The first test is the
[Cancer Analysis Workflow](https://github.com/SciLifeLab/CAW) from
SciLifeLab. We wanted to test a realistic workload, which works on
sensitive data. However, the small sample we used is on non-sensitive
data. This test is used as a placeholder for other workflow working on
sensitive data, as in Mosler.

That workflow already runs on `milou` at Uppmax, and therefore uses
`slurm`. We instantiated 3 compute nodes on Knox and 3 in
Epouta. After we installed all the dependencies on the compute nodes,
we distributed the compute nodes in slurm partitions as follows:

1. 3 nodes from Knox.
2. 1 node from Knox, 2 nodes from Epouta.
3. 2 nodes from Knox, 1 node from Epouta.
4. 3 nodes from Epouta

Moreover, when a task from the workflow only requires one node, we
were interested in finding out if the first node on the slurm
partition matters. Finally, we ran a comparision with the same workflow running on `milou` with 3 compute nodes (similar to the ones in Knox and Epouta). So we added extra partitions:

5. 1 node from Knox (first), 2 nodes from Epouta.
6. 1 node from Epouta (first), 2 nodes from Knox.
7. 2 nodes from Epouta (first), 1 node from Knox.
8. 3 nodes on `milou`.

> Conclusion: The first compute node on the slurm partition matters.

The workflow runs using nextflow. We ran it on a small non-sensitive
data sample, and recorded the elapsed time, for each partition.

`nextflow run MultiFQtoVC.nf -c <slurm_partition>.config --sample /mnt/projects/CAW/data/tsv/sample.tsv`

The results are as follows:

1. 
2. 
3. 
4. 
5. 
6. 
7. 
8.

> Conclusion: The first compute node on the slurm partition matters.

# Whole Genome Sequencing Structural Variation Pipeline

Following the same procedure as the previous experiment, using the
same partitions, we ran the
[Whole Genome Sequencing Structural Variation Pipeline](https://github.com/NBISweden/wgs-structvar)
(WGS) from [NBIS](http://www.nbis.se). It requires a `bam` file, and we ran the `manta` step on it, using again `nextflow`.

`nextflow run main.nf --bam <bamfile.bam> --steps manta,vep`

The elapsed times are as follows:

1. 
2. 
3. 
4. 
5. 
6. 
7. 
8. 

# NFS stress test

Finally, we stress-tested the network file system (NFS) by writing
files from the compute nodes onto an NFS-shared location, using
[sob](https://www.pdc.kth.se/~pek/sob).


> Conclusion: NFS is a real bottleneck and should be avoided.
