# CAW
git clone https://github.com/SciLifeLab/CAW CAW
nextflow run CAW/main.nf -c <partition.config>
                         --sample <sample.tsv>
# WGS
git clone https://github.com/NBISweden/wgs-structvar WGS
nextflow run WGS/main.nf --bam <bamfile.bam>
                         --steps manta
