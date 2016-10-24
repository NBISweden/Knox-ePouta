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
| epouta        | [15m 28s](results/CAW/timeline/epouta.html)      |
| epouta1-mm2   | [23m 32s](results/CAW/timeline/epouta1-mm2.html) |
| epouta2-mm1   | [22m 24s](results/CAW/timeline/epouta2-mm1.html) |
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

We suspected the the network file system (NFS) to be the bottleneck in
the previous workflows, since they require a lot of disk access (and
comparatively not so much compute power). So we stress-tested NFS by
writing files from the compute nodes onto an NFS-shared location,
using [sob](https://www.pdc.kth.se/~pek/sob).

We used the following tests

| #    | Test        |
| ----:|:----------- |
| 1 | Write a 24GB file in chunks of 8MB. Basic test of write I/O bandwidth. For this kind of test it is important that the file is substantially larger than the main memory of the machine. If the file is 2GB and main memory is 1GB then up to 50% of the file could be cached by the operating system and the reported write bandwidth would be much higher than what the disk+filesystem could actually provide. <br><br>**Command:** `sob -rw -b 8m -s 10g` |
| 2 | Writing 500 files of 1 MB, spread out in 10 directories <br><br>**Command:** `sob -w -b 64k -s 1m -n 500 -o 50` |
| 3 | Write 50 128MB files (6.4GB) with a block size of 64kB, then read random files among these 5000 times. A good way to test random access and mask buffer cache effects (provided the sum size of all the files is much larger than main memory). <br><br>**Command:**  `sob -w -R 5000 -n 50 -s 128m -b 64k` |
| 4 | Read and write 1 file of 1 GB. Is it cached in mem? <br><br>**Command:**  `sob -rw -b 128k -s 1g` | 


# Testing the 1GB-link

Finally, we test the network between the VMs, and especially the link between the VMs in Epouta and the ones on Knox.

The first test consists in opening 10 connections between `epouta1`
and `compute1` and holding them during 60 seconds. We used
`iperf` with the following commands:

	[compute1]$ iperf3 -4 -s # the server
	[epouta1]$ iperf3 -4 -c compute1 -P 10 -t 60 # the 10 connections

The results are surprising: We get near the link speed! After summing
the different connections, we reached `941 Mbits/sec` as sender and
`937 Mbits/sec` as receiver. To compare, running the same test
between compute2 and compute1, we get `942 Mbits/sec` as sender and
`938 Mbits/sec` as receiver.

The last test was to connect `epouta1` to `compute1`, `epouta2` to
`compute2` and `epouta3` to `compute3`, using a similar `iperf` test
as above.

	[compute_i_]$ iperf3 -4 -s # a sever
	[epouta_i_]$ iperf3 -4 -c compute_i_ -t 60 # a connection


| Bandwidth            | Sender         | Receiver      |
| --------------------:|:-------------- |:------------- |
| epouta1 <-> compute1 |  275 Mbits/sec | 272 Mbits/sec |
| epouta2 <-> compute2 |  281 Mbits/sec | 278 Mbits/sec |
| epouta3 <-> compute3 |  452 Mbits/sec | 447 Mbits/sec |

So a total of 1008 Mbits/sec as sender and 997 Mbits/sec as receiver.

Note that we get similar speed between `compute1` and `compute2`,
which happens to be scheduled on different physical nodes in Knox.

# Conclusions

* The first compute node on the slurm partition does *not* matters!
* The use of NFS is a bottleneck, but if the workflows do not write
  big file, it should hold the load.

# Suggestions for Future Work

* Tweak NFS to gain even further speed
* Use a cinder volume and not a ephemeral disk (ie not some libvirt file).
* Tweak the TCP settings in the Kernel


