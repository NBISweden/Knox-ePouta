# -*-sh-*-

set -v

echo "Timezone configuration"
echo 'Europe/Stockholm' > /etc/timezone

echo "Proxy configuration"
if grep -q 'proxy=.*' /etc/yum.conf; then
    sed -i 's/proxy=.*/proxy=http:\/\/130.238.7.178:3128\//g' /etc/yum.conf
else
    echo 'proxy=http://130.238.7.178:3128' >> /etc/yum.conf
fi

echo "EPEL repo"
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm

echo "Packages we always want"
{ PACKAGES=lsof strace jq tcpdump
  yum -y install $PACKAGES
}

echo "Upgrade system"
yum upgrade

