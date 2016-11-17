# Successful demonstration of cross-border use of secure cloud

When a cluster runs at full capacity, all the newly scheduled jobs
have to wait. In case this happens often, it is necessary to scale up
the infrastructure for more computations and more data transfers. To
this end, we can of course buy more hardware, ie, more compute nodes,
more disks and more network switches. Alternatively, and this is the
solution we present here, we can ask other clusters if they have
available resources that we could "borrow for a while".

An immediate issue with such a solution is whether a connection across
borders is even feasible, or if there is a penalizing latency. We can
imagine the scenario where computations happen in one country, while
the data is located in another country. It’s worth mentioning that
this work focused on technical aspects and did not take up legal
matters related to the transfer of sensitive data between
countries. That topic is left for further work in
the [Tryggve project](https://wiki.neic.no/wiki/Tryggve).

In order to test the connection between countries, we built a
temporary cloud cluster in Sweden, called Knox, and connected it to
the resources of ePouta, a secure cloud cluster in Finland. The
desired outcome is that the jobs would not know whether they are
scheduled in Finland or Sweden.

Between Knox and ePouta, we installed a fiber link with a dedicated
network with a capacity of 1GB/s. Note that the link is shared by
other machines, but our network is not, ie. only the set of virtual
machines that we booted on both Knox and ePouta are connected
transparently to that same network.

We were interested in running realistic workflows. We choose to run
the [Cancer Analysis Workflow](https://github.com/SciLifeLab/CAW)
(CAW) from SciLifeLab and the [Whole Genome Sequencing Structural
Variation Pipeline](https://github.com/NBISweden/wgs-structvar) (WGS)
from [NBIS](http://www.nbis.se) as a first step. The results were
surprising: we did not detect any significant slowdown when using
resources from either clusters.

We suspected that disk access or even the network itself would be a
bottleneck in this setup. So, as a second step, we stress-tested both
aspects and noticed even more surprising results: the disk accesses
are not slower at all, and the link can be used almost to 100%!

In other words, computations and tests do not notice whether they are
performed in Finland or in Sweden. Computations were actually even
faster running in Finland, since the hardware in ePouta is better than
the one in Knox. It is probably possible to fine-tune the settings to
get even further performance and a seamless connection.  This is a
very positive outcome as we can now carry on with workflows dealing
with sensitive data. You can refer
the [NBIS GitHub repository](https://github.com/NBISweden/Knox-ePouta)
for further information, or
see
[an informal presentation](https://NBISweden.github.io/Knox-ePouta/informal/).
