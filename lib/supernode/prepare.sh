##############################################################
# SLURM
yum -y install munge munge-devel munge-libs rpm-build openssl openssl-devel pam-devel numactl numactl-devel hwloc hwloc-devel lua lua-devel readline-devel rrdtool-devel ncurses-devel man2html libibmad libibumad perl-ExtUtils-MakeMaker

SLURM_VERSION=16.05.4
#if [ ! -f slurm-${SLURM_VERSION}.tar.bz2 ]; then
if [ ! -f /root/rpmbuild/RPMS/x86_64/slurm-${SLURM_VERSION}-1.el7.centos.x86_64.rpm ]; then
    SLURM_MD5=76bb02f8f0c591edf23e323873cd50ec
    curl -OL http://www.schedmd.com/download/latest/slurm-${SLURM_VERSION}.tar.bz2
    SLURM_MD5_DL=$(md5sum slurm-${SLURM_VERSION}.tar.bz2)
    [ "$SLURM_MD5" != "${SLURM_MD5_DL%% *}" ] && exit 1
    #tar xjvf slurm-${SLURM_VERSION}.tar.bz2
    rpmbuild -ta slurm-${SLURM_VERSION}.tar.bz2
fi
rsync /root/rpmbuild/RPMS/x86_64/slurm*-${SLURM_VERSION}-1.el7.centos.x86_64.rpm ${NFS_LOCATION}/.
yum -y --nogpgcheck reinstall ${NFS_LOCATION}/slurm*-${SLURM_VERSION}-1.el7.centos.x86_64.rpm

# Munge
/usr/sbin/create-munge-key -f # create using /dev/urandom
