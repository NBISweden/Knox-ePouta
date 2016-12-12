# CAW
nextflow run main.nf -c <partition.config> --sample <sample.tsv>
# WGS
nextflow run main.nf --bam <bamfile.bam> --steps manta
