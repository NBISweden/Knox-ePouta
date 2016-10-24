# Tryggve - Report on the Epouta connection

This document describes, given the [network settings](./docs.md) of
the Knox-Epouta connection, how we tested the limitations of a system,
in case some of the compute nodes are distributed accross the nordic
countries.

We sat up a test project that runs on Knox (in Sweden), and uses
Epouta's virtual machines (VMs in Finland) to extend the list of
compute nodes. The main limitation is the disk access, i.e. the
network file system (NFS) (cf. the last test).

The two workflows we tested already run on `milou` at Uppmax, and
therefore use `slurm`. We instantiated 3 compute nodes on Knox and 3
in Epouta. After we installed all the dependencies for those workflows
on the compute nodes, we distributed the compute nodes in slurm
partitions as follows.

Moreover, when a task from the workflow only requires one node, we
were interested in finding out if the first node on the slurm
partition matters (marked with *).

Finally, we ran a comparision with the same workflow running on
`milou` with 3 compute nodes (similar to the ones in Knox and
Epouta).


| Partition     | #nodes in Knox | #nodes in Epouta | Notes |
|:------------- |:--------------:|:----------------:|:----- |
| mm            | 3              | 0                |       |
| mm2-epouta1   | 2              | 1                |       |
| mm1-epouta2   | 1              | 2                |       |
| epouta        | 0              | 3                |       |
| epouta1-mm2 * | 1              | 2                | epouta nodes first in the slurm listing |
| epouta2-mm1 * | 2              | 1                | epouta nodes first in the slurm listing |
| _milou_       | -              | -                | 3 nodes on `milou` |


# Cancer Analysis Workflow

The first test is the
[Cancer Analysis Workflow](https://github.com/SciLifeLab/CAW) from
SciLifeLab. We wanted to test a realistic workload, which works on
sensitive data. However, the small sample we used is on non-sensitive
data. This test is used as a placeholder for other workflow working on
sensitive data, as in Mosler.

The workflow runs using nextflow. We ran it on a small non-sensitive
data sample, and recorded the elapsed time, for each partition.

`nextflow run MultiFQtoVC.nf -c <slurm_partition>.config --sample <sample.tsv>`

The results are as follows:

| Partition     | Elapsed Time   |
| ------------- |:-------------- |
| mm            | [](results/CAW/timeline/mm.html)                 |
| mm2-epouta1   | [23m 1s](results/CAW/timeline/mm2-epouta1.html)  |
| mm1-epouta2   | [22m 53s](results/CAW/timeline/mm1-epouta2.html) |
| epouta        | [15m 28s](results/CAW/timeline/epouta.html) &#9754;     |
| epouta1-mm2   | [23m 32s](results/CAW/timeline/epouta1-mm2.html) |
| epouta2-mm1   | [22m 24s](results/CAW/timeline/epouta2-mm1.html)        |
| milou         | [](results/CAW/timeline/milou.html)              |

# Whole Genome Sequencing Structural Variation Pipeline

Following the same procedure as the previous experiment, using the
same partitions, we ran the
[Whole Genome Sequencing Structural Variation Pipeline](https://github.com/NBISweden/wgs-structvar)
(WGS) from [NBIS](http://www.nbis.se). It requires a `bam` file, and we ran the `manta` step on it, using again `nextflow`.

`nextflow run main.nf --bam <bamfile.bam> --steps manta`

The results are as follows:

| Partition     | Elapsed Time   |
| ------------- |:-------------- |
| mm            | [9m 42s](results/CAW/timeline/mm.html)          |
| mm2-epouta1   | [9m 11s](results/CAW/timeline/mm2-epouta1.html) |
| mm1-epouta2   | [9m 41s](results/CAW/timeline/mm1-epouta2.html) |
| epouta        | [11m 12s](results/CAW/timeline/epouta.html) &#9754; |
| epouta1-mm2   | [9m 40s](results/CAW/timeline/epouta1-mm2.html) |
| epouta2-mm1   | [9m 11s](results/CAW/timeline/epouta2-mm1.html) |
| milou         | [](results/CAW/timeline/milou.html)             |

# NFS stress test

Finally, we stress-tested the network file system (NFS) by writing
files from the compute nodes onto an NFS-shared location, using
[sob](https://www.pdc.kth.se/~pek/sob).


# Conclusions

* The first compute node on the slurm partition matters.
* NFS is a real bottleneck and should be avoided.

# Suggestions for Future Work

* Tweak NFS
* Use a cinder volume and not a ephemeral disk (ie not some libvirt file).
* Tweak the TCP settings in the Kernel
