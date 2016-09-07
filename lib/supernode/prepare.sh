##############################################################
# Gradle
GRADLE_VERSION=2.13
if [ ! -d gradle-${GRADLE_VERSION} ]; then
    rm -rf gradle-${GRADLE_VERSION}-bin.zip
    curl -o gradle-${GRADLE_VERSION}-bin.zip -L https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
    unzip gradle-${GRADLE_VERSION}-bin.zip
fi
export GRADLE_HOME=$(pwd)/gradle-${GRADLE_VERSION}
[[ "$PATH" =~ "${GRADLE_HOME}/bin" ]] || export PATH=${GRADLE_HOME}/bin:$PATH

# Adding settings for HTTP and HTTPS proxy
mkdir -p ~/.gradle
[ -f ~/.gradle/gradle.properties ] && sed -i -e '/systemProp\.https\?\.proxy/ d' ~/.gradle/gradle.properties
echo "systemProp.http.proxyHost=uu_proxy" >> ~/.gradle/gradle.properties
echo "systemProp.http.proxyPort=3128" >> ~/.gradle/gradle.properties
echo "systemProp.https.proxyHost=uu_proxy" >> ~/.gradle/gradle.properties
echo "systemProp.https.proxyPort=3128" >> ~/.gradle/gradle.properties
echo 'systemProp.http.nonProxyHosts="uu_proxy|localhost"' >> ~/.gradle/gradle.properties

##############################################################
# Picard
# See: https://github.com/broadinstitute/picard
[ ! -d picard ] && git clone https://github.com/broadinstitute/picard.git
pushd picard
git pull # to update
# Gradle is in the PATH. See above.
gradle shadowJar
popd

##############################################################
# GIT LFS as RPM
if yum list installed | grep -q git-lfs; then : ; else
    curl -o git-lfs-1.4.1-1.el7.x86_64.rpm -L https://packagecloud.io/github/git-lfs/packages/el/7/git-lfs-1.4.1-1.el7.x86_64.rpm/download
    yum -y install git-lfs-1.4.1-1.el7.x86_64.rpm
fi

##############################################################
# GATK
# See: https://software.broadinstitute.org/gatk/
# and: https://github.com/broadinstitute/gatk
[ ! -d gatk ] && git clone https://github.com/broadinstitute/gatk.git
pushd gatk
git pull # to update
git lfs install
git lfs pull
gradle installAll
# gradle localJar
popd


##############################################################
# SnpEff
# See: http://snpeff.sourceforge.net/protocol.html
if [ ! -d snpEff ]; then
    curl -OL http://sourceforge.net/projects/snpeff/files/snpEff_latest_core.zip
    unzip snpEff_latest_core.zip
    pushd snpEff
    java -jar snpEff.jar download -v GRCh37.75
    popd
fi

##############################################################
# MutEct
# See: https://www.broadinstitute.org/cancer/cga/mutect

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
