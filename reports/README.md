# Tryggve Report on the Knox-ePouta connection

This document describes, given the [network settings](./docs.md) of
the Knox-Epouta connection, how we tested the limitations of a system,
in case some of the compute nodes are distributed accross the nordic
countries.

We sat up a test project that runs on Knox (in Sweden), and uses
Epouta's virtual machines (VMs in Finland) to extend the list of
compute nodes. 

The two workflows we tested already run on `milou` at Uppmax, and
therefore use `slurm`. We instantiated 3 compute nodes on Knox and 3
in Epouta. After we installed all the dependencies for those workflows
on the compute nodes (tricky task), we distributed the compute nodes
in slurm partitions as follows.

| Partition     | #nodes in Knox | #nodes in Epouta | Notes |
|:------------- |:--------------:|:----------------:|:----- |
| knox          | 3              | 0                |       |
| knox2-epouta1 | 2              | 1                |       |
| knox1-epouta2 | 1              | 2                |       |
| epouta        | 0              | 3                |       |
| epouta1-knox2 * | 1              | 2                | epouta nodes first in the slurm listing |
| epouta2-knox1 * | 2              | 1                | epouta nodes first in the slurm listing |

Moreover, when a task from the workflow only requires one node, we
were interested in finding out if the first node on the slurm
partition matters (marked with * in the above table).


# Cancer Analysis Workflow

The first test is the
[Cancer Analysis Workflow](https://github.com/SciLifeLab/CAW) from
SciLifeLab. We wanted to test a realistic workload, which works on
sensitive data. However, the small sample we used is on non-sensitive
data. This test is used as a placeholder for other workflow working on
sensitive data, as in Mosler.

The workflow runs using nextflow. We ran it on a small non-sensitive
data sample, and recorded the elapsed time, for each partition.

`nextflow run main.nf -c <slurm_partition>.config --sample <sample.tsv>`

The results are as follows:

| Partition     | Elapsed Time   |
| ------------- |:-------------- |
| knox            | [23m 58s](results/CAW/timeline/knox.html)          |
| knox2-epouta1   | [23m 27s](results/CAW/timeline/knox2-epouta1.html) |
| knox1-epouta2   | [22m 55s](results/CAW/timeline/knox1-epouta2.html) |
| epouta        | [15m 32s](results/CAW/timeline/epouta.html) &nbsp;&#9754; |
| epouta1-knox2   | [17m 28s](results/CAW/timeline/epouta1-knox2.html) |
| epouta2-knox1   | [15m 27s](results/CAW/timeline/epouta2-knox1.html) |

> Conclusion: Since we know that the node in Epouta are technically
> superior to the ones in Knox (ie, better hardware), we can observe
> that the epouta-knox connection does not influence much the results
> and that the network file system (NFS) seems to hold the load

# Whole Genome Sequencing Structural Variation Pipeline

Following the same procedure as the previous experiment, using the
same partitions, we ran the
[Whole Genome Sequencing Structural Variation Pipeline](https://github.com/NBISweden/wgs-structvar)
(WGS) from [NBIS](http://www.nbis.se). It requires a `bam` file, and we ran the `manta` step on it, using again `nextflow`.

`nextflow run main.nf --bam <bamfile.bam> --steps manta`

The results are as follows:

| Partition     | Elapsed Time   |
| ------------- |:-------------- |
| knox            | [8m 40s](results/CAW/timeline/knox.html)          |
| knox2-epouta1   | [9m 43s](results/CAW/timeline/knox2-epouta1.html) |
| knox1-epouta2   | [9m 42s](results/CAW/timeline/knox1-epouta2.html) |
| epouta        | [10m 14s](results/CAW/timeline/epouta.html) &nbsp;&#9754; |
| epouta1-knox2   | [11m 11s](results/CAW/timeline/epouta1-knox2.html) &nbsp;&#9754; |
| epouta2-knox1   | [11m 13s](results/CAW/timeline/epouta2-knox1.html) &nbsp;&#9754; |

> Conclusion: As better hardware, we expected the pipeline to run
> slightly faster on Epouta than it does on Knox. We can observe
> something a bit different: It is slightly slower when Epouta nodes
> are involved. However, the difference is not significant. The
> network file system (NFS) seems to still hold the load.

# NFS stress test

We suspected the network file system (NFS) to be a bottleneck in the
previous workflows, since they require a lot of disk access (and
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


We ran those tests using
[a script that simply connects via `ssh`](../experiments/profiles/supernode/files/run-SOB.sh) to
the VMs (in the specified order) and runs a `sob` command.

We get the following results:

---
| Test | `knox1` | `knox2` | `knox3` |
| ----:|:-----------|:-----------|:-----------|
| 1 | Write: 212s (48.368 MB/s)<br>Read: 166s (61.830 MB/s) | Write: 487s for (21.040 MB/s)<br>Read: 219s (46.657 MB/s) | Write: 492s (20.803 MB/s)<br>Read: 208s (49.290 MB/s) |
| 2 | Write: 55s (9.020 MB/s) | Write: 60s (8.369 MB/s) | Wrote: 60s (8.305 MB/s) |
| 3 | Write: 204s (31.305 MB/s) | Write: 237s (26.964 MB/s) | Write: 243s (26.385 MB/s) |
| 4 | Write: 26s (38.689 MB/s)<br>Read: 0.307s (3330.527 MB/s) | Write: 39s (26.332 MB/s)<br>Read: 0.3s (3379.480 MB/s) | Write: 37s (27.764 MB/s)<br>Read: 0.3s (3703.682 MB/s) |

---
| Test | `epouta3` | `epouta2` | `epouta1` |
| ----:|:-----------|:-----------|:-----------|
| 1 | Write: 527s (19.429 MB/s)<br>Read: 217s (47.104 MB/s) | Write: 399s (25.660 MB/s)<br>Read: 300s (34.103 MB/s) | Write: 363s (28.231 MB/s)<br>Read: 287s (35.631 MB/s) |
| 2 | Write: 79s (6.296 MB/s) | Write: 72s (6.912 MB/s) | Write: 75s (6.661 MB/s) |
| 3 | Write: 267s (23.973 MB/s) | Write: 259s (24.752 MB/s) | Write: 267s (23.963 MB/s) |
| 4 | Write: 31s (33.389 MB/s)<br>Read: 0.4s (2583.793 MB/s) | Write: 38s (26.868 MB/s)<br>Read: 0.3 s (3702.660 MB/s) | Write: 34s (29.761 MB/s)<br>Read: 0.3s (4053.569 MB/s) |


---
| Test | `knox1` | `epouta1` | `epouta2` |
| ----:|:-----------|:-----------|:-----------|
| 1 | Write: 315s (32.545 MB/s)<br>Read: 268s (38.155 MB/s) | Write: 529s (19.348 MB/s)<br>Read: 226s (45.351 MB/s) | Write: 449s (22.808 MB/s)<br>Read: 271s (37.824 MB/s) |
| 2 | Write: 50s (9.920 MB/s) | Write: 77s (6.519 MB/s) | Write: 75s (6.706 MB/s) |
| 3 | Write: 193s (33.153 MB/s) | Write: 250s (25.591 MB/s) | Write: 247s (25.883 MB/s) |
| 4 | Write: 18s (57.380 MB/s)<br>Read: 0.3s (3357.815 MB/s) | Write: 37s (27.616 MB/s)<br>Read: 0.3s (3758.074 MB/s) | Write: 35s (28.889 MB/s)<br>Read: 0.2s (4132.128 MB/s) |


---
| Test | `knox3` | `knox2` | `epouta1`  |
| ----:|:-----------|:-----------|:-----------|
| 1 | Write: 317s (32.265 MB/s)<br>Read: 227s (45.100 MB/s) | Write: 301s (34.073 MB/s)<br>Read: 236s (43.432 MB/s) | Write: 695s (14.726 MB/s)<br>Read: 104s (98.009 MB/s) |
| 2 | Write: 62s (8.100 MB/s) | Write: 62s (8.095 MB/s) | Write: 81s (6.165 MB/s) | 
| 3 | Write: 241s (26.509 MB/s) | Write: 244s (26.174 MB/s) | Write: 317s (20.208 MB/s) | 
| 4 | Write: 29s (35.531 MB/s)<br>Read: 0.3s (3752.689 MB/s) | Write: 30s (33.863 MB/s)<br>Read: 0.3s (3347.075 MB/s) | Write: 42s (24.417 MB/s)<br>Read: 0.3s (3372.855 MB/s) |

---
| Test | `epouta3` | `epouta1` | `knox2`  |
| ----:|:-----------|:-----------|:-----------|
| 1 | Write: 529s (19.348 MB/s)<br>Read: 211s (48.515 MB/s) | Write: 520s (19.675 MB/s)<br>Read: 220s (46.538 MB/s) | Write: 190s (53.941 MB/s)<br>Read: 169s (60.713 MB/s) |
| 2 | Write: 75s (6.623 MB/s) | Write: 75s (6.670 MB/s) | Write: 56s (8.984 MB/s) |
| 3 | Write: 296s (21.604 MB/s) | Write: 303s (21.087 MB/s) | Write: 202s (31.655 MB/s) | 
| 4 | Write: 39s (26.079 MB/s)<br>Read: 0.3s (2936.802 MB/s) | Write: 39s (26.013 MB/s)<br>Read: 0.2s (4486.861 MB/s) | Write: 24s (43.204 MB/s)<br>Read: 0.3 s (3419.887 MB/s) |

---
Partial conclusions:

> There is a price to pay if we stress the NFS server with many files,
> either with big files or with many small files.  However, if we do
> not read/write so many, or stay within the memory size, the NFS
> server seems to hold the load and not penalize too much.



# Testing the 1GB-link

Finally, we test the network link between the VMs, and especially the
link between the VMs in Epouta and the ones on Knox.

The first test consists in opening 10 connections between `epouta1`
and `knox1` and holding them during 60 seconds. One machine acts as
the server, and the other one connects to it, as a sender as well as a
receiver. We used `iperf` with the following commands:

	[knox1]$ iperf3 -4 -s # the server
	[epouta1]$ iperf3 -4 -c knox1 -P 10 -t 60 # the 10 connections

The results are surprising: We get near the physical link speed! After
summing the different connections, we reached `941 Mbits/sec` as
sender and `937 Mbits/sec` as receiver. To compare, running the same
test between `knox2` and `knox1`, we get `942 Mbits/sec` as
sender and `938 Mbits/sec` as receiver.

The last test was to connect `epouta1` to `knox1`, `epouta2` to
`knox2` and `epouta3` to `knox3`, using a similar `iperf` test
as above.

	[knox_i_]$ iperf3 -4 -s # a sever
	[epouta_i_]$ iperf3 -4 -c knox_i_ -t 60 # a connection


| Bandwidth            | Sender         | Receiver      |
| --------------------:|:-------------- |:------------- |
| epouta1 <-> knox1 |  275 Mbits/sec | 272 Mbits/sec |
| epouta2 <-> knox2 |  281 Mbits/sec | 278 Mbits/sec |
| epouta3 <-> knox3 |  452 Mbits/sec | 447 Mbits/sec |

So a total of 1008 Mbits/sec as sender and 997 Mbits/sec as receiver.

Note that we get similar speed between `knox1` and `knox2`,
which happen to be scheduled on different physical nodes in Knox.

# Conclusions

* The use of NFS is not necessarily a bottleneck: if the workflows do
  not write big files, it should hold the load.
* The VMs' network is smoothly at near link-speed.
* The first compute node on the slurm partition appears to *not*
  matter!
  
> In other words, whether computations are scheduled in Finland or
> Sweden does _not_ seem to matter.

# Suggestions for Future Work

* Tweak NFS to gain even further speed
* Tweak the TCP settings in the Kernel
* Scale up the solution to **many-many-many** nodes in Epouta and some
  nodes in Knox, to see how much the link can be shared.
* Improve disk accesses:
    * Use object storage or
    * Use a cinder volume and not a ephemeral disk (ie the default libvirt file).


